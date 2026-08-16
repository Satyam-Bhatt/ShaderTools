using System.Collections;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.Rendering;

// VPC responsible for converting clip space to screen space - clipping - culling
public class VPCBenchmarkRunner : MonoBehaviour
{
    public Shader shader;
    public Camera targetCamera;
    public int width = 1920, height = 1080;

    public int triangleCount = 4000000;
    public int drawCalls = 12;
    public int warmupFrames = 30;
    public int sampleFrames = 120;

    Material _mat;
    MaterialPropertyBlock _props; 
    RenderTexture _rt;
    CommandBuffer _cmd;
    readonly List<double> _samples = new List<double>();
    bool _running = false;
    bool _runTest = false;

    private void OnEnable()
    {
        _mat = new Material(shader);
        _rt = new RenderTexture(width, height, 0);
        _rt.Create();
        _cmd = new CommandBuffer { name = "VPC Benchmark" };
        _props = new MaterialPropertyBlock();

        RenderPipelineManager.endCameraRendering += OnEndCameraRendering;
    }

    private void OnDisable()
    {
        RenderPipelineManager.endCameraRendering -= OnEndCameraRendering;

        _rt.Release();
        Destroy(_mat);
    }

    void OnEndCameraRendering(ScriptableRenderContext ctx, Camera cam)
    {
        if (cam != targetCamera) return;

        _cmd.Clear();
        _cmd.SetRenderTarget(_rt);
        _cmd.ClearRenderTarget(false, true, Color.clear);
        if (_runTest)
        {
            int perDraw = triangleCount / drawCalls;
            for (int i = 0; i < drawCalls; i++)
            {
                _props.SetInt("_TriOffset", i * perDraw);
                _cmd.DrawProcedural(Matrix4x4.identity, _mat, 0, MeshTopology.Triangles, perDraw * 3, 1, _props);
            }
        }
        // Copies the commands
        ctx.ExecuteCommandBuffer(_cmd);
        // Sends the commands to the GPU
        ctx.Submit();
    }


    [ContextMenu("BenchMark Begin")]
    public void RunBenchmark()
    {
        StartCoroutine(RunBenchmark_Routine());
    }

    IEnumerator RunBenchmark_Routine()
    {
        if (_running) yield break;
        _running = true;

        _samples.Clear();
        _runTest = true;

        for (int i = 0; i < warmupFrames; i++) yield return null;

        // Get timing as frame completes
        FrameTimingManager.CaptureFrameTimings();
        var timings = new FrameTiming[1];
        for (int i = 0; i < sampleFrames; i++)
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
        Debug.Log($"VPC benchmark ({triangleCount} triangle count {drawCalls} Draw Calls): median={median:F3}ms mean={mean:F3}ms samples={_samples.Count}");

        _runTest = false;
        _running = false;
    }
}
