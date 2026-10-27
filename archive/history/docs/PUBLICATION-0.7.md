# War Journalist 0.7 Preview publication

Published October 12, 2026. Release source commit: `60ad08c`. Tag: `v0.7-preview.1`.

Nexus was updated first, followed by GitHub, Ayaka, and the existing Discord post.

- [Nexus](https://www.nexusmods.com/helldivers2/mods/17248?tab=files): 0.7 BSL main file 68496 and MDL optional file 68497. The previous 0.6 files were archived through the normal update flow. Public VirusTotal hash links match the exact ZIPs below. Public description and short description render the 0.7 shader DoF details and prominent gray-out notice. Scans were initially processing; subsequent public hash links and Manual download controls were verified for both files, with the scanning-in-progress message absent. A completed download transfer is not claimed.
- [GitHub prerelease](https://github.com/HWG90/DBF_PhotoMode/releases/tag/v0.7-preview.1): source pushed to main, tag pushed, and BSL/MDL ZIPs plus SHA256SUMS.txt uploaded. GitHub API asset digests match local bytes. No LLL package is published for 0.7.
- [Ayaka](https://ayakamods.com/mods/war-journalist-helldivers-2-photo-mode.4948/): public version 0.7 and [update 7126](https://ayakamods.com/mods/war-journalist-helldivers-2-photo-mode.4948/update/7126/). Primary external download is the GitHub BSL asset; the main description and update include the MDL alternative and matching feature/limitation notices. No Ayaka re-download hash is claimed.
- [Discord announcement](https://discord.com/channels/1260111500522295377/1559027203315073094): original message and title updated to 0.7 Preview, original image retained. Rendered message includes shader package details, exact menu notice, native manual DoF limitation, BSL/MDL-only installation, and the 0.7 GitHub link.

| Artifact | SHA-256 |
| --- | --- |
| War-Journalist-0.7-BSL.zip | ec9b3a4a18df59749ce12da9c0d3c046db1fe6c8266844fce4a66582e96647e0 |
| War-Journalist-0.7-MDL.zip | c82a22fe2e009a8d60f743c30733a4c21c6ce0fdbfb0a8e0a4fd6e19a8986448 |

Both packages contain 42 shader libraries, 42 materials and a registry with 317 IDs: 40 decorative pairs, shader DoF and scene preview assets. Camera, private menu/input and HDR-aware PNG converter are bundled. Required loaders are BSL v15+ / API 1 or MDL API 2; MCM is optional.

Shader focus/aperture response and typed-value commit were user-confirmed in-game. Shader blur samples a 960x540 color source while focused pixels retain the original full-resolution scene. Final artistic quality remains under review. Scene/depth effects and tonal grading remain visually unverified previews.

When Shader DoF is ON, scene effects and color controls are grayed out. The first status row on both pages displays exactly **"Shader DoF Enabled. Scene Effects disabled"**. The message clears and controls become available when DoF is OFF or Native camera mode is selected, subject to normal asset readiness. Packages and all publication surfaces explain the same restriction.

Native game engine DoF remains nonfunctional for manual focus/aperture control; numeric native controls remain disabled. The native toggle can use the game's existing effect. This release does not claim a native adjustable-lens fix.

Validation: 25/25 isolated Lua fixture groups passed after the final notice placement; source-unavailable BSL and MDL bootstrap, private settings persistence, native system-library closure and owned cleanup passed. Builders compile all Lua and verify native resource round-trips, registration counts, ZIP CRC/path uniqueness and bundled input/capture library hashes. Targeted tests verify the exact notice, first-row placement, disabled parameters and clearing the notice when DoF is OFF. Offline tests do not prove scene GPU visuals or native setter behavior.

Build from source with `py -3 tools/build_preview.py --output dist/releases/<new-output-name>`. Output must not already exist. Source-owned compiled shader snapshots are hash checked and packaged without installed-game asset inputs. Local investigation scripts, captures, logs, saved settings and diagnostic receipts remain outside the published source/artifacts. No game deployment or settings changes were performed by this publication task.
