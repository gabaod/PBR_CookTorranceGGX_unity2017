// =====================================================================================
// PBR_CookTorranceGGX.shader
// Custom Cook-Torrance (GGX/Trowbridge-Reitz NDF, Smith height-correlated visibility,
// Schlick Fresnel) metallic-workflow PBR shader for Unity 2017.4.9f1 (Built-in RP, Forward only).
//
// Built for: Descenders (Unity 2017.4.9f1, Player Settings Color Space = GAMMA).
//
// -------------------------------------------------------------------------------------
// TEXTURE IMPORT CHECKLIST (read this before assigning textures in the Inspector!)
// -------------------------------------------------------------------------------------
//   Albedo Map    -> Texture Type: Default, sRGB (Color Texture) = CHECKED
//   Emission Map  -> Texture Type: Default, sRGB (Color Texture) = CHECKED
//   Normal Map    -> Texture Type: Normal Map (Unity will set sRGB unchecked for you)
//   Occlusion Map -> Texture Type: Default, sRGB (Color Texture) = UNCHECKED (it's data, not color)
//   Roughness Map -> Texture Type: Default, sRGB (Color Texture) = UNCHECKED
//   Metallic Map  -> Texture Type: Default, sRGB (Color Texture) = UNCHECKED
//   Height Map    -> Texture Type: Default, sRGB (Color Texture) = UNCHECKED
//
//   Getting sRGB wrong on Albedo/Emission will make them look washed out or too dark.
//   Getting sRGB CHECKED on any of the data maps (normal/occlusion/roughness/metallic/
//   height) will silently corrupt the values the math reads - always double check.
// -------------------------------------------------------------------------------------
//
// NOTES ON DESIGN CHOICES (see chat for full reasoning):
//  - Metallic workflow, Cook-Torrance specular = D * Vis * F  (Vis already folds in the
//    1/(4*NdotL*NdotV) term - this is the Smith-GGX height-correlated visibility form).
//  - Dielectric F0 ("Specular Level") is an exposed slider instead of the usual hardcoded
//    0.04, per your request.
//  - All secondary maps (normal/occlusion/roughness/metallic/height/emission) share ONE
//    Tiling/Offset (_MainTex_ST), driven by the Albedo map's tiling/offset fields.
//  - Height map drives real Parallax Occlusion Mapping (POM) with optional self-shadowing
//    and optional silhouette clamp/fade to hide grazing-angle swimming artifacts.
//  - _LINEARPBR_ON is a shader_feature (compile-time, zero runtime cost either way).
//    OFF (default) = do the lighting math directly in gamma-space values, matching how
//    the rest of a Gamma-color-space project (like Descenders) renders.
//    ON = manually linearize inputs before lighting and re-gamma-encode the output,
//    which is closer to "textbook correct" PBR but will look different from the rest
//    of the game's gamma-space rendering. Pick ON only if you specifically want that.
//  - Most "Use X Map" toggles are shader_feature keywords (not runtime branches), so
//    unused code paths (and unused texture samples) are compiled out entirely. Because
//    shader_feature only builds the variants your actual materials use, this stays cheap
//    even though there are many keywords - just be aware that using ALL combinations
//    across many different materials will grow your build's shader variant count.
// =====================================================================================

Shader "Custom/PBR_CookTorranceGGX"
{
    Properties
    {
        [Header(Albedo)]
        _Color("Albedo Tint (RGBA)", Color) = (1,1,1,1)
        [Toggle(_ALBEDOMAP_ON)] _UseAlbedoMap("Use Albedo Map", Float) = 0
        _MainTex("Albedo (RGB) Alpha (A)", 2D) = "white" {}

        [Header(Vertex Color)]
        [Toggle(_VERTEXCOLOR_ON)] _UseVertexColor("Multiply Vertex Color into Albedo", Float) = 0

        [Header(Normal Map)]
        [Toggle(_NORMALMAP_ON)] _UseNormalMap("Use Normal Map", Float) = 0
        [NoScaleOffset][Normal] _BumpMap("Normal Map", 2D) = "bump" {}
        _BumpScale("Normal Scale", Range(0, 4)) = 1

        [Header(Occlusion Map)]
        [Toggle(_OCCLUSIONMAP_ON)] _UseOcclusionMap("Use Occlusion Map", Float) = 0
        [NoScaleOffset] _OcclusionMap("Occlusion Map (R)", 2D) = "white" {}
        _OcclusionStrength("Occlusion Strength", Range(0, 1)) = 1

        [Header(Roughness Map)]
        [Toggle(_ROUGHNESSMAP_ON)] _UseRoughnessMap("Use Roughness Map", Float) = 0
        [NoScaleOffset] _RoughnessMap("Roughness Map (R)", 2D) = "gray" {}
        _Roughness("Roughness", Range(0.03, 1)) = 0.5
        [Toggle(_INVERTROUGHNESS_ON)] _InvertRoughness("Invert Roughness (map is actually Smoothness)", Float) = 0

        [Header(Metallic Map)]
        [Toggle(_METALLICMAP_ON)] _UseMetallicMap("Use Metallic Map", Float) = 0
        [NoScaleOffset] _MetallicMap("Metallic Map (R)", 2D) = "black" {}
        _Metallic("Metallic", Range(0, 1)) = 0.0
        _SpecularLevel("Specular Level (Dielectric F0)", Range(0, 1)) = 0.04

        [Header(Height Map Parallax Occlusion Mapping)]
        [Toggle(_HEIGHTMAP_ON)] _UseHeightMap("Use Height Map", Float) = 0
        [NoScaleOffset] _HeightMap("Height Map (R)", 2D) = "black" {}
        _HeightScale("Height Scale", Range(0, 0.2)) = 0.02
        _POMMinSamples("POM Min Samples", Range(1, 64)) = 8
        _POMMaxSamples("POM Max Samples", Range(1, 128)) = 32
        [Toggle(_POMSELFSHADOW_ON)] _POMSelfShadow("POM Self-Shadowing", Float) = 0
        _POMShadowSoftening("POM Shadow Softening", Range(0.1, 4)) = 1
        [Toggle(_POMSILHOUETTECLAMP_ON)] _POMSilhouetteClamp("POM Silhouette Clamp/Fade", Float) = 1

        [Header(Emission)]
        [Toggle(_EMISSIONMAP_ON)] _UseEmissionMap("Use Emission Map", Float) = 0
        [NoScaleOffset] _EmissionMap("Emission Map", 2D) = "black" {}
        [HDR] _EmissionColor("Emission Color", Color) = (0,0,0,1)

        [Header(Lighting Math)]
        [Toggle(_LINEARPBR_ON)] _LinearPBR("Linear-space lighting math (off = Gamma, matches Descenders)", Float) = 0

        [Header(Rendering Options)]
        [Enum(Opaque,0,Cutout,1,Transparent,2)] _RenderMode("Render Mode", Float) = 0
        _Cutoff("Alpha Cutoff", Range(0, 1)) = 0.5
        [Toggle] _AlphaToMask("Alpha To Coverage (Cutout MSAA edges)", Float) = 0
        [Enum(UnityEngine.Rendering.CullMode)] _Cull("Cull Mode (2=Back/default, 1=Front, 0=Off/double-sided)", Float) = 2

        // ---- internal, driven by the custom ShaderGUI based on Render Mode ----
        [HideInInspector] _SrcBlend("__src", Float) = 1
        [HideInInspector] _DstBlend("__dst", Float) = 0
        [HideInInspector] _ZWrite("__zw", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "Queue" = "Geometry" }
        LOD 300
        Cull [_Cull]

        CGINCLUDE
        // =================================================================
        // Shared code used by ForwardBase and ForwardAdd passes.
        // =================================================================
        #include "UnityCG.cginc"
        #include "Lighting.cginc"
        #include "AutoLight.cginc"

        #define PI      3.14159265359
        #define INV_PI  0.31830988618

        // ---- uniforms ----
        sampler2D _MainTex;        float4 _MainTex_ST;
        sampler2D _BumpMap;
        sampler2D _OcclusionMap;
        sampler2D _RoughnessMap;
        sampler2D _MetallicMap;
        sampler2D _HeightMap;
        sampler2D _EmissionMap;

        half    _BumpScale;
        half    _OcclusionStrength;
        half    _Roughness;
        half    _Metallic;
        half    _SpecularLevel;
        half    _HeightScale;
        half    _POMMinSamples;
        half    _POMMaxSamples;
        half    _POMShadowSoftening;
        half4   _EmissionColor;
        half    _Cutoff;

        struct appdata
        {
            float4 vertex   : POSITION;
            float3 normal   : NORMAL;
            float4 tangent  : TANGENT;
            float2 uv       : TEXCOORD0;
            float4 color    : COLOR;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        // NOTE: v2f, vert(), and GetSurfaceData() are intentionally NOT here.
        // See the duplicated copy inside the ForwardBase and ForwardAdd passes below
        // for why (SHADOW_COORDS is not safe to share with the ShadowCaster pass).

        // Per-instance albedo tint so GPU-instanced batches can still vary color
        // (e.g. different mod variants / MaterialPropertyBlock colors) while batching.
        UNITY_INSTANCING_BUFFER_START(PerInstanceProps)
            UNITY_DEFINE_INSTANCED_PROP(fixed4, _Color)
        UNITY_INSTANCING_BUFFER_END(PerInstanceProps)


        // -----------------------------------------------------------------
        // Parallax Occlusion Mapping
        // Returns the displaced UV. If self-shadowing is enabled, also
        // writes an approximate shadow attenuation factor into `shadowOut`.
        // -----------------------------------------------------------------
        float SampleHeight(float2 uv)
        {
            return tex2D(_HeightMap, uv).r;
        }

        // Returns the parallax-displaced UV. Self-shadowing (if enabled) is computed
        // separately by POMSelfShadow() below, once the caller knows the tangent-space
        // light direction for whichever light this pass is lighting.
        float2 ParallaxOcclusionMap(float2 uv, float3 viewDirTS, float NdotVforFade)
        {
#if defined(_HEIGHTMAP_ON)
            float3 viewDir = normalize(viewDirTS);

            // Fewer steps when looking straight on, more steps at grazing angles.
            float numSteps = lerp(_POMMaxSamples, _POMMinSamples, saturate(viewDir.z));
            float stepSize = 1.0 / numSteps;

            float2 maxOffset = (viewDir.xy / max(viewDir.z, 0.05)) * _HeightScale;

#if defined(_POMSILHOUETTECLAMP_ON)
            float silhouetteFade = saturate(NdotVforFade * 3.0);
            maxOffset *= silhouetteFade;
#endif

            float2 deltaUV = maxOffset * stepSize;

            float2 curUV = uv;
            float curRayHeight = 1.0;
            float curSampledHeight = SampleHeight(curUV);

            float2 prevUV = curUV;
            float prevRayHeight = curRayHeight;
            float prevSampledHeight = curSampledHeight;

            // Linear search for the first intersection between the ray and the heightfield.
            [loop]
            for (int i = 0; i < 128; i++)
            {
                if (i >= (int)numSteps) break;
                if (curSampledHeight > curRayHeight) break;

                prevUV = curUV;
                prevRayHeight = curRayHeight;
                prevSampledHeight = curSampledHeight;

                curUV -= deltaUV;
                curRayHeight -= stepSize;
                curSampledHeight = SampleHeight(curUV);
            }

            // Binary-search style linear interpolation refinement between the last two samples.
            float denom = (prevSampledHeight - prevRayHeight) - (curSampledHeight - curRayHeight);
            float t = (denom != 0.0) ? ((prevSampledHeight - prevRayHeight) / denom) : 0.0;
            t = saturate(t);
            float2 finalUV = lerp(prevUV, curUV, t);

            return finalUV;
#else
            return uv;
#endif
        }

        // Soft self-shadow raymarch given an already-displaced UV and a tangent-space light dir.
        float POMSelfShadow(float2 uv, float3 lightDirTS)
        {
#if defined(_HEIGHTMAP_ON) && defined(_POMSELFSHADOW_ON)
            float3 lightDir = normalize(lightDirTS);
            if (lightDir.z <= 0.001) return 1.0;

            float startHeight = SampleHeight(uv);
            float shadowMultiplier = 1.0;
            float numSamples = lerp(_POMMinSamples, _POMMaxSamples, 0.5);
            float stepSize = 1.0 / numSamples;
            float2 texStep = (lightDir.xy / max(lightDir.z, 0.05)) * _HeightScale * stepSize;

            float rayHeight = startHeight + 0.001;
            float2 rayUV = uv;
            float minVisibility = 1.0;

            [loop]
            for (int i = 1; i < 64; i++)
            {
                if (i >= (int)numSamples) break;
                rayUV += texStep;
                rayHeight += stepSize;
                if (rayHeight >= 1.0) break;

                float sampledHeight = SampleHeight(rayUV);
                float delta = sampledHeight - rayHeight;
                if (delta > 0.0)
                {
                    float visibility = (1.0 - rayHeight) / max(delta, 0.0001);
                    minVisibility = min(minVisibility, saturate(visibility * _POMShadowSoftening));
                }
            }
            return minVisibility;
#else
            return 1.0;
#endif
        }

        // -----------------------------------------------------------------
        // Cook-Torrance BRDF pieces: GGX distribution, Smith (height-correlated)
        // visibility term, Schlick Fresnel.
        // -----------------------------------------------------------------
        float D_GGX(float NdotH, float roughness)
        {
            float alpha  = roughness * roughness;
            float alpha2 = alpha * alpha;
            float d = (NdotH * NdotH) * (alpha2 - 1.0) + 1.0;
            return alpha2 / max(PI * d * d, 1e-7);
        }

        // Smith joint masking-shadowing (height-correlated), already divided by 4*NdotL*NdotV.
        float V_SmithGGXCorrelated(float NdotL, float NdotV, float roughness)
        {
            float alpha  = roughness * roughness;
            float alpha2 = alpha * alpha;
            float ggxV = NdotL * sqrt(NdotV * NdotV * (1.0 - alpha2) + alpha2);
            float ggxL = NdotV * sqrt(NdotL * NdotL * (1.0 - alpha2) + alpha2);
            return 0.5 / max(ggxV + ggxL, 1e-5);
        }

        float3 F_Schlick(float VdotH, float3 F0)
        {
            float m  = saturate(1.0 - VdotH);
            float m2 = m * m;
            float m5 = m2 * m2 * m;
            return F0 + (1.0 - F0) * m5;
        }

        // Karis' analytic environment-BRDF approximation (used for IBL specular, avoids a LUT).
        float3 EnvBRDFApprox(float3 F0, float roughness, float NdotV)
        {
            const float4 c0 = float4(-1.0, -0.0275, -0.572, 0.022);
            const float4 c1 = float4(1.0, 0.0425, 1.04, -0.04);
            float4 r = roughness * c0 + c1;
            float a004 = min(r.x * r.x, exp2(-9.28 * NdotV)) * r.x + r.y;
            float2 AB = float2(-1.04, 1.04) * a004 + r.zw;
            return F0 * AB.x + AB.y;
        }

        float3 LinearizeColor(float3 c)
        {
#if defined(_LINEARPBR_ON)
            return pow(max(c, 0.0), 2.2);
#else
            return c;
#endif
        }

        float3 GammaEncodeOutput(float3 c)
        {
#if defined(_LINEARPBR_ON)
            return pow(max(c, 0.0), 1.0 / 2.2);
#else
            return c;
#endif
        }

        // -----------------------------------------------------------------
        // Shared surface-data gathering (used by both lit passes).
        // -----------------------------------------------------------------
        struct SurfaceData
        {
            float3 albedo;
            float  alpha;
            float3 worldNormal;
            float3 worldPos;
            float  roughness;
            float  metallic;
            float  occlusion;
            float3 emission;
            float2 uv;
            float  pomShadow;
        };

        // NOTE: GetSurfaceData() is intentionally NOT here - see the duplicated
        // copy inside the ForwardBase and ForwardAdd passes below.

        // -----------------------------------------------------------------
        // Cook-Torrance direct lighting for one light.
        // -----------------------------------------------------------------
        float3 CookTorranceDirect(SurfaceData s, float3 worldViewDir, float3 lightDir, float3 lightColor, float shadowAtten)
        {
            float3 N = s.worldNormal;
            float3 V = worldViewDir;
            float3 L = lightDir;
            float3 H = normalize(V + L);

            float NdotL = saturate(dot(N, L));
            float NdotV = max(dot(N, V), 1e-4);
            float NdotH = saturate(dot(N, H));
            float VdotH = saturate(dot(V, H));

            if (NdotL <= 0.0) return 0;

            float3 F0 = lerp(float3(_SpecularLevel, _SpecularLevel, _SpecularLevel), s.albedo, s.metallic);

            float  D = D_GGX(NdotH, s.roughness);
            float  Vis = V_SmithGGXCorrelated(NdotL, NdotV, s.roughness);
            float3 F = F_Schlick(VdotH, F0);

            float3 specular = D * Vis * F;

            float3 kd = (1.0 - F) * (1.0 - s.metallic);
            float3 diffuse = kd * s.albedo * INV_PI;

            float3 radiance = lightColor * NdotL * shadowAtten;
            return (diffuse + specular) * radiance;
        }

        // -----------------------------------------------------------------
        // Ambient / image-based lighting (spherical-harmonics diffuse + reflection probe specular).
        // -----------------------------------------------------------------
        float3 AmbientIBL(SurfaceData s, float3 worldViewDir)
        {
            float3 N = s.worldNormal;
            float NdotV = max(dot(N, worldViewDir), 1e-4);

            float3 F0 = lerp(float3(_SpecularLevel, _SpecularLevel, _SpecularLevel), s.albedo, s.metallic);

            // Indirect diffuse from light probes / ambient SH.
            float3 indirectDiffuse = ShadeSH9(float4(N, 1.0)) * s.albedo * (1.0 - s.metallic);

            // Indirect specular from the nearest reflection probe.
            float3 reflDir = reflect(-worldViewDir, N);
            float perceptualRoughness = s.roughness;
            float mip = perceptualRoughness * (1.7 - 0.7 * perceptualRoughness) * UNITY_SPECCUBE_LOD_STEPS;
            half4 envSample = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflDir, mip);
            float3 envColor = DecodeHDR(envSample, unity_SpecCube0_HDR);

            float3 envBRDF = EnvBRDFApprox(F0, perceptualRoughness, NdotV);
            float3 indirectSpecular = envColor * envBRDF;

            // Occlusion applied to BOTH indirect diffuse and indirect specular.
            return (indirectDiffuse + indirectSpecular) * s.occlusion;
        }
        ENDCG

        // =================================================================
        // Pass 1: ForwardBase - main directional light + ambient/IBL + emission
        // =================================================================
        Pass
        {
            Name "FORWARD_BASE"
            Tags { "LightMode" = "ForwardBase" }
            Blend [_SrcBlend] [_DstBlend]
            ZWrite [_ZWrite]
            AlphaToMask [_AlphaToMask]

            CGPROGRAM
            #pragma target 4.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdbase
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #pragma shader_feature_local _ALBEDOMAP_ON
            #pragma shader_feature_local _VERTEXCOLOR_ON
            #pragma shader_feature_local _NORMALMAP_ON
            #pragma shader_feature_local _OCCLUSIONMAP_ON
            #pragma shader_feature_local _ROUGHNESSMAP_ON
            #pragma shader_feature_local _INVERTROUGHNESS_ON
            #pragma shader_feature_local _METALLICMAP_ON
            #pragma shader_feature_local _HEIGHTMAP_ON
            #pragma shader_feature_local _POMSELFSHADOW_ON
            #pragma shader_feature_local _POMSILHOUETTECLAMP_ON
            #pragma shader_feature_local _EMISSIONMAP_ON
            #pragma shader_feature_local _LINEARPBR_ON
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local _ALPHABLEND_ON

            // ---- Lit-pass-only types/functions (deliberately NOT in the shared
            // CGINCLUDE): v2f uses SHADOW_COORDS()/light-attenuation macros that are
            // only meaningful for ForwardBase/ForwardAdd. If this lived in the shared
            // CGINCLUDE it would also get pasted into the ShadowCaster pass below and
            // fail to compile under that pass's own SHADOWS_DEPTH/SHADOWS_CUBE keywords. ----
            struct v2f
            {
                float4 pos          : SV_POSITION;
                float4 uv           : TEXCOORD0; // xy = main uv, zw = spare
                float4 tspace0      : TEXCOORD1; // tangent.x,   bitangent.x, normal.x, worldPos.x
                float4 tspace1      : TEXCOORD2; // tangent.y,   bitangent.y, normal.y, worldPos.y
                float4 tspace2      : TEXCOORD3; // tangent.z,   bitangent.z, normal.z, worldPos.z
                float3 viewDirTS    : TEXCOORD4; // tangent-space view dir, for POM
                fixed4 color        : TEXCOORD5;
                UNITY_FOG_COORDS(6)
                SHADOW_COORDS(7)
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            v2f vert(appdata v)
            {
                v2f o;
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.pos = UnityObjectToClipPos(v.vertex);
                float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;

                float3 worldNormal  = UnityObjectToWorldNormal(v.normal);
                float3 worldTangent = UnityObjectToWorldDir(v.tangent.xyz);
                float tangentSign   = v.tangent.w * unity_WorldTransformParams.w;
                float3 worldBitangent = cross(worldNormal, worldTangent) * tangentSign;

                o.tspace0 = float4(worldTangent.x, worldBitangent.x, worldNormal.x, worldPos.x);
                o.tspace1 = float4(worldTangent.y, worldBitangent.y, worldNormal.y, worldPos.y);
                o.tspace2 = float4(worldTangent.z, worldBitangent.z, worldNormal.z, worldPos.z);

                o.uv.xy = TRANSFORM_TEX(v.uv, _MainTex);
                o.uv.zw = 0;

                // View direction in tangent space, for parallax occlusion mapping.
                float3 viewDirWS = _WorldSpaceCameraPos - worldPos;
                float3x3 worldToTangent = float3x3(worldTangent, worldBitangent, worldNormal);
                o.viewDirTS = mul(worldToTangent, viewDirWS);

                o.color = v.color;

                UNITY_TRANSFER_FOG(o, o.pos);
                TRANSFER_SHADOW(o);

                return o;
            }

            SurfaceData GetSurfaceData(v2f i)
            {
                SurfaceData s;
                UNITY_INITIALIZE_OUTPUT(SurfaceData, s);

                float3 worldPos = float3(i.tspace0.w, i.tspace1.w, i.tspace2.w);
                float3 worldTangent   = float3(i.tspace0.x, i.tspace1.x, i.tspace2.x);
                float3 worldBitangent = float3(i.tspace0.y, i.tspace1.y, i.tspace2.y);
                float3 worldNormalGeom = normalize(float3(i.tspace0.z, i.tspace1.z, i.tspace2.z));

                float NdotVGeom = saturate(dot(worldNormalGeom, normalize(_WorldSpaceCameraPos - worldPos)));

                float2 uv = i.uv.xy;
                s.pomShadow = 1.0;
#if defined(_HEIGHTMAP_ON)
                uv = ParallaxOcclusionMap(uv, i.viewDirTS, NdotVGeom);
#endif
                s.uv = uv;

                // ---- albedo ----
                fixed4 albedoTex = fixed4(1,1,1,1);
#if defined(_ALBEDOMAP_ON)
                albedoTex = tex2D(_MainTex, uv);
#endif
                fixed4 tint = UNITY_ACCESS_INSTANCED_PROP(PerInstanceProps, _Color);
                fixed4 albedoColor = albedoTex * tint;

#if defined(_VERTEXCOLOR_ON)
                albedoColor.rgb *= i.color.rgb;
                albedoColor.a   *= i.color.a;
#endif

                s.albedo = LinearizeColor(albedoColor.rgb);
                s.alpha  = albedoColor.a;

                // ---- normal ----
                float3 worldNormal = worldNormalGeom;
#if defined(_NORMALMAP_ON)
                float3 tanNormal = UnpackNormal(tex2D(_BumpMap, uv));
                tanNormal.xy *= _BumpScale;
                tanNormal = normalize(tanNormal);
                worldNormal = normalize(
                    tanNormal.x * worldTangent +
                    tanNormal.y * worldBitangent +
                    tanNormal.z * worldNormalGeom);
#endif
                s.worldNormal = worldNormal;
                s.worldPos = worldPos;

                // ---- roughness ----
                float roughness = _Roughness;
#if defined(_ROUGHNESSMAP_ON)
                roughness = tex2D(_RoughnessMap, uv).r;
#endif
#if defined(_INVERTROUGHNESS_ON)
                roughness = 1.0 - roughness;
#endif
                s.roughness = clamp(roughness, 0.03, 1.0);

                // ---- metallic ----
                float metallic = _Metallic;
#if defined(_METALLICMAP_ON)
                metallic = tex2D(_MetallicMap, uv).r;
#endif
                s.metallic = saturate(metallic);

                // ---- occlusion ----
                float occlusion = 1.0;
#if defined(_OCCLUSIONMAP_ON)
                occlusion = tex2D(_OcclusionMap, uv).r;
#endif
                s.occlusion = lerp(1.0, occlusion, _OcclusionStrength);

                // ---- emission ----
                float3 emission = 0;
#if defined(_EMISSIONMAP_ON)
                emission = LinearizeColor(tex2D(_EmissionMap, uv).rgb) * _EmissionColor.rgb;
#endif
                s.emission = emission;

                return s;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);

                SurfaceData s = GetSurfaceData(i);

#if defined(_ALPHATEST_ON)
                clip(s.alpha - _Cutoff);
#endif

                float3 worldViewDir = normalize(_WorldSpaceCameraPos - s.worldPos);
                float3 lightDir = normalize(UnityWorldSpaceLightDir(s.worldPos));

                UNITY_LIGHT_ATTENUATION(atten, i, s.worldPos);

#if defined(_HEIGHTMAP_ON) && defined(_POMSELFSHADOW_ON)
                float3 worldTangent   = float3(i.tspace0.x, i.tspace1.x, i.tspace2.x);
                float3 worldBitangent = float3(i.tspace0.y, i.tspace1.y, i.tspace2.y);
                float3 worldNormalGeom = normalize(float3(i.tspace0.z, i.tspace1.z, i.tspace2.z));
                float3x3 worldToTangent = float3x3(worldTangent, worldBitangent, worldNormalGeom);
                float3 lightDirTS = mul(worldToTangent, lightDir);
                atten *= POMSelfShadow(s.uv, lightDirTS);
#endif

                float3 color = CookTorranceDirect(s, worldViewDir, lightDir, _LightColor0.rgb, atten);
                color += AmbientIBL(s, worldViewDir);
                color += s.emission;

                color = GammaEncodeOutput(color);

                fixed4 outColor = fixed4(color, s.alpha);
                UNITY_APPLY_FOG(i.fogCoord, outColor);
                return outColor;
            }
            ENDCG
        }

        // =================================================================
        // Pass 2: ForwardAdd - additional per-pixel realtime lights (point/spot/extra directional)
        // =================================================================
        Pass
        {
            Name "FORWARD_ADD"
            Tags { "LightMode" = "ForwardAdd" }
            Blend [_SrcBlend] One   // additive on top of base pass; premultiplied dst stays as-is
            ZWrite Off
            AlphaToMask [_AlphaToMask]

            CGPROGRAM
            #pragma target 4.0
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdadd_fullshadows
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #pragma shader_feature_local _ALBEDOMAP_ON
            #pragma shader_feature_local _VERTEXCOLOR_ON
            #pragma shader_feature_local _NORMALMAP_ON
            #pragma shader_feature_local _OCCLUSIONMAP_ON
            #pragma shader_feature_local _ROUGHNESSMAP_ON
            #pragma shader_feature_local _INVERTROUGHNESS_ON
            #pragma shader_feature_local _METALLICMAP_ON
            #pragma shader_feature_local _HEIGHTMAP_ON
            #pragma shader_feature_local _POMSELFSHADOW_ON
            #pragma shader_feature_local _POMSILHOUETTECLAMP_ON
            #pragma shader_feature_local _LINEARPBR_ON
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local _ALPHABLEND_ON

            // ---- Lit-pass-only types/functions (deliberately NOT in the shared
            // CGINCLUDE): v2f uses SHADOW_COORDS()/light-attenuation macros that are
            // only meaningful for ForwardBase/ForwardAdd. If this lived in the shared
            // CGINCLUDE it would also get pasted into the ShadowCaster pass below and
            // fail to compile under that pass's own SHADOWS_DEPTH/SHADOWS_CUBE keywords. ----
            struct v2f
            {
                float4 pos          : SV_POSITION;
                float4 uv           : TEXCOORD0; // xy = main uv, zw = spare
                float4 tspace0      : TEXCOORD1; // tangent.x,   bitangent.x, normal.x, worldPos.x
                float4 tspace1      : TEXCOORD2; // tangent.y,   bitangent.y, normal.y, worldPos.y
                float4 tspace2      : TEXCOORD3; // tangent.z,   bitangent.z, normal.z, worldPos.z
                float3 viewDirTS    : TEXCOORD4; // tangent-space view dir, for POM
                fixed4 color        : TEXCOORD5;
                UNITY_FOG_COORDS(6)
                SHADOW_COORDS(7)
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            v2f vert(appdata v)
            {
                v2f o;
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.pos = UnityObjectToClipPos(v.vertex);
                float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;

                float3 worldNormal  = UnityObjectToWorldNormal(v.normal);
                float3 worldTangent = UnityObjectToWorldDir(v.tangent.xyz);
                float tangentSign   = v.tangent.w * unity_WorldTransformParams.w;
                float3 worldBitangent = cross(worldNormal, worldTangent) * tangentSign;

                o.tspace0 = float4(worldTangent.x, worldBitangent.x, worldNormal.x, worldPos.x);
                o.tspace1 = float4(worldTangent.y, worldBitangent.y, worldNormal.y, worldPos.y);
                o.tspace2 = float4(worldTangent.z, worldBitangent.z, worldNormal.z, worldPos.z);

                o.uv.xy = TRANSFORM_TEX(v.uv, _MainTex);
                o.uv.zw = 0;

                // View direction in tangent space, for parallax occlusion mapping.
                float3 viewDirWS = _WorldSpaceCameraPos - worldPos;
                float3x3 worldToTangent = float3x3(worldTangent, worldBitangent, worldNormal);
                o.viewDirTS = mul(worldToTangent, viewDirWS);

                o.color = v.color;

                UNITY_TRANSFER_FOG(o, o.pos);
                TRANSFER_SHADOW(o);

                return o;
            }

            SurfaceData GetSurfaceData(v2f i)
            {
                SurfaceData s;
                UNITY_INITIALIZE_OUTPUT(SurfaceData, s);

                float3 worldPos = float3(i.tspace0.w, i.tspace1.w, i.tspace2.w);
                float3 worldTangent   = float3(i.tspace0.x, i.tspace1.x, i.tspace2.x);
                float3 worldBitangent = float3(i.tspace0.y, i.tspace1.y, i.tspace2.y);
                float3 worldNormalGeom = normalize(float3(i.tspace0.z, i.tspace1.z, i.tspace2.z));

                float NdotVGeom = saturate(dot(worldNormalGeom, normalize(_WorldSpaceCameraPos - worldPos)));

                float2 uv = i.uv.xy;
                s.pomShadow = 1.0;
#if defined(_HEIGHTMAP_ON)
                uv = ParallaxOcclusionMap(uv, i.viewDirTS, NdotVGeom);
#endif
                s.uv = uv;

                // ---- albedo ----
                fixed4 albedoTex = fixed4(1,1,1,1);
#if defined(_ALBEDOMAP_ON)
                albedoTex = tex2D(_MainTex, uv);
#endif
                fixed4 tint = UNITY_ACCESS_INSTANCED_PROP(PerInstanceProps, _Color);
                fixed4 albedoColor = albedoTex * tint;

#if defined(_VERTEXCOLOR_ON)
                albedoColor.rgb *= i.color.rgb;
                albedoColor.a   *= i.color.a;
#endif

                s.albedo = LinearizeColor(albedoColor.rgb);
                s.alpha  = albedoColor.a;

                // ---- normal ----
                float3 worldNormal = worldNormalGeom;
#if defined(_NORMALMAP_ON)
                float3 tanNormal = UnpackNormal(tex2D(_BumpMap, uv));
                tanNormal.xy *= _BumpScale;
                tanNormal = normalize(tanNormal);
                worldNormal = normalize(
                    tanNormal.x * worldTangent +
                    tanNormal.y * worldBitangent +
                    tanNormal.z * worldNormalGeom);
#endif
                s.worldNormal = worldNormal;
                s.worldPos = worldPos;

                // ---- roughness ----
                float roughness = _Roughness;
#if defined(_ROUGHNESSMAP_ON)
                roughness = tex2D(_RoughnessMap, uv).r;
#endif
#if defined(_INVERTROUGHNESS_ON)
                roughness = 1.0 - roughness;
#endif
                s.roughness = clamp(roughness, 0.03, 1.0);

                // ---- metallic ----
                float metallic = _Metallic;
#if defined(_METALLICMAP_ON)
                metallic = tex2D(_MetallicMap, uv).r;
#endif
                s.metallic = saturate(metallic);

                // ---- occlusion ----
                float occlusion = 1.0;
#if defined(_OCCLUSIONMAP_ON)
                occlusion = tex2D(_OcclusionMap, uv).r;
#endif
                s.occlusion = lerp(1.0, occlusion, _OcclusionStrength);

                // ---- emission ----
                float3 emission = 0;
#if defined(_EMISSIONMAP_ON)
                emission = LinearizeColor(tex2D(_EmissionMap, uv).rgb) * _EmissionColor.rgb;
#endif
                s.emission = emission;

                return s;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);

                SurfaceData s = GetSurfaceData(i);

#if defined(_ALPHATEST_ON)
                clip(s.alpha - _Cutoff);
#endif

                float3 worldViewDir = normalize(_WorldSpaceCameraPos - s.worldPos);
                float3 lightDir = normalize(UnityWorldSpaceLightDir(s.worldPos));

                UNITY_LIGHT_ATTENUATION(atten, i, s.worldPos);

#if defined(_HEIGHTMAP_ON) && defined(_POMSELFSHADOW_ON)
                float3 worldTangent   = float3(i.tspace0.x, i.tspace1.x, i.tspace2.x);
                float3 worldBitangent = float3(i.tspace0.y, i.tspace1.y, i.tspace2.y);
                float3 worldNormalGeom = normalize(float3(i.tspace0.z, i.tspace1.z, i.tspace2.z));
                float3x3 worldToTangent = float3x3(worldTangent, worldBitangent, worldNormalGeom);
                float3 lightDirTS = mul(worldToTangent, lightDir);
                atten *= POMSelfShadow(s.uv, lightDirTS);
#endif

                float3 color = CookTorranceDirect(s, worldViewDir, lightDir, _LightColor0.rgb, atten);
                color = GammaEncodeOutput(color);

                fixed4 outColor = fixed4(color, s.alpha);
                // Fog must be applied as black in additive passes or it double-brightens.
                UNITY_APPLY_FOG_COLOR(i.fogCoord, outColor, fixed4(0,0,0,0));
                return outColor;
            }
            ENDCG
        }

        // =================================================================
        // Pass 3: ShadowCaster - so this shader casts real-time shadows
        // (and respects Alpha Clipping so cutout foliage etc. casts correct shadows)
        // =================================================================
        Pass
        {
            Name "SHADOW_CASTER"
            Tags { "LightMode" = "ShadowCaster" }

            CGPROGRAM
            #pragma target 4.0
            #pragma vertex vertShadow
            #pragma fragment fragShadow
            #pragma multi_compile_shadowcaster
            #pragma multi_compile_instancing
            #pragma shader_feature_local _ALBEDOMAP_ON
            #pragma shader_feature_local _HEIGHTMAP_ON
            #pragma shader_feature_local _ALPHATEST_ON

            struct v2fShadow
            {
                V2F_SHADOW_CASTER;
                float2 uv : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            v2fShadow vertShadow(appdata v)
            {
                v2fShadow o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                TRANSFER_SHADOW_CASTER_NORMALOFFSET(o);
                return o;
            }

            fixed4 fragShadow(v2fShadow i) : SV_Target
            {
#if defined(_ALPHATEST_ON)
                fixed alpha = 1;
#if defined(_ALBEDOMAP_ON)
                alpha = tex2D(_MainTex, i.uv).a;
#endif
                alpha *= UNITY_ACCESS_INSTANCED_PROP(PerInstanceProps, _Color).a;
                clip(alpha - _Cutoff);
#endif
                SHADOW_CASTER_FRAGMENT(i)
            }
            ENDCG
        }
    }

    Fallback "Diffuse"
    CustomEditor "PBR_CookTorranceGGXGUI"
}
