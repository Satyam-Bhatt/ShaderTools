#ifndef SSR_RAYMARCH_INCLUDED
#define SSR_RAYMARCH_INCLUDED

// Include in a URP Renderer Feature full-screen pass, after:
// #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
// #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
//
// Requires _CameraOpaqueTexture (opaque color, "Opaque Texture" enabled in URP asset)
// and scene depth available via SampleSceneDepth().

TEXTURE2D_X(_CameraOpaqueTexture);
SAMPLER(sampler_CameraOpaqueTexture);

float _SSR_MaxDistance;   // view-space units the ray may travel
float _SSR_Thickness;     // acceptance thickness for a hit (view-space units)
float _SSR_StepStride;    // view-space distance per march step
int   _SSR_MaxSteps;      // loop iteration cap
float _SSR_EdgeFade;      // scale for screen-edge fade

// ---- Shared helpers ----

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

// ---- Loop-based march ----

half4 ScreenSpaceReflection_Loop(float2 screenUV, float3 viewNormal)
{
    float rawDepth = SampleSceneDepth(screenUV);
    if (rawDepth <= 0.0001) return half4(0, 0, 0, 0);

    float3 viewPos    = ReconstructViewPos(screenUV, rawDepth);
    float3 viewDir    = normalize(viewPos);
    float3 reflectDir = normalize(reflect(viewDir, viewNormal));

    // Reflection pointing back toward camera plane -> no valid trace
    if (reflectDir.z >= 0) return half4(0, 0, 0, 0);

    float3 rayPos  = viewPos;
    float3 rayStep = reflectDir * _SSR_StepStride;

    float2 hitUV = 0;
    bool   hit   = false;

    [loop]
    for (int i = 0; i < _SSR_MaxSteps; i++)
    {
        rayPos += rayStep;

        if (length(rayPos - viewPos) > _SSR_MaxDistance)
            break;

        float2 sampleUV = ViewToScreenUV(rayPos);
        if (any(sampleUV < 0) || any(sampleUV > 1))
            break;

        float  sceneRawDepth = SampleSceneDepth(sampleUV);
        float3 sceneViewPos  = ReconstructViewPos(sampleUV, sceneRawDepth);

        // View space looks down -Z; ray "behind" the surface means depthDiff > 0
        float depthDiff = rayPos.z - sceneViewPos.z;

        if (depthDiff > 0 && depthDiff < _SSR_Thickness)
        {
            // Binary search refine between the last two samples
            float3 lo = rayPos - rayStep;
            float3 hi = rayPos;

            [unroll]
            for (int b = 0; b < 5; b++)
            {
                float3 mid    = (lo + hi) * 0.5;
                float2 midUV  = ViewToScreenUV(mid);
                float  midRaw = SampleSceneDepth(midUV);
                float3 midVP  = ReconstructViewPos(midUV, midRaw);

                if (mid.z - midVP.z > 0) hi = mid;
                else                     lo = mid;
            }

            hitUV = ViewToScreenUV(hi);
            hit = true;
            break;
        }
    }

    if (!hit) return half4(0, 0, 0, 0);

    float2 edgeDist = min(hitUV, 1 - hitUV);
    float  edgeFade = saturate(min(edgeDist.x, edgeDist.y) * _SSR_EdgeFade);

    half3 reflColor = SAMPLE_TEXTURE2D_X(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, hitUV).rgb;
    return half4(reflColor, edgeFade);
}

#endif
