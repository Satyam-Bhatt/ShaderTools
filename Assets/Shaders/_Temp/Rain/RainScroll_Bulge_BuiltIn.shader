Shader "Custom/RainScroll_Bulge_BuiltIn"
{
    // Bulging/refracting rain for the BUILT-IN render pipeline.
    // Uses GrabPass to grab what's behind the surface, since Built-in has
    // no equivalent to URP's _CameraOpaqueTexture.
    //
    // COST NOTE: GrabPass copies the screen every frame this shader is
    // drawn. Fine for ONE rain overlay/window. Do not put this shader on
    // many separate objects - duplicate the material/object instead of
    // the shader if you need it in multiple places, and prefer the flat
    // "RainScroll_BuiltIn" shader anywhere the bulge isn't essential.

    Properties
    {
        _MainTex       ("Rain Texture (Alpha = streak/height mask)", 2D) = "white" {}
        _Color         ("Tint / Opacity", Color) = (0.9, 0.92, 0.95, 0.9)
        _Tiling        ("Tiling (X, Y)", Vector) = (1, 1, 0, 0)
        _ScrollSpeed   ("Scroll Speed (X, Y)", Vector) = (0, -2.5, 0, 0)
        _BulgeStrength ("Bulge / Refraction Strength", Range(0, 0.2)) = 0.03
        _Specular      ("Highlight Strength", Range(0, 4)) = 1.5
        _Shininess     ("Highlight Sharpness", Range(1, 128)) = 32
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
        }

        GrabPass { "_BackgroundTex" }

        Pass
        {
            Name "RainBulge"

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Off

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0
            #include "UnityCG.cginc"

            sampler2D _MainTex;
            float4 _MainTex_ST;
            sampler2D _BackgroundTex;
            fixed4  _Color;
            float4 _Tiling;
            float4 _ScrollSpeed;
            half   _BulgeStrength;
            half   _Specular;
            half   _Shininess;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv     : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos      : SV_POSITION;
                float2 uv       : TEXCOORD0;
                float4 grabPos  : TEXCOORD1;
            };

            v2f vert (appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);

                float2 uv = v.uv * _Tiling.xy;
                uv += _ScrollSpeed.xy * _Time.y;
                o.uv = uv;

                o.grabPos = ComputeGrabScreenPos(o.pos);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // Height field for this droplet/streak
                half drop = tex2D(_MainTex, i.uv).a;

                // Cheap normal-from-height using screen-space derivatives.
                half2 grad = half2(ddx(drop), ddy(drop));
                half3 normal = normalize(half3(-grad * _BulgeStrength * 40.0, 1.0));

                // Refract the grabbed background through the droplet normal
                float2 screenUV = i.grabPos.xy / i.grabPos.w;
                float2 distortedUV = screenUV + normal.xy * _BulgeStrength * drop;
                fixed3 bgColor = tex2D(_BackgroundTex, distortedUV).rgb;

                // Fake specular highlight so droplets read as wet/glassy
                half3 lightDir = normalize(half3(0.3, 0.5, 0.8));
                half  NdotL = saturate(dot(normal, lightDir));
                half  spec = pow(NdotL, _Shininess) * _Specular * drop;

                fixed3 finalRGB = bgColor + spec * _Color.rgb;
                fixed  alpha = saturate(drop) * _Color.a;

                return fixed4(finalRGB, alpha);
            }
            ENDCG
        }
    }

    FallBack Off
}
