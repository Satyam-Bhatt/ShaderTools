Shader "Custom/RainFalling"
{
    // REQUIRES _CameraOpaqueTexture
    Properties
    {
        _MainTex        ("Rain Texture (Alpha = height mask)", 2D) = "white" {}
        _Color          ("Streak Tint / Opacity", Color) = (0.9, 0.92, 0.95, 0.9)
        _BgTint         ("Glass Tint", Color) = (0.4, 0.5, 0.45, 0.35)
        _Tiling         ("Tiling (X, Y)", Vector) = (1, 1, 0, 0)
        _ScrollSpeed    ("Scroll Speed (X, Y)", Vector) = (0, -1.5, 0, 0)
        _BulgeStrength  ("Bulge", Range(0, 0.2)) = 0.03
        _Specular       ("Highlight Strength", float) = 1.5
        _Shininess      ("Highlight Sharpness", float) = 32
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
            Name "RainBulge"

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0 

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

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
                float3 positionWS  : TEXCOORD2; // OPTIONAL
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS);
                OUT.positionWS  = TransformObjectToWorld(IN.positionOS); // OPTIONAL

                float2 uv = IN.uv * _Tiling.xy;
                uv += _ScrollSpeed.xy * _Time.y;
                OUT.uv = uv;

                OUT.screenPos = ComputeScreenPos(OUT.positionHCS); // Remap -w,w to 0,w
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                half drop = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv).a;

                // Normal from height
                half2 grad = half2(ddx(drop), ddy(drop));
                // Grad is negative as normal leans away from the direction of increasing height
                half3 normal = normalize(half3(-grad * _BulgeStrength * 40.0, 1.0)); // Multiplier can make it crazy

                // Refract
                float2 screenUV = IN.screenPos.xy / IN.screenPos.w; // Perspective divide to make it 0-1
                float2 distortedUV = screenUV + normal.xy * _BulgeStrength;// * drop; // Comment drop in if need to make it a bit more subtle
                half3 bgColor = SampleSceneColor(distortedUV);

                //Specular
                Light mainLight = GetMainLight(); //OPTIONAL
                half3 L = mainLight.direction; //OPTIONAL  
                half3 V = GetWorldSpaceNormalizeViewDir(IN.positionWS); //OPTIONAL
                half3 H = normalize(V+L); //OPTIONAL

                half3 lightDir = normalize(half3(0.3, 0.5, 0.8));
                half  NdotL = saturate(dot(normal, lightDir));
                //half  NdotL = saturate(dot(normal, H));
                half  spec = pow(NdotL, _Shininess) * _Specular * drop;

                // Glass with Drops
                half3 tintedBg = lerp(bgColor, _BgTint.rgb, _BgTint.a);
                half3 outRGB   = tintedBg + spec * _Color.rgb;

                // Darker wet section
                // Porter-Duff "over" operator a + b * (1 - a)
                half outAlpha = saturate(_BgTint.a + drop * _Color.a * (1.0 - _BgTint.a));

                return half4(outRGB, outAlpha);
            }
            ENDHLSL
        }
    }

    FallBack Off
}
