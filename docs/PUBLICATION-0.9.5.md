# War Journalist 0.9.5 publication record

Status recorded on October 13, 2026. Release publication is complete except for
Nexus's automated quarantine of the MDL download, which requires site review.

Release source: `4308eaf8bab42c259953025a04996096afc96ac3`.
The annotated tag `v0.9.5` resolves to that commit.

| Destination | Recorded status |
| --- | --- |
| [GitHub release](https://github.com/HWG90/DBF_PhotoMode/releases/tag/v0.9.5) | BSL, MDL, LLL, and `SHA256SUMS.txt` published. All four public downloads were retrieved and matched the release hashes. |
| [Nexus files](https://www.nexusmods.com/helldivers2/mods/17248?tab=files) | BSL file **68579** was downloaded through the public manual-download route and its SHA256 matched the release. MDL file **68580** is quarantined by automated checks; review/reason is pending. Only these two loader packages were uploaded to Nexus. |
| [Ayaka 0.9.5 update](https://ayakamods.com/mods/war-journalist-helldivers-2-photo-mode.4948/update/7175/) | Main entry updated and the new version's update page verified. |
| [Discord announcement](https://discord.com/channels/1260111500522295377/1559027203315073094/1559501698337079316) | Existing thread title and original post updated. New feature and bug-fix announcement published and verified. Both explain the Nexus MDL quarantine and GitHub alternative. |

Nexus's linked VirusTotal pages identify the exact release ZIP hashes:
[BSL](https://www.virustotal.com/gui/file/e90452503f629248ed79595dd98762c6698a7d6ff76911a46a8df07f6907562e)
and [MDL](https://www.virustotal.com/gui/file/af5704af9807adf43e7b934ee2e93ba62bf8eba4b72649491a9b1eb0c13517a7).
Matching identity does not establish why the MDL package was quarantined.
A [review request draft](NEXUS-0.9.5-REVIEW-REQUEST.txt) is prepared and unsent.
Ayaka's update also records the MDL download alternative. Browser page content
verified the changes. Browser screenshot capture timed out, so no screenshot
proof is recorded.

## Validation

Final BSL, MDL, and LLL archives passed static package checks and isolated
standalone execution without optional mods or repository-source fallback.
Those checks establish package contents, asset closure, native dependencies,
and fixture behavior; they do not establish a fresh in-game startup.

| Archive | SHA256 |
| --- | --- |
| `War-Journalist-0.9.5-BSL.zip` | `e90452503f629248ed79595dd98762c6698a7d6ff76911a46a8df07f6907562e` |
| `War-Journalist-0.9.5-MDL.zip` | `af5704af9807adf43e7b934ee2e93ba62bf8eba4b72649491a9b1eb0c13517a7` |
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

**Normal Arsenal deploy is still required for the dedicated Photo light asset.**
Updating the source assets did not regenerate Arsenal's merged game patches.
No documented deployment CLI/local API was found in the installed app, so no
alternate deployment mechanism was used. Follow deployment with a normal
game restart. The final release's cold startup remains untested, and the new
dedicated mission-light asset remains **Not tested fully**.

Local receipts are retained under ignored `dist/` paths:

- `dist/releases/War-Journalist-0.9.5/RELEASE-BUILD-RECEIPT.json`
- `dist/releases/War-Journalist-0.9.5/PACKAGE-VALIDATION.json`
- `dist/validation/release-0.9.5-{BSL,MDL,LLL}-static.json`
- `dist/validation/public-download-0.9.5/DOWNLOAD-VERIFICATION.json`
- `dist/review/release-0.9.5-local-install/DEPLOYMENT-RECEIPT.json`
- `dist/review/release-0.9.5-local-install/backup-20261013-053107/`

See [release notes](RELEASE-0.9.5.md) and [known issues](KNOWN-ISSUES.md) for
feature coverage and remaining limits.
