# War Journalist 1.0.1

**Actually 1.0 this time.**

- **BSL startup with supported ActionCam:** finds the verified ActionCam 2.3.1/2.4 callbacks through loader wrappers, so a supported installation is no longer mistaken for an unknown camera owner. The exact closure-signature checks remain in place; this does not grant compatibility to unknown versions.
- **Saved tab layouts:** under **Composition → Menu layout → Tab layout**, choose **Slim** for one row or **Stacked** for two rows. The selection survives restarts; the global Freeze/AI/Slow Motion/Lock controls stay available.
- **Clearer icons:** Director uses a clapperboard, Subject uses a helmet, and Controls uses a cross icon.

All 1.0 features, artwork, credits and testing limits remain included below. The accepted compositor and shader assets are unchanged. Choose the matching `War-Journalist-1.0.1-BSL.zip`, `War-Journalist-1.0.1-MDL.zip` or `War-Journalist-1.0.1-LLL.zip`; GitHub offers all three, while Nexus offers BSL and MDL. Preserve settings, presets and screenshots when replacing the older runtime and deploying its matching bundled assets.

---

# War Journalist 1.0

A Helldivers 2 Photo Mode.

**1.0 is here! A HUGE THANK YOU to everyone sharing photos, testing builds, reporting bugs and helping get this thing over the line.** The community's shots and feedback have shaped these tools. Please keep the photos coming.

## Place the camera. Get back into the action.

**Director → Begin action shot** holds your chosen camera position, angle, roll and field of view while you control your Helldiver again. Stage an action shot, use the screenshot shortcut, then press your Photo Mode key to reposition. Returning to placement restores Freeze Action if it was enabled before the shot; your selected slow-motion rate is preserved. Exiting Photo Mode returns to the gameplay camera.

Record **up to 32 camera path points**, adjust each segment's duration, and choose **Smooth** movement or a **Cut**. Play the path while controlling your Helldiver; the final camera stays held when playback completes. Paths belong to the current player and scene and are not saved across restarts. A brief unavailable scene read no longer deletes recorded points; confirmed player or scene changes still end the shot and clear them.

## The controls you need stay within reach

- **Freeze Action, Slow Motion with its speed slider, Lock Camera and enemy behavior** are available in the global toolbar. Slow-motion selection and speed survive entering and leaving Photo Mode. Freeze overlays that rate, so resuming returns to it instead of forgetting it.
- **Normal, Passive and Dummy** enemy behavior has a mission-faction icon and remains restricted to verified solo missions. Passive suppresses detection; Dummy also restricts ordinary movement. The selection persists after leaving Photo Mode and covers newly discovered enemies. Reset restores Normal. Joining players disables the controls and restores owned changes; restarting begins at Normal.
- The left-edge controls drawer changes between menu and camera instructions. Its tab can be repositioned. Menu position, size and opacity remain saved through restarts.
- Native Escape/settings menus and chat take priority over Photo Mode input. Input recovery restores the gameplay camera and cursor ownership after handoffs. The camera cursor stays confined to the game window; the actual Helldivers cursor is used for menu interaction.
- Buffered mouse clicks make double-click focus reliable between render frames. Double-click another subject at any time, use Center auto-focus, or scrub focus manually with Shift for finer control.

## Poses, capes and a properly frozen ragdoll

The **213 sampled pose frames and variants** remain available under Subject while Freeze Action is enabled. Switch poses without advancing world time, then Reset to your original stance. These are sampled emote/action frames, not 213 unique store emotes. Props and another participant are not spawned.

The cape correction now handles the additional outfit variant reported by testers, retaining the original cape appearance and following the shoulders through pose changes and Reset. Unsupported cape classes still skip the correction; the existing cloth shape is retained rather than re-simulated.

**The reported spinning-ragdoll case at exact zero world time is fixed.** Photo Mode holds the captured ragdoll pose while frozen and restores its original animation mode before resuming. The live reproduction stayed still, kept the original pose and resumed normally. This does not disable the engine's physics globally or establish every ragdoll/equipment combination.

**Maxigun ammunition feeds now hide with their owned equipment.** The belt is a separate render unit; hiding the player or weapons now includes that verified local attachment without hiding unrelated scene cables.

## The full photo studio stays included

Native focus/aperture, shader DoF preview with round/hexagonal bokeh, autofocus, lens presets, scene color/depth effects, decorative overlays, framing guides, logos, SDR/HDR screenshot conversion, and five saved player-relative Director cameras remain bundled. So do up to three point/spot lights, draggable indicators, subject-focused presets, five saved lighting setups, and the color editor's Apply button and live swatch.

The earlier shader-registry repair is retained. Affected Radeon testers reported stable Alt-Tab, fullscreen, bloom and DoF changes before and after opening Photo Mode. This is evidence for those reported triggers, not a guarantee against every driver or display-setting crash; HDR/SDR switching still needs separate confirmation.

## ActionCam and installation

Supported standalone **ActionCam 2.3.1 and 2.4 may remain enabled**. ActionCam controls normal gameplay; War Journalist takes the photo/cinema camera and returns ownership after cleanup. Unknown ActionCam versions and other camera mods need separate compatibility work.

Choose one complete package: **BSL v15+ / API 1**, **MDL API 2**, or **LLL**. GitHub offers all three; Nexus offers BSL and MDL. Each archive includes its runtime, native helpers, shaders, materials, lights and logos. No separate Photo Mode asset download, MCM, DBF-HUD, ActionCam or Link's Link to Memory addon is required. Optional MCM integration remains available.

Follow the included `INSTALL.txt`, replace the old Photo Mode runtime, deploy the matching bundled assets, and restart. Preserve settings, bindings, presets and screenshots. MDL's archive has no nested ZIP: copy `dbf_freecam` into MDL Mods and deploy its `GameData` assets using the included instructions. Run only one Photo Mode runtime. Other mods replacing the shared shader registry still require a proper merge.

## Test scope

Live development checks confirmed the action-shot/return-to-placement flow, retained slow-motion/Freeze behavior, the reported cape variant, and captured-ragdoll hold and resume. Native focus/aperture and earlier stability fixes were also user-tested. Broader scene, respawn, equipment, loader and camera-mod combinations remain testing territory.

**Lighting: Not tested fully. Shader DoF remains a preview; Native remains the blur-quality baseline.** SDR compositor parity and every combined effect have not been established. HDR highlights above the GUI carrier's white level remain limited. The hoverpack guard covers its reported reproduction and requires neutral controls; connected or unidentified controllers refuse active-hover guarded pause. Pause, slow motion, fixed poses and enemy-behavior changes require verified solo authority. Passive/Dummy do not stop AI processing, damage, physics or attacks already in progress.

## Credits

Camera foundation: **ActionCam by HuedPurple**. Native UI/font reader: **CowboyBingus (0BSD)**. Selected native reader work: **Link (MIT)**. Individual logo sources, authors and licenses are bundled. Helldivers 2 and Arrowhead artwork belongs to its respective owners.

And again: **THANK YOU to everyone contributing photos, testing and bug reports.** Include your loader, scene/equipment and reproduction steps when reporting a problem.
