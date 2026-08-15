Shader "Custom/RainWiper"
{
    // REQUIRES _CameraOpaqueTexture (enable "Opaque Texture" on your URP Renderer asset)
    //
    // Two things merged here:
    //  1) The procedural, layered raindrop trick from your Shadertoy snippet. Instead of
    //     sampling a height/alpha mask texture for drop shapes (like your old _MainTex),
    //     drops are generated on the fly from a tiling noise texture read at several radial
    //     frequencies (the `r` loop 0.3 -> 0.15). That's why you get overlapping small/medium
    //     drops popping in and out without any authored drop texture.
    //  2) WiperMask() was already sitting in your file but never actually called in frag() --
    //     it's now used to blend the rain distortion back to clean tinted glass wherever the
    //     blade currently sits.
    //
    // STYLE NOTE: this produces static droplets that pop in/out over time (via the `f`
    // re-randomization term), not falling streaks like your old _ScrollSpeed/_MainTex version.
    // Different look -- droplets sitting on glass vs. rain running down it. Say if you want the
    // streak look kept as a second layered pass instead of a replacement.
    //
    // WIPER NOTE: WiperMask() only clears the blade's *instantaneous* position/width each
    // frame -- there's no persistent "stays dry after wipe" trail. In motion, with rain still
    // falling, this reads fine (a clean band follows the blade, area re-wets after it passes --
    // close to how real wipers look mid-storm). If you want a persistent dry trail, that needs
    // a small accumulation buffer (a RenderTexture painted with the wiper mask each frame, fed
    // back in here as another sample) -- happy to build that as a follow-up pass if you want it.

    Properties
    {
        _BgTint         ("Glass Tint", Color) = (0.4, 0.5, 0.45, 0.35)
        _NoiseTex       ("Tileable Noise (RGBA, Wrap = Repeat)", 2D) = "gray" {}
        _NoiseScale     ("Noise Sample Scale", Float) = 1.0

        _WiperPivotUV   ("Wiper Pivot (UV)", Vector) = (0.5, 0.05, 0, 0)
        _WiperAngle     ("Wiper Current Angle (deg)", Range(-90,90)) = 0
        _WiperWidth     ("Wiper Blade Width (deg)", Range(1,60)) = 25
        _WiperRadius    ("Wiper Reach (UV units)", Float) = 1.2
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
        }

        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off
        Cull Off

        Pass
        {
            Name "RainWiper"

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            TEXTURE2D(_NoiseTex);
            SAMPLER(sampler_NoiseTex);

            CBUFFER_START(UnityPerMaterial)
                half4  _BgTint;
                float  _NoiseScale;

                half2  _WiperPivotUV;
                half   _WiperAngle;
                half   _WiperWidth;
                half   _WiperRadius;
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

            // Unchanged from your original -- kept in mesh UV space so _WiperPivotUV stays
            // meaningful regardless of screen resolution/aspect ratio.
            float WiperMask(float2 uv)
            {
                float2 d = uv - _WiperPivotUV;
                float dist = length(d);
                float angle = degrees(atan2(d.y, d.x));

                float angleDelta = abs(angle - _WiperAngle);
                angleDelta = min(angleDelta, 360.0 - angleDelta);

                float angularMask = 1.0 - smoothstep(_WiperWidth * 0.5 - 4.0, _WiperWidth * 0.5, angleDelta);
                float radialMask = 1.0 - smoothstep(_WiperRadius - 0.05, _WiperRadius, dist);
                return saturate(angularMask * radialMask);
            }

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS);
                OUT.uv = IN.uv;
                OUT.screenPos = ComputeScreenPos(OUT.positionHCS);
                return OUT;
            }

            // Direct HLSL port of your Shadertoy snippet. Kept the same variable names
            // (U, u, N, d, p, s, f, v) on purpose so you can diff this against the GLSL
            // line-for-line if something looks off.
            //
            // One thing to know: the original fed *unnormalized*, pixel-scale UVs into
            // texture(iChannel1, round(U*x-.25)/x) and relied on iChannel1's wrap mode being
            // Repeat to make that tile sanely. Same deal here -- _NoiseTex's Wrap Mode MUST be
            // set to Repeat in the import inspector, or the grid pattern breaks at UV(1,1).
            //
            // Also: textureLod(iChannel0, u, 2.5) in the original grabs a blurred base layer
            // via mip bias. _CameraOpaqueTexture doesn't have mips by default in URP, so this
            // samples it directly instead -- slightly sharper base than the original, cosmetic
            // difference only.
            half3 ProceduralRain(float2 screenUV, half3 baseColor)
            {
                float2 U = screenUV * _ScreenParams.xy;   // pixel coords, mirrors Shadertoy fragCoord
                float2 u = screenUV;                        // normalized 0-1, mirrors Shadertoy's u

                half2 N = SAMPLE_TEXTURE2D_LOD(_NoiseTex, sampler_NoiseTex, u * 0.1 * _NoiseScale, 0).rg;

                half3 O = baseColor;

                float f, x;
                for (float r = 0.3; r > 0.1; r -= 0.05)
                {
                    x = r / 6.28318530718;

                    half4 d = SAMPLE_TEXTURE2D_LOD(_NoiseTex, sampler_NoiseTex, round(U * x - 0.25) / x * _NoiseScale, 0);

                    float2 p = U * r + 2.0 * N - 1.0;
                    float2 s = sin(p);

                    // Re-randomizes per drop every cycle so droplets pop in/out over time
                    // instead of scrolling -- see the STYLE NOTE at the top of the file.
                    f = (s.x + s.y) * max(0.0, 1.0 - frac(_Time.y * (d.b + 0.1) + d.g) * 2.0);

                    if (d.r < 0.2 && f > 0.5)
                    {
                        float3 v = normalize(-float3(cos(p) * 5.0, lerp(1.0, 10.0, f - 0.5)));
                        O = SampleSceneColor(u - v.xy * 0.3);
                    }
                }

                return O;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float2 screenUV = IN.screenPos.xy / IN.screenPos.w;

                half3 cleanTinted = lerp(SampleSceneColor(screenUV), _BgTint.rgb, _BgTint.a);
                half3 rainy = ProceduralRain(screenUV, cleanTinted);

                half wiper = WiperMask(IN.uv);

                // wiper == 1 under/behind the blade -> clean tinted glass, drops removed.
                // wiper == 0 everywhere else -> full procedural rain.
                half3 outRGB = lerp(rainy, cleanTinted, wiper);
                half outAlpha = saturate(_BgTint.a + (1.0 - wiper) * 0.25);

                return half4(outRGB, outAlpha);
            }
            ENDHLSL
        }
    }

    FallBack Off
}
