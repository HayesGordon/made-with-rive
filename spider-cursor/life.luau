-- What the spider does between moves: blinks, getting its breath back, a
-- weight shift, a glance around, a foot tap, and in the end a nap. Pure like
-- gait.luau.
--
-- This decides *when*; how it looks is the file's. Blinks, squinting,
-- breathing and sleeping are timelines in the state machine, and
-- spider.luau hands them these decisions as view model triggers, booleans
-- and numbers. The sway, glances and taps move things the gait also moves,
-- so they are drawn from here.

-- Tuning. Times in seconds, distances in artboard units.
-- How long one blink plays. Matches the Blink timelines, so a double blink
-- starts its second half after the first.
local BLINK = 0.16
local BLINK_EVERY_MIN, BLINK_EVERY_MAX = 2.2, 5.5
local BLINK_STAGGER_MIN, BLINK_STAGGER_MAX = 0.07, 0.16 -- one eye leading
local BLINK_TOGETHER = 0.6 -- chance a blink is both eyes at once
local BLINK_DOUBLE = 0.15 -- chance of a quick second blink
local TURN_BLINK = 6 -- a turn faster than this, radians per second, blinks
local STILL_SPEED = 15 -- below this the spider counts as standing
local SETTLE_IN = 0.5 -- standing this long before the idle moves start
local SHIFT = 1.2 -- weight shift, at most
local GLANCE_AFTER = 1.5
local GLANCE_EVERY_MIN, GLANCE_EVERY_MAX = 2, 5
local GLANCE_HOLD_MIN, GLANCE_HOLD_MAX = 0.5, 1.3
local TAP_AFTER = 3
local TAP_EVERY_MIN, TAP_EVERY_MAX = 3, 7
local TAP = 0.2 -- one tap, up and down
local TAP_LIFT = 5
local SLEEP_AFTER = 10 -- standing this long, it falls asleep (hosts can change it)
local DOZE = 1.2 -- how fast the sway dies down as it nods off, per second
-- After waking, the eyes take this long to open before the double blink.
local WAKE_BLINK = 0.12

export type Eye = {
    -- Seconds into a blink, or -1 between blinks.
    t: number,
    -- Seconds until a queued blink starts, or -1 for none.
    wait: number,
    -- A second blink to start once this one ends.
    again: boolean,
}

export type Life = {
    seed: number,
    time: number,
    still: number,
    eyes: { Eye },
    nextBlink: number,
    sinceBlink: number,
    -- 0 awake to 1 asleep, eased: fades the sway out as it nods off.
    doze: number,
    nextGlance: number,
    glanceLeft: number,
    glanceX: number,
    glanceY: number,
    nextTap: number,
    tapsLeft: number,
    tapT: number,
    -- Out: a blink starts on that eye this step.
    blinkedL: boolean,
    blinkedR: boolean,
    -- Out: the eyes narrow while a front leg presses.
    squinting: boolean,
    -- Out: how winded, 0 calm to 1 after a sprint.
    exertion: number,
    -- Out: asleep.
    asleep: boolean,
    -- Out: body offset in spider space.
    shiftX: number,
    shiftY: number,
    -- Out: where the eyes look instead of the pointer, a unit direction in
    -- spider space, and how much (0 the pointer, 1 the glance).
    gazeX: number,
    gazeY: number,
    gazeWeight: number,
    -- Out: which front leg taps (-1 left, 1 right, 0 none) and how high.
    tapSide: number,
    tapLift: number,
    -- In: seconds of standing before it sleeps; math.huge for never.
    sleepAfter: number,
}

local M = {}

-- Park-Miller, so a seed replays the same spider in a test.
local function random(l: Life): number
    l.seed = (l.seed * 16807) % 2147483647
    return l.seed / 2147483647
end

local function between(l: Life, lo: number, hi: number): number
    return lo + (hi - lo) * random(l)
end

local function smooth(rate: number, dt: number): number
    return 1 - math.exp(-rate * dt)
end

local function ease(t: number): number
    t = math.clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

function M.new(seed: number): Life
    local l: Life = {
        seed = math.max(math.floor(seed) % 2147483647, 1),
        time = 0,
        still = 0,
        eyes = {
            { t = -1, wait = -1, again = false },
            { t = -1, wait = -1, again = false },
        },
        nextBlink = 0,
        sinceBlink = math.huge,
        doze = 0,
        nextGlance = 0,
        glanceLeft = 0,
        glanceX = 1,
        glanceY = 0,
        nextTap = 0,
        tapsLeft = 0,
        tapT = 0,
        blinkedL = false,
        blinkedR = false,
        squinting = false,
        exertion = 0,
        asleep = false,
        shiftX = 0,
        shiftY = 0,
        gazeX = 1,
        gazeY = 0,
        gazeWeight = 0,
        tapSide = 0,
        tapLift = 0,
        sleepAfter = SLEEP_AFTER,
    }
    l.nextBlink = between(l, 1, BLINK_EVERY_MAX)
    l.nextGlance = between(l, GLANCE_EVERY_MIN, GLANCE_EVERY_MAX)
    l.nextTap = between(l, TAP_EVERY_MIN, TAP_EVERY_MAX)
    return l
end

-- Queue a blink on one eye, `wait` seconds from now.
local function queue(eye: Eye, wait: number, again: boolean)
    if eye.t < 0 and eye.wait < 0 then
        eye.wait = wait
        eye.again = again
    end
end

local function blinkBoth(l: Life)
    for _, eye in l.eyes do
        queue(eye, 0, false)
    end
    l.sinceBlink = 0
end

local function blink(l: Life)
    local r = random(l)
    local again = random(l) < BLINK_DOUBLE
    if r < BLINK_TOGETHER then
        queue(l.eyes[1], 0, again)
        queue(l.eyes[2], 0, again)
    else
        local lead = if random(l) < 0.5 then 1 else 2
        queue(l.eyes[lead], 0, again)
        queue(l.eyes[3 - lead], between(l, BLINK_STAGGER_MIN, BLINK_STAGGER_MAX), again)
    end
    l.sinceBlink = 0
end

local function stepSleep(l: Life, dt: number)
    local was = l.asleep
    l.asleep = l.still > l.sleepAfter
    l.doze += ((if l.asleep then 1 else 0) - l.doze) * smooth(DOZE, dt)
    if l.doze < 0.001 then
        l.doze = 0
    end
    if l.asleep then
        -- No blinking in its sleep: the eyes are shut.
        for _, eye in l.eyes do
            eye.t, eye.wait, eye.again = -1, -1, false
        end
    elseif was then
        -- Waking up: a double blink once the eyes are open, and no other
        -- blink due on top of it.
        for _, eye in l.eyes do
            eye.t, eye.wait, eye.again = -1, WAKE_BLINK, true
        end
        l.nextBlink = math.max(l.nextBlink, BLINK_EVERY_MIN)
    end
end

local function stepEyes(l: Life, dt: number, turnRate: number, pressing: boolean)
    l.blinkedL, l.blinkedR = false, false
    l.squinting = pressing
    if l.asleep then
        return
    end
    l.sinceBlink += dt
    l.nextBlink -= dt
    if l.nextBlink <= 0 then
        blink(l)
        l.nextBlink = between(l, BLINK_EVERY_MIN, BLINK_EVERY_MAX)
    elseif math.abs(turnRate) > TURN_BLINK and l.sinceBlink > 0.8 then
        -- Cartoon characters blink as they whip round.
        blinkBoth(l)
        l.nextBlink = math.max(l.nextBlink, BLINK_EVERY_MIN)
    end
    for i, eye in l.eyes do
        if eye.wait >= 0 then
            eye.wait -= dt
            if eye.wait < 0 then
                eye.wait = -1
                eye.t = 0
                if i == 1 then
                    l.blinkedL = true
                else
                    l.blinkedR = true
                end
            end
        elseif eye.t >= 0 then
            eye.t += dt
            if eye.t >= BLINK then
                eye.t = -1
                if eye.again then
                    eye.again = false
                    eye.wait = 0.06
                end
            end
        end
    end
end

local function stepBreath(l: Life, dt: number, speed: number)
    -- Winded fast, recovers slowly.
    local effort = math.clamp(speed / 600, 0, 1)
    local rate = if effort > l.exertion then 3 else 0.35
    l.exertion += (effort - l.exertion) * smooth(rate, dt)
    if l.exertion < 0.001 then
        l.exertion = 0
    end
end

local function stepIdle(l: Life, dt: number)
    -- Asleep, it lies still.
    local settled = ease((l.still - SETTLE_IN) / 1.5) * (1 - l.doze)
    local dozing = l.doze > 0

    -- A slow figure of eight, so the knees flex under a planted body.
    l.shiftX = settled * SHIFT * math.sin(2 * math.pi * 0.21 * l.time)
    l.shiftY = settled * SHIFT * 0.8 * math.sin(2 * math.pi * 0.42 * l.time + 1)

    -- Glancing off somewhere, then back at the pointer.
    if l.still < GLANCE_AFTER or dozing then
        l.glanceLeft = 0
        l.nextGlance = math.max(l.nextGlance, GLANCE_EVERY_MIN * 0.5)
    elseif l.glanceLeft > 0 then
        l.glanceLeft -= dt
    else
        l.nextGlance -= dt
        if l.nextGlance <= 0 then
            local a = between(l, -2.2, 2.2)
            l.glanceX, l.glanceY = math.cos(a), math.sin(a)
            l.glanceLeft = between(l, GLANCE_HOLD_MIN, GLANCE_HOLD_MAX)
            l.nextGlance = between(l, GLANCE_EVERY_MIN, GLANCE_EVERY_MAX)
        end
    end
    local want = if l.glanceLeft > 0 then 1 else 0
    l.gazeWeight += (want - l.gazeWeight) * smooth(if want > 0 then 9 else 14, dt)
    if l.gazeWeight < 0.005 then
        l.gazeWeight = 0
    end
    l.gazeX, l.gazeY = l.glanceX, l.glanceY

    -- An impatient tap or three with a front foot.
    if l.still < TAP_AFTER or dozing then
        l.tapsLeft = 0
        l.nextTap = math.max(l.nextTap, TAP_EVERY_MIN * 0.5)
    elseif l.tapsLeft > 0 then
        l.tapT += dt
        if l.tapT >= TAP then
            l.tapT = 0
            l.tapsLeft -= 1
        end
    else
        l.nextTap -= dt
        if l.nextTap <= 0 then
            l.tapSide = if random(l) < 0.5 then -1 else 1
            l.tapsLeft = if random(l) < 0.5 then 2 else 3
            l.tapT = 0
            l.nextTap = between(l, TAP_EVERY_MIN, TAP_EVERY_MAX)
        end
    end
    if l.tapsLeft > 0 then
        l.tapLift = math.sin(math.pi * l.tapT / TAP) * TAP_LIFT
    else
        -- Cut short by moving off: let the foot down rather than drop it.
        l.tapLift *= 1 - smooth(25, dt)
        if l.tapLift < 0.005 then
            l.tapLift = 0
            l.tapSide = 0
        end
    end
end

-- `speed` and `turnRate` from the gait; `pressing` while a front leg presses;
-- `busy` while the spider is doing something else that is not standing
-- around, like scrolling.
function M.step(l: Life, dt: number, speed: number, turnRate: number, pressing: boolean, busy: boolean?)
    if dt <= 0 then
        return
    end
    l.time += dt
    if speed < STILL_SPEED and math.abs(turnRate) < 0.5 and not pressing and not busy then
        l.still += dt
    else
        l.still = 0
    end
    stepSleep(l, dt)
    stepEyes(l, dt, turnRate, pressing)
    stepBreath(l, dt, speed)
    stepIdle(l, dt)
end

return M
