import AppKit
import RiveRuntime

// A plain executable: no XCTest, so it builds with swiftc alone. Exits 1 on
// the first failure.

var failures = 0

func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if !ok {
        print("FAIL line \(line): \(what)")
        failures += 1
    }
}

// Primary display, 1512x982 points.
let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
check(viewPoint(global: CGPoint(x: 0, y: 982), screen: primary) == CGPoint(x: 0, y: 0),
      "the top left of the screen is the view's origin")
check(viewPoint(global: CGPoint(x: 100, y: 900), screen: primary) == CGPoint(x: 100, y: 82),
      "y counts down from the top")

// A second display to the left of and above the primary one.
let left = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
check(viewPoint(global: CGPoint(x: -1920, y: 1280), screen: left) == CGPoint(x: 0, y: 0),
      "another display's top left is its own origin")
check(viewPoint(global: CGPoint(x: -20, y: 300), screen: left) == CGPoint(x: 1900, y: 980),
      "points on another display are relative to it")

// The spider's view: the script gives its top left with y down, AppKit
// wants the bottom left with y up.
check(viewFrame(origin: CGPoint(x: 100, y: 50), size: 288, scale: 1, containerHeight: 982)
        == CGRect(x: 100, y: 982 - 50 - 288, width: 288, height: 288),
      "the view's top left lands on the script's origin")
check(viewFrame(origin: CGPoint(x: -40, y: 900), size: 288, scale: 1, containerHeight: 982).minX == -40,
      "the view can hang off the screen's edge")
// At another size the spider's space is scaled: one unit is `scale` points.
check(viewFrame(origin: CGPoint(x: 100, y: 50), size: 288, scale: 0.5, containerHeight: 982)
        == CGRect(x: 50, y: 982 - 25 - 144, width: 144, height: 144),
      "a smaller spider's view is smaller and its origin scales")
check(spiderPoint(CGPoint(x: 300, y: 200), scale: 0.5) == CGPoint(x: 600, y: 400),
      "the pointer in a smaller spider's space is further out")
check(spiderScale(saved: 0) == 1 && spiderScale(saved: 0.75) == 0.75 && spiderScale(saved: 3) == 1,
      "the saved size, or full size when none or an unknown one is saved")

let window = makeOverlayWindow(screen: primary)
check(window.ignoresMouseEvents, "clicks go through the overlay")
check(!window.isOpaque && window.backgroundColor == .clear, "the overlay is transparent")
check(window.level >= .screenSaver, "the overlay is above menus and the Dock")
check(window.collectionBehavior.contains(.canJoinAllSpaces), "the overlay follows every Space")
check(window.collectionBehavior.contains(.fullScreenAuxiliary), "the overlay shows over full-screen apps")
check(window.frame == primary, "the overlay covers the screen")

// Palettes.
// The runtime's colour setter takes 0-1 channels and clamps anything above,
// whatever its header comment says, so 0-255 values paint white.
let c = channels(0x807A55B8)
check(c.red == 122.0 / 255 && c.green == 85.0 / 255 && c.blue == 184.0 / 255 && c.alpha == 128.0 / 255,
      "AARRGGBB splits into 0-1 channels")
check(Set(palettes.map(\.name)).count == palettes.count, "palette names are unique")
for palette in palettes {
    check(Set(palette.colors.keys) == Set(paletteSlots), "\(palette.name) sets exactly every slot")
}
check(channels(rimColor(false)).alpha == 0 && channels(rimColor(true)).alpha == 1, "the rim toggles visibility")

// Every slot the menu sets must be a colour the scene binds, or a palette
// silently does nothing. The scene's path is the first argument.
if let scenePath = CommandLine.arguments.dropFirst().first,
   let scene = try? String(contentsOfFile: scenePath, encoding: .utf8) {
    for slot in paletteSlots + ["rim"] {
        check(scene.contains("<ViewModelPropertyColor name=\"\(slot)\""), "the scene has a \(slot) colour")
    }
} else {
    check(false, "pass the path to scene.rml")
}

// The view the app shows must be the size the script's framing was tested at.
if let scenePath = CommandLine.arguments.dropFirst().first,
   let rig = try? String(contentsOfFile: (scenePath as NSString).deletingLastPathComponent + "/rig.luau", encoding: .utf8) {
    check(rig.contains("viewSize = \(Int(spiderViewSize)),"), "the app's view size matches rig.luau's viewSize")
} else {
    check(false, "rig.luau sits next to scene.rml")
}

// AppKit asks a view to update its tracking areas whenever it moves, which
// for the spider's view is every frame.
let spiderView = SpiderView()
for _ in 0..<10 {
    spiderView.updateTrackingAreas()
}
check(spiderView.trackingAreas.isEmpty, "moving the spider's view does not pile up tracking areas")

// Frame rate: a saved choice, or the display's full rate when none is saved
// (UserDefaults answers 0) or it is not one the menu offers.
check(frameRate(saved: 0) == 120, "no saved frame rate means 120")
check(frameRate(saved: 60) == 60, "a saved 60 sticks")
check(frameRate(saved: 37) == 120, "an unknown saved rate falls back to 120")

// Scrolling: AppKit's scrolling deltas already follow the content (natural
// scrolling or not), and a move up is negative as in the spider's space. A
// trackpad reports points, a wheel reports lines.
check(contentTravel(dx: 3, dy: -5, precise: true) == CGVector(dx: 3, dy: -5),
      "a trackpad's points pass straight through")
check(contentTravel(dx: 0, dy: 1, precise: false) == CGVector(dx: 0, dy: CGFloat(pointsPerScrollLine)),
      "a wheel's lines become points")

// Sleep: seconds of doing nothing before the spider naps, 0 for never.
// Nothing saved means the 10 s default, not never.
check(sleepDelay(saved: nil) == 10, "no saved sleep delay means 10 s")
check(sleepDelay(saved: 0) == 0, "a saved never sticks")
check(sleepDelay(saved: 60) == 60, "a saved delay sticks")
check(sleepDelay(saved: 7) == 10, "an unknown saved delay falls back to 10 s")

// Agent modes: ctrl-option and a digit, 0 and 1 idle, then the rest in
// order. Every mode must be a value of the scene's Agent enum, or setting it
// silently does nothing.
check(agentMode(digit: 0) == "idle" && agentMode(digit: 1) == "idle", "0 and 1 are idle")
check((2...5).map { agentMode(digit: $0) ?? "" } == ["thinking", "working", "needsYou", "done"], "2 to 5 are the other modes")
check(agentMode(digit: 6) == nil, "6 is no mode")
if let scenePath = CommandLine.arguments.dropFirst().first,
   let scene = try? String(contentsOfFile: scenePath, encoding: .utf8) {
    for (key, _) in agentModes {
        check(scene.contains("<DataEnumValue key=\"\(key)\""), "the scene has a \(key) mode")
    }
}

// Home: a web in a top corner of the screen, under the menu bar, hub inset
// from the corner, all in the spider's space.
let belowMenuBar = CGRect(x: 0, y: 70, width: 1512, height: 879)
let topRight = homeSpot(corner: .topRight, visible: belowMenuBar, screen: primary, scale: 1)
check(topRight.corner == CGPoint(x: 1512, y: 33), "the top right corner is under the menu bar")
check(topRight.hub == CGPoint(x: 1512 - homeInset, y: 33 + homeInset), "the hub hangs in from the top right")
let topLeft = homeSpot(corner: .topLeft, visible: belowMenuBar, screen: primary, scale: 1)
check(topLeft.corner == CGPoint(x: 0, y: 33) && topLeft.hub == CGPoint(x: homeInset, y: 33 + homeInset),
      "the top left corner and its hub")
let small = homeSpot(corner: .topRight, visible: belowMenuBar, screen: primary, scale: 0.5)
check(small.corner == CGPoint(x: 3024, y: 66) && small.hub == CGPoint(x: 3024 - homeInset, y: 66 + homeInset),
      "a smaller spider's home is in its own space, the inset in its own units")

// A drag is a window moving under the pointer: the window a press lands on
// is the frontmost ordinary window there that is not the overlay.
let windows: [[String: Any]] = [
    [kCGWindowLayer as String: 25, kCGWindowOwnerPID as String: 7, kCGWindowNumber as String: 1,
     kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": 1512, "Height": 33]],
    [kCGWindowLayer as String: 0, kCGWindowOwnerPID as String: 99, kCGWindowNumber as String: 2,
     kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": 1512, "Height": 982]],
    [kCGWindowLayer as String: 0, kCGWindowOwnerPID as String: 8, kCGWindowNumber as String: 3,
     kCGWindowBounds as String: ["X": 100, "Y": 100, "Width": 600, "Height": 400]],
    [kCGWindowLayer as String: 0, kCGWindowOwnerPID as String: 9, kCGWindowNumber as String: 4,
     kCGWindowBounds as String: ["X": 50, "Y": 50, "Width": 900, "Height": 700]],
]
check(windowUnder(CGPoint(x: 150, y: 120), windows: windows, ownPID: 99)?.id == 3,
      "a press lands on the frontmost window there, not the overlay or the menu bar")
check(windowUnder(CGPoint(x: 800, y: 600), windows: windows, ownPID: 99)?.id == 4, "or the one behind it")
check(windowUnder(CGPoint(x: 10, y: 10), windows: windows, ownPID: 99) == nil, "the desktop is no window")
check(windowMoved(from: CGRect(x: 100, y: 100, width: 600, height: 400), to: CGRect(x: 104, y: 100, width: 600, height: 400)),
      "a window that moved")
check(!windowMoved(from: CGRect(x: 100, y: 100, width: 600, height: 400), to: CGRect(x: 100, y: 100, width: 600, height: 400)),
      "a click that moved nothing")

// Everything the app writes must be in the spider's view model.
if let scenePath = CommandLine.arguments.dropFirst().first,
   let scene = try? String(contentsOfFile: scenePath, encoding: .utf8) {
    for name in ["home", "dragging"] {
        check(scene.contains("<ViewModelPropertyBoolean name=\"\(name)\""), "the scene has \(name)")
    }
    for name in ["homeX", "homeY", "cornerX", "cornerY"] {
        check(scene.contains("<ViewModelPropertyNumber name=\"\(name)\""), "the scene has \(name)")
    }
}

if failures > 0 {
    print("\(failures) failed")
    exit(1)
}
print("all passed")
