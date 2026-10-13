# Dedicated Photo light boot asset

0.9.5 release lighting status: **Not tested fully**. The complete package
bundles the dedicated unit below; its structure and dependency closure pass
offline checks. Startup loading and mission illumination remain unverified.

The current ship light prototype is unavailable on a mission when the ship's
resource package is no longer loaded. This is not an indefinite warm-up. Its
976-byte unit also refers to ship geometry group `ddf83b892394e370` (199,801,432
GPU bytes) and ship material `7c763e4de74815e3`. Copying that unit unchanged would
retain those ship dependencies.

`tools/photo_light_assets.py` supplies the dedicated resource
`mods/dbf_photo/units/photo_light_v1`, ID `e07f49224f0a5759`. It contains one point
light attached to root node 1, embedded transform data, and generic compiled
unit metadata. It contains no mesh, material table, GPU/stream payload, external
geometry, bones resource, or state machine. Its CPU definition is 976 bytes,
SHA256 `2978bb39852caecc576a3bcf3aecdca6b366103e7a6b6892c3fe899aa18c1f69`.

The compiled format follows the retained light-only structure whose exact
source hash is checked by the builder. The two archive reference fields are
optional: stock shared-boot unit `6906ba0515f518d7` already has both fields zero.
That independent stock unit has the same format fields and light/node section
offsets. The new definition preserves the valid light-only sections, removes
only those two references, and sets its default intensity/range to 3/8 metres.
It is a compiled structural derivative, not output from an installed Stingray
editor compiler. Engine loading remains a required test.

## Integration

Append `photo_light_assets.resources()` to the complete Photo build's shared
resource list before serializing `9ba626afa44a3aa3.patch_0`. Preserve every
existing runtime/material/shader entry. The game already loads three stock
unit resources from this shared boot archive. The candidate uses that existing
startup route; it does not assume an exposed `Application.resource_package`
constructor. The cached game inventory exposes ResourcePackage operations but
not that constructor.

The lighting manager must select the new resource ID and continue owning its
spawned units, root-node placement, queued update-phase edits, and exit/world
cleanup. No authored world unit is edited. Existing native point/spot, color,
range, and intensity setters still configure the owned light.

The standalone review ZIP contains only the new additive boot asset. Merge it
into the owning full package; do not directly replace the complete Photo
archive with its single-resource archive. The release validator must recognize
and check this explicit unit resource alongside its existing asset closure.

The release helpers are `merge_resources(existing_rows)` (exact idempotent
addition), `validate_bundled_archive(cpu, gpu, stream)` (owned unit bytes and
dependency closure), and `validate_archive(cpu, gpu)` (existing decorative
closure plus that exact unit). The latter rejects every other unexpected native
resource. Preserve the existing DoF/compositor validation for its own rows and
attach the light audit as `photo_light`; do not replace that validation.

## Evidence and next test

Read-only base archive/resource evidence is in
`dist/review/photo-light-package-20261013`. The ship source SHA256 was independently
re-read through the bounded DSAR/DSAA reader and matches the previous lighting
inventory. The shared stock light proves optional zero dependency references.
The parser layout is cross-checked against
[Filediver's unit definition](https://github.com/xypwn/filediver/blob/master/stingray/unit/unit.go).

Run `py -3.14 tools/test_photo_light_assets.py`, optionally with `--base-zip`
pointing to the complete current Photo package. It rejects external references,
mesh sections, wrong root/type, missing light, and truncated definitions, and
verifies every preexisting resource survives merging byte-for-byte.

Offline structure/archive/ZIP checks do not establish a loaded or rendered
light. After the full candidate is installed and normally started, first check
`Application.can_get('unit', IdString64.from_hex('e07f49224f0a5759'))`. If true,
verify an owned spawn contains light 1 on node 1, then capture its illumination
on a mission. Ship-only availability cannot complete that verification.

[Autodesk's light creation documentation](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/stingray_help/lighting_rendering/lighting/light_sources/create_light_source.html)
supports the unit-containing-light route. Its
[package documentation](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/stingray_help/managing_content/loading_unloading/loading_unloading_packages.html)
describes runtime package loading, but the candidate deliberately uses the
existing game boot archive because that constructor is not verified here.

Status: **Not tested fully**. Mechanically validated and prepared for the 0.9.5
package; not engine loaded or visually verified. No game, saved settings, or
LinkToMemory changes were made by the asset preparation.
