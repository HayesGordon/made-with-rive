import AppKit

/// Side of the square Rive view the spider is shown through. Matches viewSize in
/// rig.luau, which the script's framing test checks the spider fits in.
let spiderViewSize: CGFloat = 448

/// Frame rates the menu offers. The highest is a ProMotion display's rate;
/// lower halves the spider's per-frame work.
let frameRates = [60, 120]

/// The frame rate to run at, from what UserDefaults holds (0 when unset).
func frameRate(saved: Int) -> Int {
    frameRates.contains(saved) ? saved : frameRates.last!
}

/// How far one line of a mouse wheel scrolls, in points.
let pointsPerScrollLine = 10

/// How far a scroll moves the content, in the spider's space, from AppKit's
/// `scrollingDeltaX/Y`. Those already follow the content, and the system's
/// natural scrolling setting; a content move up is negative in both.
func contentTravel(dx: CGFloat, dy: CGFloat, precise: Bool) -> CGVector {
    let scale = precise ? 1 : CGFloat(pointsPerScrollLine)
    return CGVector(dx: dx * scale, dy: dy * scale)
}

/// How long the spider does nothing before it naps, in seconds, as the menu
/// offers them; 0 is never.
let sleepDelays = [10, 30, 60, 300, 0]

/// The sleep delay to use, from what UserDefaults holds (nil when unset).
func sleepDelay(saved: Int?) -> Int {
    if let saved, sleepDelays.contains(saved) {
        return saved
    }
    return sleepDelays[0]
}

/// A global mouse position (AppKit screen space: points, y up from the bottom
/// of the primary display) as a point in a view covering `screen`, with y
/// down: the spider's space.
func viewPoint(global: CGPoint, screen: CGRect) -> CGPoint {
    CGPoint(x: global.x - screen.minX, y: screen.maxY - global.y)
}

/// Sizes the menu offers, as points per unit of the spider's space. 1 is the
/// size it was drawn at.
let spiderScales: [Double] = [0.5, 0.75, 1, 1.5]

/// The size to show the spider at, from what UserDefaults holds (0 when
/// unset).
func spiderScale(saved: Double) -> Double {
    spiderScales.contains(saved) ? saved : 1
}

/// A point on the screen (points, y down) in the spider's space.
func spiderPoint(_ point: CGPoint, scale: CGFloat) -> CGPoint {
    CGPoint(x: point.x / scale, y: point.y / scale)
}

/// Where the spider's view goes in the overlay's content view: `origin` is its
/// top left in the spider's space, as the script reports it, and `size` its
/// side in the same units.
func viewFrame(origin: CGPoint, size: CGFloat, scale: CGFloat, containerHeight: CGFloat) -> CGRect {
    let side = size * scale
    return CGRect(x: origin.x * scale, y: containerHeight - origin.y * scale - side, width: side, height: side)
}

/// A borderless, transparent window over everything on `screen` that every
/// click goes straight through.
func makeOverlayWindow(screen: CGRect) -> NSWindow {
    let window = NSWindow(
        contentRect: screen,
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.ignoresMouseEvents = true
    // Over menus, the Dock and full-screen apps; only the real cursor is
    // drawn above it.
    window.level = .screenSaver
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    window.isReleasedWhenClosed = false
    return window
}

/// The spider's agent modes, as the scene's Agent enum keys them, with their
/// menu titles. The state machine plays a timeline for each.
let agentModes: [(key: String, title: String)] = [
    ("idle", "Idle"), ("thinking", "Thinking"), ("working", "Working"), ("needsYou", "Needs You"), ("done", "Done"),
]

/// The mode ctrl-option and a digit picks: 0 and 1 idle, then the rest in order.
func agentMode(digit: Int) -> String? {
    if digit == 0 { return agentModes[0].key }
    return (1...agentModes.count).contains(digit) ? agentModes[digit - 1].key : nil
}

/// The corners the spider can make its home in.
enum HomeCorner: String, CaseIterable {
    case topRight = "Top Right"
    case topLeft = "Top Left"
}

/// How far in from its corner the web's hub hangs, in the spider's units.
let homeInset: CGFloat = 84

/// Where the spider's home is, in its space: the corner of the screen under
/// the menu bar (`visible` is the screen's visible frame, `screen` its whole
/// frame, both in AppKit's space) and the hub of its web, inset from it.
func homeSpot(corner: HomeCorner, visible: CGRect, screen: CGRect, scale: CGFloat) -> (corner: CGPoint, hub: CGPoint) {
    let top = (screen.maxY - visible.maxY) / scale
    let x = (corner == .topRight ? visible.maxX - screen.minX : visible.minX - screen.minX) / scale
    let inward: CGFloat = corner == .topRight ? -1 : 1
    return (CGPoint(x: x, y: top), CGPoint(x: x + inward * homeInset, y: top + homeInset))
}

/// The window a press at `point` lands on (global display space: points, y
/// down from the top of the primary display), from `CGWindowListCopyWindowInfo`
/// front to back: the first ordinary window there that is not ours.
func windowUnder(_ point: CGPoint, windows: [[String: Any]], ownPID: pid_t) -> (id: Int, bounds: CGRect)? {
    for info in windows {
        guard (info[kCGWindowLayer as String] as? Int) == 0,
              (info[kCGWindowOwnerPID as String] as? Int).map({ pid_t($0) }) != ownPID,
              let id = info[kCGWindowNumber as String] as? Int,
              let dict = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: dict),
              bounds.contains(point)
        else { continue }
        return (id, bounds)
    }
    return nil
}

/// Whether a window moved: being dragged, rather than clicked.
func windowMoved(from: CGRect, to: CGRect) -> Bool {
    abs(from.minX - to.minX) > 0.5 || abs(from.minY - to.minY) > 0.5
}
