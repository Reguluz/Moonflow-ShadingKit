Shader"Moonflow/CelBase"
{
    Properties
    {
        [Header(Base)]
        _BaseColor("Color", Color) = (1,1,1,1)
        _DiffuseTex ("Diffuse Tex", 2D) = "white" {}
        _NormalTex("Normal Tex", 2D) = "bump" {}
        _PBSTex("Data Tex", 2D) = "black" {}
        _BaseTex_ST("TileOffset", Vector) = (1,1,0,0)
        
        _SelfShadowStr("Self Shadow Str", Range(0,1)) = 0.75
        _LitEdgeBandWidth("Lit Edge BandWidth", Range(0.001,1))=0.15
        _LitIndirectAtten("Lit Indirect Atten",Range(0,1)) = 0.5
        _EnvironmentEffect("EnvironmentEffect", Range(0,1)) = .2
        
        [Header(Rim)]
        [HDR]_RimColor("Rim Color", Color) = (0.7,0.2,0.17,1)
        _RimFalloff("Rim Falloff", Range(0,10)) = 2
        
        [Header(Mask)]
        _MaskTex("Mask Tex", 2D) = "black" {}
        [Header(Face)]
        [Toggle(MF_CEL_FACESDF_ON)]_FaceSDF("Face SDF", Float) = 0
        
        [Header(Stocking)]
        [Toggle(MF_CEL_STOCKING_ON)]_Stocking("Stocking", Float) = 0
        _NormalStr("NormalStr", Float) = 1.5
        _FresnelRatio("FresnelRatio", Range(0,1)) = 1
        _FresnelStart("FresnelStart", Range(0,1)) = 0.5
        [HDR]_StockingColor("StockingColor", Color) = (0,0,0,1)
        
        
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            Name "Base"
            HLSLPROGRAM
            #include "Library/MFBase.hlsl"
            #include "Library/MFCelLighting.hlsl"
            #include "Library/MFCelGI.hlsl"
            #pragma shader_feature MF_CEL_FACESDF_ON
            #pragma shader_feature MF_CEL_STOCKING_ON
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma vertex vert
            #pragma fragment frag

            Texture2D _DiffuseTex;
            SamplerState sampler_DiffuseTex;

            Texture2D _NormalTex;
            SamplerState sampler_NormalTex;

            Texture2D _PBSTex;
            SamplerState sampler_PBSTex;

            Texture2D _MaskTex;
            SamplerState sampler_MaskTex;
            float4 _MaskTex_ST;

            UNITY_INSTANCING_BUFFER_START(UnityPerMaterial)
                UNITY_DEFINE_INSTANCED_PROP(float4, _BaseTex_ST)
                UNITY_DEFINE_INSTANCED_PROP(float4, _BaseColor)
            
                UNITY_DEFINE_INSTANCED_PROP(float, _SelfShadowStr)
                UNITY_DEFINE_INSTANCED_PROP(float, _LitEdgeBandWidth)
                UNITY_DEFINE_INSTANCED_PROP(float, _LitIndirectAtten)
                UNITY_DEFINE_INSTANCED_PROP(float, _EnvironmentEffect)
            
                UNITY_DEFINE_INSTANCED_PROP(float4, _RimColor)
                UNITY_DEFINE_INSTANCED_PROP(float, _RimFalloff)
            
                UNITY_DEFINE_INSTANCED_PROP(float, _NormalStr)
                UNITY_DEFINE_INSTANCED_PROP(float, _FresnelRatio)
                UNITY_DEFINE_INSTANCED_PROP(float, _FresnelStart)
                UNITY_DEFINE_INSTANCED_PROP(float3, _StockingColor)
            
            UNITY_INSTANCING_BUFFER_END(UnityPerMaterial)

            float3 CelColorMix(float3 color1, float3 color2)
            {
                return max(color1, color2) * min(color1, color2);
            }
            float3 CelColorGradient(float3 color1, float3 color2, float per)
            {
                return lerp(color1, color2, per) + CelColorMix(color1, color2) * saturate( 1-abs(per * 2 - 1));
            }

            float SDFFace(float3 lightDir, float3 forward, float2 uv)
            {
                float LR = cross(forward, -lightDir).y;
                // 左右翻转
                float2 flipUV = float2(1 - uv.x, uv.y);
                float lightMapL = SAMPLE_TEXTURE2D(_MaskTex, sampler_MaskTex, uv).r;
                float lightMapR = SAMPLE_TEXTURE2D(_MaskTex, sampler_MaskTex, flipUV).r;

                float lightMap = LR > 0 ? lightMapL : lightMapR;
                lightDir.y = 0;
                forward.y = 0;
                float s = dot(-lightDir, forward);
                return saturate(step(lightMap , s ));
            }

             half Fabric(half NdV)
            {
                half intensity = 1 - NdV;
                intensity = 0 - (intensity * 0.4 - pow(intensity, _RimFalloff) ) * 0.35;
                return saturate(intensity);
            }
            half StockingAlpha(half weavingMask, half NdV, half2 uv)
            {
                half rNdV = NdV * NdV;
                half rim = saturate(((1 - clamp(rNdV, 0, 1) ) * _FresnelRatio + _FresnelStart));
                rim = clamp(rim,0, 1);
                half mask = rNdV * weavingMask;
                mask = rim - mask * rim;
                return saturate(mask);
            }
            
            float3 Curve(float3 color, float k)
            {
	            return exp(log(max(color, int3(0, 0, 0))) * k);
            }

            float3 StockingDiffuse(float3 baseColor, float2 uv, MFMatData matData, MFLightData lightData)
            {
                float ndv = saturate(dot(matData.normalWS, -normalize(matData.viewDirWS)));
                half weaveMask = max(0, SAMPLE_TEXTURE2D(_MaskTex, sampler_MaskTex, uv * _MaskTex_ST.xy + _MaskTex_ST.zw) * _NormalStr);
                half shade = lerp(0, lightData.NdL * 0.5 + 0.5, lightData.shadowAtten);
                half stockingFabric = Fabric(ndv) * clamp(shade, 0.5, 1);
                half stockingAlpha = StockingAlpha(weaveMask, ndv, uv);
                half highlight = saturate(1-stockingAlpha) * half4(Curve(ndv.xxx,15),1);
                baseColor = baseColor * (1-stockingAlpha)+_StockingColor * stockingAlpha + highlight*0.05;
                return lerp(baseColor, _RimColor, saturate(stockingFabric));
            }
            
            MFLightData EditLightingData(MFLightData ld, float2 uv)
            {
                ld.shadowAtten = ld.shadowAtten * _SelfShadowStr + 1 - _SelfShadowStr;
                #ifdef MF_CEL_FACESDF_ON
                ld.lightAtten = SDFFace(ld.lightDir, -unity_ObjectToWorld._m20_m21_m22, uv);
                #endif
                ld.lightAtten = ld.lightAtten / _LitEdgeBandWidth + _LitEdgeBandWidth;
                ld.lightAtten = smoothstep(0,1,ld.lightAtten);
                ld.lightAtten = lerp(0, ld.lightAtten, _LitIndirectAtten);
                return ld;
            }


            void MFCelRampLight(BaseVarying i, MFMatData matData, MFLightData lightData, out float3 diffuse, out float3 specular, out float3 GI)
            {
                float shadow = CelShadow(i.posWS, i.normalWS, lightData.lightDir, lightData.shadowAtten);

                diffuse = matData.diffuse;
                #ifdef MF_CEL_STOCKING_ON
                diffuse = StockingDiffuse(diffuse, i.uv, matData, lightData);
                #endif
                
                specular = GetSpecular(i.normalWS, matData, lightData);
                GI = SAMPLE_GI(i.lightmapUV, i.vertexSH, i.normalWS);
            }

            
            half4 frag (BaseVarying i) : SV_Target
            {
                float2 realUV = i.uv * _BaseTex_ST.xy + _BaseTex_ST.zw;
                float4 diffuseTex = SAMPLE_TEXTURE2D(_DiffuseTex, sampler_DiffuseTex, realUV);
                float4 normalTex = SAMPLE_TEXTURE2D(_NormalTex, sampler_NormalTex, realUV);
                float4 pbsTex = SAMPLE_TEXTURE2D(_PBSTex, sampler_PBSTex, realUV);
                
                //MFMatData
                MFMatData matData = GetMatData(i, diffuseTex.rgb * _BaseColor, diffuseTex.a, normalTex.rg, pbsTex.r, pbsTex.g, pbsTex.b, normalTex.b);
                MFLightData ld = GetLightingData(i, matData);
                
                ld = EditLightingData(ld, i.uv);
                
                float3 diffuse;
                float3 specular;
                float3 GI;
                MFCelRampLight(i, matData, ld, diffuse, specular, GI);
                float4 color = matData.alpha;
                color.rgb = diffuse * lerp(1, GI, _EnvironmentEffect) + specular;
                color.rgb += diffuse * ld.lightAtten * ld.lightColor;
                return color;
            }
            ENDHLSL
        }
        
        Pass
        {
            Name "ShadowCaster"
            Tags{"LightMode" = "ShadowCaster"}

            ZWrite On
            ZTest LEqual
            Cull[_Cull]

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature _ALPHATEST_ON

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags{"LightMode" = "DepthOnly"}

            ZWrite On
            ColorMask 0
            Cull[_Cull]

            HLSLPROGRAM
            // Required to compile gles 2.0 with standard srp library
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 2.0

            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature _ALPHATEST_ON
            #pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }
    }
}
