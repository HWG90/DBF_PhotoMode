# Cinema camera development test

1. Start Photo Mode normally, place the camera and set the lens. In Director choose Begin action shot.
2. Confirm the camera does not move or turn while you walk, sprint, ADS, shoot, melee and use equipment. Confirm the avatar and projectile/aim direction behave as expected.
3. Use your Screenshot shortcut. Press the Photo Mode shortcut to reposition; the pause checkbox should read OFF and placement stays live. Pause again if needed, begin another shot, then Exit Photo Mode and confirm the gameplay camera and inputs restore.
4. Try the handoff from a paused fixed pose and during guarded hoverpack pause. Gameplay must resume only after pose and hover restoration acknowledge completion.
5. Open chat and Escape/settings while performing. Native menus must receive input; the static view stays held. Screenshot and reposition shortcuts should stay inactive while native menu cursor focus is active. Alt-Tab must not acquire input or show the indicator.
6. Die/respawn or change scene. Cinema must end and never retain a stale camera/actor reference.
7. Run standalone ActionCam in both load orders. War Journalist retains the exclusive camera lease through placement and performance; ActionCam resumes only after full Photo cleanup.

The current placement radius is 60 m. During performance the camera is not pulled along with a moving avatar. The mode ends after the verified player or scene identity changes. Assets beyond the normal streamed scene may not be rendered; keep action shots near the staged subject.

The indicator is omitted from mod screenshots. Steam/OS captures may contain it. No engine-vector objects are retained for the shot, and the runtime state is not written to settings.
