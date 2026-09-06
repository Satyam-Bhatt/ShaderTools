Shader "Benchmark/VAF"
{
    SubShader
    {
        Pass
        {
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            struct Attributes { float3 positionOS : POSITION; };
            struct Varyings { float4 positionCS : SV_POSITION; };

            Varyings Vert(Attributes IN)
            {
                Varyings OUT;
                // Push every vertex far outside the frustum so rasterization,
                // ZROP and CROP do essentially zero work -- isolates the cost
                // of fetching this vertex's attributes from VRAM.
                OUT.positionCS = float4(IN.positionOS.x * 1000.0 + 1000.0, IN.positionOS.y, 0, 1);
                return OUT;
            }

            half4 Frag(Varyings IN) : SV_Target { return 1; }
            ENDHLSL
        }
    }
}
