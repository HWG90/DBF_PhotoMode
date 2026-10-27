# War Journalist 0.6 Preview publication

Published October 12, 2026. Release source commit: `7d26befe99669e3db80ea7228493e2ed55335739`. Tag: `v0.6-preview.1` (GitHub prerelease).

- [GitHub release](https://github.com/HWG90/DBF_PhotoMode/releases/tag/v0.6-preview.1): source pushed to main; BSL, MDL and SHA256SUMS uploaded. API-reported artifact digests match local files.
- [Nexus](https://www.nexusmods.com/helldivers2/mods/17248?tab=files): BSL main file 68421; MDL optional file 68422. Both public VirusTotal hash links match the exact uploaded ZIP hashes. Page renders version 0.6 and Safe to use. Previous 0.5 files are archived through the normal update flow. BSL requires only Bingus Shared Loader (minimum version 15); MDL inherits its existing loader file chain on MDL Pro.
- [Ayaka](https://ayakamods.com/mods/war-journalist-helldivers-2-photo-mode.4948/): public version 0.6; [update 7062](https://ayakamods.com/mods/war-journalist-helldivers-2-photo-mode.4948/update/7062/). Main external download resolves to the GitHub BSL asset and the alternate link targets MDL. The browser blocked the follow-on transfer, so no Ayaka re-download hash is claimed.
- [Discord announcement](https://discord.com/channels/1260111500522295377/1559027203315073094): original post and title edited to 0.6 Preview; bundled asset list, loader-only install, MDL two-part install and current download links verified in rendered post. Original image remains attached.

The requested first-person apology is included on all four surfaces: “Sorry about the missing shader assets in 0.5 — I forgot to bundle them. They are included in 0.6.” Nexus, Ayaka and Discord use the equivalent “They’re” contraction.

| Artifact | SHA-256 |
| --- | --- |
| War-Journalist-0.6-BSL.zip | 26245ad66ff50296185b22ab0f4eec07a92b2664f4136e78d34f1851302f8295 |
| War-Journalist-0.6-MDL.zip | ead37dcc738ca8080126250d140f18ef805c7689ed85b4bb912b498b4dc1bc6c |

Both packages include 40 decorative materials, 40 shader libraries, and a registry retaining 77 original game entries plus 40 overlay entries. All 40 owned HLSL sources were compiled and their instruction/reflection/signature sections matched the preserved shader bytecode. Stable private input/menu, native PNG conversion and camera foundation are bundled; runtime downloads of HUD, MCM or ActionCam are unnecessary.

Validation: 16 isolated runtime fixture groups; immutable ZIP CRC/checksums and exact native closure/registrations; package-only BSL/MDL startup, real private core persistence and native DLL load with external mod/source fallback disabled. PE imports use Windows system libraries only. Camera and engine drawing are mocked in startup verification; native input acquisition, screenshots, loader activation and newly packaged GPU rendering were not tested in-game. Numeric focus/aperture and scene effects remain disabled, accurately disclosed on every page. This publication does not assert completion of the independent DoF repair.

The shader registry is an immutable native resource. When combining other packages replacing the same registry, their shader IDs require an explicit union; patch priority does not merge them automatically. Older incompatible installed MCM is refused by the existing input-ownership guard and must be disabled or updated; clean standalone startup is verified with it absent.

No game deployment or saved-settings mutation occurred in this release task. The concurrent DoF working-tree edits were preserved. Release work was isolated from that writer, and only the verified release source and assets were published. Local publication screenshots/receipts remain under dist, outside Git.
