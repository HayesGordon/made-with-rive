-- Pointer in, view model out. gait.luau walks, life.luau decides what
-- happens in between, will.luau what the spider wants (play, home, holding
-- on to a dragged window), and silk.luau lays its silk, which this draws
-- under the spider. A host (Desktop, the macOS overlay) sets the pointer,
-- presses and scrolls in its own space. The markup binds the body, the abdomen's sway, the
-- pupils and the eight IK targets to the numbers written here; the blinks,
-- squint, breathing and sleep are timelines the state machine plays from the
-- triggers, booleans and numbers written here.

local body = require('body')
local gait = require('gait')
local life = require('life')
local frame = require('frame')
local rig = require('rig')
local silk = require('silk')
local will = require('will')

-- How far a fully tucked foot is drawn towards its hip. The sleep timelines
-- key how far tucked (the Tuck knob, 0 to 1).
local TUCK = 0.3
-- How far a hanging spider's feet droop.
local DANGLE = 12
-- Where the silk comes from, in spider space: the tip of the abdomen, which
-- turns about the waist.
local WAIST = -11
local SPINNERET = -37
-- Silk, light with a faint dark edge so it shows on light and dark pages.
local SILK = Color.rgba(246, 244, 255, 245)
local SILK_EDGE = Color.rgba(30, 20, 50, 64)
local SILK_WIDTH = 0.9
local SILK_EDGE_WIDTH = 2.2
-- The thread it hangs from carries its weight: thicker.
local HANG_WIDTH = 2
type Feet = { { x: Property<number>, y: Property<number> } }

type Brain = {
    spider: gait.Spider,
    life: life.Life,
    body: body.Body,
    will: will.Will,
    -- This frame's origin and spinneret, for draw.
    ox: number,
    oy: number,
    spinX: number,
    spinY: number,
    paths: { Path },
    silkPaint: Paint,
    edgePaint: Paint,
    home: Property<boolean>?,
    homeX: Property<number>?,
    homeY: Property<number>?,
    cornerX: Property<number>?,
    cornerY: Property<number>?,
    dragging: Property<boolean>?,
    grooming: Property<boolean>?,
    bodyX: Property<number>?,
    bodyY: Property<number>?,
    bodyRot: Property<number>?,
    abdomenRot: Property<number>?,
    abdomenSurge: Property<number>?,
    bodyScale: Property<number>?,
    puff: PropertyTrigger?,
    puffX: Property<number>?,
    puffY: Property<number>?,
    pupilX: Property<number>?,
    pupilY: Property<number>?,
    blinkLeft: PropertyTrigger?,
    blinkRight: PropertyTrigger?,
    squint: Property<boolean>?,
    asleep: Property<boolean>?,
    exertion: Property<number>?,
    tuck: Property<number>?,
    sleepAfter: Property<number>?,
    agent: Property<string>?,
    viewSize: Property<number>?,
    originX: Property<number>?,
    originY: Property<number>?,
    feet: Feet,
}

function init(self: Brain, context: Context): boolean
    -- init runs twice and the view model is absent the first time.
    local vm = context:viewModel()
    if vm == nil then
        return true
    end
    self.bodyX = vm:getNumber('bodyX')
    self.bodyY = vm:getNumber('bodyY')
    self.bodyRot = vm:getNumber('bodyRot')
    self.abdomenRot = vm:getNumber('abdomenRot')
    self.abdomenSurge = vm:getNumber('abdomenSurge')
    self.bodyScale = vm:getNumber('bodyScale')
    self.puff = vm:getTrigger('puff')
    self.puffX = vm:getNumber('puffX')
    self.puffY = vm:getNumber('puffY')
    self.pupilX = vm:getNumber('pupilX')
    self.pupilY = vm:getNumber('pupilY')
    self.blinkLeft = vm:getTrigger('blinkLeft')
    self.blinkRight = vm:getTrigger('blinkRight')
    self.squint = vm:getBoolean('squint')
    self.asleep = vm:getBoolean('asleep')
    self.exertion = vm:getNumber('exertion')
    self.tuck = vm:getNumber('tuck')
    self.sleepAfter = vm:getNumber('sleepAfter')
    self.agent = vm:getEnum('agent')
    self.viewSize = vm:getNumber('viewSize')
    self.originX = vm:getNumber('originX')
    self.originY = vm:getNumber('originY')
    self.home = vm:getBoolean('home')
    self.homeX = vm:getNumber('homeX')
    self.homeY = vm:getNumber('homeY')
    self.cornerX = vm:getNumber('cornerX')
    self.cornerY = vm:getNumber('cornerY')
    self.dragging = vm:getBoolean('dragging')
    self.grooming = vm:getBoolean('grooming')
    local px = vm:getNumber('pointerX')
    local py = vm:getNumber('pointerY')
    if px and py then
        local function follow()
            gait.setPointer(self.spider, px.value, py.value)
        end
        px:addListener(follow)
        py:addListener(follow)
    end
    -- Scrolling, as running totals of content travel.
    local sx = vm:getNumber('scrollX')
    local sy = vm:getNumber('scrollY')
    if sx and sy then
        local lastX, lastY = sx.value, sy.value
        local function scrolled()
            gait.scroll(self.spider, sx.value - lastX, sy.value - lastY)
            lastX, lastY = sx.value, sy.value
        end
        sx:addListener(scrolled)
        sy:addListener(scrolled)
    end
    local ended = vm:getTrigger('scrollEnd')
    if ended then
        ended:addListener(function()
            gait.scrollEnd(self.spider)
        end)
    end
    self.feet = {}
    for i = 0, #rig.legs - 1 do
        local x = vm:getNumber(`foot{i}x`)
        local y = vm:getNumber(`foot{i}y`)
        if x and y then
            table.insert(self.feet, { x = x, y = y })
        end
    end
    -- At home a click is not the spider's to press, but one close by gives
    -- it a fright; nor can it press while holding on to a window.
    local function press(side: number)
        local s, w = self.spider, self.will
        if w.mode == 'home' then
            will.poke(w, s, s.pointerX, s.pointerY)
        elseif not s.frozen then
            gait.press(s, side)
        end
    end
    local left = vm:getTrigger('pressLeft')
    if left then
        left:addListener(function()
            press(-1)
        end)
    end
    local right = vm:getTrigger('pressRight')
    if right then
        right:addListener(function()
            press(1)
        end)
    end
    return true
end

function advance(self: Brain, seconds: number): boolean
    local s = self.spider
    -- A stalled frame should not fling the spider across the screen.
    local dt = math.min(seconds, 1 / 20)
    local l = self.life
    local w = self.will
    local b = self.body
    -- The agent modes are the timelines'; the spider only has to stay awake
    -- for them, and wake up when it is needed.
    local mode = if self.agent then self.agent.value else 'idle'
    local agentBusy = mode == 'thinking' or mode == 'working' or mode == 'needsYou'
    if w.flinched then
        body.fright(b)
    end
    local x0, y0 = s.x, s.y
    will.step(w, s, {
        pointerX = s.pointerX,
        pointerY = s.pointerY,
        home = if self.home then self.home.value else false,
        hubX = if self.homeX then self.homeX.value else 0,
        hubY = if self.homeY then self.homeY.value else 0,
        cornerX = if self.cornerX then self.cornerX.value else 0,
        cornerY = if self.cornerY then self.cornerY.value else 0,
        dragging = if self.dragging then self.dragging.value else false,
        asleep = l.asleep,
        free = not agentBusy and s.scrollLevel == 0 and s.press == nil,
    }, dt)
    gait.step(s, dt)
    b.holding = w.grabbing
    b.carryX, b.carryY = s.x - x0, s.y - y0
    b.hiding = w.hiding
    body.step(b, s, dt)
    if self.sleepAfter then
        l.sleepAfter = if self.sleepAfter.value > 0 then self.sleepAfter.value else math.huge
    end
    local busy = s.scrollLevel > 0 or agentBusy or w.alert or w.grabbing
    -- Its front legs are taken while it grooms or holds on, so no taps.
    local legsBusy = s.press ~= nil or w.grooming or s.frozen
    life.step(l, dt, math.sqrt(s.vx * s.vx + s.vy * s.vy), s.turnRate, legsBusy, busy)
    if self.grooming and self.grooming.value ~= w.grooming then
        self.grooming.value = w.grooming
    end

    -- The artboard is a small view centred on the spider: draw relative to
    -- its top left and tell the host where that is. Written in this advance,
    -- so the bound nodes and the origin the host reads afterwards agree on
    -- the same frame.
    local size = if self.viewSize then self.viewSize.value else frame.SIZE
    local ox, oy = frame.origin(s.x, s.y, size)
    if w.mode == 'home' and w.homePhase ~= 'travel' and self.homeX and self.homeY and self.cornerX and self.cornerY then
        ox, oy = frame.home(self.homeX.value, self.homeY.value, self.cornerX.value, self.cornerY.value, size)
    end
    if self.originX then
        self.originX.value = ox
    end
    if self.originY then
        self.originY.value = oy
    end

    -- The weight shift moves the body over planted feet; the IK bends the
    -- knees to suit.
    local c, n = math.cos(s.heading), math.sin(s.heading)
    -- Sitting back to scroll does the same.
    local bx = s.x + s.leanX + (b.lean + l.shiftX) * c - l.shiftY * n + b.jiggleX
    local by = s.y + s.leanY + (b.lean + l.shiftX) * n + l.shiftY * c + b.jiggleY
    if self.bodyX then
        self.bodyX.value = bx - ox
    end
    if self.bodyY then
        self.bodyY.value = by - oy
    end
    -- Silk comes from the tip of the abdomen, wherever the springs put it.
    local a = s.heading + b.sway
    self.ox, self.oy = ox, oy
    self.spinX = bx + WAIST * c + (SPINNERET + b.surge) * math.cos(a)
    self.spinY = by + WAIST * n + (SPINNERET + b.surge) * math.sin(a)
    if self.bodyRot then
        self.bodyRot.value = s.heading
    end
    if self.abdomenRot then
        self.abdomenRot.value = b.sway
    end
    if self.abdomenSurge then
        self.abdomenSurge.value = b.surge
    end
    if self.bodyScale then
        self.bodyScale.value = 1 - b.dip - b.squat
    end
    -- A pressing foot kicks up dust where it lands.
    if s.touched and self.puff then
        if self.puffX and self.puffY then
            self.puffX.value = s.touchX - ox
            self.puffY.value = s.touchY - oy
        end
        self.puff:fire()
    end
    local px, py = gait.gaze(s, 2)
    px += (l.gazeX * 2 - px) * l.gazeWeight
    py += (l.gazeY * 2 - py) * l.gazeWeight
    if self.pupilX then
        self.pupilX.value = px
    end
    if self.pupilY then
        self.pupilY.value = py
    end
    -- The decisions the state machine plays timelines for.
    if l.blinkedL and self.blinkLeft then
        self.blinkLeft:fire()
    end
    if l.blinkedR and self.blinkRight then
        self.blinkRight:fire()
    end
    if self.squint and self.squint.value ~= l.squinting then
        self.squint.value = l.squinting
    end
    if self.asleep and self.asleep.value ~= l.asleep then
        self.asleep.value = l.asleep
    end
    if self.exertion then
        self.exertion.value = l.exertion * 100
    end
    -- Hanging on a thread or hiding, it draws its legs in too.
    local tuck = if self.tuck then self.tuck.value else 0
    tuck = math.max(tuck, w.hiding, w.dangle * 0.6)
    local tapping = if l.tapSide ~= 0 then gait.frontLeg(s, l.tapSide) else 0
    for i, foot in self.feet do
        local leg = s.legs[i]
        local x, y = leg.drawX, leg.drawY
        if i == tapping and leg.t < 0 and s.press == nil and s.scrollLevel == 0 then
            y -= l.tapLift
        end
        if tuck > 0 and (leg.t < 0 or s.frozen) then
            -- Asleep, the legs draw in towards the body.
            local hx, hy = gait.hipWorld(s, leg)
            x += (hx - x) * TUCK * tuck
            y += (hy - y) * TUCK * tuck
        end
        -- Hanging free, its feet droop.
        y += DANGLE * w.dangle
        foot.x.value = x - ox
        foot.y.value = y - oy
    end
    return true
end

local function line(path: Path, x1: number, y1: number, x2: number, y2: number)
    path:moveTo(Vector.xy(x1, y1))
    path:lineTo(Vector.xy(x2, y2))
end

-- The silk, under the spider: its webs, and the thread it hangs from.
function draw(self: Brain, renderer: Renderer)
    local ox, oy = self.ox, self.oy
    local w = self.will
    local paths = self.paths
    for _, p in paths do
        p:reset()
    end
    local function stroke(path: Path, opacity: number, width: number)
        local edge = self.edgePaint
        edge.color = Color.opacity(SILK_EDGE, Color.opacity(SILK_EDGE) * opacity)
        edge.thickness = width + SILK_EDGE_WIDTH - SILK_WIDTH
        renderer:drawPath(path, edge)
        local paint = self.silkPaint
        paint.color = Color.opacity(SILK, Color.opacity(SILK) * opacity)
        paint.thickness = width
        renderer:drawPath(path, paint)
    end
    local used = 0
    local function nextPath(): Path
        used += 1
        if paths[used] == nil then
            paths[used] = Path.new()
        end
        return paths[used]
    end

    local webs = table.clone(w.fading)
    if w.web then
        table.insert(webs, w.web)
    end
    for _, web in webs do
        local path = nextPath()
        for _, sg in silk.segments(web) do
            line(path, sg.x1 - ox, sg.y1 - oy, sg.x2 - ox, sg.y2 - oy)
        end
        stroke(path, web.opacity, SILK_WIDTH)
    end

    local web = w.web
    if w.hanging and web then
        local path = nextPath()
        local hx, hy = silk.hub(web)
        line(path, hx - ox, hy - oy, self.spinX - ox, self.spinY - oy)
        stroke(path, 1, HANG_WIDTH)
    end

end

return function(context: Context): Layout<Brain>
    return {
        spider = gait.new(rig.width / 2, rig.height / 2 + 40, -math.pi / 2),
        life = life.new(7),
        body = body.new(),
        will = will.new(11),
        ox = 0,
        oy = 0,
        spinX = 0,
        spinY = 0,
        paths = {},
        silkPaint = Paint.with({ style = 'stroke', thickness = SILK_WIDTH, cap = 'round', join = 'round', color = SILK }),
        edgePaint = Paint.with({ style = 'stroke', thickness = SILK_EDGE_WIDTH, cap = 'round', join = 'round', color = SILK_EDGE }),
        home = nil,
        homeX = nil,
        homeY = nil,
        cornerX = nil,
        cornerY = nil,
        dragging = nil,
        grooming = nil,
        bodyX = nil,
        bodyY = nil,
        bodyRot = nil,
        abdomenRot = nil,
        abdomenSurge = nil,
        bodyScale = nil,
        puff = nil,
        puffX = nil,
        puffY = nil,
        pupilX = nil,
        pupilY = nil,
        blinkLeft = nil,
        blinkRight = nil,
        squint = nil,
        asleep = nil,
        exertion = nil,
        tuck = nil,
        sleepAfter = nil,
        agent = nil,
        viewSize = nil,
        originX = nil,
        originY = nil,
        feet = {},
        init = init,
        advance = advance,
        draw = draw,
    }
end
