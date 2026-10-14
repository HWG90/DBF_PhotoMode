## War Journalist 0.9.9 — Shader registry compatibility hotfix

The bundled shader registry is repaired: 198 inherited registrations referenced
libraries that were missing from a clean install. It now registers only the
game's native shaders and the Photo Mode libraries included in the download.

Affected Radeon testers report that **Alt-Tab, fullscreen, bloom and DoF changes
stay stable**, before and after opening Photo Mode. All 0.9.8 features remain,
including the steady Native DoF and held ADS fixes. The runtime, GPU shaders,
lights and artwork are unchanged from the registry-only test.

Replace the old Photo Mode package, deploy the bundled assets and restart.
Preserve your settings, presets and screenshots. Lighting: **Not tested fully**;
HDR/SDR switching and unrelated crashes still need separate confirmation.

[GitHub — BSL, MDL and LLL](https://github.com/HWG90/DBF_PhotoMode/releases/tag/v0.9.9)
| [Nexus — BSL and MDL](https://www.nexusmods.com/helldivers2/mods/17248?tab=files)
| [Ayaka](https://ayakamods.com/mods/war-journalist-helldivers-2-photo-mode.4948/)
