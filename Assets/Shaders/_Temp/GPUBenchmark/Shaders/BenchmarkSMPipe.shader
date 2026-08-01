Shader "Benchmark/SMPipe"
{
    SubShader
    {
        Pass
        {
            Cull Off ZWrite Off ZTest Always

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile _FP32 _INT32 _SFU
            #include "BenchmarkCommon.hlsl"

            half4 Frag(Varyings IN) : SV_Target
            {
            #if defined(_FP32)
                // pure FP32 multiply-add chain
                float x = IN.uv.x;
                [unroll(64)]
                for (int i = 0; i < 64; i++)
                    x = x * 1.0000123 + 0.0000001 - x * x * 0.0000001;
                return x.xxxx;

            #elif defined(_INT32)
                // pure integer ALU chain (shifts, XOR, multiply)
                uint x = (uint)(IN.uv.x * 4294967295.0);
                [unroll(64)]
                for (int i = 0; i < 64; i++)
                    x = (x ^ (x << 13)) + (x >> 7) * 2654435761u;
                return (x / 4294967295.0).xxxx;

            #else // _SFU: transcendentals route through Special Function Units
                float x = IN.uv.x;
                [unroll(64)]
                for (int i = 0; i < 64; i++)
                    x = rsqrt(abs(sin(x)) + 0.001) * 0.001 + frac(x);
                return x.xxxx;
            #endif
            }
            ENDHLSL
        }
    }
}
