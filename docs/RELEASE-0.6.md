# War Journalist 0.6 Preview

Sorry about the missing shader assets in 0.5 — I forgot to bundle them. They are included in 0.6.

War Journalist now includes all 40 decorative shader overlays and their materials/registrations, camera foundation, private menu/input services, PNG screenshot converter and logos. The only mod prerequisite is the chosen Lua loader: Bingus Shared Loader v15+ for BSL, or MDL API 2 for the alternative package. MCM remains optional. DBF-HUD and original ActionCam are not required.

- BSL: the single Addon option installs the Lua runtime and every required overlay asset together. HD2 Arsenal or manual patch installation works.
- MDL: the ZIP includes dbf_freecam and GameData; install both parts following INSTALL.txt. The native assets load through the game independently of BSL.
- Standalone settings now live under %LOCALAPPDATA%/DBF/PhotoMode/settings. Existing MCM settings remain owned by MCM; this package does not ship saved settings.
- The maintained source owns its vendored camera/private services/native payloads and decorative asset blobs/HLSL. Building the release no longer reads DBF-HUD, DBF-MCM or an externally installed ActionCam package. Credits and input identities are retained.

Focus/aperture, scene color/depth effects and exposure/saturation/contrast remain disabled. This is the asset/dependency packaging update, not a claim that the custom DoF repair is finished.

Validation: isolated runtime fixtures, packaged standalone startup without external mods/source fallback, PE import checks, exact native resource/registry closure, Lua compilation and ZIP hashes. These checks do not claim new in-game validation.

[GitHub downloads](https://github.com/HWG90/DBF_PhotoMode/releases/tag/v0.6-preview.1) | [Nexus](https://www.nexusmods.com/helldivers2/mods/17248) | [Ayaka](https://ayakamods.com/mods/war-journalist-helldivers-2-photo-mode.4948/)
