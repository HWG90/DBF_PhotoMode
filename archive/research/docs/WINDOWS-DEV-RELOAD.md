# Private BML Lua reload

The archive adapter can remain resident while replacing War Journalist's Lua
runtime. Install an adapter build containing `windows_dev_reload.lua` once, arm
it with `py -3.14 tools/request_windows_reload.py --enable`, then restart the game.
Startup must log `Dev reload enabled` before requesting a reload.

After editing Lua, run `py -3.14 tools/request_windows_reload.py`. The command
compiles all sources locally, writes one immutable length-framed payload, then
atomically publishes its unique request token. Confirm `Dev reload: loaded` in
`war_journalist_lua51.log`, then reopen Photo Mode. No virtual key injection is
required. The reload closes Photo Mode and releases Freeze, input, camera and
effects through the existing disposal coordinator; it does not restart a mission.

This is disabled unless the startup marker contains exactly `wjl-dev-reload-v1`
followed by a newline. No filesystem notification API is exposed by this adapter,
so enabled sessions check a tiny request file at most once per second. An unchanged
token does not read or compile the payload. Compilation is limited to four modules
and a cooperative two-millisecond budget per frame. Individual file reads, Lua
compiler calls and runtime construction cannot be preempted; the log records the
maximum reload step time for live performance validation.

New source is compiled before the old runtime is touched. Syntax errors and
resident-module mismatches leave it running. Cleanup must explicitly return true;
if restoration cannot finish within ten seconds, replacement stops. An entry or
startup failure after retirement leaves Photo Mode stopped and requires a restart.
It never starts a second owner while old ownership is unconfirmed. Host bindings
register once per ID and the existing WJL connection remains resident.

Portable.22.13 keeps request handling active after an ordinary runtime update
error. The failed generation stays stopped until an explicit replacement passes
compilation, cleanup and enable. Its archive verification induces an update error
and replaces the complete graph twice in the same VM. Earlier adapters, including
portable.22.12, stop request handling along with Photo Mode and need one restart.

This reload covers Lua only. The adapter itself, input transport/helper modules,
compiled shaders, fonts and game asset archives still need normal deployment and
restart. Their resident source modules are pinned against live replacement.
Private one-shot test markers still need arming for the next runtime activation.
Local payloads are trusted development code, not a sandbox or a public mod format.

Remove `wj-dev-reload.enabled` before the next launch to disable the development
path. Requests and payloads stay in the game settings folder for diagnosis; remove
old payload files manually when no longer needed. Never commit them.
