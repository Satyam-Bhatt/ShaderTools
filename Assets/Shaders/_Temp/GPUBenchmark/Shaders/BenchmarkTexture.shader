Shader "Benchmark/Texture"
{
    Properties { _MainTex ("Texture", 2D) = "white" {} }
    SubShader
    {
        Pass
        {
            Cull Off ZWrite Off ZTest Always

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma multi_compile _CACHE_HIT _CACHE_MISS
            #include "BenchmarkCommon.hlsl"

            Texture2D _MainTex;
            SamplerState sampler_MainTex;

            half4 Frag(Varyings IN) : SV_Target
            {
                float2 uv = IN.uv;
            #if defined(_CACHE_MISS)
                // per-pixel pseudo-random UV -> scattered texel fetches,
                // defeats the texture cache. Use with a large (e.g. 4K) texture.
                uv = frac(uv * 9973.731 + IN.positionCS.xy * 0.013);
            #endif
                // _CACHE_HIT: fixed/small UV range on a small texture ->
                // near-100% cache hit rate.
                return _MainTex.Sample(sampler_MainTex, uv);
            }
            ENDHLSL
        }
    }
}
