local silk = require('silk')

local DT = 1 / 60

local function dist(ax: number, ay: number, bx: number, by: number): number
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

return function(): Tests
    return function(test: Tester)
        test.group('web', function()
            test.case('an orb web is spun spokes first, then the spiral, all within its reach', function(expect)
                local w = silk.orb(300, 300, 50, 3)
                local early = silk.segments(w)
                expect(#early).is(0)
                w.progress = 0.3
                local spokesOnly = silk.segments(w)
                expect(#spokesOnly).greaterThan(0)
                w.progress = 1
                local all = silk.segments(w)
                expect(#all).greaterThan(#spokesOnly * 3)
                for _, sg in all do
                    expect(dist(sg.x1, sg.y1, 300, 300)).lessThan(50 * 1.2)
                    expect(dist(sg.x2, sg.y2, 300, 300)).lessThan(50 * 1.2)
                end
            end)

            test.case('a corner web is tied to both edges of its corner', function(expect)
                -- Top right corner of a 1000-wide screen, hub in from it.
                local w = silk.corner(920, 80, 1000, 0, 5)
                w.progress = 1
                local onRight, onTop = 0, 0
                for _, sg in silk.segments(w) do
                    for _, p in { { sg.x1, sg.y1 }, { sg.x2, sg.y2 } } do
                        expect(p[1] <= 1000.01).is(true)
                        expect(p[2] >= -0.01).is(true)
                        if math.abs(p[1] - 1000) < 0.01 then
                            onRight += 1
                        end
                        if math.abs(p[2]) < 0.01 then
                            onTop += 1
                        end
                    end
                end
                expect(onRight).greaterThan(1)
                expect(onTop).greaterThan(1)
            end)

            test.case('pulled, the hub sags while the ties hold; let go, it wobbles back', function(expect)
                local w = silk.corner(920, 80, 1000, 0, 5)
                w.progress = 1
                local ties = {}
                for _, sg in silk.segments(w) do
                    if math.abs(sg.x2 - 1000) < 0.01 or math.abs(sg.y2) < 0.01 then
                        table.insert(ties, { sg.x2, sg.y2 })
                    end
                end
                for _ = 1, 60 do
                    silk.pull(w, 0, 1, DT)
                end
                local hx, hy = silk.hub(w)
                expect(hy - 80).greaterThan(4)
                expect(math.abs(hx - 920)).lessThan(0.5)
                -- The threads tied to the edges still end on them.
                local held = 0
                for _, sg in silk.segments(w) do
                    for _, t in ties do
                        if dist(sg.x2, sg.y2, t[1], t[2]) < 0.01 then
                            held += 1
                        end
                    end
                end
                expect(held).is(#ties)
                -- Let go, it springs up past where it rests, then settles.
                local highest = math.huge
                for _ = 1, 300 do
                    silk.pull(w, 0, 0, DT)
                    local _, y = silk.hub(w)
                    highest = math.min(highest, y)
                end
                expect(highest).lessThan(80 - 0.5)
                local _, y = silk.hub(w)
                expect(math.abs(y - 80)).lessThan(0.05)
            end)
        end)
    end
end
