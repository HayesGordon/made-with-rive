-- Framing: the Spider artboard is a small view that moves with the spider
-- through the host's space. The view is SIZE square, centred on the
-- body each frame; the spider is drawn relative to its top left.

local rig = require('rig')

local M = {}

-- Big enough for the legs at full stretch, a press at the pointer and the
-- rim, with the body moving at sprint speed. The Spider artboard's size.
M.SIZE = rig.viewSize

-- The view's top left, in the spider's space. Whole points, so the art does
-- not shimmer as the view moves by fractions of a pixel.
function M.origin(x: number, y: number, size: number): (number, number)
    return math.floor(x - size / 2 + 0.5), math.floor(y - size / 2 + 0.5)
end

-- At home the view holds still in the corner, its own corner on the
-- screen's, so the web, the hub and a full drop below it are all in view and
-- nothing drawn on the web moves with the spider.
function M.home(hubX: number, hubY: number, cornerX: number, cornerY: number, size: number): (number, number)
    local x = if cornerX > hubX then cornerX - size else cornerX
    local y = if cornerY > hubY then cornerY - size else cornerY
    return math.floor(x + 0.5), math.floor(y + 0.5)
end

return M
