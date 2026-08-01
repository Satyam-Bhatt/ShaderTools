using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;

public enum ColorPrecision { R8G8B8A8, R11G11B10Float, R16G16B16A16, R32G32B32A32 }

[CreateAssetMenu(menuName = "Benchmarks/Color Blend (CROP)")]
public class ColorBlendBenchmarkConfig : BenchmarkConfig
{
    public Shader shader;              // Benchmark/CROP
    public ColorPrecision precision = ColorPrecision.R8G8B8A8;
    public int width = 2048;
    public int height = 2048;
    public int overlappingTriangles = 100;

    Material _mat;
    RenderTexture _rt;

    public override void Setup()
    {
        _mat = new Material(shader);

        GraphicsFormat format = precision switch
        {
            ColorPrecision.R8G8B8A8 => GraphicsFormat.R8G8B8A8_UNorm,
            ColorPrecision.R11G11B10Float => GraphicsFormat.B10G11R11_UFloatPack32,
            ColorPrecision.R16G16B16A16 => GraphicsFormat.R16G16B16A16_SFloat,
            ColorPrecision.R32G32B32A32 => GraphicsFormat.R32G32B32A32_SFloat,
            _ => GraphicsFormat.R8G8B8A8_UNorm
        };

        _rt = new RenderTexture(width, height, 0, format);
        _rt.Create();
    }

    public override void RecordCommands(CommandBuffer cmd)
    {
        cmd.SetRenderTarget(_rt);
        cmd.ClearRenderTarget(false, true, Color.clear);
        // Each draw call renders ONE full-screen triangle; issuing many draws
        // with alpha blending on stresses the blend unit + target bandwidth.
        for (int i = 0; i < overlappingTriangles; i++)
            cmd.DrawProcedural(Matrix4x4.identity, _mat, 0, MeshTopology.Triangles, 3, 1);
    }

    public override void Cleanup()
    {
        _rt.Release();
        Object.Destroy(_mat);
    }
}
