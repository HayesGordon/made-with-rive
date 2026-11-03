-- The spider's motion, in artboard space. No view model and no scene graph:
-- spider.luau feeds it the pointer and writes out what it computes, so the
-- whole simulation can be stepped in a test.

local rig = require('rig')

-- Tuning. Distances in artboard units, times in seconds.
local FOLLOW = 7 -- how hard the body chases its target, per second
local MAX_SPEED = 1200
local ACCEL = 14 -- velocity smoothing, per second
local TURN = 11 -- heading smoothing, per second
-- Body travel between two group swings. It grows with speed, so a running
-- spider takes longer strides rather than only faster ones.
local STRIDE_MIN, STRIDE_MAX = 18, 34
local STRIDE_PER_SPEED = 0.025
-- How far out the feet are, for counting a turn on the spot as travel.
local TURN_RADIUS = 45
local STEP_MIN, STEP_MAX = 0.045, 0.14
local SETTLE = 4 -- at rest, feet further than this from home tidy up
local LIFT = 7 -- how high a stepping foot rises, drawn as an upward offset
-- Landing spots stay within this fraction of a leg's full length.
local REACH_COMFORT = 0.9
-- A planted foot this far past a leg's length steps out of turn.
local OVERSTRETCH = 1.1
local PRESS_REACH = 0.09
local PRESS_HOLD = 0.14
local PRESS_LIFT = 12
-- Scrolling: both front feet on the page under the pointer, side by side
-- like two fingers on a trackpad.
local SCROLL_STROKE = 14 -- half the length the feet can drag before re-placing
local SCROLL_SPREAD = 7 -- half the gap between the two feet
-- How far the feet move per unit the content moves. A trackpad moves the
-- page much further than the fingers, so a slow scroll is a slow drag.
local SCROLL_FOLLOW = 0.15
local SCROLL_RETURN = 0.09 -- seconds to lift back and re-place mid-gesture
local SCROLL_LIFT = 6
-- Content speed, units per second, at which letting go is a flick rather
-- than lifting off.
local FLICK_SPEED = 900
local FLICK_TIME = 0.07 -- seconds for a flick's follow-through
local FLICK_REACH = 10 -- how much further along a flick carries the feet
-- No scroll for this long counts as the fingers lifting; a mouse wheel never
-- says so itself.
local SCROLL_IDLE = 0.25
local SCROLL_BLEND = 18 -- how fast the legs take over and let go, per second
local SCROLL_LEAN = 6 -- how far the body sits back over the back legs

export type Leg = {
    rig: rig.LegRig,
    -- Planted position, or where it is now in a step.
    x: number,
    y: number,
    -- Where the current step started.
    fromX: number,
    fromY: number,
    -- 0..1 through a step, or -1 while planted.
    t: number,
    duration: number,
    -- Where the foot is drawn this frame, lift included.
    drawX: number,
    drawY: number,
}

export type Press = {
    leg: number,
    x: number,
    y: number,
    time: number,
}

-- Where the scroll gesture is: feet dragging on the page, lifting back to
-- re-place mid-gesture, following through a flick, or letting go.
export type ScrollState = 'off' | 'drag' | 'replace' | 'flick' | 'release'

export type Scroll = {
    state: ScrollState,
    -- Seconds into the current state.
    t: number,
    -- Content travel since the last frame.
    dx: number,
    dy: number,
    -- The way the feet drag, a unit vector.
    dirX: number,
    dirY: number,
    -- Where the feet are along it, -SCROLL_STROKE..SCROLL_STROKE and beyond
    -- in a flick, and where the current state started them.
    offset: number,
    from: number,
    -- How far the feet are lifted off the page.
    lift: number,
    -- Content speed, smoothed, units per second.
    speed: number,
    -- Seconds since the last scroll.
    idle: number,
    -- The fingers lifted.
    ended: boolean,
}

-- Somewhere to go other than the pointer: stand `reach` short of it, no
-- faster than `maxSpeed`, and once there turn to `face` (radians), if given.
export type Target = {
    x: number,
    y: number,
    reach: number,
    maxSpeed: number,
    face: number?,
}

export type Spider = {
    x: number,
    y: number,
    vx: number,
    vy: number,
    heading: number,
    turnRate: number,
    pointerX: number,
    pointerY: number,
    -- Where it walks to instead of the pointer, or nil to follow the pointer.
    target: Target?,
    -- Held still by something else: it neither walks nor steps, and only
    -- moves when carried.
    frozen: boolean,
    legs: { Leg },
    press: Press?,
    -- Travel since the last group swing, and which group that was.
    travel: number,
    lastGroup: number,
    scroll: Scroll,
    -- How far the front legs belong to scrolling, 0..1.
    scrollLevel: number,
    -- Where the body is drawn relative to where it stands, when it sits
    -- back to scroll.
    leanX: number,
    leanY: number,
    -- Out: a pressing foot touched down this step, and where.
    touched: boolean,
    touchX: number,
    touchY: number,
}

local M = {}

local function wrapAngle(a: number): number
    while a > math.pi do
        a -= 2 * math.pi
    end
    while a < -math.pi do
        a += 2 * math.pi
    end
    return a
end

local function smooth(rate: number, dt: number): number
    return 1 - math.exp(-rate * dt)
end

local function dist(ax: number, ay: number, bx: number, by: number): number
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

local function speed(s: Spider): number
    return math.sqrt(s.vx * s.vx + s.vy * s.vy)
end

local function stride(s: Spider): number
    return math.clamp(STRIDE_MIN + speed(s) * STRIDE_PER_SPEED, STRIDE_MIN, STRIDE_MAX)
end

-- A point in spider space, placed in the artboard.
local function toWorld(s: Spider, lx: number, ly: number): (number, number)
    local c, n = math.cos(s.heading), math.sin(s.heading)
    return s.x + lx * c - ly * n, s.y + lx * n + ly * c
end

local function hipWorld(s: Spider, leg: Leg): (number, number)
    return toWorld(s, leg.rig.hipX, leg.rig.hipY)
end

-- Where a step should land now. A foot stays planted for two strides of
-- travel, so it lands a stride ahead of its rest spot and is a stride behind
-- it by the time its group swings again. Never further from the hip than
-- the leg comfortably reaches.
local function idealFoot(s: Spider, leg: Leg): (number, number)
    local x, y = toWorld(s, leg.rig.restX, leg.rig.restY)
    local v = speed(s)
    if v > 1 then
        local lead = stride(s) * math.min(v / 60, 1) / v
        x += s.vx * lead
        y += s.vy * lead
    end
    local hx, hy = hipWorld(s, leg)
    local d = dist(x, y, hx, hy)
    local most = leg.rig.reach * REACH_COMFORT
    if d > most then
        x = hx + (x - hx) * most / d
        y = hy + (y - hy) * most / d
    end
    return x, y
end

function M.new(x: number, y: number, heading: number): Spider
    local s: Spider = {
        x = x,
        y = y,
        vx = 0,
        vy = 0,
        heading = heading,
        turnRate = 0,
        pointerX = x + math.cos(heading) * rig.headReach,
        pointerY = y + math.sin(heading) * rig.headReach,
        target = nil,
        frozen = false,
        legs = {},
        press = nil,
        travel = 0,
        lastGroup = 1,
        scroll = {
            state = 'off',
            t = 0,
            dx = 0,
            dy = 0,
            dirX = 0,
            dirY = -1,
            offset = 0,
            from = 0,
            lift = 0,
            speed = 0,
            idle = math.huge,
            ended = false,
        },
        scrollLevel = 0,
        leanX = 0,
        leanY = 0,
        touched = false,
        touchX = 0,
        touchY = 0,
    }
    for _, r in rig.legs do
        local leg: Leg = {
            rig = r,
            x = 0,
            y = 0,
            fromX = 0,
            fromY = 0,
            t = -1,
            duration = STEP_MAX,
            drawX = 0,
            drawY = 0,
        }
        leg.x, leg.y = idealFoot(s, leg)
        leg.drawX, leg.drawY = leg.x, leg.y
        table.insert(s.legs, leg)
    end
    return s
end

function M.setPointer(s: Spider, x: number, y: number)
    s.pointerX = x
    s.pointerY = y
end

function M.setTarget(s: Spider, target: Target?)
    s.target = target
end

-- Moves the whole spider, feet and all, as one piece: something it holds on
-- to is moving it.
function M.carry(s: Spider, dx: number, dy: number)
    s.x += dx
    s.y += dy
    for _, leg in s.legs do
        leg.x += dx
        leg.y += dy
        leg.fromX += dx
        leg.fromY += dy
        leg.drawX += dx
        leg.drawY += dy
    end
    if s.press then
        s.press.x += dx
        s.press.y += dy
    end
end

-- Turns the whole spider about its body to face `heading`, feet and all:
-- held still, it is swung round rather than walking round.
function M.turn(s: Spider, heading: number)
    local da = heading - s.heading
    local c, n = math.cos(da), math.sin(da)
    local function about(x: number, y: number): (number, number)
        local dx, dy = x - s.x, y - s.y
        return s.x + dx * c - dy * n, s.y + dx * n + dy * c
    end
    s.heading = heading
    for _, leg in s.legs do
        leg.x, leg.y = about(leg.x, leg.y)
        leg.fromX, leg.fromY = about(leg.fromX, leg.fromY)
        leg.drawX, leg.drawY = about(leg.drawX, leg.drawY)
    end
    if s.press then
        s.press.x, s.press.y = about(s.press.x, s.press.y)
    end
end

-- The front leg on that side: -1 left, 1 right.
function M.frontLeg(s: Spider, side: number): number
    for i, leg in s.legs do
        if leg.rig.side == side and string.sub(leg.rig.name, 2) == '1' then
            return i
        end
    end
    return 1
end

-- Presses the pointer's current spot with the front leg on that side.
function M.press(s: Spider, side: number)
    local i = M.frontLeg(s, side)
    local leg = s.legs[i]
    -- The press starts from wherever the foot is drawn now, mid-step or not.
    leg.fromX, leg.fromY = leg.drawX, leg.drawY
    leg.t = -1
    s.press = { leg = i, x = s.pointerX, y = s.pointerY, time = 0 }
    -- A small lunge toward the spot.
    local d = math.max(dist(s.pointerX, s.pointerY, s.x, s.y), 1)
    s.vx += (s.pointerX - s.x) / d * 140
    s.vy += (s.pointerY - s.y) / d * 140
end

local function moveBody(s: Spider, dt: number)
    local t = s.target
    local tx, ty = if t then t.x else s.pointerX, if t then t.y else s.pointerY
    local reach = if t then t.reach else rig.headReach
    local top = if t then t.maxSpeed else MAX_SPEED
    local dx, dy = tx - s.x, ty - s.y
    local d = math.sqrt(dx * dx + dy * dy)

    -- Stand so the pointer sits just in front of the face, where the front
    -- legs can reach it.
    local wantVx, wantVy = 0, 0
    if d > 0.001 then
        local err = d - reach
        -- Backing off is slower than chasing, and a small dead zone keeps
        -- the spider from shuffling while the pointer is still.
        if math.abs(err) < 3 then
            err = 0
        elseif err < 0 then
            err *= 0.5
        end
        local v = math.clamp(err * FOLLOW, -top * 0.3, top)
        wantVx, wantVy = dx / d * v, dy / d * v
    end
    local k = smooth(ACCEL, dt)
    s.vx += (wantVx - s.vx) * k
    s.vy += (wantVy - s.vy) * k
    s.x += s.vx * dt
    s.y += s.vy * dt

    -- Face where it is going, unless it is right on top of it; there, the
    -- way the target says, if it does.
    local before = s.heading
    local want: number? = nil
    if d > 12 then
        want = math.atan2(dy, dx)
    elseif t and t.face then
        want = t.face
    end
    if want then
        s.heading = wrapAngle(s.heading + wrapAngle(want - s.heading) * smooth(TURN, dt))
    end
    s.turnRate = wrapAngle(s.heading - before) / dt
end

local function startStep(leg: Leg, duration: number)
    leg.fromX, leg.fromY = leg.x, leg.y
    leg.t = 0
    leg.duration = duration
end

local function swing(s: Spider, group: number, duration: number, held: { boolean })
    for i, leg in s.legs do
        if leg.rig.group == group and not held[i] and leg.t < 0 then
            startStep(leg, duration)
        end
    end
    s.lastGroup = group
    s.travel = 0
end

-- The legs the gait leaves alone this frame: one pressing, the front pair
-- scrolling.
local function heldLegs(s: Spider): { boolean }
    local held = table.create(#s.legs, false)
    if s.press then
        held[s.press.leg] = true
    end
    if s.scrollLevel > 0 then
        held[M.frontLeg(s, -1)] = true
        held[M.frontLeg(s, 1)] = true
    end
    return held
end

local function stepLegs(s: Spider, dt: number)
    local v = speed(s)
    local held = heldLegs(s)
    local strideNow = stride(s)
    -- Land before the other group is due to lift.
    local duration = if v < 1 then STEP_MAX else math.clamp(0.9 * strideNow / v, STEP_MIN, STEP_MAX)

    -- Whether the group that swung last is still in the air. A foot of the
    -- other group stepping out of turn does not hold the clock up.
    local airborne = false
    for i, leg in s.legs do
        if not held[i] and leg.t >= 0 then
            leg.t = math.min(leg.t + dt / leg.duration, 1)
            if leg.t >= 1 then
                leg.t = -1
            elseif leg.rig.group == s.lastGroup then
                airborne = true
            end
        end
    end

    -- The gait clock: every stride of travel, the other group swings, once
    -- the group in the air has landed.
    s.travel += (v + math.abs(s.turnRate) * TURN_RADIUS) * dt
    -- A planted foot that will be straining at its hip by the time another
    -- swing could land also makes it time for its group. That matters most
    -- when setting off with no lead in the feet.
    local strained = { false, false }
    for i, leg in s.legs do
        if not held[i] and leg.t < 0 then
            local hx, hy = hipWorld(s, leg)
            hx += s.vx * duration
            hy += s.vy * duration
            if dist(leg.x, leg.y, hx, hy) > leg.rig.reach * REACH_COMFORT then
                strained[leg.rig.group + 1] = true
            end
        end
    end
    local nextGroup = 1 - s.lastGroup
    if airborne then
        -- wait
    elseif s.travel >= strideNow or strained[nextGroup + 1] then
        swing(s, nextGroup, duration, held)
    elseif strained[s.lastGroup + 1] then
        swing(s, s.lastGroup, duration, held)
    elseif v < 20 and math.abs(s.turnRate) < 0.3 then
        -- Standing still: a group with a foot out of place tidies up.
        for _, g in { 1 - s.lastGroup, s.lastGroup } do
            local untidy = false
            for i, leg in s.legs do
                if leg.rig.group == g and not held[i] then
                    local ix, iy = idealFoot(s, leg)
                    if dist(leg.x, leg.y, ix, iy) > SETTLE then
                        untidy = true
                    end
                end
            end
            if untidy then
                swing(s, g, STEP_MAX, held)
                break
            end
        end
    end

    for i, leg in s.legs do
        if held[i] then
            continue
        end
        local hx, hy = hipWorld(s, leg)
        if leg.t < 0 and dist(leg.x, leg.y, hx, hy) > leg.rig.reach * OVERSTRETCH then
            -- Left behind: only when the body outruns the gait.
            startStep(leg, STEP_MIN)
        end
        if leg.t >= 0 then
            -- The landing spot keeps tracking the body, so a step never
            -- lands behind a spider that sped up mid-stride.
            local ix, iy = idealFoot(s, leg)
            local e = leg.t * leg.t * (3 - 2 * leg.t)
            leg.x = leg.fromX + (ix - leg.fromX) * e
            leg.y = leg.fromY + (iy - leg.fromY) * e
            leg.drawX = leg.x
            leg.drawY = leg.y - math.sin(math.pi * leg.t) * LIFT
        else
            leg.drawX, leg.drawY = leg.x, leg.y
        end
    end
end

local function stepPress(s: Spider, dt: number)
    local p = s.press
    if p == nil then
        return
    end
    local leg = s.legs[p.leg]
    p.time += dt
    if p.time < PRESS_REACH then
        local t = p.time / PRESS_REACH
        local e = 1 - (1 - t) * (1 - t)
        leg.drawX = leg.fromX + (p.x - leg.fromX) * e
        leg.drawY = leg.fromY + (p.y - leg.fromY) * e - math.sin(math.pi * t) * PRESS_LIFT
    elseif p.time < PRESS_REACH + PRESS_HOLD then
        if p.time - dt < PRESS_REACH then
            s.touched, s.touchX, s.touchY = true, p.x, p.y
        end
        leg.drawX, leg.drawY = p.x, p.y
    else
        -- Done: step home from the pressed spot like any other step.
        s.press = nil
        leg.x, leg.y = p.x, p.y
        startStep(leg, 0.12)
    end
end

-- Content travel from a scroll, as a scroll event gives it: it follows the
-- content, so -y reveals what is below. Call as often as scrolls arrive.
function M.scroll(s: Spider, dx: number, dy: number)
    local sc = s.scroll
    sc.dx += dx
    sc.dy += dy
    sc.idle = 0
    sc.ended = false
end

-- The fingers lifted off the trackpad (or momentum took over).
function M.scrollEnd(s: Spider)
    s.scroll.ended = true
end

local function enter(sc: Scroll, state: ScrollState)
    sc.state = state
    sc.t = 0
    sc.from = sc.offset
end

local function ease(t: number): number
    t = math.clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

local function stepScroll(s: Spider, dt: number)
    local sc = s.scroll
    sc.idle += dt
    sc.t += dt
    local d = math.sqrt(sc.dx * sc.dx + sc.dy * sc.dy)
    sc.speed += (d / dt - sc.speed) * smooth(25, dt)
    local along = 0
    if d > 0.001 then
        -- Keep the stroke's direction unless the scroll turns sideways to it.
        local dot = (sc.dx * sc.dirX + sc.dy * sc.dirY) / d
        if sc.state == 'off' or sc.state == 'release' or math.abs(dot) < 0.5 then
            sc.dirX, sc.dirY = sc.dx / d, sc.dy / d
            dot = 1
        end
        along = d * dot * SCROLL_FOLLOW
    end
    sc.dx, sc.dy = 0, 0
    local lifted = sc.ended or sc.idle > SCROLL_IDLE

    if s.press then
        -- A press needs a front leg, so it wins.
        if sc.state ~= 'off' and sc.state ~= 'release' then
            enter(sc, 'release')
        end
    elseif (sc.state == 'off' or sc.state == 'release') and d > 0.001 then
        -- Fingers down: land at the back of the stroke.
        sc.offset = -SCROLL_STROKE
        sc.lift = 0
        enter(sc, 'drag')
    end

    -- Fingers lifting fast is a flick, whatever the feet were doing: a fast
    -- swipe often outruns a stroke and is mid re-place when it ends.
    if lifted and sc.speed > FLICK_SPEED and (sc.state == 'drag' or sc.state == 'replace') then
        enter(sc, 'flick')
    end

    if sc.state == 'drag' then
        sc.lift = 0
        if lifted then
            enter(sc, 'release')
        elseif sc.offset >= SCROLL_STROKE and along > 0 then
            -- A long drag still going at the end of the stroke: lift back and
            -- keep going. Only once it carries on, so a flick that ends here
            -- follows through instead.
            enter(sc, 'replace')
        else
            sc.offset = math.clamp(sc.offset + along, -SCROLL_STROKE, SCROLL_STROKE)
        end
    elseif sc.state == 'replace' then
        local r = math.min(sc.t / SCROLL_RETURN, 1)
        sc.offset = sc.from + (-SCROLL_STROKE - sc.from) * ease(r)
        sc.lift = math.sin(math.pi * r) * SCROLL_LIFT
        if r >= 1 then
            enter(sc, if lifted then 'release' else 'drag')
        end
    elseif sc.state == 'flick' then
        -- Carry on along the stroke fast while coming off the page.
        local r = math.min(sc.t / FLICK_TIME, 1)
        local to = math.max(SCROLL_STROKE, sc.from + FLICK_REACH)
        sc.offset = sc.from + (to - sc.from) * (1 - (1 - r) * (1 - r))
        sc.lift = r * SCROLL_LIFT
        if r >= 1 then
            enter(sc, 'release')
        end
    end

    local holding = sc.state == 'drag' or sc.state == 'replace' or sc.state == 'flick'
    s.scrollLevel += ((if holding then 1 else 0) - s.scrollLevel) * smooth(SCROLL_BLEND, dt)
    if sc.state == 'release' then
        -- Lifting off as the legs go back to walking.
        sc.lift = math.max(sc.lift, (1 - s.scrollLevel) * SCROLL_LIFT)
        if s.scrollLevel < 0.01 then
            s.scrollLevel = 0
            sc.state = 'off'
        end
    end

    local back = SCROLL_LEAN * s.scrollLevel
    s.leanX, s.leanY = -math.cos(s.heading) * back, -math.sin(s.heading) * back
end

-- Where the scrolling front feet are drawn, blended with where the gait left
-- them by how far scrolling has taken over.
local function drawScroll(s: Spider)
    if s.scrollLevel <= 0 then
        return
    end
    local sc = s.scroll
    -- Across the spider's face, to its right.
    local rx, ry = -math.sin(s.heading), math.cos(s.heading)
    local k = s.scrollLevel
    for _, side in { -1, 1 } do
        local i = M.frontLeg(s, side)
        if s.press and s.press.leg == i then
            continue
        end
        local leg = s.legs[i]
        local x = s.pointerX + rx * side * SCROLL_SPREAD + sc.dirX * sc.offset
        local y = s.pointerY + ry * side * SCROLL_SPREAD + sc.dirY * sc.offset - sc.lift
        -- A pointer the spider has not caught up with yet, or on another
        -- display, is reached for, not touched.
        local hx, hy = hipWorld(s, leg)
        local d = dist(x, y, hx, hy)
        local most = leg.rig.reach * REACH_COMFORT
        if d > most then
            x = hx + (x - hx) * most / d
            y = hy + (y - hy) * most / d
        end
        leg.drawX = leg.x + (x - leg.x) * k
        leg.drawY = leg.y + (y - leg.y) * k
    end
end

function M.step(s: Spider, dt: number)
    if dt <= 0 then
        return
    end
    s.touched = false
    if s.frozen then
        s.vx, s.vy, s.turnRate = 0, 0, 0
        stepPress(s, dt)
        return
    end
    moveBody(s, dt)
    stepScroll(s, dt)
    stepLegs(s, dt)
    drawScroll(s)
    stepPress(s, dt)
end

-- The pointer in spider space, scaled to a pupil offset of at most `radius`.
function M.gaze(s: Spider, radius: number): (number, number)
    local dx, dy = s.pointerX - s.x, s.pointerY - s.y
    local c, n = math.cos(-s.heading), math.sin(-s.heading)
    local lx, ly = dx * c - dy * n, dx * n + dy * c
    local d = math.sqrt(lx * lx + ly * ly)
    if d < 0.001 then
        return 0, 0
    end
    local k = math.min(d / 60, 1) * radius / d
    return lx * k, ly * k
end

M.hipWorld = hipWorld
M.idealFoot = idealFoot

return M
