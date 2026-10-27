# Windows depth-assisted subject selection

Private portable.22.3 corrects a target-ranking bug. The sampled depth can
intersect both the Helldiver's body and broad upright proxies belonging to
other animated units. Comparing their screen-distance scores directly lets a
generic proxy beat a valid body intersection, leaving pose selection unavailable.

The picker now prefers a depth-qualified intersection with the known Helldiver
body joints over a generic upright proxy. The body must still pass the current
surface-depth test: a Helldiver behind the clicked surface gains no preference.
Within either geometry class, the existing screen/depth ordering remains.
Units and joints are read only on an explicit pick; no scene cache or idle
enumeration was introduced.

On Steam build 26088801, the portable.22.3 six-point test selected the visible
Helldiver at UV (0.35, 0.5), depth 0.941 m. The body resource was
`4d1c334d294dfa97`; three generic units also qualified. The previous winning
resource `a9936cbe561e8180` scored 19.640 pixels against the body's 191.646,
confirming why the old ranking picked the wrong target. Its exact asset name
and relationship to the player remain unproven; it is not labeled an attachment
in the runtime contract.

Four valid background samples missed. One background point had no focusable
surface and did not select anything. Captures showed the menu and font intact,
then Photo Mode closed; input/time restoration were acknowledged. Settings were
unchanged. Depth sampling cost 31-35 ms total and picking 1-3 ms in this run.
This is synchronous work on explicit selection, not a steady-state cost claim.

Validation: 77 Lua fixture groups passed, all 69 packaged Lua modules matched
source, 15 ZIP checksums passed, and all nine installed files matched the ZIP.
Regression fixtures cover reversed enumeration order, overlapping proxies,
foreground occlusion, prone body geometry, and no idle work. Live evidence is
retained in `dist/review/windows-selection-body/LIVE-RESULT.json` and its captures.

This validates one reproduced Helldiver selection failure. Broader enemy,
ragdoll, posed-body, mission, and physical double-click coverage remains open.
Native DoF and shader assets were unchanged. Ragdoll/hoverpack freezing and
GPU scene-shader depth binding remain separate unresolved work.
