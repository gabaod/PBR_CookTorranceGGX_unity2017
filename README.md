# PBR_CookTorranceGGX_unity2017
Custom Cook-Torrance (GGX/Trowbridge-Reitz NDF, Smith height-correlated visibility, Schlick Fresnel) metallic-workflow PBR shader for Unity 2017.4.9f1 (Built-in RP, Forward only). Built for: Descenders (Unity 2017.4.9f1, Player Settings Color Space = GAMMA).<br>
Includes a custom material inspector for Custom/PBR_CookTorranceGGX to define settings.<br>
<br>
// -------------------------------------------------------------------------------------<br>
// TEXTURE IMPORT CHECKLIST (read this before assigning textures in the Inspector!)<br>
// -------------------------------------------------------------------------------------<br>
//   Albedo Map    -> Texture Type: Default, sRGB (Color Texture) = CHECKED<br>
//   Emission Map  -> Texture Type: Default, sRGB (Color Texture) = CHECKED<br>
//   Normal Map    -> Texture Type: Normal Map (Unity will set sRGB unchecked for you)<br>
//   Occlusion Map -> Texture Type: Default, sRGB (Color Texture) = UNCHECKED (it's data, not color)<br>
//   Roughness Map -> Texture Type: Default, sRGB (Color Texture) = UNCHECKED<br>
//   Metallic Map  -> Texture Type: Default, sRGB (Color Texture) = UNCHECKED<br>
//   Height Map    -> Texture Type: Default, sRGB (Color Texture) = UNCHECKED<br>
//<br>
//   Getting sRGB wrong on Albedo/Emission will make them look washed out or too dark.<br>
//   Getting sRGB CHECKED on any of the data maps (normal/occlusion/roughness/metallic/<br>
//   height) will silently corrupt the values the math reads - always double check.<br>
// -------------------------------------------------------------------------------------<br>
//<br>
// NOTES ON DESIGN CHOICES (see chat for full reasoning):<br>
//  - Metallic workflow, Cook-Torrance specular = D * Vis * F  (Vis already folds in the<br>
//    1/(4*NdotL*NdotV) term - this is the Smith-GGX height-correlated visibility form).<br>
//  - Dielectric F0 ("Specular Level") is an exposed slider instead of the usual hardcoded<br>
//    0.04, per your request.<br>
//  - All secondary maps (normal/occlusion/roughness/metallic/height/emission) share ONE<br>
//    Tiling/Offset (_MainTex_ST), driven by the Albedo map's tiling/offset fields.<br>
//  - Height map drives real Parallax Occlusion Mapping (POM) with optional self-shadowing<br>
//    and optional silhouette clamp/fade to hide grazing-angle swimming artifacts.<br>
//  - _LINEARPBR_ON is a shader_feature (compile-time, zero runtime cost either way).<br>
//    OFF (default) = do the lighting math directly in gamma-space values, matching how<br>
//    the rest of a Gamma-color-space project (like Descenders) renders.<br>
//    ON = manually linearize inputs before lighting and re-gamma-encode the output,<br>
//    which is closer to "textbook correct" PBR but will look different from the rest<br>
//    of the game's gamma-space rendering. Pick ON only if you specifically want that.<br>
//  - Most "Use X Map" toggles are shader_feature keywords (not runtime branches), so<br>
//    unused code paths (and unused texture samples) are compiled out entirely. Because<br>
//    shader_feature only builds the variants your actual materials use, this stays cheap<br>
//    even though there are many keywords - just be aware that using ALL combinations<br>
//    across many different materials will grow your build's shader variant count.<br>
<br>
<br>
To Setup:<br>
1. Copy Editor/PBR_CookTorranceGGXGUI.cs into your Assets/Editor folder<br>
2. Copy Shader/PBR_CookTorranceGGX.shader into Assets folder i prefer Assets/Shader<br>
3. Create a new material, assign the shader to Custom/PBR_CookTorranceGGX and use the inspector to define the fields
