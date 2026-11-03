local gait = require('gait')
local rig = require('rig')

local DT = 1 / 60

local function dist(ax: number, ay: number, bx: number, by: number): number
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- A spider standing still, facing right, with the pointer just ahead.
local function standing(): gait.Spider
    local s = gait.new(400, 300, 0)
    gait.setPointer(s, 400 + rig.headReach, 300)
    for _ = 1, 60 do
        gait.step(s, DT)
    end
    return s
end

-- Scrolls by (dx, dy) every frame for `frames` frames.
local function scroll(s: gait.Spider, dx: number, dy: number, frames: number, each: (() -> ())?)
    for _ = 1, frames do
        gait.scroll(s, dx, dy)
        gait.step(s, DT)
        if each then
            each()
        end
    end
end

return function(): Tests
    return function(test: Tester)
        test.group('scroll', function()
            test.case('both front feet go to the page under the pointer', function(expect)
                local s = standing()
                scroll(s, 0, -1, 15)
                for _, side in { -1, 1 } do
                    local leg = s.legs[gait.frontLeg(s, side)]
                    expect(dist(leg.drawX, leg.drawY, s.pointerX, s.pointerY)).lessThan(24)
                end
            end)

            test.case('a slow scroll drags the front feet slowly with the content', function(expect)
                local s = standing()
                scroll(s, 0, -2, 10)
                local leg = s.legs[gait.frontLeg(s, -1)]
                local beforeX, beforeY = leg.drawX, leg.drawY
                -- 60 units of content travel upwards over a fifth of a second
                scroll(s, 0, -5, 12)
                -- The feet follow a fraction of it, like a finger on a
                -- trackpad that moves the page further than itself.
                expect(beforeY - leg.drawY).greaterThan(5)
                expect(beforeY - leg.drawY).lessThan(14)
                -- and only along the scroll
                expect(math.abs(leg.drawX - beforeX)).lessThan(0.5)
            end)

            test.case('a slow scroll keeps the feet down instead of flicking', function(expect)
                local s = standing()
                local leg = s.legs[gait.frontLeg(s, -1)]
                scroll(s, 0, -2, 10)
                local ground = leg.drawY
                local lifted = false
                -- A steady, slow scroll: 150 units a second for a second.
                scroll(s, 0, -2.5, 60, function()
                    -- The foot only ever moves up the page with the content,
                    -- never jumps back down for another stroke.
                    if leg.drawY > ground + 0.5 then
                        lifted = true
                    end
                    ground = math.min(ground, leg.drawY)
                end)
                expect(lifted).is(false)
            end)

            test.case('a quick flick snaps the feet along and lets go', function(expect)
                local s = standing()
                local leg = s.legs[gait.frontLeg(s, 1)]
                -- Fingers settle on the page, then four frames of a fast
                -- swipe up, then they lift.
                scroll(s, 0, -0.5, 15)
                scroll(s, 0, -60, 4)
                local atRelease = leg.drawY
                gait.scrollEnd(s)
                local furthest = atRelease
                for _ = 1, 6 do
                    gait.step(s, DT)
                    furthest = math.min(furthest, leg.drawY)
                end
                -- Followed through up the page, quickly
                expect(atRelease - furthest).greaterThan(8)
                -- and lets go of the page within a fifth of a second of the
                -- fingers lifting, sooner than not scrolling at all would.
                for _ = 1, 6 do
                    gait.step(s, DT)
                end
                expect(s.scrollLevel).lessThan(0.3)
            end)

            test.case('a fast scroll flicks over and over, lifting between strokes', function(expect)
                local s = standing()
                local strokes = 0
                local lastX = 0
                local forward = false
                local leg = s.legs[gait.frontLeg(s, 1)]
                scroll(s, 0, 0, 1)
                lastX = leg.drawX
                -- 2400 units a second to the right: a stroke's worth of
                -- travel every few frames, so the feet keep re-placing.
                -- Each time a foot dragging right turns back is one stroke.
                scroll(s, 40, 0, 60, function()
                    local moved = leg.drawX - lastX
                    if moved > 0.5 then
                        forward = true
                    elseif moved < -0.5 and forward then
                        forward = false
                        strokes += 1
                    end
                    lastX = leg.drawX
                end)
                expect(strokes).greaterThan(3)
                expect(strokes).lessThan(8)
            end)

            test.case('the weight shifts back while scrolling and returns after', function(expect)
                local s = standing()
                scroll(s, 0, -2, 20)
                -- facing +x, so back is -x
                expect(s.leanX).lessThan(-3)
                for _ = 1, 60 do
                    gait.step(s, DT)
                end
                expect(math.abs(s.leanX) + math.abs(s.leanY)).lessThan(0.1)
            end)

            test.case('the back legs stay planted while the front legs scroll', function(expect)
                local s = standing()
                local planted = {}
                for i, leg in s.legs do
                    planted[i] = { leg.x, leg.y }
                end
                local moved = false
                scroll(s, 0, -8, 90, function()
                    for i, leg in s.legs do
                        local front = i == gait.frontLeg(s, -1) or i == gait.frontLeg(s, 1)
                        -- Not even a step on the spot, which lands where it
                        -- took off.
                        if not front and (leg.t >= 0 or dist(leg.x, leg.y, planted[i][1], planted[i][2]) > 0.5) then
                            moved = true
                        end
                    end
                end)
                expect(moved).is(false)
            end)

            test.case('a pointer out of reach does not pull the legs past their length', function(expect)
                local s = standing()
                -- The pointer jumps far away (another display) and the
                -- scroll arrives before the spider can walk there.
                gait.setPointer(s, 2000, 300)
                local worst = 0
                scroll(s, 0, -4, 10, function()
                    for _, side in { -1, 1 } do
                        local leg = s.legs[gait.frontLeg(s, side)]
                        local hx, hy = gait.hipWorld(s, leg)
                        worst = math.max(worst, dist(leg.drawX, leg.drawY, hx, hy) / leg.rig.reach)
                    end
                end)
                expect(worst).lessThan(1)
            end)

            test.case('when scrolling stops the front legs go back to walking', function(expect)
                local s = standing()
                scroll(s, 0, -8, 30)
                for _ = 1, 60 do
                    gait.step(s, DT)
                end
                expect(s.scrollLevel).is(0)
                for _, side in { -1, 1 } do
                    local leg = s.legs[gait.frontLeg(s, side)]
                    local ix, iy = gait.idealFoot(s, leg)
                    expect(dist(leg.drawX, leg.drawY, ix, iy)).lessThan(6)
                end
            end)
        end)
    end
end
