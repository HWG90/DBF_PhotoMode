# Helldivers 2 offline/no-EAC investigation

Date: 2026-10-25

## Goal

Determine whether the current public Helldivers 2 build supports an offline,
no-Easy-Anti-Cheat launch path through configuration, comparable to Space
Marine 2.

## Decision

No supported configuration-only path was found. The current public HD2 Steam
launch configuration routes through `start_protected_game.exe`, and the local
retail files contain no offline or no-EAC setting. A direct protection bypass
is outside this configuration investigation and must not be represented as an
offline mode.

## Evidence

- Steam App 553850's public Windows launch target is
  `start_protected_game.exe --bundle-dir data --release`.
- The locally installed `EasyAntiCheat/Settings.json` identifies
  `bin/helldivers2.exe` as the protected executable and contains no disable or
  offline flag.
- The locally installed `data/settings.ini` contains no EAC or offline launch
  permission.
- The EAC launcher accepts `-anticheat_settings=...`, but the published HD2
  configuration uses that to select another protected profile. It is not a
  no-EAC switch.
- Space Marine 2's Steam configuration lists separate `noEAC` bootstrap
  targets, providing the product-owned separation that HD2 lacks.
- Arrowhead's public FAQ says Helldivers 2 requires an internet connection.

## Validation

This was a read-only investigation. No HD2 executable, configuration, Steam
manifest, or EAC file was changed, and no alternate launch was attempted.

## Sources

- https://steamdb.info/app/553850/config/
- https://steamdb.info/app/2183900/config/
- https://arrowhead.zendesk.com/hc/en-us/articles/12571604061212-Helldivers-2-FAQ

## Unresolved items

- Arrowhead could add an official offline/no-EAC launch target in a future
  build.
- Internal development launch options are branch or entitlement restricted and
  do not establish a usable public retail path.
- A useful future check is to diff Steam launch metadata and local configuration
  after updates; no recurring polling is necessary.
