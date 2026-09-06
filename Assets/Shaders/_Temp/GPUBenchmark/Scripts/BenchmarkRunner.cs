using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// Drives a list of BenchmarkConfigs one at a time, times each with
/// FrameTimingManager (whole-frame GPU time -- accurate as long as the rest
/// of the frame is doing nothing else, which is why we hijack rendering via
/// endCameraRendering instead of letting the normal scene render), computes
/// min/max/median/mean/q25/q75, and writes a JSON file with the results.
///
/// SETUP NOTES
/// - Works with URP/HDRP (uses RenderPipelineManager events). For the
///   built-in render pipeline, swap OnEndCameraRendering's hook for
///   targetCamera.AddCommandBuffer(CameraEvent.BeforeForwardOpaque, cmd)
///   and record once in Setup() instead of every frame.
/// - Run this as a Standalone build with VSync off, not in the Editor --
///   editor overhead and the Game/Scene view both drawing will add noise.
/// - FrameTimingManager needs a graphics API that supports GPU timing
///   (DX11/DX12/Vulkan/consoles). It can silently return 0 samples on
///   unsupported combinations (e.g. some Metal/OpenGL setups) -- check
///   SystemInfo.graphicsDeviceType if results look empty.
/// </summary>
public class BenchmarkRunner : MonoBehaviour
{
    public List<BenchmarkConfig> benchmarks = new List<BenchmarkConfig>();
    public Camera targetCamera;
    public int warmupFrames = 30;
    public int sampleFrames = 120;
    public string outputFileName = "gpu_benchmark_results.json";

    CommandBuffer _cmd;
    BenchmarkConfig _active;
    readonly List<double> _samples = new List<double>();

    [Serializable]
    public class Stat
    {
        public string name;
        public double min, max, median, mean, q25, q75;
    }

    [Serializable]
    public class ResultSet
    {
        public List<Stat> results = new List<Stat>();
    }

    void Awake()
    {
        QualitySettings.vSyncCount = 0;
        Application.targetFrameRate = -1;
    }

    void OnEnable()
    {
        RenderPipelineManager.endCameraRendering += OnEndCameraRendering;
    }

    void OnDisable()
    {
        RenderPipelineManager.endCameraRendering -= OnEndCameraRendering;
    }

    void Start()
    {
        _cmd = new CommandBuffer { name = "GPU Benchmark" };
        StartCoroutine(RunAll());
    }

    void OnEndCameraRendering(ScriptableRenderContext ctx, Camera cam)
    {
        if (cam != targetCamera || _active == null) return;

        _cmd.Clear();
        _active.RecordCommands(_cmd);
        ctx.ExecuteCommandBuffer(_cmd);
        ctx.Submit();
    }

    IEnumerator RunAll()
    {
        var resultSet = new ResultSet();

        foreach (var bench in benchmarks)
        {
            Debug.Log($"[Benchmark] Running {bench.benchmarkName}...");
            bench.Setup();
            _active = bench;
            _samples.Clear();

            // Warmup: let GPU clocks/caches settle, discard these frames.
            for (int i = 0; i < warmupFrames; i++)
                yield return null;

            FrameTimingManager.CaptureFrameTimings();

            for (int i = 0; i < sampleFrames; i++)
            {
                yield return new WaitForEndOfFrame();
                FrameTimingManager.CaptureFrameTimings();

                var timings = new FrameTiming[1];
                uint got = FrameTimingManager.GetLatestTimings(1, timings);
                if (got > 0 && timings[0].gpuFrameTime > 0)
                    _samples.Add(timings[0].gpuFrameTime);
            }

            _active = null;
            bench.Cleanup();

            var stat = ComputeStats(bench.benchmarkName, _samples);
            resultSet.results.Add(stat);
            Debug.Log($"[Benchmark] {stat.name}: median={stat.median:F3}ms mean={stat.mean:F3}ms (n={_samples.Count})");
        }

        var json = JsonUtility.ToJson(resultSet, true);
        var path = Path.Combine(Application.persistentDataPath, outputFileName);
        File.WriteAllText(path, json);
        Debug.Log($"[Benchmark] Results written to {path}");
    }

    static Stat ComputeStats(string name, List<double> samples)
    {
        var s = samples.OrderBy(x => x).ToList();
        int n = s.Count;

        double Percentile(double p)
        {
            if (n == 0) return 0;
            double idx = p * (n - 1);
            int lo = (int)Math.Floor(idx), hi = (int)Math.Ceiling(idx);
            if (lo == hi) return s[lo];
            return s[lo] + (s[hi] - s[lo]) * (idx - lo);
        }

        return new Stat
        {
            name = name,
            min = n > 0 ? s[0] : 0,
            max = n > 0 ? s[n - 1] : 0,
            median = Percentile(0.5),
            mean = n > 0 ? s.Average() : 0,
            q25 = Percentile(0.25),
            q75 = Percentile(0.75)
        };
    }
}
