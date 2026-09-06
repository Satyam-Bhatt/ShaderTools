Shader "Benchmark/VPC"
{
    SubShader
    {
        Pass
        {
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            struct Attributes { uint vertexID : SV_VertexID; };
            struct Varyings { float4 positionCS : SV_POSITION; };

            // cheap integer hash to scatter each triangle across the screen
            float2 Hash(uint n)
            {
                n = (n << 13u) ^ n;
                n = n * (n * n * 15731u + 789221u) + 1376312589u;
                float x = (n & 0x7fffffffu) / float(0x7fffffff);
                n = n * 747796405u + 2891336453u;
                float y = (n & 0x7fffffffu) / float(0x7fffffff);
                return float2(x, y);
            }

            Varyings Vert(Attributes IN)
            {
                Varyings OUT;
                uint triID = IN.vertexID / 3;
                uint local = IN.vertexID % 3;

                float2 center = Hash(triID) * 2.0 - 1.0;
                // sub-pixel triangle: no vertex buffer fetch cost (position is
                // generated purely from SV_VertexID), and it's small enough
                // that most triangles get clipped/culled before rasterizing --
                // isolates viewport transform + clip + cull + setup cost.
                float2 offset = local == 0 ? float2(0, 0.00005) :
                                 local == 1 ? float2(0.00005, -0.00005) :
                                              float2(-0.00005, -0.00005);
                OUT.positionCS = float4(center + offset, 0, 1);
                return OUT;
            }

            half4 Frag(Varyings IN) : SV_Target { return 1; }
            ENDHLSL
        }
    }
}
