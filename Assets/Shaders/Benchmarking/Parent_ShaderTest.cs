using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text;
using TMPro;
using UnityEngine;

public class Parent_ShaderTest : MonoBehaviour
{
    static public Vector2Int rt_WidthHeight = new Vector2Int(1920, 1080);
    static public float warmupFrames = 30;
    static public float sampleFrames = 120;
    static public List<string> _debugLines = new List<string>();
    static public event Action<StringBuilder> updateDebugger;
    [SerializeField] private TMP_InputField rt_Width_T;
    [SerializeField] private TMP_InputField rt_Height_T;
    [SerializeField] private TMP_InputField warmupFrames_T;
    [SerializeField] private TMP_InputField sampleFrames_T;
    [SerializeField] private TMP_Text deubgger_T;

    private const int maxLines = 100;

    private void OnEnable()
    {
        updateDebugger += UpdateDebugger;
    }

    private void OnDisable()
    {
        updateDebugger -= UpdateDebugger;
    }

    public void SetRTWidth()
    {
        if (int.TryParse(rt_Width_T.text, out int res))
        {
            rt_WidthHeight.x = res;
        }
    }

    public void SetRTHeight()
    {
        if (int.TryParse(rt_Height_T.text, out int res))
        {
            rt_WidthHeight.y = res;
        }
    }

    public void SetWarmupFrames()
    {
        if (int.TryParse(warmupFrames_T.text, out int res))
        {
            warmupFrames = res;
        }
    }

    public void SetSampleFrames()
    {
        if (int.TryParse(sampleFrames_T.text, out int res))
        {
            sampleFrames = res;
        }
    }

    static public void AddDebugLine(string line)
    {
        _debugLines.Insert(0, line);
        if (_debugLines.Count > maxLines)
            _debugLines.RemoveAt(_debugLines.Count - 1);

        var sb = new StringBuilder();
        sb.Append("<color=red>").Append(_debugLines[0]).Append("</color>\n \n");

        if (_debugLines.Count > 1)
        {
            sb.Append("<color=black>");
            for (int i = 1; i < _debugLines.Count; i++)
                sb.Append(_debugLines[i]).Append(i < _debugLines.Count - 1 ? "\n" : "");
            sb.Append("</color>");
        }

        updateDebugger?.Invoke(sb);
    }

    void UpdateDebugger(StringBuilder sb)
    {
        deubgger_T.text = sb.ToString();
    }
}
