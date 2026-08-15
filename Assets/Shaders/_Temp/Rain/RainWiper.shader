Shader "Custom/RainWiper"
{
    Properties
    {
        _BgTint         ("Glass Tint", Color) = (0.4, 0.5, 0.45, 0.35)
        _NoiseTex       ("Tileable Noise (RGBA, Wrap = Repeat)", 2D) = "gray" {}
        _NoiseScale     ("Noise Sample Scale", Float) = 1.0
        _DropDistortion ("Drop Distortion", Range(0, 2)) = 0.3
        _DropSize       ("Drop Size", Range(0.001, 0.05)) = 0.015

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
                float  _DropDistortion;
                float  _DropSize;

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

            half3 ProceduralRain(float2 screenUV, half3 baseColor)
            {
                float2 U = screenUV * _ScreenParams.xy;   // pixel coordinates
                float2 u = screenUV;                        // normalized 0-1 coordinates

                // Sample displacement noise with more detail
                half2 N = SAMPLE_TEXTURE2D_LOD(_NoiseTex, sampler_NoiseTex, u * 0.1 * _NoiseScale, 0).rg;
                half2 N2 = SAMPLE_TEXTURE2D_LOD(_NoiseTex, sampler_NoiseTex, u * 0.3 * _NoiseScale, 0).rg;

                half3 O = baseColor;

                // Loop through different drop sizes (matching original)
                for (float r = 4.0; r > 0.0; r -= 1.0)
                {
                    // Grid size for this drop scale
                    float2 x = _ScreenParams.xy * r * _DropSize;

                    // Position calculation with displacement
                    float2 p = 6.28318 * u * x + (N - 0.5) * 2.0 + (N2 - 0.5) * 1.5;
                    float2 s = sin(p);
                    float2 c = cos(p);

                    // Get drop properties (consistent within each drop cell)
                    half4 d = SAMPLE_TEXTURE2D_LOD(_NoiseTex, sampler_NoiseTex, 
                        (round(u * x - 0.25) / x) * _NoiseScale, 0);

                    // Time-based animation
                    float t = (s.x + s.y) * max(0.0, 1.0 - frac(_Time.y * (d.b + 0.1) + d.g) * 2.0);

                    // Drop filtering
                    if (d.r < (5.0 - r) * 0.08 && t > 0.5)
                    {
                        // Create irregular drop shape using multiple sine waves
                        float shapeDistortion = (s.x * s.y) + (c.x * 0.5) + (s.y * c.x * 0.3);
                        float dropShape = saturate(t - 0.5) * (1.0 + shapeDistortion * _DropDistortion);

                        // Calculate irregular normal
                        float2 irregularOffset = float2(
                            c.x * (1.0 + s.y * 0.5),
                            s.x * c.y * 0.5 + c.x * s.y * 0.3
                        ) * _DropDistortion;

                        // FIXED: Explicitly provide all 3 components to float3 constructor
                        float3 v = normalize(-float3(
                            c.x + irregularOffset.x,
                            lerp(0.2, 2.0, dropShape) + irregularOffset.y,
                            0.0  // Third component explicitly set to 0
                        ));

                        // Apply refraction with irregular distortion
                        float2 refractionOffset = v.xy * 0.3;
                        refractionOffset += float2(
                            sin(p.x * 2.0 + _Time.y) * 0.02,
                            cos(p.y * 2.0 + _Time.y) * 0.02
                        ) * _DropDistortion;

                        O = SampleSceneColor(u - refractionOffset);
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

                half3 outRGB = lerp(rainy, cleanTinted, wiper);
                half outAlpha = saturate(_BgTint.a + (1.0 - wiper) * 0.25);

                return half4(outRGB, outAlpha);
            }
            ENDHLSL
        }
    }

    FallBack Off
}