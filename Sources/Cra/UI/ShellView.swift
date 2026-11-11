import AppKit
import SwiftUI

/// The window's content view: gradient background, sidebar (anchored,
/// hidden, or floating over the content on hover), a resize handle, and the
/// content area: one rounded card per pane (Arc's toolbar strip on top, the
/// Chromium view below) with dragger handles in the gaps between panes. With
/// no tab selected there is no card, just the toolbar on the gradient.
final class ShellView: NSView {
    /// Behind-window blur for vibrant (Arc-style) themes.
    let vibrancy = NSVisualEffectView()
    /// Light vibrant themes: an untinted behind-window blur (CABackdropLayer) under a
    /// black dim and a white lift gradient. The system materials all tint and cap the
    /// backdrop pass-through, so Arc's measured intercept and slope were unreachable with
    /// them (docs, 25 Oct 2026). Falls back to `vibrancy` when the layer class is missing.
    let backdropHost = NSView()
    private var backdropLayer: CALayer?
    /// In fullscreen there is nothing behind the window to capture (the backdrop read black),
    /// so NSVisualEffectView, and with it Arc's sidebar, swaps its capture for the desktop
    /// tint (CAChameleonLayer). We do the same (GitHub #83).
    private var desktopTintLayer: CALayer?
    /// macOS full screen: the page goes edge to edge (WindowFill).
    var windowFullscreen = false {
        didSet {
            guard windowFullscreen != oldValue else { return }
            refreshLift()
            edgeTargetChanged()
        }
    }
    /// The window is zoomed to fill its screen: the page goes edge to edge (WindowFill).
    var windowMaximized = false { didSet { if windowMaximized != oldValue { edgeTargetChanged() } } }
    /// AppKit's answer to whether the window draws its active look (MainWindowController.materialActiveNow).
    let activeAppearance = ActiveAppearanceProbe()
    private var loggedBackdrop: String?
    private let dimLayer = CALayer()
    private let liftLayer = CAGradientLayer()
    /// Light theme that wants the blur path (setTheme).
    private(set) var vibrantLight = false
    /// Arc's one-colour themes, light or dark: the blur under SpacePalette.solidAlpha's material.
    private(set) var solidBackdrop = false
    /// System Settings ▸ Accessibility ▸ Display ▸ Reduce transparency (or Increase contrast):
    /// AppKit's materials, and Arc's sidebar, go opaque. The backdrop layer path follows (GitHub #156).
    private var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    var usesBackdropLayer: Bool { (solidBackdrop || vibrantLight && !vibrantDark) && backdropLayer != nil }
    /// Lifts the dark blur toward Arc's mid-grey base before the gradient goes on.
    let vibrancyLift = NSView()
    let backgroundHost: NSView
    let sidebarHost: NSView
    let resizeHandle = ResizeHandleView()
    /// The content area (card minus nothing): holds the pane cards and handles.
    let contentContainer = NSView()
    /// Over the card while a Library bookmark is dragged: the drop opens it (PageDropView).
    let pageDrop = PageDropView()
    /// Pane cards in pane order (one card, `noTabID`, when nothing is selected).
    private(set) var paneCards: [PaneCardView] = []
    private var handles: [SplitDraggerHandleView] = []
    /// Keeps Alloy-hosted Chromium views that no pane shows right now.
    let parkingView = NSView()
    /// DevTools dock on the right of the focused page, like Chrome's default.
    let devToolsHost = NSView()
    let devToolsDivider = NSView()
    let devToolsHandle = DevToolsResizeHandle()
    var devToolsVisible = false { didSet { needsLayout = true; if devToolsVisible != oldValue { edgeTargetChanged() } } }
    var devToolsWidth: CGFloat = 460 { didSet { needsLayout = true } }
    /// Chrome-style DevTools: the frontend draws the dock split itself (can_dock), so its
    /// window covers the whole card body and the page is laid over its placeholder.
    var devToolsFrontendDocked = false { didSet { needsLayout = true; if devToolsFrontendDocked != oldValue { edgeTargetChanged() } } }
    /// The page rect (window coordinates) the frontend-docked layout produced; overlays follow it.
    var frontendPageRect: NSRect? { didSet { if oldValue != frontendPageRect { needsLayout = true } } }
    /// An extension's side panel (chrome.sidePanel) right of the panes, Chrome's place for it.
    let sidePanel = ExtensionSidePanelCard()
    let sidePanelHandle = DevToolsResizeHandle()
    /// The panel's width; 0 = no panel.
    var sidePanelWidth: CGFloat = 0 { didSet { if sidePanelWidth != oldValue { needsLayout = true } } }
    /// The panel page's area (window coordinates), nil while no panel shows.
    var onSidePanelFrame: ((NSRect?) -> Void)?
    /// Reports the dock area (window coordinates) so the DevTools child window follows it.
    var onDevToolsFrame: ((NSRect) -> Void)?
    /// Reports each pane's page area (window coordinates) so Chrome-style page windows follow it.
    var onPaneFrames: (([UUID: NSRect]) -> Void)?
    /// Animated transitions (sidebar, pane add/remove): target page areas + duration, so page windows animate alongside.
    var onAnimatePaneFrames: (([UUID: NSRect], TimeInterval, CAMediaTimingFunction) -> Void)?
    /// The user dragged a divider and let go: new width factors per pane.
    var onPaneResizeEnded: (([UUID: CGFloat]) -> Void)?
    var onPaneResizeBegan: (() -> Void)?
    /// Builds a pane's toolbar (the window controller owns the environment).
    var makeToolbar: ((UUID?) -> NSView)?
    /// Where the status bubble and find bar live (the content container, or an
    /// overlay panel's content view when pages are separate windows).
    private(set) var overlayParent: NSView
    /// Set while the sidebar/card frames are being animated; layout() then leaves them alone.
    private var animatingFrames = false
    /// Set while panes animate open/closed; layout() keeps their frames.
    private var animatingPanes = false
    /// Arc's faint card over the gradient while no tab is selected, with a note that none is.
    let placeholderHost = NoTabPlaceholderView()
    /// Arc's loading bar in the margin above the card, for the front tab.
    let loadingIndicator = LoadingIndicatorView()
    private var loadingTabID: UUID?
    let statusHost: NSView
    let findHost: NSView

    /// Stand-in pane id for the no-tab state (toolbar on the gradient, no card).
    static let noTabID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private(set) var paneIDs: [UUID] = []
    private(set) var paneFactors: [UUID: CGFloat] = [:]
    private(set) var splitOrientation: SplitOrientation = .horizontal
    private(set) var focusedPaneID: UUID?
    /// Panes without a page (Arc's tinted "Search or Enter URL…" pane).
    private(set) var emptyPaneIDs: Set<UUID> = []
    var isDarkTheme = false {
        didSet {
            for c in paneCards { c.isDark = isDarkTheme }
            loadingIndicator.isDark = isDarkTheme
            placeholderHost.isDark = isDarkTheme
        }
    }
    /// The ring around the focused split pane: the space's shadedDark (PaneCardView.focusRing).
    var focusRingColor: NSColor? { didSet { if focusRingColor != oldValue { updateFocusRings() } } }
    /// Each tab's page background ("#RRGGBB"), painted under its page window (PaneCardView.pageColor).
    var pageColors: [UUID: String] = [:] {
        didSet { for c in paneCards where c.pageColor != pageColors[c.tabID] { c.pageColor = pageColors[c.tabID] } }
    }
    /// Each tab's toolbar colour ("#RRGGBB"), painted behind its toolbar (PaneCardView.toolbarColor).
    var toolbarColors: [UUID: String] = [:] {
        didSet { for c in paneCards where c.toolbarColor != toolbarColors[c.tabID] { c.toolbarColor = toolbarColors[c.tabID] } }
    }

    var sidebarWidth: CGFloat = CraMetrics.sidebarDefaultWidth { didSet { needsLayout = true } }
    /// Off while the Library has the sidebar: its width is not the user's to drag.
    var sidebarResizable = true { didSet { needsLayout = true } }
    var sidebarVisible = true {
        didSet {
            needsLayout = true
            // A change made without animateSidebar (the window being built): the card follows on its ease.
            if edgeSidebarShown != sidebarVisible {
                edgeSidebarShown = sidebarVisible
                edgeTargetChanged()
            }
        }
    }
    var floatingSidebar = false { didSet { needsLayout = true } }
    /// Whether the sidebar is (or is on its way to being) docked beside the page, for WindowFill: a
    /// maximized window keeps the card's inset while it is. animateSidebar sets it at the start of
    /// the slide, so the card goes edge to edge with the sidebar leaving, not after.
    private var edgeSidebarShown = true
    var contentFullscreen = false {
        didSet {
            needsLayout = true
            // A page entering or leaving full screen starts edge to edge, the sidebar away.
            if contentFullscreen != oldValue { fullscreenSidebar = false }
        }
    }
    /// ⌘S over a page in full screen (a video), Arc 1.172: the sidebar docks beside it and the card
    /// steps in from the screen's edges with the normal margin, outline and rounded corners; ⌘S again
    /// and the page fills the screen once more. The sidebar's own setting (sidebarVisible) is left as
    /// it was, for when the page leaves full screen. Hidden, the floating sidebar still comes out
    /// over the page from the screen's left edge.
    private(set) var fullscreenSidebar = false { didSet { needsLayout = true } }
    /// The page fills the screen edge to edge: in full screen and the sidebar not docked beside it.
    var pageFillsScreen: Bool { contentFullscreen && !fullscreenSidebar }

    /// ⌘S over a page in full screen: the sidebar docks beside it (or goes), on the sidebar's slide.
    func setFullscreenSidebar(_ shown: Bool, motion: (duration: TimeInterval, curve: (Double, Double, Double, Double)) = SidebarMotion.docking(animated: false)) {
        guard contentFullscreen, shown != fullscreenSidebar else { return }
        animateSidebar(visible: sidebarVisible, floating: false, fullscreen: true, width: sidebarWidth, duration: motion.duration,
                       curve: motion.curve, fullscreenSidebar: shown)
    }
    /// Settings ▸ "Pages fill the window edge to edge" (GitHub #24).
    var edgeToEdgeSetting = false { didSet { if edgeToEdgeSetting != oldValue { edgeTargetChanged() } } }
    /// No margin, square cards: the setting, or a window that fills its screen (zoomed or full
    /// screen), where the page meets the screen's edges with no gap. Where the card is going; the
    /// frames follow `edgeProgress`.
    var edgeToEdge: Bool { edgeToEdge(maximized: windowMaximized, sidebarShown: edgeSidebarShown) }

    private func edgeToEdge(maximized: Bool, sidebarShown: Bool) -> Bool {
        WindowFill.edgeToEdge(setting: edgeToEdgeSetting, maximized: maximized, fullscreen: windowFullscreen, sidebarShown: sidebarShown,
                              devTools: devToolsVisible || devToolsFrontendDocked)
    }

    // MARK: Edge to edge, in motion

    /// How far the card has gone edge to edge: 0 in the window's margin with rounded corners, 1
    /// flush and square. It moves between them, never jumps, so the card's top-left corner, and the
    /// sidebar toggle in its toolbar with the sidebar hidden, glide to their new place: with the
    /// window's own frame during a zoom (`beginZoom`), on a short ease otherwise.
    private(set) var edgeProgress: CGFloat = 0
    /// The card has arrived flush with the window: page windows take its square corners.
    var edgeFlush: Bool { edgeProgress >= 1 }
    /// The card's corner radius on the way (CraMetrics.contentCornerRadius at rest in the margin).
    var cardRadiusNow: CGFloat { CraMetrics.contentCornerRadius * (1 - edgeProgress) }

    private struct ZoomRun { let start: NSRect; let target: NSRect; let from: CGFloat; let to: CGFloat }
    private var zoomRun: ZoomRun?
    private struct EaseRun { let start: CFTimeInterval; let from: CGFloat; let to: CGFloat; let duration: CFTimeInterval }
    private var easeRun: EaseRun?
    private var edgeLink: CADisplayLink?
    /// Full screen and the setting: the same short ease as the header toggle's glide.
    static let edgeDuration: CFTimeInterval = 0.22

    /// A zoom is taking the window from `start` to `target` on AppKit's own animation, which starts
    /// at once: the card's margin and corners (and the sidebar toggle in its toolbar with the
    /// sidebar hidden) follow the window's frame at every step (followZoom, from layout), so they
    /// move with the window on its curve and land with it, both ways. Nothing holds the zoom back.
    func beginZoom(from start: NSRect, to target: NSRect, maximized: Bool) {
        stopEase()
        let to: CGFloat = edgeToEdge(maximized: maximized, sidebarShown: edgeSidebarShown) ? 1 : 0
        zoomRun = ZoomRun(start: start, target: target, from: edgeProgress, to: to)
        windowMaximized = maximized
        needsLayout = true
    }

    /// The zoom landed (or gave up): the card is where the window says.
    func endZoom() {
        guard zoomRun != nil else { return }
        zoomRun = nil
        setEdgeProgress(edgeToEdge ? 1 : 0)
    }

    private func edgeTargetChanged() {
        guard zoomRun == nil else { return }
        let to: CGFloat = edgeToEdge ? 1 : 0
        guard to != edgeProgress else { stopEase(); return }
        // Off screen (a window being built, a test) there is nothing to watch move.
        guard let window, window.isVisible, Self.edgeDuration > 0 else { stopEase(); setEdgeProgress(to); return }
        let duration = Self.edgeDuration
        easeRun = EaseRun(start: CACurrentMediaTime(), from: edgeProgress, to: to, duration: duration)
        // A tip hanging off the moving toggle would sit over the address field (ArcTooltipController).
        ArcTooltipController.shared.holdForTransition(duration + 0.1)
        if edgeLink == nil {
            let l = displayLink(target: self, selector: #selector(edgeStep))
            l.add(to: .main, forMode: .common)
            edgeLink = l
        }
    }

    @objc private func edgeStep(_ link: CADisplayLink) {
        guard let run = easeRun else { stopEase(); return }
        let t = min(1, max(0, (link.targetTimestamp - run.start) / run.duration))
        // Ease out (cubic): quick away from where it was, settling into place.
        let eased = 1 - pow(1 - t, 3)
        setEdgeProgress(run.from + (run.to - run.from) * eased)
        if t >= 1 { stopEase() }
    }

    private func stopEase() {
        easeRun = nil
        edgeLink?.invalidate()
        edgeLink = nil
    }

    private func setEdgeProgress(_ p: CGFloat) {
        guard p != edgeProgress else { return }
        edgeProgress = p
        needsLayout = true
    }

    /// During a zoom: the card as far along as the window is (WindowFill.zoomProgress).
    private func followZoom() {
        guard let run = zoomRun, let frame = window?.frame else { return }
        let t = WindowFill.zoomProgress(start: run.start, target: run.target, current: frame)
        edgeProgress = run.from + (run.to - run.from) * t
    }
    /// Whether a lone page has a bar: the toolbar, or the developer bar on a Developer Mode site
    /// (AppSettings.showsBar(above:), #185).
    var showToolbar = true { didSet { needsLayout = true } }
    /// Whether the cards carry their bars. Arc keeps every pane's bar in a split even with the
    /// toolbar hidden (View ▸ Show Toolbar is disabled while a split is open, GitHub #178).
    var panesShowBars: Bool { barsShown(panes: paneCards.count, fullscreen: contentFullscreen) }
    private func barsShown(panes: Int, fullscreen: Bool) -> Bool { !fullscreen && (showToolbar || panes > 1) }
    var hasTab = false { didSet { needsLayout = true } }
    var onEdgeHover: ((Bool) -> Void)?
    /// Set again each time the window becomes key; only a change rebuilds the backdrop.
    var windowActive = true {
        didSet { if windowActive != oldValue { refreshLift() } }
    }

    /// Dark vibrant themes keep the earlier calibration (underWindowBackground + 15% lift).
    private(set) var vibrantDark = false

    /// A space's theme in one refresh: set one flag at a time, a switch from a vibrant to a solid
    /// space drew a frame with the vibrant calibration (two cra.log lines, dim 0.36 then 0.30).
    func setTheme(vibrantDark: Bool, vibrantLight: Bool, solid: Bool) {
        self.vibrantDark = vibrantDark
        self.vibrantLight = vibrantLight
        solidBackdrop = solid
        refreshLift()
    }

    /// Core Animation's gaussian blur (the filter NSVisualEffectView uses), built
    /// through its private class; nil when the runtime does not provide it.
    static func makeBackdropBlur(radius: Double) -> NSObject? {
        guard let cls = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let sel = NSSelectorFromString("filterWithType:")
        guard cls.responds(to: sel), let filter = cls.perform(sel, with: "gaussianBlur")?.takeUnretainedValue() as? NSObject else { return nil }
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        return filter
    }

    /// The hudWindow material's capture, as AppKit builds it (probe dump, 5 Nov 2026): an eighth-scale
    /// capture under SDR normalize, a 30 pt blur and saturate 1.6. Cra's own full-scale 40 pt blur was
    /// blurrier and greyer than Arc's over a colourful backdrop, and 64 times the pixels for the window
    /// server to rebuild whenever the capture comes back (the dropout out of Stage Manager, GitHub #156).
    /// Over the plain white and black backdrops the dim and lift were fitted on, it draws the same.
    static let backdropScale = 0.125
    static func makeBackdropFilters() -> [NSObject] {
        guard let blur = makeBackdropBlur(radius: 30) else { return [] }
        let tint = makeTintFilters()
        return tint.count == 2 ? [tint[0], blur, tint[1]] : [blur]
    }

    /// The hudWindow material's filters on its desktop tint: SDR normalize, saturate 1.6.
    static func makeTintFilters() -> [NSObject] {
        guard let cls = NSClassFromString("CAFilter") as? NSObject.Type else { return [] }
        let sel = NSSelectorFromString("filterWithType:")
        guard cls.responds(to: sel) else { return [] }
        let make = { (type: String) in cls.perform(sel, with: type)?.takeUnretainedValue() as? NSObject }
        guard let normalize = make("sdrNormalize"), let saturate = make("colorSaturate") else { return [] }
        saturate.setValue(1.6, forKey: "inputAmount")
        return [normalize, saturate]
    }

    /// Which blur path this run takes, once: scenarios run both (CRA_FLAGS) and the
    /// log says which one a crash or a stall happened on.
    private static var loggedBackdropPath = false
    private static func logBackdropPath(layer: Bool) {
        guard !loggedBackdropPath else { return }
        loggedBackdropPath = true
        let why = FeatureFlags.current.backdrop == .material ? "CRA_FLAGS" : "no CABackdropLayer or CAFilter"
        CraLog.note("sidebar backdrop: " + (layer ? "layer" : "material (\(why))"))
    }

    func refreshLift() {
        let t = CraTuning.shared
        let lift = vibrantDark ? (windowActive ? 0.15 : 0.93) : (windowActive ? t.liftActive : t.liftInactive)
        vibrancyLift.layer?.backgroundColor = NSColor(white: 1, alpha: lift).cgColor
        if usesBackdropLayer {
            vibrancy.isHidden = true
            vibrancyLift.isHidden = true
            backdropHost.isHidden = false
            CATransaction.begin(); CATransaction.setDisableActions(true)
            let backdrop = SidebarBackdrop.resolve(
                solid: solidBackdrop, active: windowActive, fullscreen: windowFullscreen,
                reduceTransparency: reduceTransparency, tintAvailable: desktopTintLayer != nil,
                vibrant: .init(dim: t.blurDim, liftTop: t.liftActive, liftBottom: t.liftActiveBottom,
                               dimInactive: t.blurDimInactive, liftInactive: t.liftInactive))
            dimLayer.opacity = Float(backdrop.dim)
            // The desktop tint stays in the tree, as in AppKit's material: at 0.05 windowed, active or not,
            // and in place of the blur in full screen. Only Reduce transparency takes it out. Inserted
            // fresh, it drew nothing until the window server had resolved it (GitHub #156). It sits under
            // the capture and the fill, so at 0.05 it doesn't change the calibrated colours.
            if let tint = desktopTintLayer {
                if reduceTransparency { tint.removeFromSuperlayer() } else if tint.superlayer == nil { backdropHost.layer?.insertSublayer(tint, at: 0) }
                tint.opacity = backdrop.source == .desktopTint ? 1 : 0.05
            }
            // A capture added back on activation draws the substitute colour until it is live, where
            // one kept under the fill showed the window behind sharp for a frame (GitHub #132).
            if let b = backdropLayer, (backdrop.source == .blur) != (b.superlayer != nil) {
                if backdrop.source == .blur { backdropHost.layer?.insertSublayer(b, at: desktopTintLayer?.superlayer == nil ? 0 : 1) } else { b.removeFromSuperlayer() }
            }
            liftLayer.colors = [NSColor(white: 1, alpha: backdrop.liftTop).cgColor, NSColor(white: 1, alpha: backdrop.liftBottom).cgColor]
            CATransaction.commit()
            let state = backdrop.logLine(active: windowActive, reduceTransparency: reduceTransparency)
            if state != loggedBackdrop {
                loggedBackdrop = state
                CraLog.note("sidebar backdrop: " + state)
            }
        } else {
            backdropHost.isHidden = true
            vibrancyLift.isHidden = false
            vibrancy.isHidden = !(vibrantLight || vibrantDark)
        }
        vibrancy.material = vibrantDark ? .underWindowBackground : t.material
        vibrancy.state = (t.forceActiveBlur || windowActive) ? .active : .inactive
        vibrancy.appearance = NSAppearance(named: t.darkBlur ? .darkAqua : .aqua)
    }
    var statusVisible = false
    var findVisible = false
    private var trackingArea: NSTrackingArea?

    init(frame: NSRect, background: NSView, sidebar: NSView, toolbar: NSView, status: NSView, find: NSView) {
        backgroundHost = background
        sidebarHost = sidebar
        statusHost = status
        findHost = find
        overlayParent = contentContainer
        super.init(frame: frame)
        wantsLayer = true

        vibrancy.blendingMode = .behindWindow
        vibrancy.material = .underWindowBackground
        vibrancy.state = .active
        vibrancy.isHidden = true
        addSubview(vibrancy)
        addSubview(activeAppearance)
        backdropHost.wantsLayer = true
        // A CABackdropLayer only blurs what is behind the window through Core
        // Animation's own filters (private CAFilter "gaussianBlur"); a CIFilter in
        // `filters` is ignored for the backdrop capture, which left the sidebar fully
        // see-through (25 Oct 2026). Without the filter class we keep the NSVisualEffectView path.
        // The window server only keeps a behind-window capture live for a layer that is
        // window-server aware in AppKit's capture group (NSVisualEffectView's own settings);
        // without them the blur showed only while the window was redrawing (GitHub #37).
        if FeatureFlags.current.backdrop == .layer,
           let cls = NSClassFromString("CABackdropLayer") as? CALayer.Type,
           case let filters = ShellView.makeBackdropFilters(), !filters.isEmpty {
            let b = cls.init()
            b.filters = filters
            b.setValue(ShellView.backdropScale, forKey: "scale")
            b.setValue(true, forKey: "windowServerAware")
            b.setValue("NSCGSWindowBehindWindowCaptureBackdropGroup", forKey: "groupName")
            // While the window server rebuilds the capture (activation, a Space switch) the
            // layer showed the stale, unblurred backdrop: the window behind, sharp (GitHub
            // #83). NSVisualEffectView's own layer allows a substitute colour for that time.
            if b.responds(to: NSSelectorFromString("setAllowsSubstituteColor:")) { b.setValue(true, forKey: "allowsSubstituteColor") }
            backdropHost.layer?.addSublayer(b)
            backdropLayer = b
            // AppKit's tint carries the material's colour filters, not the blur (hudWindow). Bare,
            // it skipped the SDR normalize and the saturate: the fullscreen sidebar came out greyer
            // than Arc's, and dark on the display in GitHub #132.
            if let tintClass = NSClassFromString("CAChameleonLayer") as? CALayer.Type {
                let t = tintClass.init()
                t.filters = ShellView.makeTintFilters()
                desktopTintLayer = t
            }
        }
        dimLayer.backgroundColor = NSColor.black.cgColor
        backdropHost.layer?.addSublayer(dimLayer)
        liftLayer.startPoint = CGPoint(x: 0.5, y: 1)
        liftLayer.endPoint = CGPoint(x: 0.5, y: 0)
        backdropHost.layer?.addSublayer(liftLayer)
        backdropHost.isHidden = true
        addSubview(backdropHost)
        Self.logBackdropPath(layer: backdropLayer != nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityDisplayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        vibrancyLift.wantsLayer = true
        vibrancyLift.layer?.backgroundColor = NSColor(white: 1, alpha: 0.15).cgColor
        vibrancyLift.isHidden = true
        addSubview(vibrancyLift)
        addSubview(backgroundHost)
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(contentContainer)
        addSubview(pageDrop)
        addSubview(loadingIndicator)
        parkingView.isHidden = true
        parkingView.autoresizesSubviews = false
        contentContainer.addSubview(parkingView)
        devToolsHost.wantsLayer = true
        devToolsHost.layer?.backgroundColor = NSColor.white.cgColor
        devToolsHost.isHidden = true
        devToolsDivider.wantsLayer = true
        devToolsDivider.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor
        devToolsDivider.isHidden = true
        devToolsHandle.isHidden = true
        devToolsHandle.onDrag = { [weak self] dx in
            guard let self else { return }
            self.devToolsWidth = min(max(320, self.devToolsWidth - dx), self.contentContainer.bounds.width * 0.7)
            self.layoutSubtreeIfNeeded()
        }
        contentContainer.addSubview(placeholderHost)
        sidePanel.isHidden = true
        sidePanelHandle.isHidden = true
        contentContainer.addSubview(sidePanel)
        contentContainer.addSubview(sidePanelHandle)
        for h in [statusHost, findHost] as [NSView] {
            h.isHidden = true
            contentContainer.addSubview(h)
        }
        // Start with the no-tab card so the toolbar exists from the first frame.
        let card = PaneCardView(tabID: ShellView.noTabID, toolbar: toolbar)
        card.hasPage = false
        card.transparent = true
        contentContainer.addSubview(card)
        paneCards = [card]
        paneIDs = []
        drawerShade.isHidden = true
        addSubview(drawerShade)
        // The loading bar over the drawer's shade: a load beside the open Library still shows.
        addSubview(loadingIndicator, positioned: .above, relativeTo: drawerShade)
        drawerMask.backgroundColor = NSColor.black.cgColor
        sidebarHost.wantsLayer = true
        sidebarHost.layer?.cornerCurve = .continuous
        addSubview(sidebarHost)
        addSubview(resizeHandle)
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func accessibilityDisplayOptionsChanged() {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        guard reduce != reduceTransparency else { return }
        reduceTransparency = reduce
        refreshLift()
    }

    override var isFlipped: Bool { false }

    // MARK: Panes

    var focusedCard: PaneCardView? {
        if let id = focusedPaneID, let c = paneCards.first(where: { $0.tabID == id }) { return c }
        return paneCards.first
    }
    func card(for id: UUID) -> PaneCardView? { paneCards.first { $0.tabID == id } }
    /// The focused pane's page area; the parking view when there is none.
    var webContainer: NSView { (hasTab ? focusedCard?.webArea : nil) ?? parkingView }

    /// Show these panes (tab ids in pane order). Empty = the no-tab state.
    /// Adding or removing panes animates like Arc (collapsed ↔ expanded).
    func setPanes(_ ids: [UUID], factors: [UUID: CGFloat], orientation: SplitOrientation, focused: UUID?, empty: Set<UUID>, animated: Bool) {
        let shownIDs = ids.isEmpty ? [ShellView.noTabID] : ids
        let previous = paneCards.map(\.tabID)
        let structural = previous != shownIDs || orientation != splitOrientation
        paneIDs = ids
        paneFactors = factors
        splitOrientation = orientation
        focusedPaneID = focused ?? ids.first
        emptyPaneIDs = empty
        hasTab = !ids.isEmpty
        // A click into another pane changes only the focus; the ring moves in the same pass.
        defer { updateFocusRings() }
        for h in handles { h.orientation = orientation }

        guard structural else {
            for c in paneCards { c.hasPage = c.tabID != ShellView.noTabID && !empty.contains(c.tabID) }
            needsLayout = true
            return
        }

        // One pane before and after, a plain tab switch: the card follows the tab.
        if paneCards.count == 1, shownIDs.count == 1, let card = paneCards.first,
           (card.tabID == ShellView.noTabID) == (shownIDs[0] == ShellView.noTabID) {
            let id = shownIDs[0]
            card.retarget(to: id)
            card.pageColor = pageColors[id]
            card.toolbarColor = toolbarColors[id]
            card.hasPage = id != ShellView.noTabID && !empty.contains(id)
            needsLayout = true
            return
        }

        let oldFrames = Dictionary(uniqueKeysWithValues: paneCards.map { ($0.tabID, $0.frame) })
        var cards: [PaneCardView] = []
        for id in shownIDs {
            if let existing = paneCards.first(where: { $0.tabID == id }) {
                cards.append(existing)
            } else {
                let card = PaneCardView(tabID: id, toolbar: makeToolbar?(id == ShellView.noTabID ? nil : id) ?? NSView())
                card.isDark = isDarkTheme
                card.pageColor = pageColors[id]
                card.toolbarColor = toolbarColors[id]
                card.transparent = id == ShellView.noTabID
                card.showToolbar = barsShown(panes: shownIDs.count, fullscreen: contentFullscreen)
                card.onToolbarHeightChange = { [weak self] in self?.needsLayout = true }
                contentContainer.addSubview(card, positioned: .below, relativeTo: placeholderHost)
                cards.append(card)
            }
        }
        let removed = paneCards.filter { c in !shownIDs.contains(c.tabID) }
        paneCards = cards
        for c in paneCards {
            c.hasPage = c.tabID != ShellView.noTabID && !empty.contains(c.tabID)
        }
        while handles.count < max(0, paneCards.count - 1) {
            let h = SplitDraggerHandleView(frame: .zero)
            h.orientation = orientation
            let index = handles.count
            h.onDragBegan = { [weak self] in self?.beginPaneDrag(index) }
            h.onDrag = { [weak self] d in self?.dragPane(index, delta: d) }
            h.onDragEnded = { [weak self] in self?.endPaneDrag() }
            h.onDoubleClick = { [weak self] in self?.resetPaneWidths() }
            contentContainer.addSubview(h, positioned: .below, relativeTo: placeholderHost)
            handles.append(h)
        }
        while handles.count > max(0, paneCards.count - 1) { handles.removeLast().removeFromSuperview() }

        let target = paneLayout(in: contentContainer.bounds)
        // Observed on Arc 1.170 (per-window frames at 27 fps): a new pane
        // appears fully laid out within one frame; only the command bar fades in.
        guard animated, SplitPaneLayout.Constants.transitionDuration > 0, !oldFrames.isEmpty, window != nil else {
            for c in removed { c.removeFromSuperview() }
            needsLayout = true
            layoutSubtreeIfNeeded()
            return
        }

        // New panes grow from a collapsed sliver at their slot; closing panes shrink to one.
        let horizontal = orientation == .horizontal
        for c in paneCards where oldFrames[c.tabID] == nil {
            guard let f = target.frames[c.tabID] else { continue }
            c.frame = horizontal ? NSRect(x: f.minX, y: f.minY, width: 0, height: f.height) : NSRect(x: f.minX, y: f.maxY, width: f.width, height: 0)
            c.alphaValue = 0
            c.frozenWebBounds = NSRect(x: 0, y: 0, width: f.width, height: max(0, f.height - (c.showToolbar ? c.toolbarHeight : 0)))
            c.layoutSubtreeIfNeeded()
        }
        for c in paneCards where oldFrames[c.tabID] != nil {
            guard let f = target.frames[c.tabID] else { continue }
            c.frozenWebBounds = NSRect(x: 0, y: 0, width: f.width, height: max(0, f.height - (c.showToolbar ? c.toolbarHeight : 0)))
        }
        animatingPanes = true
        let webTargets = paneWebFrames(target)
        onAnimatePaneFrames?(webTargets, SplitPaneLayout.Constants.transitionDuration, SplitPaneLayout.Constants.transitionTiming)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = SplitPaneLayout.Constants.transitionDuration
            ctx.timingFunction = SplitPaneLayout.Constants.transitionTiming
            ctx.allowsImplicitAnimation = true
            for c in paneCards {
                if let f = target.frames[c.tabID] { c.animator().frame = f }
                c.animator().alphaValue = 1
            }
            for c in removed {
                let f = c.frame
                c.animator().frame = horizontal ? NSRect(x: f.minX, y: f.minY, width: 0, height: f.height) : NSRect(x: f.minX, y: f.maxY, width: f.width, height: 0)
                c.animator().alphaValue = 0
            }
            for (i, h) in handles.enumerated() where i < target.gaps.count {
                h.animator().frame = target.gaps[i]
            }
        } completionHandler: { [weak self] in
            guard let self else { return }
            for c in removed { c.removeFromSuperview() }
            self.animatingPanes = false
            for c in self.paneCards { c.frozenWebBounds = nil }
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
        }
    }

    /// Arc rings the focused pane while the window shows several; one pane fills the window
    /// unmarked. A page in full screen has no card around it.
    private func updateFocusRings() {
        let ringed = paneCards.count > 1 && !contentFullscreen
        for c in paneCards {
            let ring = ringed && c.tabID == focusedPaneID ? focusRingColor : nil
            if c.focusRing != ring { c.focusRing = ring }
        }
    }

    /// The side panel's width in `bounds` (the content area), 0 when none shows: none open, a
    /// page in full screen, or no room beside the page.
    private func sidePanelShownWidth(in bounds: NSRect) -> CGFloat {
        let gap = Double(SplitPaneLayout.Constants.gap)
        let pages = sidePanelPageMinimum
        guard sidePanelWidth > 0, hasTab, !contentFullscreen,
              ExtensionSidePanelWidth.fits(container: Double(bounds.width), gap: gap, pages: pages) else { return 0 }
        return CGFloat(ExtensionSidePanelWidth.clamp(Double(sidePanelWidth), container: Double(bounds.width), gap: gap, pages: pages)).rounded()
    }

    /// What the panes need beside the side panel: each split pane keeps its minimum.
    var sidePanelPageMinimum: Double {
        ExtensionSidePanelWidth.pageMinimum(panes: paneCards.count, paneMinimum: Double(SplitPaneLayout.Constants.minimumPaneLength),
                                            gap: Double(SplitPaneLayout.Constants.gap), sideBySide: splitOrientation == .horizontal)
    }

    /// The panes' share of `bounds`: all of it, less the side panel and its gap on the right.
    private func paneArea(in bounds: NSRect) -> NSRect {
        let w = sidePanelShownWidth(in: bounds)
        guard w > 0 else { return bounds }
        return NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width - w - SplitPaneLayout.Constants.gap, height: bounds.height)
    }

    private func paneLayout(in bounds: NSRect) -> SplitPaneLayout.Result {
        let ids = paneCards.map(\.tabID)
        let panes = ids.map { SplitPaneLayout.Pane(id: $0, factor: paneFactors[$0] ?? (1 / CGFloat(max(1, ids.count)))) }
        var layout = SplitPaneLayout(panes: panes, orientation: splitOrientation, containerSize: paneArea(in: bounds).size)
        layout.backingScaleFactor = window?.backingScaleFactor ?? 2
        return layout.compute()
    }

    /// Each pane's page area in window coordinates, for the given card frames.
    private func paneWebFrames(_ layout: SplitPaneLayout.Result) -> [UUID: NSRect] {
        var out: [UUID: NSRect] = [:]
        for c in paneCards where c.tabID != ShellView.noTabID {
            guard let f = layout.frames[c.tabID] else { continue }
            let th: CGFloat = panesShowBars ? c.toolbarHeight : 0
            var web = NSRect(x: f.minX, y: f.minY, width: f.width, height: max(0, f.height - th))
            if c.tabID == focusedPaneID, devToolsVisible, !devToolsFrontendDocked, f.width > 640 {
                web.size.width -= min(max(320, devToolsWidth), f.width * 0.7)
            }
            out[c.tabID] = contentContainer.convert(web, to: nil)
        }
        return out
    }

    // MARK: Divider drags

    private var dragStartFactors: [UUID: CGFloat] = [:]

    private func beginPaneDrag(_ index: Int) {
        dragStartFactors = paneFactors
        for c in paneCards { c.frozenWebBounds = nil }
        onPaneResizeBegan?()
    }

    private func dragPane(_ index: Int, delta: CGFloat) {
        let ids = paneCards.map(\.tabID)
        let panes = ids.map { SplitPaneLayout.Pane(id: $0, factor: dragStartFactors[$0] ?? (1 / CGFloat(max(1, ids.count)))) }
        let layout = SplitPaneLayout(panes: panes, orientation: splitOrientation, containerSize: paneArea(in: contentContainer.bounds).size)
        paneFactors = layout.dragging(dividerAfter: index, by: delta).factors
        layoutContentChildren()
    }

    private func endPaneDrag() {
        onPaneResizeEnded?(paneFactors)
    }

    private func resetPaneWidths() {
        let n = CGFloat(max(1, paneCards.count))
        for c in paneCards { paneFactors[c.tabID] = 1 / n }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = SplitPaneLayout.Constants.transitionTiming
            ctx.allowsImplicitAnimation = true
            layoutContentChildren(animated: true)
        }
        onPaneResizeEnded?(paneFactors)
    }

    // MARK: Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        // activeAlways: the key window is usually a Chromium page window, and the
        // edge hover must still follow the pointer over the shell.
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let p = convert(event.locationInWindow, from: nil)
        guard !sidebarVisible, !contentFullscreen else { return }
        if !floatingSidebar, FloatingSidebarGeometry.shouldReveal(at: p, in: bounds, edgeToEdge: edgeToEdge) {
            onEdgeHover?(true)
        } else if floatingSidebar, FloatingSidebarGeometry.shouldHide(at: p, in: bounds, sidebarWidth: sidebarWidth,
                                                                     pressedMouseButtons: NSEvent.pressedMouseButtons, edgeToEdge: edgeToEdge) {
            onEdgeHover?(false)
        }
    }

    /// Leaving the shell no longer hides the floating sidebar: the pointer moving onto
    /// the floating panel or a page window counts as an exit here, so the window
    /// controller's pointer monitor decides instead.
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
    }

    /// While the sidebar floats in its own panel (Chrome-style hosting puts page
    /// windows above the shell), the shell leaves `sidebarHost`'s frame alone.
    var sidebarDetached = false

    // MARK: The Library's drawer

    /// The Library's drawer: the sidebar widens to this. Beside a docked sidebar the page card moves
    /// right with the drawer's edge at its own size, so nothing in it reflows and the window never
    /// changes; the window cuts it off at its right edge. A floating sidebar's panel takes the width
    /// over the page the same way, the card staying put under it. nil: closed.
    var drawerWidth: CGFloat? {
        didSet {
            guard drawerWidth != oldValue else { return }
            needsLayout = true
            onDrawerWidthChange?()
        }
    }
    /// The drawer's width changed: the floating panel follows it (MainWindowController).
    var onDrawerWidthChange: (() -> Void)?
    /// The sidebar's width as drawn: its own, or the drawer's while that is wider.
    var shownSidebarWidth: CGFloat { max(sidebarWidth, drawerWidth ?? 0) }
    private let drawerShade = DrawerShadeView()
    private let drawerMask = CALayer()
    private struct DrawerRun { let start: CFTimeInterval; let from: CGFloat; let to: CGFloat; let end: CGFloat? }
    private var drawerRun: DrawerRun?
    private var drawerLink: CADisplayLink?
    private var drawerDone: (() -> Void)?
    /// The drawer's slide: quick, a touch of give, no bounce past its width.
    static let drawerSpring = SpringMotion(response: 0.3, dampingFraction: 0.9)

    /// Slides the drawer open to `width`, or closed (nil) back to the sidebar's own width, on
    /// `drawerSpring`; at once with Reduce Motion or off screen. `completion` runs as it lands.
    func animateDrawer(to width: CGFloat?, completion: (() -> Void)? = nil) {
        let from = drawerWidth ?? sidebarWidth
        let to = width ?? sidebarWidth
        finishDrawer(land: false)
        guard let window, window.isVisible, abs(to - from) > 0.5,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            drawerWidth = width
            completion?()
            return
        }
        drawerDone = completion
        drawerRun = DrawerRun(start: CACurrentMediaTime(), from: from, to: to, end: width)
        let l = displayLink(target: self, selector: #selector(drawerStep))
        l.add(to: .main, forMode: .common)
        drawerLink = l
    }

    @objc private func drawerStep(_ link: CADisplayLink) {
        guard let run = drawerRun else { finishDrawer(land: false); return }
        let t = link.targetTimestamp - run.start
        let s = Self.drawerSpring
        if t >= s.settlingDuration { finishDrawer(land: true); return }
        drawerWidth = (run.to + (run.from - run.to) * CGFloat(s.offset(at: t))).rounded()
        layoutSubtreeIfNeeded()
    }

    /// The drawer at `width` at once (out of sight), a slide in flight stopped first.
    func setDrawer(_ width: CGFloat?) {
        finishDrawer(land: false)
        drawerWidth = width
    }

    /// Ends a slide in flight; `land` puts the drawer at its end first.
    private func finishDrawer(land: Bool) {
        drawerLink?.invalidate()
        drawerLink = nil
        if land, let run = drawerRun { drawerWidth = run.end }
        drawerRun = nil
        let done = drawerDone
        drawerDone = nil
        done?()
    }

    /// The card under the docked drawer: hidden by a mask from the drawer's edge, shaded along it.
    private func placeDrawerCover(sidebar: NSRect, content: NSRect) {
        let overlap = sidebarVisible && !floatingSidebar && !sidebarDetached && !contentFullscreen ? sidebar.maxX - content.minX : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if overlap > 0.5, let layer = contentContainer.layer {
            // Room beyond the card for its shadow above, below and to the right.
            let pad: CGFloat = 60
            drawerMask.frame = CGRect(x: overlap, y: -pad, width: max(0, content.width - overlap) + pad, height: content.height + 2 * pad)
            if layer.mask !== drawerMask { layer.mask = drawerMask }
            drawerShade.isHidden = false
            drawerShade.frame = NSRect(x: sidebar.maxX, y: content.minY, width: DrawerShadeView.width, height: content.height)
            drawerShade.alphaValue = min(1, overlap / 24)
        } else {
            if contentContainer.layer?.mask != nil { contentContainer.layer?.mask = nil }
            drawerShade.isHidden = true
        }
        CATransaction.commit()
    }

    // MARK: Layout

    struct Frames {
        var sidebar: NSRect
        var handle: NSRect
        var content: NSRect
        var cornerRadius: CGFloat
        var sidebarCorner: CGFloat
    }

    func frames(sidebarVisible: Bool, floating: Bool, fullscreen: Bool, width: CGFloat) -> Frames {
        let b = bounds
        if fullscreen, fullscreenSidebar {
            // Docked beside a page in full screen: Arc's inset card, whatever the window's own rule.
            let inset = CraMetrics.contentInset
            return Frames(sidebar: NSRect(x: 0, y: 0, width: width, height: b.height), handle: .zero,
                          content: NSRect(x: width, y: inset, width: max(0, b.width - width - inset), height: max(0, b.height - 2 * inset)),
                          cornerRadius: CraMetrics.contentCornerRadius, sidebarCorner: 0)
        }
        if fullscreen {
            return Frames(sidebar: NSRect(x: -width, y: 0, width: width, height: b.height),
                          handle: .zero, content: b, cornerRadius: 0, sidebarCorner: 0)
        }
        // Edge to edge (the setting, a zoomed window, full screen) the card fills what the sidebar
        // leaves, square; a window's own corners round it where they meet. On the way the margin and
        // the corners shrink together (edgeProgress), to the half point so edges stay crisp.
        let inset = WindowFill.inset(CraMetrics.contentInset, progress: edgeProgress)
        let radius = cardRadiusNow
        // The Library's drawer widens the sidebar; beside a docked sidebar the card moves right with
        // the drawer's edge at its own size (Arc 1.172.1, 10 Nov 2026), running out past the window's
        // right edge, so the page never reflows, resizes or hides under the drawer.
        let drawn = max(width, drawerWidth ?? 0)
        if sidebarVisible {
            let content = NSRect(x: drawn, y: inset, width: max(0, b.width - width - inset), height: max(0, b.height - 2 * inset))
            return Frames(sidebar: NSRect(x: 0, y: 0, width: drawn, height: b.height),
                          handle: NSRect(x: drawn - 4, y: 0, width: 8, height: b.height),
                          content: content, cornerRadius: radius, sidebarCorner: 0)
        }
        if floating {
            // The floating sidebar hovers over the page; the card does not move (Arc).
            let m = FloatingSidebarGeometry.margin
            return Frames(sidebar: NSRect(x: m, y: m, width: drawn, height: b.height - 2 * m),
                          handle: .zero, content: b.insetBy(dx: inset, dy: inset), cornerRadius: radius, sidebarCorner: 12)
        }
        // Sidebar hidden: Arc keeps the rounded card floating in its inset (measured 25 Oct:
        // card edge 10 pt from the window edge after ⌘S), with a sidebar toggle in the bar.
        return Frames(sidebar: NSRect(x: -drawn - 20, y: 0, width: drawn, height: b.height),
                      handle: .zero, content: b.insetBy(dx: inset, dy: inset), cornerRadius: radius, sidebarCorner: 0)
    }

    private var cardCornerRadius: CGFloat = CraMetrics.contentCornerRadius
    fileprivate var cardCornerRadiusNow: CGFloat { cardCornerRadius }
    fileprivate func setCardCornerRadius(_ r: CGFloat) {
        cardCornerRadius = r
        if paneCards.count == 1, let c = paneCards.first { c.cornerRadius = r }
    }
    fileprivate func setAnimatingFrames(_ on: Bool) { animatingFrames = on }
    /// The docking glide in progress (startSidebarRun).
    fileprivate var sidebarRun: SidebarRun?
    fileprivate var sidebarLink: CADisplayLink?

    override func layout() {
        super.layout()
        vibrancy.frame = bounds
        backdropHost.frame = bounds
        CATransaction.begin(); CATransaction.setDisableActions(true)
        backdropLayer?.frame = backdropHost.bounds
        desktopTintLayer?.frame = backdropHost.bounds
        dimLayer.frame = backdropHost.bounds
        liftLayer.frame = backdropHost.bounds
        CATransaction.commit()
        vibrancyLift.frame = bounds
        backgroundHost.frame = bounds
        followZoom()
        if animatingFrames { layoutContentChildren(); return }
        let f = frames(sidebarVisible: sidebarVisible, floating: floatingSidebar, fullscreen: contentFullscreen, width: sidebarWidth)
        apply(f)
    }

    func apply(_ f: Frames) {
        if !sidebarDetached { sidebarHost.frame = f.sidebar }
        if !resizeHandle.dragging {
            resizeHandle.frame = f.handle
            resizeHandle.isHidden = f.handle.isEmpty || !sidebarResizable
        }
        contentContainer.frame = f.content
        pageDrop.frame = f.content
        pageDrop.cornerRadius = f.cornerRadius
        placeDrawerCover(sidebar: f.sidebar, content: f.content)
        placeLoadingIndicator(over: f.content)
        cardCornerRadius = f.cornerRadius
        sidebarHost.layer?.cornerRadius = f.sidebarCorner
        if f.sidebarCorner > 0 {
            sidebarHost.shadow = NSShadow()
            sidebarHost.shadow?.shadowBlurRadius = 24
            sidebarHost.shadow?.shadowOffset = NSSize(width: 0, height: -6)
            sidebarHost.shadow?.shadowColor = NSColor.black.withAlphaComponent(0.3)
        } else {
            sidebarHost.shadow = nil
        }
        layoutContentChildren()
    }

    /// Centred over the card, in the margin above it, or just inside its top edge where there is
    /// none (LoadingIndicator.frame); hidden over a page in full screen.
    private func placeLoadingIndicator(over content: NSRect) {
        let f = LoadingIndicator.frame(content: content, in: bounds, pageFullscreen: contentFullscreen && !fullscreenSidebar)
        loadingIndicator.isHidden = f == nil
        if let f { loadingIndicator.frame = f }
    }

    private func loadingIndicatorFrame(over content: NSRect) -> NSRect {
        LoadingIndicator.frame(content: content, in: bounds, pageFullscreen: false) ?? loadingIndicator.frame
    }

    /// `cra://debug?windowState`: the bar's phase, whether it shows, and where ("waiting,1,679,790").
    var debugLoading: String {
        let f = loadingIndicator.frame
        return "\(loadingIndicator.phase),\(loadingIndicator.isHidden || loadingIndicator.superview == nil ? 0 : 1),\(Int(f.minX)),\(Int(f.minY))"
    }

    /// The front tab's loading state. Another tab coming to the front shows its state at once.
    func setLoading(_ phase: LoadingIndicator.Phase, tab: UUID?) {
        let sameTab = tab == loadingTabID
        loadingTabID = tab
        loadingIndicator.setPhase(phase, animated: sameTab)
    }

    func layoutContentChildren(animated: Bool = false) {
        let cb = contentContainer.bounds
        updateFocusRings()
        let toolbarVisible = panesShowBars
        let layout = paneLayout(in: cb)
        for c in paneCards {
            c.showToolbar = toolbarVisible
            // Arc's cards cast a soft shadow on the window; edge to edge there is no margin for it.
            c.castsShadow = !edgeFlush && !pageFillsScreen
            // Several panes: every card is rounded; a single card follows the window state (square in fullscreen).
            // Edge to edge every card is square.
            c.cornerRadius = paneCards.count > 1 && !edgeToEdge ? CraMetrics.contentCornerRadius : cardCornerRadius
            if !animatingPanes, let f = layout.frames[c.tabID] {
                if animated { c.animator().frame = f } else if c.frame != f { c.frame = f }
            }
            c.layoutSubtreeIfNeeded()
        }
        for (i, h) in handles.enumerated() {
            h.isHidden = i >= layout.gaps.count
            if !animatingPanes, i < layout.gaps.count {
                if animated { h.animator().frame = layout.gaps[i] } else { h.frame = layout.gaps[i] }
            }
        }
        placeholderHost.frame = cb
        placeholderHost.isHidden = hasTab
        layoutSidePanel(in: cb)
        // The no-tab card is rounded like a page's (GitHub #6: a new window showed a square one).
        placeholderHost.layer?.cornerRadius = cardCornerRadius
        placeholderHost.layer?.cornerCurve = .continuous
        parkingView.frame = cb

        // DevTools docks inside the focused card, right of its page.
        let focus = focusedCard
        let fb = focus?.bounds ?? .zero
        let th: CGFloat = toolbarVisible ? focus?.toolbarHeight ?? CraMetrics.toolbarHeight : 0
        let bodyH = max(0, fb.height - th)
        let selfDock = devToolsFrontendDocked
        let showDev = devToolsVisible && hasTab && focus != nil && (selfDock || fb.width > 640)
        let devW: CGFloat = showDev && !selfDock ? min(max(320, devToolsWidth), fb.width * 0.7) : 0
        if let focus, showDev {
            for v in [devToolsHost, devToolsDivider, devToolsHandle] where v.superview !== focus { v.removeFromSuperview(); focus.addSubview(v) }
            focus.webArea.frame = NSRect(x: 0, y: 0, width: fb.width - devW, height: bodyH)
            EmbeddedPages.place(focus.webArea.subviews, in: focus.frozenWebBounds ?? focus.webArea.bounds)
        }
        // A frontend-docked DevTools paints its own split; the shell's dock chrome stays hidden.
        devToolsHost.isHidden = !showDev || selfDock
        devToolsDivider.isHidden = !showDev || selfDock
        devToolsHandle.isHidden = !showDev || selfDock
        let devFrame = selfDock ? NSRect(x: 0, y: 0, width: fb.width, height: bodyH)
                                : NSRect(x: fb.width - devW, y: 0, width: devW, height: bodyH)
        devToolsHost.frame = devFrame
        devToolsDivider.frame = NSRect(x: fb.width - devW, y: 0, width: 1, height: bodyH)
        devToolsHandle.frame = NSRect(x: fb.width - devW - 3, y: 0, width: 7, height: bodyH)
        for sub in devToolsHost.subviews { sub.frame = devToolsHost.bounds }
        if showDev, let focus { onDevToolsFrame?(focus.convert(devFrame, to: nil)) }

        // Overlays sit over the focused page (in the container, or in the overlay panel).
        var webInContainer = focus.map { contentContainer.convert($0.webArea.frame, from: $0) } ?? cb
        if showDev, selfDock, let pr = frontendPageRect { webInContainer = contentContainer.convert(pr, from: nil) }
        let wb = overlayParent === contentContainer ? webInContainer : NSRect(origin: .zero, size: webInContainer.size)
        if overlayParent === contentContainer {
            for h in [statusHost, findHost] where contentContainer.subviews.last !== h {
                contentContainer.addSubview(h, positioned: .above, relativeTo: nil)
            }
        }
        statusHost.isHidden = !statusVisible
        statusHost.frame = NSRect(x: wb.minX, y: wb.minY, width: min(540, wb.width), height: 34)
        if findHost.superview === overlayParent {
            let size = CraMetrics.findBarSize, inset = CraMetrics.findBarInset
            findHost.isHidden = !findVisible
            findHost.frame = NSRect(x: wb.maxX - size.width - inset, y: wb.maxY - size.height - inset, width: size.width, height: size.height)
        }
        if !animatingPanes, paneCards.allSatisfy({ $0.frozenWebBounds == nil }) { onPaneFrames?(paneWebFrames(layout)) }
    }

    private func layoutSidePanel(in cb: NSRect) {
        let w = sidePanelShownWidth(in: cb)
        sidePanel.isHidden = w == 0
        sidePanelHandle.isHidden = w == 0
        guard w > 0 else { onSidePanelFrame?(nil); return }
        let gap = SplitPaneLayout.Constants.gap
        let f = NSRect(x: cb.maxX - w, y: cb.minY, width: w, height: cb.height)
        if sidePanel.frame != f { sidePanel.frame = f }
        sidePanel.cornerRadius = edgeToEdge ? 0 : CraMetrics.contentCornerRadius
        sidePanel.castsShadow = !edgeToEdge
        sidePanel.layoutSubtreeIfNeeded()
        // The handle covers the gap and reaches a little into the cards on both sides.
        sidePanelHandle.frame = NSRect(x: f.minX - gap - 3, y: cb.minY, width: gap + 6, height: cb.height)
        onSidePanelFrame?(contentContainer.convert(sidePanel.convert(sidePanel.pageArea.frame, to: contentContainer), to: nil))
    }

    /// Chrome-style hosting: the status bubble moves into a click-through panel above the
    /// page windows; the find bar, which takes clicks, into its own panel just its size, which
    /// the window controller places.
    func moveOverlays(to view: NSView, findBar: NSPanel) {
        overlayParent = view
        statusHost.removeFromSuperview()
        view.addSubview(statusHost)
        findHost.removeFromSuperview()
        findHost.isHidden = false
        findHost.autoresizingMask = [.width, .height]
        findHost.frame = findBar.contentView!.bounds
        findBar.contentView!.addSubview(findHost)
        needsLayout = true
    }

    /// Animate between sidebar states by interpolating frames.
    /// While the sidebar's width follows the fingers (a Library swipe) the pages keep their size
    /// and their cards move over them: resizing a page makes Chromium lay it out again, and once
    /// per event that stalled the swipe. `thawPages` gives them the size they end up with, once.
    func freezePages() {
        for c in paneCards where c.frozenWebBounds == nil { c.frozenWebBounds = NSRect(origin: .zero, size: c.webArea.bounds.size) }
    }

    func thawPages() {
        guard paneCards.contains(where: { $0.frozenWebBounds != nil }) else { return }
        for c in paneCards { c.frozenWebBounds = nil }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    func animateSidebar(visible: Bool, floating: Bool, fullscreen: Bool, width: CGFloat, duration: TimeInterval = SidebarMotion.duration,
                        curve: (Double, Double, Double, Double) = SidebarMotion.curve, fullscreenSidebar: Bool? = nil) {
        if let shown = fullscreenSidebar { self.fullscreenSidebar = shown }
        // Maximized, the card goes edge to edge as the sidebar leaves and back into its inset as it
        // comes, in the same slide (WindowFill): its target is set before the frames are.
        if visible != edgeSidebarShown {
            edgeSidebarShown = visible
            if zoomRun == nil {
                stopEase()
                edgeProgress = edgeToEdge ? 1 : 0
            }
        }
        let target = frames(sidebarVisible: visible, floating: floating, fullscreen: fullscreen, width: width)
        // Settings ▸ Appearance ▸ Sidebar ▸ "Animate sidebar docking"'s glide: the card's frame
        // really changes on each frame, so the page resizes with it (11 Nov 2026: sized for its
        // destination up front, it jumped there while the card was still sliding).
        if duration >= Self.liveResizeFrom, let window, window.isVisible {
            startSidebarRun(target: target, visible: visible, floating: floating, fullscreen: fullscreen, duration: duration, curve: curve)
            return
        }
        stopSidebarRun()
        // Size the pages for their destination once, up front; the cards then just slide over them.
        let targetLayout = paneLayout(in: NSRect(origin: .zero, size: target.content.size))
        var webTargets: [UUID: NSRect] = [:]
        for c in paneCards where c.tabID != ShellView.noTabID {
            guard let f = targetLayout.frames[c.tabID] else { continue }
            var w = f.width
            if c.tabID == focusedPaneID, devToolsVisible, !devToolsFrontendDocked, f.width > 640 { w -= min(max(320, devToolsWidth), f.width * 0.7) }
            let toolbarH: CGFloat = barsShown(panes: paneCards.count, fullscreen: fullscreen) ? c.toolbarHeight : 0
            c.frozenWebBounds = NSRect(x: 0, y: 0, width: w, height: max(0, f.height - toolbarH))
            webTargets[c.tabID] = convert(NSRect(x: target.content.minX + f.minX, y: target.content.minY + f.minY, width: w, height: max(0, f.height - toolbarH)), to: nil)
        }
        layoutContentChildren()
        animatingFrames = true
        // Arc 1.172.1's ⌘S at 60 fps (CraCore SidebarMotion): about 43 / 72 / 89 / 97 % of the travel
        // after frames 1–4; or Settings ▸ Appearance ▸ Sidebar's smooth glide (SidebarMotion.docking).
        let c = curve
        let timing = CAMediaTimingFunction(controlPoints: Float(c.0), Float(c.1), Float(c.2), Float(c.3))
        onAnimatePaneFrames?(webTargets, duration, timing)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = timing
            ctx.allowsImplicitAnimation = true
            if !sidebarDetached { sidebarHost.animator().frame = target.sidebar }
            contentContainer.animator().frame = target.content
            loadingIndicator.animator().frame = loadingIndicatorFrame(over: target.content)
            cardCornerRadius = target.cornerRadius
            if paneCards.count == 1, let c = paneCards.first { c.cornerRadius = target.cornerRadius }
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.animatingFrames = false
            for c in self.paneCards { c.frozenWebBounds = nil }
            self.sidebarVisible = visible
            self.floatingSidebar = floating
            self.contentFullscreen = fullscreen
            self.needsLayout = true
            self.layoutSubtreeIfNeeded()
        }
    }
}

// MARK: Docking glide, frame by frame

extension ShellView {
    /// Slides at least this long resize the page on every frame (the smooth docking glide); Arc's
    /// 85 ms slide keeps the one-step resize: Chromium couldn't lay a page out every frame of it.
    static let liveResizeFrom: TimeInterval = 0.2

    struct SidebarRun {
        let start: CFTimeInterval
        let duration: TimeInterval
        let curve: (Double, Double, Double, Double)
        let fromSidebar: NSRect
        let fromContent: NSRect
        let fromRadius: CGFloat
        let target: Frames
        let visible: Bool
        let floating: Bool
        let fullscreen: Bool
    }

    fileprivate func startSidebarRun(target: Frames, visible: Bool, floating: Bool, fullscreen: Bool, duration: TimeInterval,
                                     curve: (Double, Double, Double, Double)) {
        // From wherever the last slide left things.
        sidebarRun = SidebarRun(start: CACurrentMediaTime(), duration: duration, curve: curve, fromSidebar: sidebarHost.frame,
                                fromContent: contentContainer.frame, fromRadius: cardCornerRadiusNow, target: target,
                                visible: visible, floating: floating, fullscreen: fullscreen)
        for c in paneCards { c.frozenWebBounds = nil }
        setAnimatingFrames(true)
        if sidebarLink == nil {
            let l = displayLink(target: self, selector: #selector(sidebarRunStep))
            l.add(to: .main, forMode: .common)
            sidebarLink = l
        }
        CraLog.note("sidebar glides, the page resizing with its card")
    }

    func stopSidebarRun() {
        sidebarLink?.invalidate()
        sidebarLink = nil
        sidebarRun = nil
    }

    @objc fileprivate func sidebarRunStep(_ link: CADisplayLink) {
        guard let run = sidebarRun else { stopSidebarRun(); return }
        let t = min(run.duration, max(0, link.targetTimestamp - run.start))
        let p = CGFloat(SidebarMotion.progress(at: t, curve: run.curve, duration: run.duration))
        func lerp(_ a: NSRect, _ b: NSRect) -> NSRect {
            let r = NSRect(x: a.minX + (b.minX - a.minX) * p, y: a.minY + (b.minY - a.minY) * p,
                           width: a.width + (b.width - a.width) * p, height: a.height + (b.height - a.height) * p)
            return backingAlignedRect(r, options: .alignAllEdgesNearest)
        }
        if !sidebarDetached { sidebarHost.frame = lerp(run.fromSidebar, run.target.sidebar) }
        contentContainer.frame = lerp(run.fromContent, run.target.content)
        loadingIndicator.frame = loadingIndicatorFrame(over: contentContainer.frame)
        setCardCornerRadius(run.fromRadius + (run.target.cornerRadius - run.fromRadius) * p)
        // The cards, their pages and the page windows follow the container (onPaneFrames).
        layoutContentChildren()
        guard t >= run.duration else { return }
        stopSidebarRun()
        setAnimatingFrames(false)
        sidebarVisible = run.visible
        floatingSidebar = run.floating
        contentFullscreen = run.fullscreen
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
}

/// Thin vertical strip between sidebar and content that drags the width.
final class ResizeHandleView: NSView {
    var onDrag: ((CGFloat) -> Void)?
    /// A press on the strip; `onResize` then gets the whole drag.
    var onBegin: (() -> Void)?
    /// Points from where the press began (+ wider) and the pointer's speed in points a second;
    /// called instead of `onDrag` when set (the sidebar, #287: Arc keeps the edge under the
    /// pointer, snaps at slow speeds and hides the sidebar when dragged far enough).
    var onResize: ((_ translation: CGFloat, _ speed: CGFloat) -> Void)?
    var onEnd: (() -> Void)?
    private var lastX: CGFloat = 0
    private var startX: CGFloat = 0
    private var lastTime: TimeInterval = 0
    private var speed: CGFloat = 0
    /// A press on the strip is in progress. The shell keeps the strip in place meanwhile, even
    /// when the drag hides the sidebar: a hidden view gets no more of the drag (#287).
    private(set) var dragging = false
    private var tracking: NSTrackingArea?

    /// The window is movable by its background; this strip must own its drags.
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }

    /// A page window or the floating sidebar's panel is usually not key, so track
    /// always and set the cursor ourselves.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
    override func mouseExited(with event: NSEvent) { if !dragging { NSCursor.arrow.set() } }

    override func mouseDown(with event: NSEvent) {
        lastX = event.locationInWindow.x
        startX = lastX
        lastTime = event.timestamp
        speed = 0
        dragging = true
        onBegin?()
    }
    override func mouseDragged(with event: NSEvent) {
        let x = event.locationInWindow.x
        let dt = event.timestamp - lastTime
        // Smoothed like a pan recognizer's velocity, so one quick event doesn't read as a fling.
        if dt > 0 { speed = speed * 0.5 + (x - lastX) / CGFloat(dt) * 0.5 }
        if let onResize { onResize(x - startX, speed) } else { onDrag?(x - lastX) }
        lastX = x
        lastTime = event.timestamp
        NSCursor.resizeLeftRight.set()
    }
    override func mouseUp(with event: NSEvent) {
        dragging = false
        onEnd?()
        superview?.needsLayout = true
        if !bounds.contains(convert(event.locationInWindow, from: nil)) { NSCursor.arrow.set() }
    }
}


/// Thin vertical grab area on the DevTools divider.
final class DevToolsResizeHandle: NSView {
    var onDrag: ((CGFloat) -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func mouseDragged(with event: NSEvent) { onDrag?(event.deltaX) }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(convert(point, from: superview)) ? self : nil }
}

/// The soft shade the Library's drawer casts on the page beside it (ShellView.drawerWidth).
final class DrawerShadeView: NSView {
    static let width: CGFloat = 14
    private let gradient = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.colors = [NSColor.black.withAlphaComponent(0.12).cgColor, NSColor.black.withAlphaComponent(0.04).cgColor,
                           NSColor.black.withAlphaComponent(0).cgColor]
        gradient.locations = [0, 0.35, 1]
        layer?.addSublayer(gradient)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }
}
