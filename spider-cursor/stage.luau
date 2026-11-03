-- The Silkworks page's geometry, for page.luau: where the spider's home is
-- and where the sticky note sits and can be dragged. The page reflows to
-- the window, so all of it is worked out from the page's size.

local M = {}

-- The spider's web hangs this far in from the top right corner.
M.INSET = 84
-- The sticky note, and the strip along its top that picks it up.
M.NOTE_W = 250
M.NOTE_H = 170
M.GRIP_H = 36
-- How far in from the page's edges it starts.
local NOTE_MARGIN = 40
-- How much of the note stays on the page when it is dragged off.
M.REACH = 60

-- The web's hub and the corner it is tied into.
function M.home(w: number): (number, number, number, number)
    return w - M.INSET, M.INSET, w, 0
end

-- The note starts in the bottom right corner, out of the web's way.
function M.notePlace(w: number, h: number): (number, number)
    return math.max(w - M.NOTE_W - NOTE_MARGIN, 0), math.max(h - M.NOTE_H - NOTE_MARGIN, 0)
end

-- The pointer at (px, py) is on the strip of a note at (nx, ny).
function M.inGrip(px: number, py: number, nx: number, ny: number): boolean
    return px >= nx and px < nx + M.NOTE_W and py >= ny and py < ny + M.GRIP_H
end

-- Where a note dragged to (x, y) may go: enough of its strip on the page to
-- pick it up again.
function M.clampNote(x: number, y: number, w: number, h: number): (number, number)
    return math.clamp(x, M.REACH - M.NOTE_W, w - M.REACH), math.clamp(y, 0, math.max(h - M.GRIP_H, 0))
end

return M
