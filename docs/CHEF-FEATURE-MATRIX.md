# War Journalist to Chef: preview 5 feature matrix

2026-10-27. Compared against WJ 1.3.0 Steam Lua 5.1 and Chef 1.2.4/API 3,
revision `b7434c7289bbb9adbfeb2d3bdb57134218f2a509`. Minimum Chef remains 1.2.3;
the sandbox blob is unchanged. [Copyable BBCode](CHEF-FEATURE-MATRIX.bbcode).
Implemented means source and isolated fixtures with mocked engine calls. No row
is live-game acceptance. Shader effects and AI are excluded by the requested scope.

| Workflow | Chef candidate | Boundary/adaptation |
| --- | --- | --- |
| Freecam, mouse, speed, rotation/roll/zoom | Implemented | Rebindable clutch; shared gameplay input; opens in Chef menu |
| Smoothing, lock, reset, level/portrait tilt | Implemented | Unscaled clock; immediate reset on input handoff |
| Wheel speed/world-up elevation/independent roll and zoom rates | Implemented | Clutch-gated wheel and adjustable step |
| Focal shortcuts | Implemented | 24 mm sensor-height convention; vertical FOV |
| Freeze/resume/slow rate | Implemented, solo preview | Exact-zero request, visible-peer checks; cleanup to 1x |
| Placed/path Cinema | Implemented | Pose reset before thaw, remembered freeze, return/end actions |
| Camera paths with segment editing | Implemented | Maximum 32 points; session-local; Smooth/Cut |
| Five scene bookmarks | Implemented | Expire on camera close |
| Five saved camera presets | Adapted | Opening-camera-relative, not player-relative |
| Point/spot/cone/RGB/intensity/enable | Implemented, experimental | Three owned lights; visible output unverified |
| Light range | Conditional | 8 m default; other ranges require native getter/readback |
| Light markers/dragging/fine adjustment | Implemented | Clutch + middle mouse; captured camera plane |
| Light follow/aim/automatic rigs | Adapted | Camera follow and numeric target distance, no actor tracking |
| Light color editor/Apply/swatch | Implemented | Chef rows and optional color preview |
| Five saved lighting setups | Implemented | Camera-relative definitions, partial-failure rollback |
| Light restoration on reopen | Implemented | Removes units on close; definitions tied to world/generation/session |
| Edit light at existing anchor | Implemented | Load selected settings, then explicit Apply without camera reanchoring |
| 213 poses/select/apply/reset/recover | Experimental | Explicit exact-rig selection, Freeze and one visible peer |
| Subject/equipment/cape visibility | Unavailable | No verified readable visibility/attachment ownership contract |
| Cape pose adaptation/frozen ragdolls | Unavailable | Required attachment/physics contracts absent |
| Handycam/local-player follow | Unavailable | No authoritative actor/equipment resolver |
| Native bloom toggle | Implemented, experimental | Observed baseline, bounded acknowledgement |
| Native DoF toggle | Implemented, experimental | Boolean only; game-controlled focus |
| Numeric DoF/autofocus/click focus | Unavailable | Existing native lens packet/ownership route is outside Chef |
| Frames/guides/tint/vignette/grain/clean view | Implemented | Screen overlays, no custom scene shader |
| All curated logos/RGB/size/opacity/position | Implemented | Bounded prebaked spans; reduced edge detail |
| Movable legend | Implemented | Position/scale/opacity via Chef rows |
| Legacy draggable studio panel | Adapted | Chef menu owns edits; no custom input capture |
| Hotkeys/settings | Adapted | Optional P/Backslash gameplay shortcuts, default off; Chef menu suppression, no native chat detection |
| Retain slow motion after manual close | Implemented, opt-in | Thaws Freeze; focus/world/session/stop still restore 1x |
| External screenshot view | Adapted | Hides WJ annotations, keeps artwork; uses an external capture key |
| Gameplay suppression/cursor confinement | Unavailable | Chef has input reads, not the native input broker |
| WJ PNG capture/housekeeping | Unavailable | No capture descriptor/helper or supported file-output contract |
| Game HUD hiding | Unavailable | No verified readable ownership/restore contract |
| Shader effects/custom compositor/bokeh | Excluded | User scope; no shader resources packaged |
| AI/passive/enemy controls | Excluded | User scope; no AI actions implemented |

Unavailable rows have no success-returning stubs. Use an external screenshot
key. Clean composition affects WJ guides/logo, not game HUD. Dynamic light range
and selected-subject failures report reasons instead of claiming parity.

Source is under `freecam/chef/`, reusing portable camera/path and exact-matrix
subject modules. Native capture, visibility, input and lens adapters in the
legacy source depend on services Chef does not supply. Reusing an FFI adapter
or fabricating a qualified receipt cannot make those services available. These
features need a supported loader/engine contract and direct gameplay evidence.
See [the loader contract and sources](CHEF-LOADER-PORT.md).

WJ 1.3.0's accepted Steam graph is distinct from newer experimental Subject work.
Its release notes already list poses/visibility/cape, Handycam, HUD hiding and
numeric DoF as unrestored. Chef's pose experiment does not inherit live acceptance
from that release. Native PNG capture and Tab-based input/menu ownership require
LLL services with no equivalent public Chef capture/menu-control API.
