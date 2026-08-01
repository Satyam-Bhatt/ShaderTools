Shader "Custom/FragmentHash"
{
    Properties
    {
        _Iterations ("Iterations", Int) = 64
    }

    SubShader
    {
        Pass
        {
            Cull Off ZWrite Off ZTest Always
            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            //#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                uint vertexID : SV_VertexID;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            int _Iterations;

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                // Generates (-1,-1 || -1,3 || 3,-1)
                OUT.positionCS = float4(
                    (IN.vertexID == 2) ? 3.0 : -1.0,
                    (IN.vertexID == 1) ? 3.0 : -1.0,
                    0, 1);
                // Remaping so that -1,-1 is 0,0 rest can go out. As triangle is bigger coves the entire screen
                OUT.uv = OUT.positionCS.xy * 0.5 + 0.5;
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float x = IN.uv.x + IN.uv.y;
                for (int i = 0; i < _Iterations; i++)
                    x = frac(sin(x * 12.9898) * 43758.5453);
                return x.xxxx;
            }
            ENDHLSL
        }
    }
}
