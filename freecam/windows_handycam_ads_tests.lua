local M=dofile('freecam/windows_handycam_ads.lua')
local messages={};local a=M.new(function(v)messages[#messages+1]=v end)
local head={head={0,0,0}};local f={position={.163,0,0},forward={1,0,0}}
for i=1,1000 do assert(not a.observe(f,head,i))end;assert(#messages==0)
a.set_active(true,0);a.submitted(f.position,f.forward)
for i=1,60 do a.observe(f,head,i*.001)end;assert(not a.suspended,'Own camera output cannot establish ADS')
a.event('middle',true,.1);f.position={.17,0,0};a.observe(f,head,.11);assert(not a.suspended);a.observe(f,head,.12);assert(a.suspended)
a.event('middle',false,.19);a.event('middle',true,.2);f.position={1.132,0,0};a.observe(f,head,.21);a.observe(f,head,.22);assert(not a.suspended)
-- Remembered first-person mode can appear late after pressing aim.
a.event('right',true,1);a.observe(f,head,1.01);a.observe(f,head,1.02);assert(not a.suspended)
f.position={.17,0,0};a.observe(f,head,1.2);a.observe(f,head,1.21);assert(a.suspended)
a.observe(f,head,1.6);assert(not a.pending());f.position={3,0,0}
for i=1,1000 do a.observe(f,head,2+i)end;assert(not a.suspended,'Persistent Handycam intent recovers a late native return without another input event')
f.position={.17,0,0};a.observe(f,head,1002.5);assert(not a.suspended,'Return-only fallback cannot enter ADS without an event')
f.position={3,0,0}
a.event('right',false,1003);a.observe(f,head,1003.01);a.observe(f,head,1003.02);assert(not a.suspended)
-- Menu/focus changes preserve the shot state but require fresh classification on return.
a.set_active(false,1004);a.event('middle',true,1004);assert(not a.pending())
a.set_active(true,1005);assert(a.pending());f.position={.5,0,0};for i=1,128 do a.observe(f,head,1005.001)end
a.observe(f,head,1005.002);assert(not a.pending()and not a.suspended,'Ambiguous evidence has a finite work budget')
a.reset();assert(not a.suspended and not a.pending());print('ADS candidate: event windows, near/far hysteresis, output echo, delayed aim, idle and reset passed')

do
 local transitions=0;local b=M.new(function()transitions=transitions+1 end)
 b.set_active(true,0);b.event('middle',true,0)
 f.position={.17,0,0};b.observe(f,head,.01);b.observe(f,head,.02);assert(b.suspended and b.pending())
 for i=1,20 do
  b.event('middle',true,0) -- Replay of the exact same engine event.
  f.position={.5,0,0};b.observe(f,head,.02+i*.01);b.observe(f,head,.025+i*.01)
 end
 assert(b.suspended and transitions==1,'A completed handoff must not oscillate during camera settling or duplicate events')
 b.event('middle',true,.31) -- Release may have been lost during a native input-context switch.
 f.position={1.13,0,0}
 b.observe(f,head,.32);b.observe(f,head,.33);assert(not b.suspended and transitions==2,'A subsequent pressed event can resume even when its preceding release was missed')
 b.set_active(false,.4);b.set_active(true,.5);f.position={.17,0,0}
 b.observe(f,head,.51);b.observe(f,head,.52);assert(b.suspended,'Focus/menu return reconciles current native camera once')
 b.event('middle',false,.6);f.position={1.13,0,0}
 b.observe(f,head,.61);b.observe(f,head,.62);assert(not b.suspended,'A release-only exit reconciles without waiting for aim release')
 b.event('middle',false,.7);f.position={.17,0,0}
 b.observe(f,head,.71);b.observe(f,head,.72);assert(b.suspended,'A release-only entry also follows native evidence, never blind toggling')
end

do
 local b=M.new();b.set_active(true,0);f.position={.17,0,0};b.observe(f,head,.01);b.observe(f,head,.02)
 assert(b.suspended)
 -- Native ADS entry needs confirmation; exit must reclaim on the first far
 -- frame, even between old cadence ticks and without either input edge.
 f.position={.5,0,0};b.observe(f,head,.021);assert(b.suspended)
 b.observe(nil,head,.022);assert(b.suspended)
 f.position={1.13,0,0};local suspended,changed=b.observe(f,head,.023)
 assert(not suspended and changed,'First far frame must exit ADS without an event or timer delay')
 b.reset();b.set_active(true,1);f.position={.17,0,0};b.observe(f,head,1.01);b.observe(f,head,1.02)
 b.set_active(false,1.1);f.position={1.13,0,0};for i=1,100 do b.observe(f,head,2+i)end
 assert(b.suspended,'Inactive/menu/focus guard disables fallback work')
end

-- A rapid exit/re-entry can be delivered as one event batch, followed by
-- native camera changes on later render frames. The observation window must
-- survive the first handoff; it is not a one-transition event token.
do
 local b=M.new();b.set_active(true,0)
 f.position={.17,0,0};b.observe(f,head,.01);b.observe(f,head,.02)
 assert(b.suspended)
 b.event('middle',true,.1);b.event('middle',false,.1)
 f.position={1.13,0,0};b.observe(f,head,.11);assert(not b.suspended)
 b.submitted({.14,0,.07},{1,0,0})
 f.position={.17,0,0};b.observe(f,head,.12);b.observe(f,head,.13)
 assert(b.suspended,'Rapid native ADS re-entry after reclaim must not lose the queued input window')
 -- Our own mount must remain ignored after any number of transitions. A
 -- one-frame native near sample still must not seize ADS from the mount.
 for i=1,100 do
  local now=.14+i*.003
  f.position={1.13,0,0};b.observe(f,head,now);assert(not b.suspended)
  f.position={.14,0,.07};b.observe(f,head,now+.0001);assert(not b.suspended)
  f.position={.17,0,0};b.observe(f,head,now+.0002);assert(not b.suspended)
  b.observe(f,head,now+.0003)
  -- The original 128-sample budget may expire during the stress sequence.
  if not b.pending()then break end
  assert(b.suspended)
 end
 b.observe(f,head,.601);assert(not b.pending(),'Handoffs cannot extend the input window')
 f.position={1.13,0,0};b.observe(f,head,.602);assert(not b.suspended)
 f.position={.17,0,0};b.observe(f,head,.603);b.observe(f,head,.604)
 assert(not b.suspended,'Expired input window remains idle on native near samples')
end
