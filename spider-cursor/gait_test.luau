local gait = require('gait')
local rig = require('rig')

local DT = 1 / 60

local function run(s: gait.Spider, seconds: number)
    for _ = 1, math.floor(seconds / DT + 0.5) do
        gait.step(s, DT)
    end
end

local function dist(ax: number, ay: number, bx: number, by: number): number
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

local function anyStepping(s: gait.Spider): boolean
    for _, leg in s.legs do
        if leg.t >= 0 then
            return true
        end
    end
    return false
end

return function(): Tests
    return function(test: Tester)
        test.group('follow', function()
            test.case('stops with the pointer just ahead of the face', function(expect)
                local s = gait.new(300, 300, 0)
                gait.setPointer(s, 700, 420)
                run(s, 2)
                local d = dist(s.x, s.y, 700, 420)
                expect(math.abs(d - rig.headReach)).lessThan(4)
                -- and facing it
                local want = math.atan2(420 - s.y, 700 - s.x)
                expect(math.abs(s.heading - want)).lessThan(0.05)
            end)

            test.case('keeps up with a fast pointer', function(expect)
                local s = gait.new(100, 360, 0)
                -- 1000 px/s sweep for a second
                for i = 1, 60 do
                    gait.setPointer(s, 100 + i * 1000 / 60, 360)
                    gait.step(s, DT)
                end
                expect(dist(s.x, s.y, 1100, 360)).lessThan(200)
            end)
        end)

        test.group('gait', function()
            test.case('at a walk the two leg groups take turns', function(expect)
                local s = gait.new(200, 360, 0)
                local steps = 0
                local overlap = 0
                -- 300 px/s, steady
                for i = 1, 120 do
                    gait.setPointer(s, 200 + rig.headReach + i * 5, 360)
                    gait.step(s, DT)
                    local a, b = false, false
                    for _, leg in s.legs do
                        if leg.t == 0 then
                            steps += 1
                        end
                        if leg.t >= 0 then
                            if leg.rig.group == 0 then
                                a = true
                            else
                                b = true
                            end
                        end
                    end
                    if a and b then
                        overlap += 1
                    end
                end
                expect(steps).greaterThan(8)
                expect(overlap).is(0)
            end)

            test.case('feet stay within reach of their hips', function(expect)
                local s = gait.new(850 - rig.headReach, 360, 0)
                local worst = 0
                -- A brisk, curving pointer: up to about 500 px/s.
                for i = 1, 360 do
                    gait.setPointer(s, 550 + math.cos(i * 0.025) * 300, 360 + math.sin(i * 0.035) * 220)
                    gait.step(s, DT)
                    for _, leg in s.legs do
                        local hx, hy = gait.hipWorld(s, leg)
                        worst = math.max(worst, dist(leg.drawX, leg.drawY, hx, hy) / leg.rig.reach)
                    end
                end
                -- IK clamps anything past 1; much past it reads as a leg
                -- dragged behind.
                expect(worst).lessThan(1.25)
            end)

            test.case('a still pointer comes to rest', function(expect)
                local s = gait.new(300, 300, 0)
                gait.setPointer(s, 500, 300)
                run(s, 3)
                expect(anyStepping(s)).is(false)
            end)
        end)

        test.group('target', function()
            test.case('walks onto a target of its own, facing where it is told', function(expect)
                local s = gait.new(300, 300, 0)
                gait.setPointer(s, 700, 600)
                gait.setTarget(s, { x = 500, y = 200, reach = 0, maxSpeed = 300, face = math.pi / 2 })
                local fastest = 0
                for _ = 1, 240 do
                    gait.step(s, DT)
                    fastest = math.max(fastest, math.sqrt(s.vx * s.vx + s.vy * s.vy))
                end
                expect(dist(s.x, s.y, 500, 200)).lessThan(4)
                expect(math.abs(s.heading - math.pi / 2)).lessThan(0.05)
                expect(fastest).lessThan(301)
                expect(anyStepping(s)).is(false)
            end)

            test.case('goes back to the pointer when the target is cleared', function(expect)
                local s = gait.new(300, 300, 0)
                gait.setPointer(s, 600, 300)
                gait.setTarget(s, { x = 300, y = 300, reach = 0, maxSpeed = 300, face = nil })
                run(s, 1)
                expect(dist(s.x, s.y, 300, 300)).lessThan(4)
                gait.setTarget(s, nil)
                run(s, 2)
                expect(math.abs(dist(s.x, s.y, 600, 300) - rig.headReach)).lessThan(4)
            end)
        end)

        test.group('carry', function()
            test.case('carried, it moves as one piece: no steps, feet locked to the body', function(expect)
                local s = gait.new(300, 300, 0)
                gait.setPointer(s, 400, 300)
                run(s, 2)
                local before = {}
                for i, leg in s.legs do
                    before[i] = { leg.drawX - s.x, leg.drawY - s.y }
                end
                s.frozen = true
                for i = 1, 60 do
                    gait.carry(s, 3, math.sin(i * 0.3) * 4)
                    gait.setPointer(s, s.x + rig.headReach, s.y)
                    gait.step(s, DT)
                    expect(anyStepping(s)).is(false)
                end
                expect(s.x - 300).greaterThan(170)
                for i, leg in s.legs do
                    expect(dist(leg.drawX - s.x, leg.drawY - s.y, before[i][1], before[i][2])).lessThan(0.01)
                end
            end)

            test.case('turned while held, its feet turn with it', function(expect)
                local s = gait.new(300, 300, 0)
                gait.setPointer(s, 400, 300)
                run(s, 2)
                local before = {}
                for i, leg in s.legs do
                    before[i] = { leg.drawX - s.x, leg.drawY - s.y }
                end
                s.frozen = true
                gait.turn(s, math.pi / 2)
                expect(s.heading).is(math.pi / 2)
                -- A quarter turn: spider space x becomes screen y.
                for i, leg in s.legs do
                    expect(dist(leg.drawX - s.x, leg.drawY - s.y, -before[i][2], before[i][1])).lessThan(0.01)
                end
            end)
        end)

        test.group('press', function()
            test.case('left press puts the left front foot on the pointer', function(expect)
                local s = gait.new(300, 300, 0)
                gait.setPointer(s, 500, 300)
                run(s, 2)
                gait.press(s, -1)
                run(s, 0.15)
                local leg = s.legs[gait.frontLeg(s, -1)]
                expect(leg.rig.name).is('L1')
                expect(dist(leg.drawX, leg.drawY, 500, 300)).lessThan(1)
            end)

            test.case('right press uses the right front leg', function(expect)
                local s = gait.new(300, 300, 0)
                gait.setPointer(s, 500, 300)
                run(s, 2)
                gait.press(s, 1)
                run(s, 0.15)
                local leg = s.legs[gait.frontLeg(s, 1)]
                expect(leg.rig.name).is('R1')
                expect(dist(leg.drawX, leg.drawY, 500, 300)).lessThan(1)
                local other = s.legs[gait.frontLeg(s, -1)]
                expect(dist(other.drawX, other.drawY, 500, 300)).greaterThan(10)
            end)

            test.case('says once where and when the pressing foot touches down', function(expect)
                local s = gait.new(300, 300, 0)
                gait.setPointer(s, 500, 300)
                run(s, 2)
                gait.press(s, 1)
                local touches, touchedAt = 0, -1
                local t = 0
                for _ = 1, 60 do
                    gait.step(s, DT)
                    t += DT
                    if s.touched then
                        touches += 1
                        touchedAt = t
                        expect(dist(s.touchX, s.touchY, 500, 300)).lessThan(0.01)
                    end
                end
                expect(touches).is(1)
                -- When the foot arrives, not when the button went down.
                expect(touchedAt).greaterThan(0.05)
                expect(touchedAt).lessThan(0.15)
            end)

            test.case('the pressing foot goes home afterwards', function(expect)
                local s = gait.new(300, 300, 0)
                gait.setPointer(s, 500, 300)
                run(s, 2)
                gait.press(s, -1)
                run(s, 1)
                expect(s.press == nil).is(true)
                local leg = s.legs[gait.frontLeg(s, -1)]
                local ix, iy = gait.idealFoot(s, leg)
                expect(dist(leg.drawX, leg.drawY, ix, iy)).lessThan(6)
            end)
        end)
    end
end
