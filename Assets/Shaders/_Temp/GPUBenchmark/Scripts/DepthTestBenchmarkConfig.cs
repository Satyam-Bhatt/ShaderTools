using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;

public enum DepthPrecision { D16, D24_S8, D32, D32_S8 }
public enum ZMode { EarlyZ, LateZ }

[CreateAssetMenu(menuName = "Benchmarks/Depth Test (ZROP)")]
public class DepthTestBenchmarkConfig : BenchmarkConfig
{
    public Shader shader;              // Benchmark/ZROP
    public DepthPrecision precision = DepthPrecision.D16;
    public ZMode zMode = ZMode.EarlyZ;
    public int width = 8192;
    public int height = 4096;
    public int drawCalls = 10;
    public int trianglesPerDraw = 20000;

    Material _mat;
    RenderTexture _rt;

    public override void Setup()
    {
        _mat = new Material(shader);
        _mat.shaderKeywords = new[] { zMode == ZMode.EarlyZ ? "_EARLYZ" : "_LATEZ" };

        GraphicsFormat format = precision switch
        {
            DepthPrecision.D16 => GraphicsFormat.D16_UNorm,
            DepthPrecision.D24_S8 => GraphicsFormat.D24_UNorm_S8_UInt,
            DepthPrecision.D32 => GraphicsFormat.D32_SFloat,
            DepthPrecision.D32_S8 => GraphicsFormat.D32_SFloat_S8_UInt,
            _ => GraphicsFormat.D16_UNorm
        };

        _rt = new RenderTexture(width, height, 0)
        {
            depthStencilFormat = format,
            graphicsFormat = GraphicsFormat.None // depth-only target
        };
        _rt.Create();
    }

    public override void RecordCommands(CommandBuffer cmd)
    {
        cmd.SetRenderTarget(_rt);
        cmd.ClearRenderTarget(true, false, Color.clear);
        for (int i = 0; i < drawCalls; i++)
            cmd.DrawProcedural(Matrix4x4.identity, _mat, 0, MeshTopology.Triangles, trianglesPerDraw * 3, 1);
    }

    public override void Cleanup()
    {
        _rt.Release();
        Object.Destroy(_mat);
    }
}
