# War Journalist 1.2.1 — Less stutter, more photos

**A HUGE THANK YOU to everyone submitting photos, testing builds and reporting bugs.** And thank you for spotting the little control legend trying to eat the frametimes. Keep those shots coming!

- **Fixed the regular panel/legend hitch:** unchanged layout and draw commands now stay retained. Recreated choice lists with identical contents no longer force a full rebuild. Confirmed live with the legend enabled.
- **Lighter camera validation:** genuine camera handles are discovered once, then checked against the current Unit generation and world before use. Repeated full-world enumeration is removed from the active path.
- **Less allocation:** renderer-target checks and native lens reads reuse bounded buffers. Resource/lifetime checks remain fresh. Existing font atlas binding is preserved.
- Menu edits, pointer interaction, layout changes, changed availability and temporary font failures still update/retry normally. The camera open/close/reopen handoff was tested during this investigation.

All 1.2.0 handycam, smoothing, smooth wheel zoom, lighting and subject-visibility features remain included. This fixes the reproduced regular UI humps; occasional random spikes can still occur. Live confirmation was on LLL, with isolated fixtures and standalone package verification for BSL, MDL and LLL. No universal FPS promise.

Choose one complete package for your loader. Preserve settings, presets and screenshots, replace the runtime and matching bundled assets, then restart normally. Do not mix versions. Public scene-effects and numeric-DoF gates remain unchanged; native hover hooks and Tactical Video Camera experiments are not included.
