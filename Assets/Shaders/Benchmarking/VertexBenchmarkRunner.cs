using System.Collections;
using System.Collections.Generic;
using System.Linq;
using UnityEngine;
using UnityEngine.Rendering;
using TMPro;

// Vertex Attribute Fetch (VAF)
public class VertexBenchmarkRunner : MonoBehaviour
{
    public Shader shader;         
    public Camera targetCamera;
    public int triangleCount = 1000000;
    public int drawCalls = 18;
    public TMP_Text debugger;

    Material _mat;
    Mesh _mesh;
    RenderTexture _rt;
    CommandBuffer _cmd;
    readonly List<double> _samples = new List<double>();
    bool _running = false;
    bool _runTest = false;

    private void OnEnable()
    {
        _mat = new Material(shader);
        _rt = new RenderTexture(Parent_ShaderTest.rt_WidthHeight.x, Parent_ShaderTest.rt_WidthHeight.y, 0);
        _rt.Create();
        _cmd = new CommandBuffer { name = "VAF Benchmark" };

        RenderPipelineManager.endCameraRendering += OnEndCameraRendering;
    }

    private void OnDisable()
    {
        RenderPipelineManager.endCameraRendering -= OnEndCameraRendering;

        _rt.Release();
        Destroy(_mat);
        Destroy(_mesh);
    }

    void OnEndCameraRendering(ScriptableRenderContext ctx, Camera cam)
    {
        if (cam != targetCamera) return;

        _cmd.Clear();
        _cmd.SetRenderTarget(_rt);
        _cmd.ClearRenderTarget(false, true, Color.clear);
        if(_runTest)
        {
            for (int i = 0; i < drawCalls; i++)
                _cmd.DrawMesh(_mesh, Matrix4x4.identity, _mat, 0, 0);
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
        _mesh = BuildUniqueVertexMesh(triangleCount);

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
        Debug.Log($"VAF benchmark ({triangleCount} triangle count {drawCalls} Draw Calls): median={median:F3}ms mean={mean:F3}ms samples={_samples.Count}");
        debugger.text = $"VAF benchmark ({triangleCount} triangle count {drawCalls} Draw Calls): median={median:F3}ms mean={mean:F3}ms samples={_samples.Count}\n" + debugger.text;

        _runTest = false;
        _running = false;
    }

    Mesh BuildUniqueVertexMesh(int triCount)
    {
        int vertCount = triCount * 3;
        var mesh = new Mesh { indexFormat = UnityEngine.Rendering.IndexFormat.UInt32 }; // To accomodate more vertices
        var verts = new Vector3[vertCount];
        var indices = new int[vertCount];
        for (int i = 0; i < vertCount; i++)
        {
            verts[i] = new Vector3(Random.value, Random.value, 0);
            indices[i] = i;
        }
        mesh.vertices = verts;
        mesh.SetIndices(indices, MeshTopology.Triangles, 0);
        mesh.bounds = new Bounds(Vector3.zero, Vector3.one * 100000f); // avoid CPU culling with big bounds
        return mesh;
    }
}
