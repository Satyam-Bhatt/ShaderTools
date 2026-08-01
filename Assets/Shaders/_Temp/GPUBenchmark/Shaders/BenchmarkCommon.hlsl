#ifndef BENCHMARK_COMMON_INCLUDED
#define BENCHMARK_COMMON_INCLUDED

struct Attributes { uint vertexID : SV_VertexID; };
struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

// Classic "one triangle covers the whole screen" trick: draw with
// DrawProcedural(topology: Triangles, vertexCount: 3), no buffers needed.
Varyings Vert(Attributes IN)
{
    Varyings OUT;
    OUT.positionCS = float4(
        (IN.vertexID == 2) ? 3.0 : -1.0,
        (IN.vertexID == 1) ? 3.0 : -1.0,
        0, 1);
    OUT.uv = OUT.positionCS.xy * 0.5 + 0.5;
    return OUT;
}

#endif
