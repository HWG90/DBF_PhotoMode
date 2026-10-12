-- HD2-Addon: mods/actioncam/actioncam
-- ActionCam v10.31 - over-the-shoulder camera for Helldivers 2 (reads your Helldiver's animation state).
--   Camera bases: ActionCam (over the shoulder), Helldivers 2 (the game's own
--   camera + your adjustments), First Person (at your head, head hidden) or Ship
--   (the game's close destroyer camera, the same in every state).
--   States (stance, sprint, dive, vehicles, emplacements, death, ship map,
--   hellpod) come from your Helldiver's animation - see ANIMATION REFERENCE.
--   Handed to the game: emplacements, vehicles (except First Person or a
--   customised Vehicles section), the ship's map and hellpod, terminals,
--   cinematics. A camera-based fallback runs if animations aren't recognised.
--   Optional: Mod Options Menu (profiles, sections), Mod Bindings Menu (Photo Mode).

local sr = rawget(_G, 'stingray')

---------------------------------------------------------------- tweakables
local CFG = {}
CFG.VERSION = '10.31'
local H = {}   -- helper functions used by apply() (kept in one table: Lua allows max 60 outside variables per function)
-- Camera Smoothness (Mod Options Menu, all profiles): scales every transition time
-- below (aim in/out, FOV, sprint, stance changes, dives, blending in). 1 = as designed.
local SMOOTH = {m = 1}
local function sm(seconds) return seconds * SMOOTH.m end
CFG.TARGET_DISTANCE       = 1.75  -- hip: metres from camera to your Helldiver, along the view
CFG.ADS_DISTANCE          = 1.00  -- aiming: same measure (game: ~1.15 standing, ~0.85 crouched). 1.00 = the aim
                                  -- everyone has actually been seeing (a misplaced 1 m safety limit held it there)
CFG.SHOULDER_EXTRA        = -0.16 -- extra metres sideways, always (negative = further over the shoulder, positive = towards centre)
CFG.AIM_STRAFE_LEAD       = 0.07  -- aiming: metres further over the shoulder per m/s you move towards that side
CFG.AIM_STRAFE_MAX        = 0.30  -- ...up to this much
CFG.AIM_STRAFE_MAX_SPEED  = 6.0   -- m/s; faster movement (explosions, ragdoll, packs) counts as this for the strafe lead
CFG.SHOULDER_SWAP_TIME    = 1.0   -- seconds your head must clearly sit on the other side before a shoulder swap is accepted
CFG.AIM_ALIGN             = true  -- turn the camera slightly so the game's reticle sits on your real aim point
CFG.AIM_FALLBACK_DISTANCE = 30    -- metres; assumed aim distance if the game's physics can't be queried
CFG.FP_FORWARD            = 0.18  -- First Person: metres in front of your head (clears the helmet)
CFG.FP_UP                 = 0.04  -- First Person: metres above your head's centre (eye level)
CFG.FP_NEAR_CLIP_HIP      = 0.06  -- First Person, helmet hidden: nothing closer than this is drawn (covers your face)
CFG.FP_NEAR_CLIP_AIM      = 0.02  -- ...and while aiming, so held weapons (pistols) are never cut
                                  -- (same value for both = a fixed clip; both 0 = no clip)
CFG.FP_HELMET_HIDE        = true  -- First Person: hide your own head and helmet (head shrink) on your screen
CFG.PHOTO_SPEED           = 3.0   -- Photo Mode: metres per second
CFG.PHOTO_FAST            = 4.0   -- ...times this while the Faster key is held
CFG.PHOTO_MAX_RANGE       = 60    -- metres the camera may fly from your Helldiver (the world may not be loaded further out)
CFG.FP_HEAD_SHRINK        = true  -- First Person: shrink your own Helldiver's head node (head + helmet) on your screen
CFG.FP_HEAD_SCALE         = 0.01  -- how small (not exactly 0, which can break the maths)
CFG.FP_KEEP_MIN_DIST      = 0.15  -- nodes hanging off the head further away than this (the cape's attachment)
                                  -- keep their normal size and place
CFG.FP_NEAR_CLIP          = 0.22  -- First Person fallback while no helmet is hidden: hides your own head and
                                  -- helmet from every angle (0 = off; very close walls can be clipped too)
CFG.TG_SIDE               = 0.45  -- Tank Gunner Camera: default metres to the right of your head
CFG.TG_UP                 = 0.25  -- ...and above it
CFG.FP_BOB_LIMIT          = 0.06  -- First Person: head-bob smoothing may differ from your real head by at most this much
CFG.BARREL_AIM            = true  -- find the aim distance where the gun barrel's line meets the camera's line
CFG.BARREL_MAX_MISS       = 0.25  -- metres; the two lines must pass this close to trust the result
CFG.BARREL_CONFIRM        = 10    -- consecutive good frames before the barrel estimate is trusted
CFG.BARREL_HAND_RADIUS    = 1.1   -- metres from your head for your own (hand-held) gun
CFG.BARREL_SEARCH_RADIUS  = 3.0   -- metres from your head to look for a muzzle (3 m reaches weapon emplacements)
CFG.BARREL_AXIS_MAX_DEG   = 10    -- a gun's barrel must point within this of your view to be picked (only while aiming)
CFG.AIM_TURN_CAP_DEG      = 15    -- the camera never turns more than this towards the aim point (safety net)
CFG.BARREL_SPIN_LIMIT     = 90    -- deg/s; turning faster than this, the gun lags the view: pause barrel readings
CFG.BARREL_SPIN_SETTLE    = 0.20  -- seconds to keep paused after a fast turn, while the gun catches up
CFG.BARREL_STEADY         = 40    -- deg/s; barrel readings only count once the gun itself has stopped swinging
                                  -- (adapts to weapon ergonomics: heavy guns are simply waited for longer)
CFG.BARREL_FLOAT          = 0.30  -- metres: a "gun" whose muzzle drifts this much relative to your head (a drone such as
CFG.BARREL_FLOAT_TIME     = 0.30  -- the Guard Dog) for this long is not yours: dropped; the 2nd time, never picked again
                                  -- in this world (v10.31: was 0.20 m / 0.15 s / first time - own guns hit 0.26-0.29 m)
CFG.BARREL_FLOAT_SETTLE   = 0.50  -- seconds after you start aiming before drift counts (the gun swings up into place)
CFG.BARREL_MEMORY         = 1.5   -- seconds; after losing the barrel, ease from its last distance to the fallback
CFG.PRECISE_AIM           = true  -- apply the Precise Aiming slider while aiming (false = ignore it)
CFG.AIM_DISTANCE_SMOOTHING = 0.35 -- seconds; smooths jumps in aim distance (e.g. sweeping past a close edge). v10.25:
                                  -- 0.12 -> 0.35, and in proportion (30 -> 4 m eases like 8 -> 1 m): v10.24 log jumped 30/8/4 m
CFG.AIM_STRAFE_SMOOTHING  = 0.15  -- seconds; how smoothly the strafe lead follows your movement
CFG.HEIGHT_SHIFT          = -0.10 -- metres up/down, all stances, hip AND aim
-- Hip FOV is always the game's own FOV setting (no ActionCam change, no slider).
CFG.ADS_FOV_CHANGE        = -14   -- aiming: degrees added to the game's FOV (80 -> 66), ActionCam and First Person
CFG.SPRINT_FOV_BONUS      = 22    -- sprint: degrees added at full sprint (replaces the game's own +2; 80 base -> 98)
CFG.SPRINT_EXTRA_DISTANCE = 0.05  -- sprint: metres added to the hip distance at full sprint (negative = closer)
CFG.FOV_SMOOTHING         = 0.05  -- seconds; how softly FOV changes (aim, sprint). Lower = snappier
CFG.AIM_SMOOTHING         = 0.03  -- seconds; how closely ActionCam follows the game's own aim-in / aim-out
CFG.SPRINT_SMOOTHING      = 0.10  -- seconds; how quickly the sprint effect comes and goes
CFG.BOB_SMOOTHING         = 0.30  -- seconds; smooths your Helldiver's lean/bob so the camera doesn't follow it
CFG.TRANSITION_EASE       = 0.40  -- seconds; how gently the effect returns after a dive
CFG.OUTPUT_SPRING         = 14    -- how softly the final camera offset follows its target (lower = softer, 10-20 is sensible)
CFG.STANCE_DEBOUNCE       = 0.15  -- seconds a new stance must hold before the framing follows it
CFG.DIVE_BLEND            = 0.90  -- seconds; from the moment you dive, how long the camera takes to glide to your new stance's framing
CFG.DIVE_GRACE            = 1.0   -- seconds after a dive (getting up) the head may sit beside / at the game's camera
CFG.STANCE_BLEND          = 0.35  -- seconds; how smoothly framing moves between stand / crouch / prone
CFG.DIVE_FADE_OUT         = 0.25  -- seconds; how gently the effect steps aside when a dive starts
CFG.ENGAGE_TIME           = 0.40  -- seconds to blend in (spawning, after vehicles and special cameras)
-- Aiming, from your Helldiver's weapon pose (animation layer 4; v10.20 research: it
-- switches on the very frame you aim or stop, and never showed an aiming value without
-- the aim button). The camera reading still sets how far into aiming the game's camera
-- has glided, so ActionCam's zoom-in stays in step with the game.
CFG.AIM_POSES = {[59] = true,   -- standing, every weapon tried
                 [0] = true,    -- crouched
                 [53] = true, [45] = true, [55] = true, [27] = true,   -- prone (differs per weapon)
                 [57] = true, [61] = true, [63] = true, [70] = true, [11] = true, [21] = true,   -- v10.21 logs: seen with
                                                                     -- the game's camera fully in (other weapons/stances)
                 [41] = true}   -- v10.31 log: prone, aimed in with the Ballistic Shield (also while rolling)
CFG.HIP_POSES = {[67] = true,   -- weapon ready at hip
                 [18] = true,   -- relaxed (idle for a while)
                 [8] = true, [60] = true,   -- not aiming (reload / throw?)
                 [76] = true,   -- on the ship
                 [1] = true, [19] = true,   -- v10.21 logs: the game's camera never went past half-way in
                 [49] = true}   -- v10.30/v10.31 logs: prone at the hip with the Ballistic Shield
CFG.AIM_DEADZONE          = 0.35  -- unknown pose / no animations: camera readings below this share of aiming are
                                  -- the game's hip camera pulling in (walls, movement), not aiming
CFG.AIM_TRUST_CAMERA      = true  -- v10.31: when the weapon pose and the game's camera disagree, the camera decides
                                  -- (the Ballistic Shield and some guns use "hip" poses while aimed in, and vice versa)
CFG.AIM_CONFLICT_IN       = 0.85  -- share of aiming: a hip pose with the game's camera at least this far in...
CFG.AIM_CONFLICT_FIT      = 0.15  -- metres: ...sitting within this of the stance's aim distance (not past it: walls)...
CFG.AIM_CONFLICT_STEADY   = 0.60  -- m/s: ...and holding still (a wall pull-in slides about)...
CFG.AIM_CONFLICT_TIME     = 0.15  -- seconds: ...for this long counts as aiming. Already aiming: kept at once.
CFG.AIM_POSE_STALE        = 0.50  -- seconds: an aiming pose with the game's camera still out after this long is not
                                  -- aiming (the Evictor's standing pose 59 at the hip camera): camera with a dead zone
CFG.AIM_RELEASE_MAX       = 0.45  -- seconds; letting go of aim: ActionCam eases out with the game's camera (as it
                                  -- glides back), finishing within this time at the latest (v10.21 snapped at once)
CFG.EXTRACT_RESEARCH      = true  -- (research) log the Pelican extraction: your seat and the game's camera, from
                                  -- boarding until the mission world unloads (v10.22 also scanned the world's other
                                  -- units and crashed the game at boarding: v10.23 reads only your own Helldiver)
-- The game pulls its camera in (and down) to keep it out of the ground and objects
-- behind you. ActionCam must then not push past it or lower it (v10.22: crouched
-- aiming at a radar dish pushed the camera into the ground). Squeeze = how much
-- closer than normal the game's camera is, beyond SQUEEZE_SLACK (the game's normal
-- distances in v10.22 logs sit ~0.15 m closer than the stance table); pushing back
-- and lowering fade out over SQUEEZE_RANGE of squeeze.
-- Camera Base: Ship (v10.24) - the game's own camera on the destroyer, used everywhere.
-- Measured from your v10.22 log (2 min on the ship): your head 1.12 m ahead of the
-- camera, 0.66 m to the side (over the shoulder) and 0.11 m above it. Held in every
-- state: no aim zoom, sprint widening or stance framing - sections adjust it instead.
CFG.SHIP_DIST             = 1.12
CFG.SHIP_SIDE             = 0.66
CFG.SHIP_UP               = 0.11
CFG.SHIP_FOLLOW           = 1.5   -- seconds: how slowly the Ship camera follows your head's lean away from your body...
CFG.SHIP_FOLLOW_QUICK     = 0.15  -- ...and how quickly while your stance changes or you dive...
CFG.SHIP_QUICK_HOLD       = 0.8   -- ...and for this long after (your head is still settling)
CFG.SQUEEZE_SLACK         = 0.20
CFG.SQUEEZE_RANGE         = 0.20
CFG.SQUEEZE_NEAR          = 0.50  -- metres: ActionCam's camera this far in front of the game's is clear of what it avoided
CFG.SHIP_CAMERA_COUNT     = 10    -- a world with this many cameras is the ship; never touched
CFG.SHIP_ACTIONCAM        = true  -- ActionCam on the ship too (gameplay camera only; map and hellpod left to the game)
CFG.GAMEPLAY_CAMERA_MODEL = '465f4895f3dc98d1'  -- the player's gameplay camera unit (the only camera used on the ship)
CFG.VEHICLE_DISTANCE      = 4.25  -- game camera farther back than this = vehicle; mod steps aside
CFG.VEHICLE_FOV_MARGIN    = 3.0   -- game FOV this far above yours (vehicles widen with speed) = vehicle
CFG.VEHICLE_SEATED_DISTANCE = 3.0  -- camera this far back AND your Helldiver sitting = getting into a vehicle
CFG.VEHICLE_SEATED_HEAD   = 1.30  -- sitting = head between SEATED_MIN and this above the root...
CFG.VEHICLE_SEATED_MIN    = 0.62  -- ...(prone is ~0.47, so a dive ending prone doesn't count)
CFG.VEHICLE_SEATED_TIME   = 0.10  -- ...and held still this long (a dive passes through quickly)
CFG.VEHICLE_RELEASE_TIME  = 0.75  -- seconds of normal camera before the mod comes back after a vehicle
-- Which Helldiver is YOU (every Helldiver uses the same model). The game camera
-- follows only you: your head stays put on its screen while it moves and turns.
CFG.ID_SAMPLE             = 0.10  -- seconds between identity samples
CFG.ID_CUT                = 4.0   -- metres the camera may jump between samples before it counts as a cut
-- First choice: the engine's network ownership (the one Helldiver your peer owns).
-- Fallback when that gives no clear answer: the camera test. Evidence = "swing":
-- how far the view turned (x distance) plus how far the camera moved sideways/up;
-- your head stays roughly put on screen through it, others drift. HD2's camera
-- smooths and pivots over the shoulder, so even your head moves 30-80% of the
-- swing (v10.10 logs) - the test only acts on clear cases.
-- Input: while you hold a movement key (or push the left stick), YOUR Helldiver
-- moves that way relative to the camera; nobody else's follows your keys.
CFG.INPUT_ID              = true  -- use your movement input to identify you
CFG.INPUT_KEYS            = {forward = 'w', back = 's', left = 'a', right = 'd'}   -- keyboard movement keys
CFG.ID_INPUT_HOLD         = 0.25  -- seconds a direction must be held before it counts (your Helldiver speeds up)
CFG.ID_INPUT_SPEED        = 0.8   -- m/s: moving at least this fast...
CFG.ID_INPUT_ANGLE        = 45    -- ...within this many degrees of the direction you're pressing = a match
CFG.ID_INPUT_TIME         = 0.8   -- seconds of held input before a Helldiver can be confirmed by it...
CFG.ID_INPUT_MATCH        = 0.75  -- ...if it matched at least this share of the time...
CFG.ID_INPUT_OTHERS       = 0.4   -- ...and every other Helldiver seen as long matched at most this share
CFG.ID_INPUT_MEMORY       = 3.0   -- confirmed: seconds over which older input evidence fades out
CFG.ID_INPUT_LOST_TIME    = 1.5   -- ...once this much (faded) held-input time is in memory...
CFG.ID_INPUT_LOST         = 0.25  -- ...matching less than this share = check again (still framed meanwhile)
-- Spectating: after your death the game follows a teammate until you're reinforced.
CFG.SPECTATE_SCORE        = 1.5   -- a spectated head must sit about where a followed head does (framing score)
CFG.SPECTATE_SCAN         = 0.25  -- seconds between checks for your own climb-out while spectating
CFG.SPECTATE_WIDE         = 20    -- degrees: a game camera this much wider than your FOV isn't following anyone
                                  -- (v10.15: 122 deg while everyone was down) - left to the game
CFG.ID_STEP_ASIDE         = true  -- camera test: leave the camera to the game while the pick clearly fails
CFG.ID_MIN_SWING          = 0.03  -- metres of swing in one sample for it to count as evidence
CFG.ID_RIG_STEP           = 0.15  -- metres a head may move along the view in one sample; more = the camera rig
                                  -- itself changed (aiming in/out, stance), so that sample isn't evidence
CFG.ID_PASS_SWING         = 1.0   -- metres of swing seen before a Helldiver can be confirmed
CFG.ID_PASS               = 0.35  -- confirmed if it moved on screen at most this share of the swing...
CFG.ID_MARGIN             = 2.5   -- ...and every other Helldiver seen as long moved at least this many times more
CFG.ID_ACCEPT_TIME        = 8.0   -- seconds of checking after which the pick is accepted if it followed reasonably...
CFG.ID_ACCEPT             = 0.7   -- ...(moved at most this share of the swing, and nobody else less)
CFG.ID_ASIDE_SWING        = 3.0   -- metres of swing before a pick or a confirmed Helldiver can fail...
CFG.ID_ASIDE              = 1.0   -- ...by moving on screen at least as much as the whole swing (clear failure)
CFG.ID_LOG_EVERY          = 2.0   -- seconds between candidate lists in the log while checking
CFG.RESPAWN_SETTLE        = 3.0   -- seconds after you go down in which new Helldiver units are bodies: never read
CFG.RESPAWN_GATE_MAX      = 240   -- seconds after your death the respawn check gives up and accepts any Helldiver
-- Base FOV (your FOV setting) is kept all session. A lower one is only accepted
-- when it holds steady while you're plainly on foot and framed like the gameplay camera.
CFG.FOV_ESCAPE_TIME       = 5.0   -- seconds steady
CFG.FOV_ESCAPE_ALONG      = 3.2   -- metres: the gameplay camera is never further back than this on foot
CFG.SPRINT_UNDO_MAX       = 5.0   -- degrees: most of the game's own sprint widening ActionCam removes (it is ~2)

---------------------------------------------------------------- measured game values
-- Per stance, measured from your logs. head = head height above your Helldiver's
-- root; hip/aim = game camera distance to your head; side/lift = how far the
-- game's aim camera moves towards screen centre / up compared with hip. The mod
-- applies that at hip too, so hip and aim line up and aiming only zooms.
-- side/lift are measured values from your logs (live self-calibration was
-- retired: hectic moments fed it bad samples).
local STANCES = {
  {name = 'prone',  head = 0.47, hip = 2.55, aim = 1.04, side = 0.05, lift = -0.06, hip_lat = 0.53, hip_vert = -0.21},
  {name = 'crouch', head = 1.05, hip = 1.76, aim = 0.85, side = 0.20, lift = -0.14, hip_lat = 0.46, hip_vert = -0.23},
  {name = 'stand',  head = 1.52, hip = 2.80, aim = 1.16, side = 0.24, lift = -0.02, hip_lat = 0.58, hip_vert = -0.24},
}

local function effective(i)
  local s = STANCES[i]
  return {head = s.head, hip = s.hip, aim = s.aim, side = s.side, lift = s.lift, name = s.name, hip_lat = s.hip_lat, hip_vert = s.hip_vert}
end

local function nearest_stance(h)
  if not h or h ~= h then return 3 end
  local best, bd = 3, math.huge
  for i, s in ipairs(STANCES) do
    local d = math.abs(h - s.head)
    if d < bd then best, bd = i, d end
  end
  return best
end
H.nearest_stance = nearest_stance


-- Blend the stances smoothly by head height.
local function stance_at(h)
  if not h or h ~= h or h < 0.1 or h > 2.5 then return effective(3), 'stand?' end
  if h <= STANCES[1].head then return effective(1), 'prone' end
  if h >= STANCES[3].head then return effective(3), 'stand' end
  local ia, ib = 1, 2
  if h > STANCES[2].head then ia, ib = 2, 3 end
  local a, b = effective(ia), effective(ib)
  local t = (h - a.head) / (b.head - a.head)
  -- Stay fully on a stance near its own height; only blend in between.
  t = math.min(1, math.max(0, (t - 0.2) / 0.6))
  local r = {}
  for _, k in ipairs({'hip', 'aim', 'side', 'lift', 'hip_lat', 'hip_vert'}) do r[k] = a[k] + (b[k] - a[k]) * t end
  return r, (t < 0.5 and a.name or b.name)
end

---------------------------------------------------------------- safety gates
CFG.MAX_DISTANCE  = 6.0    -- fallback mode: a camera further than this from your head is a special camera
CFG.MAX_ANGLE_DEG = 35     -- fallback mode: your head must be this close to screen centre
-- With animations recognised, special cameras are identified directly, so these
-- safety checks only need to catch the extreme cases (e.g. a big jump pack drop
-- can leave the game camera well behind or above you for a moment).
CFG.MAX_DISTANCE_ANIM  = 12.0
CFG.MAX_ANGLE_DEG_ANIM = 60
CFG.CLOSE_DISTANCE = 1.6   -- closer than this (aiming): skip the screen-centre angle check
CFG.MIN_FOV_DEG   = 25     -- cameras narrower than this are always special (ship stations, zoom cinematics)
CFG.SPECIAL_FOV_GAP = 25   -- once your normal FOV is known: a camera this much narrower is special
                           -- (v9.2 and earlier used a fixed 60 deg, which switched ActionCam off for
                           --  anyone with the game's FOV slider set below 60)
CFG.FOV_REFERENCE = 80     -- ActionCam's own FOV changes are tuned for this and scale with your FOV
CFG.FOV_OUT_MIN   = 15     -- the final FOV is always kept within this range
CFG.FOV_OUT_MAX   = 140
CFG.CUT_DISTANCE  = 5.0
CFG.ANCHOR_NODE   = 'head'
CFG.HELLDIVER_MODEL = '4d1c334d294dfa97'  -- your Helldiver's unit (same in every log so far); nothing else is ever tracked

CFG.LOG_NAME   = 'ActionCam.log'
CFG.LOG_PREVIOUS = 'ActionCam_previous.log'   -- the previous game launch's log
CFG.SCAN_EVERY = 2.0
CFG.SEARCH_EVERY = 0.25   -- right after losing the camera (respawn, hellpod), search this often...
CFG.SEARCH_FAST_FOR = 15  -- ...for this many seconds, then slow down to:
CFG.SEARCH_SLOW = 1.0
CFG.SHIP_RECHECK = 10     -- once a world is recognised as the ship, don't re-count its cameras for this long
CFG.ACQUIRE_DISTANCE = 12.0 -- accept your Helldiver this far away when first finding the camera
CFG.LOG_EVERY  = 1.0
CFG.FLICKER_WARN = 6      -- view reversals in one second (FOV or position) that count as flicker: logged as a WARNING

---------------------------------------------------------------- logging (one file per game launch)
local log_file, log_failed
local LOGT = {t = 0}   -- seconds since start, for timestamps
local function log(line)
  if log_failed then return end
  if not log_file then
    local dir
    pcall(function() dir = os.getenv('LOCALAPPDATA') end)
    -- A fresh log each game launch (v10.23 and earlier appended forever: 40 MB logs);
    -- the previous launch's log is kept beside it as ActionCam_previous.log.
    local base = (dir or '') .. '\\CowboyBingus\\Helldivers2\\Logs\\'
    pcall(function() os.remove(base .. CFG.LOG_PREVIOUS) end)
    pcall(function() os.rename(base .. CFG.LOG_NAME, base .. CFG.LOG_PREVIOUS) end)
    local ok, f = pcall(io.open, base .. CFG.LOG_NAME, 'w')
    log_file = ok and f or nil
    if not log_file then log_failed = true; return end
    local stamp = ''
    pcall(function() stamp = os.date('%Y-%m-%d %H:%M:%S') end)
    pcall(function() log_file:write('\n==== session ', stamp, ' ====\n') end)
  end
  pcall(function() log_file:write(string.format('[%7.1f] ', LOGT.t), line, '\n'); log_file:flush() end)
end

local function try(fn, ...)
  if type(fn) ~= 'function' then return nil end
  local ok, r = pcall(fn, ...)
  if ok then return r end
end

local V, M = sr.Vector3, sr.Matrix4x4
local function xyz(v) return V.x(v), V.y(v), V.z(v) end
local function fmt(x, y, z) return string.format('%.3f,%.3f,%.3f', x, y, z) end
local function far(ax, ay, az, bx, by, bz, eps)
  return math.abs(ax - bx) > eps or math.abs(ay - by) > eps or math.abs(az - bz) > eps
end
local function clamp01(x) if x < 0 then return 0 elseif x > 1 then return 1 end return x end
CFG.COS_MAX = math.cos(math.rad(CFG.MAX_ANGLE_DEG))
CFG.COS_MAX_ANIM = math.cos(math.rad(CFG.MAX_ANGLE_DEG_ANIM))

---------------------------------------------------------------- state
local target, anchor, anchor_model
local frame, applied_frame, last_dt = 0, -1, 0
local last_written, last_base
local written_fov, game_fov_base      -- our last FOV write (radians) and the game's value under it
local base_fov                        -- your normal FOV setting, learned (degrees)
local engage = 0
local ST = {}   -- small per-frame state (kept in one table: Lua allows max 60 outside variables per function)
ST.steady_val = nil
ST.steady_time = 0
ST.no_anchor_time = 0
local smooth_off                       -- smoothed head offset from the body root
local ship_logged = {}
ST.vehicle_latched = false
ST.vehicle_clear_time = 0
local clock, airborne_t, fast_t, prev_root = 0, -99, -99, nil   -- jump/warp pack detection
local shoulder_sgn = -1                  -- -1 = right shoulder (default), +1 = left
ST.paused_logged = false
ST.prev_raw_h = nil
ST.seated_time = 0
ST.settle = 1
ST.far_time = 0
local scan_timer, log_timer = CFG.SCAN_EVERY, 0
local counts, last
local function reset_counts()
  counts = {render = 0, applied = 0, fov_skip = 0, too_far = 0, off_centre = 0, vehicle = 0, unconfirmed = 0,
            no_anchor = 0, blocked = 0, cut = 0, fov_persist = 0, special = 0,
            updates = 0, rerender = 0, still = 0, fov_held = 0, fov_flips = 0, pos_flips = 0}   -- (v10.30, see FLICK)
end
reset_counts()
last = {}

local function world_alive(w)
  local list = try(sr.Application.worlds)
  if type(list) ~= 'table' then return false end
  for _, x in pairs(list) do if x == w then return true end end
  return false
end

-- If our FOV is still on the camera but we're not applying this frame, put the
-- game's value back so a special camera never inherits our FOV.
local function restore_fov()
  if target and written_fov and game_fov_base then
    local cur = try(sr.Camera.vertical_fov, target.cam)
    if cur and math.abs(cur - written_fov) < 1e-5 then
      pcall(sr.Camera.set_vertical_fov, target.cam, game_fov_base)
    end
  end
  written_fov, game_fov_base = nil, nil
end

-- Death / respawn safety. When your Helldiver dies the mod lets go of it
-- completely, never re-attaches to the body, pauses searching while the game
-- sets up the respawn, and is careful with a freshly spawned Helldiver.
-- Which world we're in. The engine hands the mission and the ship the SAME world
-- object (v10.13 logs), so worlds can't be told apart by comparing them; instead a
-- new world is counted when your tracked Helldiver is removed (a world unloading)
-- or the ship/mission state flips.
local WORLD = {epoch = 0, ship = nil}
local function new_world(why)
  WORLD.epoch = WORLD.epoch + 1
  log('world: new world (' .. why .. ')')
end
local SAFE = {dead_unit = nil, dead_pos = nil, dead_time = nil, anchored_at = 0, crumbs = nil, gate = nil,
              bodies = {}, bodies_epoch = nil}   -- every body of yours in this world (v10.17 kept only the last)
-- Identity: which Helldiver is you. locked = the unit confirmed (or assumed) to
-- be you; while verifying, every Helldiver in view is compared (see H.id_sample).
local ID = {locked = nil, verifying = false, c = {}, at = 0, prev = nil, started = 0, log_at = 0, L = nil,
            aside = false, checked = 0, method = nil}
-- Spectating (you're dead; the game follows a teammate): framed with ActionCam
-- on request, never confirmed as you. ov = your own camera values while a
-- Spectator Profile is borrowed.
local SPEC = {active = false, unit = nil, ov = nil, ov_p = nil, dead = {}, scan_at = 0}
-- Bodies are NEVER touched: touching your own dead body crashes the game (v10.17
-- crashed on the very scan after its memory was wrongly cleared). Checked before
-- any engine call on a unit, by comparing references only.
local function remember_body(u)
  if SAFE.bodies_epoch ~= WORLD.epoch then SAFE.bodies, SAFE.bodies_epoch = {}, WORLD.epoch end
  SAFE.bodies[#SAFE.bodies + 1] = u
end
local function known_body(u)
  for _, b in ipairs(SAFE.bodies) do if rawequal(u, b) or u == b then return true end end
  for _, b in ipairs(SPEC.dead) do if rawequal(u, b) or u == b then return true end end
  return false
end
-- The tracked Helldiver's unit no longer exists. Only YOUR Helldiver vanishing
-- means a world unloaded; a spectated teammate can simply leave the game.
function H.anchor_gone()
  if SPEC.active then
    log('released: the spectated Helldiver is gone')
    anchor = nil
    return
  end
  log('released: anchor gone')
  anchor = nil
  new_world('your Helldiver was removed')
  WORLD.left, WORLD.ship = WORLD.ship, nil   -- (left that world: the next one is accepted, the other kind preferred)
end
-- Unit references are only ever compared, never used, once they may be stale.
local function same(a, b) return a ~= nil and b ~= nil and (rawequal(a, b) or a == b) end
-- Is this the body of the Helldiver that just died? Compared by the unit itself
-- and by where it fell (v7.4 compared units by their printed name, but in the
-- game every unit prints the same, so it skipped your respawned Helldiver too).
local function is_dead_body(u, hx, hy, hz)
  if not SAFE.dead_time then return false end
  if rawequal(u, SAFE.dead_unit) or u == SAFE.dead_unit then return true end
  if SAFE.dead_pos and clock - SAFE.dead_time < 90 then
    local rp = try(sr.Unit.world_position, u, 1)
    if rp then
      local dx, dy = hx - SAFE.dead_pos[1], hy - SAFE.dead_pos[2]
      local lying = (hz - V.z(rp)) < 1.0
      if lying and dx * dx + dy * dy < 2.5 * 2.5 then return true end
    end
  end
  return false
end
local function crumb(msg)
  -- After a respawn, log the first few times each risky step runs: if the game
  -- ever crashes here again, the last line in the log names the step.
  if SAFE.crumbs then
    local n = SAFE.crumbs[msg] or 0
    if n < 3 then SAFE.crumbs[msg] = n + 1; log('step: ' .. msg); return end
  end
  -- While you're dead (spectating, squad wipes - where v10.15/v10.16 crashed):
  -- keep naming every step, at most once a second each.
  if SAFE.gate then
    SAFE.crumb_t = SAFE.crumb_t or {}
    if (SAFE.crumb_t[msg] or -99) + 1.0 <= clock then SAFE.crumb_t[msg] = clock; log('step: ' .. msg) end
  end
end
local function on_anchored()
  SAFE.anchored_at = clock
  SAFE.crumbs = {}   -- log the first few risky steps after every new pick
end
-- Reading a Helldiver's animation is only done once it has been tracked for a
-- moment after a respawn, and while its head sits at a believable height.
local function anim_allowed(oz)
  SAFE.fresh = SAFE.dead_time and clock - SAFE.anchored_at < 1.5
  if SAFE.fresh then return false end
  return oz > -1.5 and oz < 2.3
end

local near_restore_ref
local PHOTO_REF
local function drop_all(reason)
  if H.spec_end then H.spec_end(reason) end
  if near_restore_ref then pcall(near_restore_ref) end
  if PHOTO_REF and PHOTO_REF.active then PHOTO_REF.active, PHOTO_REF.pos, PHOTO_REF.locked, PHOTO_REF.lock_pose = false, nil, false, nil; log('photo mode: off (' .. reason .. ')') end
  if target or anchor then log('released: ' .. reason) end
  target, anchor, last_written, last_base = nil, nil, nil, nil
  written_fov, game_fov_base, engage = nil, nil, 0
  -- base_fov (your FOV setting) is kept: it doesn't change when you die or load
  -- the ship, and relearning it there picked up a 45 deg ship scene (v10.9).
  ST.steady_val, ST.steady_time, ST.no_anchor_time = nil, 0, 0
  ID.locked, ID.verifying, ID.c, ID.prev, ID.L, ID.aside, ID.method = nil, false, {}, nil, nil, false, nil
  smooth_off, ST.vehicle_latched, ST.vehicle_clear_time = nil, false, 0
  ST.prev_game_deg, ST.sprint_s, ST.fov_offset_s = nil, nil, nil
  prev_root, ST.prev_head_h, ST.aim_hold, ST.aim_s = nil, nil, nil, nil
  ST.prev_raw_h, ST.seated_time = nil, 0
end

---------------------------------------------------------------- camera + anchor discovery
local function target_still_valid()
  local pose = try(sr.World.debug_camera_pose, target.world)
  local wp = try(sr.Camera.world_position, target.cam)
  if not (pose and wp) then return false end
  local rx, ry, rz = xyz(M.translation(pose))
  local wx, wy, wz = xyz(wp)
  if not far(wx, wy, wz, rx, ry, rz, 0.05) then return true end
  if last_written and not far(last_written[1], last_written[2], last_written[3], rx, ry, rz, 0.05) then return true end
  return false
end

local function model_of(u)
  return tostring(try(sr.Unit.resource_name, u) or try(sr.Unit.debug_name, u) or '?')
end

-- Every Helldiver in front of this camera (one fresh scan, same frame), with
-- where its head sits on the camera: along (forward), lat (right), vert (up).
local function scan_helldivers(world, cx, cy, cz, fx, fy, fz, rx, ry, rz, ux, uy, uz)
  crumb('scan Helldivers')
  -- The remembered body only matters in the world you died in: in a new world
  -- (the ship after a mission) its reference is stale and could match a new unit.
  if SAFE.bodies_epoch and SAFE.bodies_epoch ~= WORLD.epoch then SAFE.bodies, SAFE.bodies_epoch = {}, nil end
  if SAFE.dead_unit and SAFE.dead_epoch ~= WORLD.epoch then
    SAFE.dead_unit, SAFE.dead_pos = nil, nil
    log('safety: new world - forgetting the remembered body')
  end
  local list = {}
  for _, u in pairs(try(sr.World.units, world) or {}) do
    local is_body = known_body(u) or (SAFE.dead_unit and (rawequal(u, SAFE.dead_unit) or u == SAFE.dead_unit))
    if not is_body and model_of(u):find(CFG.HELLDIVER_MODEL, 1, true)
        and try(sr.Unit.has_node, u, CFG.ANCHOR_NODE) then
      local node = try(sr.Unit.node, u, CFG.ANCHOR_NODE)
      local p = node and try(sr.Unit.world_position, u, node)
      if p and not is_dead_body(u, V.x(p), V.y(p), V.z(p)) then
        local dx, dy, dz = V.x(p) - cx, V.y(p) - cy, V.z(p) - cz
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        local along = dx * fx + dy * fy + dz * fz
        if d > 0.05 and d < CFG.ACQUIRE_DISTANCE and along / d > CFG.COS_MAX then
          local rp = try(sr.Unit.world_position, u, 1)
          list[#list + 1] = {unit = u, node = node, d = d, along = along,
                             lat = dx * rx + dy * ry + dz * rz, vert = dx * ux + dy * uy + dz * uz,
                             bx = rp and V.x(rp), by = rp and V.y(rp)}
        end
      end
    end
  end
  return list
end

-- Respawn check. After your death the game spectates a teammate with a normal-
-- looking camera, so until a Helldiver is seen climbing out of a hellpod (layer 9
-- = 329/330) nobody counts as you and the camera stays the game's.
-- Who was around when you went down (v10.28). The respawn check reads the
-- animation of Helldivers to spot your climb-out - and reading a body has crashed
-- the game (v10.17 yours; v10.27 crashed on exactly this read, in a squad). Every
-- Helldiver that exists when you go down (teammates, bodies), or appears within
-- RESPAWN_SETTLE after (a body that replaces a Helldiver), is never read by it:
-- only later arrivals are - your reinforcement is always one. Spectating only ever
-- picks a Helldiver that was there before you went down (a living teammate).
-- (A list compared with same(): unit references may differ between calls.)
local function gate_note(g, u, late)
  for _, e in ipairs(g.pre) do if same(e.u, u) then return false end end
  g.pre[#g.pre + 1] = {u = u, late = late}
  return true
end
local function gate_snapshot(g, world, late)
  local n = 0
  for _, u in pairs(try(sr.World.units, world) or {}) do
    if not known_body(u) and model_of(u):find(CFG.HELLDIVER_MODEL, 1, true) and gate_note(g, u, late) then n = n + 1 end
  end
  return n
end
function H.gate_begin(world)
  local g = SAFE.gate
  if not g then return end
  g.pre, g.world, g.read = {}, world, {}
  local n = world and gate_snapshot(g, world, false) or 0
  log(string.format('respawn check: %d other Helldiver%s here as you went down - never read by the respawn check', n, n == 1 and '' or 's'))
end
-- During RESPAWN_SETTLE after you went down: anything new is noted too (a body unit).
function H.gate_settle()
  local g = SAFE.gate
  if not (g and g.pre and g.world) or clock - g.t > CFG.RESPAWN_SETTLE then return end
  if clock < (g.settle_at or 0) then return end
  g.settle_at = clock + 0.25
  if not world_alive(g.world) then return end
  local n = gate_snapshot(g, g.world, true)
  if n > 0 then log(string.format('respawn check: %d Helldiver%s appeared just as you went down (%.1f s after) - never read', n, n == 1 and '' or 's', clock - g.t)) end
end
local function gate_entry(g, u)
  if not g.pre then return nil end
  for _, e in ipairs(g.pre) do if same(e.u, u) then return e end end
  return nil
end
function H.gate_existed_before(u)   -- spectating: only a Helldiver that was there before you went down
  local g = SAFE.gate
  if not (g and g.pre) then return true end
  local e = gate_entry(g, u)
  return e ~= nil and not e.late
end

local function respawn_ok(world, h)
  local g = SAFE.gate
  if not g then return true end
  if g.epoch ~= WORLD.epoch or clock - g.t > CFG.RESPAWN_GATE_MAX then
    SAFE.gate = nil
    log('respawn check: ' .. (g.epoch ~= WORLD.epoch and 'new world' or 'timed out') .. ' - any Helldiver may be picked again')
    return true
  end
  for _, u in ipairs(g.spawned) do if same(u, h.unit) then return true end end
  -- Never read a Helldiver that was here when you went down, or appeared just after.
  if gate_entry(g, h.unit) then return false end
  if g.pre and clock - g.t < CFG.RESPAWN_SETTLE then gate_note(g, h.unit, true); return false end
  -- A newcomer: name it once before its first read (so a crash here says what was touched).
  local seen = false
  for _, u in ipairs(g.read or {}) do if same(u, h.unit) then seen = true end end
  if not seen and g.read then
    g.read[#g.read + 1] = h.unit
    log(string.format('respawn check: reading a newcomer %.1f m from the camera (%.1f s after you went down, %+.2f m up on the camera)', h.d, clock - g.t, h.vert or 0))
  end
  crumb('read animation (respawn check)')
  local st = {pcall(sr.Unit.animation_get_state, h.unit)}
  local l9 = st[1] and st[10]
  if l9 == 329 or l9 == 330 then
    g.spawned[#g.spawned + 1] = h.unit
    log(string.format('respawn check: a Helldiver is climbing out of a hellpod (%.1f m from the camera)', h.d))
    return true
  end
  return false
end
H.scan_helldivers, H.respawn_ok = scan_helldivers, respawn_ok


-- How far a head is from where the game camera puts YOUR head (over the shoulder,
-- ~2.2 m ahead, ~0.5 m to the side, slightly below centre). Only picks the first
-- guess; the identity check (H.id_sample) then confirms or corrects it.
local function framing_score(h)
  return math.abs(h.along - 2.2) + 2 * math.abs(math.abs(h.lat) - 0.5) + 2 * math.abs(h.vert + 0.2)
end

-- The Helldiver in front of this camera that sits best where you would.
-- Returns the anchor, its distance and how many Helldivers could be you.
local function anchor_for(world, cam)
  local wp   = try(sr.Camera.world_position, cam)
  local pose = try(sr.Camera.world_pose, cam)
  if not (wp and pose) then return end
  local cx, cy, cz = xyz(wp)
  return H.pick(world, cx, cy, cz, pose)
end
-- (By camera pose, so render time can use the GAME's camera before ActionCam moves it.)
function H.pick(world, cx, cy, cz, pose, only_you)   -- only_you: skip the spectate fallback
  local fx, fy, fz = xyz(M.forward(pose))
  local rx, ry, rz = xyz(M.right(pose))
  local ux, uy, uz = xyz(M.up(pose))
  local best, bs, n = nil, nil, 0
  local list = scan_helldivers(world, cx, cy, cz, fx, fy, fz, rx, ry, rz, ux, uy, uz)
  for _, h in ipairs(list) do
    if respawn_ok(world, h) then
      n = n + 1
      local sc = framing_score(h)
      if not bs or sc < bs then best, bs = h, sc end
    end
  end
  if best then return {unit = best.unit, node = best.node}, best.d, n end
  -- You're dead and nobody here can be you: if spectating with ActionCam is on,
  -- the Helldiver the game's camera is following (head where a followed head sits).
  if not only_you and SAFE.gate and H.spec_wanted and H.spec_wanted() then
    for _, h in ipairs(list) do
      local gone = not H.gate_existed_before(h.unit)   -- (only a teammate who was there before you went down)
      for _, u in ipairs(SPEC.dead) do if same(u, h.unit) then gone = true end end
      local sc = framing_score(h)
      if not gone and sc < CFG.SPECTATE_SCORE and (not bs or sc < bs) then
        -- A body must never be picked (v10.15 crashed after framing one): check now.
        crumb('read animation (spectate pick)')
        local st = {pcall(sr.Unit.animation_get_state, h.unit)}
        local down = not st[1] or #st < 32 or st[15] == 103 or (st[6] == 0 and st[23] == 0)
        if down then SPEC.dead[#SPEC.dead + 1] = h.unit else best, bs = h, sc end
      end
    end
    if best then return {unit = best.unit, node = best.node, spectate = true}, best.d, #list end
  end
  return nil, nil, #list
end

local function find_anchor()
  -- Only a Helldiver confirmed as you is taken back without a fresh look (v10.9
  -- took back whoever it had last, which kept a teammate after a respawn).
  local la = ST.last_anchor
  if la and ID.locked and same(la.unit, ID.locked) and not known_body(la.unit) and try(sr.Unit.alive, la.unit) and not (SAFE.dead_unit and (rawequal(la.unit, SAFE.dead_unit) or la.unit == SAFE.dead_unit)) then
    anchor = la
    return
  end
  local best, d, n = anchor_for(target.world, target.cam)
  if best then
    anchor = best
    ST.last_anchor = best
    on_anchored()
    if not anchor_model then anchor_model = model_of(best.unit) end
    log(string.format('anchor: %s at %.2f m (%d Helldiver%s in view)', anchor_model, d, n, n == 1 and '' or 's'))
    if best.spectate then H.spec_begin(best, d)
    else
      if SPEC.active then H.spec_end('you climbed out of a hellpod') end   -- (keep this pick)
      H.id_begin()
    end
  end
end

-- Look through every world for the rendered camera, but only accept one that has
-- your Helldiver in front of it. Background worlds (cinematics, UI) have a live
-- camera too, and v5 got stuck on one of those for a whole mission.
local SHIP_SEEN = {}   -- world -> time until which it is known to be the ship
local function find_camera()
  crumb('search for the camera')
  local list = try(sr.Application.worlds)
  if type(list) ~= 'table' then return end
  local cands, seen = {}, {}       -- every usable camera, from every world; seen[is_ship] = that kind exists
  for wi, w in pairs(list) do
    -- A world already recognised as the ship is skipped without scanning it again.
    local ship_until = SHIP_SEEN[w]
    local pose = not (ship_until and clock < ship_until) and try(sr.World.debug_camera_pose, w)
    if pose then
      local rx, ry, rz = xyz(M.translation(pose))
      local camera_units = {}
      if not (math.abs(rx) < 0.01 and math.abs(ry) < 0.01) then
        for _, u in pairs(try(sr.World.units, w) or {}) do
          local n = try(sr.Unit.num_cameras, u)
          if type(n) == 'number' and n > 0 then camera_units[#camera_units + 1] = u end
        end
      end
      local is_ship = #camera_units >= CFG.SHIP_CAMERA_COUNT
      if is_ship then
        if not CFG.SHIP_ACTIONCAM then SHIP_SEEN[w] = clock + CFG.SHIP_RECHECK end
        if not ship_logged[wi] then
          ship_logged[wi] = #camera_units
          log(string.format('world[%s] has %d cameras: the ship%s', tostring(wi), #camera_units,
            CFG.SHIP_ACTIONCAM and ' (ActionCam uses the gameplay camera only)' or ', leaving it alone'))
        end
        if CFG.SHIP_ACTIONCAM then
          -- Only the player's gameplay camera: never a terminal or station camera.
          local keep = {}
          for _, u in ipairs(camera_units) do
            if model_of(u):find(CFG.GAMEPLAY_CAMERA_MODEL, 1, true) then keep[#keep + 1] = u end
          end
          camera_units = keep
        else
          camera_units = {}
        end
      end
      do
        for _, u in ipairs(camera_units) do
            local cam = try(sr.Unit.camera, u, 1)
            local wp = cam and try(sr.Camera.world_position, cam)
            local lp = cam and try(sr.Camera.local_position, cam, u)
            if wp and lp then
              local wx, wy, wz = xyz(wp)
              local lx, ly, lz = xyz(lp)
              if not far(wx, wy, wz, rx, ry, rz, 0.01) and not far(lx, ly, lz, wx, wy, wz, 0.01) then
                cands[#cands + 1] = {wi = wi, w = w, u = u, cam = cam, ship = is_ship, x = wx, y = wy, z = wz}
                seen[is_ship] = true
              end
            end
        end
      end
    end
  end
  -- Ship or mission? The ship's world can stay loaded in the background during a
  -- mission, and both worlds pass this camera check for a moment at every load. A
  -- switch is only counted for real (v10.17 flipped 200 times and wiped the body
  -- memory while you were dead; v10.18 still flipped during loads):
  --   * while you're dead: another kind of world is neither used nor switched to
  --     unless the old kind is gone (the body memory must survive);
  --   * while alive: switch only when a Helldiver is actually picked up there.
  -- After your own Helldiver was removed (leaving the ship), the kind is unknown
  -- (WORLD.ship = nil) and the next world is simply accepted.
  local old_gone = WORLD.ship ~= nil and not seen[WORLD.ship]
  -- The current kind of world first: another kind is only considered when nothing
  -- can be picked up in it (the engine's world order is no guarantee). Kind unknown
  -- (you just left a world): the OTHER kind first - leaving the ship means a mission
  -- (the ship can stay loaded behind it), leaving a mission means the ship. At the
  -- very start (nothing left yet): the ship, where every session begins.
  local prefer = WORLD.ship
  if prefer == nil then
    if WORLD.left == nil then prefer = true else prefer = not WORLD.left end
  end
  local first, later = {}, {}
  for _, c in ipairs(cands) do if c.ship == prefer then first[#first + 1] = c else later[#later + 1] = c end end
  for _, c in ipairs(later) do first[#first + 1] = c end
  cands = first
  for _, c in ipairs(cands) do
    local other = WORLD.ship ~= nil and c.ship ~= WORLD.ship
    if not (other and SAFE.gate and not old_gone) then
      local a, d, nh = anchor_for(c.w, c.cam)
      if other and (a or old_gone) then
        new_world(c.ship and 'now on the ship' or 'now in a mission')
        WORLD.ship = c.ship
        a, d, nh = anchor_for(c.w, c.cam)   -- the respawn check and body memory belonged to the old world
      end
      if a then
        if WORLD.ship == nil then WORLD.ship = c.ship end
        target = {world = c.w, unit = c.u, cam = c.cam, ship = c.ship}
        anchor = a
        ST.last_anchor = a
        on_anchored()
        if not anchor_model then anchor_model = model_of(a.unit) end
        log(string.format('camera: world[%s] at %s, Helldiver %s at %.2f m (%d Helldiver%s in view)',
          tostring(c.wi), fmt(c.x, c.y, c.z), anchor_model, d, nh, nh == 1 and '' or 's'))
        if a.spectate then H.spec_begin(a, d)
        else
          if SPEC.active then H.spec_end('you climbed out of a hellpod') end
          H.id_begin()
        end
        return true
      end
    end
  end
end

---------------------------------------------------------------- apply (render time, once per frame)
-- Final-output smoothing: a critically damped spring on the camera offset, so
-- no single trigger (dive, sprint, stance change) can make the camera jump.
-- Aim alignment. The game aims your weapon at whatever is under the centre of
-- ITS camera and draws the reticle at the centre of ITS view. ActionCam's camera
-- sits slightly to the side, so the aim point appears off-centre on screen while
-- the reticle stays centred. Turning ActionCam's camera to look at that aim point
-- puts it back under the reticle.
local AIMFIX = {mode = nil, dist = nil}
-- (The game has no physics ray to ask - PhysicsWorld isn't exposed, v10.12 probe -
-- so the aim distance comes from the gun barrel, or AIM_FALLBACK_DISTANCE.)

-- Barrel aiming. The game points your gun at the aim point, and the aim point
-- also lies on the game camera's centre line. Where the barrel line and the
-- camera line meet is the aim point, so that gives the distance.
local GUN = {unit = nil, node = nil, axis = nil, scan_at = 0, good = 0, bad_time = 0, d = nil, miss = nil, reject = {}}
-- Drop the current gun, saying why in the log (v10.25: every pick and drop is logged).
local function gun_drop(why)
  if GUN.unit then log('barrel aiming: dropped the gun (' .. why .. ')') end
  GUN.unit, GUN.d, GUN.good, GUN.hd_ema, GUN.float_t = nil, nil, 0, nil, 0
end
local MUZZLE_NODES = {'attach_muzzle', 'muzzle', 'fx_muzzle', 'muzzle_flash', 'attach_barrel', 'barrel_end', 'j_muzzle',
  -- extra guesses for weapon emplacements and multi-barrel weapons
  'muzzle_01', 'muzzle_1', 'fx_muzzle_01', 'attach_muzzle_01', 'attach_barrel_end', 'barrel', 'barrel_01', 'gun_muzzle', 'weapon_muzzle'}
local function gun_axes(pose)
  local f, r, u = M.forward(pose), M.right(pose), M.up(pose)
  return {{V.x(f), V.y(f), V.z(f)}, {V.x(r), V.y(r), V.z(r)}, {V.x(u), V.y(u), V.z(u)}}
end

-- Where the camera line (C + F t) and the barrel line (Mz + B s) pass closest.
-- Returns t (distance along the camera line), s (along the barrel) and the miss gap.
local function line_meet(cx, cy, cz, fx, fy, fz, mx, my, mz, bx, by, bz)
  local wx, wy, wz = cx - mx, cy - my, cz - mz
  local b = fx * bx + fy * by + fz * bz
  local d0 = fx * wx + fy * wy + fz * wz
  local e = bx * wx + by * wy + bz * wz
  local denom = 1 - b * b
  if denom < 2e-5 then
    -- Parallel: they never meet; the miss is the gap between them.
    local px, py, pz = wx - d0 * fx, wy - d0 * fy, wz - d0 * fz
    return 250, 250, math.sqrt(px * px + py * py + pz * pz)
  end
  local t = (b * e - d0) / denom
  local s = (e - b * d0) / denom
  local qx, qy, qz = cx + fx * t - (mx + bx * s), cy + fy * t - (my + by * s), cz + fz * t - (mz + bz * s)
  return t, s, math.sqrt(qx * qx + qy * qy + qz * qz)
end

-- Look for a unit near your head with a muzzle whose barrel line actually passes
-- through the camera's line ahead of you (a holstered gun on your back doesn't).
local function find_gun(world, cx, cy, cz, hx, hy, hz, fx, fy, fz, skip1, skip2)
  local best, best_miss
  -- Your own weapons sit 0.6-0.8 m from your head (v10.25-27 logs); the 3 m reach is only
  -- for weapon emplacements and seats (v10.27: a gun 1.45 m away was picked for 8 s).
  local reach = GUN.wide and CFG.BARREL_SEARCH_RADIUS or CFG.BARREL_HAND_RADIUS   -- (GUN.wide: set by apply())
  local cands = {}   -- every gun that qualified, for the log
  if GUN.reject_epoch ~= WORLD.epoch then GUN.reject, GUN.reject_epoch = {}, WORLD.epoch end
  for _, u in pairs(try(sr.World.units, world) or {}) do
    local rejected = false
    for _, r in ipairs(GUN.reject) do if rawequal(u, r) then rejected = true end end
    if u ~= skip1 and u ~= skip2 and not rawequal(u, skip1) and not rejected then
      for _, name in ipairs(MUZZLE_NODES) do
        if try(sr.Unit.has_node, u, name) then
          local node = try(sr.Unit.node, u, name)
          local pose = node and try(sr.Unit.world_pose, u, node)
          if pose then
            local p = M.translation(pose)
            local dx, dy, dz = V.x(p) - hx, V.y(p) - hy, V.z(p) - hz
            if dx * dx + dy * dy + dz * dz < reach * reach then
              for ai, a in ipairs(gun_axes(pose)) do
                local dot = a[1] * fx + a[2] * fy + a[3] * fz
                local sg = dot < 0 and -1 or 1
                if math.abs(dot) > math.cos(math.rad(CFG.BARREL_AXIS_MAX_DEG)) then
                  local t, s, miss = line_meet(cx, cy, cz, fx, fy, fz, V.x(p), V.y(p), V.z(p), a[1] * sg, a[2] * sg, a[3] * sg)
                  if t > 0.5 and s > 0 and miss < CFG.BARREL_MAX_MISS then
                    local c = {unit = u, node = node, name = name, axis = ai, sign = sg, miss = miss, t = t,
                               dist = math.sqrt(dx * dx + dy * dy + dz * dz), up = dz}
                    cands[#cands + 1] = c
                    if not best_miss or miss < best_miss then best_miss, best = miss, c end
                  end
                end
              end
            end
          end
          break
        end
      end
    end
  end
  if best then
    GUN.unit, GUN.node, GUN.axis, GUN.sign = best.unit, best.node, best.axis, best.sign
    GUN.good, GUN.bad_time, GUN.hd_ema, GUN.float_t = 0, 0, nil, 0
    log(string.format('barrel aiming: found a gun (%s, node %s, axis %d%s, %.2f m from your head)',
      tostring(try(sr.Unit.resource_name, best.unit) or '?'), best.name, best.axis, best.sign < 0 and ' reversed' or '', best.dist or -1))
    -- Every candidate, so a wrong pick (e.g. a Guard Dog) can be told apart in the log.
    local parts = {}
    for i, c in ipairs(cands) do
      if i > 6 then break end
      parts[#parts + 1] = string.format('%s node %s %.2f m from head (%+.2f up) aim line miss %.2f m at %.1f m%s',
        tostring(try(sr.Unit.resource_name, c.unit) or '?'), c.name, c.dist, c.up, c.miss, c.t, c == best and ' [picked]' or '')
    end
    log(string.format('barrel aiming: %d candidate(s): %s', #cands, table.concat(parts, ' | ')))
  end
end

-- Update the barrel estimate for this frame. Returns nothing; sets GUN.d when trusted.
local function update_barrel(world, cx, cy, cz, fx, fy, fz, hx, hy, hz, dt, skip1, skip2, acquiring)
  if GUN.unit and not try(sr.Unit.alive, GUN.unit) then gun_drop('it no longer exists') end
  if not GUN.unit then
    GUN.d, GUN.good = nil, 0
    -- Only pick up a gun while aiming: at hip or mid-draw it points at odd angles.
    if acquiring and clock >= GUN.scan_at then
      GUN.scan_at = clock + 2
      find_gun(world, cx, cy, cz, hx, hy, hz, fx, fy, fz, skip1, skip2)
    end
    return
  end
  local pose = try(sr.Unit.world_pose, GUN.unit, GUN.node)
  if not pose then gun_drop('its barrel can no longer be read'); return end
  local mp = M.translation(pose)
  local mx, my, mz = V.x(mp), V.y(mp), V.z(mp)
  local a = gun_axes(pose)[GUN.axis]
  local bx, by, bz = a[1] * GUN.sign, a[2] * GUN.sign, a[3] * GUN.sign
  -- Is the gun itself still swinging (catching up after a turn; slower with
  -- low-ergonomics weapons)? Then its line isn't pointing at the aim point yet.
  local swinging = false
  if GUN.pb and dt > 0 then
    local dot = math.max(-1, math.min(1, bx * GUN.pb[1] + by * GUN.pb[2] + bz * GUN.pb[3]))
    swinging = math.deg(math.acos(dot)) / dt > CFG.BARREL_STEADY
  end
  GUN.pb = {bx, by, bz}
  if swinging then return end
  local t, s, miss = line_meet(cx, cy, cz, fx, fy, fz, mx, my, mz, bx, by, bz)
  if s < 0 then miss = 99 end
  -- A gun far from your head (dropped, holstered on a swap) or not pointing along
  -- your view is not the one you're aiming: look again.
  local hdx, hdy, hdz = mx - hx, my - hy, mz - hz
  local keep_r = CFG.BARREL_SEARCH_RADIUS + 0.5
  local hd = math.sqrt(hdx * hdx + hdy * hdy + hdz * hdz)
  if hd > keep_r then gun_drop(string.format('%.1f m from your head', hd)); return end
  -- Your gun sits rigidly in your hands; a drone (the Guard Dog) floats around you.
  -- A muzzle drifting relative to your head is not yours: drop it for this world.
  if acquiring then GUN.aim_t = (GUN.aim_t or 0) + dt else GUN.aim_t = 0 end
  if not GUN.hd_ema or clock - (GUN.seen_t or -99) > 0.3 or GUN.aim_t < CFG.BARREL_FLOAT_SETTLE then GUN.hd_ema, GUN.float_t = hd, 0 end
  GUN.seen_t = clock
  GUN.hd_ema = GUN.hd_ema + (hd - GUN.hd_ema) * (1 - math.exp(-dt / 0.5))
  local drift = math.abs(hd - GUN.hd_ema)
  if drift > CFG.BARREL_FLOAT then GUN.float_t = GUN.float_t + dt else GUN.float_t = 0 end
  if GUN.float_t >= CFG.BARREL_FLOAT_TIME then
    if GUN.strikes_epoch ~= WORLD.epoch then GUN.strikes, GUN.strikes_epoch = {}, WORLD.epoch end
    local n = 0
    for _, e in ipairs(GUN.strikes) do if rawequal(e.u, GUN.unit) then e.n = e.n + 1; n = e.n end end
    if n == 0 then GUN.strikes[#GUN.strikes + 1] = {u = GUN.unit, n = 1}; n = 1 end
    if n >= 2 then
      GUN.reject[#GUN.reject + 1] = GUN.unit
      gun_drop(string.format('its muzzle drifted %.2f m relative to your head for %.1f s, for the 2nd time - not in your hands (a drone such as the Guard Dog?); not picked again in this world', drift, GUN.float_t))
    else
      gun_drop(string.format('its muzzle drifted %.2f m relative to your head for %.1f s (1st time: it may be picked again; a 2nd time rules it out for this world)', drift, GUN.float_t))
    end
    return
  end
  GUN.miss = miss
  if miss <= CFG.BARREL_MAX_MISS and t > 0.5 then
    GUN.good, GUN.bad_time = GUN.good + 1, 0
    local td = math.min(250, t)
    GUN.d = GUN.d and math.exp(math.log(GUN.d) + (math.log(td) - math.log(GUN.d)) * (1 - math.exp(-dt / 0.08))) or td
    if GUN.good >= CFG.BARREL_CONFIRM then GUN.last_d, GUN.last_t = GUN.d, clock end
  else
    GUN.bad_time = GUN.bad_time + dt
    if GUN.bad_time > 0.5 then GUN.good, GUN.d = 0, nil end
    if GUN.bad_time > 3.0 then gun_drop('not pointing along your view for 3 s') end    -- probably the wrong gun: search again
  end
end
H.update_barrel = update_barrel

local function barrel_trusted() return GUN.d ~= nil and GUN.good >= CFG.BARREL_CONFIRM end

local function aim_distance(world, cx, cy, cz, fx, fy, fz, min_d)
  if CFG.BARREL_AIM and barrel_trusted() then
    if AIMFIX.mode ~= 'barrel' then
      AIMFIX.mode = 'barrel'
      if not AIMFIX.barrel_logged then AIMFIX.barrel_logged = true; log('aim alignment: using the gun barrel to find your aim point') end
    end
    return math.max(min_d, GUN.d)
  end
  if AIMFIX.mode == 'barrel' then AIMFIX.mode = 'fixed' end
  -- Recently lost the barrel: ease from its last distance towards the fallback
  -- rather than jumping, so the turn-in angle never twitches.
  if CFG.BARREL_AIM and GUN.last_d and clock - GUN.last_t < CFG.BARREL_MEMORY then
    local w = (clock - GUN.last_t) / CFG.BARREL_MEMORY
    local fb = CFG.AIM_FALLBACK_DISTANCE
    return math.max(min_d, math.exp(math.log(GUN.last_d) + (math.log(fb) - math.log(GUN.last_d)) * w))
  end
  if AIMFIX.mode ~= 'fixed' then
    AIMFIX.mode = 'fixed'
    if not AIMFIX.fixed_logged then
      AIMFIX.fixed_logged = true
      log(string.format('aim alignment: no gun barrel found yet, assuming a %d m aim distance', CFG.AIM_FALLBACK_DISTANCE))
    end
  end
  return CFG.AIM_FALLBACK_DISTANCE
end
H.aim_distance = aim_distance

local SPR = {}
local NOANIM = {ok = false}
local DH = {active = false, t = 1}   -- dive hold
local function spring(x, v, target, w, dt)
  local f = 1 + 2 * dt * w
  local hoo = dt * w * w
  local inv = 1 / (f + dt * hoo)
  return (f * x + dt * v + dt * hoo * target) * inv, (v + hoo * (target - x)) * inv
end

-- Research: log your Helldiver's animation state whenever it changes, with
-- context, so the next version can react to real actions (dive, sprint, getting
-- up) instead of guessing from the camera.
local ANIM = {timer = 0, last = nil, lines = 0}
local function log_anim(unit, dt, ctx)
  ANIM.timer = ANIM.timer + dt
  if ANIM.timer < 0.05 or ANIM.lines > 20000 then return end
  ANIM.timer = 0
  local res = {pcall(sr.Unit.animation_get_state, unit)}
  if not res[1] then
    if not ANIM.failed then ANIM.failed = true; log('anim: animation_get_state failed: ' .. tostring(res[2])) end
    return
  end
  local parts = {}
  for i = 2, #res do
    local v = res[i]
    if type(v) == 'table' then
      local t = {}
      for k, x in pairs(v) do t[#t + 1] = tostring(k) .. '=' .. tostring(x) end
      parts[#parts + 1] = '{' .. table.concat(t, ' ') .. '}'
    else
      parts[#parts + 1] = tostring(v)
    end
  end
  local s = table.concat(parts, ',')
  if s ~= ANIM.last then
    ANIM.last = s
    ANIM.lines = ANIM.lines + 1
    log('anim: ' .. s .. ' | ' .. ctx)
  end
end
H.log_anim = log_anim



-- Your Helldiver's animation state machine (31 layers). Mapped from your logs:
--   layer 22: 6/7 standing, 2/3 crouched, 4/5 prone
--   layer 3: 71 (or layer 1: 78 at the start) = sprinting. Layer 1: 76 is the
--   slow-down out of a sprint, and layer 21 lags behind both.
--   layer 2:  34/35 and layer 3: 35/24 = diving (going prone on purpose never uses these)
--   layer 14: see ANIMATION REFERENCE below for every known value
-- If the numbers ever stop matching (e.g. after a game update), the mod falls
-- back to its older camera-based guesses and says so in the log.
local AN = {ok = false, bad = 0, seen = false, cur = nil, from = nil, t = 1, logged_l14 = {},
            pending = nil, pending_t = 0, sprint = false, sprint_off_t = 0}

-- Aiming or not, from the weapon pose (see CFG.AIM_POSES / HIP_POSES):
--   aiming pose  -> the camera reading as it is (the game's camera gliding in);
--   hip pose     -> not aiming, whatever the camera does (the ship's close camera,
--                   the hip camera pulling in near walls - v10.19 read those as aiming);
--   unknown pose / no animations -> the camera reading, minus a dead zone; an
--                   unknown pose is logged once so it can be added to the lists.
local AIMPOSE = {logged = {}, rel = nil, cf_t = 0, lo_t = 0, cf_on = false, cf_n = 0, lo_n = 0, cf_logged = {}, lo_logged = {}}
-- v10.31: the pose lists can't cover every weapon (Ballistic Shield: crouched pose 8 /
-- prone 18 / standing 67 all aimed in; Evictor: standing 59 at the hip camera). When
-- pose and camera disagree, the camera decides - see CFG.AIM_CONFLICT_* / AIM_POSE_STALE.
-- fits: the game's camera sits steadily at the stance's aim distance (from apply()).
local function aim_target(aim_raw, A, prev, dt, fits)
  local pose = A.ok and AN.l4 or nil
  dt = dt or 0
  if pose ~= nil and CFG.HIP_POSES[pose] then
    AIMPOSE.lo_t = 0
    local ship = pose == 76 or A.l14 == 3
    if not CFG.AIM_TRUST_CAMERA or ship or aim_raw < CFG.AIM_CONFLICT_IN then
      AIMPOSE.cf_t = 0
      if AIMPOSE.cf_on then
        AIMPOSE.cf_on = false
        log(string.format('aim: camera moved out (reading %.2f, weapon pose %s) - not aiming', aim_raw, tostring(pose)))
      end
      return 0
    end
    local was_aiming = (prev or 0) >= 0.5
    if was_aiming then AIMPOSE.cf_t = CFG.AIM_CONFLICT_TIME
    elseif fits then AIMPOSE.cf_t = AIMPOSE.cf_t + dt
    else AIMPOSE.cf_t = 0 end
    if AIMPOSE.cf_t < CFG.AIM_CONFLICT_TIME then return 0 end
    if not AIMPOSE.cf_on then
      AIMPOSE.cf_on = true
      AIMPOSE.cf_n = AIMPOSE.cf_n + 1
      if not AIMPOSE.cf_logged[pose] then
        AIMPOSE.cf_logged[pose] = true
        log(string.format('aim: weapon pose %s says hip but the game\'s camera is aimed in (reading %.2f%s) - the camera decides: aiming (logged once per pose; "pose_vs_cam" on status lines counts them)',
          tostring(pose), aim_raw, was_aiming and ', you were already aiming' or ''))
      end
    end
    return aim_raw
  end
  AIMPOSE.cf_t = 0
  if AIMPOSE.cf_on then AIMPOSE.cf_on = false end
  if pose ~= nil and CFG.AIM_POSES[pose] then
    if CFG.AIM_TRUST_CAMERA and aim_raw < CFG.AIM_DEADZONE then
      AIMPOSE.lo_t = AIMPOSE.lo_t + dt
      if AIMPOSE.lo_t >= CFG.AIM_POSE_STALE then
        if AIMPOSE.lo_t - dt < CFG.AIM_POSE_STALE then
          AIMPOSE.lo_n = AIMPOSE.lo_n + 1
          if not AIMPOSE.lo_logged[pose] then
            AIMPOSE.lo_logged[pose] = true
            log(string.format('aim: weapon pose %s says aiming but the game\'s camera stayed out for %.1f s (reading %.2f) - the camera decides: not aiming (logged once per pose; "cam_vs_pose" on status lines counts them)',
              tostring(pose), CFG.AIM_POSE_STALE, aim_raw))
          end
        end
        return 0
      end
    else
      AIMPOSE.lo_t = 0
    end
    return aim_raw
  end
  AIMPOSE.lo_t = 0
  if pose ~= nil and not AIMPOSE.logged[pose] and aim_raw > CFG.AIM_DEADZONE then
    AIMPOSE.logged[pose] = true
    log(string.format('aim: unknown weapon pose %s (camera reading %.2f) - using the camera with a dead zone; please report it with whether you were aiming',
      tostring(pose), aim_raw))
  end
  return math.max(0, (aim_raw - CFG.AIM_DEADZONE) / (1 - CFG.AIM_DEADZONE))
end
-- Letting go of aim (v10.22): the weapon pose flips to hip in one frame, but the
-- game's camera glides back out. Instead of dropping straight to hip (zoom, offsets
-- and FOV snapping), ease out WITH the game's camera: follow its reading down, never
-- back up, and finish within AIM_RELEASE_MAX (x Camera Smoothness) at the latest.
-- prev: last frame's value. Only ever after real aiming (prev 0 stays 0: the ship's
-- close camera or the hip camera pulling in never start it).
-- (status lines) times the camera overruled the pose this period, either way; resets them
function H.aim_counts()
  local a, b = AIMPOSE.cf_n, AIMPOSE.lo_n
  AIMPOSE.cf_n, AIMPOSE.lo_n = 0, 0
  return a, b, AIMPOSE.cf_on and 'cam' or 'pose'
end
function H.aim_gate(aim_raw, A, prev, dt, fits)
  local g = aim_target(aim_raw, A, prev, dt, fits)
  prev = prev or 0
  if g >= prev - 1e-4 then AIMPOSE.rel = nil; return g end
  if not AIMPOSE.rel then AIMPOSE.rel = {from = prev, t = 0} end
  local R = AIMPOSE.rel
  R.t = R.t + (dt or 0)
  local cap = R.from * math.max(0, 1 - R.t / sm(CFG.AIM_RELEASE_MAX))
  local v = math.max(g, math.min(prev, aim_raw, cap))
  if v <= g + 0.01 then AIMPOSE.rel = nil; return g end
  return v
end
local SPRINT_L1 = {[78] = true, [79] = true}   -- 78 sprint start, 79 a second sprint loop (v10.24 log: 4 s of sprint missed)
-------------------------------------------------------------------------------
-- ANIMATION REFERENCE (from in-game logs; sr.Unit.animation_get_state gives 31
-- layers - "L1".."L31" below = the 1st..31st value on an "anim:" log line).
-- Kept here so values never have to be dug out of old logs again.
--
-- STANCE (L22)              6/7 = standing, 2/3 = crouched, 4/5 = prone
--                           1   = standing ON THE SHIP (ship uses its own set)
-- SPRINT                    L3 = 71, or L1 = 78 (start); L1 = 76 = slowing down
--                           (L1 = 80/81/82 also seen while running - unconfirmed)
-- DIVE                      L2 = 34/35, or L3 = 24/35
-- DEATH                     L14 = 103, or L5 = 0 together with L22 = 0
--
-- L9 (short pulses, not lasting states)
--   329 / 330               climbing out of the hellpod (mission start / respawn)
--   247 / 248               ship: Armoury terminal (start of use)
--   250 / 251               ship: Command Centre terminal (start of use)
--   253 / 255 / 254         ship: GALACTIC MAP / war table - 253 going in, 255 HELD while
--                           using it (head leans in to ~1.45 m), 254 leaving -> game camera
--                           (the map uses the normal gameplay camera unit, FOV 30/20)
--   307 / 308               JUMP PACK launch (layer 2 = 49/50 at the same time)
--   237 / 238               in the air (jump pack flight, and also plain falls/drops)
--   312                     landing
--                           -> the Jump Pack section runs from 307/308 until 312
--   282 ... 283             mission: an episode always starts 282 and ends 283, cycling
--                           284, 291/292, 294/295, 285/286, 288/289 in between (1-9 s) -
--                           unknown - NOT the jump pack (that is 307-312); possibly reloading
--
-- L14 (lasting states)
--   36                      on foot (missions)
--   3                       on foot (ship)
--   15                      ship: map open                         -> game camera
--   17                      ship: in the hellpod (head below root) -> game camera
--   42                      FRV seat 1 getting in (NOT the warp pack - that label was wrong)
--   Weapon emplacements     getting on / used / getting off       -> game camera
--     Anti-Tank             22 / 21 / 23   (game switches to its own scope, FOV ~22.5)
--     Grenadier Battlement  - / 27 / -
--     HMG                   87 / 86 / 88   (HMG camera FOV ~72 - must not be learned as base FOV)
--   Vehicles                getting in / seated / getting out  (head height when seated)
--     FRV seat 1 (driver)   42 / 64 / 54 or 55   (0.72 m)   [L1 = 108 while driving]
--     FRV seat 2            41 / 62 / 52   (0.71 m)
--     FRV seat 3            44 / 66 / 56   (0.71 m)
--     FRV seat 4            45 / 68 / 58   (0.69 m)
--     FRV seat 5 (gunner)   39 / 60 / 48   (1.42-1.66 m - standing)
--     Tank driver           98 / 102 / 101 (98: climbing up, head ~2.2 m)
--     Tank gunner           97 / 96 / 100
--   25 then 26              unknown: ~4 s with head low (0.5-0.8 m), then 26 when
--                           getting up - seen once (log of v10.5) - to identify
--   89                      seen once near the end of a mission, head low - possibly
--                           boarding the Pelican at extraction
-- L1 (movement): 84 / 86 / 87 / 90 / 92 / 93 change during jump-pack flights but also while
--   standing still - unreliable; use layer 9 for the jump pack
--
-- ACTED ON: every seat above (SEAT_GROUP: driver / passenger / tank_gunner,
-- getting in and out included); special 15, 17, 21-23, 27, 86-88 and layer 9
-- 253-255; death 103.
-------------------------------------------------------------------------------
-- Vehicle seats by group, getting in / seated / getting out (from your logs).
local SEAT_GROUP = {
  -- drivers: FRV seat 1, tank driver
  [42] = 'driver', [64] = 'driver', [54] = 'driver', [55] = 'driver',
  [98] = 'driver', [102] = 'driver', [101] = 'driver',
  -- FRV passengers and the FRV's standing rear gunner (they aim their own weapons)
  [41] = 'passenger', [62] = 'passenger', [52] = 'passenger',
  [44] = 'passenger', [66] = 'passenger', [56] = 'passenger',
  [45] = 'passenger', [68] = 'passenger', [58] = 'passenger',
  [39] = 'passenger', [60] = 'passenger', [48] = 'passenger',
  -- the tank's gunner
  [97] = 'tank_gunner', [96] = 'tank_gunner', [100] = 'tank_gunner',
}
-- Handed to the game's camera (from your logs): weapon emplacements while used
-- (Anti-Tank 22/21/23, Grenadier Battlement 27, HMG 87/86/88), and on the ship
-- the map (15) and the hellpod (17).
local SPECIAL_L14 = {[21] = 'emplacement', [22] = 'emplacement', [23] = 'emplacement', [27] = 'emplacement',
                     [86] = 'emplacement', [87] = 'emplacement', [88] = 'emplacement', [15] = 'ship map', [17] = 'hellpod'}
local SPECIAL_L9 = {[253] = 'galactic map', [254] = 'galactic map', [255] = 'galactic map'}
local KNOWN_L14 = {[3] = true, [15] = true, [17] = true, [21] = true, [22] = true, [23] = true, [27] = true,
                   [86] = true, [87] = true, [88] = true, [36] = true, [103] = true, [89] = true}
for k in pairs(SEAT_GROUP) do KNOWN_L14[k] = true end
local ANIM_STANCE = {[6] = 3, [7] = 3, [2] = 2, [3] = 2, [4] = 1, [5] = 1, [1] = 3}   -- 1: standing on the ship
local function anim_classify(unit, dt)
  local s = {pcall(sr.Unit.animation_get_state, unit)}
  local ok = s[1] and #s >= 32   -- your Helldiver has 31 animation layers
  local stance = ok and ANIM_STANCE[s[23]] or nil     -- s[1] is pcall's status, so layer n is s[n+1]
  AN.l4 = ok and s[5] or nil                           -- weapon pose (aiming or not)
  if stance then
    AN.bad, AN.seen = 0, true
  else
    AN.bad = AN.bad + dt
  end
  local was = AN.ok
  AN.ok = AN.seen and AN.bad < 1.0
  if AN.ok ~= was then
    log(AN.ok and 'animation states recognised: using them' or 'animation states not recognised: using camera-based detection')
  end
  if s[1] and #s >= 32 and (s[15] == 103 or (s[6] == 0 and s[23] == 0)) then
    AN.dead = true
    return AN
  end
  AN.dead = false
  if not AN.ok then return AN end
  local L1, L2, L3, L14 = s[2], s[3], s[4], s[15]
  -- Death: most layers drop to 0 and layer 14 reads 103 (from your log).
  AN.dead = (L14 == 103) or (s[6] == 0 and s[23] == 0)
  AN.dive    = (L2 == 34 or L2 == 35 or L3 == 24 or L3 == 35)
  AN.seat = SEAT_GROUP[L14]
  AN.vehicle = AN.seat ~= nil
  AN.l9 = s[10]
  -- Jump pack: starts on the launch (layer 9 = 307/308), stays on through the
  -- flight (237/238), ends on landing (312) or anything else. Plain falls and
  -- drops (237/238 without a launch) don't count.
  local l9 = s[10]
  if l9 == 307 or l9 == 308 then
    AN.jetpack = true
  elseif not (AN.jetpack and (l9 == 237 or l9 == 238)) then
    AN.jetpack = false
  end
  AN.special = SPECIAL_L14[L14] or SPECIAL_L9[s[10]]
  AN.l14, AN.l14_epoch = L14, WORLD.epoch
  if not KNOWN_L14[L14] and not AN.logged_l14[L14] then
    AN.logged_l14[L14] = true
    log('anim: unmapped layer 14 value ' .. tostring(L14) .. ' (please report if it was a vehicle or new action)')
  end
  -- Sprint: on the moment the sprint animation starts; off once it has been
  -- gone for a tenth of a second (the gait flickers briefly between cycles).
  if SPRINT_L1[L1] or L3 == 71 then
    AN.sprint, AN.sprint_off_t = true, 0
  elseif AN.sprint then
    AN.sprint_off_t = AN.sprint_off_t + dt
    if AN.sprint_off_t > 0.08 then AN.sprint = false end
  end
  -- Stance: ignore split-second blips (standing -> prone passes through a
  -- one-frame "crouch"), but follow a real change after STANCE_DEBOUNCE.
  if not AN.cur then AN.cur, AN.from, AN.t = stance, stance, 1 end
  if stance and stance ~= AN.cur then
    if stance ~= AN.pending then AN.pending, AN.pending_t = stance, 0 end
    AN.pending_t = AN.pending_t + dt
    if AN.pending_t >= CFG.STANCE_DEBOUNCE then
      AN.from, AN.cur, AN.t, AN.pending = AN.cur, stance, 0, nil
    end
  else
    AN.pending = nil
  end
  AN.t = math.min(1, AN.t + dt / sm(CFG.STANCE_BLEND))
  return AN
end

-- Framing for the current animation stance, blended smoothly from the previous one.
local function anim_stance()
  local a, b = effective(AN.from), effective(AN.cur)
  local t = AN.t * AN.t * (3 - 2 * AN.t)
  local r = {}
  for _, k in ipairs({'hip', 'aim', 'side', 'lift', 'hip_lat', 'hip_vert'}) do r[k] = a[k] + (b[k] - a[k]) * t end
  return r, STANCES[AN.cur].name
end
H.anim_stance = anim_stance

---------------------------------------------------------------- identity (which Helldiver is you)
-- Every Helldiver uses the same model, so "closest to the camera" can pick a teammate.
--   (HD2 has no network ownership to ask - no unit synchroniser, v10.11-v10.13 logs -
--   so that check was removed in v10.24.) Your input (keys / stick) and the camera test: the game camera follows only YOU, so your head
--      stays roughly put on its screen while the view turns and the camera moves;
--      anyone else's drifts. While checking, the best guess is framed as normal; the
--      camera is only left to the game while that guess CLEARLY fails (moves on screen
--      at least as much as the whole swing). Confirmed when one stays put while every
--      other one seen as long drifts, or after 8 s of reasonable following.
-- Turning alone can't separate you from a teammate shoulder to shoulder (the camera
-- orbits around you, so they barely move either); moving the camera can.
function H.id_begin(why)
  -- Was this pick your climb-out (strong evidence)? Then it is never re-guessed.
  ID.from_respawn = (SAFE.gate ~= nil) and not why
  ID.last_t = clock
  -- A Helldiver that climbed out of a hellpod has been picked up: the respawn check
  -- has done its job (a spectated teammate can no longer be picked).
  if SAFE.gate and anchor and not why then SAFE.gate = nil; log('respawn check: done') end
  if ID.locked then ID.was = ID.locked end   -- still watched for death while stepped aside
  ID.verifying, ID.c, ID.prev, ID.started, ID.locked, ID.L, ID.log_at = true, {}, nil, clock, nil, nil, clock + 1.0
  ID.many, ID.many_logged = false, nil
  ID.aside, ID.checked, ID.method = false, 0, nil
  if why then log('identity: ' .. why) end
end

local function id_score(e) return (e.sw or 0) > 0 and e.res / e.sw or nil end
local function id_input_share(e) return (e.it or 0) > 0 and (e.im or 0) / e.it or nil end

-- One candidate's evidence from this sample (rot = view turn in radians, dTp =
-- sideways/up camera movement in metres).
local function id_measure(e, h, rot, dTp)
  if e.o and math.abs(h.along - e.o[1]) <= CFG.ID_RIG_STEP then
    local sw = rot * math.max(1, h.d) + dTp
    if sw >= CFG.ID_MIN_SWING then
      e.sw = (e.sw or 0) + sw
      e.res = (e.res or 0) + math.abs(h.lat - e.o[2]) + math.abs(h.vert - e.o[3])
    end
  end
  e.o = {h.along, h.lat, h.vert, h.d}
end

-- Where your head sits on the game camera (any stance, aiming or not, either shoulder).
local function id_plausible(o)
  return o[1] > 0.6 and o[1] < 4.0 and math.abs(o[2]) < 1.2 and o[3] > -0.8 and o[3] < 0.5
end

local function id_list(cands)
  local t = {}
  for i, e in ipairs(cands) do
    local o = e.o or {0, 0, 0, 0}
    local sc = id_score(e)
    local ish = id_input_share(e)
    t[#t + 1] = string.format('#%d %.1fm (ahead %.2f side %+.2f up %+.2f) swing %.2f moved %.2f score %s input %s%s', i, o[4], o[1], o[2], o[3],
      e.sw or 0, e.res or 0, sc and string.format('%.2f', sc) or '-',
      ish and string.format('%.0f%% of %.1fs', ish * 100, e.it) or '-', (anchor and same(anchor.unit, e.unit)) and ' [current pick]' or '')
  end
  return #t > 0 and table.concat(t, '; ') or 'none in view'
end

-- Movement input (keyboard WASD, or controller 1's left stick when it's in use),
-- read straight from the engine. Returns forward, right in -1..1, or nil when no
-- movement is being pressed. Every function is checked once; anything missing is
-- logged and simply not used.
local INP = {held = 0, dir = nil, src = nil}
function H.input_intent()
  if not CFG.INPUT_ID then return nil end
  local fw, rt, src = 0, 0, nil
  local K = rawget(sr, 'Keyboard')
  if INP.idx == nil then
    INP.idx = {}
    local found = {}
    if type(K) == 'table' and type(K.button_index) == 'function' and type(K.button) == 'function' then
      log('input: first call to Keyboard.button_index')
      for k, name in pairs(CFG.INPUT_KEYS) do
        local ok, i = pcall(K.button_index, name)
        if ok and i ~= nil then INP.idx[k] = i; found[#found + 1] = name .. '=' .. tostring(i) end
      end
    end
    log(#found > 0 and ('input: keyboard movement keys found (' .. table.concat(found, ' ') .. ')')
      or 'input: keyboard not available - keyboard movement not used')
  end
  local function key(k)
    local i = INP.idx[k]
    if i == nil then return 0 end
    local ok, v = pcall(K.button, i)
    return (ok and type(v) == 'number') and v or 0
  end
  if next(INP.idx) then fw, rt = key('forward') - key('back'), key('right') - key('left') end
  if fw ~= 0 or rt ~= 0 then src = 'keys' end
  local P = rawget(sr, 'Pad1')
  if INP.stick == nil then
    INP.stick = false
    if type(P) == 'table' and type(P.axis_index) == 'function' and type(P.axis) == 'function' then
      log('input: first call to Pad1.axis_index')
      local ok, i = pcall(P.axis_index, 'left')
      if ok and i ~= nil then INP.stick = i end
    end
    log(INP.stick and ('input: controller left stick found (axis ' .. tostring(INP.stick) .. ')') or 'input: controller stick not available')
  end
  if INP.stick and not src then
    local oka, active = true, true
    if type(P.active) == 'function' then oka, active = pcall(P.active) end
    if oka and active then
      local ok, v = pcall(P.axis, INP.stick)
      if ok and v then
        local okx, x = pcall(V.x, v)
        local oky, y = pcall(V.y, v)
        if okx and oky and type(x) == 'number' and type(y) == 'number' and math.abs(x) + math.abs(y) > 0.3 then
          fw, rt, src = y, x, 'controller'
        end
      end
    end
  end
  if not src then return nil end
  if not INP.seen then INP.seen = true; log('input: movement read from your ' .. src .. ' (input identity is working)') end
  return fw, rt, src
end

-- One sample of input evidence for a candidate: did it move the way you're pressing?
-- (wx, wy = the pressed direction in the world, or nil; steady = held long enough)
local function id_measure_input(e, bx, by, wx, wy, steady)
  if bx and e.rp and steady and wx then
    local dt = clock - e.rp[3]
    if dt > 0.02 and dt < 0.5 then
      local vx, vy = (bx - e.rp[1]) / dt, (by - e.rp[2]) / dt
      local sp = math.sqrt(vx * vx + vy * vy)
      e.it = (e.it or 0) + dt
      if sp >= CFG.ID_INPUT_SPEED and (vx * wx + vy * wy) / sp >= math.cos(math.rad(CFG.ID_INPUT_ANGLE)) then
        e.im = (e.im or 0) + dt
      end
    end
  end
  e.rp = bx and {bx, by, clock} or nil
end

local function id_lock(unit, node, msg, method)
  local list = id_list(ID.c)
  ID.locked_at = clock
  ID.verifying, ID.locked, ID.c, ID.L, ID.was = false, unit, {}, nil, unit
  ID.aside, ID.method = false, method or 'camera'
  if anchor and not same(anchor.unit, unit) then
    anchor = {unit = unit, node = node}
    ST.last_anchor = anchor
    on_anchored()
    smooth_off, prev_root, engage = nil, nil, 0    -- ease in from the game camera
    GUN.unit, GUN.d, GUN.good = nil, nil, 0          -- that gun was theirs
    AN.cur, AN.from, AN.t, AN.pending = nil, nil, 1, nil
    log('identity: the confirmed Helldiver is not the first pick - switching to it')
  end
  if SAFE.gate then SAFE.gate = nil; log('respawn check: done') end
  log(string.format('identity: confirmed your Helldiver after %.1f s (%s) | %s', clock - ID.started, msg, list))
end

local function id_decide()
  -- Input first: one Helldiver clearly moves with your keys / stick, nobody else does.
  local ib, ibs
  for _, e in ipairs(ID.c) do
    local m = id_input_share(e)
    if m and e.it >= CFG.ID_INPUT_TIME and (not ibs or m > ibs) then ib, ibs = e, m end
  end
  if ib and ibs >= CFG.ID_INPUT_MATCH then
    local clear = true
    for _, e in ipairs(ID.c) do
      local m = id_input_share(e)
      if e ~= ib and m and e.it >= 0.5 * ib.it and m > CFG.ID_INPUT_OTHERS then clear = false end
    end
    if clear then
      id_lock(ib.unit, ib.node, string.format('moves with your %s: %.0f%% of %.1f s', INP.src or 'input', ibs * 100, ib.it), 'input')
      return
    end
  end
  local best, bsc, pick
  for _, e in ipairs(ID.c) do
    local sc = id_score(e)
    if sc and e.sw >= CFG.ID_PASS_SWING and (not bsc or sc < bsc) then best, bsc = e, sc end
    if anchor and same(e.unit, anchor.unit) then pick = e end
  end
  -- The current guess clearly doesn't follow the camera: leave the camera to the game.
  local psc = pick and id_score(pick)
  local failing = (psc and pick.sw >= CFG.ID_ASIDE_SWING and psc >= CFG.ID_ASIDE) and true or false
  if failing ~= ID.aside and CFG.ID_STEP_ASIDE then
    ID.aside = failing
    log(failing and string.format('identity: the current guess clearly doesn\'t follow the camera (moved %.0f%% of the swing) - game camera until someone does | %s', psc * 100, id_list(ID.c))
      or 'identity: the current guess follows the camera again - ActionCam back on')
  end
  if best and bsc <= CFG.ID_PASS then
    -- Everyone else seen for a comparable amount of swing must have clearly drifted.
    local clear = true
    for _, e in ipairs(ID.c) do
      if e ~= best and (e.sw or 0) >= 0.5 * best.sw then
        local sc = id_score(e)
        if not sc or sc < bsc * CFG.ID_MARGIN or sc < CFG.ID_PASS then clear = false end
      end
    end
    if #ID.c == 1 and not id_plausible(best.o) then clear = false end
    if clear then
      id_lock(best.unit, best.node, #ID.c == 1 and 'the only one in view, at your head\'s spot' or string.format('%d in view', #ID.c))
      return
    end
  end
  -- Long enough with the guess following reasonably and nobody doing better: accept it.
  if pick and psc and ID.checked >= CFG.ID_ACCEPT_TIME and (pick.sw or 0) >= CFG.ID_ASIDE_SWING and psc < CFG.ID_ACCEPT then
    for _, e in ipairs(ID.c) do
      local sc = id_score(e)
      if e ~= pick and sc and (e.sw or 0) >= 0.5 * pick.sw and sc <= psc then return end
    end
    id_lock(pick.unit, pick.node, string.format('followed the camera reasonably for %.0f s', ID.checked))
  end
end

-- Called from apply() with the game's camera (before ActionCam moves it).
function H.id_sample(world, cx, cy, cz, pose)
  if SPEC.active then return end   -- the spectated teammate is never checked as you
  if not anchor or not (ID.verifying or ID.locked) then return end
  if clock < ID.at then return end
  ID.at = clock + CFG.ID_SAMPLE
  -- No identity checks in vehicles, at emplacements, or while a special camera has
  -- the view (the camera follows the vehicle or gun, or isn't following you at all).
  if AN.ok and (AN.vehicle or AN.special) then ID.prev = nil; return end
  -- ...nor while diving and getting up (v10.24): the camera swings around you as you
  -- land, which read as "stopped following the camera" (v10.23 log, 1394 s).
  if AN.ok and (AN.dive or AN.jetpack or AN.l9 == 237 or AN.l9 == 238 or (ST.dive_seen and clock - ST.dive_seen <= CFG.DIVE_GRACE)) then ID.prev = nil; return end
  -- Checking was paused for over a second (the game's own camera had the view:
  -- arrival cinematic, map, hellpod) and there's no evidence yet (no view swing, no
  -- input): the first guess was made blind, so guess again from where heads sit now,
  -- before framing anyone (v10.18 framed a Helldiver 3 m to your side for a moment
  -- after arriving on the ship). Never for your climb-out, which is real evidence.
  local evidence = false
  for _, e in ipairs(ID.c) do if (e.sw or 0) > 0 or (e.it or 0) > 0 then evidence = true end end
  if ID.verifying and not ID.from_respawn and ID.last_t and clock - ID.last_t > 1.0 and not evidence then
    local a = H.pick(world, cx, cy, cz, pose, true)
    if a and not same(a.unit, anchor.unit) then
      anchor = a
      ST.last_anchor = a
      on_anchored()
      smooth_off, prev_root = nil, nil
      GUN.unit, GUN.d, GUN.good = nil, nil, 0
      AN.cur, AN.from, AN.t, AN.pending = nil, nil, 1, nil
      ID.c, ID.prev = {}, nil
      log('identity: the game\'s camera had the view - guessing again from where heads sit now')
    end
  end
  ID.last_t = clock
  local fx, fy, fz = xyz(M.forward(pose))
  local rx, ry, rz = xyz(M.right(pose))
  local ux, uy, uz = xyz(M.up(pose))
  -- How far the view turned and the camera moved sideways/up since the last
  -- sample; a camera cut starts over.
  local rot, dTp, p = 0, 0, ID.prev
  if p then
    local mx, my, mz = cx - p[1], cy - p[2], cz - p[3]
    if math.sqrt(mx * mx + my * my + mz * mz) > CFG.ID_CUT then p = nil
    else
      rot = math.acos(math.max(-1, math.min(1, fx * p[4] + fy * p[5] + fz * p[6])))
      local ma = mx * fx + my * fy + mz * fz
      dTp = math.sqrt(math.max(0, mx * mx + my * my + mz * mz - ma * ma))
    end
  end
  ID.prev = {cx, cy, cz, fx, fy, fz}
  -- Movement input, turned into a direction in the world (relative to the camera's heading).
  local ifw, irt, isrc = H.input_intent()
  local wx, wy, steady
  if ifw then
    local hx2, hy2 = fx, fy
    local hl = math.sqrt(hx2 * hx2 + hy2 * hy2)
    if hl > 0.1 then
      hx2, hy2 = hx2 / hl, hy2 / hl
      -- right (horizontal) = forward rotated 90 degrees clockwise
      wx, wy = hx2 * ifw + hy2 * irt, hy2 * ifw - hx2 * irt
      local wl = math.sqrt(wx * wx + wy * wy)
      if wl > 0.1 then wx, wy = wx / wl, wy / wl else wx, wy = nil, nil end
    end
  end
  if wx and INP.dir and (wx * INP.dir[1] + wy * INP.dir[2]) > 0.9 then INP.held = INP.held + CFG.ID_SAMPLE else INP.held = 0 end
  INP.dir = wx and {wx, wy} or nil
  if isrc then INP.src = isrc end
  steady = wx and INP.held >= CFG.ID_INPUT_HOLD
  if not p then
    for _, e in ipairs(ID.c) do e.o = nil end
    if ID.L then ID.L.o = nil end
    return
  end
  if ID.verifying then
    crumb('identity scan')
    local keep = {}
    for _, h in ipairs(H.scan_helldivers(world, cx, cy, cz, fx, fy, fz, rx, ry, rz, ux, uy, uz)) do
      if H.respawn_ok(world, h) then
        local e
        for _, x in ipairs(ID.c) do if same(x.unit, h.unit) then e = x; break end end
        e = e or {unit = h.unit, node = h.node}
        id_measure(e, h, rot, dTp)
        id_measure_input(e, h.bx, h.by, wx, wy, steady)
        keep[#keep + 1] = e
      end
    end
    ID.c = keep
    if #keep > 1 then ID.many = true end
    ID.checked = ID.checked + CFG.ID_SAMPLE
    id_decide()
    if ID.verifying and clock >= ID.log_at then
      ID.log_at = clock + CFG.ID_LOG_EVERY
      log(string.format('identity: checking for %.0f s (best guess framed meanwhile unless it clearly fails) | %s', clock - ID.started, id_list(ID.c)))
    end
    return
  end
  -- Confirmed: only your Helldiver.
  if not same(anchor.unit, ID.locked) then H.id_begin('tracked Helldiver changed - checking who is you'); return end
  local hp = try(sr.Unit.world_position, anchor.unit, anchor.node)
  if not hp then return end
  local dx, dy, dz = V.x(hp) - cx, V.y(hp) - cy, V.z(hp) - cz
  local h = {along = dx * fx + dy * fy + dz * fz, lat = dx * rx + dy * ry + dz * rz, vert = dx * ux + dy * uy + dz * uz,
             d = math.sqrt(dx * dx + dy * dy + dz * dz)}
  ID.L = ID.L or {}
  id_measure(ID.L, h, rot, dTp)
  -- Input: recent evidence counts most (older fades over ID_INPUT_MEMORY seconds).
  local fade = math.exp(-CFG.ID_SAMPLE / CFG.ID_INPUT_MEMORY)
  ID.L.it, ID.L.im = (ID.L.it or 0) * fade, (ID.L.im or 0) * fade
  local rp = try(sr.Unit.world_position, anchor.unit, 1)
  id_measure_input(ID.L, rp and V.x(rp), rp and V.y(rp), wx, wy, steady)
  if ID.L.it >= CFG.ID_INPUT_LOST_TIME then
    local m = id_input_share(ID.L)
    if m < CFG.ID_INPUT_LOST then
      H.id_begin(string.format("your Helldiver didn't move with your %s (%.0f%% recently) - checking again (still framed unless the check fails)",
        INP.src or 'input', m * 100))
      return
    end
  end
  if (ID.L.sw or 0) >= CFG.ID_ASIDE_SWING then
    local sc = id_score(ID.L)
    if sc >= CFG.ID_ASIDE then
      local o = ID.L.o
      H.id_begin(string.format("your Helldiver clearly stopped following the camera (moved %.0f%% of the swing; now %.1f m, ahead %.2f side %+.2f up %+.2f) - checking again (still framed unless the check fails)",
        sc * 100, o[4], o[1], o[2], o[3]))
    else
      ID.L.sw, ID.L.res = 0, 0
    end
  end
end

-- While unconfirmed, the normal death check (which reads the tracked Helldiver)
-- doesn't run, so watch the last confirmed Helldiver (you) for going down: a death
-- missed here would skip the respawn check, and the game then spectates a teammate
-- whom the camera follows. Returns true if you went down (everything let go).
function H.id_watch_death()
  local u = ID.was
  if not u or not AN.seen then return false end
  if not try(sr.Unit.alive, u) then ID.was = nil; return false end
  local st = {pcall(sr.Unit.animation_get_state, u)}
  if not (st[1] and #st >= 32 and (st[15] == 103 or (st[6] == 0 and st[23] == 0))) then return false end
  local rp = try(sr.Unit.world_position, u, 1)
  SAFE.dead_unit, SAFE.dead_time, SAFE.dead_pos, SAFE.dead_epoch = u, clock, rp and {V.x(rp), V.y(rp)} or nil, WORLD.epoch
  remember_body(u)
  SAFE.gate = {t = clock, epoch = WORLD.epoch, spawned = {}}
  H.gate_begin(target and target.world)
  SPEC.dead = {}
  AN.ok, AN.dead, AN.cur, AN.from, AN.t, AN.pending, AN.sprint = false, false, nil, nil, 1, nil, false
  ID.was = nil
  log('respawn check: waiting for your Helldiver to climb out of a hellpod (spectating: '
    .. (H.spec_wanted() and 'ActionCam, never counted as you' or 'game camera') .. ')')
  log('Helldiver down (while unconfirmed): handing the camera back to the game until you respawn')
  drop_all('death')
  return true
end

-- Base FOV escape hatch. The base FOV is kept all session, so a camera more than
-- SPECIAL_FOV_GAP below it is treated as special. If you really lowered your FOV
-- setting that much, accept the new value once it holds steady while you're
-- plainly on foot and the camera frames you like the gameplay camera (the 45 deg
-- ship scene after extraction sits 3.3-4.4 m back with your head above centre).
function H.fov_escape(cx, cy, cz, pose, game_deg)
  local ok = false
  if anchor and AN.seen and not SAFE.fresh then
    local hp = try(sr.Unit.world_position, anchor.unit, anchor.node)
    local st = {pcall(sr.Unit.animation_get_state, anchor.unit)}
    if hp and st[1] and #st >= 32 then
      local fx, fy, fz = xyz(M.forward(pose))
      local rx, ry, rz = xyz(M.right(pose))
      local ux, uy, uz = xyz(M.up(pose))
      local dx, dy, dz = V.x(hp) - cx, V.y(hp) - cy, V.z(hp) - cz
      local along, lat, vert = dx * fx + dy * fy + dz * fz, dx * rx + dy * ry + dz * rz, dx * ux + dy * uy + dz * uz
      ok = (st[15] == 36 or st[15] == 3) and st[10] == 0 and ANIM_STANCE[st[23]] == 3
        and along > 1.0 and along < CFG.FOV_ESCAPE_ALONG
        and math.abs(lat) > 0.15 and math.abs(lat) < 1.0 and vert > -0.7 and vert < 0.25
    end
  end
  if ok and ST.low_val and math.abs(game_deg - ST.low_val) < 0.05 and clock - (ST.low_last or -1) < 0.2 then
    ST.low_time = ST.low_time + last_dt
  else
    ST.low_val, ST.low_time = game_deg, 0
  end
  ST.low_last = clock
  if ok and ST.low_time >= CFG.FOV_ESCAPE_TIME then
    base_fov, ST.low_time = game_deg, 0
    log(string.format('base FOV lowered: %.2f (your FOV setting seems to have changed)', base_fov))
    return true
  end
  return false
end

-- First Person near plane: hide your own head/helmet by not drawing anything
-- very close to the camera. The game's value is remembered and put back whenever
-- First Person isn't being applied (other modes, vehicles, death, menus).
local NEAR = {orig = nil, active = false}
local function near_apply(cam, value)
  value = value or CFG.FP_NEAR_CLIP
  if not NEAR.active then
    local cur = try(sr.Camera.near_range, cam)
    -- Remember the game's own value once (it is what gets restored).
    if NEAR.orig == nil and type(cur) == 'number' then NEAR.orig = cur end
    if not NEAR.logged then
      NEAR.logged = true
      log(string.format('first person: game near plane %s', tostring(cur)))
    end
  end
  if value <= 0 then value = NEAR.orig or value end
  if value <= 0 then NEAR.active = true; return end
  local ok = pcall(sr.Camera.set_near_range, cam, value)
  if not ok and not NEAR.failed then NEAR.failed = true; log('first person: Camera.set_near_range not available') end
  NEAR.active = true
end
local helmet_restore_ref
local function near_restore()
  if NEAR.active and target and NEAR.orig then pcall(sr.Camera.set_near_range, target.cam, NEAR.orig) end
  NEAR.active = false
  if helmet_restore_ref then pcall(helmet_restore_ref) end
end

-- Head shrink: scale your own Helldiver's 'head' node down while in First
-- Person, so the head and anything on it (the helmet) shrink out of view. Only
-- your own unit is touched; re-applied every frame right before drawing (the
-- animation may reset it); the original scale is put back when leaving.
local SHRINK = {unit = nil, node = nil, orig = nil, logged = false, failed = false, keep = nil}
local function shrink_restore()
  if SHRINK.unit and SHRINK.orig and try(sr.Unit.alive, SHRINK.unit) then
    -- Rebuilt from plain numbers: the engine's vector values only last one frame.
    local o = SHRINK.orig
    local ok = pcall(sr.Unit.set_local_scale, SHRINK.unit, SHRINK.node, V(o[1], o[2], o[3]))
    for _, k in ipairs(SHRINK.keep or {}) do
      pcall(sr.Unit.set_local_scale, SHRINK.unit, k.i, V(k.sx, k.sy, k.sz))
      if k.base then pcall(sr.Unit.set_local_position, SHRINK.unit, k.i, V(k.base[1], k.base[2], k.base[3])) end
    end
    if target then pcall(sr.World.update_unit, target.world, SHRINK.unit) end
    if not SHRINK.restore_logged then
      SHRINK.restore_logged = true
      log('first person: head size restored' .. (ok and '' or ' (FAILED)'))
    end
  end
  SHRINK.unit, SHRINK.node, SHRINK.orig, SHRINK.keep = nil, nil, nil, nil
end
local function shrink_apply(world, me)
  if not CFG.FP_HEAD_SHRINK or SHRINK.failed then return false end
  if SHRINK.unit ~= me then
    shrink_restore()
    local node = try(sr.Unit.node, me, 'head')
    if not node then SHRINK.failed = true; log('first person: no head node to shrink'); return false end
    SHRINK.unit, SHRINK.node = me, node
    -- Keep the original size as plain numbers (engine vectors expire after a frame).
    local o = try(sr.Unit.local_scale, me, node)
    SHRINK.orig = o and {V.x(o), V.y(o), V.z(o)} or {1, 1, 1}
    -- Nodes hanging directly off the head, measured before shrinking. Those well
    -- away from the head (the cape's attachment) will keep their size and place.
    SHRINK.keep = {}
    local hp0 = try(sr.Unit.world_position, me, node)
    local n = try(sr.Unit.num_scene_graph_items, me) or 0
    local children, dists = 0, {}
    if hp0 then
      for i = 1, n do
        if i ~= node and try(sr.Unit.scene_graph_parent, me, i) == node then
          children = children + 1
          local p = try(sr.Unit.world_position, me, i)
          if p then
            local dx, dy, dz = V.x(p) - V.x(hp0), V.y(p) - V.y(hp0), V.z(p) - V.z(hp0)
            local d = math.sqrt(dx * dx + dy * dy + dz * dz)
            dists[#dists + 1] = string.format('%.2f', d)
            if d > CFG.FP_KEEP_MIN_DIST then
              local ls = try(sr.Unit.local_scale, me, i)
              local lp = try(sr.Unit.local_position, me, i)
              SHRINK.keep[#SHRINK.keep + 1] = {i = i,
                sx = ls and V.x(ls) or 1, sy = ls and V.y(ls) or 1, sz = ls and V.z(ls) or 1,
                base = lp and {V.x(lp), V.y(lp), V.z(lp)} or nil}
            end
          end
        end
      end
    end
    if not SHRINK.logged then
      SHRINK.logged = true
      log(string.format('first person: shrinking your head node (original scale %.2f,%.2f,%.2f)', SHRINK.orig[1], SHRINK.orig[2], SHRINK.orig[3]))
      log(string.format('first person: head has %d attached node(s) at %s m; keeping %d at normal size (the cape)',
        children, #dists > 0 and table.concat(dists, ', ') or '-', #SHRINK.keep))
    end
  end
  local s = CFG.FP_HEAD_SCALE
  local ok, err = pcall(sr.Unit.set_local_scale, me, SHRINK.node, V(s, s, s))
  if not ok then
    SHRINK.failed = true
    log('first person: could not shrink the head: ' .. tostring(err))
    return false
  end
  -- Cancel the shrink on the kept nodes: scale them back up and push their offset
  -- from the head back out by the same factor (a shrunk parent pulls children in).
  local inv = 1 / s
  for _, k in ipairs(SHRINK.keep or {}) do
    local lp = try(sr.Unit.local_position, me, k.i)
    if lp then
      local cx2, cy2, cz2 = V.x(lp), V.y(lp), V.z(lp)
      -- If the value is still our own last write, the animation didn't reset it:
      -- keep using the original offset (never stack the correction).
      if not (k.written and math.abs(cx2 - k.written[1]) < 1e-5 and math.abs(cy2 - k.written[2]) < 1e-5 and math.abs(cz2 - k.written[3]) < 1e-5) then
        k.base = {cx2, cy2, cz2}
      end
      local wx2, wy2, wz2 = k.base[1] * inv, k.base[2] * inv, k.base[3] * inv
      pcall(sr.Unit.set_local_position, me, k.i, V(wx2, wy2, wz2))
      k.written = {wx2, wy2, wz2}
    end
    pcall(sr.Unit.set_local_scale, me, k.i, V(k.sx * inv, k.sy * inv, k.sz * inv))
  end
  pcall(sr.World.update_unit, world, me)
  return true
end

-- Hiding your head in First Person is the head shrink above. These two keep
-- their names for the code that calls them.
local function helmet_restore()
  shrink_restore()
end
-- One frame: apply the shrink. Returns true while your head is hidden.
local function helmet_step(world, me, cam_unit, hx, hy, hz)
  if not CFG.FP_HELMET_HIDE then return false end
  -- Never change another player's Helldiver: shrinking a spectated teammate's head
  -- (v10.15/v10.16) preceded two crashes when they died and the squad respawned.
  if SPEC.active then return false end
  return shrink_apply(world, me)
end
H.helmet_step = helmet_step

near_restore_ref = near_restore
helmet_restore_ref = helmet_restore
local function skip(reason)
  counts[reason] = counts[reason] + 1
  engage = 0
  ST.sprint_s, ST.fov_offset_s = nil, nil
  SPR.f = nil
  DH.active = false
  last.pull, last.side, last.lift = nil, nil, nil
  ST.ship_off = nil
  restore_fov()
  near_restore()
end

---------------------------------------------------------------- player settings (Mod Options Menu, optional)
-- Without Mod Options Menu, ActionCam runs on its defaults (USER stays at zero).
-- With it, the MODS tab gets an "ActionCam" category: a profile choice, the
-- main adjustments (your Standing / default camera, applied ON TOP of the
-- defaults), optional per-section overrides, and saving to Custom profiles.
local USER = {enabled = true, precise_aim = true, aim_precision = 1, spectate = 1, spec_profile = 1, dist = 0, side = 0, height = 0,
              aim_dist = 0, control = 0, hd2_base = 0,
              veh_separate = 0, tg_on = 0, tg_dist = 0, tg_side = 0, tg_height = 0}
-- (No FOV sliders here: the game's FOV setting is used. Only sections have a FOV slider.)
local SLIDERS = {'dist', 'side', 'height', 'aim_dist'}
-- Sections: when switched on, their values replace the main ones in that state.
local SECTIONS = {'crouch', 'prone', 'sprint', 'dive', 'air', 'vehicle', 'aim'}   -- ('aim' added last in v10.24: saved Edit Section picks keep their places)
local SECTION_NAMES = {'Crouching', 'Prone', 'Sprinting', 'Diving', 'Jump Pack', 'Vehicles (Experimental)', 'Aiming'}   -- (Jump Pack is stored as 'air')
local SEC_FIELDS = {'on', 'dist', 'side', 'height', 'fov'}
-- Every value a profile stores (flat keys, e.g. sec_crouch_dist).
local ALLKEYS = {}
for _, k in ipairs(SLIDERS) do ALLKEYS[#ALLKEYS + 1] = k end
ALLKEYS[#ALLKEYS + 1] = 'control'
ALLKEYS[#ALLKEYS + 1] = 'hd2_base'
for _, k in ipairs({'veh_separate', 'tg_on', 'tg_dist', 'tg_side', 'tg_height'}) do ALLKEYS[#ALLKEYS + 1] = k end
-- Profile options read straight from the menu (kind: choice2 = 2-way choice, toggle, num).
local EXTRA = {veh_seats = {'veh_separate', 'choice2'}, tg_on = {'tg_on', 'toggle'},
               tg_dist = {'tg_dist', 'num'}, tg_side = {'tg_side', 'num'}, tg_height = {'tg_height', 'num'}}
for _, s in ipairs(SECTIONS) do
  for _, f in ipairs(SEC_FIELDS) do
    local key = 'sec_' .. s .. '_' .. f     -- e.g. sec_sprint_fov
    ALLKEYS[#ALLKEYS + 1] = key
    USER[key] = 0
  end
end
local CUSTOM_COUNT = 4
local PROFILE_OFF, PROFILE_DEFAULT = 1, 2          -- then Custom 1..4 are 3..6
local PROFILE_FP = 7                               -- First Person Default (added last so Custom slots keep their places)
local PROFILE_SHIP = 8                             -- Ship Camera Default (v10.24)
local BASE_SHIP = 3                                -- USER.hd2_base: 0 ActionCam, 1 Helldivers 2, 2 First Person, 3 Ship
local function is_custom(p) return p > PROFILE_DEFAULT and p <= PROFILE_DEFAULT + 4 end
-- A locked profile's values: no adjustments, just its camera base.
local function locked_values(p, copy)
  local W = copy(nil)
  if p == PROFILE_FP then W.hd2_base = 2 end
  if p == PROFILE_SHIP then W.hd2_base = BASE_SHIP end
  return W
end
local OPT = {registered = false, prefix = 'actioncam.', mod = 'ActionCam',
             pending = nil, profiles = {}, profile = PROFILE_DEFAULT, section = 1, W = {}}

local profile_choices, save_choices = {'Helldivers 2 Default (Mod Off)', 'ActionCam Default'}, {'Off'}
for i = 1, CUSTOM_COUNT do
  profile_choices[#profile_choices + 1] = 'Custom ' .. i
  save_choices[#save_choices + 1] = 'Custom ' .. i
end
profile_choices[#profile_choices + 1] = 'First Person Default'
profile_choices[#profile_choices + 1] = 'Ship Camera Default'

local OPTIONS = {
  {key = 'profile', spec = {type = 'choice', label = 'Profile', choices = profile_choices, default = PROFILE_DEFAULT,
    description = 'Helldivers 2 Default turns ActionCam off. ActionCam Default is the mod as designed. First Person Default puts the camera at your Helldiver\'s head. Ship Camera Default is the game\'s own destroyer camera, used everywhere. These four are locked. Custom profiles hold your own adjustments: switching profile loads its values into the sliders.'}},
  {key = 'dist', spec = {type = 'slider', label = 'Distance', min = -1.35, max = 2.5, step = 0.05, default = 0, gap = true,
    description = 'Closer (negative) or further (positive), in metres, compared with ActionCam Default. This is your Standing / default camera. Applies when aiming too. Going further back than the game\'s own camera can clip into walls and rocks when you stand near them.'}},
  {key = 'side', spec = {type = 'slider', label = 'Shoulder Offset', min = -1.0, max = 1.0, step = 0.02, default = 0,
    description = 'Further over your shoulder (positive) or towards the centre (negative), in metres. Follows the game\'s shoulder swap. Large values can clip into walls and rocks when you stand near them.'}},
  {key = 'height', spec = {type = 'slider', label = 'Height', min = -1.0, max = 1.0, step = 0.02, default = 0,
    description = 'Raise (positive) or lower (negative) the camera, in metres. Large values can clip into ceilings, walls and the ground.'}},
  {key = 'aim_dist', spec = {type = 'slider', label = 'Aim Distance', min = -0.45, max = 1.5, step = 0.05, default = 0, gap = true,
    description = 'Advanced. Extra closer (negative) or further (positive) when aiming only, in metres. Going further back than the game\'s aim camera can clip into walls. Field of view always follows the game\'s own FOV setting.'}},
  {key = 'base', spec = {type = 'choice', label = 'Camera Base', choices = {'ActionCam', 'Helldivers 2', 'First Person', 'Ship'}, default = 1,
    description = 'What your adjustments are layered on: ActionCam\'s over-the-shoulder camera, the game\'s own camera, First Person (at your Helldiver\'s head), or Ship (the game\'s close destroyer camera, the same in every state). First Person aims accurately once ActionCam finds your gun\'s barrel (see the log). Saving from a default profile keeps its base.'}},
  {key = 'mode', spec = {type = 'choice', label = 'Mode', choices = {'Standard Mode', 'Control Mode'}, default = 1, gap = true,
    description = 'Standard Mode: ActionCam as designed; the Customise sections below are ignored. Control Mode: each section you switch on starts as an exact copy of your standing camera and is adjusted with Edit Section.'}},
  {key = 'on_crouch', spec = {type = 'toggle', label = 'Customise Crouching', default = false, gap = true,
    description = 'Control Mode only. On: while crouched, use an exact copy of your standing camera, adjusted by the Crouching sliders (Edit Section). Off: ActionCam\'s normal crouch camera.'}},
  {key = 'on_prone', spec = {type = 'toggle', label = 'Customise Prone', default = false,
    description = 'Control Mode only. On: while prone, use an exact copy of your standing camera, adjusted by the Prone sliders (Edit Section). Off: ActionCam\'s normal prone camera.'}},
  {key = 'on_sprint', spec = {type = 'toggle', label = 'Customise Sprinting', default = false,
    description = 'Control Mode only. On: while sprinting, use an exact copy of your standing camera (no built-in sprint effects), adjusted by the Sprinting sliders (Section Field of View about +25 gives a similar widening). Off: ActionCam\'s normal sprint effects.'}},
  {key = 'on_dive', spec = {type = 'toggle', label = 'Customise Diving', default = false,
    description = 'Control Mode only. On: dives glide to a copy of your standing camera, adjusted by the Diving sliders. Off: ActionCam\'s normal dive.'}},
  {key = 'on_air', spec = {type = 'toggle', label = 'Customise Jump Pack', default = false,
    description = 'Control Mode only. On: from jump pack launch until you land, use a copy of your standing camera adjusted by the Jump Pack sliders (Edit Section). Off: ActionCam\'s normal camera.'}},
  {key = 'on_aim', spec = {type = 'toggle', label = 'Customise Aiming', default = false,
    description = 'Control Mode only. On: while aiming, the Aiming sliders (Edit Section) adjust your normal aiming camera, easing in and out with the aim. Aiming takes priority over Crouching and Prone while you aim. Its Shoulder Offset and Height are kept even at Precise Aiming 100, so large values can put the reticle slightly off up close.'}},
  {key = 'on_vehicle', spec = {type = 'toggle', label = 'Customise Vehicles (Experimental)', default = false,
    description = 'Control Mode only, experimental. Off: vehicles use the game\'s own camera (First Person stays at your head). On: the Vehicles sliders adjust the vehicle camera, or your head position in First Person. Large values can clip into the vehicle.'}},
  {key = 'section', spec = {type = 'choice', label = 'Edit Section', choices = SECTION_NAMES, default = 1, gap = true,
    description = 'Which section the four sliders below edit. The sliders adjust that section starting from an exact copy of your standing camera. Only used in Control Mode, for sections whose Customise toggle is on.'}},
  {key = 'sec_dist', spec = {type = 'slider', label = 'Section Distance', min = -1.35, max = 2.5, step = 0.05, default = 0,
    description = 'Closer (negative) or further (positive) than your standing camera, in metres, for this section. For Vehicles it moves the game\'s own vehicle camera. Large values can clip into walls, rocks and vehicles.'}},
  {key = 'sec_side', spec = {type = 'slider', label = 'Section Shoulder Offset', min = -1.0, max = 1.0, step = 0.02, default = 0,
    description = 'Further over your shoulder (positive) or towards the centre (negative) than your standing camera, in metres. For Vehicles: right (positive) or left (negative).'}},
  {key = 'sec_height', spec = {type = 'slider', label = 'Section Height', min = -1.0, max = 1.0, step = 0.02, default = 0,
    description = 'Raise (positive) or lower (negative) the camera compared with your standing camera, in metres, for this section.'}},
  {key = 'sec_fov', spec = {type = 'slider', label = 'Section Field of View', min = -30, max = 30, step = 1, default = 0,
    description = 'Degrees added to the game\'s field of view in this section.'}},
  {key = 'veh_seats', spec = {type = 'choice', label = 'Vehicle Seats', choices = {'Combined', 'Separate'}, default = 1, gap = true,
    description = 'Combined: every vehicle seat uses the vehicle camera. Separate: driver seats use the vehicle camera, while FRV passenger and gunner seats use your normal on-foot camera.'}},
  {key = 'tg_on', spec = {type = 'toggle', label = 'Tank Gunner Camera', default = false,
    description = 'Off: the tank gunner seat uses the game\'s turret camera. On: an over-the-shoulder camera behind your head (or at your head in First Person), adjusted with the three sliders below. Experimental: it can clip into the tank.'}},
  {key = 'tg_dist', spec = {type = 'slider', label = 'Tank Gunner Distance', min = -1.5, max = 3.0, step = 0.05, default = 0,
    description = 'Tank Gunner Camera: further back (positive) or closer (negative), in metres.'}},
  {key = 'tg_side', spec = {type = 'slider', label = 'Tank Gunner Side', min = -1.5, max = 1.5, step = 0.05, default = 0,
    description = 'Tank Gunner Camera: right (positive) or left (negative), in metres.'}},
  {key = 'tg_height', spec = {type = 'slider', label = 'Tank Gunner Height', min = -1.0, max = 2.0, step = 0.05, default = 0,
    description = 'Tank Gunner Camera: higher (positive) or lower (negative), in metres.'}},
  {key = 'save_as', spec = {type = 'choice', label = 'Save Current As', choices = save_choices, default = 1, gap = true,
    description = 'Pick a Custom slot and apply to save the sliders above into it and switch to it. From a locked default profile, change the sliders and pick a slot in the same apply. Editing a Custom profile saves into it automatically.'}},
  {key = 'aim_precision', spec = {type = 'slider', label = 'Precise Aiming', min = 0, max = 100, step = 5, default = 100, gap = true,
    description = 'While aiming, how far the camera lines up with the game\'s own aim so the reticle matches where shots land. 100 = exact at every range. Lower keeps more of your profile\'s side and height offsets when aiming, with a small error mostly up close. Applies to all profiles.'}},
  {key = 'smoothness', spec = {type = 'slider', label = 'Camera Smoothness', min = 50, max = 300, step = 10, default = 100,
    description = 'How gently the camera changes between states: aiming in and out, field of view, sprinting, crouching and prone, dives, and blending in after vehicles and respawns. 100 = ActionCam as designed. Higher = slower, softer transitions; lower = snappier. Applies to all profiles.'}},
  {key = 'spectate', spec = {type = 'choice', label = 'Spectating Camera', choices = {'ActionCam', 'Vanilla'}, default = 1, gap = true,
    description = 'While you wait to be reinforced, the game follows a teammate. ActionCam: frame them with ActionCam, using the Spectator Profile below. Vanilla: the game\'s own spectator camera. Applies to all profiles.'}},
  {key = 'spec_profile', spec = {type = 'choice', label = 'Spectator Profile', choices = {'Current Profile', 'ActionCam Default', 'Custom 1', 'Custom 2', 'Custom 3', 'Custom 4', 'Ship Camera Default'}, default = 1,
    description = 'The profile used while spectating with ActionCam. Current Profile follows the one you are using (Helldivers 2 Default means the game\'s camera). First Person is never used for spectating: First Person profiles use ActionCam Default over the shoulder instead. Aim alignment is off while spectating.'}},
  {key = 'reset', spec = {type = 'toggle', label = 'Reset Adjustments', default = false,
    description = 'Turn on and apply to put the sliders back to 0 (and save that into the selected Custom profile). It switches itself back off.'}},
}

-- Custom profiles are kept in their own small file beside Mod Options Menu's.
local function profiles_path()
  local dir
  pcall(function() dir = os.getenv('LOCALAPPDATA') end)
  return (dir or '') .. '\\CowboyBingus\\Helldivers2\\Logs\\ActionCam.profiles'
end

local function profiles_load()
  local ok, f = pcall(io.open, profiles_path(), 'r')
  if not ok or not f then return end
  for line in f:lines() do
    local slot, key, value = line:match('^custom(%d+)%.([%w_]+)=([%-%d%.]+)')
    slot, value = tonumber(slot), tonumber(value)
    if slot and value and slot >= 1 and slot <= CUSTOM_COUNT then
      OPT.profiles[slot] = OPT.profiles[slot] or {}
      OPT.profiles[slot][key] = value
    end
  end
  f:close()
end

local function profiles_save()
  local ok, f = pcall(io.open, profiles_path(), 'w')
  if not ok or not f then log('settings: could not write the profiles file'); return end
  f:write('# ActionCam custom profiles (adjustments on top of ActionCam Default)\n')
  for slot = 1, CUSTOM_COUNT do
    local p = OPT.profiles[slot]
    if p then
      for _, k in ipairs(ALLKEYS) do f:write(string.format('custom%d.%s=%s\n', slot, k, tostring(p[k] or 0))) end
    end
  end
  f:close()
end

local function copy_values(src_t)
  local t = {}
  for _, k in ipairs(ALLKEYS) do t[k] = (src_t and src_t[k]) or 0 end
  return t
end

local function get_num(menu, key)
  local ok, v = pcall(menu.get, OPT.prefix .. key)
  return (ok and type(v) == 'number') and v or 0
end

-- Show a profile's values in the menu: main sliders, stance framing, and the
-- currently selected section.
local function ui_write(menu, W)
  for _, k in ipairs(SLIDERS) do pcall(menu.set, OPT.prefix .. k, W[k] or 0) end
  pcall(menu.set, OPT.prefix .. 'mode', (W.control == 1) and 2 or 1)
  for id, e in pairs(EXTRA) do
    local v = W[e[1]] or 0
    if e[2] == 'choice2' then v = (v == 1) and 2 or 1 elseif e[2] == 'toggle' then v = (v == 1) end
    pcall(menu.set, OPT.prefix .. id, v)
  end
  local base_i = (OPT.profile == PROFILE_OFF) and 2 or ((W.hd2_base or 0) + 1)
  pcall(menu.set, OPT.prefix .. 'base', base_i)
  local s = SECTIONS[OPT.section]
  for _, sec in ipairs(SECTIONS) do pcall(menu.set, OPT.prefix .. 'on_' .. sec, (W['sec_' .. sec .. '_on'] or 0) == 1) end
  for _, f in ipairs({'dist', 'side', 'height', 'fov'}) do pcall(menu.set, OPT.prefix .. 'sec_' .. f, W['sec_' .. s .. '_' .. f] or 0) end
end

local function use(profile, W)
  SPEC.ov, SPEC.ov_p = nil, nil       -- (spectating re-borrows its profile on top of the new values)
  OPT.profile, OPT.W = profile, W
  USER.enabled = profile ~= PROFILE_OFF
  for _, k in ipairs(ALLKEYS) do USER[k] = W[k] or 0 end
end

local function profile_name(p) return profile_choices[p] or '?' end

---------------------------------------------------------------- spectating
-- After your death the game's camera follows a teammate until you're reinforced
-- (old logs: picked up ~5 s after death, a living Helldiver ~1.3 m away, framed
-- like the normal camera). With Spectating Camera = ActionCam, that teammate is
-- framed with ActionCam using the Spectator Profile. They are NEVER confirmed as
-- you: no identity checks run, the respawn check stays in force, and your own
-- climb-out out of a hellpod ends spectating. Aim alignment (barrel, Precise
-- Aiming) and base FOV learning are off while spectating - they're about YOUR aim.
local function spec_profile()        -- the profile to frame with, or nil (game camera)
  if USER.spectate == 2 then return nil end
  local sp = USER.spec_profile or 1
  local p = (sp == 1) and OPT.profile or (sp == 7 and PROFILE_SHIP or sp)   -- (choice 7 = Ship Camera Default)
  if p == PROFILE_OFF then return nil end
  return p
end
-- (Spectating only ever starts while the respawn check is active, which itself
-- needs recognised animations - so no separate animation requirement: after a
-- Restart while dead, nobody's animations are read until you respawn.)
function H.spec_wanted() return spec_profile() ~= nil end

-- Borrow the Spectator Profile's camera values (your own are put back afterwards).
local function spec_restore()
  if SPEC.ov then
    USER.enabled = SPEC.ov.enabled
    for _, k in ipairs(ALLKEYS) do USER[k] = SPEC.ov[k] end
    SPEC.ov, SPEC.ov_p = nil, nil
  end
end
function H.spec_apply()
  local p = spec_profile()
  if not p then spec_restore(); return end
  local W = (p == OPT.profile) and copy_values(OPT.W)
    or (is_custom(p) and copy_values(OPT.profiles[p - PROFILE_DEFAULT]) or locked_values(p, copy_values))
  -- First Person isn't used while spectating (it meant hiding the teammate's head,
  -- i.e. changing their Helldiver): over the shoulder with ActionCam Default instead.
  if (W.hd2_base or 0) == 2 then
    p, W = PROFILE_DEFAULT, locked_values(PROFILE_DEFAULT, copy_values)
    if not SPEC.fp_logged then
      SPEC.fp_logged = true
      log('spectating: First Person is not used for spectating - over the shoulder (ActionCam Default) instead')
    end
  end
  if p == OPT.profile then spec_restore(); return end
  if SPEC.ov and SPEC.ov_p == p then return end
  spec_restore()
  SPEC.ov = {enabled = USER.enabled}
  for _, k in ipairs(ALLKEYS) do SPEC.ov[k] = USER[k] end
  USER.enabled = true
  for _, k in ipairs(ALLKEYS) do USER[k] = W[k] or 0 end
  SPEC.ov_p = p
  log('spectating: using the ' .. profile_name(p) .. ' profile')
end

local function spec_reset_tracking()
  AN.ok, AN.dead, AN.cur, AN.from, AN.t, AN.pending, AN.sprint = false, false, nil, nil, 1, nil, false
  GUN.unit, GUN.d, GUN.good = nil, nil, 0
  ID.verifying, ID.locked, ID.c, ID.aside = false, nil, {}, false
end
function H.spec_begin(a, d)
  local again = SPEC.active
  local same_one = again and same(SPEC.unit, a.unit)
  SPEC.active, SPEC.unit, SPEC.scan_at = true, a.unit, clock + CFG.SPECTATE_SCAN
  if not same_one then spec_reset_tracking() end
  H.spec_apply()
  if not again then
    log(string.format('spectating: framing the Helldiver the game is following (%.1f m away) - not you; your climb-out ends it', d or 0))
  elseif not same_one then
    log(string.format('spectating: now following another Helldiver (%.1f m away)', d or 0))
  end
end
function H.spec_end(why)
  if not SPEC.active then spec_restore(); return end
  SPEC.active, SPEC.unit = false, nil      -- (SPEC.dead is kept until the respawn check ends)
  spec_restore()
  spec_reset_tracking()
  log('spectating: ended (' .. tostring(why) .. ')')
end
-- The spectated teammate went down: not you - let go and follow whoever is next.
function H.spec_target_down()
  SPEC.dead[#SPEC.dead + 1] = anchor.unit
  log('spectating: the Helldiver you were watching went down - waiting for the game to follow someone else')
  SAFE.crumbs = {}                       -- name the next risky steps in the log
  crumb('restore head size and near plane (spectated Helldiver down)')
  near_restore()                         -- never leave a body with a shrunk head (v10.15 crash)
  anchor = nil
  spec_reset_tracking()
end
-- The game's camera is far wider than normal (everyone down, an overview): not
-- following anyone, so leave it to the game and put any head shrink back.
function H.spec_wide(game_deg)
  if not ST.spec_wide then
    ST.spec_wide = true
    SAFE.crumbs = {}
    log(string.format("spectating: the game's camera is a wide view (%.0f deg) - not following anyone, left to the game", game_deg))
    crumb('restore head size and near plane (wide view)')
    near_restore()
  end
end
-- Every 0.25 s while spectating: has YOUR Helldiver climbed out (spectating ends,
-- normal identity takes over)? Did the respawn check end another way, or was
-- spectating switched off?
function H.spec_step()
  if not SPEC.active then return end
  if not SAFE.gate then H.spec_end('respawn check over'); SPEC.dead = {}; anchor = nil; return end
  if not H.spec_wanted() then H.spec_end('switched to the game camera'); anchor = nil; return end
  H.spec_apply()
end
-- At render time, against the GAME's camera (ActionCam's own camera position is
-- around the teammate): has YOUR Helldiver climbed out? Returns true if so.
function H.spec_sample(world, cx, cy, cz, pose)
  if not SPEC.active or clock < SPEC.scan_at then return false end
  SPEC.scan_at = clock + CFG.SPECTATE_SCAN
  local a, d = H.pick(world, cx, cy, cz, pose, true)
  if a and not a.spectate then
    H.spec_end('you climbed out of a hellpod')
    anchor = a
    ST.last_anchor = a
    on_anchored()
    log(string.format('anchor: your new Helldiver at %.2f m', d or 0))
    H.id_begin()
    return true
  end
  return false
end

-- Everything from one APPLY is handled together on the next frame, reading the
-- final values from the menu (the menu reports changes one at a time).
local function settle_pending(menu)
  local ch = OPT.pending
  OPT.pending = nil
  local W = copy_values(OPT.W)
  local profile = OPT.profile
  local edited = false

  -- 0) Picking a Section and editing its sliders in the same APPLY edits the
  --    section you just picked.
  if type(ch.section) == 'number' and SECTIONS[ch.section] then OPT.section = ch.section end
  -- 1) Edits.
  if ch.sliders then
    for _, k in ipairs(SLIDERS) do W[k] = get_num(menu, k) end
    edited = true
  end
  if ch.mode then W.control = (ch.mode == 2) and 1 or 0; edited = true end
  if ch.extras then
    for id, e in pairs(EXTRA) do
      local ok, v = pcall(menu.get, OPT.prefix .. id)
      if ok and v ~= nil then
        if e[2] == 'choice2' then W[e[1]] = (v == 2) and 1 or 0
        elseif e[2] == 'toggle' then W[e[1]] = (v == true) and 1 or 0
        elseif type(v) == 'number' then W[e[1]] = v end
      end
    end
    edited = true
  end
  if ch.base then W.hd2_base = math.max(0, math.min(BASE_SHIP, (ch.base or 1) - 1)); edited = true end
  if ch.toggles then
    for _, sec in ipairs(SECTIONS) do
      local okt, on = pcall(menu.get, OPT.prefix .. 'on_' .. sec)
      W['sec_' .. sec .. '_on'] = (okt and on == true) and 1 or 0
    end
    edited = true
  end
  if ch.sec_edit then
    local s = SECTIONS[OPT.section]
    for _, f in ipairs({'dist', 'side', 'height', 'fov'}) do W['sec_' .. s .. '_' .. f] = get_num(menu, 'sec_' .. f) end
    edited = true
  end
  if ch.reset == true then
    W = copy_values(nil)
    pcall(menu.set, OPT.prefix .. 'reset', false)
    edited = true
    log('settings: adjustments reset (main and all sections)')
  end

  -- 2) Profile actions.
  if type(ch.save_as) == 'number' and ch.save_as > 1 then
    if not ch.base then
      if OPT.profile == PROFILE_OFF then W.hd2_base = 1
      elseif OPT.profile == PROFILE_DEFAULT then W.hd2_base = 0
      elseif OPT.profile == PROFILE_FP then W.hd2_base = 2
      elseif OPT.profile == PROFILE_SHIP then W.hd2_base = BASE_SHIP end
    end
    local slot = ch.save_as - 1
    OPT.profiles[slot] = copy_values(W)
    profiles_save()
    profile = PROFILE_DEFAULT + slot
    pcall(menu.set, OPT.prefix .. 'profile', profile)
    pcall(menu.set, OPT.prefix .. 'save_as', 1)
    log('settings: saved to ' .. profile_name(profile) .. ' and switched to it')
  elseif ch.profile and ch.profile ~= OPT.profile then
    profile = ch.profile
    W = is_custom(profile) and copy_values(OPT.profiles[profile - PROFILE_DEFAULT]) or locked_values(profile, copy_values)
    log('settings: profile ' .. profile_name(profile))
  elseif edited and is_custom(profile) then
    OPT.profiles[profile - PROFILE_DEFAULT] = copy_values(W)
    profiles_save()
    log('settings: updated ' .. profile_name(profile))
  elseif edited and not is_custom(profile) then
    W = locked_values(profile, copy_values)
    log('settings: ' .. profile_name(profile) .. ' is locked; changes reverted (use a Custom profile)')
  end
  if not is_custom(profile) then W = locked_values(profile, copy_values) end

  OPT.profile = profile
  ui_write(menu, W)
  use(profile, W)
end

local function options_step()
  local menu = rawget(_G, 'ModOptionsMenu')
  if OPT.registered then
    if OPT.pending and menu then settle_pending(menu) end
    return
  end
  if not menu or menu.api ~= 1 then return end
  OPT.registered = true   -- the two addons may load in either order
  profiles_load()
  for _, o in ipairs(OPTIONS) do
    local id = OPT.prefix .. o.key
    o.spec.mod = OPT.mod
    local ok, res, why = pcall(menu.register_option, id, o.spec)
    if not ok or res == false then log('settings: could not register ' .. id .. ': ' .. tostring(why or res)) end
    if o.key == 'aim_precision' then
      local okg, v = pcall(menu.get, id)
      if okg and type(v) == 'number' then USER.aim_precision = math.max(0, math.min(1, v / 100)) end
    end
    if o.key == 'smoothness' then
      local okg, v = pcall(menu.get, id)
      if okg and type(v) == 'number' then SMOOTH.m = math.max(0.5, math.min(3, v / 100)) end
    end
    if o.key == 'spectate' or o.key == 'spec_profile' then
      local okg, v = pcall(menu.get, id)
      if okg and type(v) == 'number' then USER[o.key] = v end
    end
    pcall(menu.on_change, id, function(value)
      if o.key == 'aim_precision' then
        if type(value) == 'number' then USER.aim_precision = math.max(0, math.min(1, value / 100)) end
        log(string.format('settings: Precise Aiming %d%%', math.floor(USER.aim_precision * 100 + 0.5)))
        return
      end
      if o.key == 'smoothness' then   -- global, takes effect at once
        if type(value) == 'number' then SMOOTH.m = math.max(0.5, math.min(3, value / 100)) end
        log(string.format('settings: Camera Smoothness %d%%', math.floor(SMOOTH.m * 100 + 0.5)))
        return
      end
      if o.key == 'spectate' or o.key == 'spec_profile' then   -- global, takes effect at once
        if type(value) == 'number' then USER[o.key] = value end
        log('settings: Spectating Camera ' .. (USER.spectate == 2 and 'Vanilla' or 'ActionCam') .. ', Spectator Profile '
          .. ((USER.spec_profile or 1) == 1 and 'Current Profile' or profile_name(USER.spec_profile)))
        return
      end
      OPT.pending = OPT.pending or {}
      if o.key == 'profile' or o.key == 'save_as' or o.key == 'reset' or o.key == 'section' or o.key == 'mode' or o.key == 'base' then
        OPT.pending[o.key] = value
      elseif EXTRA[o.key] then
        OPT.pending.extras = true
      elseif o.key:sub(1, 3) == 'on_' then
        OPT.pending.toggles = true
      elseif o.key:sub(1, 4) == 'sec_' then
        OPT.pending.sec_edit = true
      else
        OPT.pending.sliders = true
      end
    end)
  end
  -- Start from what was saved: a Custom profile's own file; the defaults load clean.
  local okp, p = pcall(menu.get, OPT.prefix .. 'profile')
  local profile = (okp and type(p) == 'number') and p or PROFILE_DEFAULT
  local oks, sec = pcall(menu.get, OPT.prefix .. 'section')
  if oks and type(sec) == 'number' and SECTIONS[sec] then OPT.section = sec end
  local W = is_custom(profile) and copy_values(OPT.profiles[profile - PROFILE_DEFAULT]) or locked_values(profile, copy_values)
  ui_write(menu, W)
  use(profile, W)
  local on = {}
  for i, s in ipairs(SECTIONS) do if USER['sec_' .. s .. '_on'] == 1 then on[#on + 1] = SECTION_NAMES[i] end end
  log(string.format('settings: Camera Smoothness %d%%, Precise Aiming %d%%', math.floor(SMOOTH.m * 100 + 0.5), math.floor(USER.aim_precision * 100 + 0.5)))
  log(string.format('settings: Mod Options Menu found; profile=%s dist=%+.2f side=%+.2f height=%+.2f aim_dist=%+.2f mode=%s sections on: %s',
    profile_name(profile), USER.dist, USER.side, USER.height, USER.aim_dist,
    (USER.control == 1 and 'Control' or 'Standard') .. (USER.hd2_base == 1 and ', Helldivers 2 base' or (USER.hd2_base == 2 and ', First Person base' or (USER.hd2_base == BASE_SHIP and ', Ship base' or ''))), #on > 0 and table.concat(on, ', ') or 'none'))
end

-- Sections (Control Mode only). A section that is on starts as an exact copy of
-- the standing camera: its sliders are ADDED to your main settings, and the
-- state's own built-in behaviour (closer crouch/prone framing, sprint effects,
-- dive-to-prone) is replaced by standing framing in proportion to its weight.
-- Returns the adjusted main values plus how "standing-based" this moment is.
local SECW = {crouch = 0, prone = 0, sprint = 0, dive = 0, air = 0}
local MIX = {}
local function section_mix(sidx, sprint, diving, jetpack, dt, aim)
  local ctrl = USER.control == 1
  local function ease(key, target, tau)
    local k = 1 - math.exp(-dt / tau)
    SECW[key] = SECW[key] + ((ctrl and target or 0) - SECW[key]) * k
    return SECW[key]
  end
  local wc = ease('crouch', (sidx == 2 and USER.sec_crouch_on == 1) and 1 or 0, sm(CFG.STANCE_BLEND))
  local wp = ease('prone',  (sidx == 1 and USER.sec_prone_on == 1) and 1 or 0, sm(CFG.STANCE_BLEND))
  SECW.sprint = (ctrl and USER.sec_sprint_on == 1) and sprint or 0      -- sprint is already smoothed
  local wd = ease('dive',   (diving and USER.sec_dive_on == 1) and 1 or 0, 0.15)
  local wa = ease('air',    (jetpack and USER.sec_air_on == 1) and 1 or 0, 0.25)   -- Jump Pack section
  -- Aiming (v10.24): follows how far into aiming you are (already smoothed), and takes
  -- priority over Crouching / Prone while you aim (they fade out as it fades in).
  local wA = (ctrl and USER.sec_aim_on == 1) and (aim or 0) or 0
  wc, wp = wc * (1 - wA), wp * (1 - wA)
  local d, s, h, f = USER.dist, USER.side, USER.height, 0   -- FOV: sections only, on top of the game's
  for sec, w in pairs({crouch = wc, prone = wp, sprint = SECW.sprint, dive = wd, air = wa, aim = wA}) do
    if w > 0.0005 then
      d = d + (USER['sec_' .. sec .. '_dist'] or 0) * w
      s = s + (USER['sec_' .. sec .. '_side'] or 0) * w
      h = h + (USER['sec_' .. sec .. '_height'] or 0) * w
      f = f + (USER['sec_' .. sec .. '_fov'] or 0) * w
    end
  end
  MIX.stand_base = math.min(1, wc + wp + wd)                -- use standing framing instead of the stance's own
  -- The Aiming section's sideways / height part: kept even when Precise Aiming lines
  -- the camera up with the game's aim line (it's what you asked for while aiming).
  MIX.aim_side, MIX.aim_height = (USER.sec_aim_side or 0) * wA, (USER.sec_aim_height or 0) * wA
  MIX.no_sprint_fx = (ctrl and USER.sec_sprint_on == 1) and 1 or 0   -- a sprint section replaces the built-in sprint effects
  return d, s, h, f
end
H.section_mix = section_mix

-- Vehicles (experimental, only when that section is switched on): adjust the
-- game's own vehicle camera rather than framing your seated Helldiver.
local VEH = {w = 0}
local function apply_vehicle(cam, unit, cx, cy, cz, fx, fy, fz, rx, ry, rz, ux, uy, uz, game_fov, game_deg, dt)
  VEH.w = math.min(1, VEH.w + dt / 0.4)
  local w = VEH.w
  local back = (USER.sec_vehicle_dist or 0) * w
  local sd, up = (USER.sec_vehicle_side or 0) * w, (USER.sec_vehicle_height or 0) * w
  local nx, ny, nz = cx - fx * back + rx * sd + ux * up, cy - fy * back + ry * sd + uy * up, cz - fz * back + rz * sd + uz * up
  sr.Camera.set_local_position(cam, unit, V(nx, ny, nz))
  pcall(sr.World.update_unit, target.world, unit)
  last_written = {nx, ny, nz}
  local new_deg = math.max(CFG.FOV_OUT_MIN, math.min(CFG.FOV_OUT_MAX, game_deg + (USER.sec_vehicle_fov or 0) * w))
  local new_fov = math.rad(new_deg)
  pcall(sr.Camera.set_vertical_fov, cam, new_fov)
  written_fov, game_fov_base = new_fov, game_fov
  last.out_fov = new_deg
end
H.apply_vehicle = apply_vehicle

-- First Person in vehicles: stay at your (seated) head, looking where the game's
-- vehicle camera looks. Main sliders apply as on foot; in Control Mode with
-- Customise Vehicles on, the Vehicles sliders add on top. The head stays hidden.
local function fp_vehicle(cam, unit, cx, cy, cz, fx, fy, fz, rx, ry, rz, ux, uy, uz, qx, qy, qz, hx, hy, hz, game_fov, game_deg, me)
  local on = (USER.control == 1 and USER.sec_vehicle_on == 1) and 1 or 0
  local d = USER.dist + on * (USER.sec_vehicle_dist or 0)
  local sd = USER.side + on * (USER.sec_vehicle_side or 0)          -- positive = right
  local up = CFG.FP_UP + USER.height + on * (USER.sec_vehicle_height or 0)
  local fwd = CFG.FP_FORWARD - d
  -- Same head-bob handling as on foot: smoothed, but within a few cm of the real head.
  local bx2, by2, bz2 = hx - qx, hy - qy, hz - qz
  local blen = math.sqrt(bx2 * bx2 + by2 * by2 + bz2 * bz2)
  if blen > CFG.FP_BOB_LIMIT then
    local k = CFG.FP_BOB_LIMIT / blen
    bx2, by2, bz2 = bx2 * k, by2 * k, bz2 * k
  end
  local ex, ey, ez = qx + bx2, qy + by2, qz + bz2
  local nx, ny, nz = ex + fx * fwd + rx * sd + ux * up, ey + fy * fwd + ry * sd + uy * up, ez + fz * fwd + rz * sd + uz * up
  sr.Camera.set_local_position(cam, unit, V(nx, ny, nz))
  pcall(sr.World.update_unit, target.world, unit)
  last_written = {nx, ny, nz}
  -- The game's vehicle FOV (it widens with speed) plus your adjustments.
  local new_deg = math.max(CFG.FOV_OUT_MIN, math.min(CFG.FOV_OUT_MAX, game_deg + on * (USER.sec_vehicle_fov or 0)))
  local new_fov = math.rad(new_deg)
  pcall(sr.Camera.set_vertical_fov, cam, new_fov)
  written_fov, game_fov_base = new_fov, game_fov
  last.out_fov = new_deg
  -- Keep your head hidden while seated.
  local hidden = helmet_step(target.world, me, unit, qx, qy, qz)
  near_apply(cam, hidden and CFG.FP_NEAR_CLIP_HIP or CFG.FP_NEAR_CLIP)
  if not VEH.fp_logged then VEH.fp_logged = true; log('first person: staying at your head in vehicles') end
end
H.fp_vehicle = fp_vehicle

-- Tank Gunner Camera (optional): over your shoulder, behind your head in the
-- direction you look - or at your head in First Person - plus the Tank Gunner
-- sliders. The turret camera looks away from you, so this is placed from your
-- head rather than pulled in from the game's camera.
local function tank_gunner(cam, unit, fx, fy, fz, rx, ry, rz, ux, uy, uz, qx, qy, qz, game_fov, game_deg, me)
  local fp = USER.hd2_base == 2
  local back, sd, up
  if fp then
    back = -(CFG.FP_FORWARD - (USER.tg_dist or 0))
    sd = USER.tg_side or 0
    up = CFG.FP_UP + (USER.tg_height or 0)
  else
    back = CFG.TARGET_DISTANCE + USER.dist + (USER.tg_dist or 0)
    sd = CFG.TG_SIDE + (USER.tg_side or 0)
    up = CFG.TG_UP + (USER.tg_height or 0)
  end
  local nx, ny, nz = qx - fx * back + rx * sd + ux * up, qy - fy * back + ry * sd + uy * up, qz - fz * back + rz * sd + uz * up
  sr.Camera.set_local_position(cam, unit, V(nx, ny, nz))
  pcall(sr.World.update_unit, target.world, unit)
  last_written = {nx, ny, nz}
  local new_deg = math.max(CFG.FOV_OUT_MIN, math.min(CFG.FOV_OUT_MAX, game_deg))
  local new_fov = math.rad(new_deg)
  pcall(sr.Camera.set_vertical_fov, cam, new_fov)
  written_fov, game_fov_base = new_fov, game_fov
  last.out_fov = new_deg
  if fp then
    local hidden = helmet_step(target.world, me, unit, qx, qy, qz)
    near_apply(cam, hidden and CFG.FP_NEAR_CLIP_HIP or CFG.FP_NEAR_CLIP)
  else
    near_restore()
  end
  if not VEH.tg_logged then VEH.tg_logged = true; log('tank gunner camera: active') end
end
H.tank_gunner = tank_gunner

---------------------------------------------------------------- Photo Mode (needs Mod Bindings Menu)
-- A free camera: Toggle detaches it where it is; the movement bindings fly it
-- relative to where you look (Up/Down straight up and down); the mouse / right
-- stick looks around as normal. Your Helldiver stays put unless you use WASD.
local PHOTO = {active = false, pos = nil, registered = false, failed_logged = false,
               missing_logged = false, was = {}, input = {},
               locked = false, lock_pose = nil}
-- Key bindings (Mod Bindings Menu). Binding ids are saved by the menu: never rename them.
local PHOTO_BINDS = {
  {id = 'actioncam.photo_toggle',  label = 'Photo Mode: Toggle',               key = 'toggle'},
  {id = 'actioncam.photo_lock',    label = 'Photo Mode: Lock Camera',          key = 'lock'},
  {id = 'actioncam.photo_forward', label = 'Photo Mode: Forward (use Hold)',   key = 'forward'},
  {id = 'actioncam.photo_back',    label = 'Photo Mode: Back (use Hold)',      key = 'back'},
  {id = 'actioncam.photo_left',    label = 'Photo Mode: Left (use Hold)',      key = 'left'},
  {id = 'actioncam.photo_right',   label = 'Photo Mode: Right (use Hold)',     key = 'right'},
  {id = 'actioncam.photo_up',      label = 'Photo Mode: Up (use Hold)',        key = 'up'},
  {id = 'actioncam.photo_down',    label = 'Photo Mode: Down (use Hold)',      key = 'down'},
  {id = 'actioncam.photo_fast',    label = 'Photo Mode: Faster (use Hold)',    key = 'fast'},
  -- Restart: switch ActionCam off and on again (a way to carry on past a bug).
  {id = 'actioncam.restart',       label = 'Restart ActionCam',                key = 'restart'},
}
-- One binding per profile, in the Profile menu's order (index = profile number).
for i, name in ipairs(profile_choices) do
  PHOTO_BINDS[#PHOTO_BINDS + 1] = {id = 'actioncam.profile_' .. i, label = 'Profile: ' .. name, key = 'profile' .. i, profile = i}
end

-- Switch profile from a key: the same as picking it in the menu (the menu shows
-- it and keeps it). Without Mod Options Menu the profile is used directly.
local function switch_profile(p)
  local menu = rawget(_G, 'ModOptionsMenu')
  if OPT.registered and menu then
    OPT.pending = OPT.pending or {}
    OPT.pending.profile = p
    pcall(menu.set, OPT.prefix .. 'profile', p)
  else
    if not OPT.file_loaded then OPT.file_loaded = true; profiles_load() end
    local W = is_custom(p) and copy_values(OPT.profiles[p - PROFILE_DEFAULT]) or locked_values(p, copy_values)
    OPT.profile = p
    use(p, W)
  end
  log('key binding: profile ' .. profile_name(p))
end

PHOTO_REF = PHOTO
local function bindings_step()
  local menu = rawget(_G, 'ModBindingsMenu')
  if not menu or menu.api ~= 1 then
    if not PHOTO.missing_logged and clock > 20 then
      PHOTO.missing_logged = true
      log('key bindings: Mod Bindings Menu not found - Photo Mode, Restart and profile keys are unavailable')
    end
    return
  end
  -- The two addons may load in either order: retry what isn't in yet (every 2 s
  -- once tried). Bindings that did register work meanwhile - the menu's slots are
  -- shared by all mods, so one that doesn't fit mustn't switch off the rest.
  if not PHOTO.registered and clock >= (PHOTO.retry_at or 0) then
    PHOTO.retry_at = clock + 2
    local all, failed = true, {}
    for _, b in ipairs(PHOTO_BINDS) do
      if not b.ok then
        local ok, res, why = pcall(menu.register_binding, b.id, b.label, nil, {category = 'ActionCam'})
        if ok and res ~= false then b.ok = true else all = false; failed[#failed + 1] = '"' .. b.label .. '": ' .. tostring(why or res) end
      end
    end
    if all then
      PHOTO.registered = true
      log('key bindings: registered (set them in Options > Controls, MODS tab)')
    elseif not PHOTO.failed_logged then
      PHOTO.failed_logged = true
      log('key bindings: could not register ' .. #failed .. ' (still trying): ' .. table.concat(failed, '; '))
    end
  end
  local I, was = PHOTO.input, PHOTO.was
  for _, b in ipairs(PHOTO_BINDS) do
    local down = false
    if b.ok then
      local ok, d = pcall(menu.is_down, b.id)
      down = ok and d == true
    end
    I[b.key] = down
  end
  -- Presses (not every frame a key reads as down).
  local function pressed(key) local p = I[key] and not was[key]; was[key] = I[key]; return p end
  if pressed('restart') then H.full_restart('key binding'); return end
  for _, b in ipairs(PHOTO_BINDS) do
    if b.profile and pressed(b.key) then switch_profile(b.profile) end
  end
  if pressed('toggle') then
    if PHOTO.active then
      -- (also when locked: Toggle simply ends Photo Mode)
      PHOTO.active, PHOTO.pos, PHOTO.locked, PHOTO.lock_pose = false, nil, false, nil
      engage = 0                                  -- ease back to the normal camera
      log('photo mode: off')
    elseif target then
      PHOTO.active, PHOTO.pos = true, nil
      log('photo mode: on')
    end
  end
  -- Lock Camera: freeze position, direction and FOV; press again to unlock.
  if pressed('lock') and PHOTO.active then
    PHOTO.locked, PHOTO.lock_pose = not PHOTO.locked, nil
    log('photo mode: camera ' .. (PHOTO.locked and 'locked' or 'unlocked'))
  end
end

-- One frame of Photo Mode: fly the detached camera and place it.
function PHOTO.apply(cam, unit, pose, cx, cy, cz)
  -- Photo Mode skips the normal camera logic, so check for your Helldiver going
  -- down here; the normal death handling then takes over on the next frame.
  if anchor and try(sr.Unit.alive, anchor.unit) then
    local A = anim_classify(anchor.unit, last_dt)
    if A.dead then
      PHOTO.active, PHOTO.pos, PHOTO.locked, PHOTO.lock_pose = false, nil, false, nil
      log('photo mode: off (Helldiver down)')
      return
    end
  end
  if not PHOTO.pos then
    -- Start exactly where the camera was last drawn.
    PHOTO.pos = last_written and {last_written[1], last_written[2], last_written[3]} or {cx, cy, cz}
  end
  near_restore()             -- First Person: show your head again (the camera has left it)
  if PHOTO.locked then
    -- Capture the view once (as plain numbers: engine vectors expire), then hold it.
    if not PHOTO.lock_pose then
      local f0, u0 = M.forward(pose), M.up(pose)
      PHOTO.lock_pose = {f = {V.x(f0), V.y(f0), V.z(f0)}, u = {V.x(u0), V.y(u0), V.z(u0)},
                         fov = try(sr.Camera.vertical_fov, cam)}
    end
    local lp, p = PHOTO.lock_pose, PHOTO.pos
    sr.Camera.set_local_position(cam, unit, V(p[1], p[2], p[3]))
    local Q = rawget(sr, 'Quaternion')
    if Q and Q.look then
      local okq, q = pcall(Q.look, V(lp.f[1], lp.f[2], lp.f[3]), V(lp.u[1], lp.u[2], lp.u[3]))
      if okq and q then pcall(sr.Camera.set_local_rotation, cam, unit, q) end
    end
    if lp.fov then
      local cur = try(sr.Camera.vertical_fov, cam)
      pcall(sr.Camera.set_vertical_fov, cam, lp.fov)
      written_fov, game_fov_base = lp.fov, cur
    end
    pcall(sr.World.update_unit, target.world, unit)
    last_written = {p[1], p[2], p[3]}
    counts.applied = counts.applied + 1
    return
  end
  restore_fov()
  local fx, fy, fz = xyz(M.forward(pose))
  local rx, ry, rz = xyz(M.right(pose))
  local I = PHOTO.input
  local mf = (I.forward and 1 or 0) - (I.back and 1 or 0)
  local mr = (I.right and 1 or 0) - (I.left and 1 or 0)
  local mu = (I.up and 1 or 0) - (I.down and 1 or 0)
  local spd = CFG.PHOTO_SPEED * (I.fast and CFG.PHOTO_FAST or 1) * last_dt
  local p = PHOTO.pos
  p[1] = p[1] + (fx * mf + rx * mr) * spd
  p[2] = p[2] + (fy * mf + ry * mr) * spd
  p[3] = p[3] + (fz * mf + rz * mr + mu) * spd
  -- Keep within range of your Helldiver.
  local hp = anchor and try(sr.Unit.world_position, anchor.unit, anchor.node)
  if hp then
    local dx, dy, dz = p[1] - V.x(hp), p[2] - V.y(hp), p[3] - V.z(hp)
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if d > CFG.PHOTO_MAX_RANGE then
      local k = CFG.PHOTO_MAX_RANGE / d
      p[1], p[2], p[3] = V.x(hp) + dx * k, V.y(hp) + dy * k, V.z(hp) + dz * k
    end
  end
  sr.Camera.set_local_position(cam, unit, V(p[1], p[2], p[3]))
  pcall(sr.World.update_unit, target.world, unit)
  last_written = {p[1], p[2], p[3]}
  counts.applied = counts.applied + 1
end

-- High frame rates (v10.30). At ~115 fps a player's game drew several frames per
-- update, and on many of them its camera hadn't moved, so ActionCam skipped them -
-- FOV included. If the game puts its own FOV back on such a frame, the view jumps
-- between ActionCam's aim zoom and the game's FOV many times a second (reported:
-- "zooming in/out very fast" when aiming crouched / prone). So on every frame where
-- ActionCam's camera is still in place, its FOV is held too.
function H.fov_hold(cam, unit)
  if not (written_fov and game_fov_base and last_written) then return end
  local lp = try(sr.Camera.local_position, cam, unit)
  if not lp or far(V.x(lp), V.y(lp), V.z(lp), last_written[1], last_written[2], last_written[3], 1e-4) then return end
  local cur = try(sr.Camera.vertical_fov, cam)
  if not cur or math.abs(cur - written_fov) < 1e-5 then return end
  -- The game put its own FOV back: keep ActionCam's offset on top of the game's new value.
  local new_fov = cur + (written_fov - game_fov_base)
  game_fov_base, written_fov = cur, new_fov
  pcall(sr.Camera.set_vertical_fov, cam, new_fov)
  counts.fov_held = counts.fov_held + 1
end

-- Flicker watch (v10.30): after every drawn frame, what the camera actually shows.
-- Counts direction reversals of the FOV (> 1 deg) and of the camera's distance to
-- your head (> 0.15 m) - a steady camera has none; flicker has many - and logs a
-- warning (at most every 10 s) when a second holds several. Catches anything that
-- swaps between two camera states from frame to frame, whatever the frame rate.
local FLICK = {fov = nil, fd = 0, pos = nil, pd = 0, t = 0, fn = 0, pn = 0, warn_at = 0}
function H.flicker_watch()
  if not target then return end
  local cur = try(sr.Camera.vertical_fov, target.cam)
  local lp = try(sr.Camera.local_position, target.cam, target.unit)
  if not (cur and lp) then return end
  local deg = math.deg(cur)
  if FLICK.fov then
    local d = deg - FLICK.fov
    if math.abs(d) > 1.0 then
      if FLICK.fd ~= 0 and (d > 0) ~= (FLICK.fd > 0) then FLICK.fn = FLICK.fn + 1; counts.fov_flips = counts.fov_flips + 1 end
      FLICK.fd = d
    end
  end
  FLICK.fov = deg
  local p = {V.x(lp), V.y(lp), V.z(lp)}
  if FLICK.pos then
    local d = math.sqrt((p[1] - FLICK.pos[1])^2 + (p[2] - FLICK.pos[2])^2 + (p[3] - FLICK.pos[3])^2)
    if d > 0.15 then
      local dir = {(p[1] - FLICK.pos[1]) / d, (p[2] - FLICK.pos[2]) / d, (p[3] - FLICK.pos[3]) / d}
      if FLICK.pdir and dir[1] * FLICK.pdir[1] + dir[2] * FLICK.pdir[2] + dir[3] * FLICK.pdir[3] < -0.7 then
        FLICK.pn = FLICK.pn + 1; counts.pos_flips = counts.pos_flips + 1
      end
      FLICK.pdir = dir
    end
  end
  FLICK.pos = p
  if clock - FLICK.t >= 1.0 then
    if (FLICK.fn >= CFG.FLICKER_WARN or FLICK.pn >= CFG.FLICKER_WARN) and clock >= FLICK.warn_at then
      FLICK.warn_at = clock + 10
      log(string.format('WARNING flicker: in the last second the view reversed %d time(s) in FOV and %d time(s) in position (%d frames drawn, %d updates) - please report this log',
        FLICK.fn, FLICK.pn, FLICK.frames or 0, FLICK.updates or 0))
    end
    FLICK.t, FLICK.fn, FLICK.pn, FLICK.frames, FLICK.updates = clock, 0, 0, 0, 0
  end
  FLICK.frames = (FLICK.frames or 0) + 1
end

local function apply()
  if target and applied_frame == frame then
    -- Drawn again without a game update in between (high frame rates).
    counts.rerender = counts.rerender + 1
    H.fov_hold(target.cam, target.unit)
    return
  end
  if not target then return end
  if not USER.enabled and not PHOTO.active then
    -- Profile 'Helldivers 2 Default': leave the camera entirely to the game.
    applied_frame = frame
    restore_fov(); engage = 0; near_restore()
    return
  end
  applied_frame = frame

  if not world_alive(target.world) then drop_all('world gone'); return end
  if not try(sr.Unit.alive, target.unit) then drop_all('camera unit gone'); return end
  if anchor and not try(sr.Unit.alive, anchor.unit) then H.anchor_gone() end

  local cam, unit = target.cam, target.unit
  local lp   = try(sr.Camera.local_position, cam, unit)
  local wp   = try(sr.Camera.world_position, cam)
  local pose = try(sr.Camera.world_pose, cam)
  if not (lp and wp and pose) then return skip('blocked') end
  local cx, cy, cz = xyz(lp)
  local wx, wy, wz = xyz(wp)
  if far(cx, cy, cz, wx, wy, wz, 0.01) then return skip('blocked') end
  if PHOTO.active then return PHOTO.apply(cam, unit, pose, cx, cy, cz) end
  if last_written and not far(cx, cy, cz, last_written[1], last_written[2], last_written[3], 1e-4) then
    -- The game didn't move its camera this update: ActionCam's position is still in place.
    counts.still = counts.still + 1
    H.fov_hold(cam, unit)
    return
  end

  if last_base and far(cx, cy, cz, last_base[1], last_base[2], last_base[3], CFG.CUT_DISTANCE) then
    counts.cut = counts.cut + 1
    -- A camera cut (cinematic, or a vehicle seat's own camera such as the tank
    -- gunner) no longer lets go of your Helldiver: death is detected from the
    -- animation now, and the turret camera looks away from you, so a fresh search
    -- would never find you again from there.
    last_written, engage = nil, 0
  end
  last_base = {cx, cy, cz}

  -- The game's own FOV this frame (if our write is still there, the game didn't set one).
  local cur_fov = try(sr.Camera.vertical_fov, cam)
  if not cur_fov then return skip('blocked') end
  local game_fov = cur_fov
  if written_fov and math.abs(cur_fov - written_fov) < 1e-5 and game_fov_base then
    game_fov = game_fov_base
    counts.fov_persist = counts.fov_persist + 1
  end
  local game_deg = math.deg(game_fov)
  last.fov = game_deg
  if CFG.EXTRACT_RESEARCH then H.extract_cam(cx, cy, cz, pose, game_deg, cam) end
  -- Special (narrow) cameras: judged against YOUR normal FOV once it is known,
  -- so a low FOV setting in the game's options never switches ActionCam off.
  if game_deg < CFG.MIN_FOV_DEG or (base_fov and game_deg < base_fov - CFG.SPECIAL_FOV_GAP) then
    -- (unless you've really lowered your FOV setting a lot: see H.fov_escape)
    if not (game_deg >= CFG.MIN_FOV_DEG and H.fov_escape(cx, cy, cz, pose, game_deg)) then
      return skip('fov_skip')
    end
  end
  -- Which Helldiver is you: sampled against the game's camera, before any skip
  -- below (a wrong pick is usually 'too far' - that is how it got stuck in v10.9).
  H.id_sample(target.world, cx, cy, cz, pose)
  if H.spec_sample(target.world, cx, cy, cz, pose) then return skip('no_anchor') end   -- you climbed out: start fresh next frame
  if SPEC.active and base_fov and game_deg > base_fov + CFG.SPECTATE_WIDE then H.spec_wide(game_deg); return skip('special') end
  ST.spec_wide = nil
  -- The current guess clearly doesn't follow the camera: leave the camera to the game.
  if CFG.ID_STEP_ASIDE and anchor and not ID.locked and ID.aside then
    if H.id_watch_death() then return end
    return skip('unconfirmed')
  end
  -- On the ship with several Helldivers around (v10.29: after an extraction with a full
  -- squad, the first guess framed a teammate for 1.5 s): nobody is framed until your
  -- movement or the camera test confirms which one is you. The game holds its camera
  -- still until you move anyway, so nothing is lost by waiting.
  if anchor and not ID.locked and ID.verifying and ID.many and target.ship then
    if not ID.many_logged then
      ID.many_logged = true
      log('identity: several Helldivers on the ship - the game\'s camera until your movement confirms which one is you')
    end
    return skip('unconfirmed')
  end

  if not anchor then return skip('no_anchor') end
  crumb('read head position')
  local hp = try(sr.Unit.world_position, anchor.unit, anchor.node)
  local rp = try(sr.Unit.world_position, anchor.unit, 1)
  if not (hp and rp) then anchor = nil; return skip('no_anchor') end
  if math.abs(V.z(hp) - V.z(rp)) > 3.0 then return skip('no_anchor') end   -- ragdoll / not a normal pose
  -- Body root moves with you; the head's offset from it (lean, bob, crouch) is
  -- smoothed so the camera follows your movement but not every sway.
  local bx, by, bz = xyz(rp)
  -- Your Helldiver's own movement: jump packs launch you upwards and warp packs
  -- teleport you. Both pull the camera back like a vehicle, so remember them.
  if prev_root and last_dt > 0 then
    local vx, vy, vz = (bx - prev_root[1]) / last_dt, (by - prev_root[2]) / last_dt, (bz - prev_root[3]) / last_dt
    if math.abs(vz) > 1.5 then airborne_t = clock end
    if math.sqrt(vx * vx + vy * vy) > 12 then fast_t = clock end
    last.hspeed = math.sqrt(vx * vx + vy * vy)
    ST.hspeed_s = (ST.hspeed_s or 0) + (last.hspeed - (ST.hspeed_s or 0)) * (1 - math.exp(-last_dt / 0.5))
    last.vx, last.vy = vx, vy
  end
  prev_root = {bx, by, bz}
  local ox, oy, oz = V.x(hp) - bx, V.y(hp) - by, V.z(hp) - bz
  if not smooth_off then
    smooth_off = {ox, oy, oz}
  else
    local k = 1 - math.exp(-last_dt / CFG.BOB_SMOOTHING)
    smooth_off[1] = smooth_off[1] + (ox - smooth_off[1]) * k
    smooth_off[2] = smooth_off[2] + (oy - smooth_off[2]) * k
    smooth_off[3] = smooth_off[3] + (oz - smooth_off[3]) * k
  end
  local hx, hy, hz = bx + smooth_off[1], by + smooth_off[2], bz + smooth_off[3]

  local fx, fy, fz = xyz(M.forward(pose))
  local rx, ry, rz = xyz(M.right(pose))
  local ux, uy, uz = xyz(M.up(pose))
  local dx, dy, dz = hx - cx, hy - cy, hz - cz
  local along = dx * fx + dy * fy + dz * fz
  -- Safety checks use the real head position (the smoothed one lags behind
  -- during fast stance changes like diving prone, which fooled the angle check).
  local rdx, rdy, rdz = V.x(hp) - cx, V.y(hp) - cy, V.z(hp) - cz
  local dist  = math.sqrt(rdx * rdx + rdy * rdy + rdz * rdz)
  local ralong = rdx * fx + rdy * fy + rdz * fz
  last.along, last.dist = along, dist
  if anim_allowed(oz) then
    local rz0 = V.z(rp)
    local vz0 = (ST.prev_rz and last_dt > 0) and (rz0 - ST.prev_rz) / last_dt or 0
    ST.prev_rz = rz0
    H.log_anim(anchor.unit, last_dt, string.format('head_h=%.2f dist=%.2f fov=%.1f aim=%.2f z=%.2f vz=%.2f', oz, dist, math.deg(cur_fov), 1 - (last.hip or 1), rz0, vz0))
  end
  local A = NOANIM
  if anim_allowed(oz) then
    crumb('read animation state')
    A = anim_classify(anchor.unit, last_dt)
  elseif AN.ok and not AN.dead and not SAFE.fresh then
    -- Skipping the read for a moment (e.g. a hard knockback makes your head
    -- height look odd): keep the last known animation state instead of falling
    -- back to camera-based guesses mid-chaos.
    A = AN
  end
  if A.dead and SPEC.active then
    H.spec_target_down()
    return skip('no_anchor')
  end
  if A.dead then
    -- Your Helldiver is down: hand the camera back and forget this body.
    SAFE.dead_unit, SAFE.dead_time, SAFE.dead_pos, SAFE.dead_epoch = anchor.unit, clock, {bx, by}, WORLD.epoch
    remember_body(anchor.unit)
    log(string.format('safety: %d bod%s of yours remembered in this world (never touched)', #SAFE.bodies, #SAFE.bodies == 1 and 'y' or 'ies'))
    if AN.seen then
      -- Until you climb out of a hellpod, the game spectates teammates: none of them is you.
      SAFE.gate = {t = clock, epoch = WORLD.epoch, spawned = {}}
      H.gate_begin(target.world)
      SPEC.dead = {}
      log('respawn check: waiting for your Helldiver to climb out of a hellpod (spectating: '
        .. (H.spec_wanted() and 'ActionCam, never counted as you' or 'game camera') .. ')')
    end
    ID.was = nil
    AN.ok, AN.dead, AN.cur, AN.from, AN.t, AN.pending, AN.sprint = false, false, nil, nil, 1, nil, false
    log('Helldiver down: handing the camera back to the game until you respawn')
    restore_fov()
    drop_all('death')
    return
  end
  -- Weapon emplacements, the ship's map and the hellpod: the game's own camera.
  if A.special then
    if ST.special_logged ~= A.special then ST.special_logged = A.special; log('handing the camera to the game: ' .. A.special) end
    return skip('special')
  end
  ST.special_logged = nil
  -- Climbing out of a hellpod after a respawn (v10.25): your head is still down in
  -- the pod, and for the first 1.5 s animations aren't read (crash safety), so the
  -- camera-only guess pulled the camera onto your head - a "first person" moment
  -- (v10.24 log, 540 s). Leave the camera to the game until you're out, then blend in.
  local climbing = (SAFE.fresh and ID.from_respawn) or (A.ok and (A.l9 == 329 or A.l9 == 330))
  if climbing then
    if not ST.climb_logged then ST.climb_logged = true; log('respawn: leaving the camera to the game while you climb out of the hellpod') end
    return skip('special')
  end
  ST.climb_logged = nil

  -- First Person in a recognised vehicle seat: the safety checks below (camera
  -- far away, head not in front) don't apply - e.g. the tank gunner looks out
  -- along the turret, away from your Helldiver.
  local tg_cam = A.seat == 'tank_gunner' and USER.tg_on == 1
  local fp_seat = (USER.hd2_base == 2 and A.vehicle == true) or tg_cam
  local max_dist = AN.seen and CFG.MAX_DISTANCE_ANIM or CFG.MAX_DISTANCE
  if dist > max_dist and not fp_seat then return skip('too_far') end
  -- Close in (aiming), a dive or stance change can swing your head well off
  -- centre for a moment; only far cameras need the strict angle check.
  -- Close in, only require your head to be in front of the camera (first person
  -- puts the camera at or ahead of the head, which this still rejects).
  local ok_angle
  local cos_max = AN.seen and CFG.COS_MAX_ANIM or CFG.COS_MAX
  if dist < CFG.CLOSE_DISTANCE then ok_angle = ralong > 0.2 else ok_angle = ralong / dist >= cos_max end
  -- Diving (v10.24): a backwards dive lands you beside, under or even at the game's
  -- camera (v10.23 log: 0.10 m while getting up), which failed this check and handed
  -- the camera to the game for ~0.5 s. Your animation says you're diving: skip the
  -- angle check for the dive and DIVE_GRACE after it (the distance check stays).
  -- (v10.28: and in the air - a jump pack flight or a fall, layer 9 = 237/238 - where the
  -- game's camera swings wide: v10.27 log, your head 2.7-3.1 m off its centre, 0.5 s hand-backs.)
  if A.ok and (A.dive or A.jetpack or A.l9 == 237 or A.l9 == 238) then ST.dive_seen = clock end
  local dive_grace = A.ok and not SPEC.active and ST.dive_seen and clock - ST.dive_seen <= CFG.DIVE_GRACE
  if (dist <= 0.05 or not ok_angle) and not fp_seat and not dive_grace then return skip('off_centre') end
  if dist <= 0.05 then return skip('off_centre') end


  -- Vehicles: the game's camera sits much farther back and its FOV widens with
  -- speed. Step aside and stay out until the normal camera has been back a moment.
  -- Sitting in a vehicle: head at seat height and holding still. A dive drops
  -- the head through that range fast and ends prone (lower), so it doesn't count.
  local raw_speed = (ST.prev_raw_h and last_dt > 0) and math.abs(oz - ST.prev_raw_h) / last_dt or 0
  ST.prev_raw_h = oz
  if oz > CFG.VEHICLE_SEATED_MIN and oz < CFG.VEHICLE_SEATED_HEAD and raw_speed < 0.6 then
    ST.seated_time = ST.seated_time + last_dt
  else
    ST.seated_time = 0
  end
  local seated = ST.seated_time >= CFG.VEHICLE_SEATED_TIME
  local in_vehicle
  if A.ok or AN.seen then   -- animations work this session (even if paused for a moment after a respawn)
    -- The seated animation says so directly; no distance, speed or FOV guesses.
    -- Vehicle Seats = Separate: FRV passenger and gunner seats use the on-foot camera.
    local seat_on_foot = USER.veh_separate == 1 and A.seat == 'passenger'
    in_vehicle = (A.vehicle == true and not seat_on_foot)
      -- Backstop for seats not mapped yet: sitting (head at seat height) with the
      -- game camera far back, while layer 14 is not an on-foot value.
      or (not seat_on_foot and A.l14 and A.l14 ~= 36 and A.l14 ~= 3 and oz > 0.3 and oz < 1.3 and along > 6)
  else
    in_vehicle = along > CFG.VEHICLE_DISTANCE
      or (seated and along > CFG.VEHICLE_SEATED_DISTANCE)
      or (base_fov and game_deg > base_fov + CFG.VEHICLE_FOV_MARGIN)
  end
  -- Speed-based jump/warp detection only matters for the fallback guesses above.
  local jump_or_warp = not (A.ok or AN.seen) and ((clock - airborne_t) < 1.0 or (clock - fast_t) < 1.0)
  if in_vehicle and not ST.vehicle_latched and jump_or_warp then
    -- A jump or warp pack, not a vehicle: keep the camera mod running.
    if not ST.paused_logged then log('jump/warp pack movement: not treating this as a vehicle'); ST.paused_logged = true end
    in_vehicle = false
  elseif not jump_or_warp then
    ST.paused_logged = false
  end
  if in_vehicle then
    if not ST.vehicle_latched then log('vehicle camera detected: stepping aside') end
    ST.vehicle_latched, ST.vehicle_clear_time = true, 0
  elseif ST.vehicle_latched then
    ST.vehicle_clear_time = ST.vehicle_clear_time + last_dt
    if ST.vehicle_clear_time >= CFG.VEHICLE_RELEASE_TIME then
      ST.vehicle_latched = false
      log('normal camera back: resuming')
    end
  end
  if ST.vehicle_latched then
    ST.prev_game_deg = game_deg
    if tg_cam then
      counts.vehicle = counts.vehicle + 1
      H.tank_gunner(cam, unit, fx, fy, fz, rx, ry, rz, ux, uy, uz, V.x(hp), V.y(hp), V.z(hp), game_fov, game_deg, anchor.unit)
      return
    end
    if USER.hd2_base == 2 then
      -- First Person: stay in first person in vehicles (adjustable with the Vehicles section).
      counts.vehicle = counts.vehicle + 1
      H.fp_vehicle(cam, unit, cx, cy, cz, fx, fy, fz, rx, ry, rz, ux, uy, uz,
        V.x(hp), V.y(hp), V.z(hp), hx, hy, hz, game_fov, game_deg, anchor.unit)
      return
    end
    near_restore()
    if USER.control == 1 and USER.sec_vehicle_on == 1 then
      counts.vehicle = counts.vehicle + 1
      H.apply_vehicle(cam, unit, cx, cy, cz, fx, fy, fz, rx, ry, rz, ux, uy, uz, game_fov, game_deg, last_dt)
      return
    end
    return skip('vehicle')
  end
  VEH.w = 0

  -- Learn your normal FOV: the lowest value that has held steady for a full
  -- second (blends between cameras pass through odd values; v5 caught one).
  if ST.steady_val and math.abs(game_deg - ST.steady_val) < 0.05 then
    ST.steady_time = ST.steady_time + last_dt
  else
    ST.steady_val, ST.steady_time = game_deg, 0
  end
  -- Only learn it while on foot and doing nothing special: standing, not
  -- sprinting or diving, not at a terminal/map (layer 9), not seated. (Learning
  -- from the galactic map's 30 deg or an emplacement's 72 deg broke FOV before.)
  local normal = not SPEC.active and oz > 1.35 and ((not A.ok) or ((A.l14 == 36 or A.l14 == 3) and (A.l9 or 0) == 0
    and not A.dive and not AN.sprint and not A.vehicle and not A.special))
  -- (Changes under 0.1 deg are the game's own wobble, not a new setting.)
  if normal and ST.steady_time >= 1.0 and (not base_fov or ST.steady_val < base_fov - 0.1) then
    base_fov = ST.steady_val
    log(string.format('base FOV learned: %.2f', base_fov))
  elseif normal and base_fov and ST.steady_time >= 3.0 and ST.steady_val > base_fov + 0.5 and (ST.hspeed_s or 0) < 1.0 then
    -- Recover upwards: a higher value held steadily while on foot and standing
    -- (still or nearly) is your real FOV. Not while running: running animations the
    -- sprint check doesn't know hold the game's sprint FOV steady (v10.18: 92.2 deg).
    base_fov = ST.steady_val
    log(string.format('base FOV corrected upwards: %.2f', base_fov))
  end
  -- 0 = not sprinting, 1 = full sprint (from the game's own sprint FOV widening).
  -- The game ramps its FOV up when you start sprinting and down (slowly) when
  -- you stop. Treat "above base and not falling" as sprinting, then apply our
  -- own, quicker smoothing so the effect starts and ends crisply but softly.
  local above   = base_fov and (game_deg - base_fov) > 0.3
  local falling = ST.prev_game_deg and game_deg < ST.prev_game_deg - 0.005
  ST.prev_game_deg = game_deg
  local sprint_target = (above and not falling) and 1 or 0
  if A.ok then sprint_target = A.sprint and 1 or 0 end
  local ks = 1 - math.exp(-last_dt / sm(CFG.SPRINT_SMOOTHING))
  ST.sprint_s = ST.sprint_s and (ST.sprint_s + (sprint_target - ST.sprint_s) * ks) or sprint_target
  local sprint = ST.sprint_s
  -- Which stance, and how far into aiming the game's camera is (0 hip, 1 aim),
  -- judged against that stance's own hip and aim distances.
  local head_h = smooth_off and smooth_off[3]
  local st, st_name
  if A.ok and A.cur then st, st_name = H.anim_stance() else st, st_name = stance_at(head_h) end
  local aim_raw = clamp01((st.hip - along) / (st.hip - st.aim))
  -- While changing stance (e.g. going prone while aiming) the stance numbers
  -- shift under the game's camera; hold the previous aim state until it settles.
  local head_speed = (ST.prev_head_h and head_h and last_dt > 0) and math.abs(head_h - ST.prev_head_h) / last_dt or 0
  ST.prev_head_h = head_h
  local changing = (A.ok and (AN.t < 1 or A.dive)) or (not A.ok and head_speed > 0.35)
  if changing and ST.aim_hold then aim_raw = ST.aim_hold end
  -- (v10.31) does the game's camera sit steadily at this stance's aim distance? - lets the
  -- camera overrule a "hip" weapon pose (Ballistic Shield and others)
  local along_speed = (ST.prev_along and last_dt > 0) and math.abs(along - ST.prev_along) / last_dt or 99
  ST.prev_along = along
  local fits = along >= st.aim - CFG.AIM_CONFLICT_FIT and along <= st.aim + CFG.AIM_CONFLICT_FIT
               and along_speed < CFG.AIM_CONFLICT_STEADY and not changing
  aim_raw = H.aim_gate(aim_raw, A, ST.aim_hold, last_dt, fits)
  -- During a dive or fast stance change, let the game's own camera lead (it
  -- keeps its distance while you drop); ease the effect back once settled.
  -- Only big fast drops count (a dive, or dropping prone from standing: ~1 m).
  -- Crouching (~0.5 m) is left alone so toggling crouch doesn't bump the camera.
  if raw_speed > 0.8 then
    if not ST.drop_start then ST.drop_start = (ST.prev_drop_h or oz) end
  elseif head_speed < 0.2 then
    ST.drop_start = nil
  end
  ST.prev_drop_h = oz
  local diving = ST.drop_start and (ST.drop_start - oz) > 0.7
  if A.ok then diving = false end   -- with animations, dives are handled by holding the framing (below)
  if diving then
    ST.settle = math.max(0, ST.settle - last_dt / sm(CFG.DIVE_FADE_OUT))
  else
    ST.settle = math.min(1, ST.settle + last_dt / sm(CFG.TRANSITION_EASE))
  end
  ST.aim_hold = aim_raw
  local ka = 1 - math.exp(-last_dt / sm(CFG.AIM_SMOOTHING))
  ST.aim_s = ST.aim_s and (ST.aim_s + (aim_raw - ST.aim_s) * ka) or aim_raw
  local aim = ST.aim_s
  local hip = 1 - aim
  engage = math.min(1, engage + last_dt / sm(CFG.ENGAGE_TIME))
  last.sprint, last.hip, last.engage, last.head_h, last.stance = sprint, hip, engage, head_h, st_name

  -- Where your head sits on the GAME's camera (before our changes).
  local lat_g  = dx * rx + dy * ry + dz * rz
  local vert_g = dx * ux + dy * uy + dz * uz
  last.lat, last.vert = lat_g, vert_g
  -- Which shoulder the game camera is on (the game's shoulder swap flips this).
  -- A real shoulder swap holds; a hectic moment (camera swinging wide, knockback)
  -- only briefly puts your head on the other side. Require clear, sustained evidence.
  local other_side = aim < 0.1 and along > 2.0 and along < 3.6
    and math.abs(lat_g) > 0.3 and (lat_g < 0 and -1 or 1) ~= shoulder_sgn
  if other_side then
    ST.swap_time = (ST.swap_time or 0) + last_dt
    if ST.swap_time >= CFG.SHOULDER_SWAP_TIME then
      shoulder_sgn, ST.swap_time = -shoulder_sgn, 0
      log('shoulder swap detected: ' .. (shoulder_sgn < 0 and 'right' or 'left') .. ' shoulder')
    end
  else
    ST.swap_time = 0
  end
  -- Section overrides (Crouching, Prone, Sprinting, Diving, Jump Pack).
  local sidx = (A.ok and AN.cur) or H.nearest_stance(head_h)
  local e_dist, e_side, e_height, e_fov = H.section_mix(sidx, sprint, A.ok and A.dive, A.ok and AN.jetpack == true, last_dt, aim)
  -- Where a Control Mode section is on, frame exactly like standing: standing
  -- distances, and the same head position beside/above as the standing camera.
  local sb = MIX.stand_base or 0
  local S3 = STANCES[3]
  local scale = (st.hip / S3.hip) + (1 - st.hip / S3.hip) * sb
  local aim_base = math.min(CFG.ADS_DISTANCE, st.aim)
  aim_base = aim_base + (math.min(CFG.ADS_DISTANCE, S3.aim) - aim_base) * sb
  local want_hip = (CFG.TARGET_DISTANCE + e_dist) * scale
  local want_aim = aim_base + e_dist + USER.aim_dist
  local sprint_fx = 1 - (MIX.no_sprint_fx or 0)
  local want = want_hip + (want_aim - want_hip) * aim + CFG.SPRINT_EXTRA_DISTANCE * sprint * sprint_fx
  want = math.max(0.4, want)   -- never inside your Helldiver's head
  -- Pushing the camera back past the game's (wall-safe) camera is only allowed
  -- for the player's own 'further' settings, and to reach the standing aim
  -- distance in a copied Control Mode section; otherwise it only ever pulls in.
  local push_limit = math.max(0, e_dist + USER.aim_dist * aim) + math.max(0, aim_base - math.min(CFG.ADS_DISTANCE, st.aim)) * aim
  -- Room behind the game's camera: 1 = normal distance, 0 = squeezed in (see CFG.SQUEEZE_*).
  -- (On the ship the game's normal camera is the close destroyer one: v10.24 saw it as
  -- permanently squeezed and stopped lowering the camera there.)
  local expected = (target.ship and CFG.SHIP_DIST) or (st.hip + (st.aim - st.hip) * aim)
  local squeeze = math.max(0, expected - along - CFG.SQUEEZE_SLACK)
  local clear_t = math.max(0, 1 - squeeze / CFG.SQUEEZE_RANGE)
  ST.clear = ST.clear or clear_t
  local kc = 1 - math.exp(-last_dt / (clear_t < ST.clear and 0.03 or sm(0.30)))   -- give way at once, come back gently
  ST.clear = ST.clear + (clear_t - ST.clear) * kc
  local clear = ST.clear
  if clear > 0.95 then ST.squeeze_logged = nil end
  push_limit = push_limit * clear
  local pull = math.max(along - want, -push_limit)
  -- Never get much closer to your REAL head than intended. During fast moves
  -- (a dive) the smoothed point lags behind you and would drag the camera onto you.
  if pull > 0 then pull = math.min(pull, math.max(0, ralong - want * 0.85)) end
  -- The ST.settle fade only applies to the hip part, so aiming (incl. prone while
  -- aiming) is unaffected.
  local eased = ST.settle * ST.settle * (3 - 2 * ST.settle)   -- smooth start and finish, no snap
  -- The dive fade goes through a spring so it can't jolt; aiming does not
  -- (the game's own aim shift is instant, and ours must cancel it exactly).
  local fade_target = 1 - (1 - eased) * hip
  if not SPR.f then SPR.f, SPR.vf = fade_target, 0 end
  SPR.f, SPR.vf = spring(SPR.f, SPR.vf, fade_target, CFG.OUTPUT_SPRING / SMOOTH.m, last_dt)
  local fade = math.max(0, math.min(1, SPR.f))
  pull = pull * engage * fade
  -- Pre-apply the game's own aim offset at hip; it fades out exactly as the game applies it.
  -- Aiming while strafing towards your shoulder side: the camera trails behind,
  -- so your Helldiver slides towards the crosshair. Lead the camera further over
  -- the shoulder in proportion to that movement (moving the other way is fine).
  local toward = ((last.vx or 0) * rx + (last.vy or 0) * ry) * -shoulder_sgn   -- m/s towards the shoulder side
  toward = math.min(toward, CFG.AIM_STRAFE_MAX_SPEED)
  local lead_target = math.min(CFG.AIM_STRAFE_MAX, math.max(0, toward) * CFG.AIM_STRAFE_LEAD) * aim
  local kl = 1 - math.exp(-last_dt / CFG.AIM_STRAFE_SMOOTHING)
  last.lead = (last.lead or 0) + (lead_target - (last.lead or 0)) * kl
  -- Standing copy: move the camera so your head sits where it does on the
  -- standing camera (measured per stance), at hip.
  local lat_fix  = (S3.hip_lat - (st.hip_lat or S3.hip_lat)) * sb * hip
  local vert_fix = (S3.hip_vert - (st.hip_vert or S3.hip_vert)) * sb * hip
  -- ...and standing's own hip offsets too (they fade out when aiming anyway).
  local st_side = st.side + (S3.side - st.side) * sb
  local st_lift = st.lift + (S3.lift - st.lift) * sb
  local side = (st_side * hip * fade + CFG.SHOULDER_EXTRA - e_side - lat_fix - last.lead) * shoulder_sgn * engage
  local lift = (st_lift * hip * fade + CFG.HEIGHT_SHIFT + e_height - vert_fix) * engage
  last.e_fov = e_fov
  -- Camera Base: Helldivers 2. ActionCam's own framing is off: the game's camera
  -- is only moved by your adjustments (and sections, in Control Mode).
  local fp = USER.hd2_base == 2
  if fp then
    -- Camera Base: First Person. At your (smoothed) head, slightly forward and at
    -- eye level, looking where the game camera looks. Your adjustments move it:
    -- Distance back/forward, Shoulder Offset sideways, Height up/down.
    local fwd = CFG.FP_FORWARD - e_dist - USER.aim_dist * aim
    local out_side = e_side * -shoulder_sgn                  -- positive = towards your shoulder side
    local up = CFG.FP_UP + e_height
    -- Smooth out head bob, but never let the camera trail your real head by more
    -- than a few centimetres (in a dive the smoothed head lags well behind).
    local qx, qy, qz = V.x(hp), V.y(hp), V.z(hp)
    local bx2, by2, bz2 = hx - qx, hy - qy, hz - qz
    local blen = math.sqrt(bx2 * bx2 + by2 * by2 + bz2 * bz2)
    if blen > CFG.FP_BOB_LIMIT then
      local k = CFG.FP_BOB_LIMIT / blen
      bx2, by2, bz2 = bx2 * k, by2 * k, bz2 * k
    end
    local ex, ey, ez = qx + bx2, qy + by2, qz + bz2
    local tx, ty, tz = ex + fx * fwd + rx * out_side + ux * up, ey + fy * fwd + ry * out_side + uy * up, ez + fz * fwd + rz * out_side + uz * up
    local dx3, dy3, dz3 = tx - cx, ty - cy, tz - cz
    pull = (dx3 * fx + dy3 * fy + dz3 * fz) * engage
    side = (dx3 * rx + dy3 * ry + dz3 * rz) * engage
    lift = (dx3 * ux + dy3 * uy + dz3 * uz) * engage
  elseif USER.hd2_base == BASE_SHIP then
    -- Camera Base: Ship. The destroyer's camera: SHIP_DIST behind, SHIP_SIDE over the
    -- shoulder, SHIP_UP below head height - the same in every state. Your adjustments
    -- (and sections in Control Mode) move it: Distance back, Shoulder Offset, Height.
    -- v10.26: placed from your BODY (the point the game's camera follows), at your
    -- head's height, as an offset from the game's camera - v10.24/25 placed it from
    -- your head and copied every lean (stopping: forward, then back). The head's
    -- offset from your body only follows slowly (SHIP_FOLLOW), so leans are ignored.
    -- (Quickly while your stance changes or you dive - the head moves well ahead of
    -- your body going prone - so the camera never ends up on top of your head.)
    if A.ok and (A.dive or AN.t < 1) then ST.ship_quick_t = clock end
    local quick = ST.ship_quick_t and clock - ST.ship_quick_t < CFG.SHIP_QUICK_HOLD
    local kf = 1 - math.exp(-last_dt / (quick and CFG.SHIP_FOLLOW_QUICK or sm(CFG.SHIP_FOLLOW)))
    if not ST.ship_off then ST.ship_off = {smooth_off[1], smooth_off[2], smooth_off[3]} end
    for i = 1, 3 do ST.ship_off[i] = ST.ship_off[i] + (smooth_off[i] - ST.ship_off[i]) * kf end
    local qx, qy, qz = bx + ST.ship_off[1], by + ST.ship_off[2], bz + ST.ship_off[3]
    local dq1, dq2, dq3 = qx - cx, qy - cy, qz - cz
    local q_along = dq1 * fx + dq2 * fy + dq3 * fz
    local q_lat   = dq1 * rx + dq2 * ry + dq3 * rz
    local q_vert  = dq1 * ux + dq2 * uy + dq3 * uz
    local back = math.max(0.4, CFG.SHIP_DIST + e_dist + USER.aim_dist * aim)
    local lat_t = shoulder_sgn * (CFG.SHIP_SIDE + e_side)      -- where your head should sit on the camera
    local vert_t = CFG.SHIP_UP - e_height
    pull = q_along - back                                      -- (move the game's camera by these)
    if pull < 0 then pull = pull * clear end                   -- squeezed: don't push past the game's camera
    pull = pull * engage
    side = (q_lat - lat_t) * engage
    lift = (q_vert - vert_t) * engage
  elseif USER.hd2_base == 1 or (USER.hd2_base == 0 and target.ship) then
    -- Helldivers 2 base - and, on the destroyer, the ActionCam base too (v10.27): the
    -- ship's own camera (1.12 m) is already closer than ActionCam's framing, so your
    -- adjustments apply on top of it (v10.26: Distance -0.30 did nothing there).
    pull = -(e_dist + USER.aim_dist * aim) * engage          -- positive Distance = further back
    if pull > 0 then pull = math.min(pull, math.max(0, ralong - 0.4)) end
    if pull < 0 then pull = pull * clear end                  -- squeezed: don't push past the game's camera
    side = -e_side * shoulder_sgn * engage                    -- positive = further over the shoulder
    lift = e_height * engage
  end
  -- Precise Aiming: without an exact aim distance, the only way to keep the
  -- reticle exact at every range is to sit on the game's own aim line while
  -- aiming (moving along that line, i.e. the zoom, is still fine).
  -- How fast is the view turning? During (and just after) a fast turn the gun
  -- lags behind, so its barrel line is not a reliable guide: pause readings.
  if last.pf and last_dt > 0 then
    local dot = math.max(-1, math.min(1, fx * last.pf[1] + fy * last.pf[2] + fz * last.pf[3]))
    local rate = math.deg(math.acos(dot)) / last_dt
    if rate > CFG.BARREL_SPIN_LIMIT then ST.spin_until = clock + CFG.BARREL_SPIN_SETTLE end
  end
  last.pf = {fx, fy, fz}
  local spinning = ST.spin_until and clock < ST.spin_until
  -- In first person the camera is far from the game's aim line even at hip, and
  -- the gun points at the reticle when hip-firing too: read the barrel always.
  local gun_needed = (aim > 0.3 or USER.hd2_base == 2) and not SPEC.active   -- (aim alignment is about YOUR aim)
  if CFG.BARREL_AIM and gun_needed and not spinning then
    GUN.wide = (A.ok and (A.special == 'emplacement' or A.vehicle == true)) or not A.ok   -- (no animations: can't tell, keep the old reach)
    H.update_barrel(target.world, cx, cy, cz, fx, fy, fz, V.x(hp), V.y(hp), V.z(hp), last_dt, anchor.unit, target.unit, aim > 0.5)
  elseif not gun_needed then
    GUN.good, GUN.d = 0, nil   -- only trust the barrel while actually aiming
  end
  -- The camera's POSITION while aiming depends only on your settings (the
  -- Precise Aiming slider), never on whether the barrel is currently trusted:
  -- the barrel only fine-tunes the small turn-in angle. So losing or regaining
  -- the barrel can't move the camera.
  local precise = CFG.PRECISE_AIM ~= false
  if precise and not fp and USER.hd2_base ~= BASE_SHIP and not SPEC.active then   -- (Ship holds its framing when aiming)
    local p = aim * USER.aim_precision
    local as, ah = -(MIX.aim_side or 0) * shoulder_sgn * engage, (MIX.aim_height or 0) * engage   -- Aiming section's share
    side = (side - as) * (1 - p) + as
    lift = (lift - ah) * (1 - p) + ah
  end
  -- Squeezed: never lower the camera below the game's (it is keeping out of the ground).
  -- Only when ActionCam's camera is near the game's distance (v10.25): pulled well in
  -- front of it (most of the time at hip) it's nowhere near what the game avoided, and
  -- v10.24 removed the lowering 41% of the time at hip - a quick bob up and down.
  local near_clear = clear + (1 - clear) * math.max(0, math.min(1, pull / CFG.SQUEEZE_NEAR))
  last.clear = near_clear
  if not fp and lift < 0 then
    if near_clear < 0.5 and not ST.squeeze_logged then
      ST.squeeze_logged = true
      ST.squeeze_n = (ST.squeeze_n or 0) + 1
      if clock >= (ST.squeeze_log_at or 0) then   -- (v10.28: at most every 30 s - v10.27 logged 64 in a session)
        ST.squeeze_log_at = clock + 30
        log(string.format('camera squeezed by the game (%.2f m closer than normal) next to ActionCam\'s camera: not lowering it (%d time%s since the last note)',
          expected - along, ST.squeeze_n, ST.squeeze_n == 1 and '' or 's'))
        ST.squeeze_n = 0
      end
    end
    lift = lift * near_clear
  end
  -- Dive (animation mode): from the moment you dive, glide smoothly from the
  -- framing you had to your new stance's framing over DIVE_BLEND.
  if A.ok then
    if A.dive and not DH.active and not fp then
      -- Dive starts: remember the framing you had, and start gliding from it.
      DH.active, DH.t = true, 0
      DH.pull, DH.side, DH.lift = last.pull or pull, last.side or side, last.lift or lift
    end
    if DH.active then
      DH.t = math.min(1, DH.t + last_dt / sm(CFG.DIVE_BLEND))
      local e = DH.t * DH.t * (3 - 2 * DH.t)
      pull = DH.pull + (pull - DH.pull) * e
      side = DH.side + (side - DH.side) * e
      lift = DH.lift + (lift - DH.lift) * e
      -- Never closer than 1 m to your real head during the dive glide.
      if pull > 0 then pull = math.max(0, math.min(pull, ralong - 1.0)) end
      if DH.t >= 1 and not A.dive then DH.active = false end
    end
  end
  last.pull, last.side, last.lift = pull, side, lift
  local nx = cx + fx * pull + rx * side + ux * lift
  local ny = cy + fy * pull + ry * side + uy * lift
  local nz = cz + fz * pull + rz * side + uz * lift
  crumb('move camera')
  sr.Camera.set_local_position(cam, unit, V(nx, ny, nz))
  if fp then
    local hidden = H.helmet_step(target.world, anchor.unit, target.unit, V.x(hp), V.y(hp), V.z(hp))
    local clip = hidden and (CFG.FP_NEAR_CLIP_HIP + (CFG.FP_NEAR_CLIP_AIM - CFG.FP_NEAR_CLIP_HIP) * aim) or CFG.FP_NEAR_CLIP
    near_apply(cam, clip)
  else
    near_restore()
  end
  if CFG.AIM_ALIGN and (math.abs(side) > 0.005 or math.abs(lift) > 0.005) then
    -- Look at the game's aim point from our new position.
    local d = H.aim_distance(target.world, cx, cy, cz, fx, fy, fz, ralong + 0.5)
    local kd = 1 - math.exp(-last_dt / CFG.AIM_DISTANCE_SMOOTHING)
    AIMFIX.dist = AIMFIX.dist and math.exp(math.log(AIMFIX.dist) + (math.log(math.max(0.1, d)) - math.log(AIMFIX.dist)) * kd) or d
    local px, py, pz = cx + fx * AIMFIX.dist, cy + fy * AIMFIX.dist, cz + fz * AIMFIX.dist
    local dx2, dy2, dz2 = px - nx, py - ny, pz - nz
    local len = math.sqrt(dx2 * dx2 + dy2 * dy2 + dz2 * dz2)
    -- Report once whether the camera can actually be turned (so a missing
    -- function never fails silently).
    if len > 0.5 then
      local Q = rawget(sr, 'Quaternion')
      if not (Q and type(Q.look) == 'function') then
        if not AIMFIX.no_quat then AIMFIX.no_quat = true; log('aim alignment: Quaternion.look not available - camera not turned') end
      else
        local lx, ly, lz = dx2 / len, dy2 / len, dz2 / len
      -- Safety net: never turn more than AIM_TURN_CAP_DEG away from your view.
      local cosang = lx * fx + ly * fy + lz * fz
      local capc = math.cos(math.rad(CFG.AIM_TURN_CAP_DEG))
      if cosang < capc then
        local px, py, pz = lx - fx * cosang, ly - fy * cosang, lz - fz * cosang
        local pl = math.sqrt(px * px + py * py + pz * pz)
        if pl > 1e-6 then
          local sn = math.sin(math.rad(CFG.AIM_TURN_CAP_DEG))
          lx, ly, lz = fx * capc + px / pl * sn, fy * capc + py / pl * sn, fz * capc + pz / pl * sn
        else
          lx, ly, lz = fx, fy, fz
        end
        if not AIMFIX.cap_logged then AIMFIX.cap_logged = true; log('aim alignment: turn limited to the safety cap (a bad aim reading was ignored)') end
      end
      local okq, q = pcall(Q.look, V(lx, ly, lz), V(ux, uy, uz))
        local okr, err = false, 'no rotation'
        if okq and q then okr, err = pcall(sr.Camera.set_local_rotation, cam, unit, q) end
        if not AIMFIX.reported then
          AIMFIX.reported = true
          if okr then
            log(string.format('aim alignment: camera turned towards the aim point (%.1f m away, %s)', AIMFIX.dist, tostring(AIMFIX.mode)))
          else
            log('aim alignment: could not turn the camera: ' .. tostring(okq and err or q))
          end
        end
      end
    end
    last.aim_d = AIMFIX.dist
  end
  pcall(sr.World.update_unit, target.world, unit)
  last_written = {nx, ny, nz}

  -- FOV: the game's own FOV at hip. ActionCam and First Person add their aim zoom
  -- and sprint widening, tuned for an 80 deg game FOV and scaled to yours (so
  -- they zoom by the same proportion at 50 or 110). Control Mode sections add
  -- their own FOV slider; a Sprinting section replaces the sprint widening.
  -- Camera Base Helldivers 2: the game's own FOV throughout (sections aside).
  local fov_target = last.e_fov or 0
  if USER.hd2_base ~= 1 and USER.hd2_base ~= BASE_SHIP then   -- (Helldivers 2 and Ship: the game's own FOV)
    local fs = (base_fov or game_deg) / CFG.FOV_REFERENCE
    fov_target = fov_target + CFG.ADS_FOV_CHANGE * fs * aim
      + CFG.SPRINT_FOV_BONUS * fs * sprint * (1 - (MIX.no_sprint_fx or 0))
    -- Undo the game's own +2 sprint ramp (ActionCam drives sprint FOV itself).
    if base_fov and game_deg > base_fov then fov_target = fov_target - math.min(game_deg - base_fov, CFG.SPRINT_UNDO_MAX) end
  end
  local kf = 1 - math.exp(-last_dt / sm(CFG.FOV_SMOOTHING))
  ST.fov_offset_s = ST.fov_offset_s and (ST.fov_offset_s + (fov_target - ST.fov_offset_s) * kf) or fov_target
  local new_deg = math.max(CFG.FOV_OUT_MIN, math.min(CFG.FOV_OUT_MAX, game_deg + ST.fov_offset_s * engage))
  local new_fov = math.rad(new_deg)
  pcall(sr.Camera.set_vertical_fov, cam, new_fov)
  written_fov, game_fov_base = new_fov, game_fov
  last.out_fov = new_deg
  counts.applied = counts.applied + 1
end

---------------------------------------------------------------- render hook
local render_hooked = false
local function hook_render()
  if render_hooked then return end
  local previous = rawget(_G, 'render')
  if type(previous) ~= 'function' then return end
  render_hooked = true
  log('hooked global render()')
  render = function(...)
    counts.render = counts.render + 1
    local ok, err = pcall(apply)
    if not ok then log('apply error: ' .. tostring(err)); drop_all('error') end
    pcall(H.flicker_watch)
    return previous(...)
  end
end

local function n2(x) return x and string.format('%.2f', x) or 'nil' end

---------------------------------------------------------------- restart (key binding)
-- Switch ActionCam off and on again: everything it has learned or is tracking is
-- forgotten, as if it had just loaded. Kept: your settings and profile, the key
-- bindings, and two safety memories - the body of a Helldiver that just died
-- (never re-picked) and the respawn check while you wait to be reinforced.
-- The log gets a marker and a snapshot of the state just before, so whatever
-- went wrong can still be found and fixed.
local function yn(x) return x and 'yes' or 'no' end
function H.full_restart(why)
  pcall(function()
    log(string.format('==== RESTART (%s) ====', why))
    log(string.format('restart snapshot: camera=%s ship=%s anchor=%s identity=%s respawn_check=%s base_fov=%s photo=%s profile=%s base=%s',
      yn(target), yn(target and target.ship), yn(anchor),
      ID.locked and 'locked' or (ID.verifying and 'checking' or 'none'), yn(SAFE.gate), n2(base_fov),
      yn(PHOTO.active), profile_name(OPT.profile), tostring(USER.hd2_base)))
    log(string.format('restart snapshot: anim ok=%s seen=%s stance=%s l14=%s l9=%s special=%s vehicle=%s seat=%s jetpack=%s | vehicle_latched=%s gun=%s aim_mode=%s shoulder=%s',
      yn(AN.ok), yn(AN.seen), tostring(AN.cur), tostring(AN.l14), tostring(AN.l9), tostring(AN.special), yn(AN.vehicle),
      tostring(AN.seat), yn(AN.jetpack), yn(ST.vehicle_latched), yn(GUN.unit), tostring(AIMFIX.mode), shoulder_sgn < 0 and 'right' or 'left'))
    log(string.format('restart snapshot: last game_fov=%s out_fov=%s along=%s dist=%s hip=%s stance=%s head_h=%s lat=%s vert=%s | this second: applied=%d special=%d vehicle=%d fov_skip=%d too_far=%d off_centre=%d no_anchor=%d',
      n2(last.fov), n2(last.out_fov), n2(last.along), n2(last.dist), n2(last.hip), tostring(last.stance), n2(last.head_h), n2(last.lat), n2(last.vert),
      counts.applied, counts.special, counts.vehicle, counts.fov_skip, counts.too_far, counts.off_centre, counts.no_anchor))
  end)
  -- Let go of everything first (restores First Person's head and near plane,
  -- ends Photo Mode, hands the FOV back).
  drop_all('restart')
  SHRINK.failed = false
  -- Learned / tracked state.
  base_fov, smooth_off, prev_root, airborne_t, fast_t, shoulder_sgn = nil, nil, nil, -99, -99, -1
  local keep_logged = AN.logged_l14
  for k in pairs(AN) do AN[k] = nil end
  AN.ok, AN.bad, AN.seen, AN.t, AN.logged_l14, AN.pending_t, AN.sprint, AN.sprint_off_t = false, 0, false, 1, keep_logged, 0, false, 0
  for k in pairs(GUN) do GUN[k] = nil end
  GUN.scan_at, GUN.good, GUN.bad_time = 0, 0, 0
  AIMFIX.mode, AIMFIX.dist = nil, nil
  for k in pairs(ST) do ST[k] = nil end
  ST.steady_time, ST.no_anchor_time, ST.vehicle_latched, ST.vehicle_clear_time = 0, 0, false, 0
  ST.paused_logged, ST.seated_time, ST.settle, ST.far_time = false, 0, 1, 0
  ID.locked, ID.verifying, ID.c, ID.at, ID.prev, ID.started, ID.log_at, ID.L, ID.was = nil, false, {}, 0, nil, 0, 0, nil, nil
  ID.aside, ID.checked, ID.method = false, 0, nil
  SAFE.anchored_at, SAFE.crumbs, SAFE.fresh = 0, nil, nil
  SPR.f, SPR.vf = nil, nil
  DH.active, DH.t = false, 1
  for k in pairs(SECW) do SECW[k] = 0 end
  for k in pairs(MIX) do MIX[k] = nil end
  VEH.w = 0
  for k in pairs(SHIP_SEEN) do SHIP_SEEN[k] = nil end
  for k in pairs(ship_logged) do ship_logged[k] = nil end
  for k in pairs(last) do last[k] = nil end
  anchor_model = nil
  reset_counts()
  -- Back on the game's camera for a moment, then search afresh.
  ST.restart_until = clock + 0.5
  scan_timer = CFG.SEARCH_EVERY
  log('restart: everything forgotten (settings kept); looking for your camera again in 0.5 s')
end

---------------------------------------------------------------- per-frame bookkeeping
local started, failures = false, 0

---------------------------------------------------------------- extraction research (logging only)
-- Logs the Pelican extraction, for a future extraction camera (lock on the ground
-- as it lifts off, then a close-up at its shoulder as it jets away). NOTHING here
-- moves the camera. From boarding (layer 14 = 89) or sitting in the Pelican (90-94)
-- until the mission world unloads, every 0.25 s and at once when layer 14 / 9
-- change: your animation layers, where you are (relative to where you boarded),
-- and the game's camera (position, direction, FOV, distance to you, camera switches).
-- The game's cabin camera rides with the Pelican, so its path shows the take-off.
-- v10.22 also scanned every other unit in the world (position, size, rotation) and
-- crashed the game at boarding: v10.23 only makes reads ActionCam already makes
-- every frame (your own live Helldiver's animation and position, the camera).
local EXTRACT = {active = false, cool = 0, n = 0}
local EXTRACT_L14 = {[89] = true, [90] = true, [91] = true, [92] = true, [93] = true, [94] = true}
CFG.EXTRACT_MAX_TIME, CFG.EXTRACT_MAX_LINES = 180, 900

-- From apply(): the game's camera this frame (before any of ActionCam's skips).
function H.extract_cam(cx, cy, cz, pose, deg, cam)
  if not EXTRACT.active then return end
  local f = M.forward(pose)
  EXTRACT.cam = {cx, cy, cz, V.x(f), V.y(f), V.z(f), deg, clock, cam}
end

local function ex_log(line)
  EXTRACT.n = EXTRACT.n + 1
  if EXTRACT.n <= CFG.EXTRACT_MAX_LINES then log('extract: ' .. line) end
end
local function ex_rel(x, y, z)
  local o = EXTRACT.origin
  return string.format('(%.2f,%.2f,%.2f)', x - o[1], y - o[2], z - o[3])
end
local function ex_heading(fx, fy) return string.format('%.0f', math.deg(math.atan2(fy, fx))) end
local function ex_end(why)
  ex_log(string.format('end (%s) after %.1f s, %d lines', why, clock - EXTRACT.t0, EXTRACT.n))
  EXTRACT.active, EXTRACT.unit, EXTRACT.world, EXTRACT.cam = false, nil, nil, nil
  EXTRACT.cool = clock + 5
end

function H.extract_step(dt)
  if not EXTRACT.active then
    if clock < EXTRACT.cool or not anchor or SPEC.active or not target then return end
    if target.ship or AN.l14_epoch ~= WORLD.epoch then return end   -- (v10.24 started twice on the ship from a stale state)
    if not (AN.ok and AN.l14 and EXTRACT_L14[AN.l14]) then return end
    local u = anchor.unit
    if known_body(u) or not try(sr.Unit.alive, u) then return end
    local rp = try(sr.Unit.world_position, u, 1)
    if not rp then return end
    EXTRACT.active, EXTRACT.unit, EXTRACT.world, EXTRACT.epoch = true, u, target.world, WORLD.epoch
    EXTRACT.origin = {V.x(rp), V.y(rp), V.z(rp)}
    EXTRACT.t0, EXTRACT.n, EXTRACT.tick = clock, 0, 0
    EXTRACT.l14, EXTRACT.l9, EXTRACT.foot_t = nil, nil, 0
    EXTRACT.last_cam = nil
    ex_log(string.format('start: layer 14 = %d, you at world (%.2f,%.2f,%.2f); positions below are relative to this',
      AN.l14, EXTRACT.origin[1], EXTRACT.origin[2], EXTRACT.origin[3]))
    return
  end
  -- Stop before touching anything that may be gone.
  if WORLD.epoch ~= EXTRACT.epoch then return ex_end('new world') end
  if not world_alive(EXTRACT.world) then return ex_end('mission world unloaded') end
  local u = EXTRACT.unit
  if known_body(u) then return ex_end('you went down') end
  if not try(sr.Unit.alive, u) then return ex_end('your Helldiver unit is gone') end
  if clock - EXTRACT.t0 > CFG.EXTRACT_MAX_TIME then return ex_end('time limit') end
  if EXTRACT.n > CFG.EXTRACT_MAX_LINES then return ex_end('line limit') end
  local s = {pcall(sr.Unit.animation_get_state, u)}
  local ok = s[1] and #s >= 32
  if ok and (s[15] == 103 or (s[6] == 0 and s[23] == 0)) then return ex_end('you went down') end
  local l14, l9 = ok and s[15], ok and s[10]
  -- On foot for 5 s (left the Pelican, boarding cancelled, or the ship): stop.
  if l14 == 36 or l14 == 3 then EXTRACT.foot_t = EXTRACT.foot_t + dt else EXTRACT.foot_t = 0 end   -- (3: on the ship)
  if EXTRACT.foot_t > 5 then return ex_end('back on foot') end
  local changed = l14 ~= EXTRACT.l14 or l9 ~= EXTRACT.l9
  EXTRACT.l14, EXTRACT.l9 = l14, l9
  EXTRACT.tick = EXTRACT.tick + dt
  if changed or EXTRACT.tick >= 0.25 then
    EXTRACT.tick = 0
    local rp = try(sr.Unit.world_position, u, 1)
    local node = try(sr.Unit.node, u, CFG.ANCHOR_NODE)
    local hp = node and try(sr.Unit.world_position, u, node)
    local you = '?'
    if rp then you = ex_rel(V.x(rp), V.y(rp), V.z(rp)) end
    if hp and rp then you = you .. string.format(' head_h=%.2f', V.z(hp) - V.z(rp)) end
    local c, camtxt = EXTRACT.cam, 'none yet'
    if c then
      local dist = '?'
      if hp then dist = string.format('%.2f', math.sqrt((c[1] - V.x(hp))^2 + (c[2] - V.y(hp))^2 + (c[3] - V.z(hp))^2)) end
      camtxt = string.format('%s yaw=%s pitch=%.0f fov=%.1f dist=%s age=%.2f', ex_rel(c[1], c[2], c[3]), ex_heading(c[4], c[5]),
        math.deg(math.asin(math.max(-1, math.min(1, c[6])))), c[7], dist, clock - c[8])
      if not rawequal(c[9], EXTRACT.last_cam) then
        camtxt = camtxt .. (EXTRACT.last_cam and ' NEW CAMERA' or '')
        EXTRACT.last_cam = c[9]
      end
    end
    ex_log(string.format('t=%.2f%s l14=%s l9=%s l1=%s l4=%s l22=%s | you %s | cam %s | actioncam=%s',
      clock - EXTRACT.t0, changed and ' CHANGE' or '', tostring(l14), tostring(l9), tostring(ok and s[2]), tostring(ok and s[5]),
      tostring(ok and s[23]), you, camtxt, (anchor and rawequal(anchor.unit, u)) and 'tracking you' or 'not tracking'))
  end
end

local function step(dt)
  if not started then
    started = true
    log(string.format('ActionCam v' .. CFG.VERSION .. ' started: hip=%.2f ads=%.2f side_extra=%.2f height=%.2f hip_fov=game ads_fov=%+d sprint_fov=+%d sprint_dist=%.2f smooth=%.2f',
      CFG.TARGET_DISTANCE, CFG.ADS_DISTANCE, CFG.SHOULDER_EXTRA, CFG.HEIGHT_SHIFT, CFG.ADS_FOV_CHANGE,
      CFG.SPRINT_FOV_BONUS, CFG.SPRINT_EXTRA_DISTANCE, CFG.BOB_SMOOTHING))
  end
  frame = frame + 1
  counts.updates = counts.updates + 1
  FLICK.updates = (FLICK.updates or 0) + 1
  pcall(options_step)
  pcall(bindings_step)
  hook_render()
  dt = tonumber(dt) or 0
  last_dt = dt
  clock = clock + dt
  LOGT.t = clock

  if target and (not world_alive(target.world) or not try(sr.Unit.alive, target.unit)) then
    drop_all('camera gone')
  end
  if anchor and not try(sr.Unit.alive, anchor.unit) then H.anchor_gone() end

  local far_limit = AN.seen and CFG.MAX_DISTANCE_ANIM or CFG.MAX_DISTANCE
  if last.dist and last.dist > far_limit then ST.far_time = ST.far_time + dt else ST.far_time = 0 end
  if target and not anchor then ST.no_anchor_time = ST.no_anchor_time + dt else ST.no_anchor_time = 0 end
  if target and ST.no_anchor_time > 3.0 then drop_all('no Helldiver near this camera for 3 s') end
  if anchor and ST.far_time > 4.0 then
    log('released: anchor far away for 4 s')
    anchor, last.dist, ST.far_time, ID.locked = nil, nil, 0, nil   -- look again from scratch
  end

  scan_timer = scan_timer + dt
  if target and anchor then last.found_at = clock end
  local searching_fast = (clock - (last.found_at or -99)) < CFG.SEARCH_FAST_FOR or not last.found_at
    or SAFE.gate ~= nil   -- (the hellpod climb-out only lasts ~1-1.5 s)
  local every = (target and anchor) and CFG.SCAN_EVERY or (searching_fast and CFG.SEARCH_EVERY or CFG.SEARCH_SLOW)
  if scan_timer >= every then
    scan_timer = 0
    if target and not target_still_valid() then drop_all('camera no longer rendered') end
    local resting = (SAFE.dead_time and (clock - SAFE.dead_time) < 5.0)
      or (ST.restart_until and clock < ST.restart_until)   -- just restarted: the game's camera for a moment
    if not target and not resting then find_camera() end
    if target and not anchor and not resting then find_anchor() end
  end
  -- Just went down: note any Helldiver unit that appears now (a body) - never read.
  if SAFE.gate then
    local ok, err = pcall(H.gate_settle)
    if not ok then log('respawn check: noting bodies failed: ' .. tostring(err)) end
  end
  -- Spectating: watch for your own climb-out (and the respawn check ending).
  if SPEC.active then
    local ok, err = pcall(H.spec_step)
    if not ok then log('spectating: check failed: ' .. tostring(err)) end
  end

  -- Extraction research (logging only).
  if CFG.EXTRACT_RESEARCH then
    local ok, err = pcall(H.extract_step, dt)
    if not ok then log('extract: research failed, switched off: ' .. tostring(err)); CFG.EXTRACT_RESEARCH = false end
  end

  log_timer = log_timer + dt
  if log_timer >= CFG.LOG_EVERY then
    log_timer = 0
    log(string.format('render=%d updates=%d applied=%d rerender=%d still=%d fov_held=%d fov_flips=%d pos_flips=%d unconfirmed=%d vehicle=%d special=%d fov_skip=%d too_far=%d off_centre=%d no_anchor=%d blocked=%d cuts=%d fov_persist=%d | game_fov=%s base_fov=%s out_fov=%s along=%s hip=%s sprint=%s engage=%s stance=%s head_h=%s lat=%s vert=%s shoulder=%s lead=%s aim_d=%s gun_d=%s miss=%s clear=%s | pose=%s pose_vs_cam=%d cam_vs_pose=%d aim_by=%s',
      counts.render, counts.updates, counts.applied, counts.rerender, counts.still, counts.fov_held, counts.fov_flips, counts.pos_flips, counts.unconfirmed, counts.vehicle, counts.special, counts.fov_skip, counts.too_far, counts.off_centre, counts.no_anchor,
      counts.blocked, counts.cut, counts.fov_persist,
      n2(last.fov), n2(base_fov), n2(last.out_fov), n2(last.along), n2(last.hip), n2(last.sprint), n2(last.engage), tostring(last.stance), n2(last.head_h), n2(last.lat), n2(last.vert),
      shoulder_sgn < 0 and 'right' or 'left', n2(last.lead), n2(last.aim_d), n2(GUN.d), n2(GUN.miss), n2(last.clear),
      tostring(AN.l4), H.aim_counts()))
    reset_counts()
  end
end

local previous_update = rawget(_G, 'update')
update = function(dt, ...)
  if failures < 5 then
    local ok, err = pcall(step, dt)
    if not ok then
      failures = failures + 1
      log('error ' .. failures .. ': ' .. tostring(err))
    end
  end
  if previous_update then return previous_update(dt, ...) end
end
