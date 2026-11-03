-- Desktop is a host for the spider, like the macOS overlay: it passes the
-- pointer and scrolls on to the spider's view model, in Desktop's space.
-- Presses are listeners in Desktop's state machine. It also tells the
-- spider where home is (the top right corner), and lets the window be
-- dragged by its title bar, telling the spider while that happens.

local rig = require('rig')

-- The title bar, in Desktop's space before any drag.
local TITLE_LEFT, TITLE_TOP, TITLE_RIGHT, TITLE_BOTTOM = 100, 70, 1000, 114
-- The spider's web hangs this far in from the corner.
local HOME_INSET = 84

type Host = {
    pointerX: Property<number>?,
    pointerY: Property<number>?,
    scrollX: Property<number>?,
    scrollY: Property<number>?,
    scrollEnd: PropertyTrigger?,
    windowX: Property<number>?,
    windowY: Property<number>?,
    dragging: Property<boolean>?,
    -- Where the pointer was when the window last moved, while dragging.
    grabX: number?,
    grabY: number?,
}

function init(self: Host, context: Context): boolean
    -- init runs twice and the view model is absent the first time.
    local vm = context:viewModel()
    if vm == nil then
        return true
    end
    local spider = vm:getViewModel('spider')
    if spider == nil then
        return true
    end
    local s = spider.value
    self.windowX = vm:getNumber('windowX')
    self.windowY = vm:getNumber('windowY')
    self.dragging = s:getBoolean('dragging')
    local home: { [string]: number } = {
        homeX = rig.width - HOME_INSET,
        homeY = HOME_INSET,
        cornerX = rig.width,
        cornerY = 0,
    }
    for name, value in home do
        local p = s:getNumber(name)
        if p then
            p.value = value
        end
    end
    self.pointerX = s:getNumber('pointerX')
    self.pointerY = s:getNumber('pointerY')
    self.scrollX = s:getNumber('scrollX')
    self.scrollY = s:getNumber('scrollY')
    self.scrollEnd = s:getTrigger('scrollEnd')
    return true
end

-- A fill-sized ScriptedLayout gets every move in artboard coordinates,
-- drags included.
function pointerMove(self: Host, event: PointerEvent)
    local x, y = event.position.x, event.position.y
    if self.pointerX and self.pointerY then
        self.pointerX.value = x
        self.pointerY.value = y
    end
    local gx, gy = self.grabX, self.grabY
    if gx and gy and self.windowX and self.windowY then
        self.windowX.value += x - gx
        self.windowY.value += y - gy
        self.grabX, self.grabY = x, y
        if self.dragging and not self.dragging.value then
            self.dragging.value = true
        end
    end
end

-- Pressing the title bar picks the window up. Never claimed, so the press
-- listeners still play the spider's press.
function pointerDown(self: Host, event: PointerEvent)
    local wx = if self.windowX then self.windowX.value else 0
    local wy = if self.windowY then self.windowY.value else 0
    local x, y = event.position.x - wx, event.position.y - wy
    if x >= TITLE_LEFT and x <= TITLE_RIGHT and y >= TITLE_TOP and y <= TITLE_BOTTOM then
        self.grabX, self.grabY = event.position.x, event.position.y
    end
end

function pointerUp(self: Host, event: PointerEvent)
    self.grabX, self.grabY = nil, nil
    if self.dragging and self.dragging.value then
        self.dragging.value = false
    end
end

-- Scrolling anywhere over the artboard, as running totals of content travel.
-- Never claimed, so whatever is under the pointer still scrolls.
function pointerScroll(self: Host, event: ScrollEvent)
    if event.phase == 'begin' or event.phase == 'update' then
        if self.scrollX and self.scrollY then
            self.scrollX.value += event.delta.x
            self.scrollY.value += event.delta.y
        end
    elseif event.phase == 'end' or event.phase == 'momentum' then
        -- The fingers lifted. Momentum is the page coasting after a flick,
        -- which the legs have already let go of; some hosts send it without
        -- an `end` first.
        if self.scrollEnd then
            self.scrollEnd:fire()
        end
    end
end

return function(context: Context): Layout<Host>
    return {
        pointerX = nil,
        pointerY = nil,
        scrollX = nil,
        scrollY = nil,
        scrollEnd = nil,
        windowX = nil,
        windowY = nil,
        dragging = nil,
        grabX = nil,
        grabY = nil,
        init = init,
        pointerMove = pointerMove,
        pointerDown = pointerDown,
        pointerUp = pointerUp,
        pointerScroll = pointerScroll,
    }
end
