-- Silk, as geometry: the webs a spider spins. Pure like gait.luau: spider.luau decides when, and
-- draws what this gives it. Points are in the host's space.

-- Tuning. Distances in artboard units, times in seconds.
-- Webs: how many spokes, how many turns of spiral, and how unevenly a
-- spider lays them.
local ORB_SPOKES = 11
local CORNER_SPOKES = 9
local RINGS = 6
local WOBBLE = 0.18
-- How much of the spinning is spokes; the rest is the spiral.
local SPOKE_SHARE = 0.35
-- How the web gives: a weight on the hub pulls it this far, and it springs
-- back with this stiffness and damping (per second), wobbling as it goes.
local SAG = 8
local SAG_STIFF = 90
local SAG_DAMP = 3.5

export type Spoke = { angle: number, length: number }

export type Web = {
    x: number,
    y: number,
    spokes: { Spoke },
    -- 0 nothing spun yet to 1 finished.
    progress: number,
    -- 1 whole to 0 gone.
    opacity: number,
    -- How far the hub is pulled out of place, and how fast it is moving.
    sagX: number,
    sagY: number,
    sagVX: number,
    sagVY: number,
}

export type Segment = { x1: number, y1: number, x2: number, y2: number }

local M = {}

-- A little pseudo random from a seed, so a web is the same each time it is
-- drawn.
local function wobble(seed: number, i: number): number
    local v = math.sin(seed * 12.9898 + i * 78.233) * 43758.5453
    return (v - math.floor(v)) * 2 - 1
end

-- A round web centred on (x, y).
function M.orb(x: number, y: number, radius: number, seed: number): Web
    local spokes = {}
    for i = 1, ORB_SPOKES do
        local a = (i - 1 + wobble(seed, i) * WOBBLE) * 2 * math.pi / ORB_SPOKES
        table.insert(spokes, { angle = a, length = radius * (1 + wobble(seed, i + 50) * WOBBLE) })
    end
    return { x = x, y = y, spokes = spokes, progress = 0, opacity = 1, sagX = 0, sagY = 0, sagVX = 0, sagVY = 0 }
end

-- A web in a corner, hub at (x, y), its spokes on the corner's side tied to
-- the two edges that meet at (cornerX, cornerY); the rest hang free.
function M.corner(x: number, y: number, cornerX: number, cornerY: number, seed: number): Web
    local radius = math.max(math.abs(cornerX - x), math.abs(cornerY - y)) * 1.1
    local spokes = {}
    for i = 1, CORNER_SPOKES do
        local a = (i - 1 + wobble(seed, i) * WOBBLE) * 2 * math.pi / CORNER_SPOKES
        local c, n = math.cos(a), math.sin(a)
        -- Out to whichever edge it meets first, if it meets one within reach.
        local len = radius * (1 + wobble(seed, i + 50) * WOBBLE)
        local toX = if math.abs(c) > 1e-6 then (cornerX - x) / c else math.huge
        local toY = if math.abs(n) > 1e-6 then (cornerY - y) / n else math.huge
        local edge = math.min(if toX > 0 then toX else math.huge, if toY > 0 then toY else math.huge)
        if edge < len * 1.6 then
            len = edge
        end
        table.insert(spokes, { angle = a, length = len })
    end
    return { x = x, y = y, spokes = spokes, progress = 0, opacity = 1, sagX = 0, sagY = 0, sagVX = 0, sagVY = 0 }
end

-- A weight hangs on the hub: (px, py) is its pull, 1 long for the
-- spider's whole weight, (0, 0) for none.
function M.pull(w: Web, px: number, py: number, dt: number)
    local ax = (px * SAG - w.sagX) * SAG_STIFF - w.sagVX * SAG_DAMP
    local ay = (py * SAG - w.sagY) * SAG_STIFF - w.sagVY * SAG_DAMP
    w.sagVX += ax * dt
    w.sagVY += ay * dt
    w.sagX += w.sagVX * dt
    w.sagY += w.sagVY * dt
end

-- Where the hub is now.
function M.hub(w: Web): (number, number)
    return w.x + w.sagX, w.y + w.sagY
end

-- A point f of the way out along a spoke. The hub's sag carries the threads
-- with it, less the further out, and nothing at the ends where they are tied.
local function along(w: Web, s: Spoke, f: number): (number, number)
    local give = 1 - f
    return w.x + math.cos(s.angle) * s.length * f + w.sagX * give, w.y + math.sin(s.angle) * s.length * f + w.sagY * give
end

-- The threads spun so far: spokes one by one, then the spiral from the
-- outside in, a span at a time.
function M.segments(w: Web): { Segment }
    local out: { Segment } = {}
    local n = #w.spokes
    local spokesDone = math.clamp(w.progress / SPOKE_SHARE, 0, 1) * n
    for i, s in w.spokes do
        local f = math.clamp(spokesDone - (i - 1), 0, 1)
        if f > 0 then
            local x2, y2 = along(w, s, f)
            local hx, hy = M.hub(w)
            table.insert(out, { x1 = hx, y1 = hy, x2 = x2, y2 = y2 })
        end
    end
    local spans = math.clamp((w.progress - SPOKE_SHARE) / (1 - SPOKE_SHARE), 0, 1) * n * RINGS
    for k = 0, n * RINGS - 1 do
        local f = math.clamp(spans - k, 0, 1)
        if f <= 0 then
            break
        end
        local ring = k // n
        local i = k % n + 1
        local j = i % n + 1
        -- Each span steps a little further in, so the rings spiral.
        local r1 = 0.92 - (ring + (i - 1) / n) * 0.8 / RINGS
        local r2 = 0.92 - (ring + i / n) * 0.8 / RINGS
        local a, b = w.spokes[i], w.spokes[j]
        local x1, y1 = along(w, a, r1)
        local x2, y2 = along(w, b, r2)
        table.insert(out, { x1 = x1, y1 = y1, x2 = x1 + (x2 - x1) * f, y2 = y1 + (y2 - y1) * f })
    end
    return out
end

return M
