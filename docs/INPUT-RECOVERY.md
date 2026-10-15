# Gameplay mouse recovery development candidate

This candidate prevents Photo Mode from capturing a mouse state already held by
Epic LUT, MCM or the LLL manager. Epic LUT can borrow Photo's input through an
acknowledged handoff; Photo waits until Epic releases it before resuming capture.
Each provider keeps ownership until its own native input and cursor restoration
finish. A failed or unknown ownership read blocks a new capture.

If gameplay look becomes stuck, focus the game and press **Ctrl+Shift+F10**.
Alternatively choose **Controls → Recover gameplay mouse**. Controls also lets
you rebind the recovery key; Ctrl+Shift remain required for the shortcut.

Recovery closes cooperating Epic LUT, MCM and LLL menus, exits Photo Mode, and
waits for pose, simulation and input cleanup. Once all known owners acknowledge
release, it restores gameplay mouse focus and hides the menu cursor. Close the
game's Escape/settings menu and chat if recovery reports that they are still
active. The log reports either the pending owner or `gameplay mouse restored`.
Recovery restores normal time and exits an action shot. It does not synthesize
key releases or change saved keybinds, artwork, screenshots or presets.

This package contains no new native input DLL or runtime hook. Separate Epic LUT
and MCM Lua fixes accompany the local development installation. The Photo fix
also recognizes older Epic frontends, while the updated Epic frontend handles
release failures and replaced providers explicitly.

Both legacy and independent-camera packages are review candidates based on
1.0.1. They are not public releases. Offline tests reproduce the invalid restore
state and exercise both editor opening orders, pending cleanup and the recovery
shortcut. Actual gameplay confirmation with Epic LUT and Photo Mode together is
still required. LLL candidates require a normal game restart to activate.
