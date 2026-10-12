# War Journalist 0.7 Preview

Shader depth of field now provides working focus distance and aperture controls. This is a preview release for **BSL and MDL only**.

**NOTICE: When Shader DoF is enabled, scene effects and color controls are grayed out. The menu displays "Shader DoF Enabled. Scene Effects disabled". Turn DoF OFF or select Native camera mode to use scene effects.**

**Native game engine DoF remains nonfunctional for manual focus/aperture control.** Its numeric controls remain disabled. The native toggle can enable the game's existing effect, but it does not provide the adjustable lens implementation. Choose **Shader preview** to use the working focus/aperture controls.

## Shader DoF package

- Depth-aware focus distance and aperture/f-stop, with 32/64 sample quality and round/hexagonal bokeh choices.
- The blur samples the game's 960×540 color source. Pixels in focus retain the original full-resolution scene. This is not a full-resolution blur pipeline; final bokeh quality remains under review.
- Focus and aperture response and typed-value saving were confirmed in-game. Shader registration and loaded shader bytes were checked separately.
- All assets are bundled: 40 decorative overlays plus the DoF and scene shaders, totaling 42 shader libraries, 42 materials, and a registry with 317 IDs. No separate shader asset download is needed.
- HDR-aware PNG capture, standalone private menu/input services, and the camera runtime are included. MCM is optional; DBF-HUD and ActionCam downloads are unnecessary.

## Controls and preview features

In menu focus, W/S selects the row and A/D adjusts its value or cycles dropdown options without mouse hover. Shift+A/D provides 0.001 m focus steps. Valid typed values save when leaving the field; Escape cancels. Mouse Exit followed by P reopens Photo Mode.

Scene previews include Negative, Monochrome, Posterize, Duotone, Solarize, Inverted depth, Thermal depth, Depth contours, and Depth fog, plus exposure, contrast, and saturation. Their visual results remain unverified. Scene/color controls are gated while Shader DoF is ON because the passes do not yet share grading. Turn DoF OFF or select native camera mode to test them. Scene previews also use the 960×540 color source; neutral controls preserve the original image.

## Install

Choose one package. BSL requires Bingus Shared Loader v15+ / API 1; import the ZIP into HD2 Arsenal, enable War Journalist, deploy, and restart normally. MDL requires API 2: install the included GameData patch triplets and copy dbf_freecam to `%LOCALAPPDATA%/MDL/Helldivers2/Mods`, then enable it and restart normally. Manual patch installation is described in INSTALL.txt.

Disable original ActionCam, older War Journalist packages, the LLL Photo Mode addon, and any separate DoF asset candidate before installing. Settings and screenshots are not bundled or overwritten. Other mods replacing the shader registry require an explicit registration merge.

This release does not claim a native focus/aperture fix, final shader quality, verified scene effects, or an unrelated alt-tab crash fix.
