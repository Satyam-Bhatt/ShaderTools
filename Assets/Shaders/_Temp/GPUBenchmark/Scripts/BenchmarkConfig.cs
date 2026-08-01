using UnityEngine;
using UnityEngine.Rendering;

/// <summary>
/// Base class for a single GPU pipeline-stage benchmark.
/// Setup() runs once before timing starts, RecordCommands() records exactly
/// the workload you want measured into the command buffer that gets executed
/// every frame during the sampling window, Cleanup() releases resources.
/// </summary>
public abstract class BenchmarkConfig : ScriptableObject
{
    public string benchmarkName;

    public abstract void Setup();
    public abstract void RecordCommands(CommandBuffer cmd);
    public abstract void Cleanup();
}
