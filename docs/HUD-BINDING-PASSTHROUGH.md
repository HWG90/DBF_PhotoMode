# Game HUD binding passthrough

The Windows input adapter reads the saved `Misc.ToggleHudVisibility` action
when acquiring keyboard input. It discovers the selected Steam account from
`loginusers.vdf` (the sole account or the unique MostRecent account), then reads
that account's `553850/remote/input_settings.config`. Ambiguous accounts are
reported as unavailable. SteamID64 subtraction uses decimal limbs to avoid
Lua 5.1 double rounding.

The assigned keyboard keys are removed from the helper's capture mask. Other
gameplay keys retain their existing isolation. Menu/camera transitions reuse
the mask; a new input acquisition refreshes it. No files are read per frame.

The Photo Mode toolbar displays the binding instead of an actionable Toggle HUD
button. It warns when the action is unbound or its configuration cannot be read.
Binding changes invalidate retained menu geometry; unchanged state stays cached.

This enables the player's HUD shortcut. It does not dispatch the action directly,
read native HUD visibility, or implement automatic screenshot hide/restore.

The toolbar uses the assigned game binding, such as `Toggle HUD [/]`, instead
of a separate toggle action. The mask is refreshed on input acquisition; a game
binding change takes effect when Photo Mode next acquires input.
