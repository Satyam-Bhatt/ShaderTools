Shader "Benchmark/ZROP"
{
    SubShader
    {
        Pass
        {
            Cull Off
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile _EARLYZ _LATEZ

            struct Attributes { uint vertexID : SV_VertexID; };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            Varyings Vert(Attributes IN)
            {
                Varyings OUT;
                // one full-screen-covering triangle per draw call
                uint local = IN.vertexID % 3;
                float2 pos = local == 0 ? float2(-1, -1) : local == 1 ? float2(3, -1) : float2(-1, 3);
                OUT.positionCS = float4(pos, 0, 1);
                OUT.uv = pos * 0.5 + 0.5;
                return OUT;
            }

        #if defined(_LATEZ)
            // Writing SV_Depth forces the GPU to run the fragment shader
            // BEFORE it knows the depth value, so the depth test can't
            // happen early -- this is the "LateZ" path.
            void Frag(Varyings IN, out half4 color : SV_Target, out float depth : SV_Depth)
            {
                color = 1;
                depth = frac(sin(dot(IN.uv, float2(12.9898, 78.233))) * 43758.5453);
            }
        #else
            // No depth output override -> hardware can run the depth test
            // before invoking this shader at all ("EarlyZ").
            half4 Frag(Varyings IN) : SV_Target
            {
                return 1;
            }
        #endif
            ENDHLSL
        }
    }
}
