local frame = require('frame')
local gait = require('gait')
local rig = require('rig')
local silk = require('silk')
local will = require('will')

local DT = 1 / 60

-- How far outside the drawn foot and body points the art reaches: stroke,
-- rim, abdomen and shadow.
local ART = 40

-- The worst gap between any drawn point and the view's edge this frame;
-- negative means something is cut off.
local function clearance(s: gait.Spider, size: number): number
    local ox, oy = frame.origin(s.x, s.y, size)
    local worst = math.huge
    local function point(x: number, y: number)
        local lx, ly = x - ox, y - oy
        worst = math.min(worst, lx, ly, size - lx, size - ly)
    end
    point(s.x, s.y)
    for _, leg in s.legs do
        point(leg.drawX, leg.drawY)
    end
    return worst - ART
end

return function(): Tests
    return function(test: Tester)
        test.group('frame', function()
            test.case('the origin centres the spider on whole points', function(expect)
                local ox, oy = frame.origin(500.4, 300.6, 256)
                expect(ox).is(372)
                expect(oy).is(173)
            end)

            test.case('the whole spider stays in view through a sprint, a turn and a press', function(expect)
                local s = gait.new(200, 360, 0)
                local worst = math.huge
                -- 1000 px/s to the right, then a sharp turn back, then a press
                for i = 1, 60 do
                    gait.setPointer(s, 200 + rig.headReach + i * 1000 / 60, 360)
                    gait.step(s, DT)
                    worst = math.min(worst, clearance(s, frame.SIZE))
                end
                gait.setPointer(s, 600, 200)
                for _ = 1, 30 do
                    gait.step(s, DT)
                    worst = math.min(worst, clearance(s, frame.SIZE))
                end
                gait.press(s, 1)
                for _ = 1, 30 do
                    gait.step(s, DT)
                    worst = math.min(worst, clearance(s, frame.SIZE))
                end
                expect(worst).greaterThan(0)
            end)
            test.case('at home the view holds still, with the web and a full drop in it', function(expect)
                -- Top right: the corner at the screen edge, the hub in from it.
                local hubX, hubY, cornerX, cornerY = 1016, 84, 1100, 0
                local s = gait.new(600, 400, 0)
                local w = will.new(3)
                local inp: will.Input = {
                    pointerX = 600 + rig.headReach,
                    pointerY = 400,
                    home = true,
                    hubX = hubX,
                    hubY = hubY,
                    cornerX = cornerX,
                    cornerY = cornerY,
                    dragging = false,
                    asleep = false,
                    free = true,
                }
                local function stepBoth(seconds: number, each: (() -> ())?)
                    for _ = 1, math.floor(seconds / DT + 0.5) do
                        gait.setPointer(s, inp.pointerX, inp.pointerY)
                        will.step(w, s, inp, DT)
                        gait.step(s, DT)
                        if each then
                            each()
                        end
                    end
                end
                stepBoth(9)
                local ox, oy = frame.home(hubX, hubY, cornerX, cornerY, frame.SIZE)
                -- The view's top right is the screen's corner.
                expect(ox + frame.SIZE).is(cornerX)
                expect(oy).is(cornerY)
                -- Room on the open sides, left and below; the screen's edges
                -- cut the other two anyway.
                local worst = math.huge
                local function point(x: number, y: number, art: number)
                    worst = math.min(worst, x - ox - art, oy + frame.SIZE - y - art)
                end
                local web = w.web
                if web then
                    for _, sg in silk.segments(web) do
                        point(sg.x2, sg.y2, 2)
                    end
                end
                will.startDrop(w, s)
                local lowest = 0
                stepBoth(2, function()
                    lowest = math.max(lowest, s.y - hubY)
                    point(s.x, s.y, 40)
                    for _, leg in s.legs do
                        -- A foot tip, not the whole body's art.
                        point(leg.drawX, leg.drawY, 15)
                    end
                end)
                expect(lowest).greaterThan(200)
                expect(worst).greaterThan(0)
            end)
        end)
    end
end
