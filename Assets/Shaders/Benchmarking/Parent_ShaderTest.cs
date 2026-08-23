using TMPro;
using UnityEngine;

public class Parent_ShaderTest : MonoBehaviour
{
    static public Vector2Int rt_WidthHeight = new Vector2Int(1920, 1080);
    static public float warmupFrames = 30;
    static public float sampleFrames = 120;
    [SerializeField] private TMP_InputField rt_Width_T;
    [SerializeField] private TMP_InputField rt_Height_T;
    [SerializeField] private TMP_InputField warmupFrames_T;
    [SerializeField] private TMP_InputField sampleFrames_T;

    public void SetRTWidth()
    {
        if(int.TryParse(rt_Width_T.text, out int res))
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
}
