Shader "Benchmark/CROP"
{
    Properties { _Color ("Color", Color) = (1, 0.85, 0.4, 0.5) }
    SubShader
    {
        Pass
        {
            Cull Off
            ZWrite Off
            ZTest Always
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            float4 _Color;
            struct Attributes { uint vertexID : SV_VertexID; };
            struct Varyings { float4 positionCS : SV_POSITION; };

            Varyings Vert(Attributes IN)
            {
                Varyings OUT;
                uint local = IN.vertexID % 3;
                float2 pos = local == 0 ? float2(-1, -1) : local == 1 ? float2(3, -1) : float2(-1, 3);
                OUT.positionCS = float4(pos, 0, 1);
                return OUT;
            }

            half4 Frag(Varyings IN) : SV_Target
            {
                return _Color;
            }
            ENDHLSL
        }
    }
}
