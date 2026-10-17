Shader "Custom/ScreenSpaceImplementation_LOOP"
{
    Properties
    {
}
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
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float2 uv : TEXCOORD2;
                float4 tangentWS = TEXCOORD3;
            };

            CBUFFER_START(UnityPerMaterial)
            CBUFFER_END

            // TODO
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

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                // TransformObjectToWorld applies the model matrix
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
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
                // SampleSurfaceNormal builds the final per-pixel normal because
                // SHOULD WE NORMALIZE TANGENT??
                float3 normalWS = SampleSurfaceNormal(IN.uv, geoNormalWS, IN.tangentWS); // What does this do

            }
            ENDHLSL
        }
    }
}
