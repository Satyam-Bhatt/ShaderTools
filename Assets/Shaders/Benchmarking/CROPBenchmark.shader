Shader "Custom/CROPBenchmark"
{
    Properties
    {
        _Color ("Main Color", Color) = (1, 0.85, 0.4, 0.5)
    }

    SubShader
    {
        Tags { "RenderType" = "Transparent" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Cull Off
            ZWrite Off
            ZTest Always
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            struct Attributes
            {
                uint vertexID : SV_VertexID;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            float4 _Color;

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                // Create full screen triangles and stack one over the other
                OUT.positionCS = float4(
                   (IN.vertexID == 2) ? 3.0 : -1.0,
                   (IN.vertexID == 1) ? 3.0 : -1.0,
                   0, 1);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                return _Color;
            }
            ENDHLSL
        }
    }
}
