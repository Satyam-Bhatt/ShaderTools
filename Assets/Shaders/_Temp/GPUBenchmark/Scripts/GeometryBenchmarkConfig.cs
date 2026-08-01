using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// Vertex Attribute Fetch: a huge mesh whose vertex shader shoves every
/// triangle off-screen, so the ONLY real cost left is fetching vertex data
/// from VRAM. Uses an actual vertex buffer (unlike VPC below).
/// </summary>
[CreateAssetMenu(menuName = "Benchmarks/Vertex Attribute Fetch (VAF)")]
public class VertexFetchBenchmarkConfig : BenchmarkConfig
{
    public Shader shader;              // Benchmark/VAF
    public int triangleCount = 1_000_000; // 3M verts = 1M unique triangles
    public int drawCalls = 18;
    public int depthTextureSize = 1024;

    Material _mat;
    Mesh _mesh;
    RenderTexture _rt;

    public override void Setup()
    {
        _mat = new Material(shader);
        _mesh = BuildUniqueVertexMesh(triangleCount);
        _rt = new RenderTexture(depthTextureSize, depthTextureSize, 24);
        _rt.Create();
    }

    // Every triangle gets its own 3 vertices (no sharing) so the vertex
    // cache can't help you -- this matches "3,000,000 vertices" in the deck.
    static Mesh BuildUniqueVertexMesh(int triCount)
    {
        int vertCount = triCount * 3;
        var mesh = new Mesh { indexFormat = UnityEngine.Rendering.IndexFormat.UInt32 };
        var verts = new Vector3[vertCount];
        var indices = new int[vertCount];
        for (int i = 0; i < vertCount; i++)
        {
            verts[i] = new Vector3(Random.value, Random.value, 0);
            indices[i] = i;
        }
        mesh.vertices = verts;
        mesh.SetIndices(indices, MeshTopology.Triangles, 0);
        mesh.bounds = new Bounds(Vector3.zero, Vector3.one * 100000f); // avoid CPU culling
        return mesh;
    }

    public override void RecordCommands(CommandBuffer cmd)
    {
        cmd.SetRenderTarget(_rt);
        for (int i = 0; i < drawCalls; i++)
            cmd.DrawMesh(_mesh, Matrix4x4.identity, _mat, 0, 0);
    }

    public override void Cleanup()
    {
        _rt.Release();
        Object.Destroy(_mat);
        Object.Destroy(_mesh);
    }
}

/// <summary>
/// Viewport Processing Cluster: triangles generated procedurally from
/// SV_VertexID (zero vertex-buffer cost) sized at sub-pixel scale and
/// scattered across clip space -- isolates transform/clip/cull/setup cost.
/// </summary>
[CreateAssetMenu(menuName = "Benchmarks/Viewport Processing Cluster (VPC)")]
public class ViewportClusterBenchmarkConfig : BenchmarkConfig
{
    public Shader shader;              // Benchmark/VPC
    public int triangleCount = 4_000_000;
    public int drawCalls = 12;
    public int depthTextureSize = 1024;

    Material _mat;
    RenderTexture _rt;

    public override void Setup()
    {
        _mat = new Material(shader);
        _rt = new RenderTexture(depthTextureSize, depthTextureSize, 24);
        _rt.Create();
    }

    public override void RecordCommands(CommandBuffer cmd)
    {
        cmd.SetRenderTarget(_rt);
        int perDraw = triangleCount / drawCalls;
        for (int i = 0; i < drawCalls; i++)
            cmd.DrawProcedural(Matrix4x4.identity, _mat, 0, MeshTopology.Triangles, perDraw * 3, 1);
    }

    public override void Cleanup()
    {
        _rt.Release();
        Object.Destroy(_mat);
    }
}
