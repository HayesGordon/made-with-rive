-- The legs as the scene's bones draw them, for the gait. scene_test.py checks
-- the hips and reach match the bones, and viewSize the Spider artboard.
-- Spider space: facing +x, y down, so left legs have negative y.
export type LegRig = {
    name: string, side: number, group: number,
    hipX: number, hipY: number, restX: number, restY: number,
    reach: number,
}

local legs: { LegRig } = {
    { name = "L1", side = -1, group = 0, hipX = 9.1925, hipY = -7.0707, restX = 49.0297, restY = -30.0707, reach = 67 },
    { name = "L2", side = -1, group = 1, hipX = 3.7082, hipY = -10.4616, restX = 16.0689, restY = -48.5039, reach = 58 },
    { name = "L3", side = -1, group = 0, hipX = -3.3076, hipY = -10.5739, restX = -18.2919, restY = -47.6612, reach = 58 },
    { name = "L4", side = -1, group = 1, hipX = -9.1925, hipY = -7.0707, restX = -44.5104, restY = -25.8495, reach = 64 },
    { name = "R1", side = 1, group = 1, hipX = 9.1925, hipY = 7.0707, restX = 49.0297, restY = 30.0707, reach = 67 },
    { name = "R2", side = 1, group = 0, hipX = 3.7082, hipY = 10.4616, restX = 16.0689, restY = 48.5039, reach = 58 },
    { name = "R3", side = 1, group = 1, hipX = -3.3076, hipY = 10.5739, restX = -18.2919, restY = 47.6612, reach = 58 },
    { name = "R4", side = 1, group = 0, hipX = -9.1925, hipY = 7.0707, restX = -44.5104, restY = 25.8495, reach = 64 },
}

return {
    legs = legs,
    headReach = 44,
    viewSize = 448,
    width = 1100,
    height = 720,
}
