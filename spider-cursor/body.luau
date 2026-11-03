-- The body's weight: how it rides on the legs. Pure like gait.luau, which it
-- follows. Each part is a damped spring, so it swings past and settles
-- rather than snapping to place:
--
-- * the abdomen trails a turn and swings past when the turn stops;
-- * the whole body leans into its speed, and lurches forward when it stops;
-- * the abdomen, the heavy part, surges on along the body when it stops,
--   and holds back when it sets off;
-- * the body dips as feet land;
-- * held on to something being dragged, it squats low and jiggles on its
--   locked legs as that thing shakes, and bounces up when it lets go;
-- * a fright makes it jump; hiding presses it down.
local gait = require('gait')

-- Tuning. Stiffness per second squared, damping per second: below
-- 2 * sqrt(stiffness) a spring swings past its rest.
local SWAY_STIFF, SWAY_DAMP = 140, 10
local SWAY_PER_TURN = 0.06 -- radians of trail per radian per second of turn
local SWAY_MAX = 0.5
local LEAN_STIFF, LEAN_DAMP = 90, 8
local LEAN_PER_SPEED = 0.004 -- units forward per unit per second
local LEAN_MAX = 3
local LEAN_INERTIA = 0.15 -- how much a change of speed throws the body
local SURGE_STIFF, SURGE_DAMP = 70, 6
local SURGE_INERTIA = 0.2
local MAX_THROW = 6 -- the most either is thrown along the body, in units
local DIP_STIFF, DIP_DAMP = 200, 14
local DIP_PER_FOOT = 0.09 -- each landing foot pushes the dip this fast
-- Squatting is a dip that lasts: how much smaller the body draws held low,
-- and hidden. Soft, so letting go bounces up past full height.
local SQUAT_STIFF, SQUAT_DAMP = 120, 5
local SQUAT_HELD = 0.12
local SQUAT_HIDDEN = 0.14
local JIGGLE_STIFF, JIGGLE_DAMP = 220, 9
local JIGGLE_INERTIA = 0.25 -- how much a shake of what it holds throws the body
local JIGGLE_MAX = 5
local FRIGHT = 1.4 -- how hard a fright jumps it up

export type Body = {
    -- Out: abdomen trail, radians.
    sway: number,
    swayV: number,
    -- Out: the body drawn this far ahead of where it stands, along its
    -- heading.
    lean: number,
    leanV: number,
    -- Out: the abdomen this far forward along the body.
    surge: number,
    surgeV: number,
    -- Out: how much smaller the body draws, pressed down towards the page.
    dip: number,
    dipV: number,
    -- Out: how much smaller still it draws, squatting or hiding.
    squat: number,
    squatV: number,
    -- Out: the body thrown about on locked legs, in the host's space.
    jiggleX: number,
    jiggleY: number,
    jiggleVX: number,
    jiggleVY: number,
    -- In: holding on to something that is being dragged, and how far it
    -- moved the spider this step.
    holding: boolean,
    carryX: number,
    carryY: number,
    -- In: 0 out in the open to 1 hidden.
    hiding: number,
    -- The carry's velocity last step.
    carryVX: number,
    carryVY: number,
    -- Speed along the heading last step, and which feet were in the air.
    along: number,
    flying: { boolean },
}

local M = {}

function M.new(): Body
    return {
        sway = 0,
        swayV = 0,
        lean = 0,
        leanV = 0,
        surge = 0,
        surgeV = 0,
        dip = 0,
        dipV = 0,
        squat = 0,
        squatV = 0,
        jiggleX = 0,
        jiggleY = 0,
        jiggleVX = 0,
        jiggleVY = 0,
        holding = false,
        carryX = 0,
        carryY = 0,
        hiding = 0,
        carryVX = 0,
        carryVY = 0,
        along = 0,
        flying = {},
    }
end

-- One semi-implicit Euler step of a spring pulling `x` to `rest`, with an
-- extra `push`.
local function spring(x: number, v: number, rest: number, stiff: number, damp: number, push: number, dt: number): (number, number)
    v += (stiff * (rest - x) - damp * v + push) * dt
    return x + v * dt, v
end

-- Something gave it a fright: it jumps.
function M.fright(b: Body)
    b.dipV -= FRIGHT
end

function M.step(b: Body, s: gait.Spider, dt: number)
    if dt <= 0 then
        return
    end
    local along = s.vx * math.cos(s.heading) + s.vy * math.sin(s.heading)
    local accel = (along - b.along) / dt
    b.along = along

    local trail = math.clamp(-s.turnRate * SWAY_PER_TURN, -SWAY_MAX, SWAY_MAX)
    b.sway, b.swayV = spring(b.sway, b.swayV, trail, SWAY_STIFF, SWAY_DAMP, 0, dt)

    -- Speeding up throws the body back, slowing down throws it forward.
    local lean = math.clamp(along * LEAN_PER_SPEED, 0, LEAN_MAX)
    b.lean, b.leanV = spring(b.lean, b.leanV, lean, LEAN_STIFF, LEAN_DAMP, -accel * LEAN_INERTIA, dt)
    b.lean = math.clamp(b.lean, -MAX_THROW, MAX_THROW)
    b.surge, b.surgeV = spring(b.surge, b.surgeV, 0, SURGE_STIFF, SURGE_DAMP, -accel * SURGE_INERTIA, dt)
    b.surge = math.clamp(b.surge, -MAX_THROW, MAX_THROW)

    local landed = 0
    for i, leg in s.legs do
        local flying = leg.t >= 0
        if b.flying[i] and not flying then
            landed += 1
        end
        b.flying[i] = flying
    end
    b.dipV += landed * DIP_PER_FOOT
    b.dip, b.dipV = spring(b.dip, b.dipV, 0, DIP_STIFF, DIP_DAMP, 0, dt)

    local low = (if b.holding then SQUAT_HELD else 0) + b.hiding * SQUAT_HIDDEN
    b.squat, b.squatV = spring(b.squat, b.squatV, low, SQUAT_STIFF, SQUAT_DAMP, 0, dt)

    -- What it holds speeding up leaves the body behind.
    local cvx, cvy = 0, 0
    if b.holding then
        cvx, cvy = b.carryX / dt, b.carryY / dt
    end
    local ax, ay = (cvx - b.carryVX) / dt, (cvy - b.carryVY) / dt
    if not b.holding then
        ax, ay = 0, 0
    end
    b.carryVX, b.carryVY = cvx, cvy
    b.jiggleX, b.jiggleVX = spring(b.jiggleX, b.jiggleVX, 0, JIGGLE_STIFF, JIGGLE_DAMP, -ax * JIGGLE_INERTIA, dt)
    b.jiggleY, b.jiggleVY = spring(b.jiggleY, b.jiggleVY, 0, JIGGLE_STIFF, JIGGLE_DAMP, -ay * JIGGLE_INERTIA, dt)
    b.jiggleX = math.clamp(b.jiggleX, -JIGGLE_MAX, JIGGLE_MAX)
    b.jiggleY = math.clamp(b.jiggleY, -JIGGLE_MAX, JIGGLE_MAX)
end

return M
