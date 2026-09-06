Shader "Custom/URP_PlaneSSR"
{
    // Screen-Space Reflection shader for URP, meant for a flat plane (water, floor, mirror-like surface).
    // Requires: URP asset with "Depth Texture" AND "Opaque Texture" enabled
    // (Renderer Data and/or URP Asset settings). Without these two textures this shader has nothing to sample.
    //
    // Two reflection sampling methods are included, toggled with _UseNoLoop:
    //   - Loop method:    per-pixel view-space ray march + binary refine against the depth texture (accurate, costlier).
    //   - No-loop method: single-tap screen-space UV distortion using the (optionally normal-mapped) surface
    //                      normal (cheap, no branching/loop, good for stylized water or mobile).

    Properties
    {
        _BaseColor      ("Base Color (fallback / tint)", Color) = (0.05, 0.08, 0.1, 1)
        _Reflectivity   ("Reflectivity", Range(0,1)) = 0.9
        _FresnelPower   ("Fresnel Power", Range(0.1, 8)) = 3

        [Header(Normal Mapping)]
        _NormalMap      ("Normal Map", 2D) = "bump" {}
        _NormalStrength ("Normal Strength", Range(0, 2)) = 1
        _NormalTiling   ("Normal Tiling", Vector) = (1,1,0,0)

        [Header(Reflection Method)]
        [Toggle(_USE_NOLOOP)] _UseNoLoop ("Use No-Loop (single tap) Method", Float) = 0

        [Header(Loop Ray March Settings)]
        _MaxSteps       ("Ray March Steps", Range(8, 128)) = 48
        _StepSize       ("Ray Step Size (view space)", Range(0.01, 2)) = 0.15
        _Thickness      ("Depth Thickness Tolerance", Range(0.01, 5)) = 0.5
        _MaxDistance    ("Max Reflection Distance", Range(1, 200)) = 50
        _BinarySteps    ("Binary Refine Steps", Range(0, 12)) = 5

        [Header(No Loop Settings)]
        _NoLoopDistance ("No-Loop Sample Distance (view space)", Range(0.1, 50)) = 5

        [Header(Edge Fade)]
        _EdgeFade       ("Screen Edge Fade", Range(0.0, 0.5)) = 0.15
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        LOD 100

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
        ENDHLSL

        Pass
        {
            Name "ForwardSSR"
            Tags { "LightMode"="UniversalForward" }
            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local _USE_NOLOOP
            #pragma target 3.5

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 positionWS  : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float4 tangentWS   : TEXCOORD2; // w = sign
                float2 uv          : TEXCOORD3;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float  _Reflectivity;
                float  _FresnelPower;
                float4 _NormalMap_ST;
                float  _NormalStrength;
                float4 _NormalTiling;
                int    _MaxSteps;
                float  _StepSize;
                float  _Thickness;
                float  _EdgeFade;
                float  _MaxDistance;
                int    _BinarySteps;
                float  _NoLoopDistance;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs vpi = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionHCS = vpi.positionCS;
                OUT.positionWS  = vpi.positionWS;
                OUT.normalWS    = TransformObjectToWorldNormal(IN.normalOS);
                float3 tangentWS = TransformObjectToWorldDir(IN.tangentOS.xyz);
                OUT.tangentWS   = float4(tangentWS, IN.tangentOS.w * GetOddNegativeScale());
                OUT.uv          = IN.uv;
                return OUT;
            }

            // ---------- Method 1: Normal sampling ----------
            // Samples the normal map and blends it (tangent -> world space) with the geometric
            // surface normal, scaled by _NormalStrength. Used to add ripple/detail to the reflection
            // direction for both the loop and no-loop methods below.
            float3 SampleSurfaceNormal(float2 uv, float3 normalWS, float4 tangentWS)
            {
                float2 tiledUV = uv * _NormalTiling.xy + _NormalTiling.zw;
                float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, tiledUV), _NormalStrength);

                float3 bitangentWS = cross(normalWS, tangentWS.xyz) * tangentWS.w;
                float3x3 tangentToWorld = float3x3(tangentWS.xyz, bitangentWS, normalWS);

                // mul with row-major TBN (tangentToWorld rows = basis vectors) -> world space normal
                float3 perturbedWS = normalize(mul(normalTS, tangentToWorld));
                return perturbedWS;
            }

            // Converts a view-space position to a 0..1 screen UV using the projection matrix.
            float2 ViewToScreenUV(float3 viewPos)
            {
                float4 clipPos = mul(UNITY_MATRIX_P, float4(viewPos, 1.0));
                float2 ndc = clipPos.xy / clipPos.w;
                float2 uv = ndc * 0.5 + 0.5;
                #if UNITY_UV_STARTS_AT_TOP
                    uv.y = 1.0 - uv.y;
                #endif
                return uv;
            }

            // Returns linear eye-space depth (positive, distance from camera) stored at screen uv.
            float SceneEyeDepth(float2 uv)
            {
                float raw = SampleSceneDepth(uv);
                return LinearEyeDepth(raw, _ZBufferParams);
            }

            float EdgeFadeAmount(float2 uv)
            {
                float2 edgeDist = min(uv, 1.0 - uv);
                return saturate(min(edgeDist.x, edgeDist.y) / max(_EdgeFade, 1e-4));
            }

            // ---------- Method 2a: Ray-marched reflection (loop) ----------
            // Marches a ray in view space along the reflection vector, sampling the depth texture each
            // step to find an intersection with existing scene geometry, then binary-search refines it.
            half3 SampleReflectionLoop(float3 viewPosOrigin, float3 reflectDirVS, out float fadeOut)
            {
                float3 rayPos = viewPosOrigin;
                float3 rayStep = reflectDirVS * _StepSize;
                float3 prevRayPos = rayPos;

                bool hit = false;
                float2 hitUV = 0;

                [loop]
                for (int i = 0; i < _MaxSteps; i++)
                {
                    prevRayPos = rayPos;
                    rayPos += rayStep;

                    if (length(rayPos - viewPosOrigin) > _MaxDistance)
                        break;

                    float2 uv = ViewToScreenUV(rayPos);
                    if (uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1)
                        break;

                    float sceneDepth = SceneEyeDepth(uv);
                    float rayDepth = -rayPos.z;
                    float diff = rayDepth - sceneDepth;

                    if (diff > 0 && diff < _Thickness)
                    {
                        hit = true;
                        hitUV = uv;
                        break;
                    }
                }

                if (hit)
                {
                    float3 a = prevRayPos;
                    float3 b = rayPos;

                    [loop]
                    for (int j = 0; j < _BinarySteps; j++)
                    {
                        float3 mid = lerp(a, b, 0.5);
                        float2 uv = ViewToScreenUV(mid);
                        float sceneDepth = SceneEyeDepth(uv);
                        float rayDepth = -mid.z;
                        float diff = rayDepth - sceneDepth;

                        if (diff > 0 && diff < _Thickness)
                        {
                            b = mid;
                            hitUV = uv;
                        }
                        else
                        {
                            a = mid;
                        }
                    }

                    fadeOut = EdgeFadeAmount(hitUV);
                    return SampleSceneColor(hitUV);
                }

                fadeOut = 0;
                return _BaseColor.rgb;
            }

            // ---------- Method 2b: No-loop single-tap reflection ----------
            // No ray march: steps ONE fixed distance (_NoLoopDistance) along the actual reflection
            // vector in view space, projects that single point to a screen UV, and takes one texture
            // fetch there. Because it moves along the real reflect direction (not just the normal's
            // slope), it can land on genuinely different screen content (sky, other objects) instead of
            // resampling the same flat surface. Trade-off: with no depth comparison, it doesn't check
            // that anything is actually there, so it can "see through" objects or drift when the fixed
            // distance doesn't match the real scene depth. Cheap and stylized, not geometrically correct.
            half3 SampleReflectionNoLoop(float3 viewPosOrigin, float3 reflectDirVS, out float fadeOut)
            {
                float3 samplePos = viewPosOrigin + reflectDirVS * _NoLoopDistance;
                float2 uv = ViewToScreenUV(samplePos);

                if (uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1)
                {
                    fadeOut = 0;
                    return _BaseColor.rgb;
                }

                fadeOut = EdgeFadeAmount(uv);
                return SampleSceneColor(uv);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float3 geoNormalWS = normalize(IN.normalWS);
                float3 normalWS = SampleSurfaceNormal(IN.uv, geoNormalWS, IN.tangentWS);

                float3 viewPosOrigin = TransformWorldToView(IN.positionWS);
                float3 viewNormal    = normalize(TransformWorldToViewDir(normalWS, true));
                float3 viewDirIn     = normalize(viewPosOrigin);
                float3 reflectDirVS  = normalize(reflect(viewDirIn, viewNormal));

                half3 reflectionColor;
                float fade;

                #if defined(_USE_NOLOOP)
                    reflectionColor = SampleReflectionNoLoop(viewPosOrigin, reflectDirVS, fade);
                #else
                    reflectionColor = SampleReflectionLoop(viewPosOrigin, reflectDirVS, fade);
                #endif

                float NdotV = saturate(dot(normalWS, normalize(GetWorldSpaceViewDir(IN.positionWS))));
                float fresnel = pow(1.0 - NdotV, _FresnelPower);
                float reflectAmount = saturate(_Reflectivity * lerp(0.2, 1.0, fresnel));

                half3 finalColor = lerp(_BaseColor.rgb, reflectionColor, reflectAmount * fade);
                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Lit"
}
