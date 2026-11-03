import AppKit
import RiveRuntime

/// Calls `onAdvance` after every advance, before that frame is drawn.
final class FollowingViewModel: RiveViewModel {
    var onAdvance: (() -> Void)?

    override func player(didAdvanceby seconds: Double, riveModel: RiveModel?) {
        onAdvance?()
    }
}

/// A menu-bar app that shows the spider on the primary display and feeds it
/// the global mouse. The spider's brain is the same Luau the CLI player runs;
/// this only passes the pointer, pulls the press triggers and keeps a small
/// Rive view under the spider inside a screen-sized click-through window, so
/// only that view is ever redrawn.
final class SpiderApp: NSObject, NSApplicationDelegate {
    private let rivPath: String
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var viewModel: FollowingViewModel?
    private var instance: RiveDataBindingViewModel.Instance?
    private var clickMonitor: Any?
    private var scrollMonitor: Any?
    private var scrolled = CGVector.zero
    private var lastMouse = CGPoint(x: CGFloat.nan, y: .nan)
    private var paletteMenu = NSMenu()
    private var rimItem: NSMenuItem!
    private var paletteName = UserDefaults.standard.string(forKey: "palette") ?? palettes[0].name
    private var rimOn = UserDefaults.standard.bool(forKey: "rim")
    private var fpsMenu = NSMenu()
    private var sizeMenu = NSMenu()
    private var sleepMenu = NSMenu()
    private var sleepAfter = sleepDelay(saved: UserDefaults.standard.object(forKey: "sleepAfter") as? Int)
    private var scale = CGFloat(spiderScale(saved: UserDefaults.standard.double(forKey: "size")))
    private var fps = frameRate(saved: UserDefaults.standard.integer(forKey: "fps"))
    private var modeMenu = NSMenu()
    private var mode = agentModes[0].key
    private var hotkeys: Hotkeys?
    private var home = false
    private var homeItem: NSMenuItem!
    private var cornerMenu = NSMenu()
    private var homeCorner = HomeCorner(rawValue: UserDefaults.standard.string(forKey: "homeCorner") ?? "") ?? .topRight
    private var dragMonitor: Any?
    /// The window the last left press landed on, until it is released.
    private var pressedWindow: (id: Int, bounds: CGRect)?
    private var dragging = false

    init(rivPath: String) {
        self.rivPath = rivPath
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "ant", accessibilityDescription: "Spider")
        let menu = NSMenu()
        menu.addItem(withTitle: "Hide Spider", action: #selector(toggle(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Reload Spider", action: #selector(reload), keyEquivalent: "r")
        menu.addItem(.separator())
        for palette in palettes {
            paletteMenu.addItem(withTitle: palette.name, action: #selector(choosePalette(_:)), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Color", action: nil, keyEquivalent: "").submenu = paletteMenu
        rimItem = menu.addItem(withTitle: "White Rim", action: #selector(toggleRim), keyEquivalent: "")
        for (i, size) in spiderScales.enumerated() {
            sizeMenu.addItem(withTitle: "\(Int(size * 100))%", action: #selector(chooseSize(_:)), keyEquivalent: "").tag = i
        }
        menu.addItem(withTitle: "Size", action: nil, keyEquivalent: "").submenu = sizeMenu
        for delay in sleepDelays {
            let title = delay == 0 ? "Never" : delay < 60 ? "\(delay) s" : "\(delay / 60) min"
            sleepMenu.addItem(withTitle: title, action: #selector(chooseSleep(_:)), keyEquivalent: "").tag = delay
        }
        menu.addItem(withTitle: "Sleep After", action: nil, keyEquivalent: "").submenu = sleepMenu
        for rate in frameRates {
            fpsMenu.addItem(withTitle: "\(rate) fps", action: #selector(chooseFrameRate(_:)), keyEquivalent: "").tag = rate
        }
        menu.addItem(withTitle: "Frame Rate", action: nil, keyEquivalent: "").submenu = fpsMenu
        // Agent modes, for the demo: the hot keys are global, the menu shows them.
        for (i, mode) in agentModes.enumerated() {
            let item = modeMenu.addItem(withTitle: mode.title, action: #selector(chooseMode(_:)), keyEquivalent: "\(i + 1)")
            item.keyEquivalentModifierMask = [.control, .option]
            item.tag = i + 1
        }
        menu.addItem(withTitle: "Agent Mode", action: nil, keyEquivalent: "").submenu = modeMenu
        // Home: the spider goes to its corner and stops following the pointer.
        homeItem = menu.addItem(withTitle: "Go Home", action: #selector(toggleHome), keyEquivalent: "h")
        homeItem.keyEquivalentModifierMask = [.control, .option]
        for corner in HomeCorner.allCases {
            cornerMenu.addItem(withTitle: corner.rawValue, action: #selector(chooseCorner(_:)), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Home Corner", action: nil, keyEquivalent: "").submenu = cornerMenu
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items + paletteMenu.items + fpsMenu.items + sizeMenu.items + sleepMenu.items + modeMenu.items + cornerMenu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        statusItem.menu = menu
        updateMenu()
        hotkeys = Hotkeys(onDigit: { [weak self] digit in
            if let mode = agentMode(digit: digit) {
                self?.setMode(mode)
            }
        }, onHome: { [weak self] in
            self?.toggleHome()
        })

        let screen = NSScreen.screens[0].frame
        window = makeOverlayWindow(screen: screen)
        // Stays empty and transparent: nothing here is redrawn.
        window.contentView = NSView(frame: CGRect(origin: .zero, size: screen.size))
        load()
        window.orderFrontRegardless()

        // Mouse-down monitors need no Accessibility permission (only key
        // monitors do). The click itself has already gone to the app under
        // the pointer; this only plays the press.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.type == .leftMouseDown {
                self?.pressedWindow = self?.windowAtMouse()
            }
            self?.press(left: event.type == .leftMouseDown)
        }
        // A window dragged by the pointer: the window a press landed on moves
        // before the press is released. Window bounds need no permission.
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return }
            if event.type == .leftMouseUp {
                self.pressedWindow = nil
                self.setDragging(false)
            } else if !self.dragging, let pressed = self.pressedWindow, let now = self.windowBounds(pressed.id),
                      windowMoved(from: pressed.bounds, to: now) {
                self.setDragging(true)
            }
        }
        // Scrolls in any app. The fingers lifting (the gesture ending, or the
        // page starting to coast on momentum) lets the legs flick or let go.
        scrollMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            if !event.momentumPhase.isEmpty {
                if event.momentumPhase.contains(.began) {
                    self?.scrollEnded()
                }
                return
            }
            self?.scroll(contentTravel(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY,
                                       precise: event.hasPreciseScrollingDeltas))
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                self?.scrollEnded()
            }
        }
    }

    private func load() {
        guard let data = FileManager.default.contents(atPath: rivPath) else {
            NSLog("spider: cannot read \(rivPath)")
            return
        }
        do {
            let file = try RiveFile(data: data, loadCdn: false)
            let model = RiveModel(riveFile: file)
            let vm = FollowingViewModel(model, stateMachineName: nil, fit: .layout, alignment: .topLeft,
                                        autoPlay: true, artboardName: "Spider")
            model.enableAutoBind { [weak self] instance in
                self?.instance = instance
                instance.numberProperty(fromPath: "viewSize")?.value = Float(spiderViewSize)
                instance.numberProperty(fromPath: "sleepAfter")?.value = Float(self?.sleepAfter ?? 10)
                instance.enumProperty(fromPath: "agent")?.value = self?.mode ?? agentModes[0].key
                self?.applyHome()
                self?.applyColors()
            }
            vm.onAdvance = { [weak self] in
                self?.followSpider()
                self?.trackPointer()
            }
            viewModel?.riveView?.removeFromSuperview()
            let view = SpiderView(model: model, autoPlay: true)
            vm.setRiveView(view: view)
            view.setPreferredFramesPerSecond(preferredFramesPerSecond: fps)
            applyScale()
            view.frame = CGRect(x: 0, y: 0, width: spiderViewSize, height: spiderViewSize)
            window.contentView?.addSubview(view)
            viewModel = vm
            lastMouse = CGPoint(x: CGFloat.nan, y: .nan)
            // The new view model's totals start at zero.
            scrolled = .zero
        } catch {
            NSLog("spider: cannot load \(rivPath): \(error)")
        }
    }

    /// Puts the view where the script just drew the spider relative to. The
    /// script wrote that origin in the advance that just ran, and this frame
    /// is drawn after this returns, so the two always match.
    private func followSpider() {
        guard let instance, let view = viewModel?.riveView,
              let x = instance.numberProperty(fromPath: "originX")?.value,
              let y = instance.numberProperty(fromPath: "originY")?.value
        else { return }
        let frame = viewFrame(origin: CGPoint(x: CGFloat(x), y: CGFloat(y)), size: spiderViewSize,
                              scale: scale, containerHeight: window.frame.height)
        if view.frame != frame {
            view.frame = frame
        }
    }

    /// Polled once a frame rather than monitored: a global mouse-moved monitor
    /// misses drags into other apps' windows, and the position needs no
    /// permission. Takes effect in the next advance.
    private func trackPointer() {
        let mouse = NSEvent.mouseLocation
        guard mouse != lastMouse, let instance else { return }
        lastMouse = mouse
        let point = spiderPoint(viewPoint(global: mouse, screen: window.frame), scale: scale)
        instance.numberProperty(fromPath: "pointerX")?.value = Float(point.x)
        instance.numberProperty(fromPath: "pointerY")?.value = Float(point.y)
    }

    /// Running totals: the script takes the difference whenever they change,
    /// so several scrolls in one frame all count.
    private func scroll(_ travel: CGVector) {
        guard let instance, travel != .zero else { return }
        trackPointer()
        scrolled.dx += travel.dx
        scrolled.dy += travel.dy
        instance.numberProperty(fromPath: "scrollX")?.value = Float(scrolled.dx)
        instance.numberProperty(fromPath: "scrollY")?.value = Float(scrolled.dy)
    }

    private func scrollEnded() {
        instance?.triggerProperty(fromPath: "scrollEnd")?.trigger()
    }

    private func press(left: Bool) {
        // Bring the pointer up to date first: the press lands where the
        // spider last saw it.
        trackPointer()
        instance?.triggerProperty(fromPath: left ? "pressLeft" : "pressRight")?.trigger()
    }

    /// Tells the spider whether it is home, and where home is in its space.
    private func applyHome() {
        guard let instance, let screen = NSScreen.screens.first else { return }
        let spot = homeSpot(corner: homeCorner, visible: screen.visibleFrame, screen: screen.frame, scale: scale)
        instance.numberProperty(fromPath: "homeX")?.value = Float(spot.hub.x)
        instance.numberProperty(fromPath: "homeY")?.value = Float(spot.hub.y)
        instance.numberProperty(fromPath: "cornerX")?.value = Float(spot.corner.x)
        instance.numberProperty(fromPath: "cornerY")?.value = Float(spot.corner.y)
        instance.booleanProperty(fromPath: "home")?.value = home
    }

    @objc private func toggleHome() {
        home.toggle()
        updateMenu()
        applyHome()
    }

    @objc private func chooseCorner(_ item: NSMenuItem) {
        homeCorner = HomeCorner(rawValue: item.title) ?? .topRight
        UserDefaults.standard.set(homeCorner.rawValue, forKey: "homeCorner")
        updateMenu()
        applyHome()
    }

    private func setDragging(_ on: Bool) {
        guard on != dragging else { return }
        dragging = on
        trackPointer()
        instance?.booleanProperty(fromPath: "dragging")?.value = on
    }

    /// The window under the pointer, in the window server's space (y down
    /// from the top of the primary display).
    private func windowAtMouse() -> (id: Int, bounds: CGRect)? {
        guard let primary = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        let mouse = NSEvent.mouseLocation
        return windowUnder(CGPoint(x: mouse.x, y: primary.frame.maxY - mouse.y), windows: list,
                           ownPID: ProcessInfo.processInfo.processIdentifier)
    }

    private func windowBounds(_ id: Int) -> CGRect? {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id)) as? [[String: Any]])?.first,
              let dict = info[kCGWindowBounds as String] as? NSDictionary
        else { return nil }
        return CGRect(dictionaryRepresentation: dict)
    }

    private func applyColors() {
        guard let instance else { return }
        var colors = (palettes.first { $0.name == paletteName } ?? palettes[0]).colors
        colors["rim"] = rimColor(rimOn)
        for (slot, argb) in colors {
            let c = channels(argb)
            instance.colorProperty(fromPath: slot)?.set(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
        }
    }

    private func updateMenu() {
        for item in paletteMenu.items {
            item.state = item.title == paletteName ? .on : .off
        }
        rimItem.state = rimOn ? .on : .off
        for item in sleepMenu.items {
            item.state = item.tag == sleepAfter ? .on : .off
        }
        for item in sizeMenu.items {
            item.state = spiderScales[item.tag] == Double(scale) ? .on : .off
        }
        for item in modeMenu.items {
            item.state = agentMode(digit: item.tag) == mode ? .on : .off
        }
        for item in fpsMenu.items {
            item.state = item.tag == fps ? .on : .off
        }
        homeItem.title = home ? "Follow the Pointer" : "Go Home"
        for item in cornerMenu.items {
            item.state = item.title == homeCorner.rawValue ? .on : .off
        }
    }

    @objc private func chooseMode(_ item: NSMenuItem) {
        if let mode = agentMode(digit: item.tag) {
            setMode(mode)
        }
    }

    /// The state machine's Agent layer plays the mode's timeline.
    private func setMode(_ key: String) {
        mode = key
        updateMenu()
        instance?.enumProperty(fromPath: "agent")?.value = key
    }

    @objc private func chooseSleep(_ item: NSMenuItem) {
        sleepAfter = item.tag
        UserDefaults.standard.set(sleepAfter, forKey: "sleepAfter")
        updateMenu()
        instance?.numberProperty(fromPath: "sleepAfter")?.value = Float(sleepAfter)
    }

    @objc private func chooseSize(_ item: NSMenuItem) {
        scale = CGFloat(spiderScales[item.tag])
        UserDefaults.standard.set(Double(scale), forKey: "size")
        updateMenu()
        applyScale()
    }

    /// The artboard keeps its size in its own units; the view shows each unit
    /// as `scale` points.
    private func applyScale() {
        guard let vm = viewModel else { return }
        vm.layoutScaleFactor = Double(window.backingScaleFactor * scale)
        followSpider()
        // Home is in the spider's space, which just changed.
        applyHome()
        // Send the pointer again in the new space.
        lastMouse = CGPoint(x: CGFloat.nan, y: .nan)
    }

    @objc private func chooseFrameRate(_ item: NSMenuItem) {
        fps = item.tag
        UserDefaults.standard.set(fps, forKey: "fps")
        updateMenu()
        viewModel?.riveView?.setPreferredFramesPerSecond(preferredFramesPerSecond: fps)
    }

    @objc private func choosePalette(_ item: NSMenuItem) {
        paletteName = item.title
        UserDefaults.standard.set(paletteName, forKey: "palette")
        updateMenu()
        applyColors()
    }

    @objc private func toggleRim() {
        rimOn.toggle()
        UserDefaults.standard.set(rimOn, forKey: "rim")
        updateMenu()
        applyColors()
    }

    @objc private func toggle(_ item: NSMenuItem) {
        if window.isVisible {
            window.orderOut(nil)
            item.title = "Show Spider"
        } else {
            window.orderFrontRegardless()
            item.title = "Hide Spider"
        }
    }

    @objc private func reload() {
        load()
    }
}

// The .riv to play: the first argument, else the copy in the app bundle.
let rivPath = CommandLine.arguments.dropFirst().first
    ?? Bundle.main.path(forResource: "spider", ofType: "riv")
    ?? "spider.riv"
let app = NSApplication.shared
let delegate = SpiderApp(rivPath: rivPath)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
