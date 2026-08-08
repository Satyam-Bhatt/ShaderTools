Shader "Custom/RainScroll_Mobile"
{
 // Same scrolling rain, but each streak/droplet BULGES and refracts
    // whatever is behind the surface, like real wet glass.
    //
    // REQUIRES: URP Renderer asset -> "Opaque Texture" enabled.
    // (Project Settings-ish location: your Universal Renderer Data asset,
    //  under Rendering -> Opaque Texture = On)

    Properties
    {
        _MainTex        ("Rain Texture (Alpha = streak/height mask)", 2D) = "white" {}
        _Color          ("Streak Tint / Opacity", Color) = (0.9, 0.92, 0.95, 0.9)
        _BgTint         ("Windshield/Glass Tint (applies everywhere, not just gaps)", Color) = (0.4, 0.5, 0.45, 0.35)
        _Tiling         ("Tiling (X, Y)", Vector) = (1, 1, 0, 0)
        _ScrollSpeed    ("Scroll Speed (X, Y)", Vector) = (0, -1.5, 0, 0)
        _BulgeStrength  ("Bulge / Refraction Strength", Range(0, 0.2)) = 0.03
        _Specular       ("Highlight Strength", Range(0, 4)) = 1.5
        _Shininess      ("Highlight Sharpness", Range(1, 128)) = 32
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
        }

        // We need to draw AFTER opaques exist in _CameraOpaqueTexture, and
        // we don't need real blending since alpha is used to mask the lerp
        // manually - but keeping normal alpha blend is fine and simplest.
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off
        Cull Off

        Pass
        {
            Name "RainBulge"

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0 // needs ddx/ddy + a texture fetch, still mobile-fine

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half4  _Color;
                half4  _BgTint;
                float4 _Tiling;
                float4 _ScrollSpeed;
                half   _BulgeStrength;
                half   _Specular;
                half   _Shininess;
            CBUFFER_END

            struct Attributes
            {
                float3 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float4 screenPos   : TEXCOORD1;
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS);

                float2 uv = IN.uv * _Tiling.xy;
                uv += _ScrollSpeed.xy * _Time.y;
                OUT.uv = uv;

                OUT.screenPos = ComputeScreenPos(OUT.positionHCS);
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                // Height field for this droplet/streak
                half drop = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv).a;

                // Cheap normal-from-height using screen-space derivatives.
                // Flat areas (drop constant, mostly 0) give ~zero gradient,
                // so distortion naturally only shows up on droplet edges.
                half2 grad = half2(ddx(drop), ddy(drop));
                half3 normal = normalize(half3(-grad * _BulgeStrength * 40.0, 1.0));

                // Refract the background through the droplet normal
                float2 screenUV = IN.screenPos.xy / IN.screenPos.w;
                float2 distortedUV = screenUV + normal.xy * _BulgeStrength * drop;
                half3 bgColor = SampleSceneColor(distortedUV);

                // Fake specular highlight so droplets "pop" like wet glass
                half3 lightDir = normalize(half3(0.3, 0.5, 0.8));
                half  NdotL = saturate(dot(normal, lightDir));
                half  spec = pow(NdotL, _Shininess) * _Specular * drop;

                // Tint the ENTIRE surface uniformly first - like actual
                // tinted glass - then let droplets add refraction/highlight
                // on top of that tint rather than replacing it in the gaps.
                half3 tintedBg = lerp(bgColor, _BgTint.rgb, _BgTint.a);
                half3 outRGB   = tintedBg + spec * _Color.rgb;

                // Base alpha is the constant "how tinted is the glass"
                // value, with a small extra opacity bump right at droplets
                // (wet spots read very slightly denser than dry glass).
                half outAlpha = saturate(_BgTint.a + drop * _Color.a * (1.0 - _BgTint.a));

                return half4(outRGB, outAlpha);
            }
            ENDHLSL
        }
    }

    FallBack Off
}
