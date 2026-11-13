import AppKit

@main
enum FloatingSidebarTests {
    private static var checks = 0

    @MainActor
    static func main() {
        geometry()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1400, height: 880),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let shell = ShellView(frame: NSRect(origin: .zero, size: window.frame.size))
        window.contentView = shell
        let sidebar = FloatingSidebarController(shell: shell, window: window, palette: { SpacePalette() })
        sidebar.sidebarHidden = { true }
        // Do not install the pointer timer or post input events. The real controller
        // and AppKit animation completions run with an offscreen disposable panel.
        sidebar.show()
        expect(sidebar.isShown && shell.sidebarDetached, "show attaches the sidebar to its panel")
        let panel = window.childWindows!.first { $0 is FloatingSidebarPanel }!
        arcsReveal(window: window, sidebar: sidebar, panel: panel)

        sidebar.hide(animated: true)
        expect(!sidebar.isShown && shell.sidebarDetached, "animated hide remains in flight before completion")
        sidebar.show()
        drainAnimations()
        expect(sidebar.isShown && shell.sidebarDetached && panel.parent === window && panel.isVisible,
               "an old hide completion must not remove a newly revealed panel")
        expect(shell.sidebarHost.window === panel, "the revealed sidebar retains its native panel owner")

        // The floating sidebar's edge drags the width through the shell's handle.
        var saved: CGFloat?
        shell.resizeHandle.onDrag = { shell.sidebarWidth += $0 }
        shell.resizeHandle.onEnd = { saved = shell.sidebarWidth }
        let edge = shell.sidebarHost.superview?.subviews.compactMap { $0 as? ResizeHandleView }.first
        expect(edge.map { !$0.isHidden && abs($0.frame.maxX - shell.sidebarHost.frame.maxX) < 0.5 } == true,
               "the floating sidebar has a resize strip on its right edge")
        let panelWidth = panel.frame.width
        edge?.onDrag?(40)
        edge?.onEnd?()
        expect(shell.sidebarWidth == 368 && saved == 368, "dragging the floating edge resizes and saves the width")
        expect(panel.frame.width == panelWidth + 40 && shell.sidebarHost.frame.width == 368
               && abs(edge!.frame.maxX - shell.sidebarHost.frame.maxX) < 0.5,
               "the panel, sidebar and strip follow the new width")
        edge?.onDrag?(-40)
        // A whole drag from the floating edge reaches the shell's handle too (#287: Arc's resize
        // works from the start width and the pointer's speed).
        var began = false, got: (CGFloat, CGFloat)?
        shell.resizeHandle.onBegin = { began = true }
        shell.resizeHandle.onResize = { t, v in got = (t, v); shell.sidebarWidth = 328 + t }
        edge?.onBegin?()
        edge?.onResize?(20, 15)
        expect(began && got.map { $0 == 20 && $1 == 15 } == true && shell.sidebarHost.frame.width == 348,
               "the floating edge hands the drag's start, translation and speed to the shell")
        shell.resizeHandle.onResize?(0, 0)
        shell.resizeHandle.onBegin = nil
        shell.resizeHandle.onResize = nil
        libraryDrawer(shell: shell, sidebar: sidebar, panel: panel)
        shell.resizeHandle.onDrag = nil
        shell.resizeHandle.onEnd = nil

        // Multiple animation completions can be queued; only the latest show owns it.
        sidebar.hide(animated: true)
        sidebar.show()
        sidebar.hide(animated: true)
        sidebar.show()
        drainAnimations()
        expect(sidebar.isShown && shell.sidebarDetached && panel.parent === window && panel.isVisible,
               "rapid edge re-entry leaves the latest reveal visible")

        sidebar.hide(animated: true)
        sidebar.prepareForAnchoring()
        expect(!sidebar.isShown && !shell.sidebarDetached && shell.sidebarHost.superview === shell,
               "anchoring during hide immediately brings the sidebar home")
        expect(shell.floatingSidebar && panel.parent == nil && !panel.isVisible,
               "anchoring preserves the floating start frame while removing its panel")
        drainAnimations()
        expect(shell.floatingSidebar && shell.sidebarHost.superview === shell,
               "a stale hide completion must not overwrite the anchoring start state")

        sidebar.show()
        sidebar.hide(animated: true)
        sidebar.hide(animated: false)
        expect(!shell.sidebarDetached && panel.parent == nil && !panel.isVisible,
               "a synchronous hide finishes an in-flight animated hide immediately")
        drainAnimations()
        expect(!sidebar.isShown && !shell.sidebarDetached && !panel.hasShadow,
               "late show and hide completions cannot revive a hidden panel or shadow")

        sidebar.show()
        sidebar.hide(animated: true)
        drainAnimations()
        expect(!sidebar.isShown && !shell.sidebarDetached && !shell.floatingSidebar,
               "an uninterrupted hide still reattaches the sidebar normally")

        onlyTheKeyWindowReveals(window: window, sidebar: sidebar, panel: panel)
        noTrafficLightsInFullScreen(sidebar: sidebar)
        libraryLeavesWithThePointer(shell: shell, sidebar: sidebar)

        // #136: the pointer is sampled only while Cra is the active app, and (11 Nov 2026, macOS's
        // "Using Significant Energy") only while the sidebar is hidden or floating out: docked, the
        // 30 Hz timer woke Cra for nothing (FloatingSidebarPoll).
        sidebar.sidebarHidden = { true }
        sidebar.install()
        expect(!sidebar.isPolling, "an inactive app installs no pointer timer")
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApp)
        expect(sidebar.isPolling, "becoming active starts the pointer timer")
        expect(sidebar.pollingInterval == FloatingSidebarPoll.fast, "at the edge reveal's pace")
        sidebar.sidebarHidden = { false }
        sidebar.updatePolling()
        expect(!sidebar.isPolling, "docked: no pointer timer at all")
        sidebar.sidebarHidden = { true }
        sidebar.updatePolling()
        expect(sidebar.isPolling, "hidden again: the edge is watched")
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        expect(!sidebar.isPolling, "leaving the app stops it")
        window.close()
        print("Floating sidebar: \(checks) checks passed")
    }

    /// GitHub #82: like Arc, only the key window's hidden sidebar comes out on hover, so a window
    /// behind another can't reveal over it. The key window may be one of its own children (the
    /// page, DevTools, the floating panel); with Cra inactive, none reveals.
    // promise: #82
    @MainActor
    private static func onlyTheKeyWindowReveals(window: NSWindow, sidebar: FloatingSidebarController, panel: NSWindow) {
        let page = NSWindow(contentRect: NSRect(x: -9990, y: -9990, width: 1380, height: 860),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        page.isReleasedWhenClosed = false
        window.addChildWindow(page, ordered: .above)
        let front = NSWindow(contentRect: window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        front.isReleasedWhenClosed = false
        var key: NSWindow? = window
        sidebar.keyWindow = { key }
        expect(sidebar.isKey, "the key window reveals")
        key = page
        expect(sidebar.isKey, "its page being key counts as the window")
        sidebar.show()
        key = panel
        expect(sidebar.isKey, "its floating panel being key counts as the window")
        sidebar.hide(animated: false)
        key = front
        expect(!sidebar.isKey, "a window behind the key window does not reveal")
        key = nil
        expect(!sidebar.isKey, "no key window (Cra inactive) does not reveal")
        window.removeChildWindow(page)
        page.close()
        front.close()
    }

    /// In macOS full screen the traffic lights belong to the menu bar's title bar: the hidden sidebar
    /// comes out without the stand-in set it carries in a window (its toggle takes their place).
    /// The Library opened over a hidden sidebar opens in the floating one, which widens to the
    /// drawer's width and back, the sidebar never docked (MainWindowController.showLibrary).
    @MainActor
    private static func libraryDrawer(shell: ShellView, sidebar: FloatingSidebarController, panel: NSWindow) {
        sidebar.reposition()
        let width = shell.sidebarWidth
        let before = panel.frame.width
        shell.drawerWidth = 420
        sidebar.reposition()
        expect(abs(panel.frame.width - (before + 420 - width)) < 0.5 && abs(shell.sidebarHost.frame.width - 420) < 0.5,
               "the floating panel and the sidebar in it take the Library drawer's width")
        expect(sidebar.isShown && shell.sidebarDetached, "the sidebar stays floating, not docked, for the Library")
        shell.drawerWidth = nil
        sidebar.reposition()
        expect(abs(panel.frame.width - before) < 0.5 && abs(shell.sidebarHost.frame.width - width) < 0.5,
               "closing the Library gives the floating sidebar its own width back")
    }

    /// The Library open in the floating sidebar keeps it out until the pointer has been on it (from
    /// ⇧⌘L the pointer is elsewhere); after that the pointer leaving takes the sidebar away like any
    /// other time, and `didHide` tells the window, which closes the Library so the next reveal is
    /// the space. Before, the shell's own pointer tracking hid the panel with the Library still in
    /// it, and every reveal after came back stuck on the Library (10 Nov 2026).
    @MainActor
    private static func libraryLeavesWithThePointer(shell: ShellView, sidebar: FloatingSidebarController) {
        let off = CGPoint(x: 900, y: 300), on = CGPoint(x: 120, y: 300)
        var library = true, held = false, hid = 0
        sidebar.holdsUntilVisited = { library }
        sidebar.staysShown = { held }
        sidebar.didHide = { hid += 1 }
        sidebar.show()
        drainAnimations()
        sidebar.pointerSample(at: off, pressedMouseButtons: 0)
        expect(sidebar.isShown, "the Library opened from the keyboard keeps the sidebar out until the pointer comes to it")
        sidebar.pointerSample(at: on, pressedMouseButtons: 0)
        sidebar.pointerSample(at: off, pressedMouseButtons: 1)
        expect(sidebar.isShown, "a drag out of the Library doesn't take it away")
        held = true
        sidebar.pointerSample(at: off, pressedMouseButtons: 0)
        expect(sidebar.isShown, "nor does leaving while something beside it is open (the bookmark card)")
        held = false
        sidebar.pointerSample(at: off, pressedMouseButtons: 0)
        expect(!sidebar.isShown, "the pointer leaving after it has been on the Library takes the sidebar away")
        drainAnimations()
        expect(hid == 1 && !shell.sidebarDetached, "the window hears the sidebar went, once it is out of sight")

        sidebar.show()
        drainAnimations()
        expect(sidebar.isShown, "the next reveal comes out")
        sidebar.pointerSample(at: off, pressedMouseButtons: 0)
        expect(sidebar.isShown, "each reveal waits for the pointer again while the Library holds it")
        library = false
        sidebar.pointerSample(at: off, pressedMouseButtons: 0)
        expect(!sidebar.isShown, "without the Library, leaving takes it away at once")
        drainAnimations()
        expect(hid == 2, "every hide is heard")
        sidebar.holdsUntilVisited = { false }
        sidebar.staysShown = { false }
        sidebar.didHide = nil

        // Back from the Library under a resting pointer off the sidebar (12 Nov 2026): it stays out
        // until the pointer moves on away, comes onto it or clicks outside; it used to go at once.
        sidebar.show()
        drainAnimations()
        let rest = CGPoint(x: 600, y: 300)
        sidebar.holdAfterReturn(pointer: rest)
        sidebar.pointerSample(at: rest, pressedMouseButtons: 0)
        expect(sidebar.isShown && sidebar.returnHold != nil, "where the pointer rested, the sidebar stays out")
        sidebar.pointerSample(at: CGPoint(x: 630, y: 300), pressedMouseButtons: 0)
        expect(sidebar.isShown, "a small drift doesn't take it away")
        sidebar.pointerSample(at: CGPoint(x: 680, y: 300), pressedMouseButtons: 0)
        expect(!sidebar.isShown && sidebar.returnHold == nil, "moving on away does")
        drainAnimations()
        sidebar.show()
        drainAnimations()
        sidebar.holdAfterReturn(pointer: rest)
        sidebar.pointerSample(at: on, pressedMouseButtons: 0)
        expect(sidebar.isShown && sidebar.returnHold == nil, "coming onto the sidebar ends the hold")
        sidebar.pointerSample(at: off, pressedMouseButtons: 0)
        expect(!sidebar.isShown, "after which leaving takes it away as usual")
        drainAnimations()

        // Popovers hung from the sidebar (the Extensions popover, the bookmark card) go as the
        // sidebar starts to go, not after its slide: they were left on screen with nothing under
        // them (10 Nov 2026).
        var starts = 0, endsAtStart = -1
        sidebar.willHide = { starts += 1; endsAtStart = hid }
        sidebar.didHide = { hid += 1 }
        sidebar.show()
        drainAnimations()
        sidebar.hide(animated: true)
        expect(starts == 1 && endsAtStart == 2 && hid == 2, "willHide comes as the hide starts, before the slide is over")
        drainAnimations()
        expect(hid == 3, "and didHide once it is out of sight")
        sidebar.hide(animated: true)
        expect(starts == 1, "a hidden sidebar's hide calls nothing")
        sidebar.willHide = nil
        sidebar.didHide = nil
    }

    @MainActor
    private static func noTrafficLightsInFullScreen(sidebar: FloatingSidebarController) {
        var fullscreen = false
        sidebar.windowFullscreen = { fullscreen }
        sidebar.show()
        expect(sidebar.showsTrafficLights, "in a window the floating sidebar carries stand-in traffic lights")
        sidebar.hide(animated: false)
        fullscreen = true
        sidebar.show()
        expect(!sidebar.showsTrafficLights, "in full screen the floating sidebar shows no traffic lights")
        // The window going full screen while the sidebar is out takes them away too.
        sidebar.hide(animated: false)
        fullscreen = false
        sidebar.show()
        fullscreen = true
        sidebar.reposition()
        expect(!sidebar.showsTrafficLights, "entering full screen with the sidebar out takes its traffic lights away")
        sidebar.hide(animated: false)
        sidebar.windowFullscreen = { false }
    }

    // promise: #24
    /// Where the pointer reveals and hides the floating sidebar; edge to edge, with no margin, only
    /// Arc's 5 pt strip over the page reveals it (#24).
    private static func geometry() {
        // Nonzero bounds also check that both paths use shell-local geometry.
        let bounds = CGRect(x: 20, y: 10, width: 1400, height: 880)
        expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 20, y: 100), in: bounds), "left edge reveals")
        expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 30, y: 100), in: bounds), "the whole 10 pt margin reveals")
        expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 30.1, y: 100), in: bounds), "page content does not reveal")
        expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 16, y: 100), in: bounds), "just outside the window reveals, as in Arc")
        expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 15.9, y: 100), in: bounds), "further outside does not reveal")
        expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 22, y: 9.9), in: bounds), "above the window does not reveal")
        expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 22, y: 890.1), in: bounds), "below the window does not reveal")
        // Edge to edge (GitHub #24) there is no margin; only Arc's 5 pt strip over the page reveals.
        expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 25, y: 100), in: bounds, edgeToEdge: true), "edge to edge: 5 pt reveals")
        expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 25.1, y: 100), in: bounds, edgeToEdge: true), "edge to edge: the page past 5 pt does not reveal")
        expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 16, y: 100), in: bounds, edgeToEdge: true), "edge to edge: just outside the window still reveals")
        expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 24, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: 0, edgeToEdge: true),
               "edge to edge: the reveal strip does not hide what it revealed")
        expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 17, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: 0),
               "the outside reveal strip does not hide what it revealed")
        expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 429, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: 0),
               "panel margin and leave slack are included in the retention boundary")
        expect(FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 429.1, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: 0),
               "leaving the shared retention boundary hides after release")
        expect(FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 15.9, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: 0),
               "leaving the window hides after release")
        for button in [1, 2, 4] {
            expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 429.1, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: button),
                   "button mask \(button) preserves the sidebar beyond the leave slack during a gesture")
            expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 15.9, y: 100), in: bounds, sidebarWidth: 328, pressedMouseButtons: button),
                   "button mask \(button) preserves the sidebar outside the moving window during a gesture")
        }
    }

    // promise: #293
    /// GitHub #293: the hidden sidebar is less jumpy, as in Arc 1.172.1 (120 fps, 9 Nov 2026). The pointer
    /// waits 0.1 s in the strip before it comes out, so brushing the edge doesn't flash it; it stays out
    /// until 81 pt past its width; it springs in and eases out on Arc's curves; and its shadow is a soft
    /// one under it, not the hard outline a window shadow drew round the panel.
    @MainActor
    private static func arcsReveal(window: NSWindow, sidebar: FloatingSidebarController, panel: NSWindow) {
        var dwell = FloatingSidebarRevealDwell()
        expect(!dwell.sample(inStrip: true, at: 10.0), "arriving at the edge doesn't reveal at once")
        expect(!dwell.sample(inStrip: true, at: 10.06), "nor 60 ms later")
        expect(!dwell.sample(inStrip: false, at: 10.08), "leaving the strip doesn't reveal")
        expect(!dwell.sample(inStrip: true, at: 10.12), "coming back starts the wait over")
        expect(!dwell.sample(inStrip: true, at: 10.206), "a brush Arc ignored (86 ms) doesn't reveal")
        expect(!dwell.sample(inStrip: true, at: 10.219), "nor anything shorter than Arc's wait")
        expect(dwell.sample(inStrip: true, at: 10.22), "0.1 s in the strip reveals")
        dwell.reset()
        expect(!dwell.sample(inStrip: true, at: 11), "after a reveal the next one waits again")

        let bounds = CGRect(x: 0, y: 0, width: 1728, height: 950)
        expect(!FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 344, y: 300), in: bounds, sidebarWidth: 264, pressedMouseButtons: 0),
               "a 264 pt sidebar stays out with the pointer at x 344, as in Arc")
        expect(FloatingSidebarGeometry.shouldHide(at: CGPoint(x: 346, y: 300), in: bounds, sidebarWidth: 264, pressedMouseButtons: 0),
               "and goes at x 346, where Arc's went")

        expect(!panel.hasShadow, "the sidebar's panel draws no window shadow (its rim outlined the sidebar)")
        let shadow = window.childWindows!.first { $0 !== panel && $0.ignoresMouseEvents }
        expect(shadow != nil, "a click-through panel carries the sidebar's shadow")
        let order = window.childWindows!
        let shell = sidebar.shell
        expect(shadow.map { s in order.firstIndex { $0 === s }! < order.firstIndex { $0 === panel }! } == true,
               "the shadow sits under the sidebar")
        let layer = shadow?.contentView?.subviews.first?.layer
        expect(layer.map { $0.shadowOpacity > 0 && $0.shadowPath != nil && $0.mask != nil } == true,
               "the shadow is a soft layer shadow with the sidebar cut out of it")
        let slider = shell_slider(panel)
        let spring = slider?.layer?.animation(forKey: "slide") as? CASpringAnimation
        expect(spring.map { $0.stiffness == 759 && $0.damping == 46.3 && $0.initialVelocity == 23.3 && $0.isAdditive } == true,
               "the reveal is Arc's spring")
        sidebar.hide(animated: true)
        let ease = slider?.layer?.animation(forKey: "slide")
        expect(ease.map { !($0 is CASpringAnimation) && abs($0.duration - 0.102) < 0.001 } == true, "the hide is Arc's 0.1 s ease")
        expect(shadow?.parent === window, "the shadow leaves with the sidebar, not before it")
        drainAnimations()
        expect(shadow?.parent == nil && shadow?.isVisible == false, "and is gone once the sidebar is")
        // The shell's own mouse-moved path waits too: it used to call show() at once, which is how the
        // edge still flashed with the poll's wait in place.
        var clock: TimeInterval = 100
        sidebar.now = { clock }
        sidebar.keyWindow = { window }
        sidebar.hide(animated: false)
        sidebar.edgeHovered()
        expect(!sidebar.isShown, "a move into the strip doesn't reveal at once")
        expect(sidebar.staged && shell.sidebarDetached && panel.parent === window && panel.ignoresMouseEvents,
               "it stages the sidebar in its panel during the wait, out of sight and letting clicks through")
        clock = 100.05
        sidebar.edgeSample(inStrip: false)
        expect(!sidebar.staged && !shell.sidebarDetached && panel.parent == nil && shell.sidebarHost.superview === shell,
               "leaving the strip before the wait is over puts the sidebar back")
        clock = 100.1
        sidebar.edgeHovered()
        clock = 100.18
        sidebar.edgeHovered()
        expect(!sidebar.isShown, "coming back waits again: 80 ms is not enough")
        clock = 100.2
        sidebar.edgeHovered()
        expect(sidebar.isShown && !sidebar.staged && !panel.ignoresMouseEvents, "it reveals once the pointer has waited 0.1 s")
        sidebar.now = { ProcessInfo.processInfo.systemUptime }
        drainAnimations()
        expect(sidebar.isShown && shadow?.parent === window, "the shadow comes back with the sidebar")
    }

    /// The view that slides inside the sidebar panel.
    @MainActor
    private static func shell_slider(_ panel: NSWindow) -> NSView? {
        panel.contentView?.subviews.first
    }

    private static func drainAnimations() {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.6))
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        checks += 1
    }
}

// Lightweight dependencies for compiling the production controller without CEF.
// They provide layout/theme data only; lifecycle and animation code is not copied.
struct SpacePalette {
    var vibrant = false
    var isDark = false
}

final class PaletteBackgroundView: NSView {
    var palette: SpacePalette
    init(palette: SpacePalette) { self.palette = palette; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
}

enum CraMetrics {
    static let contentInset: CGFloat = 10
    static let titleRowCenter: CGFloat = 24
}

final class CraTuning {
    static let shared = CraTuning()
    let material: NSVisualEffectView.Material = .sidebar
    let darkBlur = false
    let liftActive: CGFloat = 0.1
}

final class ResizeHandleView: NSView {
    var onDrag: ((CGFloat) -> Void)?
    var onBegin: (() -> Void)?
    var onResize: ((_ translation: CGFloat, _ speed: CGFloat) -> Void)?
    var onEnd: (() -> Void)?
}

final class ShellView: NSView {
    let sidebarHost = NSView()
    let resizeHandle = ResizeHandleView()
    var sidebarWidth: CGFloat = 328
    /// The Library's drawer (ShellView.drawerWidth): the floating panel takes the wider width.
    var drawerWidth: CGFloat?
    var shownSidebarWidth: CGFloat { max(sidebarWidth, drawerWidth ?? 0) }
    var sidebarResizable = true
    var contentFullscreen = false
    var edgeToEdge = false
    var sidebarDetached = false
    var floatingSidebar = false
    struct Frames { let sidebar: NSRect }

    override init(frame: NSRect) {
        super.init(frame: frame)
        sidebarHost.wantsLayer = true
        addSubview(sidebarHost)
        addSubview(resizeHandle)
    }
    required init?(coder: NSCoder) { fatalError() }

    func frames(sidebarVisible: Bool, floating: Bool, fullscreen: Bool, width: CGFloat) -> Frames {
        let margin = FloatingSidebarGeometry.margin
        return Frames(sidebar: NSRect(x: margin, y: margin, width: max(width, drawerWidth ?? 0), height: bounds.height - 2 * margin))
    }
}
