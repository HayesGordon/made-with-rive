-- What the spider wants to do, beyond walking after the pointer. Pure like
-- gait.luau: it steers the gait (a target, being held still and carried)
-- and hands spider.luau decisions and silk to draw.
--
-- * Following, with the pointer still for a while, it plays: grooms,
--   wanders off a little and comes back, or spins a little web round
--   itself.
-- * Following, when a window drag starts under it, it holds on: carried
--   with the pointer, legs locked, until the drag ends.
-- * Sent home, it walks to a corner, spins a web there and rests in it,
--   now and then dropping on a thread to swing. It no longer follows the
--   pointer, only watches it: it flinches at a click nearby and hides while
--   a window is dragged.

local gait = require('gait')
local silk = require('silk')

-- Tuning. Times in seconds, distances in artboard units.
local STILL = 0.5 -- the pointer moving less than this a step is still
local STANDING = 10 -- the spider slower than this is standing
local PLAY_AFTER_MIN, PLAY_AFTER_MAX = 2.5, 4
local PLAY_GAP_MIN, PLAY_GAP_MAX = 1.5, 3
local PLAYS = 2 -- per stretch of a still pointer; then it may doze off
local GROOM = 2.4 -- the Groom timeline's length
local WANDER_MIN, WANDER_MAX = 50, 85
local WANDER_SPEED = 90
local WANDER_PAUSE = 1.2
local WANDER_GIVE_UP = 4
local SPIN = 4 -- spinning a little web
local ORB = 58
local LEAVE_WEB = 20 -- this far from its web, it has left it
local WEB_FADE = 1
local HOME_SPEED = 420
local HOME_SPIN = 3.5
local DROP_EVERY_MIN, DROP_EVERY_MAX = 7, 13
local DROP_DEPTH_MIN, DROP_DEPTH_MAX = 200, 225
local DROP_DOWN = 0.8
-- The thread stretches as it catches the fall: a spring this stiff (radians
-- per second) and damped, so it drops past where it hangs and bounces.
local CATCH = 6
local CATCH_DAMP = 0.5
-- And it bobs a little on it while it hangs.
local BOB = 2.5
local BOB_PERIOD = 1.3
local SWING_TIME = 3
local SWING = 18
local SWING_PERIOD = 1.6
-- Hanging, it turns head down this far below the hub.
local HANG_TURN = 40
local CLIMB = 0.8
local CLIMB_FAST = 0.25
local POKE_REACH = 160 -- a click this close is a fright
local NEAR = 100 -- a pointer moving this close is worth watching
local HIDE_RATE = 10 -- per second
local GRAB_REACH = 120 -- a drag starting this close is one it holds on to

export type Play = 'none' | 'groom' | 'wander' | 'spin'
export type Mode = 'follow' | 'home'
export type HomePhase = 'travel' | 'spin' | 'rest' | 'drop'

export type Input = {
    pointerX: number,
    pointerY: number,
    -- Sent home, with its web's hub and the corner of the screen it is in.
    home: boolean,
    hubX: number,
    hubY: number,
    cornerX: number,
    cornerY: number,
    -- A window is being dragged with the pointer.
    dragging: boolean,
    asleep: boolean,
    -- Nothing else wants the spider: no agent mode that keeps it busy, no
    -- press or scroll.
    free: boolean,
}

export type Will = {
    seed: number,
    mode: Mode,
    lastX: number,
    lastY: number,
    -- Seconds the pointer has been still with the spider standing.
    quiet: number,
    nextPlay: number,
    playsLeft: number,
    play: Play,
    playT: number,
    wanderPhase: string,
    spinFrom: number,
    homePhase: HomePhase,
    homeT: number,
    nextDrop: number,
    dropT: number,
    dropDepth: number,
    -- Climbing back early: seconds into it, or -1, and where from.
    climbT: number,
    climbX: number,
    climbY: number,
    -- Where it hangs now, relative to the hub.
    hangX: number,
    hangY: number,
    wasDragging: boolean,
    -- Out: holding on to a dragged window.
    grabbing: boolean,
    -- Out: let go of it this step.
    released: boolean,
    -- Out: a click nearby gave it a fright.
    flinched: boolean,
    -- Out: something worth staying awake for.
    alert: boolean,
    -- Out: 0 out in the open to 1 pressed into its corner.
    hiding: number,
    -- Out: the Groom timeline should play.
    grooming: boolean,
    -- Out: hanging on a thread from the hub.
    hanging: boolean,
    -- Out: 0 on the web to 1 hanging free, for the legs to dangle.
    dangle: number,
    -- Out: the web it is in or spinning, and webs left behind.
    web: silk.Web?,
    fading: { silk.Web },
}

local M = {}

local function random(w: Will): number
    w.seed = (w.seed * 16807) % 2147483647
    return w.seed / 2147483647
end

local function between(w: Will, lo: number, hi: number): number
    return lo + (hi - lo) * random(w)
end

local function dist(ax: number, ay: number, bx: number, by: number): number
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

local function speed(s: gait.Spider): number
    return math.sqrt(s.vx * s.vx + s.vy * s.vy)
end

local function ease(t: number): number
    t = math.clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

function M.new(seed: number): Will
    local w: Will = {
        seed = math.max(math.floor(seed) % 2147483647, 1),
        mode = 'follow',
        lastX = 0,
        lastY = 0,
        quiet = 0,
        nextPlay = 0,
        playsLeft = PLAYS,
        play = 'none',
        playT = 0,
        wanderPhase = 'out',
        spinFrom = 0,
        homePhase = 'travel',
        homeT = 0,
        nextDrop = 0,
        dropT = 0,
        dropDepth = 0,
        climbT = -1,
        climbX = 0,
        climbY = 0,
        hangX = 0,
        hangY = 0,
        wasDragging = false,
        grabbing = false,
        released = false,
        flinched = false,
        alert = false,
        hiding = 0,
        grooming = false,
        hanging = false,
        dangle = 0,
        web = nil,
        fading = {},
    }
    w.nextPlay = between(w, PLAY_AFTER_MIN, PLAY_AFTER_MAX)
    return w
end

local function leaveWeb(w: Will)
    local web = w.web
    if web then
        table.insert(w.fading, web)
        w.web = nil
    end
end

-- Stops whatever play is going on, without counting it.
local function stopPlay(w: Will, s: gait.Spider)
    w.play = 'none'
    w.grooming = false
    gait.setTarget(s, nil)
end

local function endPlay(w: Will, s: gait.Spider)
    stopPlay(w, s)
    w.playsLeft -= 1
    w.nextPlay = w.quiet + between(w, PLAY_GAP_MIN, PLAY_GAP_MAX)
end

function M.startPlay(w: Will, s: gait.Spider, play: Play)
    stopPlay(w, s)
    w.play = play
    w.playT = 0
    if play == 'groom' then
        w.grooming = true
    elseif play == 'wander' then
        -- Off to one side, away from the pointer.
        local away = math.atan2(s.y - w.lastY, s.x - w.lastX) + between(w, -1.1, 1.1)
        local d = between(w, WANDER_MIN, WANDER_MAX)
        w.wanderPhase = 'out'
        gait.setTarget(s, { x = s.x + math.cos(away) * d, y = s.y + math.sin(away) * d, reach = 0, maxSpeed = WANDER_SPEED, face = nil })
    elseif play == 'spin' then
        leaveWeb(w)
        w.web = silk.orb(s.x, s.y, ORB, w.seed % 1000)
        w.spinFrom = s.heading
        gait.setTarget(s, { x = s.x, y = s.y, reach = 0, maxSpeed = 60, face = s.heading })
    end
end

local function stepPlay(w: Will, s: gait.Spider, dt: number)
    w.playT += dt
    if w.play == 'groom' then
        if w.playT >= GROOM then
            endPlay(w, s)
        end
    elseif w.play == 'wander' then
        local t = s.target
        if w.wanderPhase == 'out' then
            if (t and dist(s.x, s.y, t.x, t.y) < 4) or w.playT > WANDER_GIVE_UP then
                -- A look round where it ended up.
                w.wanderPhase, w.playT = 'pause', 0
                gait.setTarget(s, { x = s.x, y = s.y, reach = 0, maxSpeed = WANDER_SPEED, face = nil })
            end
        elseif w.wanderPhase == 'pause' then
            if w.playT >= WANDER_PAUSE then
                w.wanderPhase, w.playT = 'back', 0
                gait.setTarget(s, nil)
            end
        elseif w.playT > 0.6 and speed(s) < 5 then
            endPlay(w, s)
        end
    elseif w.play == 'spin' then
        -- It turns round once as it lays the spiral.
        local web = w.web
        local p = math.min(w.playT / SPIN, 1)
        if web then
            web.progress = p
        end
        local t = s.target
        if t then
            t.face = w.spinFrom + ease(p) * 2 * math.pi
        end
        if p >= 1 then
            endPlay(w, s)
        end
    end
end

local function stepFollow(w: Will, s: gait.Spider, inp: Input, dt: number, dx: number, dy: number, moved: boolean)
    if w.grabbing then
        if inp.dragging then
            gait.carry(s, dx, dy)
            return
        end
        w.grabbing = false
        s.frozen = false
        w.released = true
    elseif inp.dragging and not w.wasDragging and dist(inp.pointerX, inp.pointerY, s.x, s.y) < GRAB_REACH then
        stopPlay(w, s)
        w.grabbing = true
        s.frozen = true
        return
    end

    local standing = speed(s) < STANDING
    if moved then
        w.quiet = 0
        w.playsLeft = PLAYS
        w.nextPlay = between(w, PLAY_AFTER_MIN, PLAY_AFTER_MAX)
        if w.play ~= 'none' then
            stopPlay(w, s)
        end
    elseif standing or w.play ~= 'none' then
        w.quiet += dt
    end
    local web = w.web
    if web and w.play ~= 'spin' and dist(s.x, s.y, web.x, web.y) > LEAVE_WEB then
        leaveWeb(w)
    end
    if w.play == 'none' then
        if inp.free and not inp.asleep and standing and w.playsLeft > 0 and w.quiet >= w.nextPlay then
            local r = random(w)
            local play: Play = if r < 0.4 then 'groom' elseif r < 0.75 or w.web then 'wander' else 'spin'
            M.startPlay(w, s, play)
        end
    else
        stepPlay(w, s, dt)
    end
end

local function homeTarget(inp: Input, face: number?): gait.Target
    return { x = inp.hubX, y = inp.hubY, reach = 0, maxSpeed = HOME_SPEED, face = face }
end

local function outOfCorner(inp: Input): number
    return math.atan2(inp.hubY - inp.cornerY, inp.hubX - inp.cornerX)
end

local function climb(w: Will)
    if w.homePhase == 'drop' and w.climbT < 0 then
        w.climbT, w.climbX, w.climbY = 0, w.hangX, w.hangY
    end
end

-- Drops from the hub on a thread, swings, and climbs back.
function M.startDrop(w: Will, s: gait.Spider)
    w.homePhase = 'drop'
    w.dropT = 0
    w.dropDepth = between(w, DROP_DEPTH_MIN, DROP_DEPTH_MAX)
    w.climbT = -1
    w.hangX, w.hangY = 0, 0
    s.frozen = true
end

-- How far down the thread it is, t seconds after letting go, as a share of
-- the depth it hangs at.
local function caught(t: number): number
    local wd = CATCH * math.sqrt(1 - CATCH_DAMP * CATCH_DAMP)
    local k = CATCH_DAMP * CATCH
    return 1 - math.exp(-k * t) * (math.cos(wd * t) + k / wd * math.sin(wd * t))
end

local function stepDrop(w: Will, s: gait.Spider, inp: Input, dt: number)
    w.dropT += dt
    local t = w.dropT
    local x, y = 0, 0
    if w.climbT >= 0 then
        w.climbT += dt
        local e = 1 - ease(w.climbT / CLIMB_FAST)
        x, y = w.climbX * e, w.climbY * e
        if w.climbT >= CLIMB_FAST then
            t = math.huge
        end
    elseif t < DROP_DOWN + SWING_TIME then
        -- Caught by the thread, then a pendulum dying down.
        local len = w.dropDepth * caught(t) + BOB * math.sin(2 * math.pi * t / BOB_PERIOD) * ease(t / DROP_DOWN) * (1 - ease((t - DROP_DOWN) / SWING_TIME))
        local a = 0
        if t > DROP_DOWN then
            local u = (t - DROP_DOWN) / SWING_TIME
            a = math.sin(2 * math.pi * (t - DROP_DOWN) / SWING_PERIOD) * SWING * (1 - u * 0.7) * ease(u * 6)
        end
        x = a
        y = math.sqrt(math.max(len * len - a * a, 0))
    else
        local e = 1 - ease((t - DROP_DOWN - SWING_TIME) / CLIMB)
        x, y = 0, w.dropDepth * e
    end
    if t >= DROP_DOWN + SWING_TIME + CLIMB then
        x, y = 0, 0
    end
    gait.carry(s, inp.hubX + x - s.x, inp.hubY + y - s.y)
    -- It hangs head down from its spinneret, so it faces along the thread,
    -- away from the hub; near the hub it turns back to how it rests.
    local rest = outOfCorner(inp)
    local d = math.sqrt(x * x + y * y)
    local away = if d > 0.001 then math.atan2(y, x) else rest
    local turn = math.atan2(math.sin(away - rest), math.cos(away - rest))
    w.dangle = ease(d / HANG_TURN)
    gait.turn(s, rest + turn * w.dangle)
    w.hangX, w.hangY = x, y
    if t >= DROP_DOWN + SWING_TIME + CLIMB then
        w.homePhase = 'rest'
        w.homeT = 0
        w.nextDrop = between(w, DROP_EVERY_MIN, DROP_EVERY_MAX)
        s.frozen = false
        gait.setTarget(s, homeTarget(inp, outOfCorner(inp)))
    end
end

local function stepHome(w: Will, s: gait.Spider, inp: Input, dt: number, moved: boolean)
    local hide = if inp.dragging then 1 else 0
    w.hiding += (hide - w.hiding) * (1 - math.exp(-HIDE_RATE * dt))
    if moved and dist(inp.pointerX, inp.pointerY, s.x, s.y) < NEAR then
        w.alert = true
    end
    if inp.dragging or w.alert then
        climb(w)
    end
    w.homeT += dt
    if w.homePhase == 'travel' then
        gait.setTarget(s, homeTarget(inp, outOfCorner(inp)))
        if dist(s.x, s.y, inp.hubX, inp.hubY) < 4 and speed(s) < STANDING then
            w.homePhase, w.homeT = 'spin', 0
            w.web = silk.corner(inp.hubX, inp.hubY, inp.cornerX, inp.cornerY, w.seed % 1000)
            w.spinFrom = s.heading
        end
    elseif w.homePhase == 'spin' then
        local p = math.min(w.homeT / HOME_SPIN, 1)
        local web = w.web
        if web then
            web.progress = p
        end
        gait.setTarget(s, homeTarget(inp, w.spinFrom + ease(p) * 2 * math.pi))
        if p >= 1 then
            w.homePhase, w.homeT = 'rest', 0
            w.nextDrop = between(w, DROP_EVERY_MIN, DROP_EVERY_MAX)
        end
    elseif w.homePhase == 'rest' then
        gait.setTarget(s, homeTarget(inp, outOfCorner(inp)))
        if inp.free and not inp.asleep and w.hiding < 0.1 and w.homeT >= w.nextDrop then
            M.startDrop(w, s)
        end
    elseif w.homePhase == 'drop' then
        stepDrop(w, s, inp, dt)
    end
    w.hanging = w.homePhase == 'drop'
    -- Its weight on the thread drags the hub after it; let go, the web
    -- springs back and wobbles.
    local web = w.web
    if web then
        local d = math.sqrt(w.hangX * w.hangX + w.hangY * w.hangY)
        local px, py = 0, 0
        if w.hanging and d > 0.001 then
            local k = ease(d / HANG_TURN) / d
            px, py = w.hangX * k, w.hangY * k
        end
        silk.pull(web, px, py, dt)
    end
end

-- A click at (x, y). Close by, while home, it gives the spider a fright.
function M.poke(w: Will, s: gait.Spider, x: number, y: number)
    w.flinched = w.mode == 'home' and dist(x, y, s.x, s.y) < POKE_REACH
end

function M.step(w: Will, s: gait.Spider, inp: Input, dt: number)
    w.released = false
    w.alert = w.flinched
    w.flinched = false
    local dx, dy = inp.pointerX - w.lastX, inp.pointerY - w.lastY
    local moved = math.sqrt(dx * dx + dy * dy) > STILL
    w.lastX, w.lastY = inp.pointerX, inp.pointerY

    for i = #w.fading, 1, -1 do
        local web = w.fading[i]
        web.opacity -= dt / WEB_FADE
        if web.opacity <= 0 then
            table.remove(w.fading, i)
        end
    end

    if inp.home and w.mode == 'follow' then
        stopPlay(w, s)
        leaveWeb(w)
        w.grabbing = false
        s.frozen = false
        w.mode = 'home'
        w.homePhase, w.homeT = 'travel', 0
    elseif not inp.home and w.mode == 'home' then
        s.frozen = false
        w.hanging = false
        w.dangle = 0
        w.mode = 'follow'
        w.quiet = 0
        gait.setTarget(s, nil)
    end

    if w.mode == 'home' then
        stepHome(w, s, inp, dt, moved)
    else
        w.hiding += (0 - w.hiding) * (1 - math.exp(-HIDE_RATE * dt))
        stepFollow(w, s, inp, dt, dx, dy, moved)
    end
    w.wasDragging = inp.dragging
end

return M
