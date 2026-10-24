Shader "Custom/ScreenSpaceImplementation_LOOP"
{
    Properties
    {
        [Header (Normal Mapping)]
        _NormalMap ("Normal Map", 2D) = "bump"{}
        _NormalStrength ("Normal Strength", float) = 1
        _NormalTiling ("Normal Tiling", Vector) = (1,1,0,0)
        
        [Header(Loop Ray March Setting)]
        _MaxSteps ("Max Steps", Range(8,128)) = 48
        _StepSize ("Ray Step Size", Range(0.01, 2)) = 0.15
        _MaxDistance ("Max Reflection Distance", Range(1, 200)) = 50
        _Thickness ("Depth Thickness Tolerance", Range(0.01, 5)) = 0.50
        _BinarySteps ("Binary Refine Steps", Range(0, 12)) = 5

        [Header(EdgeFade)]
        _EdgeFade ("Screen Edge Fade", Range(0,0.5)) = 0.15
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" "Queue" = "Geometry"}

        Pass
        {
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDeptTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclateOpaqueTexure.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 positionWS  : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float2 uv          : TEXCOORD2;
                float4 tangentWS   : TEXCOORD3;
            };

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            CBUFFER_START(UnityPerMaterial)
                float _NormalStrength;
                float4 _NormalTiling;
                float4 _NormalMap_ST;

                int _MaxSteps;
                float _StepSize;
                float _MaxDistance;
                float _Thickness;
                float _BinarySteps;

                float _EdgeFade;
            CBUFFER_END

            // Sample normal texture
            float3 SampleSurfaceNormal(float2 uv, float3 normalWS, float4 tangentWS)
            {
                float2 tiledUV = uv * _NormalTiling.xy + _NormalTiling.zw;
                float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, tiledUV), _NormalStrength);

                float3 bitangentWS = cross(normalWS, tangentWS.xyz) * tangentWS.w;
                float3x3 tangentToWorld = float3x3(tangentWS.xyz, bitangentWS, normalWS); // TBN matrix

                float3 perturbedWS = normalize(mul(normalTS, tangentToWorld));
                return perturbedWS;
            }

            // Converts a view space position to a 0-1 screen uv using projection matrix
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

            // Converts depth value into view space - positive Distance from the camera
            // TODO: Verify the claim
            float SceneEyeDepth(float2 uv)
            {
                float raw = SampleSceneDepth(uv);
                return LinearEyeDepth(raw, _ZBufferParams);
            }
            
            // Fades in towards the center _EdgeFade with edges 0 and center 1
            // Sharp lines at diagonals here x ad y are the same because it doesn't match with the steady gradient of x and y
            float EdgeFadeAmount(float2 uv)
            {
                float2 edgeDist = min(uv, 1 - uv);
                return saturate(min(edgeDist.x, edgeDist.y) / max(_EdgeFade, 1e-4));
            }

            // Basically march the ray and test the Depth (world space)
            // If at any point we march beyond the depth that means we have hit something
            // When we know we have hit something we again march between the prevRayPos and the current ray pos
            // We find the middle point, sample the depth there and then check it with our position and see if we are behind or in front of that depth
            // if we are behind then we move the prevRayPos to the mid and run the loop, if we are ahead then we move the current ray pos to the mid and run the loop
            // This just ensures that we sameple the color from the correct place as we keep on moving the prevRayPos and current ray pos. This also helps us avoid erros especially if our ray steps are quite big
            // Also one thing to keep in mid that we are comparing the depth value at that location with the z value of that vector to see if the vector is behind or ahead of it
            // This happens in View space
            // TODO: Verify this claim and also ask won't some GPU cores get free early and some would run more in this loop case as we break early
            // TODO: Sample the exact point that we get in the first loop
            half3 SampleRedlectionLoop(float3 viewPosOrigin, float3 reflectDirVS, out float fadeOut)
            {
                float3 rayPos = viewPosOrigin;
                float3 rayStep = reflectDirVS * _StepSize;
                float3 prevRayPos = rayPos;

                bool hit = false;
                float2 hitUV = 0;

                // Check if we hit something by marching the ray and testing the depth
                [loop]
                for(int i = 0; i < _MaxSteps; i++)
                {
                    prevRayPos = rayPos;
                    rayPos += rayStep;

                    if(length(rayPos - viewPosOrigin) > _MaxDistance)
                        break;

                    float2 uv = ViewToScreenUV(rayPos); 
                    if (uv.x < 0 || uv.x > 1 || uv.y < 0 || uv.y > 1)
                        break;

                    float sceneDepth = SceneEyeDepth(uv);
                    // To make the value positive as the camera faces in the negative direction we add minus sign to make it positive
                    float rayDepth = -rayPos.z; // TODO: Verify this claim
                    float diff = rayDepth - sceneDepth;

                    if(diff > 0 && diff < _Thickness)
                    {
                        hit = true;
                        hitUV = uv;
                        break;
                    }
                }

                if(hit)
                {
                    float3 a = prevRayPos;
                    float3 b = rayPos;

                    // Check what did we hit and returning the color on the basis of that
                    [loop]
                    for (int j = 0; j < _BinarySteps; j++)
                    {
                        float3 mid = lerp(a, b, 0.5); 
                        float2 uv = ViewToScreenUV(mid);
                        float sceneDepth = SceneEyeDepth(uv);
                        float rayDepth = -mid.z; // Here we are only concerned about the z value
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
                    return SampleSceneColor(hitUV); // TODO: Implement it yourself
                }

                fadeOut = 0;
                return _BaseColor.rgb;
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                // TransformObjectToWorld applies the model matrix
                OUT.positionWS = mul(UNITY_MATRIX_M, float4(IN.positionOS, 1.0)).xyz;
                // TransformObjectToWorldNormal this multiplied it with the Inverse transpose of model matrix (3x3).
                // M = Model || R = Rotation || S = Scale
                // M = RS
                // M^-1 = S^-1 R^-1
                // M^-1 = S^-1 R^T (R is orthogonal so inverse is transpose)
                // M^-T = R S^-1 (The order is restored. Transpose of R^T is R itself. S is a diagonal matrix so transpose doesn't do anything to it)
                // We need the inverse of S matrix as in the case of non uniform scaling - inverse of S gives us the correct scaling which adjusts the normals direction or where is should lean towards. One visualization is that as the plane shrinks - the tangent on that plane shrinks too but the normal increases
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS.xyz);
                OUT.tangentWS.xyz = TransformObjectToWorldDir(IN.tangentOS.xyz);
                // What GetOddNegativeScale does is that is goes and fetches the scale axes of the object. If the object's transform has odd number of negative scale axes (one or three) it returns -1 and if it has 2 or 0 negative scale axes then returns 1
                // It is needed because when someone makes the scale negative then the Geometry flips. As tangents are baked into the mesh but do not change with the tranform. We need to update the tangents so that when we get the bitangent, which is the cross product of normal and the tangent, it points in the right direction. This just flips the tangent when the Geometry is flipped
                // Even number of negative axis like (-1,-1,1) is just a 180 rotation 
                OUT.tangentWS = float4(tangentWS, IN.tangentOS.w * GetOddNegativeScale()); 
                OUT.uv = IN.uv;
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // We didn't normalize earlier as if we would have then after it would have been interpolated in the fragment stage unit vector would have broken.
                // So always renormalize in the fragment Shader
                float3 geoNormalWS = normalize(IN.normalWS); // Why didn't we normalize them earlier
                float4 geoTangentWS = normalize(IN.tangentWS);
                // SampleSurfaceNormal builds the final per-pixel normal from the texture we attached above. We get normal from the texture in tangent space and we convert it into WS by multiplying with TBN matrix
                float3 normalWS = SampleSurfaceNormal(IN.uv, geoNormalWS, geoTangentWS);

                // This makes the camera at origin and the vertex at some position w.r.t camera
                float3 viewPosOrigin = mul(UNITY_MATRIX_V, float4(IN.positionWS, 1.0)).xyz; // TODO: Verify this claim
                float3 viewNormal = normalize(TransformWorldToViewDir(normalWS, true)); // TODO: Why pass true here
                // Direction from camera to the vertex
                float3 viewDirIn = normalize(viewPosOrigin);
                float3 reflectDirVS = normalize(reflec(viewDirIn, viewNormal));
                
                half3 reflectionColor;
                float fade;

                // We pass viewPosOrigin instead of direction as we are going to move in that direction and increment it slowly
                reflectionColor = SampleRedlectionLoop(viewPosOrigin, reflectDirVS, fade); // TODO: Verify this claim

                float NdotV = saturate(dot(normalWS, normalize(GetWorldSpaceViewDir(IN.positionWS))));// TODO: How is this View vector I guess I know but need to think
                // Steeper angle more refleciteve and straight angle then neglegible fresnel. Power just helps us control the tansition
                // TODO: Verify
                float fresnel = pow(1.0 - NdotV, _FresnelPower); 
                // How much we want to reflect as per the angle we looking at
                float reflectAmount = saturate(_Reflectivity * lerp(0.2, 1.0, fresnel));

                // Blend between base color and reflection color on the basis of our looking angle and Fade
                // TODO: Looke once more and test the reflection color separately
                half3 finalColor = lerp(_BaseColor.rgb, reflectionColor, reflectAmount * fade);
                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}
