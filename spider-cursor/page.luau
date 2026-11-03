-- Silkworks is a host for the spider, like Desktop and the macOS overlay:
-- it passes the pointer on to the spider's view model in the page's space,
-- and how far the catches list scrolled (its offset, written back by the
-- list, so drags and trackpad gestures count alike), tells the spider where home is (the page's top right
-- corner, wherever that is as the page reflows), and lets the sticky note
-- be dragged by its strip, telling the spider while that happens. The
-- page's buttons are listeners in its state machine; the few that need
-- arithmetic fire triggers this counts.

local stage = require('stage')

-- How long the list must rest before a lifted gesture is over.
local REST = 0.1
-- How long Silk waits before a nap when naps are on.
local NAP_AFTER = 10
-- The naps switch: where its knob sits off and on, and its track colours.
local KNOB_OFF, KNOB_ON = 3, 23
local TRACK_OFF = Color.rgba(214, 206, 232, 255)
local TRACK_ON = Color.rgba(109, 74, 255, 255)

type Page = {
    pointerX: Property<number>?,
    pointerY: Property<number>?,
    scrollY: Property<number>?,
    scrollEnd: PropertyTrigger?,
    dragging: Property<boolean>?,
    home: { [string]: Property<number> },
    -- The list's offset as last passed on; whether it moved since the
    -- last press, and whether the fingers lifted off a drag of it, after
    -- which its glide is not the spider's to follow; how long it has
    -- rested.
    listAt: number,
    scrolled: boolean,
    lifted: boolean,
    still: number,
    noteX: Property<number>?,
    noteY: Property<number>?,
    -- The page's size, from resize, and whether the note has been dragged:
    -- until it is, it keeps to the bottom right corner as the page resizes.
    w: number,
    h: number,
    moved: boolean,
    -- Where the pointer was when the note last moved, while dragging it.
    grabX: number?,
    grabY: number?,
}

local function count(vm: ViewModel, trigger: string, number: string)
    local t = vm:getTrigger(trigger)
    local n = vm:getNumber(number)
    if t and n then
        t:addListener(function()
            n.value += 1
        end)
    end
end

local function place(self: Page)
    local hubX, hubY, cornerX, cornerY = stage.home(self.w)
    local spots: { [string]: number } = { homeX = hubX, homeY = hubY, cornerX = cornerX, cornerY = cornerY }
    for name, value in spots do
        local p = self.home[name]
        if p then
            p.value = value
        end
    end
    local nx, ny = self.noteX, self.noteY
    if nx and ny then
        if self.moved then
            nx.value, ny.value = stage.clampNote(nx.value, ny.value, self.w, self.h)
        else
            nx.value, ny.value = stage.notePlace(self.w, self.h)
        end
    end
end

function init(self: Page, context: Context): boolean
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
    self.pointerX = s:getNumber('pointerX')
    self.pointerY = s:getNumber('pointerY')
    self.scrollY = s:getNumber('scrollY')
    self.scrollEnd = s:getTrigger('scrollEnd')
    self.dragging = s:getBoolean('dragging')
    for _, name in { 'homeX', 'homeY', 'cornerX', 'cornerY' } do
        local p = s:getNumber(name)
        if p then
            self.home[name] = p
        end
    end
    local list = vm:getNumber('listScroll')
    if list then
        self.listAt = list.value
        list:addListener(function()
            local dy = list.value - self.listAt
            self.listAt = list.value
            self.still = 0
            if self.lifted or dy == 0 then
                return
            end
            self.scrolled = true
            if self.scrollY then
                self.scrollY.value += dy
            end
        end)
    end
    self.noteX = vm:getNumber('noteX')
    self.noteY = vm:getNumber('noteY')
    count(vm, 'catchFly', 'flies')
    count(vm, 'spinWeb', 'webs')
    count(vm, 'pat', 'pats')

    local naps = vm:getTrigger('toggleNaps')
    local knob = vm:getNumber('napsKnob')
    local track = vm:getColor('napsTrack')
    local sleepAfter = s:getNumber('sleepAfter')
    if naps and knob and track and sleepAfter then
        naps:addListener(function()
            local on = sleepAfter.value <= 0
            sleepAfter.value = if on then NAP_AFTER else 0
            knob.value = if on then KNOB_ON else KNOB_OFF
            track.value = if on then TRACK_ON else TRACK_OFF
        end)
    end
    if self.w > 0 then
        place(self)
    end
    return true
end

function advance(self: Page, seconds: number): boolean
    self.still += seconds
    if self.lifted and self.still > REST then
        self.lifted = false
    end
    return true
end

function resize(self: Page, size: Vector, scale: number)
    self.w, self.h = size.x, size.y
    place(self)
end

-- A fill-sized ScriptedLayout gets every move in the page's coordinates,
-- drags included.
function pointerMove(self: Page, event: PointerEvent)
    local x, y = event.position.x, event.position.y
    if self.pointerX and self.pointerY then
        self.pointerX.value = x
        self.pointerY.value = y
    end
    local gx, gy = self.grabX, self.grabY
    local nx, ny = self.noteX, self.noteY
    if gx and gy and nx and ny then
        nx.value, ny.value = stage.clampNote(nx.value + x - gx, ny.value + y - gy, self.w, self.h)
        self.grabX, self.grabY = x, y
        self.moved = true
        if self.dragging and not self.dragging.value then
            self.dragging.value = true
        end
    end
end

-- Pressing the note's strip picks it up. Never claimed, so the press
-- listeners still play the spider's press.
function pointerDown(self: Page, event: PointerEvent)
    self.scrolled = false
    local nx, ny = self.noteX, self.noteY
    if nx and ny and stage.inGrip(event.position.x, event.position.y, nx.value, ny.value) then
        self.grabX, self.grabY = event.position.x, event.position.y
    end
end

-- Letting go of a drag of the list lifts the spider's fingers.
function pointerUp(self: Page, event: PointerEvent)
    self.grabX, self.grabY = nil, nil
    if self.scrolled and self.scrollEnd then
        self.scrolled = false
        self.lifted = true
        self.scrollEnd:fire()
    end
    if self.dragging and self.dragging.value then
        self.dragging.value = false
    end
end

return function(context: Context): Layout<Page>
    return {
        pointerX = nil,
        pointerY = nil,
        scrollY = nil,
        scrollEnd = nil,
        dragging = nil,
        home = {},
        listAt = 0,
        scrolled = false,
        lifted = false,
        still = 0,
        noteX = nil,
        noteY = nil,
        w = 0,
        h = 0,
        moved = false,
        grabX = nil,
        grabY = nil,
        init = init,
        advance = advance,
        resize = resize,
        pointerMove = pointerMove,
        pointerDown = pointerDown,
        pointerUp = pointerUp,
    }
end
