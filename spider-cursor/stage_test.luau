local stage = require('stage')

return function(): Tests
    return function(test: Tester)
        test.group('stage', function()
            test.case('home is the top right corner, whatever the page width', function(expect)
                for _, w in { 1440, 900 } do
                    local hubX, hubY, cornerX, cornerY = stage.home(w)
                    expect(cornerX).is(w)
                    expect(cornerY).is(0)
                    expect(hubX).is(w - stage.INSET)
                    expect(hubY).is(stage.INSET)
                end
            end)

            test.case('the note starts on screen, clear of the web in the corner', function(expect)
                for _, size in { { 1440, 900 }, { 800, 600 } } do
                    local w, h = size[1], size[2]
                    local x, y = stage.notePlace(w, h)
                    expect(x >= 0 and x + stage.NOTE_W <= w).is(true)
                    expect(y >= 0 and y + stage.NOTE_H <= h).is(true)
                    expect(y).greaterThan(stage.INSET * 2)
                end
            end)

            test.case('only the note\'s title strip picks it up', function(expect)
                expect(stage.inGrip(110, 205, 100, 200)).is(true)
                expect(stage.inGrip(100 + stage.NOTE_W - 1, 200 + stage.GRIP_H - 1, 100, 200)).is(true)
                expect(stage.inGrip(110, 200 + stage.GRIP_H + 1, 100, 200)).is(false)
                expect(stage.inGrip(99, 205, 100, 200)).is(false)
            end)

            test.case('dragged off the page, the note keeps its strip in reach', function(expect)
                local w, h = 1000, 700
                for _, p in { { -5000, -5000 }, { 5000, 5000 } } do
                    local x, y = stage.clampNote(p[1], p[2], w, h)
                    -- Some of the strip is still on the page to grab.
                    expect(x + stage.NOTE_W).greaterThan(stage.REACH - 0.001)
                    expect(w - x).greaterThan(stage.REACH - 0.001)
                    expect(y >= 0 and y + stage.GRIP_H <= h).is(true)
                end
                local x, y = stage.clampNote(300, 200, w, h)
                expect(x).is(300)
                expect(y).is(200)
            end)
        end)
    end
end
