local body = require('body')
local gait = require('gait')
local rig = require('rig')

local DT = 1 / 60

-- Steps the gait and the body together for `seconds`, calling `each` after
-- every frame.
local function run(s: gait.Spider, b: body.Body, seconds: number, each: (() -> ())?)
    for _ = 1, math.floor(seconds / DT + 0.5) do
        gait.step(s, DT)
        body.step(b, s, DT)
        if each then
            each()
        end
    end
end

return function(): Tests
    return function(test: Tester)
        test.group('body', function()
            test.case('the abdomen trails a turn, swings past and settles', function(expect)
                local s = gait.new(300, 300, 0)
                local b = body.new()
                -- Turn to face straight down: turning clockwise, so the
                -- abdomen trails the other way.
                gait.setPointer(s, 300 + rig.headReach * 0.2, 300 + rig.headReach)
                local trailed, swungPast = 0, 0
                run(s, b, 1.5, function()
                    trailed = math.min(trailed, b.sway)
                    if trailed < -0.05 then
                        swungPast = math.max(swungPast, b.sway)
                    end
                end)
                expect(trailed).lessThan(-0.05)
                expect(swungPast).greaterThan(0.01)
                run(s, b, 2)
                expect(math.abs(b.sway)).lessThan(0.005)
            end)

            test.case('leans into a sprint, lurches forward as it stops, then settles', function(expect)
                local s = gait.new(100, 300, 0)
                local b = body.new()
                gait.setPointer(s, 1000, 300)
                local cruising, fastest, lurch = 0, 0, 0
                run(s, b, 3, function()
                    local v = math.sqrt(s.vx * s.vx + s.vy * s.vy)
                    if v > fastest then
                        fastest = v
                        cruising = b.lean
                    elseif v < fastest * 0.5 then
                        lurch = math.max(lurch, b.lean)
                    end
                end)
                expect(cruising).greaterThan(0.5)
                expect(lurch).greaterThan(cruising)
                run(s, b, 3)
                expect(math.abs(b.lean)).lessThan(0.05)
            end)

            test.case('the abdomen surges on as the body stops', function(expect)
                local s = gait.new(100, 300, 0)
                local b = body.new()
                gait.setPointer(s, 1000, 300)
                local surge = 0
                run(s, b, 3, function()
                    surge = math.max(surge, b.surge)
                end)
                expect(surge).greaterThan(1)
                run(s, b, 3)
                expect(math.abs(b.surge)).lessThan(0.05)
            end)

            test.case('dips as feet land, and holds still standing', function(expect)
                local s = gait.new(100, 300, 0)
                local b = body.new()
                gait.setPointer(s, 600, 300)
                local dip = 0
                run(s, b, 1, function()
                    dip = math.max(dip, b.dip)
                end)
                expect(dip).greaterThan(0.01)
                expect(dip).lessThan(0.06)
                run(s, b, 4)
                expect(b.dip).lessThan(0.001)
            end)
        end)

        test.group('held', function()
            test.case('held on a dragged window, it squats and jiggles as the window shakes', function(expect)
                local s = gait.new(300, 300, 0)
                local b = body.new()
                run(s, b, 0.5)
                s.frozen = true
                b.holding = true
                local squat, jiggle = 0, 0
                for i = 1, 90 do
                    local dx = math.sin(i * 0.5) * 6
                    gait.carry(s, dx, 0)
                    b.carryX, b.carryY = dx, 0
                    gait.step(s, DT)
                    body.step(b, s, DT)
                    squat = math.max(squat, b.squat)
                    jiggle = math.max(jiggle, math.abs(b.jiggleX))
                end
                expect(squat).greaterThan(0.08)
                expect(jiggle).greaterThan(1)
                expect(jiggle <= 5).is(true)
            end)

            test.case('let go, it bounces up past its height and settles', function(expect)
                local s = gait.new(300, 300, 0)
                local b = body.new()
                b.holding = true
                run(s, b, 1)
                b.holding = false
                b.carryX, b.carryY = 0, 0
                local lowest = 0
                run(s, b, 0.6, function()
                    lowest = math.min(lowest, b.squat)
                end)
                expect(lowest).lessThan(-0.03)
                run(s, b, 2)
                expect(math.abs(b.squat)).lessThan(0.005)
                expect(math.abs(b.jiggleX) + math.abs(b.jiggleY)).lessThan(0.01)
            end)

            test.case('a fright makes it jump, and hiding presses it down', function(expect)
                local s = gait.new(300, 300, 0)
                local b = body.new()
                run(s, b, 0.5)
                body.fright(b)
                local jumped = 0
                run(s, b, 0.3, function()
                    jumped = math.min(jumped, b.dip)
                end)
                expect(jumped).lessThan(-0.04)
                b.hiding = 1
                run(s, b, 1)
                expect(b.squat).greaterThan(0.1)
            end)
        end)
    end
end
