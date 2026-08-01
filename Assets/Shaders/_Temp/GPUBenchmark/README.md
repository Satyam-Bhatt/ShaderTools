# GPU Pipeline Stage Benchmarks — Unity skeleton

Replicates the approach from Jan Mróz's "GPU stage benchmarks" deck:
isolate one hardware stage, feed it a workload that stresses only that
stage, measure whole-frame GPU time (frame overhead is near-zero so this
≈ the stage cost), repeat for N frames, compute stats.

This is untested skeleton code — it compiles conceptually but hasn't been
run through the Unity compiler here, so expect to fix small API mismatches
(especially `GraphicsFormat` names, which shift a bit between Unity
versions) once you drop it into your project.

## Files

```
Scripts/
  BenchmarkConfig.cs                 - abstract base every benchmark implements
  DepthTestBenchmarkConfig.cs        - ZROP: EarlyZ/LateZ x D16/D24S8/D32/D32S8
  ColorBlendBenchmarkConfig.cs       - CROP: alpha blend x 4 color formats
  ShaderPipeBenchmarkConfig.cs       - SM pipes (FP32/INT32/SFU) + texture cache hit/miss
  GeometryBenchmarkConfig.cs         - VAF (vertex fetch) and VPC (viewport/clip/cull)
  BenchmarkRunner.cs                 - drives everything, times it, writes JSON

Shaders/
  BenchmarkCommon.hlsl               - shared full-screen-triangle vertex shader
  BenchmarkZROP.shader
  BenchmarkCROP.shader
  BenchmarkSMPipe.shader
  BenchmarkTexture.shader
  BenchmarkVAF.shader
  BenchmarkVPC.shader
```

## Setup in your project

1. Drop `Scripts/` and `Shaders/` anywhere under `Assets/`.
2. Create one `BenchmarkConfig` asset per test you want, via the
   `Assets > Create > Benchmarks` menu (e.g. one `DepthTestBenchmarkConfig`
   set to D16/EarlyZ, another set to D16/LateZ, etc. — this matches the 21
   config assets you can see in the Inspector screenshot in the deck).
3. Add a `BenchmarkRunner` to an empty GameObject in an otherwise empty
   scene, assign your camera, and drag all the config assets into the
   `benchmarks` list, in the order you want them run.
4. **Build a Standalone player and run that** — don't rely on Editor
   numbers. The Editor's own overhead (Scene view still rendering, profiler
   hooks, etc.) will pollute the timing. `QualitySettings.vSyncCount = 0`
   is already set in `Awake()`.

## Why `FrameTimingManager` instead of a stopwatch

Unity doesn't expose raw GPU timestamp queries to C#. The practical
scriptable option is `FrameTimingManager.GetLatestTimings()`, which gives
you `gpuFrameTime` per frame (needs a graphics API with GPU timing support —
DX11/DX12/Vulkan/consoles; check `SystemInfo.graphicsDeviceType` if you get
zero samples). That's *whole frame* GPU time, which is exactly why the
deck's approach of stripping the render loop down to nothing but the
benchmark draw call matters — with near-zero overhead, frame time ≈
benchmark time.

`BenchmarkRunner` hooks `RenderPipelineManager.endCameraRendering` (URP/HDRP)
and swaps in the active benchmark's command buffer instead of letting the
normal scene render. For the Built-in Render Pipeline, replace that hook
with `targetCamera.AddCommandBuffer(CameraEvent.BeforeForwardOpaque, cmd)`
and record the commands once in `Setup()` instead of every frame.

## Reading the results

The runner writes `gpu_benchmark_results.json` to
`Application.persistentDataPath` (Debug.Log prints the exact path). Shape:

```json
{
  "results": [
    {
      "name": "ZROP-D16_EarlyZ_Benchmark",
      "min": 17.74, "max": 19.68,
      "median": 18.43, "mean": 18.46,
      "q25": 18.38, "q75": 18.49
    }
  ]
}
```

Same fields as the deck's output — `min`/`max` tell you jitter/thermal
throttling range, `median` is the number to actually compare across GPUs
(less sensitive to occasional spikes than `mean`), and a tight
`q25`–`q75` band means the measurement is stable (widen `sampleFrames`
if it isn't).

## Tuning per-test knobs (matches the deck's methodology notes)

- **ZROP**: 10 draw calls × 20,000 triangles into an 8192×4096 depth
  texture, run once per depth format × EarlyZ/LateZ.
- **CROP**: 100 overlapping full-screen triangles into a 2048×2048 target,
  once per color format.
- **VAF**: 18 draw calls rendering a 3M-triangle mesh with unique vertices
  per triangle (no shared verts — defeats the post-transform cache),
  pushed off-screen.
- **VPC**: 12 draw calls generating 4M sub-pixel triangles procedurally
  into a 1K D16 depth target.
- **SM/Texture**: full-screen shader, loop unrolled ~64x with the target
  instruction type; texture test alternates a small 16×16 texture (cache
  hit) vs. a 4K texture with per-pixel random UV (cache miss).

## Caveats worth knowing before you trust the numbers

- GPU boost clocks drift with thermals — the `warmupFrames` window exists
  to let clocks settle, but for serious cross-GPU comparisons you'll want
  a longer soak and ideally locked clocks.
- `[unroll(64)]` loop counts are a starting point — tune them so each test
  runs long enough to dominate measurement noise (roughly >2-3ms) without
  taking forever.
- Driver-side batching/reordering can occasionally leak work across
  benchmarks if you don't fully flush between them — `ctx.Submit()` per
  frame in the runner should be enough, but watch for suspiciously
  correlated timings between adjacent benchmarks in your list.
