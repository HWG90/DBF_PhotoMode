# Known issues in 0.9.5

- **Mission photo-light asset fix: Not tested fully.** Dedicated light assets are now bundled so spawning no longer relies on a ship-only prefab. The earlier ship light was demonstrated live; the new asset path has offline validation only. Availability still requires the correct assets to be loaded after restart.
- Native focus/aperture and camera-instance recovery were user-tested during development. This does not prove every scene, game update, ragdoll or transition. Controls wait for a validated current camera rather than writing through a stale one.
- Shader DoF and scene grading share a full-resolution compositor. HDR tint/exposure was accepted with neutral grading, no scene effect and active Shader DoF. SDR compositor parity and every effect combination remain unverified. Blurred HDR energy above GUI white remains limited by the GUI carrier. Native remains the blur-quality baseline.
- WARMING UP SCENE may remain briefly after launch or display changes while resources stabilize. Install all assets included with your chosen loader package and restart after changing them.
- The reported hoverpack + melee pause/resume reproduction passed with the data-only guard. This is limited test coverage. Connected or unidentified controllers refuse active-hover guarded pause. Pause and slow motion require a verified solo session.
- Screenshot conversion includes SDR channel and HDR brightness fixes; ship UI may still appear. The rebindable Pause shortcut is fixture-tested; this release does not claim a separate live keyboard-trigger validation or intercept Windows Print Screen.
- AI passive/dummy controls are not integrated into this release. Director currently provides camera presets.
- Shader packs replacing the default shader registry require a registration merge. Run only one Photo Mode runtime loader at a time.
- No general alt-tab crash fix or HDR/SDR switching crash fix is claimed. Newly bundled logos, mission lights and complete release cold-start behavior have not all received fresh live acceptance.
