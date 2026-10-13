# War Journalist 0.9.5 publication record

Status recorded on October 13, 2026. Release publication is complete. The MDL
package was subsequently replaced with a flat ZIP containing no nested archives.

Release source: `4308eaf8bab42c259953025a04996096afc96ac3`.
The annotated tag `v0.9.5` resolves to that commit.

| Destination | Recorded status |
| --- | --- |
| [GitHub release](https://github.com/HWG90/DBF_PhotoMode/releases/tag/v0.9.5) | BSL, MDL, LLL, and `SHA256SUMS.txt` published. All four public downloads were retrieved and matched the release hashes. |
| [Nexus files](https://www.nexusmods.com/helldivers2/mods/17248?tab=files) | BSL file **68579** was downloaded through the public manual-download route and its SHA256 matched the release. Flat MDL replacement **68590** cleared scanning and exposes public download controls. Original MDL **68580** was archived after quarantine. Only BSL and MDL are published on Nexus. |
| [Ayaka 0.9.5 update](https://ayakamods.com/mods/war-journalist-helldivers-2-photo-mode.4948/update/7175/) | Main entry updated and the new version's update page verified. The update now records cleared Nexus MDL scanning and flat installation steps. |
| [Discord announcement](https://discord.com/channels/1260111500522295377/1559027203315073094/1559501698337079316) | Existing thread title and original post updated for release. The feature and bug-fix announcement now records cleared Nexus MDL scanning and flat installation steps. |

Nexus's linked VirusTotal pages identify the exact release ZIP hashes:
[BSL](https://www.virustotal.com/gui/file/e90452503f629248ed79595dd98762c6698a7d6ff76911a46a8df07f6907562e)
and [flat MDL](https://www.virustotal.com/gui/file/1c6d7b232229af6edbee61121c024d646d00e1630edcdae1ef956a650f463c94).
Matching identity does not establish why the original MDL package was quarantined.
A [review request draft](NEXUS-0.9.5-REVIEW-REQUEST.txt) remains unsent; the user
chose the flat re-upload instead.
Browser page content verified the changes. A Nexus files-page screenshot now
records both download entries, their green scan indicators and manual-download
buttons. The replacement's public Nexus download has not been hash-verified;
GitHub's replacement download has. Earlier release screenshot capture timed out.

## Validation

Final BSL, MDL, and LLL archives passed static package checks and isolated
standalone execution without optional mods or repository-source fallback.
Those checks establish package contents, asset closure, native dependencies,
and fixture behavior; they do not establish a fresh in-game startup.

| Archive | SHA256 |
| --- | --- |
| `War-Journalist-0.9.5-BSL.zip` | `e90452503f629248ed79595dd98762c6698a7d6ff76911a46a8df07f6907562e` |
| `War-Journalist-0.9.5-MDL.zip` (flat revision) | `1c6d7b232229af6edbee61121c024d646d00e1630edcdae1ef956a650f463c94` |
| `War-Journalist-0.9.5-LLL.zip` | `9eaec10d55ff1f8c454235ef23ff304b22f27f1f819f34da68707101891c2bc5` |

The user confirmed the original hoverpack + melee + Photo Mode pause/resume
reproduction worked in the development runtime. Four earlier basic pause/resume
cycles are separate evidence. See [the scoped hover verification](HOVER-PAUSE-VERIFICATION.json).
Connected or unidentified controllers still refuse active-hover guarded pause.

## Local installation

At `2026-10-13T09:31:08Z`, the final LLL runtime and existing Arsenal Photo
source assets were installed and verified against the final package. Nineteen
files were added or replaced, with existing versions backed up; 57 runtime/source
files were verified. Existing
configuration, settings, screenshots, unknown files, Arsenal manager data, and
nine merged game archive files remained unchanged. The local Arsenal entry's
GUID and option selection were preserved.

The user subsequently deployed through Arsenal and restarted. In the fresh game
process (PID 75972), the dedicated Photo light unit `e07f49224f0a5759` is present
in `9ba626afa44a3aa3.patch_89`. Its 976-byte payload matches the source, SHA256
`2978bb39852caecc576a3bcf3aecdca6b366103e7a6b6892c3fe899aa18c1f69`.
The session log records successful light creation. Full **Exit photo mode**
intentionally removes the owned lights; Tab/camera controls and Hide preserve
them. Scalar light settings are retained, but placed units/positions are not
automatically recreated on re-entry. Broader mission-light testing remains
**Not tested fully**.

## Flat MDL packaging revision

The original published MDL ZIP (SHA256
`af5704af9807adf43e7b934ee2e93ba62bf8eba4b72649491a9b1eb0c13517a7`)
was repacked without rebuilding runtime or game assets. Fifty-one entries remain
byte-identical. The nested asset ZIP was removed and its Arsenal manifest moved
to the root; installation documents and file checksums were updated. The root
manifest installs `GameData` only. Users copy `dbf_freecam` into MDL Mods separately.

The 2,225,196-byte replacement passed static and isolated standalone checks,
including a scan for nested archive signatures. Existing BSL and LLL packages
also pass the updated verifier. GitHub's replacement MDL was downloaded and its
hash matched; `SHA256SUMS.txt` was replaced with all three current package hashes.
The original release tag remains unchanged. No runtime changes or local runtime
redeployment were required for this packaging revision.

Local receipts are retained under ignored `dist/` paths:

- `dist/releases/War-Journalist-0.9.5/RELEASE-BUILD-RECEIPT.json`
- `dist/releases/War-Journalist-0.9.5/PACKAGE-VALIDATION.json`
- `dist/validation/release-0.9.5-{BSL,MDL,LLL}-static.json`
- `dist/validation/public-download-0.9.5/DOWNLOAD-VERIFICATION.json`
- `dist/review/release-0.9.5-local-install/DEPLOYMENT-RECEIPT.json`
- `dist/review/release-0.9.5-local-install/backup-20261013-053107/`
- `dist/releases/War-Journalist-0.9.5-MDL-flat-r1/REPACK-RECEIPT.json`
- `dist/releases/War-Journalist-0.9.5-MDL-flat-r1/PACKAGE-VALIDATION.json`
- `dist/validation/public-download-0.9.5-mdl-flat-r1/`
- `dist/review/photo-light-deployment-75972-20261013/READONLY-AUDIT.json`

See [release notes](RELEASE-0.9.5.md) and [known issues](KNOWN-ISSUES.md) for
feature coverage and remaining limits.
