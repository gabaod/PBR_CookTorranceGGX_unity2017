// =====================================================================================
// PBR_CookTorranceGGXGUI.cs
// Custom material inspector for Custom/PBR_CookTorranceGGX.
//
// EDITOR-ONLY: This lives under an Editor folder and only runs inside the Unity
// Editor while you're authoring materials. It does NOT ship in a built game/mod -
// AssetBundles only contain the compiled .shader, never Editor scripts, so this
// file has no runtime footprint and doesn't need to touch ModTool.Interface at all.
//
// Put this file in: Assets/Editor/PBR_CookTorranceGGXGUI.cs
// (any path under a folder literally named "Editor" works)
// =====================================================================================

using UnityEngine;
using UnityEditor;

public class PBR_CookTorranceGGXGUI : ShaderGUI
{
	private enum RenderMode
	{
		Opaque = 0,
		Cutout = 1,
		Transparent = 2
	}

	// property name -> shader_feature keyword it should drive.
	// (Unity 2017's compiler is C# 4/5-ish and doesn't support C# 7 named tuples,
	// so this uses a plain struct instead of "(string prop, string keyword)[]".)
	private struct ToggleKeywordPair
	{
		public string prop;
		public string keyword;
		public ToggleKeywordPair(string prop, string keyword)
		{
			this.prop = prop;
			this.keyword = keyword;
		}
	}

	private static readonly ToggleKeywordPair[] ToggleKeywordMap = new ToggleKeywordPair[]
	{
		new ToggleKeywordPair("_UseAlbedoMap",       "_ALBEDOMAP_ON"),
		new ToggleKeywordPair("_UseVertexColor",     "_VERTEXCOLOR_ON"),
		new ToggleKeywordPair("_UseNormalMap",       "_NORMALMAP_ON"),
		new ToggleKeywordPair("_UseOcclusionMap",    "_OCCLUSIONMAP_ON"),
		new ToggleKeywordPair("_UseRoughnessMap",    "_ROUGHNESSMAP_ON"),
		new ToggleKeywordPair("_InvertRoughness",    "_INVERTROUGHNESS_ON"),
		new ToggleKeywordPair("_UseMetallicMap",     "_METALLICMAP_ON"),
		new ToggleKeywordPair("_UseHeightMap",       "_HEIGHTMAP_ON"),
		new ToggleKeywordPair("_POMSelfShadow",      "_POMSELFSHADOW_ON"),
		new ToggleKeywordPair("_POMSilhouetteClamp", "_POMSILHOUETTECLAMP_ON"),
		new ToggleKeywordPair("_UseEmissionMap",     "_EMISSIONMAP_ON"),
		new ToggleKeywordPair("_LinearPBR",          "_LINEARPBR_ON"),
	};

	// persisted per-editor-session foldout state
	private bool foldAlbedo = true;
	private bool foldNormal = false;
	private bool foldOcclusion = false;
	private bool foldRoughness = true;
	private bool foldMetallic = true;
	private bool foldHeight = false;
	private bool foldEmission = false;
	private bool foldLighting = false;
	private bool foldRendering = true;

	private MaterialEditor materialEditor;
	private MaterialProperty[] props;

	public override void OnGUI(MaterialEditor matEditor, MaterialProperty[] properties)
	{
		materialEditor = matEditor;
		props = properties;
		Material[] materials = System.Array.ConvertAll(matEditor.targets, o => (Material)o);

		EditorGUI.BeginChangeCheck();

		EditorGUILayout.HelpBox(
			"Texture import reminder:\n" +
			"Albedo / Emission -> sRGB (Color Texture) CHECKED.\n" +
			"Normal / Occlusion / Roughness / Metallic / Height -> sRGB UNCHECKED (they're data, not color).",
			MessageType.Info);

		EditorGUILayout.Space();
		DrawAlbedoSection();
		EditorGUILayout.Space();
		DrawNormalSection();
		EditorGUILayout.Space();
		DrawOcclusionSection();
		EditorGUILayout.Space();
		DrawRoughnessSection();
		EditorGUILayout.Space();
		DrawMetallicSection();
		EditorGUILayout.Space();
		DrawHeightSection();
		EditorGUILayout.Space();
		DrawEmissionSection();
		EditorGUILayout.Space();
		DrawLightingSection();
		EditorGUILayout.Space();
		DrawRenderingSection();

		if (EditorGUI.EndChangeCheck())
		{
			foreach (Material m in materials)
			{
				SyncToggleKeywords(m);
				ApplyRenderMode(m);
			}
		}
	}

	public override void AssignNewShaderToMaterial(Material material, Shader oldShader, Shader newShader)
	{
		base.AssignNewShaderToMaterial(material, oldShader, newShader);
		SyncToggleKeywords(material);
		ApplyRenderMode(material);
	}

	// -----------------------------------------------------------------------------
	// Sections
	// -----------------------------------------------------------------------------

	private void DrawAlbedoSection()
	{
		foldAlbedo = EditorGUILayout.Foldout(foldAlbedo, "Albedo", true, EditorStyles.foldout);
		if (!foldAlbedo) return;
		EditorGUI.indentLevel++;

		MaterialProperty color = FindProperty("_Color");
		MaterialProperty useMap = FindProperty("_UseAlbedoMap");
		MaterialProperty mainTex = FindProperty("_MainTex");

		materialEditor.ShaderProperty(color, "Albedo Tint (RGBA)");
		bool useAlbedo = DrawToggle(useMap, "Use Albedo Map");
		using (new EditorGUI.DisabledScope(!useAlbedo))
		{
			materialEditor.TexturePropertySingleLine(new GUIContent("Albedo Map"), mainTex);
		}
		// Shared Tiling/Offset lives here and is reused by every other map.
		materialEditor.TextureScaleOffsetProperty(mainTex);

		DrawToggle(FindProperty("_UseVertexColor"), "Multiply Vertex Color into Albedo");

		EditorGUI.indentLevel--;
	}

	private void DrawNormalSection()
	{
		foldNormal = EditorGUILayout.Foldout(foldNormal, "Normal Map", true, EditorStyles.foldout);
		if (!foldNormal) return;
		EditorGUI.indentLevel++;

		bool use = DrawToggle(FindProperty("_UseNormalMap"), "Use Normal Map");
		using (new EditorGUI.DisabledScope(!use))
		{
			materialEditor.TexturePropertySingleLine(new GUIContent("Normal Map"), FindProperty("_BumpMap"));
			materialEditor.ShaderProperty(FindProperty("_BumpScale"), "Normal Scale");
		}

		EditorGUI.indentLevel--;
	}

	private void DrawOcclusionSection()
	{
		foldOcclusion = EditorGUILayout.Foldout(foldOcclusion, "Occlusion Map", true, EditorStyles.foldout);
		if (!foldOcclusion) return;
		EditorGUI.indentLevel++;

		bool use = DrawToggle(FindProperty("_UseOcclusionMap"), "Use Occlusion Map");
		using (new EditorGUI.DisabledScope(!use))
		{
			materialEditor.TexturePropertySingleLine(new GUIContent("Occlusion Map (R)"), FindProperty("_OcclusionMap"));
			materialEditor.ShaderProperty(FindProperty("_OcclusionStrength"), "Occlusion Strength");
		}
		EditorGUILayout.HelpBox("Applied to both indirect diffuse and indirect specular (does not affect direct lighting).", MessageType.None);

		EditorGUI.indentLevel--;
	}

	private void DrawRoughnessSection()
	{
		foldRoughness = EditorGUILayout.Foldout(foldRoughness, "Roughness Map", true, EditorStyles.foldout);
		if (!foldRoughness) return;
		EditorGUI.indentLevel++;

		materialEditor.ShaderProperty(FindProperty("_Roughness"), "Roughness (used when no map, or as a multiplier feel)");
		bool use = DrawToggle(FindProperty("_UseRoughnessMap"), "Use Roughness Map");
		using (new EditorGUI.DisabledScope(!use))
		{
			materialEditor.TexturePropertySingleLine(new GUIContent("Roughness Map (R)"), FindProperty("_RoughnessMap"));
			DrawToggle(FindProperty("_InvertRoughness"), "Invert (map is actually Smoothness)");
		}

		EditorGUI.indentLevel--;
	}

	private void DrawMetallicSection()
	{
		foldMetallic = EditorGUILayout.Foldout(foldMetallic, "Metallic Map", true, EditorStyles.foldout);
		if (!foldMetallic) return;
		EditorGUI.indentLevel++;

		materialEditor.ShaderProperty(FindProperty("_Metallic"), "Metallic (used when no map)");
		bool use = DrawToggle(FindProperty("_UseMetallicMap"), "Use Metallic Map");
		using (new EditorGUI.DisabledScope(!use))
		{
			materialEditor.TexturePropertySingleLine(new GUIContent("Metallic Map (R)"), FindProperty("_MetallicMap"));
		}
		materialEditor.ShaderProperty(FindProperty("_SpecularLevel"), "Specular Level (dielectric F0, default 0.04)");

		EditorGUI.indentLevel--;
	}

	private void DrawHeightSection()
	{
		foldHeight = EditorGUILayout.Foldout(foldHeight, "Height Map (Parallax Occlusion Mapping)", true, EditorStyles.foldout);
		if (!foldHeight) return;
		EditorGUI.indentLevel++;

		bool use = DrawToggle(FindProperty("_UseHeightMap"), "Use Height Map");
		using (new EditorGUI.DisabledScope(!use))
		{
			materialEditor.TexturePropertySingleLine(new GUIContent("Height Map (R)"), FindProperty("_HeightMap"));
			materialEditor.ShaderProperty(FindProperty("_HeightScale"), "Height Scale");
			materialEditor.ShaderProperty(FindProperty("_POMMinSamples"), "POM Min Samples (facing camera)");
			materialEditor.ShaderProperty(FindProperty("_POMMaxSamples"), "POM Max Samples (grazing angle)");

			bool selfShadow = DrawToggle(FindProperty("_POMSelfShadow"), "POM Self-Shadowing");
			using (new EditorGUI.DisabledScope(!selfShadow))
			{
				materialEditor.ShaderProperty(FindProperty("_POMShadowSoftening"), "Self-Shadow Softening");
			}

			DrawToggle(FindProperty("_POMSilhouetteClamp"), "Silhouette Clamp / Fade (hides grazing-angle swimming)");
		}
		EditorGUILayout.HelpBox("POM is per-pixel raymarched displacement, not real geometry - it can't change the mesh silhouette.", MessageType.None);

		EditorGUI.indentLevel--;
	}

	private void DrawEmissionSection()
	{
		foldEmission = EditorGUILayout.Foldout(foldEmission, "Emission", true, EditorStyles.foldout);
		if (!foldEmission) return;
		EditorGUI.indentLevel++;

		bool use = DrawToggle(FindProperty("_UseEmissionMap"), "Use Emission Map");
		using (new EditorGUI.DisabledScope(!use))
		{
			materialEditor.TexturePropertySingleLine(new GUIContent("Emission Map"), FindProperty("_EmissionMap"));
		}
		materialEditor.ShaderProperty(FindProperty("_EmissionColor"), "Emission Color (HDR)");

		EditorGUI.indentLevel--;
	}

	private void DrawLightingSection()
	{
		foldLighting = EditorGUILayout.Foldout(foldLighting, "Lighting Math", true, EditorStyles.foldout);
		if (!foldLighting) return;
		EditorGUI.indentLevel++;

		bool linear = DrawToggle(FindProperty("_LinearPBR"), "Linear-space lighting math");
		EditorGUILayout.HelpBox(
			linear
				? "ON: inputs are manually linearized before lighting and the result is re-gamma-encoded. More 'textbook correct' PBR, but will look different from the rest of a Gamma-space project like Descenders."
				: "OFF (recommended for Descenders): lighting math runs directly on gamma-space values, matching how the rest of the game renders.",
			MessageType.None);

		EditorGUI.indentLevel--;
	}

	private void DrawRenderingSection()
	{
		foldRendering = EditorGUILayout.Foldout(foldRendering, "Rendering Options", true, EditorStyles.foldout);
		if (!foldRendering) return;
		EditorGUI.indentLevel++;

		MaterialProperty renderModeProp = FindProperty("_RenderMode");
		RenderMode mode = (RenderMode)renderModeProp.floatValue;
		EditorGUI.BeginChangeCheck();
		mode = (RenderMode)EditorGUILayout.EnumPopup("Render Mode", mode);
		if (EditorGUI.EndChangeCheck())
		{
			renderModeProp.floatValue = (float)mode;
		}

		if (mode == RenderMode.Cutout)
		{
			materialEditor.ShaderProperty(FindProperty("_Cutoff"), "Alpha Cutoff");
			DrawToggle(FindProperty("_AlphaToMask"), "Alpha To Coverage (smoother cutout edges w/ MSAA)");
		}

		materialEditor.ShaderProperty(FindProperty("_Cull"), "Cull Mode (Off = double-sided)");

		EditorGUI.indentLevel--;
	}

	// -----------------------------------------------------------------------------
	// Helpers
	// -----------------------------------------------------------------------------

	private MaterialProperty FindProperty(string name)
	{
		return FindProperty(name, props);
	}

	/// Draws a plain toggle bound to a float MaterialProperty and returns its value.
	/// (Drawn manually rather than relying on the built-in [Toggle] drawer so we can
	/// nest it inside our own foldouts and use its value to conditionally show fields.)
	private bool DrawToggle(MaterialProperty prop, string label)
	{
		EditorGUI.showMixedValue = prop.hasMixedValue;
		EditorGUI.BeginChangeCheck();
		bool value = EditorGUILayout.Toggle(label, prop.floatValue > 0.5f);
		if (EditorGUI.EndChangeCheck())
		{
			prop.floatValue = value ? 1f : 0f;
		}
		EditorGUI.showMixedValue = false;
		return prop.floatValue > 0.5f;
	}

	private static void SyncToggleKeywords(Material m)
	{
		foreach (var pair in ToggleKeywordMap)
		{
			if (!m.HasProperty(pair.prop)) continue;
			bool on = m.GetFloat(pair.prop) > 0.5f;
			if (on) m.EnableKeyword(pair.keyword);
			else m.DisableKeyword(pair.keyword);
		}
	}

	/// Mirrors Unity Standard shader's SetupMaterialWithBlendMode: drives blend state,
	/// ZWrite, render queue and RenderType tag, and the alpha-test/alpha-blend keywords,
	/// from the single Render Mode dropdown.
	private static void ApplyRenderMode(Material m)
	{
		if (!m.HasProperty("_RenderMode")) return;
		RenderMode mode = (RenderMode)m.GetFloat("_RenderMode");

		switch (mode)
		{
			case RenderMode.Opaque:
				m.SetOverrideTag("RenderType", "Opaque");
				m.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.One);
				m.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.Zero);
				m.SetFloat("_ZWrite", 1f);
				m.DisableKeyword("_ALPHATEST_ON");
				m.DisableKeyword("_ALPHABLEND_ON");
				m.renderQueue = (int)UnityEngine.Rendering.RenderQueue.Geometry;
				break;

			case RenderMode.Cutout:
				m.SetOverrideTag("RenderType", "TransparentCutout");
				m.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.One);
				m.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.Zero);
				m.SetFloat("_ZWrite", 1f);
				m.EnableKeyword("_ALPHATEST_ON");
				m.DisableKeyword("_ALPHABLEND_ON");
				m.renderQueue = (int)UnityEngine.Rendering.RenderQueue.AlphaTest;
				break;

			case RenderMode.Transparent:
				m.SetOverrideTag("RenderType", "Transparent");
				m.SetFloat("_SrcBlend", (float)UnityEngine.Rendering.BlendMode.SrcAlpha);
				m.SetFloat("_DstBlend", (float)UnityEngine.Rendering.BlendMode.OneMinusSrcAlpha);
				m.SetFloat("_ZWrite", 0f);
				m.DisableKeyword("_ALPHATEST_ON");
				m.EnableKeyword("_ALPHABLEND_ON");
				m.renderQueue = (int)UnityEngine.Rendering.RenderQueue.Transparent;
				break;
		}
	}
}
