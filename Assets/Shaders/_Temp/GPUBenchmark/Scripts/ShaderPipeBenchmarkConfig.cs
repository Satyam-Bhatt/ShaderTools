using UnityEngine;
using UnityEngine.Rendering;

public enum SMPipe { FP32, INT32, SFU }

[CreateAssetMenu(menuName = "Benchmarks/SM Pipe (FP32/INT32/SFU)")]
public class ShaderPipeBenchmarkConfig : BenchmarkConfig
{
    public Shader shader;              // Benchmark/SMPipe
    public SMPipe pipe = SMPipe.FP32;
    public int width = 1920;
    public int height = 1080;

    Material _mat;
    RenderTexture _rt;

    public override void Setup()
    {
        _mat = new Material(shader);
        _mat.shaderKeywords = new[] { pipe switch
        {
            SMPipe.FP32 => "_FP32",
            SMPipe.INT32 => "_INT32",
            SMPipe.SFU => "_SFU",
            _ => "_FP32"
        }};
        _rt = new RenderTexture(width, height, 0);
        _rt.Create();
    }

    public override void RecordCommands(CommandBuffer cmd)
    {
        cmd.SetRenderTarget(_rt);
        cmd.DrawProcedural(Matrix4x4.identity, _mat, 0, MeshTopology.Triangles, 3, 1);
    }

    public override void Cleanup()
    {
        _rt.Release();
        Object.Destroy(_mat);
    }
}

[CreateAssetMenu(menuName = "Benchmarks/Texture Cache")]
public class TextureCacheBenchmarkConfig : BenchmarkConfig
{
    public Shader shader;              // Benchmark/Texture
    public Texture2D sourceTexture;    // e.g. a 4K texture for cache-miss testing
    public bool cacheMiss = false;
    public int width = 1920;
    public int height = 1080;

    Material _mat;
    RenderTexture _rt;

    public override void Setup()
    {
        _mat = new Material(shader);
        _mat.shaderKeywords = new[] { cacheMiss ? "_CACHE_MISS" : "_CACHE_HIT" };
        _mat.SetTexture("_MainTex", sourceTexture);
        _rt = new RenderTexture(width, height, 0);
        _rt.Create();
    }

    public override void RecordCommands(CommandBuffer cmd)
    {
        cmd.SetRenderTarget(_rt);
        cmd.DrawProcedural(Matrix4x4.identity, _mat, 0, MeshTopology.Triangles, 3, 1);
    }

    public override void Cleanup()
    {
        _rt.Release();
        Object.Destroy(_mat);
    }
}
