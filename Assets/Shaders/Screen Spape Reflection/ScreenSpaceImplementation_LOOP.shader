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
                //float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float2 uv : TEXCOORD2;
            };

            CBUFFER_START(UnityPerMaterial)
            CBUFFER_END

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
                // We need the inverse of S matrix as in the case of non uniform scaling - inverse of S gives us the correct scaling which adjusts the normals direction or where is should leand towards
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS.xyz);
                OUT.uv = IN.uv;
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                return color;
            }
            ENDHLSL
        }
    }
}
