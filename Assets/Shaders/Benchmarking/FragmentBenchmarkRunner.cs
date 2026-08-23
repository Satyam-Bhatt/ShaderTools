using System.Collections;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.Rendering;
using TMPro;

public class FragmentBenchmarkRunner : MonoBehaviour
{
    public Shader shader;
    public Camera targetCamera;
    public int iterations = 64;
    public TMP_Text debugger;

    Material _mat;
    RenderTexture _rt;
    CommandBuffer _cmd;
    readonly List<double> _samples = new List<double>();
    bool _running = false;

    private void OnEnable()
    {
        _mat = new Material(shader);
        _mat.SetInt("_Iterations", iterations);
        _rt = new RenderTexture(Parent_ShaderTest.rt_WidthHeight.x, Parent_ShaderTest.rt_WidthHeight.y, 0);
        _rt.Create();
        _cmd = new CommandBuffer { name = "Hash Benchmark" };

        RenderPipelineManager.endCameraRendering += OnEndCameraRendering;
    }

    void OnDisable()
    {
        RenderPipelineManager.endCameraRendering -= OnEndCameraRendering;

        _rt.Release();
        Destroy(_mat);
    }


    // Called once per camera after it has finished rendering. Its called per frame 
    void OnEndCameraRendering(ScriptableRenderContext ctx, Camera cam)
    {
        if (cam != targetCamera) return;

        _cmd.Clear();
        _cmd.SetRenderTarget(_rt);
        _cmd.ClearRenderTarget(false, true, Color.clear);
        // Run the vertex shader 3 times with vertex index 0,1,2
        _cmd.DrawProcedural(Matrix4x4.identity, _mat, 0, MeshTopology.Triangles, 3, 1);
        // Copies the commands
        ctx.ExecuteCommandBuffer(_cmd);
        // Sends the commands to the GPU
        ctx.Submit();
    }

    [ContextMenu("BenchMark Begin")]
    public void RunBenchmark()
    {
        _mat.SetInt("_Iterations", iterations);
        StartCoroutine(RunBenchmark_Routine());
    }

    IEnumerator RunBenchmark_Routine()
    {
        if (_running) yield break;
        _running = true;

        _samples.Clear();
        for (int i = 0; i < Parent_ShaderTest.warmupFrames; i++) yield return null;

        // Get timing as frame completes
        FrameTimingManager.CaptureFrameTimings();
        var timings = new FrameTiming[1];
        for (int i = 0; i < Parent_ShaderTest.sampleFrames; i++)
        {
            yield return new WaitForEndOfFrame();
            FrameTimingManager.CaptureFrameTimings();
            // GetLatestTimings populates the array with the latest frame timings
            if (FrameTimingManager.GetLatestTimings(1, timings) > 0 && timings[0].gpuFrameTime > 0)
                _samples.Add(timings[0].gpuFrameTime);
        }
        _samples.Sort();
        double median = _samples.Count > 0 ? _samples[_samples.Count / 2] : 0;
        double mean = _samples.Count > 0 ? _samples.Average() : 0;
        Debug.Log($"Hash benchmark ({iterations} iters): median={median:F3}ms mean={mean:F3}ms samples={_samples.Count}");
        debugger.text = $"Hash benchmark ({iterations} iters): median={median:F3}ms mean={mean:F3}ms samples={_samples.Count}\n" + debugger.text;

        _running = false;
    }
}
