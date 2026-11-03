local gait = require('gait')
local rig = require('rig')
local silk = require('silk')
local will = require('will')

local DT = 1 / 60

local function dist(ax: number, ay: number, bx: number, by: number): number
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

local function input(px: number, py: number): will.Input
    return {
        pointerX = px,
        pointerY = py,
        home = false,
        hubX = 920,
        hubY = 80,
        cornerX = 1000,
        cornerY = 0,
        dragging = false,
        asleep = false,
        free = true,
    }
end

-- Steps the will and the gait together, as spider.luau does.
local function run(w: will.Will, s: gait.Spider, inp: will.Input, seconds: number, each: ((number) -> ())?)
    for i = 1, math.floor(seconds / DT + 0.5) do
        gait.setPointer(s, inp.pointerX, inp.pointerY)
        will.step(w, s, inp, DT)
        gait.step(s, DT)
        if each then
            each(i)
        end
    end
end

-- A spider standing just behind a pointer at (500, 400).
local function settled(): (will.Will, gait.Spider, will.Input)
    local s = gait.new(500 - rig.headReach, 400, 0)
    local w = will.new(3)
    local inp = input(500, 400)
    run(w, s, inp, 0.5)
    return w, s, inp
end

return function(): Tests
    return function(test: Tester)
        test.group('idle play', function()
            test.case('a still pointer gets something to do, and moving it stops play at once', function(expect)
                local w, s, inp = settled()
                local played = false
                run(w, s, inp, 8, function()
                    if w.play ~= 'none' then
                        played = true
                    end
                end)
                expect(played).is(true)
                will.startPlay(w, s, 'groom')
                will.step(w, s, inp, DT)
                expect(w.grooming).is(true)
                inp.pointerX += 40
                will.step(w, s, inp, DT)
                expect(w.play).is('none')
                expect(w.grooming).is(false)
                expect(s.target == nil).is(true)
            end)

            test.case('wanders off a little, then comes back to the pointer', function(expect)
                local w, s, inp = settled()
                local x0, y0 = s.x, s.y
                w.playsLeft = 1
                will.startPlay(w, s, 'wander')
                local furthest = 0
                run(w, s, inp, 9, function()
                    furthest = math.max(furthest, dist(s.x, s.y, x0, y0))
                end)
                expect(furthest).greaterThan(40)
                expect(furthest).lessThan(110)
                expect(math.abs(dist(s.x, s.y, 500, 400) - rig.headReach)).lessThan(6)
            end)

            test.case('spins a little web round itself, which fades once it walks off', function(expect)
                local w, s, inp = settled()
                w.playsLeft = 1
                will.startPlay(w, s, 'spin')
                run(w, s, inp, 6)
                local web = w.web
                expect(web ~= nil and web.progress >= 1).is(true)
                expect(dist(s.x, s.y, if web then web.x else 0, if web then web.y else 0)).lessThan(6)
                inp.pointerX, inp.pointerY = 800, 400
                run(w, s, inp, 2)
                expect(w.web == nil).is(true)
                expect(#w.fading).is(0)
            end)
        end)

        test.group('home', function()
            test.case('walks to its corner, spins a web there, and rests facing out', function(expect)
                local w, s, inp = settled()
                inp.home = true
                run(w, s, inp, 9)
                expect(dist(s.x, s.y, 920, 80)).lessThan(6)
                local web = w.web
                expect(web ~= nil and web.progress >= 1).is(true)
                -- Out of the corner: down and to the left.
                local out = math.atan2(80 - 0, 920 - 1000)
                expect(math.abs(s.heading - out)).lessThan(0.1)
                -- It does not chase the pointer while home.
                inp.pointerX, inp.pointerY = 300, 600
                run(w, s, inp, 1)
                expect(dist(s.x, s.y, 920, 80)).lessThan(6)
            end)

            test.case('drops on a thread, swings with its legs held, and climbs back', function(expect)
                local w, s, inp = settled()
                inp.home = true
                run(w, s, inp, 9)
                local rest = s.heading
                will.startDrop(w, s)
                local lowest, sideways = 0, 0
                local legsMoved, offLine, sag = 0, 0, 0
                local reach = dist(s.legs[1].drawX, s.legs[1].drawY, s.x, s.y)
                run(w, s, inp, 2, function()
                    expect(s.frozen).is(true)
                    lowest = math.max(lowest, s.y - 80)
                    sideways = math.max(sideways, math.abs(s.x - 920))
                    legsMoved = math.max(legsMoved, math.abs(dist(s.legs[1].drawX, s.legs[1].drawY, s.x, s.y) - reach))
                    -- Hanging, it faces away from the hub: head down, its
                    -- abdomen and the thread above it.
                    if s.y - 80 > 60 then
                        -- Hanging free, its legs dangle.
                        expect(w.dangle).is(1)
                        local away = math.atan2(s.y - 80, s.x - 920)
                        offLine = math.max(offLine, math.abs(s.heading - away))
                        local web = w.web
                        if web then
                            local _, hy = silk.hub(web)
                            sag = math.max(sag, hy - 80)
                        end
                    end
                end)
                expect(lowest).greaterThan(200)
                -- The thread gives: it drops past where it hangs and bounces.
                expect(lowest - w.dropDepth).greaterThan(8)
                expect(sideways).greaterThan(4)
                expect(legsMoved).lessThan(0.01)
                expect(offLine).lessThan(0.05)
                -- Its weight pulls the web's hub down.
                expect(sag).greaterThan(3)
                run(w, s, inp, 4)
                expect(s.frozen).is(false)
                expect(dist(s.x, s.y, 920, 80)).lessThan(2)
                expect(math.abs(s.heading - rest)).lessThan(0.05)
                expect(w.dangle).is(0)
            end)

            test.case('a click nearby makes it flinch and climb straight back', function(expect)
                local w, s, inp = settled()
                inp.home = true
                run(w, s, inp, 9)
                will.startDrop(w, s)
                run(w, s, inp, 1)
                expect(s.y - 80).greaterThan(20)
                will.poke(w, s, s.x + 30, s.y + 20)
                expect(w.flinched).is(true)
                run(w, s, inp, 0.5)
                expect(dist(s.x, s.y, 920, 80)).lessThan(2)
                -- Far away, a click is ignored.
                will.poke(w, s, 100, 600)
                expect(w.flinched).is(false)
            end)

            test.case('hides while a window is dragged, and comes out after', function(expect)
                local w, s, inp = settled()
                inp.home = true
                run(w, s, inp, 9)
                inp.dragging = true
                run(w, s, inp, 0.6)
                expect(w.hiding).greaterThan(0.8)
                inp.dragging = false
                run(w, s, inp, 1)
                expect(w.hiding).lessThan(0.2)
            end)

            test.case('called back, it leaves the web to fade and follows again', function(expect)
                local w, s, inp = settled()
                inp.home = true
                run(w, s, inp, 9)
                inp.home = false
                run(w, s, inp, 4)
                expect(w.web == nil).is(true)
                expect(#w.fading).is(0)
                expect(math.abs(dist(s.x, s.y, 500, 400) - rig.headReach)).lessThan(6)
            end)
        end)

        test.group('grab', function()
            test.case('holds on to a dragged window and moves with it, then lets go', function(expect)
                local w, s, inp = settled()
                inp.dragging = true
                local x0 = s.x
                run(w, s, inp, 0.5, function()
                    inp.pointerX += 4
                    inp.pointerY += math.sin(inp.pointerX) * 3
                end)
                -- One frame to take hold, then it rides along.
                expect(s.x - x0).greaterThan(4 * 28)
                expect(w.grabbing).is(true)
                inp.dragging = false
                will.step(w, s, inp, DT)
                expect(w.released).is(true)
                expect(s.frozen).is(false)
            end)

            test.case('a drag far from the spider is not its business', function(expect)
                local w, s, inp = settled()
                inp.dragging = true
                inp.pointerX, inp.pointerY = 900, 100
                will.step(w, s, inp, DT)
                expect(w.grabbing).is(false)
            end)
        end)
    end
end
