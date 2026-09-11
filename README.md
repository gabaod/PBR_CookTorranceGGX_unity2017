# PBR_CookTorranceGGX_unity2017
Custom Cook-Torrance (GGX/Trowbridge-Reitz NDF, Smith height-correlated visibility, Schlick Fresnel) metallic-workflow PBR shader for Unity 2017.4.9f1 (Built-in RP, Forward only). Built for: Descenders (Unity 2017.4.9f1, Player Settings Color Space = GAMMA).<br>
Includes a custom material inspector for Custom/PBR_CookTorranceGGX to define settings.<br>
<br>
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
