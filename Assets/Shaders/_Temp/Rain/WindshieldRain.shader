Shader "Custom/WindshieldRain"
{
    Properties
    {
        _RainTex ("Rain Normal/Mask (RGB=Normal, A=DropletMask)", 2D) = "bump" {}

        _Tiling1 ("Layer 1 Tiling", Float) = 3.0
        _Speed1 ("Layer 1 Pan Speed (x,y)", Vector) = (0, -0.03, 0, 0)

        _Tiling2 ("Layer 2 Tiling", Float) = 5.5
        _Speed2 ("Layer 2 Pan Speed (x,y)", Vector) = (0.015, -0.05, 0, 0)

        _DistortionStrength ("Refraction Distortion Strength", Range(0,0.05)) = 0.01
        _RainAmount ("Rain Amount (0=dry, 1=downpour)", Range(0,1)) = 1.0

        _SpecColor ("Glint Color", Color) = (1,1,1,1)
        _SpecPower ("Glint Sharpness", Range(1,256)) = 64
        _FresnelPower ("Fresnel Power", Range(0.1,8)) = 3.0

        _TintColor ("Glass Tint", Color) = (0.85, 0.9, 0.95, 0.15)

        // Wiper mask: a simple angular wedge sweeping around a pivot in UV space
        _WiperPivotUV ("Wiper Pivot (UV)", Vector) = (0.5, 0.05, 0, 0)
        _WiperAngle ("Wiper Current Angle (deg)", Range(-90,90)) = 0
        _WiperWidth ("Wiper Blade Width (deg)", Range(1,60)) = 25
        _WiperRadius ("Wiper Reach (UV units)", Float) = 1.2
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }
        LOD 200

        Pass
        {
            Name "WindshieldRain"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // URP exposes the opaque color texture after opaque pass if "Opaque Texture" is
            // enabled in the URP Asset (and Camera Opaque Texture on the camera).
            TEXTURE2D(_CameraOpaqueTexture);
            SAMPLER(sampler_CameraOpaqueTexture);

            TEXTURE2D(_RainTex);
            SAMPLER(sampler_RainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _RainTex_ST;
                float _Tiling1, _Tiling2;
                float2 _Speed1, _Speed2;
                float _DistortionStrength;
                float _RainAmount;
                float4 _SpecColor;
                float _SpecPower;
                float _FresnelPower;
                float4 _TintColor;
                float2 _WiperPivotUV;
                float _WiperAngle;
                float _WiperWidth;
                float _WiperRadius;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float4 screenPos   : TEXCOORD1;
                float3 normalWS    : TEXCOORD2;
                float3 tangentWS   : TEXCOORD3;
                float3 bitangentWS : TEXCOORD4;
                float3 viewDirWS   : TEXCOORD5;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs posInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs normInputs = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);

                OUT.positionHCS = posInputs.positionCS;
                OUT.screenPos = ComputeScreenPos(posInputs.positionCS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _RainTex);
                OUT.normalWS = normInputs.normalWS;
                OUT.tangentWS = normInputs.tangentWS;
                OUT.bitangentWS = normInputs.bitangentWS;
                OUT.viewDirWS = GetWorldSpaceViewDir(posInputs.positionWS);
                return OUT;
            }

            // returns 1 near the wiper blade sweep, 0 elsewhere (soft edge)
            float WiperMask(float2 uv)
            {
                float2 d = uv - _WiperPivotUV;
                float dist = length(d);
                float angle = degrees(atan2(d.y, d.x)); // -180..180, measured from pivot

                float angleDelta = abs(angle - _WiperAngle);
                angleDelta = min(angleDelta, 360.0 - angleDelta);

                float angularMask = 1.0 - smoothstep(_WiperWidth * 0.5 - 4.0, _WiperWidth * 0.5, angleDelta);
                float radialMask = 1.0 - smoothstep(_WiperRadius - 0.05, _WiperRadius, dist);
                return saturate(angularMask * radialMask);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // --- sample two panning layers of the rain texture at different scale/speed ---
                float2 uv1 = IN.uv * _Tiling1 + _Speed1 * _Time.y;
                float2 uv2 = IN.uv * _Tiling2 + _Speed2 * _Time.y;

                half4 rain1 = SAMPLE_TEXTURE2D(_RainTex, sampler_RainTex, uv1);
                half4 rain2 = SAMPLE_TEXTURE2D(_RainTex, sampler_RainTex, uv2);

                // unpack tangent-space normals (RGB, 0..1 -> -1..1)
                float3 n1 = normalize(rain1.rgb * 2.0 - 1.0);
                float3 n2 = normalize(rain2.rgb * 2.0 - 1.0);

                // blend the two layers (average normal, add masks)
                float3 tsNormal = normalize(n1 + n2);
                float dropletMask = saturate(rain1.a * 0.7 + rain2.a * 0.6);

                // fade whole effect in/out with rain amount, and clear it under the wiper
                float wiper = WiperMask(IN.uv);
                float effectMask = dropletMask * _RainAmount * (1.0 - wiper);

                // --- build world-space normal from tangent-space perturbation ---
                float3x3 TBN = float3x3(
                    normalize(IN.tangentWS),
                    normalize(IN.bitangentWS),
                    normalize(IN.normalWS)
                );
                float3 normalWS = normalize(mul(tsNormal, TBN));

                // --- refraction: offset the screen UV using the perturbed normal's tangent-plane component ---
                float2 screenUV = IN.screenPos.xy / IN.screenPos.w;
                float2 refractOffset = tsNormal.xy * _DistortionStrength * effectMask;
                float2 distortedUV = screenUV + refractOffset;

                half3 behindGlass = SAMPLE_TEXTURE2D(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, distortedUV).rgb;

                // subtle glass tint over whatever is behind
                half3 tinted = lerp(behindGlass, behindGlass * _TintColor.rgb, _TintColor.a);

                // --- fresnel + specular glint off the droplet-perturbed normal ---
                float3 viewDir = normalize(IN.viewDirWS);
                float fresnel = pow(1.0 - saturate(dot(normalWS, viewDir)), _FresnelPower);

                Light mainLight = GetMainLight();
                float3 halfDir = normalize(mainLight.direction + viewDir);
                float spec = pow(saturate(dot(normalWS, halfDir)), _SpecPower);

                half3 glint = _SpecColor.rgb * spec * effectMask;
                half3 finalColor = tinted + glint + fresnel * effectMask * 0.05;

                // alpha: mostly see-through, droplets/wiper area very slightly denser
                half alpha = saturate(0.15 + effectMask * 0.1);

                return half4(finalColor, alpha);
            }
            ENDHLSL
        }
    }
}
