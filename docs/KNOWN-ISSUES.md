# Known issues in 0.7 Preview

NOTICE: When Shader DoF is enabled, scene effects and color controls are grayed out.
The menu displays "Shader DoF Enabled. Scene Effects disabled".
Turn DoF OFF or select Native camera mode to use scene effects.

- Native game engine DoF is still nonfunctional for manual focus/aperture control. Native numeric controls remain disabled; the native toggle only uses the existing engine effect. Use Shader preview for adjustable focus/aperture.
- Shader DoF blur samples a 960x540 color source. Focused pixels retain the original full-resolution scene; final bokeh quality remains under review.
- Scene effects and exposure/contrast/saturation are unverified previews. They are gated while Shader DoF is ON because the passes do not yet share grading. Scene color also uses a 960x540 source.
- Built-in HDR-aware PNG capture may retain ship UI. Steam screenshots remain an alternative.
- Shader packs replacing the default shader registry require an explicit registration merge.
- Pause and slow motion require a verified solo session. No unrelated alt-tab crash fix is claimed.

BSL and MDL are the only published packages for this preview.
