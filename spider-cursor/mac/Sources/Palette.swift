/// A colour scheme for the spider. Each key is a view model colour property
/// in the .riv; values are 0xAARRGGBB, as in the markup.
struct Palette {
    let name: String
    let colors: [String: UInt32]
}

/// The palette slots the scene binds, besides the rim.
let paletteSlots = ["ink", "leg", "bodyTop", "bodyBottom", "marks"]

let palettes: [Palette] = [
    Palette(name: "Grape", colors: [
        "ink": 0xFF170D30, "leg": 0xFF4E3390, "bodyTop": 0xFFA27CF0, "bodyBottom": 0xFF32246F, "marks": 0xFFFFB8E6,
    ]),
    Palette(name: "Tangerine", colors: [
        "ink": 0xFF2E0E08, "leg": 0xFFB8360E, "bodyTop": 0xFFFFC25C, "bodyBottom": 0xFFD93A1E, "marks": 0xFFFFF0B8,
    ]),
    Palette(name: "Lime", colors: [
        "ink": 0xFF0B2410, "leg": 0xFF2F7E22, "bodyTop": 0xFFE6FF6E, "bodyBottom": 0xFF3DA62C, "marks": 0xFFFAFFD6,
    ]),
    Palette(name: "Bubblegum", colors: [
        "ink": 0xFF2A0820, "leg": 0xFF9E1670, "bodyTop": 0xFFFF9FCC, "bodyBottom": 0xFFB81C78, "marks": 0xFFFFE6F3,
    ]),
    Palette(name: "Cyan", colors: [
        "ink": 0xFF06172E, "leg": 0xFF1462A8, "bodyTop": 0xFF9EFBFF, "bodyBottom": 0xFF1C7FD8, "marks": 0xFFEFFFFF,
    ]),
    Palette(name: "Gold", colors: [
        "ink": 0xFF2B1800, "leg": 0xFFA85F00, "bodyTop": 0xFFFFF08C, "bodyBottom": 0xFFE8870C, "marks": 0xFFFFF9DE,
    ]),
    Palette(name: "Black Widow", colors: [
        "ink": 0xFF000000, "leg": 0xFF1D1A28, "bodyTop": 0xFF4C4560, "bodyBottom": 0xFF0E0C18, "marks": 0xFFFF3B30,
    ]),
]

/// The rim colour, on or off.
func rimColor(_ on: Bool) -> UInt32 {
    on ? 0xFFFFFFFF : 0x00FFFFFF
}
