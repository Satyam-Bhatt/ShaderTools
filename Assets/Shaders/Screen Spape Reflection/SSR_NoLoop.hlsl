#ifndef SSR_NOLOOP_INCLUDED
#define SSR_NOLOOP_INCLUDED

// Loop-free SSR: the march is expanded at preprocessor time (no for/while in
// source), and hit selection is branchless (step/lerp/max instead of if/break).
// Trade-off vs the loop version: every step always executes (no early-out),
// so cost per pixel is constant regardless of whether the ray hits early —
// good for avoiding divergence, worse if most pixels miss on step 1.

TEXTURE2D_X(_CameraOpaqueTexture);
SAMPLER(sampler_CameraOpaqueTexture);

float _SSR_Thickness;
float _SSR_StepStride;   // base stride; actual step distance grows exponentially
float _SSR_EdgeFade;

#define SSR_STEPS 16

// ---- Shared helpers (identical to the loop version) ----

float3 ReconstructViewPos(float2 uv, float rawDepth)
{
    float4 clipPos = float4(uv * 2.0 - 1.0, rawDepth, 1.0);
#if UNITY_UV_STARTS_AT_TOP
    clipPos.y = -clipPos.y;
#endif
    float4 viewPos = mul(unity_CameraInvProjection, clipPos);
    return viewPos.xyz / viewPos.w;
}

float2 ViewToScreenUV(float3 viewPos)
{
    float4 clipPos = mul(unity_CameraProjection, float4(viewPos, 1.0));
    float2 ndc = clipPos.xy / clipPos.w;
    float2 uv = ndc * 0.5 + 0.5;
#if UNITY_UV_STARTS_AT_TOP
    uv.y = 1.0 - uv.y;
#endif
    return uv;
}

// ---- Loop-free march ----

half4 ScreenSpaceReflection_NoLoop(float2 screenUV, float3 viewNormal)
{
    float rawDepth = SampleSceneDepth(screenUV);
    if (rawDepth <= 0.0001) return half4(0, 0, 0, 0);

    float3 viewPos    = ReconstructViewPos(screenUV, rawDepth);
    float3 viewDir    = normalize(viewPos);
    float3 reflectDir = normalize(reflect(viewDir, viewNormal));

    if (reflectDir.z >= 0) return half4(0, 0, 0, 0);

    // Running "best hit so far" state, updated unconditionally every step
    float  closestHitDist = 1e8;
    float2 closestHitUV   = 0;
    float  hitMask        = 0;

    // One step of the march, expanded inline for a fixed exponential distance.
    // idx grows the stride as (2^idx - 1) so 16 steps cover far more ground
    // than 16 fixed-size steps would, without any runtime loop counter.
    #define SSR_STEP(idx)                                                          \
    {                                                                              \
        float travel   = _SSR_StepStride * (exp2((float)(idx)) - 1.0);             \
        float3 rayPos  = viewPos + reflectDir * travel;                            \
        float2 sampleUV = ViewToScreenUV(rayPos);                                  \
        float inBounds  = all(sampleUV >= 0) * all(sampleUV <= 1);                 \
        float sceneRaw  = SampleSceneDepth(sampleUV);                              \
        float3 sceneVP  = ReconstructViewPos(sampleUV, sceneRaw);                  \
        float depthDiff = rayPos.z - sceneVP.z;                                    \
        float isHit     = inBounds * step(0.0, depthDiff) * step(depthDiff, _SSR_Thickness); \
        /* keep the earliest (smallest travel) hit found so far */                 \
        float better       = isHit * step(travel, closestHitDist);                 \
        closestHitDist     = lerp(closestHitDist, travel, better);                 \
        closestHitUV       = lerp(closestHitUV, sampleUV, better);                 \
        hitMask            = max(hitMask, isHit);                                  \
    }

    SSR_STEP(1)  SSR_STEP(2)  SSR_STEP(3)  SSR_STEP(4)
    SSR_STEP(5)  SSR_STEP(6)  SSR_STEP(7)  SSR_STEP(8)
    SSR_STEP(9)  SSR_STEP(10) SSR_STEP(11) SSR_STEP(12)
    SSR_STEP(13) SSR_STEP(14) SSR_STEP(15) SSR_STEP(16)

    #undef SSR_STEP

    if (hitMask < 0.5) return half4(0, 0, 0, 0);

    float2 edgeDist = min(closestHitUV, 1 - closestHitUV);
    float  edgeFade = saturate(min(edgeDist.x, edgeDist.y) * _SSR_EdgeFade);

    half3 reflColor = SAMPLE_TEXTURE2D_X(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, closestHitUV).rgb;
    return half4(reflColor, edgeFade * hitMask);
}

#endif
