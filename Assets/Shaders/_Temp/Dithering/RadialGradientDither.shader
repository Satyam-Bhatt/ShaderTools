
Shader "Custom/RadialGradientDitherHalftone"
{
 Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _InnerRadius ("Solid Radius", Range(0, 0.5)) = 0.15
        _OuterRadius ("Outer Radius (fully faded)", Range(0, 0.5)) = 0.5
        _DitherScale ("Dither Pixel Scale", float) = 1
        [KeywordEnum(Bayer8x8, GradientNoise)] _DitherMode ("Dither Mode", Float) = 0
    }

    SubShader
    {
        // Cutout-style: no real alpha blending, pixels are either drawn or
        // discarded based on a Bayer dither pattern -> classic "dither fade" look.
        Tags { "RenderType"="TransparentCutout" "Queue"="AlphaTest" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _DITHERMODE_BAYER8X8 _DITHERMODE_GRADIENTNOISE
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv     : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv        : TEXCOORD0;
                float4 vertex    : SV_POSITION;
                float4 screenPos : TEXCOORD1;
            };

            fixed4 _Color;
            float _InnerRadius;
            float _OuterRadius;
            float _DitherScale;

            // 8x8 Bayer matrix, values 0-63.
            // Denser and less visibly repetitive than 4x4 (tiles every 8px instead of every 4px).
            static const float bayer8x8[64] =
            {
                 0, 32,  8, 40,  2, 34, 10, 42,
                48, 16, 56, 24, 50, 18, 58, 26,
                12, 44,  4, 36, 14, 46,  6, 38,
                60, 28, 52, 20, 62, 30, 54, 22,
                 3, 35, 11, 43,  1, 33,  9, 41,
                51, 19, 59, 27, 49, 17, 57, 25,
                15, 47,  7, 39, 13, 45,  5, 37,
                63, 31, 55, 23, 61, 29, 53, 21
            };

            // Interleaved gradient noise (Jorge Jimenez, "Next Generation Post
            // Processing in Call of Duty: Advanced Warfare"). No fixed tiling
            // like Bayer, so it reads as much less repetitive/patterned.
            float gradientNoise(float2 pixelPos)
            {
                const float3 magic = float3(0.06711056, 0.00583715, 52.9829189);
                return frac(magic.z * frac(dot(pixelPos, magic.xy)));
            }

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                o.screenPos = ComputeScreenPos(o.vertex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // UV assumed 0-1 across the quad, circle centered at (0.5, 0.5)
                float2 centered = i.uv - 0.5;
                float dist = length(centered);

                // Fully solid inside _InnerRadius, gradient falloff to _OuterRadius
                float alpha = 1.0 - saturate((dist - _InnerRadius) / max(_OuterRadius - _InnerRadius, 0.0001));

                // Discard anything past the outer radius entirely
                clip(_OuterRadius - dist);

                // Compute a stable screen-space pixel coordinate for the dither pattern
                float2 screenUV = i.screenPos.xy / i.screenPos.w;
                float2 pixelPos = screenUV * _ScreenParams.xy / _DitherScale;

                float threshold;
                #if defined(_DITHERMODE_GRADIENTNOISE)
                    threshold = gradientNoise(pixelPos);
                #else
                    int x = fmod(pixelPos.x, 8);
                    int y = fmod(pixelPos.y, 8);
                    threshold = bayer8x8[y * 8 + x] / 64.0;
                #endif

                // Pixel survives only if the gradient alpha beats the dither threshold.
                // Near the center alpha=1 -> always survives (solid).
                // Near the edge alpha->0 -> fewer and fewer pixels survive (dithered fade).
                clip(alpha - threshold);

                return _Color;
            }
            ENDCG
        }
    }

    FallBack "Transparent/Cutout/VertexLit"
}
