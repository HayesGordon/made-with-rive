local life = require('life')

local DT = 1 / 60

-- Steps a standing spider (speed 0, no turn, no press) unless told otherwise,
-- calling `each` after every frame.
local function run(l: life.Life, seconds: number, speed: number, each: (number) -> ())
    for i = 1, math.floor(seconds / DT + 0.5) do
        life.step(l, DT, speed, 0, false)
        each(i * DT)
    end
end

-- When each eye starts a blink. The blinks themselves are timelines; the
-- script only decides when, and which eye.
local function closings(l: life.Life, seconds: number): ({ number }, { number })
    local left, right = {}, {}
    run(l, seconds, 0, function(t)
        if l.blinkedL then
            table.insert(left, t)
        end
        if l.blinkedR then
            table.insert(right, t)
        end
    end)
    return left, right
end

return function(): Tests
    return function(test: Tester)
        test.group('blink', function()
            test.case('blinks every few seconds', function(expect)
                local l = life.new(7)
                l.sleepAfter = math.huge
                local left, right = closings(l, 60)
                expect(#left).greaterThan(8)
                expect(#left).lessThan(35)
                expect(#right).greaterThan(8)
                expect(#right).lessThan(35)
            end)

            test.case('sometimes one eye leads, from either side', function(expect)
                local l = life.new(3)
                l.sleepAfter = math.huge
                local left, right = closings(l, 180)
                local together, leftFirst, rightFirst = 0, 0, 0
                -- Each left closing against its nearest right one, so the
                -- two halves of a double blink do not pair up.
                for _, tl in left do
                    local gap = math.huge
                    for _, tr in right do
                        if math.abs(tr - tl) < math.abs(gap) then
                            gap = tr - tl
                        end
                    end
                    if math.abs(gap) < 0.02 then
                        together += 1
                    elseif gap > 0 and gap < 0.2 then
                        leftFirst += 1
                    elseif gap < 0 and gap > -0.2 then
                        rightFirst += 1
                    end
                end
                expect(together).greaterThan(5)
                expect(leftFirst).greaterThan(0)
                expect(rightFirst).greaterThan(0)
            end)

            test.case('a sharp turn makes it blink', function(expect)
                local l = life.new(1)
                -- Too soon for a blink of its own.
                local early = false
                run(l, 0.3, 0, function()
                    early = early or l.blinkedL or l.blinkedR
                end)
                expect(early).is(false)
                local left, right = false, false
                for _ = 1, 12 do
                    life.step(l, DT, 300, 9, false)
                    left = left or l.blinkedL
                    right = right or l.blinkedR
                end
                expect(left).is(true)
                expect(right).is(true)
            end)

            test.case('squints while pressing', function(expect)
                local l = life.new(1)
                life.step(l, DT, 0, 0, true)
                expect(l.squinting).is(true)
                life.step(l, DT, 0, 0, false)
                expect(l.squinting).is(false)
            end)
        end)

        test.group('sleep', function()
            test.case('falls asleep after the idle time and stops blinking', function(expect)
                local l = life.new(4)
                l.sleepAfter = 10
                run(l, 9.9, 0, function() end)
                expect(l.asleep).is(false)
                run(l, 0.2, 0, function() end)
                expect(l.asleep).is(true)
                local blinked = false
                run(l, 20, 0, function()
                    blinked = blinked or l.blinkedL or l.blinkedR
                end)
                expect(blinked).is(false)
            end)

            test.case('never sleeps when sleep is off', function(expect)
                local l = life.new(4)
                l.sleepAfter = math.huge
                local slept = false
                run(l, 60, 0, function()
                    slept = slept or l.asleep
                end)
                expect(slept).is(false)
            end)

            test.case('wakes the moment it moves, with a double blink', function(expect)
                local l = life.new(4)
                l.sleepAfter = 2
                run(l, 6, 0, function() end)
                expect(l.asleep).is(true)
                life.step(l, DT, 200, 0, false)
                expect(l.asleep).is(false)
                local left, right = 0, 0
                run(l, 0.7, 200, function()
                    left += if l.blinkedL then 1 else 0
                    right += if l.blinkedR then 1 else 0
                end)
                expect(left).is(2)
                expect(right).is(2)
            end)

            test.case('stays awake while busy, and being busy wakes it', function(expect)
                local l = life.new(4)
                l.sleepAfter = 2
                for _ = 1, 6 * 60 do
                    life.step(l, DT, 0, 0, false, true)
                end
                expect(l.asleep).is(false)
                run(l, 6, 0, function() end)
                expect(l.asleep).is(true)
                life.step(l, DT, 0, 0, false, true)
                expect(l.asleep).is(false)
            end)

            test.case('lies still asleep: no sway, glances or taps', function(expect)
                local l = life.new(5)
                l.sleepAfter = 2
                run(l, 6, 0, function() end)
                local busy = false
                run(l, 20, 0, function()
                    if math.abs(l.shiftX) + math.abs(l.shiftY) > 0.05 or l.gazeWeight > 0.01 or l.tapLift > 0.01 then
                        busy = true
                    end
                end)
                expect(busy).is(false)
            end)
        end)

        test.group('idle', function()
            test.case('standing still it shifts, glances around and taps a foot', function(expect)
                local l = life.new(5)
                l.sleepAfter = math.huge
                local shifted, glanced, tapped = false, false, false
                local most = 0
                run(l, 30, 0, function()
                    local d = math.sqrt(l.shiftX ^ 2 + l.shiftY ^ 2)
                    most = math.max(most, d)
                    shifted = shifted or d > 0.5
                    glanced = glanced or l.gazeWeight > 0.9
                    tapped = tapped or (l.tapLift > 2 and l.tapSide ~= 0)
                end)
                expect(shifted).is(true)
                expect(glanced).is(true)
                expect(tapped).is(true)
                -- Subtle: the feet are planted and the knees take it up.
                expect(most).lessThan(2.5)
            end)

            test.case('walking it does none of that', function(expect)
                local l = life.new(5)
                local busy = false
                run(l, 30, 200, function()
                    if math.abs(l.shiftX) + math.abs(l.shiftY) > 0.01 or l.gazeWeight > 0.01 or l.tapLift > 0.01 then
                        busy = true
                    end
                end)
                expect(busy).is(false)
            end)

            test.case('gets winded fast and gets its breath back slowly', function(expect)
                -- How the breathing looks is the timelines'; how winded the
                -- spider is, which they blend by, is the script's.
                local l = life.new(2)
                run(l, 2, 0, function() end)
                expect(l.exertion).is(0)
                run(l, 1, 900, function() end)
                expect(l.exertion).greaterThan(0.8)
                run(l, 1.5, 0, function() end)
                expect(l.exertion).greaterThan(0.3)
                run(l, 15, 0, function() end)
                expect(l.exertion).lessThan(0.05)
            end)
        end)
    end
end
