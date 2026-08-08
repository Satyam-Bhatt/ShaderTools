Shader "Custom/RainScroll_Mobile_BuiltIn"
{
    // Cheap scrolling rain for the BUILT-IN render pipeline.
    // Put on a transparent quad in front of the camera, or on a window mesh's UVs.

    Properties
    {
        _MainTex     ("Rain Texture (Alpha = streak mask)", 2D) = "white" {}
        _Color       ("Tint / Opacity", Color) = (0.8, 0.85, 0.9, 0.7)
        _Tiling      ("Tiling (X, Y)", Vector) = (1, 1, 0, 0)
        _ScrollSpeed ("Scroll Speed (X, Y)", Vector) = (0, -2.5, 0, 0)
        _Brightness  ("Brightness", Range(0, 3)) = 1.2
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "IgnoreProjector" = "True"
        }

        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off
        Cull Off

        Pass
        {
            Name "RainScroll"

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 2.0
            #include "UnityCG.cginc"

            sampler2D _MainTex;
            float4 _MainTex_ST;
            fixed4  _Color;
            float4 _Tiling;
            float4 _ScrollSpeed;
            half   _Brightness;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv     : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv  : TEXCOORD0;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);

                float2 uv = v.uv * _Tiling.xy;
                uv += _ScrollSpeed.xy * _Time.y; // _Time.y = seconds since load
                o.uv = uv;
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                fixed4 tex = tex2D(_MainTex, i.uv);

                half streak = tex.a * _Brightness;
                fixed3 rgb  = _Color.rgb * streak;
                fixed  alpha = streak * _Color.a;

                return fixed4(rgb, alpha);
            }
            ENDCG
        }
    }

    FallBack Off
}
