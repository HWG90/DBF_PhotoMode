# War Journalist 1.2.0 — Handycam

A Helldivers 2 Photo Mode.

**A HUGE THANK YOU to everyone submitting photos, testing builds and reporting bugs.** Your shots keep making this better. Keep them coming!

- **First-person handycam:** Director → Action camera mode → First-person handycam. Control your Helldiver while recording from the head camera. The avatar and equipment are hidden for a clear view, including the lower body. Gameplay HUD is hidden during handycam.
- **Handheld motion:** adjustable shake intensity adds movement-driven sway, pitch and roll. Set intensity to zero for a clean head camera. Optional camera smoothing has its own strength slider.
- **Smooth wheel zoom:** wheel up zooms in, wheel down zooms out. Zoom eases toward its target using real time, including during slow motion. Mouse look stays available to gameplay.
- **Less visibility stutter:** unchanged equipment no longer triggers full rediscovery and repeated mesh checks twice a second. In the measured handycam sample, the worst visibility update fell from about 22 ms to 1.6 ms. The tester confirmed reduced hitches; this is not a universal FPS promise.
- **Lights in action shots:** photo lights remain active; camera-follow lights track the shot camera, including handycam. A transient missed camera-pose read now retains the last valid light anchor for the same live scene. Wider lighting coverage remains **Not tested fully**.
- **Hide just the cape:** a separate Subject visibility option, with owned restoration.
- **Quieter interface:** Cinema notifications are optional and off by default. Epic LUT handoffs suspend the Photo menu and return to menu control afterward.
- **Cape Reset:** restore the body before evaluating the cape attachment on a frozen pose reset. Cloth can retain its last simulated drape; this is not a full cloth reset.

The 1.1.0 player-side Passive/no-aggro mode, bounded Dummy updates, independent camera, input recovery, poses, camera paths and lighting rigs remain included. **So uh... don't get too comfy.** Passive is not invulnerability.

Choose one complete package: BSL, MDL or LLL. GitHub has all three; Nexus has BSL and MDL. Preserve settings, presets and screenshots, replace the old runtime, deploy the matching bundled assets and restart normally. Do not mix runtime versions.

Validation: isolated Lua fixtures, native input tests and standalone package checks. The visibility correction was measured live on LLL. Handycam smoothing, final zoom feel and lighting transitions still need wider live testing across loaders. Native Tactical Video Camera experiments and native hover hooks are not included. Public scene effects and numeric DoF gates remain unchanged.
