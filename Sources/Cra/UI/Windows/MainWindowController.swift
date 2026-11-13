import AppKit
import CraCEF
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, BrowserManagerDelegate {
    unowned let app: AppDelegate
    var store: SidebarStore { app.store }
    let sidebarUI = SidebarUIState()
    let sidebarActions = SidebarActions()
    let overlay = OverlayState()
    let commandBar: CommandBarController
    private(set) var browsers: BrowserManager!
    private(set) var shell: ShellView!
    private var commandPanel: CommandBarPanel!
    private var commandHost: CommandBarView!
    let tabSwitcher = TabSwitcher()
    private let tabSwitcherPanel = TabSwitcherPanel()
    private var spaceEditor: NSWindow?
    private var importWindow: ImportWindowController?
    private var scrollMonitor: Any?
    private var childClickMonitor: Any?
    private var middleClickMonitor: Any?
    /// A Shift-click on a page's image opens it in Cra's preview (MainWindowController+ImagePreview).
    var imageClickMonitor: Any?
    var shiftPress: (window: NSWindow?, at: NSPoint, time: TimeInterval)?
    private enum SwipeAxis { case undecided, horizontal, vertical }
    private var swipeAxis = SwipeAxis.vertical
    /// A space or Library swipe is under the fingers: begun, its release not yet seen.
    private var swipeTracking = false
    private var swipeX: CGFloat = 0
    private var swipeY: CGFloat = 0
    /// Points travelled since the space swipe locked, and recent deltas for its release speed.
    private var swipeTravel: CGFloat = 0
    private var swipeSamples: [(time: TimeInterval, dx: CGFloat)] = []
    /// The trackpad ticks of the swipe: Arc's page detent, and one on release (issue #260).
    private var swipeHaptics = PageDetentHaptics()
    /// Which space the swipe lands on, decided as the fingers move; it taps when that changes.
    private var swipeCommit = SpaceSwipeCommit()
    /// Shift + wheel over the sidebar adding up toward a space change.
    private var wheelSpaceSwitch = WheelSpaceSwitch()
    /// The Library's reveal a swipe started from: 0 on the first space, 1 in the Library; nil
    /// when the swipe can only page between spaces.
    private var librarySwipeFrom: CGFloat?
    /// Where the Library was sliding when the swipe caught it (LibrarySwipe.reveal's `toward`).
    private var librarySwipeToward: CGFloat?
    private var librarySettleSpring: (start: CFTimeInterval, from: CGFloat, velocity: CGFloat, target: CGFloat)?
    private var librarySettleLink: CADisplayLink?
    /// Shows the lists' overlay knob again once a swipe's scroller flash has faded.
    private var swipeKnobReveal: DispatchWorkItem?
    private var enteredFullscreenForContent = false
    /// The tab whose page (a video) is in element fullscreen.
    private var contentFullscreenTab: UUID?
    private var lastSidebarVisible = true
    /// The theme the background and placeholder root views were made with.
    private var shownTheme: SpaceTheme?
    private var lastSidebarWidth: CGFloat = 0
    private var commandBarOpenedAt = Date.distantPast
    /// The address field the command bar hangs under (screen rect); nil while it is centred.
    private var commandBarAnchor: NSRect?
    private var commandBarClosingClick = DismissingClick()
    private let toast = ShinyToast()
    /// Each live tab's wait for its first response (GitHub #256), the tab whose notice the toast
    /// shows (nil once another toast took its place), and the check when the next one is due.
    private var slowResponses: [UUID: SlowResponseNotice] = [:]
    private var slowResponseToastTab: UUID?
    private var slowResponseCheck: ScheduledWork?
    private var commandObserving = false
    /// Closed for good (another window stayed open): it no longer follows the store.
    private var isTornDown = false

    var currentBrowser: CraBrowser? { browsers.visibleRuntime?.browser }

    /// The window's extension side panel (chrome.sidePanel; Chrome's, which Arc lacks).
    private(set) lazy var sidePanel = ExtensionSidePanelController(app: app, shell: shell, owner: self)

    /// The side panel's page window joined this window's children: the overlay panels stay above it.
    func sidePanelPageAttached() { raiseOverlayPanels() }

    /// This window's entry in the store (WindowSession): its space, open tabs, frame.
    let windowID: UUID
    /// Pages load in the off-the-record profile; nothing is saved (WindowSession.isIncognito).
    let isIncognito: Bool
    /// Arc's Blank Window (#220): a sidebar of its own, "This Window", in the normal profile.
    var isBlank: Bool { store.isBlank(window: windowID) }
    /// Shows only a space of its own (incognito or Blank): no other spaces, no space switching.
    var isStandalone: Bool { isIncognito || isBlank }
    var focusedSpaceID: UUID { store.focusedSpaceID(window: windowID) }
    var focusedSpace: Space { store.focusedSpace(window: windowID) }
    var selectedTabID: UUID? { store.selectedTabID(window: windowID) }
    var selectedTab: SidebarItem? { store.selectedTab(window: windowID) }
    var sidebarVisible: Bool {
        get { store.window(windowID).sidebarVisible }
        set { store.updateWindow(windowID) { $0.sidebarVisible = newValue } }
    }

    init(app: AppDelegate, session: WindowSession) {
        self.app = app
        windowID = session.id
        isIncognito = session.isIncognito
        commandBar = CommandBarController(engine: app.engine, store: app.store)
        let frame = session.frame.map { NSRectFromString($0) } ?? NSRect(x: 0, y: 0, width: 1400, height: 880)
        let window = CraWindow(contentRect: frame,
                               styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                               backing: .buffered, defer: false)
        super.init(window: window)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 640, height: 420)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.title = "Pane"
        // The initializer can shift a saved global frame onto the current screen.
        // Apply it after construction so a window on another display stays there.
        // A test instance (CRA_TEST_SCREEN) keeps every window on its display.
        if TestScreen.screen != nil {
            if session.frame == nil { window.centerOnTestScreen() } else { window.setFrame(TestScreen.place(frame), display: false) }
        } else if session.frame != nil, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            window.setFrame(frame, display: false)
        } else {
            window.center()
        }
        window.delegate = self
        (window as? CraWindow)?.onEscape = { [weak self] in self?.windowEscape() }
        sidebarUI.windowID = session.id

        let store = app.store
        let palette = focusedSpace.theme.palette
        shell = ShellView(frame: window.contentView!.bounds,
                          background: SpaceBackgroundView(store: store, ui: sidebarUI),
                          sidebar: SidebarView(store: store, ui: sidebarUI, actions: sidebarActions, favicons: app.favicons),
                          toolbar: PaneToolbarView(paneTabID: nil, store: store, ui: sidebarUI, actions: sidebarActions),
                          status: StatusBubbleView(overlay: overlay),
                          // In a conversation Ask on Page's field only asks: typing doesn't find.
                          find: FindBarView(overlay: overlay, onFind: { [weak self] q, fwd in
                                                guard let self, self.askOnPage.findsWhileTyping else { return }
                                                self.find(q, forward: fwd)
                                            },
                                            onClose: { [weak self] in self?.hideFindBar() }))
        shell.sidebarWidth = CGFloat(store.prefs.sidebarWidth)
        shell.sidebarVisible = sidebarVisible
        shell.showToolbar = store.settings.showsBar(above: selectedTabID.flatMap { store.item($0)?.tab?.url })
        shell.edgeToEdgeSetting = store.settings.edgeToEdgeContent
        lastSidebarVisible = sidebarVisible
        window.trafficLightsHidden = !sidebarVisible
        lastSidebarWidth = CGFloat(store.prefs.sidebarWidth)
        window.contentView = shell
        // A window restored at its screen's size opens edge to edge.
        shell.windowMaximized = WindowFill.isMaximized(frame: window.frame, visibleFrame: window.screen?.visibleFrame ?? .zero)
        window.backgroundColor = NSColor(palette.gradientColors.first ?? .gray)

        browsers = BrowserManager(store: store, favicons: app.favicons, container: shell.parkingView, clock: app.composition.clock)
        // What extensions set for a tab (chrome.action.setIcon with tabId) went with its page.
        browsers.pageClosed = { ExtensionStore.shared.forgetActionTab($0) }
        browsers.delegate = self
        browsers.windowID = session.id
        browsers.takeRuntimeFromOtherWindow = { [weak self] id in
            guard let self else { return nil }
            for other in self.app.mainWindows where other !== self {
                if let rt = other.browsers.release(id) {
                    // The window it came from keeps the tab selected behind a blurred stand-in.
                    DispatchQueue.main.async { [weak other] in other?.refresh() }
                    return rt
                }
            }
            return nil
        }
        // AppKit asks the view under a press whether it may move the window. In the
        // sidebar's list that is SwiftUI's scroll container, which always says yes,
        // so the window's own flag is what keeps a row press for the row's drag.
        sidebarUI.onPointerOverDraggableChange = { [weak window] over in window?.isMovableByWindowBackground = !over }
        browsers.paneHost = { [weak self] id in self?.shell.card(for: id)?.webArea }
        shell.makeToolbar = { [weak self] id in
            guard let self else { return NSView() }
            return PaneToolbarView(paneTabID: id, store: self.store, ui: self.sidebarUI, actions: self.sidebarActions)
        }
        shell.onPaneResizeBegan = { [weak self] in self?.pageWindowsFollowLive = true }
        shell.onPaneResizeEnded = { [weak self] factors in
            guard let self else { return }
            self.pageWindowsFollowLive = false
            if let sel = self.selectedTabID, let split = self.store.splitContaining(sel) {
                self.store.setSplitWidthFactors(split.id, factors.mapValues { Double($0) })
            }
        }

        commandPanel = CommandBarPanel()
        commandHost = CommandBarView(controller: commandBar, favicons: app.favicons)
        commandPanel.contentView = commandHost
        commandPanel.delegate = self
        tabSwitcherPanel.contentView = TabSwitcherView(switcher: tabSwitcher, favicons: app.favicons)
        tabSwitcher.onShow = { [weak self] in self?.showTabSwitcherPanel() }
        tabSwitcher.onHide = { [weak self] in self?.hideTabSwitcherPanel() }
        tabSwitcher.onCommit = { [weak self] id in
            guard let self, id != self.selectedTabID else { return }
            let space = self.focusedSpaceID
            self.store.selectTab(id, window: self.windowID)
            // Arc rings a tab chosen from the keyboard only when it had to change space to show
            // it; within a space the selection alone marks it (issue #12).
            if self.focusedSpaceID != space { self.sidebarUI.keyboardFocusID = id }
        }
        tabSwitcher.direction = { [weak app] event in
            switch app?.bindings.action(for: event)?.id {
            case "recentTab": return 1
            case "recentTabBackward": return -1
            default: return nil
            }
        }

        wireActions()
        // Arc's drag of the sidebar's edge (#287, SidebarResize): the edge stays under the pointer,
        // a slow drag snaps to 228 pt with a haptic tick, and the sidebar hides under 82 pt and
        // comes back at 164 if the drag returns before letting go.
        shell.resizeHandle.onBegin = { [weak self] in
            guard let self else { return }
            sidebarResize = SidebarResize(startWidth: Double(shell.sidebarWidth))
            hiddenByResize = false
        }
        shell.resizeHandle.onResize = { [weak self] translation, speed in
            guard let self, var resize = sidebarResize else { return }
            let wasSnapped = resize.isSnapped
            let outcome = resize.update(translation: Double(translation), speed: Double(speed))
            sidebarResize = resize
            switch outcome {
            case .hidden where !shell.floatingSidebar:
                // Hidden this way, it keeps the width the drag started from (Arc: ⌘S brings back
                // a 200 pt sidebar dragged shut from 200).
                shell.sidebarWidth = CGFloat(resize.startWidth)
                if sidebarVisible {
                    sidebarVisible = false
                    hiddenByResize = true
                }
            case .hidden:
                shell.sidebarWidth = CGFloat(SidebarWidth.minimum)
            case .width(let w):
                shell.sidebarWidth = CGFloat(w)
                if hiddenByResize {
                    hiddenByResize = false
                    sidebarVisible = true
                }
            }
            shell.layoutSubtreeIfNeeded()
            if resize.isSnapped, !wasSnapped {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        shell.resizeHandle.onEnd = { [weak self] in
            guard let self else { return }
            sidebarResize = nil
            // The first time a drag hides the sidebar, Arc's tip says how to get it back
            // (hasHiddenSidebarWithGesture: once, never again).
            if hiddenByResize, !UserDefaults.standard.bool(forKey: Self.hiddenSidebarByDragKey) {
                UserDefaults.standard.set(true, forKey: Self.hiddenSidebarByDragKey)
                let keys = KeyBindingRegistry.shared.action("toggleSidebar")?.primary?.display ?? "⌘S"
                showToast("You can use", keyCap: (keys, "to easily show and hide your Sidebar!"))
            }
            hiddenByResize = false
            store.prefs.sidebarWidth = Double(shell.sidebarWidth)
            lastSidebarWidth = shell.sidebarWidth
        }
        // The shell's own pointer tracking: in from the edge, and out through the floating sidebar's
        // own check (the Library and the cards beside it hold it out).
        shell.onEdgeHover = { [weak self] show in
            if show { self?.setFloatingSidebar(true) } else { self?.floatingSidebar?.pointerLeft() }
        }

        installSwipeMonitor()
        installChildClickMonitor()
        installImageClickMonitor()
        installFloatingSidebar()
        observeStore()
        refresh()
        shell.onDevToolsFrame = { [weak self] rect in
            guard let self, let id = self.browsers.visibleTabID else { return }
            self.positionDevToolsWindow(rect, tab: id)
        }
        shell.onPaneFrames = { [weak self] frames in self?.positionPageWindows(frames) }
        shell.onAnimatePaneFrames = { [weak self] frames, d, timing in self?.animatePageWindows(to: frames, duration: d, timing: timing) }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshMaterialActive(); self?.sidebarUI.appActive = true }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshMaterialActive(); self?.sidebarUI.appActive = false }
        }
        shell.activeAppearance.onChange = { [weak self] in self?.refreshMaterialActive() }
        // Any window: key and main move between this window, its page windows and other windows.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didBecomeMainNotification,
                     NSWindow.didResignMainNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshMaterialActive() }
            }
        }
    }

    /// The sidebar's material follows this window's active state, as AppKit's does for Arc's sidebar
    /// (SidebarBackdrop.windowActive, GitHub #156). Going inactive waits one turn of the run loop: key
    /// moving between this window and one of its page windows resigns one before the other takes it,
    /// and the sidebar must not flash its flat fill in between.
    private func refreshMaterialActive() {
        if materialActiveNow() { shell.windowActive = true; return }
        guard shell.windowActive else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.materialActiveNow() else { return }
            self.shell.windowActive = false
        }
    }

    private func materialActiveNow() -> Bool {
        guard let window, !isTornDown else { return false }
        func holds(_ w: NSWindow?) -> Bool {
            var w = w
            while let x = w { if x === window { return true }; w = x.parent }
            return false
        }
        return SidebarBackdrop.windowActive(appActive: NSApp.isActive, miniaturized: window.isMiniaturized,
                                            holdsKeyOrMain: holds(NSApp.keyWindow) || holds(NSApp.mainWindow),
                                            activeAppearance: shell.activeAppearance.isActive ?? false)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Wiring

    private func wireActions() {
        sidebarActions.titleBarDoubleClick = { [weak self] in (self?.window as? CraWindow)?.performTitleDoubleClickAction() }
        sidebarActions.openCommandBar = { [weak self] mode in self?.openCommandBar(mode) }
        sidebarActions.closeTab = { [weak self] id in self?.closeTab(id) }
        sidebarActions.unloadTab = { [weak self] id in self?.unloadTab(id) }
        sidebarActions.moveBlankWindow = { [weak self] space in
            guard let self else { return }
            self.app.moveBlankWindow(self, toSpace: space)
        }
        sidebarActions.tearOffTab = { [weak self] id, point in
            guard let self else { return }
            self.app.tearOffTab(id, at: point, from: self)
        }
        sidebarActions.goBack = { [weak self] in self?.goBack() }
        sidebarActions.goForward = { [weak self] in self?.currentBrowser?.goForward() }
        sidebarActions.reload = { [weak self] in
            guard let b = self?.currentBrowser else { return }
            b.isLoading ? b.stopLoading() : b.reload()
        }
        sidebarActions.editSpace = { [weak self] s in self?.showSpaceEditor(space: s) }
        sidebarActions.newSpaceWith = { [weak self] ids in
            self?.showSpaceEditor(space: nil) { space in
                guard let self else { return }
                for id in ids { self.store.moveTab(id, toSpace: space, window: self.windowID) }
                self.sidebarUI.clearPicks()
            }
        }
        sidebarActions.changeSpaceIcon = { [weak self] s, anchor in self?.showSpaceIconPicker(space: s, anchor: anchor) }
        sidebarActions.editSpaceTheme = { [weak self] s, point in self?.showSpaceStyleEditor(space: s, at: point) }
        sidebarActions.editSpaceThemeBeside = { [weak self] s, card in self?.showSpaceStyleEditor(space: s, beside: card) }
        sidebarActions.newProfile = { [weak self] id in self?.showNewProfileDialog(forSpace: id) }
        sidebarActions.manageSpaces = { [weak self] in self?.showManageSpaces() }
        sidebarActions.deleteSpace = { [weak self] s in self?.app.confirmDeleteSpace(s, in: self?.window) }
        sidebarActions.toggleSidebar = { [weak self] in self?.toggleSidebar() }
        sidebarActions.toggleLibrary = { [weak self] in self?.toggleLibrary() }
        sidebarActions.showLibrary = { [weak self] page in self?.showLibrary(page) }
        sidebarActions.closeLibrary = { [weak self] in self?.leaveLibrary() }
        sidebarActions.exitPageFullscreen = { [weak self] in self?.exitContentFullscreen() }
        sidebarActions.openBookmark = { [weak self] b in self?.openBookmark(b) }
        sidebarUI.onShownSpaceChanged = { [weak self] in self?.dismissPopovers("another space shows", spaceChange: true) }
        // A bookmark dragged from the Library onto the page: a new tab, or with ⇧ this one.
        shell.pageDrop.onDrop = { [weak self] url, here in
            guard let self else { return }
            if here { self.loadInSelectedTab(url) } else { self.store.createTab(url: url, select: true, window: self.windowID) }
            CraLog.note("bookmark dropped on the page: \(here ? "this tab" : "new tab")")
        }
        bookmarkDragObservers = [BookmarkDrag.began, BookmarkDrag.ended].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.shell.pageDrop.setArmed(name == BookmarkDrag.began) }
            }
        }
        sidebarActions.editBookmark = { [weak self] b, row in
            guard let self, let window = self.window, let rowWindow = row.window else { return }
            BookmarkEditPopover.show(b, from: rowWindow.convertToScreen(row.convert(row.bounds, to: nil)), in: window, isNew: false)
        }
        sidebarActions.restoreArchived = { [weak self] id in
            guard let self else { return }
            _ = self.store.restoreArchived(id)
            self.closeLibrary()
        }
        sidebarActions.resetPinnedTab = { [weak self] id in self?.resetPinnedTab(id) }
        sidebarActions.separatePinnedTab = { [weak self] id in self?.separatePinnedTab(id) }
        sidebarActions.editPinnedURL = { [weak self] id in self?.editPinnedURL(id) }
        sidebarActions.showToast = { [weak self] text in self?.showToast(text) }
        sidebarActions.openURL = { [weak self] url in
            guard let self else { return }
            self.store.createTab(url: url, window: self.windowID)
        }
        sidebarActions.loadTyped = { [weak self] typed in
            guard let self else { return }
            let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            self.loadInSelectedTab(SuggestionEngine.looksLikeURL(t) ? SuggestionEngine.urlFromInput(t) : self.commandBar.engine.searchURL(t))
        }
        sidebarActions.openTyped = { [weak self] typed in
            guard let self else { return }
            let t = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            self.store.createTab(url: SuggestionEngine.looksLikeURL(t) ? SuggestionEngine.urlFromInput(t) : self.commandBar.engine.searchURL(t), window: self.windowID)
        }
        sidebarActions.focusPane = { [weak self] id in
            guard let self, self.selectedTabID != id else { return }
            self.store.selectTab(id, window: windowID)
        }
        sidebarActions.closePane = { [weak self] id in self?.closeSplitPane(id) }
        sidebarActions.separatePane = { [weak self] id in self?.separatePane(id) }
        sidebarActions.paneNavigate = { [weak self] id, what in
            guard let self else { return }
            if self.selectedTabID != id { self.store.selectTab(id, window: windowID) }
            guard let b = self.browsers.runtime(for: id)?.browser else { return }
            switch what {
            case "goBack": self.goBack(id)
            case "goForward": b.goForward()
            case "reload": b.isLoading ? b.stopLoading() : b.reload()
            default: break
            }
        }
        sidebarActions.editPaneURL = { [weak self] id in
            guard let self else { return }
            if self.selectedTabID != id { self.store.selectTab(id, window: windowID) }
            self.openCommandBar(.editURL)
        }
        // Toolbar buttons are ~34 pt wide and the click lands near the middle: the popup's
        // right edge lines up with the button's (Chrome anchors popups that way).
        sidebarActions.runExtension = { [weak self] id in
            guard let self else { return }
            let button = Self.extensionButtonUnderPointer()
            // A pin in the sidebar's grid (toolbar hidden) hangs its popup under its own button; one in
            // a bar above the page (the toolbar, a split pane's, the developer bar) under that bar.
            let inBar = button.map { self.isInPaneBar($0) } ?? false
            self.runExtensionAction(id, buttonRightX: button?.maxX ?? NSEvent.mouseLocation.x + 17,
                                    buttonBottomY: inBar ? self.toolbarBottomOnScreen()?.y
                                        : self.store.settings.showToolbar == false ? button?.minY : nil)
        }
        sidebarActions.showExtensionsMenu = { [weak self] in self?.showToolbarExtensionsMenu() }
        sidebarActions.showTranslate = { [weak self] id, anchor in self?.showTranslate(id, from: anchor) }
        sidebarActions.showBlockedPopups = { [weak self] id, anchor in self?.showBlockedPopups(id, from: anchor) }
        sidebarActions.paneRunExtension = { [weak self] pane, id in
            guard let self else { return }
            self.focusPaneNow(pane)
            self.sidebarActions.runExtension(id)
        }
        sidebarActions.paneExtensionsMenu = { [weak self] pane in
            self?.focusPaneNow(pane)
            self?.showToolbarExtensionsMenu()
        }
        // Popups from an extension's shortcut or chrome.action.openPopup() hang where the
        // menu bar's do: under the extension's toolbar button, else at the card's right end.
        // Arc puts every popup in one place, whatever opened it.
        ExtensionActions.shared.watchPopups { [weak app] id in
            guard let main = app?.main, let window = main.window, let key = NSApp.keyWindow, key === window || key.parent === window else { return nil }
            return main.extensionPopupAnchor(id)
        }
        // Chromium's install and removal prompts come without a parent window (#349): they hang
        // over the browser window in use, where a sheet does.
        ChromiumDialogs.start { [weak app] in app?.main?.window }
        ExtensionActions.shared.watchActions { [weak app] in
            app?.mainWindows.flatMap { $0.browsers.runtimes.values.map { (tab: $0.tabID, browser: $0.browser) } } ?? []
        }
        ExtensionActions.shared.sidePanelHandler = { [weak app] request, tab in
            guard let app else { return }
            ExtensionSidePanelController.route(request, tab: tab, app: app)
        }
        browsers.nowPlaying = sidebarUI.nowPlaying
        sidebarUI.nowPlaying.perform = { [weak self] id, action in
            guard let self else { return }
            switch action {
            case .show:
                store.selectTab(id, window: windowID)
                window?.makeKeyAndOrderFront(nil)
            case .toggleMute:
                let muted = !(store.item(id)?.tab?.muted ?? false)
                store.setMuted(id, muted)
                app.runtime(for: id)?.browser.setAudioMuted(muted)
            default:
                browsers.performNowPlaying(id, action)
            }
        }
        sidebarActions.performAction = { [weak self] id in
            if id.hasPrefix("openInSplit:"), let uuid = UUID(uuidString: String(id.dropFirst(12))) {
                self?.openTabInSplit(uuid)
            } else if id.hasPrefix("muteTab:"), let uuid = UUID(uuidString: String(id.dropFirst(8))) {
                let muted = self?.store.item(uuid)?.tab?.muted ?? false
                self?.app.runtime(for: uuid)?.browser.setAudioMuted(muted)
            } else {
                self?.app.perform(id)
            }
        }
        commandBar.onCommit = { [weak self] s, typed, mode in self?.handleCommit(s, typed: typed, mode: mode) }
        commandBar.onOpenInBackground = { [weak self] s, typed in self?.openInBackground(s, typed: typed) ?? false }
        commandBar.onOpenInSplit = { [weak self] s, typed in self?.openInSplit(s, typed: typed) ?? false }
        commandBar.onClose = { [weak self] in self?.hideCommandPanel() }
        commandBar.spaceName = { [weak self] id in self?.store.space(id)?.title ?? "" }
    }

    // MARK: Observation

    private func observeStore() {
        guard !isTornDown else { return }
        withObservationTracking {
            _ = store.revision
            _ = store.prefs
            _ = store.settings
            _ = store.spaces
            _ = SystemAppearance.shared.isDark
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observeStore()
            }
        }
    }

    func refresh() {
        guard !isTornDown, !isPutAway else { return }
        let space = focusedSpace
        let palette = space.theme.palette
        // Its extensions belong to the space's profile, and the popovers to the space they opened in.
        if siteControlCenter.isShown, siteControlCenterSpaceID != space.id { siteControlCenter.close() }
        if popoverSpaceID != space.id {
            if popoverSpaceID != nil { dismissPopovers("another space is open", spaceChange: true) }
            popoverSpaceID = space.id
        }
        // refresh runs on every store change (each page title, each window move). A new root
        // view rebuilds its whole SwiftUI tree, and a new window appearance or background redraws
        // every view, so all of these follow the theme only when it changes. What the root
        // views show beyond the palette they observe themselves.
        if shownTheme != space.theme.shown {
            shownTheme = space.theme.shown
            // A swipe in the floating sidebar changes space under it (issue #12).
            floatingSidebar?.refreshBackdrop()
            shell.placeholderHost.wantsLayer = true
            shell.placeholderHost.layer?.backgroundColor = (palette.isDark ? NSColor.white.withAlphaComponent(0.04) : NSColor.black.withAlphaComponent(0.03)).cgColor
            shell.isDarkTheme = palette.isDark
            // The space's light or dark goes to the window's content (sidebar, toolbar, pages'
            // frame), not to the window: AppKit hands a window's appearance to every menu, sheet,
            // alert and popover it presents, and those follow macOS as Arc's do, whatever the
            // space colour (#171).
            shell.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
            // The command bar is dark in a dark space (an Incognito window's too) and follows macOS
            // in a light one (CommandBarTones.appearance); its selected row and info badge take the
            // space's palette, also when the space changes under an open bar.
            commandPanel.appearance = CommandBarTones.appearance(spaceIsDark: palette.isDark)
                .flatMap { NSAppearance(named: $0 == "dark" ? .darkAqua : .aqua) }
            commandBar.theme = space.theme.shown
            // Vibrant themes see through to the desktop like Arc; others are opaque.
            shell.vibrancy.isHidden = !palette.vibrant
            shell.vibrancyLift.isHidden = !palette.vibrant
            shell.setTheme(vibrantDark: palette.isDark, vibrantLight: palette.vibrant && !palette.isDark, solid: palette.solid)
            window?.isOpaque = !palette.vibrant
            window?.backgroundColor = palette.vibrant ? .clear : NSColor(palette.gradientColors.first ?? .gray)
        }

        let ring = NSColor(space.theme.shadedDark)
        if shell.focusRingColor != ring { shell.focusRingColor = ring }
        browsers.pruneMissingTabs()
        let selected = selectedTabID
        // Split view: the selected tab's split decides which panes are on screen.
        let panes = store.visiblePaneTabIDs(in: focusedSpaceID, window: windowID)
        let split = selected.flatMap { store.splitContaining($0) }
        let factors = SplitPaneLayout.normalizedFactors(ids: panes, stored: split?.split?.widthFactors ?? [:])
        let empty = Set(panes.filter { store.item($0)?.isEmptyTab == true })
        // A lone page's bar: the toolbar, or the developer bar on a Developer Mode site (#185).
        let loneBar = store.settings.showsBar(above: panes.count == 1 ? store.item(panes[0])?.tab?.url : nil)
        if shell.showToolbar != loneBar { shell.showToolbar = loneBar }
        if shell.edgeToEdgeSetting != store.settings.edgeToEdgeContent { shell.edgeToEdgeSetting = store.settings.edgeToEdgeContent }
        // Before setPanes: a pane whose page is not live yet gets its bar colour now, not white.
        let bars = toolbarColors(panes: panes)
        if bars != shell.toolbarColors { shell.toolbarColors = bars }
        // The same for the bar itself: retarget builds it at once, before browsers.show makes the
        // pane's page visible, so a live page's colour and buttons must already be there. Without
        // them a switch between loaded tabs drew one frame with Back greyed out, on a white bar when
        // the tab had no saved colour (incognito, or any tab before 0.1.26) (#84).
        syncNavStates(panes)
        // A page in full screen (a video) leaves it before another tab takes the window: a click
        // in the floating sidebar, a link from another app, a new tab (ContentFullscreenExit).
        if ContentFullscreenExit.shouldExit(fullscreenTab: contentFullscreenTab, shownTabs: panes, commandBarOpening: false) {
            exitContentFullscreen()
        }
        shell.setPanes(panes, factors: factors, orientation: split?.split?.orientation ?? .horizontal, focused: selected, empty: empty, animated: true)
        // A page is on screen in one window at a time. Arc keeps the tab selected in every window
        // that has it open: the window in use holds the page, the others show a blurred snapshot
        // until they are used again (windowDidBecomeKey takes the page back).
        let elsewhere = Set(panes.filter(showsElsewhere))
        let live = panes.filter { !elsewhere.contains($0) }
        let liveFocus = selected.flatMap { elsewhere.contains($0) ? nil : $0 }
        for c in shell.paneCards {
            c.showsElsewhere = elsewhere.contains(c.tabID)
            c.elsewhereSnapshot = c.showsElsewhere ? app.runtime(for: c.tabID)?.snapshot : nil
        }
        sidebarUI.splitPaneIDs = panes.count > 1 ? panes : []
        if live != browsers.visibleTabIDs || liveFocus != browsers.visibleTabID
            || live.contains(where: { browsers.runtime(for: $0) == nil && store.item($0)?.isEmptyTab == false }) {
            browsers.show(live, focused: liveFocus, focus: !commandBar.isOpen)
        }
        shell.layoutContentChildren()
        syncPeeks(onScreen: panes)
        syncRingPanel()
        syncSidebarUI()
        window?.title = selectedTab?.displayTitle ?? space.title

        if sidebarVisible != lastSidebarVisible {
            lastSidebarVisible = sidebarVisible
            let motion = dockingMotion
            (window as? CraWindow)?.trafficLightsFade = motion.duration
            (window as? CraWindow)?.trafficLightsHidden = !lastSidebarVisible
            // Anchoring while the sidebar floats: bring it home first so it slides from there.
            if lastSidebarVisible { floatingSidebar?.prepareForAnchoring() }
            CraLog.note("sidebar slides \(lastSidebarVisible ? "docked" : "away") over \(motion.duration) s")
            shell.animateSidebar(visible: lastSidebarVisible, floating: false, fullscreen: shell.contentFullscreen, width: shell.sidebarWidth,
                                 duration: motion.duration, curve: motion.curve)
            // Docked: the pointer needn't be sampled; hidden: the edge is watched (FloatingSidebarPoll).
            floatingSidebar?.updatePolling()
        }
        if CGFloat(store.prefs.sidebarWidth) != lastSidebarWidth {
            lastSidebarWidth = CGFloat(store.prefs.sidebarWidth)
            shell.sidebarWidth = lastSidebarWidth
            if let page = sidebarUI.libraryPage, sidebarUI.libraryReveal == nil { shell.drawerWidth = libraryWidth(page) }
        }
    }

    /// The browser window the user is in (AppDelegate follows the key window).
    private var isActiveWindow: Bool { store.activeWindowID == windowID }

    /// `cra://debug?dragEnd`: a drag of a row of this window's list let go at a screen point
    /// with nothing taking it, as a drag out of the sidebar ends (#219).
    /// `cra://debug?pickTabs=0,1` (⌘-click picks by row), `plainClickTab=<i>`, `emptyListClick=1`,
    /// `picksState=<label>`: the focused space's tab picks without a pointer.
    func debugPicks(_ dict: [String: String]) {
        func list(in v: NSView) -> SpaceListView? {
            if let l = v as? SpaceListView, l.spaceID == focusedSpaceID { return l }
            return v.subviews.lazy.compactMap { list(in: $0) }.first
        }
        let tabs = store.listedTabIDs(in: focusedSpaceID)
        let l = window?.contentView.flatMap(list(in:))
        if let picks = dict["pickTabs"] {
            for i in picks.split(separator: ",").compactMap({ Int($0) }) where tabs.indices.contains(i) {
                sidebarUI.pick(tabs[i], range: false, in: store)
            }
        }
        if let i = dict["plainClickTab"].flatMap(Int.init), tabs.indices.contains(i), let l,
           let e = NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0) {
            l.clickTab(tabs[i], event: e)
        }
        if dict["emptyListClick"] != nil { l?.clickEmptySpace() }
        if let label = dict["picksState"] { CraLog.note("tab picks \(label): \(sidebarUI.multiSelection.count)") }
        // loadingRows=<label>: how many tab rows show the loading arc now.
        if let label = dict["loadingRows"] {
            func rows(in v: NSView) -> [TabRowView] { v.subviews.flatMap { ($0 as? TabRowView).map { [$0] } ?? rows(in: $0) } }
            let n = window?.contentView.map(rows(in:))?.filter { $0.model?.loading == true }.count ?? 0
            CraLog.note("loading rows \(label): \(n)")
        }
    }

    /// `cra://debug?faviconState=<label>`: the icon each tab of the focused space shows, as its row
    /// takes it from the favicon cache: its widest pixels, or none (the globe).
    func debugFaviconState(_ label: String) {
        let rows = store.listedTabIDs(in: focusedSpaceID).compactMap { store.item($0) }.map { item in
            let px = item.tab.flatMap { app.favicons.image(forKey: $0.iconKey) }?.representations.map(\.pixelsWide).max()
            return "\(item.displayTitle)=\(px.map { "\($0)px" } ?? "none")"
        }
        CraLog.note("favicons \(label): \(rows.joined(separator: ", "))")
    }

    func testDragEnded(_ id: UUID, at screenPoint: NSPoint) {
        func list(in v: NSView) -> SpaceListView? {
            if let l = v as? SpaceListView, l.spaceID == focusedSpaceID { return l }
            return v.subviews.lazy.compactMap { list(in: $0) }.first
        }
        guard let l = window?.contentView.flatMap(list(in:)) else { CraLog.note("dragEnd: no list"); return }
        l.dragEnded(id, at: screenPoint, operation: [])
    }

    /// `cra://debug?pickedMenu=<n>`: picks the focused space's first n listed tabs, as ⌘-click does,
    /// and logs the menu a right-click on the first one opens (#356): "|" between rows, "──" for a
    /// separator, "▸" after a submenu, " (off)" after a dimmed row. `run` picks the row (or a submenu's
    /// row) with that title (its "…" may be left off) and logs what it copied; the clipboard gets its
    /// old contents back.
    func testPickedMenu(count: Int, label: String, run: String?) {
        func rows(in v: NSView) -> [TabRowView] {
            (v as? TabRowView).map { [$0] } ?? v.subviews.flatMap { rows(in: $0) }
        }
        let listed = store.listedTabIDs(in: focusedSpaceID)
        guard listed.count >= count, let first = listed.first,
              let row = window?.contentView.flatMap(rows(in:))?.first(where: { $0.model?.id == first })
        else { CraLog.note("picked menu \(label): no row"); return }
        sidebarUI.multiSelection = Set(listed.prefix(count))
        guard let menu = row.contextMenu(at: .zero) else { CraLog.note("picked menu \(label): no menu"); return }
        CraLog.note("picked menu \(label): \(Self.menuReadout(menu))")
        let rows = menu.items + menu.items.flatMap { $0.submenu?.items ?? [] }
        guard let run, let item = rows.first(where: { $0.title == run || $0.title == run + "…" }), let owner = item.menu else { return }
        let copied = Self.probeClipboard { owner.performActionForItem(at: owner.index(of: item)) }
        CraLog.note("picked menu \(label) ran \(run): \(copied) picks=\(sidebarUI.multiSelection.count)")
    }

    /// For test hooks: a menu's rows, "|" between rows, "──" for a separator, "▸" after a submenu,
    /// " (off)" after a dimmed row.
    static func menuReadout(_ menu: NSMenu) -> String {
        menu.items.map { item -> String in
            if item.isSeparatorItem { return "──" }
            return item.title + (item.submenu != nil ? " ▸" : "") + (item.isEnabled ? "" : " (off)")
        }.joined(separator: "|")
    }

    /// `cra://debug?favoriteMenu=<n>`: logs the menu a right-click on the n-th favorite tile opens
    /// (grid order, rows as menuReadout writes them). `run` picks the row with that title and logs
    /// the tile's tab after it: muted as saved and as Chromium has the page (#387).
    func testFavoriteMenu(tile n: Int, label: String, run: String?) {
        var tiles: [FavoriteTileView] = []
        func collect(_ v: NSView) {
            if let t = v as? FavoriteTileView, !t.isHiddenOrHasHiddenAncestor { tiles.append(t) }
            v.subviews.forEach(collect)
        }
        window?.contentView.map(collect)
        tiles.sort { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        guard tiles.indices.contains(n - 1), let menu = tiles[n - 1].contextMenu() else {
            CraLog.note("favorite menu \(label): no tile \(n)"); return
        }
        CraLog.note("favorite menu \(label): \(Self.menuReadout(menu))")
        guard let run, let index = menu.items.firstIndex(where: { $0.title == run }) else { return }
        menu.performActionForItem(at: index)
        let id = tiles[n - 1].itemID
        let page = app.runtime(for: id).map { $0.browser.isAudioMuted() ? "muted" : "unmuted" } ?? "not loaded"
        CraLog.note("favorite menu \(label) ran \(run): saved=\(store.item(id)?.tab?.muted == true ? "muted" : "unmuted") page=\(page)")
    }

    /// For test hooks: runs `action` and returns what it put on the clipboard ("-" for nothing, line
    /// breaks as ⏎), then puts the clipboard's old contents back.
    static func probeClipboard(_ action: () -> Void) -> String {
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { $0[$1] = item.data(forType: $1) }
        } ?? []
        let before = pb.changeCount
        action()
        guard pb.changeCount != before else { return "-" }
        let copied = (pb.string(forType: .string) ?? "").replacingOccurrences(of: "\n", with: "⏎")
        pb.clearContents()
        pb.writeObjects(saved.map { types in
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        })
        return copied
    }

    /// `cra://debug?pickedCopy=<clicks>`: clicks rows of the focused space's list as the pointer
    /// would, "c2" ⌘-clicking the second listed tab and "s3" ⇧-clicking the third (an empty list
    /// picks nothing), then presses ⇧⌘C as a key event, so the menu's key equivalent runs as
    /// typed, and logs what reached the clipboard (#322). The clipboard gets its old contents back.
    func testPickedCopy(clicks: String, label: String) {
        let listed = store.listedTabIDs(in: focusedSpaceID)
        sidebarUI.clearPicks()
        for click in clicks.split(separator: ",") {
            guard let n = Int(click.dropFirst()), listed.indices.contains(n - 1) else { CraLog.note("picked copy \(label): no row \(click)"); return }
            sidebarUI.pick(listed[n - 1], range: click.first == "s", in: store)
        }
        guard let window else { return }
        let pb = NSPasteboard.general
        let saved = pb.pasteboardItems?.map { item in
            item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { $0[$1] = item.data(forType: $1) }
        } ?? []
        let before = pb.changeCount
        TestGesture.key("C", keyCode: 8, modifiers: [.command, .shift], in: window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            let copied = pb.changeCount != before ? pb.string(forType: .string) ?? "" : "-"
            CraLog.note("picked copy \(label): \(copied.replacingOccurrences(of: "\n", with: "⏎")) picks=\(self?.sidebarUI.multiSelection.count ?? 0)")
            guard pb.changeCount != before else { return }
            pb.clearContents()
            pb.writeObjects(saved.map { types in
                let item = NSPasteboardItem()
                for (type, data) in types { item.setData(data, forType: type) }
                return item
            })
        }
    }

    /// The tab's page belongs to another window that has it open: the window in use takes it,
    /// others keep it where it is. Windows restored at launch (none has the page yet, and
    /// `app.mainWindows` is still empty) leave it to the window in use, else the first one.
    private func showsElsewhere(_ id: UUID) -> Bool {
        if isActiveWindow || browsers.runtime(for: id) != nil { return false }
        if app.mainWindows.contains(where: { $0 !== self && $0.browsers.runtime(for: id) != nil }) { return true }
        let windows = store.prefs.windows
        let showing = windows.filter { store.visiblePaneTabIDs(in: store.focusedSpaceID(window: $0.id), window: $0.id).contains(id) }
        if showing.contains(where: { $0.id == store.activeWindowID }) { return true }
        return showing.first.map { $0.id != windowID } ?? false
    }

    /// Runs on every page event (progress, title, favicon). An @Observable property notifies
    /// on every assignment, equal or not, and every sidebar row reads some of these, so each
    /// one is assigned only when it changed.
    private func syncSidebarUI() {
        let loaded = Set(app.mainWindows.flatMap { $0.browsers.runtimes.keys })
        if loaded != sidebarUI.loadedTabIDs { sidebarUI.loadedTabIDs = loaded }
        let loading = Set(app.mainWindows.flatMap { $0.browsers.runtimes.filter { $0.value.browser.isLoading }.keys })
        if loading != sidebarUI.loadingTabIDs { sidebarUI.loadingTabIDs = loading }
        let capturing = Set(app.mainWindows.flatMap { $0.browsers.runtimes.filter { $0.value.browser.isCapturingMedia }.keys })
        if capturing != sidebarUI.capturingTabIDs { sidebarUI.capturingTabIDs = capturing }
        let audible = Set(app.mainWindows.flatMap { $0.browsers.runtimes.filter { $0.value.browser.isAudible }.keys })
        if audible != sidebarUI.audibleTabIDs { sidebarUI.audibleTabIDs = audible }
        let unloaded = Set(app.mainWindows.flatMap { $0.browsers.sleptTabs })
        if unloaded != sidebarUI.unloadedTabIDs { sidebarUI.unloadedTabIDs = unloaded }
        let onScreen = Set(app.mainWindows.flatMap { $0.browsers.visibleTabIDs })
        if onScreen != sidebarUI.onScreenTabIDs { sidebarUI.onScreenTabIDs = onScreen }
        let soundPlaying = Set(app.mainWindows.flatMap { $0.browsers.runtimes.filter { $0.value.soundPlaying }.keys })
        if soundPlaying != sidebarUI.soundPlayingTabIDs { sidebarUI.soundPlayingTabIDs = soundPlaying }
        let b = browsers.visibleRuntime?.browser
        let canGoBack = canNavigateBack(browsers.visibleTabID, b)
        if sidebarUI.canGoBack != canGoBack { sidebarUI.canGoBack = canGoBack }
        if sidebarUI.canGoForward != (b?.canGoForward ?? false) { sidebarUI.canGoForward = b?.canGoForward ?? false }
        if sidebarUI.isLoading != (b?.isLoading ?? false) { sidebarUI.isLoading = b?.isLoading ?? false }
        shell.setLoading(LoadingIndicator.Phase(isLoading: b?.isLoading ?? false, committed: b?.hasCommittedLoad ?? false),
                         tab: browsers.visibleTabID)
        let themeColor = browsers.visibleRuntime?.themeColor ?? ""
        if sidebarUI.pageThemeColor != themeColor { sidebarUI.pageThemeColor = themeColor }
        for (id, rt) in browsers.runtimes where sidebarUI.progress[id] != rt.progress { sidebarUI.progress[id] = rt.progress }
        syncNavStates(browsers.visibleTabIDs)
        syncSlowResponse()
    }

    /// The front tab still waiting for its first response after ten seconds says so in the toast,
    /// with Stop Loading (SlowResponseNotice, GitHub #256). Runs on every page event and when the
    /// front tab's notice falls due.
    private func syncSlowResponse() {
        let now = app.composition.clock.now
        var next: [UUID: SlowResponseNotice] = [:]
        for (id, rt) in browsers.runtimes {
            var n = slowResponses[id] ?? SlowResponseNotice()
            n.update(LoadingIndicator.Phase(isLoading: rt.browser.isLoading, committed: rt.browser.hasCommittedLoad),
                     navigation: rt.browser.navigationStarts, now: now)
            next[id] = n
        }
        slowResponses = next
        let id = browsers.visibleTabID
        let notice = id.flatMap { next[$0] }
        slowResponseCheck?.cancel()
        slowResponseCheck = nil
        if let due = notice?.showsAt, due > now {
            slowResponseCheck = app.composition.clock.after(due.timeIntervalSince(now)) { [weak self] in self?.syncSlowResponse() }
        }
        if let id, notice?.isShown(at: now) == true {
            if slowResponseToastTab != id { showSlowResponse(id) }
        } else if let shown = slowResponseToastTab {
            slowResponseToastTab = nil
            CraLog.note("page \(slowResponseLogHost(shown)) no longer waiting: notice gone (navigation \(browsers.runtime(for: shown)?.browser.navigationStarts ?? 0))")
            toast.dismiss()
        }
    }

    private func showSlowResponse(_ id: UUID) {
        guard let window, let browser = browsers.runtime(for: id)?.browser else { return }
        let url = browser.navigatingURL ?? store.item(id)?.tab?.url ?? ""
        let page = shell.webContainer.convert(shell.webContainer.bounds, to: nil)
        toast.show(SlowResponseNotice.message(for: url),
                   action: ShinyToast.Action(title: "Stop Loading") { [weak self] in
                       CraLog.note("page \(self?.slowResponseLogHost(id) ?? "") stopped from the notice")
                       self?.browsers.runtime(for: id)?.browser.stopLoading()
                   },
                   page: page, in: window, theme: focusedSpace.theme,
                   onClose: { [weak self] in
                       // ✕: the page goes on waiting, without the notice.
                       self?.slowResponses[id]?.close()
                       if self?.slowResponseToastTab == id { self?.slowResponseToastTab = nil }
                   })
        slowResponseToastTab = id
        CraLog.note("page \(slowResponseLogHost(id)) still waiting for a response: notice shown (navigation \(browser.navigationStarts))")
    }

    /// The host for log lines, as CraLog writes pages.
    private func slowResponseLogHost(_ id: UUID) -> String {
        guard let browser = browsers.runtime(for: id)?.browser else { return "?" }
        return browser.isIncognito ? "(incognito)" : CraLog.host(browser.navigatingURL ?? store.item(id)?.tab?.url ?? "")
    }

    /// Each pane's toolbar state, for the panes whose page is live in this window.
    private func syncNavStates(_ ids: [UUID]) {
        var nav: [UUID: TabNavState] = [:]
        for id in ids {
            guard let rt = browsers.runtime(for: id) else { continue }
            nav[id] = TabNavState(canGoBack: canNavigateBack(id, rt.browser), canGoForward: rt.browser.canGoForward, isLoading: rt.browser.isLoading,
                                  themeColor: rt.themeColor, protectedMedia: PageEngines.protectedMediaService(of: rt.browser),
                                  translation: rt.translation, blockedPopups: rt.blockedPopups.waiting.count)
        }
        if nav != sidebarUI.navStates { sidebarUI.navStates = nav }
        if let id = browsers.visibleTabID, let service = nav[id]?.protectedMedia { tellAboutProtectedMedia(service) }
    }

    // MARK: Split view

    /// Arc's "Add Split View" (⌃⇧=): a new empty pane opens after the focused
    /// one, with the command bar ready to fill it.
    func addSplitPane() {
        guard let current = selectedTabID else { openCommandBar(.newTab); return }
        if store.paneTabIDs(for: current).count >= 4 {
            showToast("Cannot Add New Pane")
            return
        }
        guard store.addEmptyPane(nextTo: current) != nil else { return }
        refresh()
        openCommandBar(.editURL)
    }

    /// Arc's "Open in Split View" on a sidebar tab: that tab joins the open one in a split, as the
    /// command bar's split row does with a tab it lists.
    func openTabInSplit(_ id: UUID) {
        guard let current = selectedTabID, current != id, store.item(current)?.isEmptyTab == false else { return }
        if store.paneTabIDs(for: current).contains(id) { store.selectTab(id, window: windowID); return }
        guard store.paneTabIDs(for: current).count < 4 else { showToast("Cannot Add New Pane"); return }
        let split = store.splitContaining(current).map { sp in store.addToSplit(sp.id, tabID: id, at: nil); return store.item(sp.id) }
            ?? store.createSplit(with: [current, id], at: current)
        store.selectTab(split.flatMap { store.paneID(for: id, in: $0) } ?? id, window: windowID)
    }

    /// Arc's "Close this Split Pane" (⌃⇧-): the pane's tab closes like any tab;
    /// the split keeps the other panes. A pinned split's pane leaves it (closing it
    /// would only unload the whole split).
    func closeSplitPane(_ id: UUID) {
        guard store.splitContaining(id) != nil else { closeTab(id); return }
        if store.item(id)?.isEmptyTab == true || store.isPinned(id) {
            store.archiveTab(id, reason: .manual)
        } else {
            closeTab(id)
        }
    }

    /// Arc's "Separate Page from Split View": the pane becomes a normal tab again.
    func separatePane(_ id: UUID) {
        guard store.splitContaining(id) != nil else { return }
        store.separateFromSplit(id)
        store.selectTab(id, window: windowID)
    }

    /// Arc's View ▸ Expand Current Split: the pane takes the window and the other panes keep the
    /// minimum width, stored as the split's width factors like a divider drag (SplitPaneLayout.expanding).
    /// Arc lays it out in one frame; a double-click on a divider or a drag brings the panes back.
    func expandSplitPane(_ id: UUID) {
        guard let split = store.splitContaining(id) else { return }
        let factors = SplitPaneLayout.expanding(id, in: store.paneTabIDs(for: id))
        store.setSplitWidthFactors(split.id, factors.mapValues { Double($0) })
    }

    func cycleSplitPane(_ delta: Int) {
        guard let current = selectedTabID else { return }
        let panes = store.paneTabIDs(for: current)
        guard panes.count > 1, let idx = panes.firstIndex(of: current) else { return }
        let n = panes.count
        store.selectTab(panes[((idx + delta) % n + n) % n])
    }

    // MARK: BrowserManagerDelegate

    func browserManagerDidUpdate(_ tabID: UUID) {
        syncSidebarUI()
        let colors = browsers.runtimes.compactMapValues { $0.backgroundColor.isEmpty ? nil : $0.backgroundColor }
        if colors != shell.pageColors { shell.pageColors = colors }
        let bars = toolbarColors(panes: shell.paneIDs)
        if bars != shell.toolbarColors { shell.toolbarColors = bars }
        if tabID == browsers.visibleTabID { window?.title = store.item(tabID)?.displayTitle ?? "Pane" }
        if overlay.findVisible, tabID == browsers.visibleTabID { syncAskOnPage() }
    }

    /// Each live page's and each pane's bar colour, by PaneToolbarView's rule (ToolbarColor):
    /// a pane shows before browsers.show creates its page, so it falls back to what the tab remembers.
    private func toolbarColors(panes: [UUID]) -> [UUID: String] {
        var bars: [UUID: String] = [:]
        for id in Set(browsers.runtimes.keys).union(panes) {
            bars[id] = ToolbarColor.hex(reported: browsers.runtime(for: id)?.themeColor, remembered: store.item(id)?.tab?.themeColor)
        }
        return bars
    }

    func browserManager(statusMessage: String, tabID: UUID?) {
        overlay.status = statusMessage
        shell.statusVisible = !statusMessage.isEmpty
        shell.layoutContentChildren()
        linkHovered(statusMessage, tabID: tabID ?? browsers.visibleRuntime?.tabID)
    }

    /// 5-Second Previews: the hovered link, with the page it is on and the profile that would load
    /// it. Incognito spaces get no previews: their pages load in no profile a fetch could use.
    private func linkHovered(_ link: String, tabID: UUID?) {
        let space = tabID.flatMap { store.spaceID(ofItem: $0) } ?? focusedSpaceID
        let rt = tabID.flatMap { browsers.runtime(for: $0) }
        let page = (rt?.browser.currentURL ?? currentBrowser?.currentURL).flatMap(URL.init(string:))
        guard store.settings.fiveSecondPreviews, LinkSummaryService.shared.isAvailable, !store.isIncognito(space: space),
              let url = URL(string: link), LinkSummaryPolicy.canPreview(link: url, page: page) else {
            LinkSummaryPreviewController.shared.linkHoverChanged(nil)
            return
        }
        let pointerInPage = { (host: NSWindow) -> CGPoint? in
            let f = host.frame, m = NSEvent.mouseLocation
            return f.contains(m) ? CGPoint(x: (m.x - f.minX) / f.width, y: (f.maxY - m.y) / f.height) : nil
        }
        let site = LinkSummaryPolicy.autoSite(page: page)
        LinkSummaryPreviewController.shared.linkHoverChanged(.init(
            link: url, page: page, window: window,
            profilePath: tabID.flatMap { store.profilePath(item: $0) } ?? store.profilePath(space: space),
            httpsOnly: store.settings.httpsOnly, theme: store.spaces[space]?.theme ?? focusedSpace.theme,
            shiftHeld: NSEvent.modifierFlags.contains(.shift),
            favicon: app.favicons.image(for: url.absoluteString)
                ?? FaviconKey.key(for: url.absoluteString).flatMap { app.favicons.image(forKey: FaviconKey.siteKey(of: $0)) },
            inspect: { [weak rt] done in
                // The link under the pointer, its frame, and whether it is one of Arc's (LinkSummaryPolicy.hoverScript).
                guard let rt, let host = rt.hostWindow, host.isVisible, let pointer = pointerInPage(host) else { done(nil); return }
                let params = (try? JSONSerialization.data(withJSONObject: [
                    "expression": LinkSummaryPolicy.hoverScript(pointer: pointer, site: site), "returnByValue": true]))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                rt.browser.evaluate(inIsolatedWorld: PageScript.world, params: params) { [weak host] result, _ in
                    let value = PeekSource.value(result)
                    DispatchQueue.main.async {
                        guard let host, let value else { done(nil); return }
                        let rect = PeekLayout.fraction(fromScript: value).flatMap { PeekLayout.source(fraction: $0, in: host.frame) }
                        done(.init(rect: rect, arcLink: value["arc"] as? Bool ?? false))
                    }
                }
            }))
    }

    func browserManager(findMatches count: Int, activeMatch: Int) {
        guard overlay.findVisible else { return }
        askOnPage.matchesUpdated(count: count)
        if count >= 0 { overlay.findCountText = lastFindText }
        if count >= 0 { overlay.findMatchCount = count }
        if activeMatch >= 0 { overlay.findActiveMatch = activeMatch }
    }

    func browserManager(download: CraDownloadInfo) {
        let name = (download.fullPath as NSString).lastPathComponent.isEmpty ? download.suggestedName : (download.fullPath as NSString).lastPathComponent
        if let tab = browsers.downloadSourceTab, let item = store.item(tab), let t = item.tab {
            TidyDownloadsService.shared.noteSource(download.identifier, title: item.displayTitle, url: t.url)
        }
        if windowDownloads.insert(download.identifier).inserted {
            ChromeDownloadAnimation.suppress()
            showDownloadInSidebar(download, name: name)
        }
        // Progress and failures show in the downloads list, as in Arc (it has no download toast).
        DownloadHistory.shared.report(id: download.identifier, name: name, path: download.fullPath, received: download.receivedBytes,
                                      total: download.totalBytes, percent: download.percent, complete: download.state == .complete,
                                      cancelled: download.state == .cancelled, failed: download.state == .interrupted,
                                      paused: download.paused)
        updateRecentDownload(download)
        if download.state == .complete, !download.fullPath.isEmpty, finishedDownloads.insert(download.identifier).inserted {
            DownloadHistory.shared.add(path: download.fullPath, profile: browsers.downloadSourceTab.map(store.profileDirectoryName(item:)) ?? profileDirectoryName)
            // The address's scheme only, never the file: scenarios wait for this line.
            CraLog.note("Download finished from a \(URL(string: download.url)?.scheme ?? "unknown"): address")
            let id = download.identifier
            TidyDownloadsService.shared.finished(id, path: download.fullPath, downloadURL: download.url, window: windowID, store: store) { [weak self] path in
                guard let self, var recent = self.sidebarUI.recentDownload, recent.id == id else { return }
                recent.path = path
                self.sidebarUI.recentDownload = recent
            }
        }
        if download.state == .inProgress, downloadWatchdog == nil {
            downloadWatchdog = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkStalledDownloads() }
            }
        }
    }

    private var downloadWatchdog: Timer?

    /// Chromium stops reporting a download once the tab that started it is gone (the
    /// download carries on, or ends, silently), which left its row "in progress" for
    /// good. A row that hasn't heard from Chromium for a while reads the file instead:
    /// gone means it ended, the full size with no .crdownload beside it means it's done.
    private func checkStalledDownloads() {
        // A paused download hears nothing from Chromium until it resumes, and isn't stalled.
        let inProgress = DownloadHistory.shared.live.filter { $0.running && windowDownloads.contains($0.id) }
        guard !inProgress.isEmpty else {
            downloadWatchdog?.invalidate()
            downloadWatchdog = nil
            return
        }
        let fm = FileManager.default
        for t in inProgress where !t.paused && !t.path.isEmpty && Date().timeIntervalSince(t.updated) > 5 {
            guard !fm.fileExists(atPath: t.path + ".crdownload") else { continue }
            let size = (try? fm.attributesOfItem(atPath: t.path))?[.size] as? Int64
            let state: CraDownloadState
            if size == nil { state = .cancelled }
            else if let size, t.total > 0, size >= t.total { state = .complete }
            else { continue }
            let info = CraDownloadInfo()
            info.identifier = t.id
            info.fullPath = t.path
            info.suggestedName = t.name
            info.totalBytes = t.total
            info.receivedBytes = size ?? 0
            info.percent = state == .complete ? 100 : t.percent
            info.state = state
            browserManager(download: info)
        }
    }

    /// Arc's download animation: the file drops onto the Library button and a download
    /// glyph is thrown at it from the pointer (DownloadFlight). Arc 1.170 kept the file 30 s;
    /// Cra puts it away after 5 s of nothing happening to it, on a spring (LibraryButtonView).
    private func showDownloadInSidebar(_ download: CraDownloadInfo, name: String) {
        let type = UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
        sidebarUI.recentDownload = RecentDownload(id: download.identifier, path: download.fullPath,
                                                  image: NSWorkspace.shared.icon(for: type))
        var flight: TimeInterval = 0
        if let window, window.isVisible, let anchor = sidebarUI.libraryAnchor, let host = anchor.window,
           host.isVisible, !anchor.isHiddenOrHasHiddenAncestor {
            // Aim at the bin's centre (screen coordinates are y-up, the offset is SwiftUI's y-down).
            let glyph = host.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let bin = NSPoint(x: glyph.midX + LibraryButtonView.binOffset.width, y: glyph.midY - LibraryButtonView.binOffset.height)
            flight = DownloadFlight.launch(over: window, from: NSEvent.mouseLocation, to: bin)
        }
        putAwayBin(download.identifier, after: flight + Self.binIdle)
    }

    /// How long the bin waits with nothing happening before it goes (10 Nov 2026: 5 s, not Arc's 30).
    static let binIdle: TimeInterval = 5

    /// The bin leaves `binIdle` after it lands, but not while a download runs (its badge is how a
    /// running download shows without hovering, #272), while the pointer is on the Library button or
    /// the downloads list, or while Tidy Downloads' card points at it. It goes `binIdle` after the
    /// last of those.
    private func putAwayBin(_ id: UInt32, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.sidebarUI.recentDownload?.id == id else { return }
            if DownloadHistory.shared.hasRunningDownloads || self.sidebarUI.libraryHovered || self.sidebarUI.downloadsListOpen
                || TidyDownloadsService.shared.card != nil {
                self.putAwayBin(id, after: Self.binIdle)
                return
            }
            if let ended = DownloadHistory.shared.lastEnded, Date().timeIntervalSince(ended) < Self.binIdle {
                self.putAwayBin(id, after: Self.binIdle - Date().timeIntervalSince(ended))
                return
            }
            CraLog.note("download bin put away")
            self.sidebarUI.recentDownload = nil
        }
    }

    private var finishedDownloads: Set<UInt32> = []
    /// Downloads this window's pages started (its flight and stall checks).
    private var windowDownloads: Set<UInt32> = []

    /// Keeps the Library button's file current: its path once known, its Quick Look
    /// thumbnail once the download is complete (Arc showed a text file's page).
    private func updateRecentDownload(_ download: CraDownloadInfo) {
        // Only the first complete update counts; Chromium sends more after it.
        guard var recent = sidebarUI.recentDownload, recent.id == download.identifier,
              !finishedDownloads.contains(download.identifier) else { return }
        if !download.fullPath.isEmpty, recent.path != download.fullPath {
            recent.path = download.fullPath
            sidebarUI.recentDownload = recent
        }
        guard download.state == .complete, !download.fullPath.isEmpty else { return }
        let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: download.fullPath), size: CGSize(width: 32, height: 32),
                                                   scale: window?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        let id = download.identifier
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] thumbnail, _ in
            let image = thumbnail?.nsImage
            DispatchQueue.main.async {
                guard let self, var recent = self.sidebarUI.recentDownload, recent.id == id else { return }
                // The first progress update can lack a filename. Use the finished file's Finder
                // icon if Quick Look has no preview, including after Tidy Downloads renamed it.
                recent.image = image ?? NSWorkspace.shared.icon(forFile: recent.path)
                self.sidebarUI.recentDownload = recent
            }
        }
    }

    /// Takes the page out of full screen and the window back to its layout at once, without waiting
    /// for the page to say so (its own report comes later and finds nothing left to do).
    private func exitContentFullscreen() {
        guard let id = contentFullscreenTab else { return }
        browsers.runtime(for: id)?.browser.exitFullscreen()
        browserManager(fullscreen: false, tabID: id)
    }

    /// A page went full screen (a video) or came back. The sidebar's own setting never changes:
    /// meanwhile it floats over the page (the window's left edge or ⌘S brings it out), and coming
    /// back the window is as it was, the sidebar docked or hidden.
    func browserManager(fullscreen: Bool, tabID: UUID) {
        guard let window else { return }
        if !fullscreen { leaveContentFullscreenSidebar() }
        shell.contentFullscreen = fullscreen
        // The sidebar's address pill offers Exit Fullscreen meanwhile (Arc).
        sidebarUI.pageFullscreen = fullscreen
        contentFullscreenTab = fullscreen ? tabID : nil
        if fullscreen, !window.styleMask.contains(.fullScreen) {
            enteredFullscreenForContent = true
            window.toggleFullScreen(nil)
        } else if !fullscreen, enteredFullscreenForContent, window.styleMask.contains(.fullScreen) {
            enteredFullscreenForContent = false
            window.toggleFullScreen(nil)
        }
    }

    /// CEF owns the DevTools window (embedding in our NSView trips a Chromium CHECK on macOS).
    /// DevTools docks inside the content card (Chrome's default), to the right of the page.
    func browserManagerDevToolsHost(for tabID: UUID) -> NSView? {
        shell.devToolsVisible = true
        shell.needsLayout = true
        shell.layoutSubtreeIfNeeded()
        return shell.devToolsHost
    }

    // MARK: Chrome-style page windows

    /// The link status bubble's panel, over the focused page's bottom left and always
    /// click-through: a click on a link under the bubble goes to the page. Anything clickable over
    /// the page gets its own panel just its size (the find bar). Only the bubble's strip, not
    /// the page: screenshot apps take the front window under the pointer, and a page-sized clear
    /// panel made every shot of the page blank white (#346).
    private var overlayPanel: NSPanel?
    private var findPanel: FindBarPanel?
    /// The text the page's find last ran on.
    private var lastFindText = ""
    /// The focused page's screen rect the find panel was last placed on.
    private var lastFindPage: NSRect?
    /// Arc Max's Ask on Page: with the setting on, the find bar's panel shows this card instead (#393).
    private(set) lazy var askOnPage: AskOnPageController = {
        let c = AskOnPageController(overlay: overlay)
        c.onFind = { [weak self] q, forward in self?.find(q, forward: forward) }
        c.onClose = { [weak self] in self?.hideFindBar() }
        c.browser = { [weak self] in self?.currentBrowser }
        c.onResize = { [weak self] in self?.refitFindPanel() }
        return c
    }()
    /// The focused pane's ring while its page is in a window of its own (DevTools docked in it):
    /// that window covers the card, and the card's ring with it (GitHub #178).
    private var ringPanel: NSPanel?
    /// Page area per visible tab, window coordinates (one entry per pane).
    private var lastPaneFrames: [UUID: NSRect] = [:]
    /// While a divider is dragged the page windows follow every mouse move.
    private var pageWindowsFollowLive = false

    private func ensureOverlayPanel() {
        guard overlayPanel == nil, let window else { return }
        func clearPanel() -> NSPanel {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.isMovable = false
            panel.hidesOnDeactivate = false
            panel.contentView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
            return panel
        }
        let panel = clearPanel()
        panel.ignoresMouseEvents = true
        let find = FindBarPanel()
        shell.moveOverlays(to: panel.contentView!, findBar: find)
        let ask = askOnPage.view
        ask.frame = find.contentView!.bounds
        ask.autoresizingMask = [.width, .height]
        ask.isHidden = true
        find.contentView!.addSubview(ask)
        window.addChildWindow(panel, ordered: .above)
        overlayPanel = panel
        findPanel = find
        if overlay.findVisible { window.addChildWindow(find, ordered: .above) }
    }

    /// Shows the focused card's ring above its page window while that page is not in the card.
    private func syncRingPanel() {
        guard let window else { return }
        let card = shell.focusedCard
        let tab = browsers.visibleTabID
        let host = tab.flatMap { browsers.runtime(for: $0)?.hostWindow }
        let pageInOwnWindow = host.map { $0.isVisible && !EmbeddedPages.isHost($0) } ?? false
        let devTools = tab.flatMap { browsers.visibleDevToolsWindows[$0] }?.isVisible ?? false
        guard let card, let color = card.focusRing, card.window === window, pageInOwnWindow || devTools else {
            if let panel = ringPanel, panel.parent != nil { window.removeChildWindow(panel); panel.orderOut(nil) }
            return
        }
        let panel = ringPanel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.hidesOnDeactivate = false
            p.contentView = FocusRingView(frame: .zero)
            ringPanel = p
            return p
        }()
        let frame = window.convertToScreen(card.convert(card.bounds, to: nil))
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if let ring = panel.contentView {
            ring.layer?.borderColor = color.cgColor
            ring.layer?.cornerRadius = card.cornerRadius
        }
        if panel.parent == nil {
            window.addChildWindow(panel, ordered: .above)
            raiseOverlayPanels()
        }
    }

    /// A Peek's windows went on the window above its other children (opened, or back with its tab):
    /// the floating sidebar goes back in front of them (#295).
    func peekWindowsAttached() {
        guard let window else { return }
        for panel in floatingSidebar?.attachedPanels ?? [] {
            window.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
        }
    }

    /// Overlay panel above the page windows (and the floating sidebar), the find bar above it.
    private func raiseOverlayPanels() {
        guard let window else { return }
        var panels: [NSPanel?] = [overlayPanel]
        if let ringPanel, ringPanel.parent != nil { panels.insert(ringPanel, at: 0) }
        if overlay.findVisible { panels.append(findPanel) }
        // A Peek (and its dimming) stays above everything else in the window but the hidden sidebar
        // slid out at the edge: that one is the sidebar, whose rows stay in reach of a Peek (#242, #295).
        var wanted = panels.compactMap { $0 } + peeks.flatMap(\.peekWindows) + (floatingSidebar?.attachedPanels ?? [])
        // Permission cards over their page's top left corner (#371).
        wanted += PermissionPopover.panels(over: window)
        // The address field's dropdown over the floating sidebar's field: above the sidebar, or the
        // sidebar covered its left part and cut off what was typed (11 Nov 2026); and the command bar ⌘T
        // opened from a Peek stays above the Peek (#379).
        if commandPanel.parent === window, commandPanel.isVisible || commandBar.isOpen { wanted.append(commandPanel) }
        // Chromium's install and removal prompts (#349) hang over everything, as a sheet does.
        wanted += ChromiumDialogs.dialogs(over: window)
        // Already the last children, in order, and showing: re-adding each one rebuilt the
        // window's ordering group, a window server round trip, on every tab switch.
        let children = window.childWindows ?? []
        if children.suffix(wanted.count).elementsEqual(wanted, by: ===), wanted.allSatisfy(\.isVisible) { return }
        for panel in wanted {
            window.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
            panel.orderFront(nil)
        }
    }

    /// The status bubble's screen frame: its strip at the focused page's bottom left.
    private func overlayPanelFrame(page: NSRect) -> NSRect {
        StatusBubbleStrip.frame(inPage: page)
    }

    /// The find bar's screen frame: the top trailing corner of the focused page.
    private func findPanelFrame(page: NSRect) -> NSRect {
        lastFindPage = page
        let size = askOnPage.state.enabled ? askOnPage.size : CraMetrics.findBarSize, inset = CraMetrics.findBarInset
        var page = page
        if let window, page.maxX > window.frame.maxX { page.size.width = max(0, window.frame.maxX - page.minX) }
        return NSRect(x: page.maxX - size.width - inset, y: page.maxY - size.height - inset, width: size.width, height: size.height)
    }

    /// Attaches the visible tabs' Chrome windows over their pane areas, hides the others.
    func browserManagerPageWindowsChanged(focus: Bool) {
        guard let window else { return }
        // A focus still waiting for its page to embed is stale once pages change without one.
        if !focus { embedFocusTab = nil }
        ensureOverlayPanel()
        let visibleIDs = Set(browsers.visibleTabIDs)
        let focused = browsers.visibleRuntime?.hostWindow
        for (id, rt) in browsers.runtimes {
            guard let w = rt.hostWindow else {
                if visibleIDs.contains(id) { updatePageTopGrabber(id, from: nil) }
                continue
            }
            // Chromium never learns that an ordered-out window is hidden (it checks for a hidden
            // NSView ancestor), so hidden tabs stayed "visible": background tabs autoplayed video
            // and ran at full speed. A hidden content view makes the tab hidden like Chrome's
            // background tabs: media waits until the tab is first shown.
            if !visibleIDs.contains(id) {
                w.contentView?.isHidden = true
                // An embedded page leaves the window with its card, so Chromium sees it hidden.
                if EmbeddedPages.isHost(w), let views = EmbeddedPages.pageViews(of: w) {
                    for v in views where v.superview !== w.contentView { v.removeFromSuperview() }
                }
                if w.isVisible {
                    w.orderOut(nil)
                    // A new background page starts in CEF's 10 pt window. Let it lay out at
                    // the pane size before autofocus can scroll its player off the top.
                    let pane = shell.webContainer
                    if w.parent == nil, !pane.bounds.isEmpty {
                        w.setFrame(window.convertToScreen(pane.convert(pane.bounds, to: nil)), display: false)
                    }
                }
                continue
            }
            // Shown while drawing for releaseHiddenFrames: a child below this window until now,
            // so it is attached above like any page window, opaque and clickable again.
            if releasingFrames.remove(id) != nil {
                Self.applyFrameRelease(HiddenFrameRelease.doneSteps(shown: true), to: w)
            }
            if w.parent !== window {
                // Borderless: a titled window gets macOS's rounded corners on all four sides,
                // which shows under the toolbar and where the page meets DevTools.
                w.styleMask.remove([.titled, .resizable])
                w.styleMask.insert(.fullSizeContentView)
                ChromiumWindowCorners.setSquare(true, for: w)
                ChromiumChildHover.setDocked(true, for: w)
                ChromiumChildFullscreen.attach(w)
                w.titlebarAppearsTransparent = true
                w.titleVisibility = .hidden
                w.isMovable = false
                w.hasShadow = false
                w.isOpaque = false
                w.backgroundColor = .clear
                if let cv = w.contentView {
                    cv.wantsLayer = true
                    cv.layer?.cornerRadius = CraMetrics.contentCornerRadius
                    cv.layer?.cornerCurve = .continuous
                    cv.layer?.maskedCorners = cv.isFlipped ? [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
                    cv.layer?.masksToBounds = true
                }
                window.addChildWindow(w, ordered: .above)
            }
            // Hidden pages are not kept in step with the panes, so size this one before it shows.
            positionPageWindows(lastPaneFrames)
            w.contentView?.isHidden = false
            embedPage(id, from: w)
            updatePageTopGrabber(id, from: w)
            // Ordering a window that is already showing is a window server round trip too.
            if !w.isVisible { w.orderFront(nil) }
            if focus, w === focused, EmbeddedPages.isEnabled, browsers.visibleDevToolsWindow == nil {
                // Focus goes to the page inside this window; one not embedded yet takes it when it is.
                embedFocusTab = id
                focusEmbeddedPage(id)
            } else if focus, w === focused {
                w.makeKey()
                devToolsLog("page win \(w.windowNumber) makeKey -> isKey=\(w.isKeyWindow) canBecomeKey=\(w.canBecomeKey) style \(w.styleMask.rawValue)")
            }
        }
        releaseUnfocusedEmbeddedPage()
        syncRingPanel()
        if browsers.visibleDevToolsWindows.values.contains(where: { $0.parent === window }) {
            raisePageWindows()
        } else {
            raiseOverlayPanels()
        }
    }

    private func updatePageTopGrabber(_ id: UUID, from host: NSWindow?) {
        guard let window, let card = shell.card(for: id) else { return }
        let grabber = card.pageTopGrabber
        guard let page = EmbeddedPages.webContentsView(in: card.webArea)
            ?? host?.contentView.flatMap(EmbeddedPages.webContentsView(in:)) else {
            grabber.removeFromSuperview()
            return
        }
        grabber.isEnabled = { [weak self] in
            guard let self else { return false }
            return !self.isTornDown && self.store.settings.pageTopWindowDrag && !self.shell.contentFullscreen
        }
        // Arc's band reaches 60 pt from the card's top with its bar (#363): 28 pt under the toolbar.
        grabber.barHeight = { [weak card] in
            guard let card, card.showToolbar else { return 0 }
            return card.toolbarHeight
        }
        grabber.attach(to: page, owner: window)
    }

    /// Page windows drawing once, hidden, so their last frame lets go of an evicted page (#195).
    private var releasingFrames: Set<UUID> = []

    /// A hidden tab's page window is ordered out with its compositor suspended, and its last frame
    /// kept the page's surface, and the page's tiles in the GPU process (~15 MB a tab), alive after
    /// Chromium evicted it: every tab ever shown kept them. Chrome detaches a background tab from its
    /// one window instead. Ordered in for a moment, transparent and below this window, the page
    /// window draws a frame without the page and Chromium frees it (HiddenFrameRelease). It goes in
    /// as a child below this window, transparent the whole time, so nothing of it shows, over a
    /// full-screen window or in Stage Manager either (#261).
    func releaseHiddenFrames(now: Date) {
        let visible = Set(browsers.visibleTabIDs)
        let hidden = browsers.runtimes.values.compactMap { rt -> HiddenFrameRelease.Tab? in
            guard let at = rt.hiddenAt, rt.hostWindow != nil, !visible.contains(rt.tabID) else { return nil }
            return .init(id: rt.tabID, hiddenAt: at, releasedFor: rt.hiddenFrameReleasedFor)
        }
        guard let window else { return }
        for id in HiddenFrameRelease.due(hidden, visible: visible.count, now: now) {
            guard let rt = browsers.runtime(for: id), let w = rt.hostWindow, !w.isVisible, w.parent == nil,
                  !releasingFrames.contains(id) else { continue }
            rt.hiddenFrameReleasedFor = rt.hiddenAt
            releasingFrames.insert(id)
            Self.applyFrameRelease(HiddenFrameRelease.drawSteps, to: w, below: window)
            // Two or three frames: the compositor unsuspends, paints and commits.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak w] in
                guard let w else { return }
                // Taken by browserManagerPageWindowsChanged when the tab was shown meanwhile. With
                // this controller gone the window still goes: left in, it stayed for good (#261).
                if let self, self.releasingFrames.remove(id) == nil { return }
                Self.applyFrameRelease(HiddenFrameRelease.doneSteps(shown: false), to: w)
            }
        }
    }

    /// Does HiddenFrameRelease's steps to a page window; `window` is the one it goes below.
    private static func applyFrameRelease(_ steps: [HiddenFrameRelease.WindowStep], to w: NSWindow, below window: NSWindow? = nil) {
        for step in steps {
            switch step {
            case .transparent: w.alphaValue = 0
            case .opaque: w.alphaValue = 1
            case .clickThrough(let on): w.ignoresMouseEvents = on
            case .attachBelow: window?.addChildWindow(w, ordered: .below)
            case .detach: w.parent?.removeChildWindow(w)
            case .orderOut: w.orderOut(nil)
            }
        }
    }

    /// Moves the page's view from its Chrome window into its card (EmbeddedPages). With its
    /// DevTools open the page goes back: Chrome's docked frontend lays it out in its window.
    private func embedPage(_ id: UUID, from w: NSWindow) {
        guard EmbeddedPages.isEnabled else { return }
        guard let views = EmbeddedPages.pageViews(of: w) else { return }
        let target: NSView
        if browsers.devToolsViews[id]?.window != nil, let cv = w.contentView {
            EmbeddedPages.unmarkHost(w)
            target = cv
        } else if let card = shell.paneCards.first(where: { $0.tabID == id }) {
            EmbeddedPages.markHost(w)
            target = card.webArea
        } else {
            return
        }
        // Compositor first, the page's input view above it.
        if views.contains(where: { $0.superview !== target }) {
            for v in views { target.addSubview(v) }
        }
        let bounds = shell.paneCards.first { $0.webArea === target }?.frozenWebBounds ?? target.bounds
        EmbeddedPages.place(views, in: bounds)
        if embedFocusTab == id { focusEmbeddedPage(id) }
    }

    /// `cra://debug?pageInsets=1`: where the focused page's input view sits against the compositor
    /// that draws the page, after its card lays out again, and the insets Chromium gave it. While
    /// the debugger bar shows, both say the bar's height at the top (#241).
    func pageInsetsReadout() -> String {
        guard let host = browsers.visibleRuntime?.hostWindow, let views = EmbeddedPages.pageViews(of: host),
              let compositor = views.first, let page = views.last, let area = page.superview else { return "page view insets: no page" }
        pageInsetsReadouts += 1
        if let card = shell.paneCards.first(where: { $0.webArea === area }) {
            card.needsLayout = true
            card.layoutSubtreeIfNeeded()
        }
        let c = compositor.frame, p = page.frame
        let top = area.isFlipped ? p.minY - c.minY : c.maxY - p.maxY
        let bottom = area.isFlipped ? c.maxY - p.maxY : p.minY - c.minY
        let chromium = EmbeddedPages.chromiumInsets(of: page).map { "top=\(Int($0.top)) left=\(Int($0.left)) bottom=\(Int($0.bottom)) right=\(Int($0.right))" } ?? "none"
        // The compositor's area from the window's top left, where clickAt points go.
        let inWindow = area.convert(c, to: nil)
        let origin = "\(Int(inWindow.minX)),\(Int((window?.frame.height ?? 0) - inWindow.maxY))"
        return "page view insets \(pageInsetsReadouts): top=\(Int(top)) left=\(Int(p.minX - c.minX)) bottom=\(Int(bottom)) right=\(Int(c.maxX - p.maxX)); Chromium's \(chromium); page area at \(origin) \(Int(c.width))x\(Int(c.height))"
    }

    private var pageInsetsReadouts = 0

    /// `cra://debug?screenshotPick=x,y`: the window a screenshot app's "window under the pointer"
    /// takes at that point of this window (from its top left), read from the window list it reads.
    /// Over a page that is this window, whose card draws the page (#346). Only Cra's windows
    /// count: a test copy runs behind other apps.
    func screenshotPickReadout(at p: CGPoint) -> String {
        guard let window else { return "screenshot pick: no window" }
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let mine = list.compactMap { d -> ScreenshotPick.Window? in
            guard (d[kCGWindowOwnerPID as String] as? Int) == pid, let number = d[kCGWindowNumber as String] as? Int,
                  let bounds = d[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return .init(number: number, frame: frame, layer: d[kCGWindowLayer as String] as? Int ?? 0,
                         alpha: d[kCGWindowAlpha as String] as? Double ?? 1,
                         shared: (d[kCGWindowSharingState as String] as? Int ?? 1) != 0)
        }
        guard let me = mine.first(where: { $0.number == window.windowNumber }) else { return "screenshot pick: window not listed" }
        let pick = ScreenshotPick.window(at: CGPoint(x: me.frame.minX + p.x, y: me.frame.minY + p.y), in: mine)
        let name = pick.map { $0.number == window.windowNumber ? "main window" : "window \($0.number) \(Int($0.frame.width))x\(Int($0.frame.height))" } ?? "none"
        return "screenshot pick at \(Int(p.x)),\(Int(p.y)): \(name)"
    }

    /// `cra://debug?embedDump=1`: where every page view is, for EmbeddedPages work.
    func embeddedPagesDump() -> String {
        func tree(_ v: NSView, _ depth: Int) -> String {
            var s = String(repeating: "  ", count: depth) + "\(type(of: v)) \(v.frame) hidden=\(v.isHidden) layer=\(v.layer.map { "\(type(of: $0)) \($0.bounds) hidden=\($0.isHidden) sub=\($0.sublayers?.count ?? 0)" } ?? "nil")\n"
            if depth < 4 { for sub in v.subviews { s += tree(sub, depth + 1) } }
            return s
        }
        var out = "embedded pages (enabled=\(EmbeddedPages.isEnabled)) key=\(window?.isKeyWindow ?? false) fr=\(String(describing: window?.firstResponder))\n"
        for c in shell.paneCards { out += "card \(c.tabID.uuidString.prefix(8)) \(c.frame)\n" + tree(c.webArea, 1) }
        for (id, rt) in browsers.runtimes {
            guard let w = rt.hostWindow else { continue }
            out += "host \(id.uuidString.prefix(8)) win \(w.windowNumber) alpha=\(w.alphaValue) visible=\(w.isVisible) host=\(EmbeddedPages.isHost(w)) frame \(w.frame)\n"
            if let cv = w.contentView { out += tree(cv, 1) }
        }
        return out
    }

    /// An embedded page stays this window's first responder after its pane loses focus (an empty
    /// split pane opened beside it). When the window became key again (the command bar closing)
    /// the page reported focus, which selects its pane, and the URL meant for the empty pane
    /// opened as a new tab. A page window never had that: it was a window of its own.
    private func releaseUnfocusedEmbeddedPage() {
        guard EmbeddedPages.isEnabled, let window, let responder = window.firstResponder as? NSView,
              NSStringFromClass(type(of: responder)) == "RenderWidgetHostViewCocoa" else { return }
        let focused = browsers.visibleTabID.flatMap { browsers.runtime(for: $0)?.hostWindow }.flatMap(EmbeddedPages.pageViews(of:)) ?? []
        // The extension side panel's page keeps the keys it has.
        let panel = sidePanel.isShowing ? sidePanel.embeddedViews : []
        if !(focused + panel).contains(where: { responder.isDescendant(of: $0) }) { window.makeFirstResponder(nil) }
    }

    /// The tab whose embedded page should take keyboard focus once it is in its card.
    private var embedFocusTab: UUID?

    private func focusEmbeddedPage(_ id: UUID) {
        guard let window, let host = browsers.runtime(for: id)?.hostWindow,
              let view = EmbeddedPages.pageViews(of: host)?.last, view.window === window else { return }
        embedFocusTab = nil
        // Never from a panel that has the keys (the command bar filling a split pane, the find bar).
        if let key = NSApp.keyWindow, key !== window, !EmbeddedPages.isHost(key), key.parent === window { return }
        window.makeKey()
        if let render = EmbeddedPages.renderView(in: view) { window.makeFirstResponder(render) }
    }

    /// Diagnostic log shared with the bridge: `defaults write uz.pane.browser devToolsLog -bool YES`.
    private static let devToolsLogEnabled = UserDefaults.standard.bool(forKey: "devToolsLog")
    private func devToolsLog(_ message: @autoclosure () -> String) {
        guard Self.devToolsLogEnabled else { return }
        let path = NSTemporaryDirectory() + "cra-devtools.log"
        let line = String(format: "%.3f shell: %@\n", Date().timeIntervalSince1970, message())
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
        else { try? line.write(toFile: path, atomically: true, encoding: .utf8) }
    }

    /// Every visible page window follows its pane. Hidden tabs are left where they are and
    /// sized when they show (browserManagerPageWindowsChanged): each resize makes Chromium lay
    /// the page out synchronously, ~5 ms a window, which once ran for every loaded tab on
    /// every sidebar toggle and every step of a window resize.
    private func positionPageWindows(_ frames: [UUID: NSRect]) {
        guard let window, !frames.isEmpty else { return }
        lastPaneFrames = frames
        let focusRect = (browsers.visibleTabID.flatMap { frames[$0] }) ?? frames.values.first!
        let focusPage = browsers.visibleTabID.map { pageRect(forBody: focusRect, tab: $0) } ?? focusRect
        let devTools = browsers.visibleDevToolsWindows
        let live = pageWindowsFollowLive || shell.devToolsFrontendDocked || !devTools.isEmpty
        for id in browsers.visibleTabIDs {
            guard let w = browsers.runtime(for: id)?.hostWindow else {
                updatePageTopGrabber(id, from: nil)
                continue
            }
            let body = frames[id] ?? focusRect
            let page = pageRect(forBody: body, tab: id)
            let target = window.convertToScreen(page)
            // Chrome's docked frontend spans its pane's body, under the page.
            if devTools[id] != nil, browsers.devToolsDockedState[id] ?? true { positionDevToolsWindow(body, tab: id) }
            if w.frame != target { w.setFrame(target, display: live) }
            updatePageCorners(w, page: page, body: body)
            // A switch can show the page before its card exists; the card is laid out by now.
            embedPage(id, from: w)
            updatePageTopGrabber(id, from: w)
            if shell.devToolsFrontendDocked, w.isVisible {
                devToolsLog("page win \(w.windowNumber) '\(w.title)' tab \(id.uuidString.prefix(8)) visible=\(browsers.visibleTabIDs.contains(id)) body \(body) page \(page) style \(w.styleMask.rawValue) parent \(w.parent?.windowNumber ?? -1)")
            }
        }
        let pr: NSRect? = shell.devToolsFrontendDocked ? focusPage : nil
        if shell.frontendPageRect != pr { shell.frontendPageRect = pr }
        let focusOnScreen = window.convertToScreen(focusPage)
        if let panel = overlayPanel, panel.frame != overlayPanelFrame(page: focusOnScreen) { panel.setFrame(overlayPanelFrame(page: focusOnScreen), display: true) }
        syncRingPanel()
        if let find = findPanel, find.frame != findPanelFrame(page: focusOnScreen) { find.setFrame(findPanelFrame(page: focusOnScreen), display: true) }
    }

    /// Pages follow their cards without Chromium laying them out on every frame (an animated
    /// window frame resized the page at each step, a synchronous layout each time, and the
    /// page trailed its card). Each page takes its final frame at once; one that grows is
    /// revealed from its old edges by a mask animated in step with the card. One that shrinks
    /// needs nothing: its card, painted in the page's colour, slides under the gap.
    private func animatePageWindows(to frames: [UUID: NSRect], duration: TimeInterval, timing: CAMediaTimingFunction) {
        guard let window, !frames.isEmpty else { return }
        lastPaneFrames = frames
        let focusRect = (browsers.visibleTabID.flatMap { frames[$0] }) ?? frames.values.first!
        let focusPage = browsers.visibleTabID.map { pageRect(forBody: focusRect, tab: $0) } ?? focusRect
        for id in browsers.visibleTabIDs {
            guard let w = browsers.runtime(for: id)?.hostWindow, let body = frames[id] else { continue }
            let page = pageRect(forBody: body, tab: id)
            let target = window.convertToScreen(page)
            let from = w.frame
            CATransaction.begin()
            if from != target {
                w.setFrame(target, display: true)
                fillContentView(w)
            }
            updatePageCorners(w, page: page, body: body)
            if w.isVisible, !EmbeddedPages.isHost(w), let cv = w.contentView {
                revealPage(cv, from: from, to: target, duration: duration, timing: timing)
            }
            CATransaction.commit()
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = timing
            for (id, dev) in browsers.visibleDevToolsWindows where dev.parent === window {
                guard browsers.runtime(for: id)?.hostWindow != nil, let body = frames[id] else { continue }
                dev.animator().setFrame(window.convertToScreen(body), display: true)
            }
            overlayPanel?.animator().setFrame(overlayPanelFrame(page: window.convertToScreen(focusPage)), display: true)
            findPanel?.animator().setFrame(findPanelFrame(page: window.convertToScreen(focusPage)), display: true)
        }
    }

    /// Masks a page that just grew from `from` to `to` (screen rects) down to the part it
    /// covered before, then opens the mask to the full page over the card's animation.
    private func revealPage(_ view: NSView, from: NSRect, to: NSRect, duration: TimeInterval, timing: CAMediaTimingFunction) {
        guard duration > 0, let layer = view.layer else { return }
        let shown = from.intersection(to)
        guard !shown.isEmpty, shown.width < to.width - 0.5 || shown.height < to.height - 0.5 else { return }
        let start = NSRect(x: shown.minX - to.minX, y: view.isFlipped ? to.maxY - shown.maxY : shown.minY - to.minY,
                           width: shown.width, height: shown.height)
        let end = view.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let mask = CALayer()
        mask.backgroundColor = NSColor.black.cgColor
        // The moving edge is the card's edge, rounded like it.
        mask.cornerRadius = layer.cornerRadius
        mask.cornerCurve = .continuous
        mask.maskedCorners = layer.maskedCorners
        mask.frame = end
        layer.mask = mask
        CATransaction.setCompletionBlock { [weak layer, weak mask] in
            if let layer, let mask, layer.mask === mask { layer.mask = nil }
        }
        let bounds = CABasicAnimation(keyPath: "bounds")
        bounds.fromValue = NSValue(rect: NSRect(origin: .zero, size: start.size))
        bounds.toValue = NSValue(rect: NSRect(origin: .zero, size: end.size))
        let position = CABasicAnimation(keyPath: "position")
        position.fromValue = NSValue(point: NSPoint(x: start.midX, y: start.midY))
        position.toValue = NSValue(point: NSPoint(x: end.midX, y: end.midY))
        let group = CAAnimationGroup()
        group.animations = [bounds, position]
        group.duration = duration
        group.timingFunction = timing
        mask.add(group, forKey: "reveal")
        CATransaction.commit()
    }

    /// Where a page goes inside its pane body: the whole body, or, with Chrome's docked
    /// frontend, the placeholder the frontend reported. The placeholder keeps its offsets
    /// from the body's edges while the body is still resizing, so the page follows at
    /// once instead of waiting for the frontend's next layout.
    private func pageRect(forBody body: NSRect, tab: UUID) -> NSRect {
        guard browsers.devToolsViews[tab] != nil, browsers.runtime(for: tab)?.hostWindow != nil,
              browsers.devToolsDockedState[tab] ?? true,
              let p = browsers.devToolsPlaceholders[tab] else { return body }
        return p.pageRect(in: body)
    }

    /// Only the page corners that are card corners get rounded (a page docked beside
    /// DevTools meets it with a straight edge, like Arc).
    private func updatePageCorners(_ w: NSWindow, page: NSRect, body: NSRect) {
        guard let cv = w.contentView, let layer = cv.layer else { return }
        fillContentView(w)
        // Chromium can restore its own style mask (fullscreen, display changes), which brings
        // back macOS's rounded window corners on all four sides: square the window again.
        if w.styleMask.contains(.titled) || w.styleMask.contains(.resizable) {
            w.styleMask.remove([.titled, .resizable])
            ChromiumWindowCorners.setSquare(true, for: w)
        }
        // Chromium's content view is flipped, so its layer's MinY edge is the top.
        let bottomLeft: CACornerMask = cv.isFlipped ? .layerMinXMaxYCorner : .layerMinXMinYCorner
        let bottomRight: CACornerMask = cv.isFlipped ? .layerMaxXMaxYCorner : .layerMaxXMinYCorner
        let topLeft: CACornerMask = cv.isFlipped ? .layerMinXMinYCorner : .layerMinXMaxYCorner
        let topRight: CACornerMask = cv.isFlipped ? .layerMaxXMinYCorner : .layerMaxXMaxYCorner
        // The whole mask, not only the corner set: a rebuilt layer would otherwise keep
        // whatever radius and clipping it came with.
        if layer.cornerCurve != .continuous { layer.cornerCurve = .continuous }
        if !layer.masksToBounds { layer.masksToBounds = true }
        // Edge to edge the card is square, but a page window is not clipped by the main
        // window: where it meets the window's corners it takes their radius. On the way there
        // (a zoom, full screen) it keeps the card's shrinking radius.
        if shell.edgeFlush {
            roundAtWindowCorners(layer, rect: page, flipped: cv.isFlipped)
            return
        }
        let radius = shell.pageFillsScreen ? 0 : shell.contentFullscreen ? CraMetrics.contentCornerRadius : shell.cardRadiusNow
        if layer.cornerRadius != radius { layer.cornerRadius = radius }
        var corners: CACornerMask = []
        // A fullscreen card is square.
        if !shell.pageFillsScreen, abs(page.minY - body.minY) < 0.5 {
            if abs(page.minX - body.minX) < 0.5 { corners.insert(bottomLeft) }
            if abs(page.maxX - body.maxX) < 0.5 { corners.insert(bottomRight) }
        }
        // Without the toolbar the page's top edge is the card's top edge too.
        if !shell.pageFillsScreen, !shell.panesShowBars, abs(page.maxY - body.maxY) < 0.5 {
            if abs(page.minX - body.minX) < 0.5 { corners.insert(topLeft) }
            if abs(page.maxX - body.maxX) < 0.5 { corners.insert(topRight) }
        }
        if layer.maskedCorners != corners { layer.maskedCorners = corners }
    }

    /// Edge to edge: a child window (page or DevTools) is not clipped by the main window, so
    /// the corners of `rect` (window coordinates) that sit on the window's corners take its radius.
    private func roundAtWindowCorners(_ layer: CALayer, rect: NSRect, flipped: Bool) {
        guard let window else { return }
        let radius = window.styleMask.contains(.fullScreen) || shell.contentFullscreen ? 0 : LittleWindow.cornerRadius(of: window)
        let w = shell.bounds
        var corners: CACornerMask = []
        if abs(rect.minY - w.minY) < 0.5 {
            if abs(rect.minX - w.minX) < 0.5 { corners.insert(flipped ? .layerMinXMaxYCorner : .layerMinXMinYCorner) }
            if abs(rect.maxX - w.maxX) < 0.5 { corners.insert(flipped ? .layerMaxXMaxYCorner : .layerMaxXMinYCorner) }
        }
        if abs(rect.maxY - w.maxY) < 0.5 {
            if abs(rect.minX - w.minX) < 0.5 { corners.insert(flipped ? .layerMinXMinYCorner : .layerMinXMaxYCorner) }
            if abs(rect.maxX - w.maxX) < 0.5 { corners.insert(flipped ? .layerMaxXMinYCorner : .layerMaxXMaxYCorner) }
        }
        if layer.cornerRadius != radius { layer.cornerRadius = radius }
        if layer.maskedCorners != corners { layer.maskedCorners = corners }
    }

    /// Chromium lays its frameless window's content view out below a 22 pt title bar
    /// that Cra hides, leaving a blank band over the page; make it fill the window.
    private func fillContentView(_ w: NSWindow) {
        guard let cv = w.contentView else { return }
        let full = NSRect(origin: .zero, size: w.frame.size)
        if cv.frame != full { cv.frame = full }
    }

    /// Shows the visible tabs' DevTools windows (each split pane keeps its own) and hides
    /// the other tabs'. Chrome-style pages get Chrome's dockable frontend (see CraCEF's
    /// DevToolsClient): its window spans the pane's body under the page, which is laid
    /// over the placeholder it reports. Alloy pages keep the shell's own split with CEF's
    /// window on the right, for the focused tab only.
    func browserManagerDevToolsChanged() {
        BoostEditorController.shared.devToolsChanged()
        guard let window else { return }
        let visible = browsers.visibleDevToolsWindow
        let shown = browsers.visibleDevToolsWindows
        for (_, view) in browsers.devToolsViews {
            if let w = view.window, !shown.values.contains(where: { $0 === w }) { w.orderOut(nil) }
        }
        let selfDock = visible != nil && browsers.visibleRuntime?.hostWindow != nil
        let docked = browsers.visibleTabID.flatMap { browsers.devToolsDockedState[$0] } ?? true
        devToolsLog("devToolsChanged visible=\(visible?.windowNumber ?? -1) selfDock=\(selfDock) docked=\(docked) visibleTabs=\(browsers.visibleTabIDs.map { $0.uuidString.prefix(8) }) overlay=\(overlayPanel?.windowNumber ?? -1)")
        // This runs on every tab switch; the shell is laid out again only when the dock changed.
        let devToolsVisible = visible != nil && (docked || !selfDock)
        if visible != nil || shell.devToolsFrontendDocked != selfDock || shell.devToolsVisible != devToolsVisible {
            shell.devToolsFrontendDocked = selfDock
            shell.devToolsVisible = devToolsVisible
            shell.needsLayout = true
            shell.layoutSubtreeIfNeeded()
        }
        if visible == nil, shell.frontendPageRect != nil { shell.frontendPageRect = nil }
        var attached = false
        for id in browsers.visibleTabIDs {
            guard let w = shown[id] else { continue }
            let chrome = browsers.runtime(for: id)?.hostWindow != nil
            if chrome, browsers.devToolsDockedState[id] == false {
                detachDevToolsWindow(w, tab: id)
                continue
            }
            attachDevToolsWindow(w, selfDock: chrome, tab: id)
            // Chrome's frontend spans its pane's body (positionPageWindows keeps it there);
            // Alloy's sits in the shell's dock.
            if !chrome { positionDevToolsWindow((shell.devToolsHost.superview ?? shell.contentContainer).convert(shell.devToolsHost.frame, to: nil), tab: id) }
            w.orderFront(nil)
            attached = true
        }
        if attached { raisePageWindows() }
        positionPageWindows(lastPaneFrames)
    }

    /// The docked frontend moved its placeholder (also streamed while its splitter is dragged).
    func browserManagerDevToolsPageBoundsChanged() {
        positionPageWindows(lastPaneFrames)
        if Self.devToolsLogEnabled, devToolsTreeDumps < 2 {
            devToolsTreeDumps += 1
            if let dev = browsers.visibleDevToolsWindow { devToolsLog("devtools win \(dev.windowNumber) style \(dev.styleMask.rawValue) close=\(buttonState(dev)) opaque=\(dev.isOpaque)\n" + viewTree(dev.contentView)) }
            if let page = browsers.visibleRuntime?.hostWindow { devToolsLog("page win \(page.windowNumber) style \(page.styleMask.rawValue) close=\(buttonState(page)) opaque=\(page.isOpaque) key=\(page.isKeyWindow)\n" + viewTree(page.contentView)) }
            if let panel = overlayPanel { devToolsLog("overlay \(panel.windowNumber) style \(panel.styleMask.rawValue) frame \(panel.frame)\n" + viewTree(panel.contentView, max: 1)) }
        }
    }
    private var devToolsTreeDumps = 0

    /// `cra://debug?windowCorners=<label>`: each child window's frame, style, corner mask, whether
    /// Cra squares it and the radius macOS still clips it to (`os=`, 0 for a squared window; the
    /// card's own corners are the layer's `r=`).
    func debugWindowCorners(_ label: String) {
        guard let window else { return }
        for (i, w) in (window.childWindows ?? []).enumerated() where w.isVisible {
            let l = w.contentView?.layer
            let corners = l.map { "r=\($0.cornerRadius) mask=\($0.maskedCorners.rawValue) clip=\($0.masksToBounds ? 1 : 0)" } ?? "no layer"
            let role = browsers.runtimes.values.contains { $0.hostWindow === w } ? "page" : (browsers.visibleDevToolsWindow === w ? "devtools" : "\(type(of: w))")
            CraLog.note("window corners \(label): child\(i) \(role) #\(w.windowNumber) frame=\(Int(w.frame.minX)),\(Int(w.frame.minY)),\(Int(w.frame.width)),\(Int(w.frame.height)) style=\(w.styleMask.rawValue) square=\(ChromiumWindowCorners.isSquareWindow(w) ? 1 : 0) os=\(ChromiumWindowCorners.effectiveRadius(w).map { "\(Int($0.rounded()))" } ?? "-") \(corners)")
        }
    }
    private func buttonState(_ w: NSWindow) -> String {
        guard let b = w.standardWindowButton(.closeButton) else { return "none" }
        return "hidden=\(b.isHidden) alpha=\(b.alphaValue) frame=\(b.frame) superHidden=\(b.superview?.isHidden ?? false)"
    }
    private func viewTree(_ v: NSView?, depth: Int = 0, max: Int = 3) -> String {
        guard let v else { return "(nil)\n" }
        var s = String(repeating: "  ", count: depth) + "\(type(of: v)) \(v.frame) hidden=\(v.isHidden)\n"
        if depth < max { for sub in v.subviews { s += viewTree(sub, depth: depth + 1, max: max) } }
        return s
    }

    private func attachDevToolsWindow(_ w: NSWindow, selfDock: Bool, tab: UUID) {
        guard let window else { return }
        if w.parent !== window {
            // CEF made a normal window; strip its chrome so only the DevTools content shows.
            DevToolsWindowChrome.dock(w)
            window.addChildWindow(w, ordered: .above)
            fillContentView(w)
            if selfDock { setDevToolsTitleBarInset(nil, tab: tab) }
        }
        updateDevToolsCorners(w, tab: tab)
    }

    private func updateDevToolsCorners(_ w: NSWindow, tab: UUID) {
        guard let cv = w.contentView else { return }
        cv.wantsLayer = true
        guard let layer = cv.layer else { return }
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        if shell.edgeFlush, let window {
            roundAtWindowCorners(layer, rect: window.convertFromScreen(w.frame), flipped: cv.isFlipped)
            return
        }
        layer.cornerRadius = shell.cardRadiusNow
        // Frontend-docked: the window spans the card body, so both bottom corners are
        // card corners, and the top ones too without the toolbar (else they showed past the
        // page's rounded top corners). Shell-docked (Alloy): it sits right of the page.
        let selfDock = browsers.runtime(for: tab)?.hostWindow != nil
        let bottom: CACornerMask = cv.isFlipped ? [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] : [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        let all: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        layer.maskedCorners = selfDock ? (shell.panesShowBars ? bottom : all) : [.layerMaxXMaxYCorner, .layerMaxXMinYCorner]
    }

    /// "Undock into separate window": the frontend's window becomes a floating window of its own.
    private func detachDevToolsWindow(_ w: NSWindow, tab: UUID) {
        guard let window else { return }
        guard w.parent === window else {
            // Already floating: show it again after a tab switch without taking the keys.
            if !w.isVisible { w.orderFront(nil) }
            return
        }
        window.removeChildWindow(w)
        DevToolsWindowChrome.undock(w, over: window, pageURL: browsers.runtime(for: tab)?.browser.currentURL)
        setDevToolsTitleBarInset(w, tab: tab)
        w.makeKeyAndOrderFront(nil)
    }

    /// The undocked window's title bar covers the top of the frontend: its layout moves down by
    /// the bar's height (0 when docked, `w` nil).
    private func setDevToolsTitleBarInset(_ w: NSWindow?, tab: UUID) {
        browsers.runtime(for: tab)?.browser.executeJavaScript(DevToolsWindowChrome.titleBarInsetScript(for: w), inDevTools: true)
    }

    /// Page windows go above the DevTools windows (each spans its pane's body when the
    /// frontend docks), and the overlay panel above everything.
    private func raisePageWindows() {
        guard let window else { return }
        // Child windows ignore orderWindow:relativeTo:; re-adding a child puts it above its siblings.
        for id in browsers.visibleTabIDs {
            guard let w = browsers.runtime(for: id)?.hostWindow, w.parent === window else { continue }
            window.removeChildWindow(w)
            window.addChildWindow(w, ordered: .above)
            w.orderFront(nil)
        }
        raiseOverlayPanels()
    }

    private func positionDevToolsWindow(_ rectInWindow: NSRect, tab id: UUID) {
        guard let window, let v = browsers.devToolsViews[id], let w = v.window, w.parent === window else { return }
        let onScreen = window.convertToScreen(rectInWindow)
        if w.frame != onScreen { w.setFrame(onScreen, display: true) }
        fillContentView(w)
        updateDevToolsCorners(w, tab: id)
        if let cv = w.contentView, v.frame != cv.bounds {
            v.frame = cv.bounds
        }
    }

    func browserManagerHandleKey(_ event: NSEvent) -> Bool {
        // Chrome: Escape leaves a page's element fullscreen, before the page sees the key.
        // Chrome's own handling never got it here: the video stayed fullscreen.
        if event.keyCode == 53, event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
           let id = contentFullscreenTab, let browser = browsers.runtime(for: id)?.browser {
            browser.exitFullscreen()
            return true
        }
        return app.handleReservedKey(event)
    }
    func browserManagerHandleUnhandledKey(_ event: NSEvent) -> Bool { app.handleUnhandledKey(event) }
    /// A hidden page asked for focus: the Picture in Picture window's "back to tab" button.
    func browserManagerFocusedBrowser(_ tabID: UUID) {
        guard tabID != browsers.visibleTabID else { return }
        // Split view: clicking into another pane focuses it (Arc: focusedContentID
        // follows the click); its toolbar gets the options button and shortcuts act on it.
        if browsers.visibleTabIDs.contains(tabID) {
            store.selectTab(tabID, window: windowID)
            return
        }
        guard browsers.runtime(for: tabID)?.browser.isInPictureInPicture == true else { return }
        store.selectTab(tabID, window: windowID)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func browserManagerPageClosedTab(_ tabID: UUID) { closeTab(tabID) }

    /// Arc's translation toasts (#310), for a page this window shows.
    func browserManagerTranslationToast(_ tabID: UUID, text: String) {
        guard store.visiblePaneTabIDs(in: focusedSpaceID, window: windowID).contains(tabID) else { return }
        showToast(text)
    }

    /// An extension brought one of this window's tabs to the front (SwitchyOmega's Options with
    /// its settings tab already open): selected, as in Arc (GitHub #38). A page that asked
    /// (Chromium allows that after a click on its notification, or from its opener) also
    /// brings the window and Cra to the front, like Arc: Messenger's chat opens on a click.
    /// What comes forward is TabActivationRaise's: never this window from behind another
    /// browser window in use (#239).
    func browserManagerActivationRequested(_ tabID: UUID, byPage: Bool) {
        store.selectTab(tabID, window: windowID)
        var key = NSApp.keyWindow
        while let parent = key?.parent { key = parent }
        let windowIsKey = key != nil && key === window
        let otherKey = key.map { k in app.mainWindows.contains { $0 !== self && $0.window === k } } ?? false
        let outcome = TabActivationRaise.outcome(byPage: byPage, appActive: NSApp.isActive, windowIsKey: windowIsKey,
                                                 anotherBrowserWindowIsKey: otherKey)
        CraLog.note("tab \(tabID.uuidString.prefix(8)) brought to the front by its \(byPage ? "page" : "extension"): "
                    + "\(outcome) (window key=\(windowIsKey), another window key=\(otherKey))")
        switch outcome {
        case .windowAndApp where !HitchMonitor.background:
            showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
        case .window:
            showWindow(nil)
        default:
            break
        }
    }

    /// Arc's Peek (PeekTrigger): the link opens over the window and the tab stays put.
    func browserManagerOpensPeek(url: String, fromTab tabID: UUID, pageURL: String, shiftClick: Bool, newTab: Bool) -> Bool {
        guard !isIncognito, PeekTrigger.opens(url, from: pageURL, shiftClick: shiftClick, newTab: newTab,
                                               fromPinned: store.isPinned(tabID), settings: store.settings) else { return false }
        app.openPeek(url: url, over: self, fromTab: tabID)
        return true
    }

    /// Arc's ⌥⌘-click (LittleWindowTrigger, decided by BrowserManager): the link opens in a Little Window and the
    /// tab stays put. After Chromium's call returns, as a split pane opens: the window makes a page of its own.
    func browserManagerOpensLittleWindow(url: String, fromTab tabID: UUID) -> Bool {
        guard !isIncognito else { return false }
        let space = focusedSpaceID
        DispatchQueue.main.async { [weak self] in _ = self?.app.openLittleWindow(url: url, space: space) }
        return true
    }

    func browserManagerCaptureImage(at point: NSPoint, tabID: UUID) {
        guard tabID == browsers.visibleTabID else { return }
        capturePage(liftImageAt: point)
    }

    func browserManagerOpenLink(_ url: String, in kind: CraLinkWindow, space: UUID?, fromIncognito: Bool) {
        app.openLink(url, in: kind, space: space, fromIncognito: fromIncognito)
    }

    /// Open Link in Split View (#257): the link opens as a pane beside the page it was clicked in,
    /// as ⌥Return does from the command bar; a split of four says so, as Add Split View does.
    /// Tab ▸ Load on Start: those tabs' pages load once Cra has opened, behind the page on screen.
    func loadTabsOnStart() {
        var n = 0
        for item in store.allTabs() where item.tab?.loadOnStart == true && browsers.runtime(for: item.id) == nil
            && !store.isIncognito(item: item.id) {
            if browsers.ensureRuntime(for: item.id) != nil { n += 1 }
        }
        if n > 0 { CraLog.note("load on start: \(n) tab\(n == 1 ? "" : "s") loaded behind") }
    }

    func browserManagerOpenLinkInPeek(_ url: String, fromTab tabID: UUID) {
        guard !isIncognito else { return }
        CraLog.note("link opens in Peek from the page's menu")
        app.openPeek(url: url, over: self, fromTab: tabID)
    }

    func browserManagerOpenLinkInSplit(_ url: String, fromTab tabID: UUID) {
        // cra:// is Cra's scripting scheme; a page must not drive it.
        if url.isEmpty || InternalScheme.isInternal(url) || store.item(tabID) == nil { return }
        guard store.openLinkInSplit(url, from: tabID, window: windowID) != nil else {
            showToast("Cannot Add New Pane")
            return
        }
        refresh()
    }

    /// The area Arc's Peek is centred on (window coordinates): right of the sidebar to the
    /// window's edge, top to bottom; the whole window with the sidebar out of the way.
    private func peekAreaInWindow() -> NSRect {
        guard let window else { return .zero }
        return PeekLayout.area(window: window.frame.size, contentMinX: peekContentMinX())
    }

    /// Where the sidebar ends (window coordinates), 0 with it hidden.
    private func peekContentMinX() -> CGFloat {
        // Asked from windowDidResize, before the shell has laid out at the new size.
        shell.layoutSubtreeIfNeeded()
        let content = shell.convert(shell.contentContainer.frame, to: nil)
        let sidebarShown = store.window(windowID).sidebarVisible && content.minX > CraMetrics.contentInset
        return sidebarShown ? content.minX : 0
    }

    /// Where a click closes a Peek (screen coordinates): the page area, not the sidebar, whose rows
    /// still open their tabs (#242).
    func peekDismissArea() -> NSRect {
        guard let window else { return .zero }
        return PeekLayout.dismissArea(covering: window.frame, contentMinX: peekContentMinX())
    }

    /// cra://debug?peekCatcher: whether the shown Peek's click catcher leaves the sidebar's rows to
    /// the sidebar (#242).
    func peekCatcherReadout() -> String {
        guard let window, let dim = peeks.first(where: { !$0.isParked })?.dimFrame else { return "none" }
        let sidebar = window.convertToScreen(shell.sidebarHost.convert(shell.sidebarHost.bounds, to: nil))
        guard store.window(windowID).sidebarVisible else { return "sidebar=hidden floating=\(floatingSidebarOverPeek())" }
        return "sidebar=\(dim.intersects(sidebar.insetBy(dx: 0.5, dy: 0.5)) ? "covered" : "clear")"
    }

    /// Whether the hidden sidebar, slid out over the page, is in front of the shown Peek's windows
    /// (#295): "above", "below", or "none" while it isn't out. Read from the window server's order.
    private func floatingSidebarOverPeek() -> String {
        guard let sidebar = floatingSidebar?.attachedPanels.last, sidebar.isVisible else { return "none" }
        // The card's page is a Chromium window of its own, a child of the card's.
        let peekWindows = peeks.flatMap { $0.peekWindows + ($0.peekWindows.isEmpty ? [] : [$0.browser?.hostWindow].compactMap { $0 }) }
        // Front to back as the window server has them; the window's child order (back to front)
        // when it doesn't list one of them yet.
        var frontToBack = NSWindow.windowNumbers(options: [])?.map(\.intValue) ?? []
        if !([sidebar] + peekWindows).allSatisfy({ frontToBack.contains($0.windowNumber) }) {
            frontToBack = (window?.childWindows ?? []).reversed().map(\.windowNumber)
            for p in peeks { if let card = p.window, let host = p.browser?.hostWindow, let i = frontToBack.firstIndex(of: card.windowNumber) { frontToBack.insert(host.windowNumber, at: i) } }
        }
        guard let mine = frontToBack.firstIndex(of: sidebar.windowNumber) else { return "none" }
        let behind = peekWindows.allSatisfy { w in frontToBack.firstIndex(of: w.windowNumber).map { $0 > mine } ?? true }
        return behind ? "above" : "below"
    }

    /// The whole area, where a Peek grows from and goes back to (screen coordinates).
    func peekArea() -> NSRect { window?.convertToScreen(peekAreaInWindow()) ?? .zero }

    /// Arc's Peek card (screen coordinates).
    func peekFrame() -> NSRect { window?.convertToScreen(PeekLayout.card(in: peekAreaInWindow())) ?? .zero }

    /// Close, Expand and Add To Split beside the card, top first (screen coordinates).
    func peekButtonFrames() -> [NSRect] {
        guard let window else { return [] }
        return PeekLayout.buttons(beside: PeekLayout.card(in: peekAreaInWindow())).map { window.convertToScreen($0) }
    }

    /// The link a Peek opens from (GitHub #204): Arc grows the card out of it and closes it back in.
    /// The link under the pointer in `tabID`'s page, else the page's focused link, found by
    /// PeekLayout's script in Cra's isolated world, with a picture of it cut from Chromium's
    /// screenshot. Answers within `PeekSource.wait` whatever Chromium does: nil without a link (the
    /// Peek then grows from the whole area), no picture when the screenshot is late.
    func peekSource(fromTab tabID: UUID?, completion: @escaping (PeekSource?) -> Void) {
        guard let tabID, let window, let rt = browsers.runtimes[tabID], let host = rt.hostWindow, host.parent === window,
              host.isVisible, rt.browser.isCreated, !rt.browser.isClosed else {
            CraLog.note("peek: from the click (no page to find the link in)")
            completion(nil)
            return
        }
        let completion: (PeekSource?) -> Void = { source in
            CraLog.note(source.map { "peek: from a link at \(Int($0.rect.minX)),\(Int($0.rect.minY)) \(Int($0.rect.width))×\(Int($0.rect.height))\($0.image == nil ? ", no picture" : "")" }
                ?? "peek: from the click (no link under the pointer or focused)")
            completion(source)
        }
        let pageFrame = host.frame
        let m = NSEvent.mouseLocation
        let pointer = pageFrame.contains(m)
            ? CGPoint(x: (m.x - pageFrame.minX) / pageFrame.width, y: (pageFrame.maxY - m.y) / pageFrame.height) : nil
        var fraction: CGRect??
        var picture: CGImage??
        var answered = false
        let finish: (Bool) -> Void = { [weak window] timedOut in
            guard !answered, let window else { return }
            guard case .some(let found) = fraction else {
                if timedOut { answered = true; completion(nil) }
                return
            }
            if picture == nil, !timedOut { return }
            answered = true
            guard let found, let rect = PeekLayout.source(fraction: found, in: window.convertFromScreen(pageFrame)) else { completion(nil); return }
            let image = (picture ?? nil).flatMap { PeekSource.crop($0, to: found) }
            completion(PeekSource(tabID: tabID, rect: rect, image: image))
        }
        let script = PeekLayout.sourceScript(pointer: pointer)
        let params = (try? JSONSerialization.data(withJSONObject: ["expression": script, "returnByValue": true]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        rt.browser.evaluate(inIsolatedWorld: PageScript.world, params: params) { result, _ in
            let found = PeekSource.value(result).flatMap(PeekLayout.fraction(fromScript:))
            DispatchQueue.main.async { if fraction == nil { fraction = .some(found) }; finish(false) }
        }
        rt.browser.sendDevToolsMethod("Page.captureScreenshot", params: #"{"format":"png","optimizeForSpeed":true}"#) { shot, _ in
            let image = PeekSource.image(fromScreenshot: shot)
            DispatchQueue.main.async { if picture == nil { picture = .some(image) }; finish(false) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + PeekSource.wait) { finish(true) }
    }

    /// Where the link a Peek came from is now (the page may have scrolled), in this window's
    /// coordinates; nil when it's gone, off the page or Chromium doesn't answer in time.
    func peekSourceAgain(_ source: PeekSource, completion: @escaping (NSRect?) -> Void) {
        guard let window, let rt = browsers.runtimes[source.tabID], let host = rt.hostWindow, host.parent === window,
              host.isVisible, rt.browser.isCreated, !rt.browser.isClosed else { completion(nil); return }
        var answered = false
        let params = (try? JSONSerialization.data(withJSONObject: ["expression": PeekLayout.sourceAgainScript, "returnByValue": true]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        rt.browser.evaluate(inIsolatedWorld: PageScript.world, params: params) { [weak window, weak host] result, _ in
            let found = PeekSource.value(result).flatMap(PeekLayout.fraction(fromScript:))
            DispatchQueue.main.async {
                guard !answered else { return }
                answered = true
                guard let window, let host, let found else { completion(nil); return }
                completion(PeekLayout.source(fraction: found, in: window.convertFromScreen(host.frame)))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + PeekSource.wait) {
            guard !answered else { return }
            answered = true
            completion(nil)
        }
    }

    /// Arc fades the page under a Peek to 28 % over the window's background, its sidebar as it is;
    /// Cra also draws it back a little unless it fills the window edge to edge (PR #221).
    /// `PeekVeil` says which Peek it is veiled for, so a Peek that ended early never veils it and
    /// one whose close already fades it back doesn't snap that fade.
    private var peekVeil = PeekVeil()

    /// `peek` is opening over this window, or back with its tab (`animated` false, #242).
    func showPeekVeil(for peek: UUID, animated: Bool = true) {
        guard peekVeil.show(for: peek) else { return }
        if animated { applyPeekVeil(duration: PeekLayout.openVeilDuration, timing: PeekTransition.easeOutCubic) } else { applyPeekVeil(duration: 0) }
    }

    /// `peek` waits on its tab while another is on screen (#242): the page snaps back, and the
    /// Peek can veil it again.
    func parkPeekVeil(for peek: UUID) {
        guard peekVeil.hide(for: peek) else { return }
        applyPeekVeil(duration: 0)
    }

    /// `peek` is closing: the page comes back over Arc's 0.2 s while the card lands.
    func hidePeekVeil(for peek: UUID) {
        guard peekVeil.hide(for: peek) else { return }
        applyPeekVeil(duration: PeekLayout.closeVeilDuration, timing: PeekTransition.easeOutCubic)
    }

    /// `peek`'s window is gone (Expand and Add To Split don't animate): the page snaps back.
    func endPeekVeil(for peek: UUID) {
        guard peekVeil.end(for: peek) else { return }
        applyPeekVeil(duration: 0)
    }

    /// cra://debug?peekShown: the page behind a Peek as it is set now (the peek-backdrop scenario).
    func peekBackdropShown() -> String {
        func scale(_ v: NSView?) -> String {
            String(format: "%.3f", v?.layer.map { CATransform3DGetAffineTransform($0.sublayerTransform).a } ?? 1)
        }
        let content = shell.contentContainer
        // Pages in their own windows (DevTools docked, or CRA_EMBED_PAGES=0); embedded ones go with the content.
        let pages = browsers.runtimes.values.compactMap(\.hostWindow).filter { $0.parent === window && !EmbeddedPages.isHost($0) }
        return String(format: "veiled=%d alpha=%.2f scale=%@ windows=%@", peekVeil.isOn ? 1 : 0, content.alphaValue, scale(content),
                      pages.map { String(format: "%.2f@", $0.alphaValue) + scale($0.contentView) }.joined(separator: ","))
    }

    private func applyPeekVeil(duration: TimeInterval, timing: CAMediaTimingFunction? = nil) {
        let look = PeekLayout.backdrop(veiled: peekVeil.isOn, edgeToEdge: shell.edgeToEdge)
        let content = shell.contentContainer
        let center = CGPoint(x: content.bounds.midX, y: content.bounds.midY)
        PeekTransition.scaleBackdrop(content, around: center, to: look.scale, duration: duration, timing: timing)
        // Not a window drawing for releaseHiddenFrames: a child below this one, it stays transparent.
        let pages = browsers.runtimes.filter { !releasingFrames.contains($0.key) }.values.compactMap(\.hostWindow).filter { $0.parent === window }
        if let window {
            // Each page window shrinks around the same point on screen as the page's card.
            let screenCenter = window.convertPoint(toScreen: content.convert(center, to: nil))
            for page in pages where !EmbeddedPages.isHost(page) {
                guard let view = page.contentView else { continue }
                let pageCenter = view.convert(page.convertPoint(fromScreen: screenCenter), from: nil)
                PeekTransition.scaleBackdrop(view, around: pageCenter, to: look.scale, duration: duration, timing: timing)
            }
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = timing
            content.animator().alphaValue = look.alpha
            for w in pages { w.animator().alphaValue = look.alpha }
        }
    }

    /// Add To Split from a Peek: the peeked page, a new tab, joins `source` as a pane (Arc's
    /// openInSplit), or a toast when the split is full.
    func canAddPane(to source: UUID) -> Bool { store.paneTabIDs(for: source).count < 4 }

    func joinSplit(_ tabID: UUID, with source: UUID) {
        let split = store.splitContaining(source).map { sp in store.addToSplit(sp.id, tabID: tabID, at: nil); return store.item(sp.id) }
            ?? store.createSplit(with: [source, tabID], at: source)
        store.selectTab(split.flatMap { store.paneID(for: tabID, in: $0) } ?? tabID, window: windowID)
    }

    private var peeks: [LittleWindowController] { app.littleWindows.filter { $0.peekParent === self } }

    /// Arc keeps a Peek per tab (#242): each shows while its tab is on screen here, waits out of
    /// sight while another is, and goes with its tab (PeekPresence).
    private func syncPeeks(onScreen panes: [UUID]) {
        for p in peeks {
            switch PeekPresence.of(peekFrom: p.peekSourceTab, onScreen: panes, tabExists: p.peekSourceTab.map { store.item($0) != nil } ?? false) {
            case .shown:
                p.unparkPeek()
                // The sidebar shown or hidden under it: the catcher follows the page area.
                if let f = p.dimFrame, f != peekDismissArea() { p.repositionPeek() }
            case .parked: p.parkPeek()
            case .dropped: p.dropPeek()
            }
        }
    }

    /// `tab`'s page closed (a pinned tab's ⌘W keeps its row): its Peek goes with it (#242).
    func dropPeeks(from tab: UUID) {
        for p in peeks where p.peekSourceTab == tab { p.dropPeek() }
    }

    /// cra://debug?peeks: this window's Peeks, on screen or not, and their pages (#242).
    func peeksShown() -> String {
        let list = peeks.map { p in "\(p.window.map { $0.isVisible && $0.alphaValue > 0 } == true ? "shown" : "hidden") \(p.currentURL)" }
        return list.isEmpty ? "none" : list.joined(separator: ", ")
    }

    /// The Peek closed last over this window and the tab it came from: Arc's ⇧⌘T brings it back
    /// when nothing was archived after it.
    var closedPeek: (url: String, tabID: UUID?, at: Date)?

    // MARK: Tabs

    /// cra://debug?devtoolsjs=…: run script in the current tab's DevTools frontend.
    func debugRunInDevTools(_ script: String) { currentBrowser?.executeJavaScript(script, inDevTools: true) }

    func closeCurrentTab() {
        // ⌘W with tabs picked in the sidebar takes all of them. As in Arc (SidebarClose.commandW),
        // a Today tab among them archives them all, pinned ones too; otherwise they all keep
        // their place and unload.
        let ids = sidebarUI.multiSelection.isEmpty ? selectedTabID.map { [$0] } ?? [] : Array(sidebarUI.multiSelection)
        guard !ids.isEmpty else { return }
        sidebarUI.clearPicks()
        let action = SidebarClose.commandW(anyToday: ids.contains { !store.isPinned($0) })
        // The open tab goes last so closing it doesn't hop through tabs about to close.
        let open = selectedTabID
        for id in ids.filter({ $0 != open }) + ids.filter({ $0 == open }) {
            if action == .keep || !store.isPinned(id) {
                closeTab(id)
            } else {
                // A pinned split goes as one, as it closes as one.
                for p in store.paneTabIDs(for: id) { store.archiveTab(p, reason: .manual) }
            }
        }
    }

    /// Back (⌘[, the toolbar, the Go menu) on tab `id`, the one in front by default: the page's
    /// own history, else a tab a link opened closes and the tab it came from shows again, as
    /// Arc's navigateBackToReferrer (GitHub #273).
    func goBack(_ id: UUID? = nil) {
        guard let id = id ?? browsers.visibleTabID, let b = browsers.runtime(for: id)?.browser else { return }
        switch store.backStep(id, canGoBack: b.canGoBack) {
        case .history:
            b.goBack()
        case .close(let referrer):
            store.closeToReferrer(id, referrer: referrer, window: windowID)
        case .none:
            break
        }
    }

    /// The tab whose page `event` landed on: a Chromium page in its own host window, or the pane
    /// under the point for a page in this window (an embedded Chromium page, whose view lives in
    /// the pane card and not its host window, or an Easel or WebKit page). A swipe goes to the
    /// page under the pointer, which in Split View needn't be the focused pane. nil anywhere else
    /// (the sidebar, a panel).
    func pageTab(under event: NSEvent) -> UUID? {
        guard let target = event.window else { return nil }
        return browsers.visibleTabIDs.first { id in
            guard let browser = browsers.runtime(for: id)?.browser else { return false }
            if let host = browser.hostWindow, host === target { return true }
            let embedded = browser.hostWindow.flatMap { EmbeddedPages.isHost($0) ? EmbeddedPages.pageViews(of: $0)?.last : nil }
            let view = embedded ?? browser.containerView
            return view.window === target && view.bounds.contains(view.convert(event.locationInWindow, from: nil))
        }
    }

    /// A two-finger swipe back over tab `id`'s page, which has nothing behind it, so Chromium's
    /// swipe asks Cra (ChromiumHistorySwipe, GitHub #370): what Back does there, a link's tab
    /// closing to the tab it came from. nil when the swipe shouldn't start.
    func swipeBackClose(_ id: UUID) -> (() -> Void)? {
        guard case .close(let referrer) = store.backStep(id, canGoBack: false, swipe: true) else { return nil }
        return { [weak self] in
            guard let self else { return }
            store.closeToReferrer(id, referrer: referrer, window: windowID)
        }
    }

    /// Whether Back does anything on tab `id` showing `browser` (Arc: canNavigateBack).
    private func canNavigateBack(_ id: UUID?, _ browser: CraBrowser?) -> Bool {
        guard let id, let browser else { return false }
        return store.backStep(id, canGoBack: browser.canGoBack) != .none
    }

    /// Today tabs are archived. Pinned tabs and favorites stay; they unload
    /// and return to their pinned page (Arc's close-on-pinned behaviour).
    func closeTab(_ id: UUID) {
        guard let item = store.item(id), item.isTab else { return }
        if store.isPinned(id) {
            // A pinned split closes as one: every pane unloads and goes back to its page.
            let panes = store.paneTabIDs(for: id)
            let wasSelected = selectedTabID.map(panes.contains) ?? false
            for p in panes {
                _ = store.resetPinnedTab(p)
                for w in app.mainWindows { w.browsers.unload(p); w.dropPeeks(from: p) }
            }
            // Arc goes back to the tab shown before this one if its page is still loaded, and
            // otherwise shows nothing (CloseSuccessor). The panes were just unloaded, so they
            // don't count.
            if wasSelected { store.selectTab(store.closeSuccessor(ofPinned: id, window: windowID), window: windowID) }
        } else {
            store.archiveTab(id, reason: .manual)
        }
    }

    /// The space's open tabs, the latest first. A pinned tab that was closed (unloaded) isn't
    /// open: ⌃Tab doesn't list it.
    private func openRecentTabs(limit: Int) -> [UUID] {
        Array(store.recentTabs(in: focusedSpaceID, limit: .max, window: windowID)
            .filter { $0 == selectedTabID || !store.isPinned($0) || app.runtime(for: $0) != nil }
            .prefix(limit))
    }

    func resetPinnedTab(_ id: UUID) {
        guard let home = store.resetPinnedTab(id) else { return }
        app.runtime(for: id)?.browser.loadURL(home)
    }

    /// Arc's ⌘-click on the favicon of a pinned tab away from its page ("Separate From Pinned
    /// Tab", GitHub #139): the page moves to a new Today tab at the top, the pinned tab goes back
    /// to its page and stays open.
    func separatePinnedTab(_ id: UUID) {
        guard let t = store.item(id)?.tab, store.isPinned(id), t.url != t.savedURL else { return }
        _ = store.createTab(url: t.url, title: t.savedTitle, in: store.spaceID(ofItem: id), select: false, index: 0)
        resetPinnedTab(id)
        store.selectTab(id, window: windowID)
    }

    /// Edit Pinned URL… (#54): Arc's dialog with the pinned URL. A page showing the old
    /// pinned URL loads the new one; one navigated away stays where it is.
    func editPinnedURL(_ id: UUID) {
        guard let window, let tab = store.item(id)?.tab, store.isPinned(id), tab.liveItemURL == nil else { return }
        DialogPanel.present(over: window) { [weak self] close in
            EditPinnedURLDialog(url: tab.savedURL, onSave: { url in
                close()
                guard let self, let before = self.store.item(id)?.tab, self.store.setPinnedURL(id, to: url),
                      before.url == before.savedURL, before.url != url else { return }
                self.app.runtime(for: id)?.browser.loadURL(url)
            }, onCancel: close)
        }
    }

    func cycleTab(_ delta: Int) {
        let tabs = store.visibleTabs(in: focusedSpaceID)
        guard !tabs.isEmpty else { return }
        let idx = selectedTabID.flatMap { id in tabs.firstIndex { $0.id == id } } ?? -1
        let n = tabs.count
        store.selectTab(tabs[((idx + delta) % n + n) % n].id)
    }

    func zoom(by delta: Double) {
        guard let b = currentBrowser else { return }
        b.setZoomLevel(b.zoomLevel() + delta)
    }

    var captureOverlay: CaptureOverlay?
    var captureRequest: (id: UUID, window: NSWindow)?

    /// Send To… an easel: the capture goes on it, under what is there, and its tab comes forward
    /// (a new one when it has none open).
    private func sendCapture(_ png: Data, toEasel id: UUID) {
        guard EaselFiles.add(picture: png, to: id) else { return }
        CraLog.note("capture sent to an easel, which now holds \(EaselFiles.load(id).items.count) items")
        let url = Easel(id: id).url
        if let tab = store.allTabs().first(where: { $0.tab?.url == url }) {
            browsers.unload(tab.id)  // opened again from the file, picture included
            store.selectTab(tab.id, window: windowID)
            refresh()
        } else {
            _ = store.createTab(url: url, title: EaselFiles.load(id).title, select: true, window: windowID)
        }
    }

    /// Testing without the pointer (cra://debug?captureToEasel=1): the visible page captured and
    /// the capture menu's New Easel chosen.
    func debugCaptureToEasel(send: Bool = false) {
        currentBrowser?.sendDevToolsMethod("Page.captureScreenshot", params: #"{"format":"png"}"#) { [weak self] shot, _ in
            MainActor.assumeIsolated {
                let o = shot.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                let png = (o?["data"] as? String).flatMap { Data(base64Encoded: $0) }
                // send: Send To… the easel edited last, as if picked from its menu.
                if send, let png, let last = EaselFiles.all().first { self?.sendCapture(png, toEasel: last.id); return }
                self?.captureFinished(.newEasel, png)
            }
        }
    }

    /// The capture menu's choice, once the overlay is down.
    func captureFinished(_ action: CaptureOverlay.Action?, _ png: Data?, in peek: LittleWindowController? = nil) {
        captureOverlay = nil
        if let peek {
            if peek.canCapturePage, action != nil || NSApp.isActive { peek.focusPage() }
        } else if action != nil || NSApp.isActive, window?.isVisible == true {
            window?.makeKey()
            currentBrowser?.setFocused(true)
        }
        switch action {
        case .copy?:
            guard let png else { return }
            PageCommands.copyCapture(png)
            if let peek { peek.showToast("Screenshot Copied to Clipboard") } else { showToast("Screenshot Copied to Clipboard") }
        case .save?:
            if let png { saveCapture(png, over: peek?.window) }
        case .message?:
            if let png { sendCaptureViaMessages(png) }
        case .newEasel?:
            guard let png, let easel = EaselFiles.create(withPicture: png) else { return }
            _ = store.createTab(url: easel.url, title: easel.title, select: true, window: windowID)
        case .sendToEasel?:
            guard let png else { return }
            let easels = EaselFiles.all()
            guard !easels.isEmpty else {
                if let easel = EaselFiles.create(withPicture: png) { _ = store.createTab(url: easel.url, title: easel.title, select: true, window: windowID) }
                return
            }
            let menu = NSMenu()
            for e in easels {
                MenuItems.add(menu, e.title) { [weak self] in self?.sendCapture(png, toEasel: e.id) }
            }
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        case .retake?:
            capturePage(in: peek)
        case nil:
            break
        }
    }

    /// Arc's "Send via iMessage…": Messages' compose sheet with the capture attached.
    private func sendCaptureViaMessages(_ png: Data) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Pane Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(PageCommands.captureFileName())
        guard (try? png.write(to: url)) != nil, let service = NSSharingService(named: .composeMessage),
              service.canPerform(withItems: [url]) else {
            showToast("Messages Isn't Available")
            return
        }
        service.perform(withItems: [url])
    }

    // MARK: Sidebar

    /// Docking and undocking's slide: Arc's near-instant one, or Settings ▸ Appearance ▸ Sidebar ▸
    /// "Animate sidebar docking"'s glide.
    var dockingMotion: (duration: TimeInterval, curve: (Double, Double, Double, Double)) {
        SidebarMotion.docking(animated: store.settings.animateSidebarDocking)
    }

    func toggleSidebar() {
        // The window is changing: a tip on the toggle would hang over the page (ArcTooltipController).
        ArcTooltipController.shared.holdForTransition(dockingMotion.duration + 0.1)
        // Over a page in full screen ⌘S docks the sidebar beside it, the card stepping in from the
        // screen's edges (Arc), and takes it away again; the sidebar's own setting stays as it was
        // for when the page leaves full screen. The floating sidebar comes home first to slide in.
        if shell.contentFullscreen {
            let dock = !shell.fullscreenSidebar
            if dock, shell.sidebarDetached { floatingSidebar?.prepareForAnchoring() }
            CraLog.note("sidebar slides \(dock ? "docked" : "away") over \(dockingMotion.duration) s")
            shell.setFullscreenSidebar(dock, motion: dockingMotion)
            return
        }
        if sidebarUI.libraryPage != nil {
            // The Library floated out over a hidden sidebar: leaving it is all ⌘S does.
            let floated = libraryFloats
            closeLibrary()
            if floated { return }
        }
        sidebarVisible.toggle()
        if !sidebarVisible { setFloatingSidebar(false) }
    }

    // MARK: Library

    /// The Library is open in the floating sidebar, over a sidebar that stays hidden: leaving it
    /// puts the sidebar back the way it was (floating while the pointer is on it, else hidden).
    private var libraryFloats = false
    /// ⇧⌘L's close in flight (closeLibraryDirectly); a newer open or close replaces it.
    private var libraryClosing: UUID?
    /// The drag of the sidebar's edge in progress (#287), and whether it has hidden the sidebar.
    private var sidebarResize: SidebarResize?
    private var hiddenByResize = false
    static let hiddenSidebarByDragKey = "hasHiddenSidebarWithGesture"

    /// Arc's Library button and ⇧⌘L: open the Library on the page last shown, or leave it. In a
    /// docked sidebar it slides in and out like the swipe into it (LibrarySwipe).
    func toggleLibrary() {
        let opening = librarySettleSpring.map { $0.target < 1 } ?? (sidebarUI.libraryPage == nil)
        // On a sidebar in sight (docked, or floating out) it slides in like the swipe into it.
        if libraryClosing != nil {
            // Pressed again while it closes: it opens back out.
            showLibrary(sidebarUI.libraryPage ?? sidebarUI.lastLibraryPage)
        } else if !opening, librarySettleSpring == nil, sidebarUI.libraryReveal == nil {
            // Open and at rest: straight back to the space, no slide past the tab list (#4, 10 Nov).
            closeLibraryDirectly()
        } else if librarySwipeFrom == nil, shell.sidebarVisible || floatingSidebar?.isShown == true {
            if opening, sidebarUI.libraryPage == nil { libraryFloats = !shell.sidebarVisible }
            slideLibrary(to: opening ? 1 : 0)
        } else if opening {
            showLibrary(sidebarUI.lastLibraryPage)
        } else {
            closeLibrary()
        }
    }

    /// The Library takes over the sidebar, which widens over the page as a drawer for its page rail
    /// (LibraryView, ShellView.drawerWidth): the page and the window keep their size. With the
    /// sidebar hidden it opens in the floating sidebar, which stays out while it is open, and the
    /// sidebar stays hidden: it is never docked for it.
    func showLibrary(_ page: LibraryPage) {
        cancelDirectClose()
        sidebarUI.lastLibraryPage = page
        let opening = sidebarUI.libraryPage == nil
        withAnimation(.easeOut(duration: 0.05)) { sidebarUI.libraryPage = page }
        let width = libraryWidth(page)
        guard opening else {
            // Another page: the drawer takes its width.
            if shell.drawerWidth != width { shell.animateDrawer(to: width) }
            return
        }
        sidebarUI.downloadsListOpen = false
        commandBar.close()
        shell.sidebarResizable = false
        if sidebarVisible {
            libraryFloats = false
            shell.animateDrawer(to: width)
        } else {
            libraryFloats = true
            if floatingSidebar?.isShown == true {
                shell.animateDrawer(to: width)
            } else {
                // Out of sight: it comes out at the Library's width.
                shell.drawerWidth = width
                floatingSidebar?.show()
            }
        }
        window?.makeKey()
    }

    /// The sidebar's width with the Library in it. The Spaces page widens to fit every space's card,
    /// leaving the page 56 pt (Arc 1.171; the cards scroll sideways when they don't fit); the
    /// drawers (Media, Downloads, Easels, Boosts, Archived Tabs) open to about 400 pt
    /// (LibraryDrawerWidth).
    private func libraryWidth(_ page: LibraryPage) -> CGFloat {
        let sidebar = CGFloat(store.prefs.sidebarWidth)
        let windowWidth = window?.frame.width ?? 1280
        switch page {
        case .spaces:
            let base = sidebar + LibraryMetrics.extraWidth
            let n = store.orderedSpaces.filter { !store.isIncognito(space: $0.id) }.count
            let room = windowWidth - SpacesManagerMetrics.pageRoom
            return max(base, min(SpacesManagerMetrics.width(spaces: n), room))
        case .media, .downloads, .easels, .boosts, .bookmarks, .archive:
            return CGFloat(LibraryDrawerWidth.width(sidebar: Double(sidebar), window: Double(windowWidth)))
        }
    }

    /// The Library's ←, Escape and its other ways out: back to the space on the swipe's spring, the
    /// drawer narrowing as the space slides back in, exactly like a swipe out (slideLibrary); at
    /// once where nothing of it is in sight or with Reduce Motion.
    func leaveLibrary() {
        guard sidebarUI.libraryPage != nil else { return }
        if window?.isVisible == true, shell.sidebarVisible || floatingSidebar?.isShown == true,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            slideLibrary(to: 0)
        } else {
            closeLibrary()
        }
    }

    /// `instantly`: out of sight (the floating sidebar just went), so nothing slides.
    func closeLibrary(instantly: Bool = false) {
        guard sidebarUI.libraryPage != nil else { return }
        cancelDirectClose()
        stopLibrarySettle()
        if instantly {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { sidebarUI.libraryPage = nil }
        } else {
            withAnimation(.easeOut(duration: 0.1)) { sidebarUI.libraryPage = nil }
        }
        sidebarUI.libraryReveal = nil
        shell.sidebarResizable = true
        shell.sidebarWidth = CGFloat(store.prefs.sidebarWidth)
        if instantly { shell.setDrawer(nil) } else { shell.animateDrawer(to: nil) }
        if libraryFloats { restoreFloatingAfterLibrary() }
        currentBrowser?.setFocused(true)
    }

    /// ⇧⌘L (and the Library button) with the Library open and at rest: the drawer narrows back to
    /// the sidebar's width over the Library, which keeps its width under it (covered, not squeezed),
    /// the page card moving back with the drawer; as it lands the tab list is there in one cut. The
    /// swipe-like slide it used showed the tab list sliding in beside the Library first.
    func closeLibraryDirectly() {
        guard sidebarUI.libraryPage != nil, libraryClosing == nil else { return }
        let floatingOut = floatingSidebar.map { $0.isShown && $0.sidebarHidden() } ?? false
        switch LibraryClose.motion(floatingSidebarOut: floatingOut, pointerOnSidebar: pointerOnFloatingSidebar(width: shell.shownSidebarWidth)) {
        case .withFloatingSidebar:
            // The pointer is off it: the sidebar slides away at the Library's width and the Library
            // goes once it's out of sight (floatingSidebarDidHide), one motion. Narrowing first and
            // then hiding showed the drawer collapse to the sidebar's width on the way.
            stopLibrarySettle()
            sidebarUI.libraryReveal = nil
            CraLog.note("library closes directly with the floating sidebar")
            floatingSidebar?.hide(animated: true)
            return
        case .slideBack:
            // Under the pointer: the Library's own ← slide back to the space, the sidebar staying
            // out (restoreFloatingAfterLibrary keeps it while the pointer is on it).
            CraLog.note("library slides back in the floating sidebar")
            leaveLibrary()
            return
        case .narrow:
            break
        }
        stopLibrarySettle()
        sidebarUI.libraryReveal = nil
        let token = UUID()
        libraryClosing = token
        sidebarUI.libraryHeldWidth = shell.drawerWidth ?? shell.sidebarWidth
        shell.sidebarResizable = true
        shell.sidebarWidth = CGFloat(store.prefs.sidebarWidth)
        CraLog.note("library closes directly")
        shell.animateDrawer(to: nil) { [weak self] in
            guard let self, self.libraryClosing == token else { return }
            self.libraryClosing = nil
            self.sidebarUI.libraryHeldWidth = nil
            self.sidebarUI.libraryCloseCut = true
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { self.sidebarUI.libraryPage = nil }
            if self.libraryFloats { self.restoreFloatingAfterLibrary() }
            self.currentBrowser?.setFocused(true)
        }
    }

    /// A close in flight is called off (the Library opened again, or closed another way).
    private func cancelDirectClose() {
        guard libraryClosing != nil else { return }
        libraryClosing = nil
        sidebarUI.libraryHeldWidth = nil
        shell.sidebarResizable = false
        (shell.sidebarHost as? SidebarView)?.needsLayout = true
    }

    /// A page leaving full screen: the floating sidebar over it goes, so a docked sidebar comes back
    /// in its place and a hidden one stays hidden.
    private func leaveContentFullscreenSidebar() {
        guard let floatingSidebar, floatingSidebar.isShown || shell.sidebarDetached else { return }
        if sidebarUI.libraryPage != nil, libraryFloats { closeLibrary() }
        floatingSidebar.hide(animated: false)
    }

    /// Leaving a Library that opened over the hidden sidebar: the sidebar goes back to floating,
    /// away once the pointer isn't on it, never docked.
    /// The pointer off it, the sidebar stays out until the pointer moves on away, comes onto it or clicks
    /// outside (FloatingSidebarReturnHold, 12 Nov 2026): it used to go the moment the slide back landed.
    private func restoreFloatingAfterLibrary() {
        libraryFloats = false
        guard let floatingSidebar, floatingSidebar.isShown, let window else { return }
        if !pointerOnFloatingSidebar(width: shell.sidebarWidth) {
            // Measured from the real pointer, which the sidebar's own samples follow.
            floatingSidebar.holdAfterReturn(pointer: shell.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
        }
        CraLog.note("floating sidebar stays after the Library (\(floatingSidebar.returnHold.map { "held, pointer \(Int($0.startDistance)) pt off it" } ?? "pointer on it"))")
    }

    /// cra://debug?pointerOnSidebar=1|0: the floating sidebar's pointer test answered so (a scenario
    /// can't move the pointer); nil asks the pointer.
    var debugPointerOnSidebar: Bool?

    /// The pointer is on the floating sidebar, `width` wide.
    private func pointerOnFloatingSidebar(width: CGFloat) -> Bool {
        if let forced = debugPointerOnSidebar { return forced }
        guard let window else { return false }
        let p = shell.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return p.x >= shell.bounds.minX && p.x <= shell.bounds.minX + FloatingSidebarGeometry.margin + width && shell.bounds.contains(p)
    }

    /// The floating sidebar went away with the Library in it (the pointer left it after a visit):
    /// the Library goes too, out of sight, so the next reveal shows the space's tabs where the user
    /// was. Before, the panel went with the Library still open and every reveal came back to it.
    private func floatingSidebarDidHide() {
        guard sidebarUI.libraryPage != nil, floatingSidebar?.sidebarHidden() == true else { return }
        closeLibrary(instantly: true)
        CraLog.note("library closed with the floating sidebar")
    }

    /// Arc's floating sidebar lives in its own panel above the page windows (see FloatingSidebarController).
    private(set) var floatingSidebar: FloatingSidebarController?
    /// A Library bookmark drag arms the page card's drop (PageDropView).
    private var bookmarkDragObservers: [NSObjectProtocol] = []

    private func setFloatingSidebar(_ show: Bool) {
        guard let floatingSidebar else { return }
        if show { if !sidebarVisible { floatingSidebar.edgeHovered() } } else { floatingSidebar.hide(animated: true) }
    }

    private func installFloatingSidebar() {
        guard let window, floatingSidebar == nil else { return }
        let f = FloatingSidebarController(shell: shell, window: window, palette: { [weak self] in
            self?.focusedSpace.theme.palette ?? SpaceTheme.presets[0].palette
        })
        // A page in full screen (a video) hides the sidebar whatever it is set to: it floats over the page.
        // A page in full screen (a video) hides the sidebar until ⌘S docks it beside the page: the
        // floating one comes out over the page from the screen's edge meanwhile.
        f.sidebarHidden = { [weak self] in self.map { $0.shell.contentFullscreen ? !$0.shell.fullscreenSidebar : !$0.sidebarVisible } ?? false }
        // The folder preview, the theme picker, the bookmark card and the media preview belong to
        // the floating sidebar while they are open. The Library holds it out until the pointer has
        // been on it; after that leaving takes the sidebar away, and the Library with it.
        f.staysShown = { [weak self] in
            FolderPreviewController.shared.isOpen || MediaPreviewController.shared.isShown
                || self?.window?.childWindows?.contains { $0 is StyleEditorPanel && $0.isVisible } == true
                // A popover hung from the sidebar reaches past it: the pointer going into it isn't leaving.
                || self?.siteControlCenter.isShown == true || BookmarkEditPopover.isOpen(in: self?.window)
                // Create a Space, and its theme picker beside it.
                || self?.sidebarUI.creatingSpace != nil
                // The address field's dropdown lies over the field: typing in it isn't leaving.
                || self?.commandBarOverFloatingSidebar == true || self?.libraryClosingForAddress == true
                // A scenario standing in for the pointer on the sidebar (cra://debug?pointerOnSidebar=1).
                || self?.debugPointerOnSidebar == true
        }
        // Going, it takes its popovers with it at once: they were left hanging over nothing.
        f.willHide = { [weak self] in
            self?.dismissPopovers("the floating sidebar hides")
            // An open downloads list slides away with it as it is, then closes out of sight.
            self?.sidebarUI.downloadsRideAway(for: FloatingSidebarController.Metrics.hideDuration + 0.3)
        }
        f.holdsUntilVisited = { [weak self] in self?.sidebarUI.libraryPage != nil }
        f.didHide = { [weak self] in
            self?.sidebarUI.downloadsRodeAway()
            self?.floatingSidebarDidHide()
        }
        shell.onDrawerWidthChange = { [weak f] in f?.reposition() }
        f.didAttachPanel = { [weak self] in
            // Keep the find bar above the floating sidebar.
            self?.raiseOverlayPanels()
        }
        f.install()
        floatingSidebar = f
    }

    /// Pages and DevTools are separate Chromium child windows, and Chromium drops a
    /// click on a window that isn't key. In Chrome they share one window, so moving
    /// between the page and DevTools never costs a click: make the target key first.
    /// Only while focus is already inside this window; a click into an inactive Cra
    /// still just activates it, like Chrome.
    private func installChildClickMonitor() {
        childClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, let window = self.window, let target = event.window, target.parent === window,
                  target !== self.overlayPanel, !target.isKeyWindow, target.canBecomeKey, NSApp.isActive,
                  let key = NSApp.keyWindow, key === window || key.parent === window else { return event }
            target.makeKey()
            return event
        }
        // A mouse's back and forward buttons over the sidebar switch spaces, like Arc's
        // SidebarView (issue #233); over a page they stay Chromium's history back and forward.
        // Middle-click on a sidebar tab closes it, like Arc and Chrome. Anywhere else, a page
        // included, the click goes on to whatever is under it. The row is found under the click
        // itself: a remembered hover outlived its row when the tab joined a split, and a middle
        // click inside a split pane closed that tab (GitHub #208).
        middleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
            guard let self else { return event }
            if self.mouseButtonSwitchesSpace(event.buttonNumber, event) { return nil }
            guard event.buttonNumber == 2, let window = self.window, let target = event.window,
                  target === window || target.parent === window,
                  let id = SpaceListView.tabID(under: event) else { return event }
            self.middleClickClose(id)
            return nil
        }
    }

    /// What the row's hover button does: close every picked tab when this is one of them;
    /// the open pinned tab unloads and stays pinned, another pinned tab is archived.
    /// Unload Tab, in whichever window has the tab's page.
    func unloadTab(_ id: UUID) {
        for w in app.mainWindows where w.browsers.runtimes[id] != nil { w.browsers.unloadTab(id) }
    }

    private func middleClickClose(_ id: UUID) {
        // Settings ▸ Tabs: a middle click unloads the tab's page instead (a tab on screen keeps it).
        if store.settings.middleClickUnloadsTab {
            for t in sidebarUI.group(for: id, in: store) where sidebarUI.canUnload(t) { unloadTab(t) }
            return
        }
        let group = sidebarUI.group(for: id, in: store)
        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
            if group.count == 1, store.isPinned(id), selectedTabID != id {
                store.archiveTab(id, reason: .manual)
            } else {
                let open = selectedTabID
                for t in group.filter({ $0 != open }) + group.filter({ $0 == open }) { closeTab(t) }
                sidebarUI.multiSelection.subtract(group)
            }
        }
    }

    /// Two-finger swipes over the sidebar page between spaces the way Dia does
    /// (ARCUI.PageSwipeController): the sidebar strip and the window tint follow the
    /// fingers 1:1, rubber-band past the first and last space, tick a haptic detent at
    /// each page, and on release a zero-bounce spring carries the release speed onto a
    /// page. A gesture locks to one axis early, so vertical list scrolling is untouched.
    private func installSwipeMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            // Any new gesture ends the last space swipe. Pages are child windows (and every
            // main window has this monitor), so a scroll that starts there never reaches the
            // phase switch below; a stale .horizontal would eat the page's momentum and
            // scrolling would stop dead the moment the fingers lift.
            if event.phase == .began || event.phase == .mayBegin {
                // A swipe whose end never came (a view took the gesture's last events) is let go
                // now, so the sidebar isn't left between two pages.
                if self.swipeTracking { self.endSpaceSwipe() }
                self.swipeAxis = .vertical
            }
            // A mouse wheel only ever scrolls.
            if !event.hasPreciseScrollingDeltas { self.showListKnobs() }
            // The momentum tail of a space swipe belongs to the swipe, not the tab list.
            if !event.momentumPhase.isEmpty { return self.swipeAxis == .horizontal ? nil : event }
            // A wheel turned sideways, or with Shift (which macOS turns sideways), pages
            // between spaces over the sidebar like Arc (issue #93).
            if !event.hasPreciseScrollingDeltas, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                return self.wheelSwitchesSpace(event) ? nil : event
            }
            // The floating sidebar is in its own panel (FloatingSidebarController): its swipes
            // come from that window.
            let host = self.shell.sidebarHost
            guard event.window === self.window || (event.window != nil && event.window === host.window),
                  event.hasPreciseScrollingDeltas else { return event }
            switch event.phase {
            case .mayBegin, .began:
                // Create a Space open: no swipe pages the spaces under it (CreateSpaceSlide).
                let inSidebar = (self.shell.sidebarVisible || self.shell.floatingSidebar) && event.window === host.window
                    && host.bounds.contains(host.convert(event.locationInWindow, from: nil)) && self.spaceGesturesAllowed
                // In the Library a swipe can only take it back out; on the Spaces page the cards
                // scroll first, and only a swipe that starts with them at their end leaves (Arc).
                var overSidebar = inSidebar
                if inSidebar, let page = self.sidebarUI.libraryPage {
                    overSidebar = page != .spaces || self.spacesStripAtEnd(event)
                }
                self.swipeAxis = overSidebar ? .undecided : .vertical
                if overSidebar { self.hideListKnobs() }
                self.swipeX = 0
                self.swipeY = 0
                return event
            case .changed:
                switch self.swipeAxis {
                case .vertical:
                    return event
                case .undecided:
                    self.swipeX += event.scrollingDeltaX
                    self.swipeY += event.scrollingDeltaY
                    guard max(abs(self.swipeX), abs(self.swipeY)) > 6 else { return event }
                    // One space still swipes into the Library.
                    guard abs(self.swipeX) > abs(self.swipeY) * 1.2, !self.isStandalone,
                          self.store.spaceOrder.count > 1 || !self.shell.floatingSidebar,
                          // At the Spaces page's end a swipe back along the cards scrolls them.
                          !(self.sidebarUI.libraryPage == .spaces && self.swipeX > 0) else {
                        self.swipeAxis = .vertical
                        self.showListKnobs()
                        return event
                    }
                    self.swipeAxis = .horizontal
                    HitchMonitor.mark("swipe-begin")
                    self.beginSpaceSwipe()
                    self.trackSpaceSwipe(by: self.swipeX, at: event.timestamp)
                    return nil
                case .horizontal:
                    self.trackSpaceSwipe(by: event.scrollingDeltaX, at: event.timestamp)
                    return nil
                }
            case .ended, .cancelled:
                if self.swipeAxis != .vertical { self.showListKnobs(after: 1) }
                guard self.swipeAxis == .horizontal else { return event }
                self.endSpaceSwipe()
                return nil
            default:
                return event
            }
        }
    }

    private func hideListKnobs() {
        swipeKnobReveal?.cancel()
        swipeKnobReveal = nil
        SidebarScroller.hiddenForSwipe = true
    }

    /// After `delay` seconds: by then the knob AppKit flashed at the touch has faded out.
    private func showListKnobs(after delay: TimeInterval = 0) {
        swipeKnobReveal?.cancel()
        guard delay > 0 else { SidebarScroller.hiddenForSwipe = false; return }
        let work = DispatchWorkItem { SidebarScroller.hiddenForSwipe = false }
        swipeKnobReveal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func beginSpaceSwipe() {
        swipeTracking = true
        swipeTravel = 0
        swipeSamples = []
        swipeHaptics = PageDetentHaptics()
        let at = store.spaceOrder.firstIndex(of: focusedSpaceID) ?? 0
        swipeCommit = SpaceSwipeCommit(pages: -at...max(-at, store.spaceOrder.count - 1 - at))
        sidebarUI.spaceSettleVelocity = 0
        // A swipe during a Library settle picks it up where it shows.
        librarySwipeToward = librarySettleSpring?.target
        stopLibrarySettle()
        let shown = sidebarUI.libraryReveal
        librarySwipeFrom = nil
        // The floating sidebar swipes into and out of the Library too; the sidebar stays hidden.
        guard shell.sidebarVisible || floatingSidebar?.isShown == true || sidebarUI.libraryPage != nil else { return }
        if let page = sidebarUI.libraryPage {
            prepareLibraryReveal(page)
            librarySwipeFrom = shown ?? 1
        } else if shown != nil || store.spaceOrder.first == focusedSpaceID {
            // The Library button slides it in from any space.
            prepareLibraryReveal(sidebarUI.lastLibraryPage)
            librarySwipeFrom = shown ?? 0
        }
        // The Library is the page before the first space; a swipe picked up in a settle starts
        // from the page it was nearer.
        swipeHaptics = PageDetentHaptics(page: -Int((librarySwipeFrom ?? 0).rounded()))
    }

    private func performSwipeHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    /// The fingers' speed over the last 80 ms, in pages a second (+ toward the next space).
    private func swipeVelocity(width: CGFloat) -> CGFloat {
        let span = (swipeSamples.last?.time ?? 0) - (swipeSamples.first?.time ?? 0)
        let moved = swipeSamples.reduce(0) { $0 + $1.dx }
        // A lone sample carries no timing: a slow lift.
        return span > 0.004 ? -moved / CGFloat(span) / width : 0
    }

    // MARK: Swiping into the Library (LibrarySwipe)

    private func prepareLibraryReveal(_ page: LibraryPage) {
        sidebarUI.libraryRevealPage = page
        sidebarUI.libraryRevealWidth = libraryWidth(page)
        sidebarUI.libraryRevealBase = CGFloat(store.prefs.sidebarWidth)
    }

    /// Shows reveal `r`, and like Arc the sidebar widens with it, from its own width to the
    /// Library's, so the Library lands at its width with nothing left to resize.
    private func setLibraryReveal(_ r: CGFloat) {
        sidebarUI.libraryReveal = r
        // The drawer widens over the page, which keeps its size (ShellView.drawerWidth).
        let width = LibrarySwipe.sidebarWidth(reveal: r, base: sidebarUI.libraryRevealBase, library: sidebarUI.libraryRevealWidth)
        shell.drawerWidth = width > shell.sidebarWidth + 0.5 ? width : nil
    }

    /// Past the first space the fingers pull the Library in like the page before it; in the
    /// Library they push it back out. Returns false when the swipe is one between spaces.
    private func trackLibrarySwipe() -> Bool {
        guard let from = librarySwipeFrom else { return false }
        let width = sidebarUI.libraryRevealWidth
        guard let r = LibrarySwipe.reveal(from: from, travel: swipeTravel, width: width, toward: librarySwipeToward) else {
            // Back on the space and beyond: the swipe heads for the next space instead. One that
            // caught the Library sliding out lets it land first and pages with what's left.
            if from != 0 {
                swipeTravel = LibrarySwipe.travelPastSpace(from: from, travel: swipeTravel, width: width)
                librarySwipeFrom = 0
                librarySwipeToward = nil
                finishLibrarySwipe(at: 0)
            } else if sidebarUI.libraryReveal != nil {
                setLibraryReveal(0)
                sidebarUI.libraryReveal = nil
                shell.thawPages()
            }
            return false
        }
        if sidebarUI.spaceSwipe != 0 { sidebarUI.spaceSwipe = 0 }
        setLibraryReveal(r)
        if swipeHaptics.track(position: -r, pages: -1...0) { performSwipeHaptic() }
        return true
    }

    /// The release settles on the space swipe's spring, frame by frame on the display link.
    private func endLibrarySwipe(_ r: CGFloat) {
        librarySwipeFrom = nil
        let width = sidebarUI.libraryRevealWidth
        let velocity = LibrarySwipe.velocity(samples: swipeSamples, width: width)
        let target = LibrarySwipe.target(reveal: r, velocity: velocity)
        if swipeHaptics.land(on: -Int(target.rounded())) { performSwipeHaptic() }
        settleLibrary(from: r, velocity: velocity, to: target)
    }

    /// The Library button: the same spring from rest, or turned around from where a settle is.
    private func slideLibrary(to target: CGFloat) {
        if let s = librarySettleSpring {
            let t = CGFloat(CACurrentMediaTime() - s.start)
            let r = LibrarySwipe.settle(from: s.from, velocity: s.velocity, to: s.target, at: t)
            settleLibrary(from: r, velocity: LibrarySwipe.settleVelocity(from: s.from, velocity: s.velocity, to: s.target, at: t), to: target)
            return
        }
        let from: CGFloat = sidebarUI.libraryPage == nil ? 0 : 1
        guard from != target else { return }
        prepareLibraryReveal(sidebarUI.libraryPage ?? sidebarUI.lastLibraryPage)
        setLibraryReveal(from)
        settleLibrary(from: from, velocity: 0, to: target)
    }

    private func settleLibrary(from r: CGFloat, velocity: CGFloat, to target: CGFloat) {
        librarySettleSpring = (start: CACurrentMediaTime(), from: r, velocity: velocity, target: target)
        if librarySettleLink == nil {
            let link = shell.displayLink(target: self, selector: #selector(stepLibrarySettle))
            link.add(to: .main, forMode: .common)
            librarySettleLink = link
        }
    }

    @objc private func stepLibrarySettle(_ link: CADisplayLink) {
        guard let s = librarySettleSpring else { return stopLibrarySettle() }
        let t = CGFloat(link.targetTimestamp - s.start)
        if LibrarySwipe.isSettled(from: s.from, velocity: s.velocity, to: s.target, at: t, width: sidebarUI.libraryRevealWidth) {
            stopLibrarySettle()
            finishLibrarySwipe(at: s.target)
        } else {
            setLibraryReveal(LibrarySwipe.settle(from: s.from, velocity: s.velocity, to: s.target, at: t))
        }
    }

    private func stopLibrarySettle() {
        librarySettleSpring = nil
        librarySettleLink?.invalidate()
        librarySettleLink = nil
    }

    /// Landed: the window is in the Library or on the space, at the width the swipe ends on.
    private func finishLibrarySwipe(at target: CGFloat) {
        var instant = Transaction()
        instant.disablesAnimations = true
        let width: CGFloat
        if target >= 1 {
            let page = sidebarUI.libraryPage ?? sidebarUI.libraryRevealPage
            if sidebarUI.libraryPage == nil {
                sidebarUI.lastLibraryPage = page
                libraryFloats = !shell.sidebarVisible
                sidebarUI.downloadsListOpen = false
                commandBar.close()
                shell.sidebarResizable = false
                withTransaction(instant) { sidebarUI.libraryPage = page }
                window?.makeKey()
            }
            width = libraryWidth(page)
        } else {
            var left = false
            if sidebarUI.libraryPage != nil {
                withTransaction(instant) { sidebarUI.libraryPage = nil }
                shell.sidebarResizable = true
                // ⌘L's bar has the keys: the page doesn't take them back.
                if !libraryClosingForAddress { currentBrowser?.setFocused(true) }
                left = true
            }
            width = CGFloat(store.prefs.sidebarWidth)
            // Left for the address (⌘L), the floating sidebar stays out for its dropdown.
            if left, libraryFloats, !libraryClosingForAddress { restoreFloatingAfterLibrary() } else if sidebarUI.libraryPage == nil { libraryFloats = false }
        }
        sidebarUI.libraryReveal = nil
        shell.sidebarWidth = CGFloat(store.prefs.sidebarWidth)
        shell.drawerWidth = target >= 1 ? width : nil
        if target < 1, let done = libraryLeft { DispatchQueue.main.async { done() } }
    }

    /// The Spaces page's cards under the pointer are scrolled to their end (or there are none).
    private func spacesStripAtEnd(_ event: NSEvent) -> Bool {
        // Arc ignores a swipe over the Library's rail.
        guard let strip = spacesStrip(at: event) else { return false }
        let clip = strip.contentView
        return clip.bounds.minX >= (strip.documentView?.frame.width ?? 0) - clip.bounds.width - 1
    }

    /// Whether the Spaces page's cards under the pointer can still scroll the way a wheel of `dx`
    /// moves them (a negative `dx` toward the last card, as the scroll view applies it).
    private func spacesStripCanScroll(_ event: NSEvent, dx: CGFloat) -> Bool {
        guard let strip = spacesStrip(at: event) else { return false }
        return dx < 0 ? !spacesStripAtEnd(event) : strip.contentView.bounds.minX > 1
    }

    /// The Spaces page's row of cards under the pointer.
    private func spacesStrip(at event: NSEvent) -> NSScrollView? {
        guard let root = shell.sidebarHost.window?.contentView?.superview else { return nil }
        var v = root.hitTest(event.locationInWindow)
        while let view = v, !(view is NSScrollView && (view as? NSScrollView)?.hasHorizontalScroller == true) { v = view.superview }
        return v as? NSScrollView
    }

    /// A mouse's back or forward button released over the sidebar: the previous or next space,
    /// wrapping as Spaces ▸ Previous/Next Space do (Arc's SidebarView, issue #233). Returns false
    /// for any other button, or one released anywhere else.
    func mouseButtonSwitchesSpace(_ button: Int, _ event: NSEvent) -> Bool {
        guard let offset = MouseButtonSpaceSwitch.offset(buttonNumber: button), isOverSidebar(event),
              spaceGesturesAllowed else { return false }
        store.focusSpace(offset: offset, window: windowID)
        return true
    }

    /// Whether `event` is over this window's sidebar, docked or floating, in a window that has
    /// spaces to switch (not a Little Window).
    private func isOverSidebar(_ event: NSEvent) -> Bool {
        let host = shell.sidebarHost
        return (shell.sidebarVisible || shell.floatingSidebar) && event.window != nil && event.window === host.window
            && host.bounds.contains(host.convert(event.locationInWindow, from: nil)) && !isStandalone
    }

    /// Whether the pointer, not the key event's window, is over this window's sidebar. A key
    /// goes to the focused page, so ⌥← from a mouse button has to be hit-tested here (issue #233).
    func pointerOverSidebar() -> Bool {
        let host = shell.sidebarHost
        guard (shell.sidebarVisible || shell.floatingSidebar), !isStandalone, let window = host.window else { return false }
        let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        guard host.bounds.contains(host.convert(point, from: nil)) else { return false }
        return NSWindow.windowNumber(at: NSEvent.mouseLocation, belowWindowWithWindowNumber: 0) == window.windowNumber
    }

    /// Shift + wheel, or a sideways wheel, over the sidebar: past a flick the next or previous
    /// space comes in on the space change's spring, and before the first space the Library
    /// slides in, as a swipe would bring it (Arc 1.171, WheelSpaceSwitch). Returns false for a
    /// wheel the sidebar doesn't take.
    private func wheelSwitchesSpace(_ event: NSEvent) -> Bool {
        guard isOverSidebar(event), spaceGesturesAllowed else { return false }
        let dx = event.scrollingDeltaX
        // On the Spaces page the cards scroll first; once they can't scroll that way the wheel pages,
        // which leaves the Library when it heads for the next space, and over the rail it leaves at
        // once (Arc).
        if sidebarUI.libraryPage == .spaces, spacesStripCanScroll(event, dx: dx) { return false }
        let step = wheelSpaceSwitch.step(dx: dx, inverted: event.isDirectionInvertedFromDevice, at: event.timestamp)
        guard step != 0 else { return true }
        let order = store.spaceOrder
        // Where the Library is headed, if it is sliding.
        let inLibrary = librarySettleSpring.map { $0.target >= 1 } ?? (sidebarUI.libraryPage != nil)
        switch WheelSpaceSwitch.target(step: step, index: order.firstIndex(of: focusedSpaceID) ?? 0, count: order.count,
                                       inLibrary: inLibrary, libraryAllowed: !shell.floatingSidebar && shell.sidebarVisible) {
        case .space(let i): store.focusSpace(order[i], window: windowID)
        case .openLibrary, .closeLibrary: toggleLibrary()
        case nil: break
        }
        return true
    }

    /// Swipes, a sideways wheel and a mouse's back and forward buttons may switch spaces: not while
    /// Create a Space is open (CreateSpaceSlide), which only Cancel or Create Space closes.
    private var spaceGesturesAllowed: Bool {
        CreateSpaceSlide.allowsSpaceGesture(creatingSpace: sidebarUI.creatingSpace != nil)
    }

    /// A space swipe of `steps` trackpad samples `dx` apart, 8 ms apart (cra://debug?swipe=).
    func debugSpaceSwipe(dx: CGFloat, steps: Int) {
        guard spaceGesturesAllowed else { CraLog.note("space swipe ignored: Create a Space is open"); return }
        beginSpaceSwipe()
        for i in 1...max(1, steps) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.008 * Double(i)) { [weak self] in
                self?.trackSpaceSwipe(by: dx, at: ProcessInfo.processInfo.systemUptime)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.008 * Double(steps + 1)) { [weak self] in self?.endSpaceSwipe() }
    }

    private func trackSpaceSwipe(by dx: CGFloat, at time: TimeInterval) {
        let width = max(1, shell.sidebarWidth)
        swipeTravel += dx
        swipeSamples.append((time, dx))
        swipeSamples.removeAll { time - $0.time > 0.08 }
        if trackLibrarySwipe() { return }
        let index = CGFloat(store.spaceOrder.firstIndex(of: focusedSpaceID) ?? 0)
        let first = -index, last = CGFloat(store.spaceOrder.count - 1) - index
        // Content follows the fingers (natural scrolling: fingers left = next space).
        var pages = max(-1, min(1, -swipeTravel / width))
        // Rubber band past either end, with the resistance curve AppKit scroll views use.
        func band(_ x: CGFloat) -> CGFloat { 1 - 1 / (x * 0.55 + 1) }
        if pages < first { pages = first - band(first - pages) * 0.5 }
        if pages > last { pages = last + band(pages - last) * 0.5 }
        sidebarUI.spaceSwipe = pages
        // On past the last space: the ring that opens Create a Space fills, a tick each quarter.
        if !isStandalone, sidebarUI.libraryPage == nil {
            let fill = SpaceCreateSwipe.fill(overscroll: Double(-swipeTravel / width - last))
            createSwipeFill = fill > 0 ? fill : nil
            (shell.sidebarHost as? SidebarView)?.showCreateSwipe(createSwipeFill)
            if createSwipeTicks.update(fill: fill) {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        // One tap each time the space the swipe would land on changes, with the fingers still
        // down: half way, or as soon as a flick commits (SpaceSwipeCommit).
        if swipeCommit.update(position: pages, velocity: swipeVelocity(width: width)) { performSwipeHaptic() }
    }

    private func endSpaceSwipe() {
        HitchMonitor.mark("swipe-lift")
        swipeTracking = false
        // Let go with the ring full: Create a Space, the new space going at the end.
        if let fill = createSwipeFill {
            createSwipeFill = nil
            createSwipeTicks.reset()
            (shell.sidebarHost as? SidebarView)?.showCreateSwipe(nil)
            if SpaceCreateSwipe.commits(fill: fill) {
                CraLog.note("swipe past the last space opens Create a Space")
                DispatchQueue.main.async { [weak self] in self?.showCreateSpace() }
            }
        }
        if let r = sidebarUI.libraryReveal, librarySwipeFrom != nil { return endLibrarySwipe(r) }
        librarySwipeFrom = nil
        let width = max(1, shell.sidebarWidth)
        let pages = sidebarUI.spaceSwipe
        let velocity = swipeVelocity(width: width)
        // Lands where the swipe committed while the fingers moved (one tap each change, already
        // given); the release's own sample can still change it, and taps then (#260).
        if swipeCommit.update(position: pages, velocity: velocity) { performSwipeHaptic() }
        let index = store.spaceOrder.firstIndex(of: focusedSpaceID) ?? 0
        var step = swipeCommit.step
        if !(0..<store.spaceOrder.count).contains(index + step) { step = 0 }
        let remaining = CGFloat(step) - pages
        sidebarUI.spaceSettleVelocity = abs(remaining) > 0.001 ? Double(max(-4, min(12, velocity / remaining))) : 0
        // The new space becomes the strip's page at once and the swipe returns to rest; the space
        // pager and the window tint spring from where they show to the page in Core Animation
        // (SpacePagerView, PagedGradientView), so a busy main thread doesn't stop the settle.
        if step != 0 {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                // The space first: the strip and the tint read what's left of the swipe
                // against the space shown.
                store.focusSpace(store.spaceOrder[index + step], window: windowID)
                sidebarUI.spaceSwipe = pages - CGFloat(step)
            }
        }
        sidebarUI.spaceSwipe = 0
        // Clicks and shortcuts that switch spaces later start from rest.
        DispatchQueue.main.async { [weak self] in self?.sidebarUI.spaceSettleVelocity = 0 }
    }

    // MARK: Extensions

    private let siteControlCenter = SiteControlCenterPopover()
    /// The swipe past the last space: the ring's fill, and its quarter ticks.
    private var createSwipeFill: Double?
    private var createSwipeTicks = SpaceCreateSwipe()
    let translatePopover = TranslatePopover()

    /// Arc's translate popover (#310) under the button that was pressed (screen rect): the
    /// toolbar's, or the sidebar URL field's "Translation Available". The languages for its menu
    /// come with the first one opened on the page.
    func showTranslate(_ id: UUID, from anchor: NSRect?) {
        guard let window, let content = window.contentView, let rt = browsers.runtime(for: id), let state = rt.translation,
              let anchor = anchor ?? (shell.sidebarHost as? SidebarView)?.translateFrameOnScreen else { return }
        let rect = content.convert(window.convertFromScreen(anchor), from: nil)
        var actions = TranslateActions()
        actions.translate = { [weak self] target in self?.browsers.translatePage(id, to: target) }
        actions.showOriginal = { [weak self] in self?.browsers.revertTranslation(id) }
        actions.neverTranslateSite = { [weak self] in self?.browsers.neverTranslateSite(id) }
        actions.languageSettings = { [weak self] in self?.app.perform("languageSettings") }
        let show = { [weak self] in
            guard let self, let state = self.browsers.runtime(for: id)?.translation else { return }
            self.translatePopover.toggle(relativeTo: rect, of: content, state: state, actions: actions)
        }
        if state.languages.isEmpty { browsers.refreshTranslation(id, then: show) } else { show() }
    }
    /// The blocked pop-ups popover (#357) under the button that was pressed (screen rect): the
    /// toolbar's, or the sidebar URL field's "Pop-ups Blocked". Upstream showed a menu; here it is a
    /// popover in the space's colours (BlockedPopupsPopover), with the same rows.
    func showBlockedPopups(_ id: UUID, from anchor: NSRect?) {
        guard let window, let content = window.contentView,
              let anchor = anchor ?? (shell.sidebarHost as? SidebarView)?.blockedPopupsFrameOnScreen else { return }
        let rect = content.convert(window.convertFromScreen(anchor), from: nil)
        var actions = BlockedPopupsActions()
        actions.open = { [weak self] popup in self?.browsers.openBlockedPopups(id, popup: popup) }
        actions.setAllowed = { [weak self] on in self?.browsers.setPopupsAllowed(id, on) }
        blockedPopupsPopover.toggle(relativeTo: rect, of: content, rows: blockedPopupsRows(id), actions: actions)
    }

    let blockedPopupsPopover = BlockedPopupsPopover()

    /// Chrome's blocked pop-ups bubble, row by row (CraCore BlockedPopups.rows): the pop-ups (each
    /// opens as a tab below the page), Open All, and the site's Always Allow switch.
    func blockedPopupsRows(_ id: UUID) -> [BlockedPopups.Row] {
        BlockedPopups.rows(browsers.blockedPopups(id), pageURL: browsers.runtime(for: id)?.browser.currentURL ?? "",
                           allowed: browsers.popupsAllowed(id))
    }

    /// The space the Site Control Center was opened in.
    private var siteControlCenterSpaceID: UUID?
    /// The space the window last showed, for closing popovers when another comes up.
    private var popoverSpaceID: UUID?

    /// Screen y of the focused card's toolbar bottom (its top edge when the toolbar is hidden),
    /// and the card's right edge.
    fileprivate func toolbarBottomOnScreen() -> (y: CGFloat, cardMaxX: CGFloat)? {
        guard let window else { return nil }
        let card = shell.focusedCard.map { shell.contentContainer.convert($0.frame, to: nil) }
            ?? shell.convert(shell.contentContainer.frame, to: nil)
        let onScreen = window.convertToScreen(card)
        let bar = shell.focusedCard?.toolbarHeight ?? CraMetrics.toolbarHeight
        return (onScreen.maxY - (shell.panesShowBars ? bar : 0), onScreen.maxX)
    }

    /// Where a popup from a URL-bar button hangs: under the toolbar, or, with the toolbar
    /// hidden, under the sidebar's URL pill (also while the sidebar floats in its panel).
    private func urlBarBottomOnScreen() -> CGFloat? {
        guard !store.settings.showToolbar else { return toolbarBottomOnScreen()?.y }
        let host = shell.sidebarHost
        guard let w = host.window else { return nil }
        let rect = w.convertToScreen(host.convert(host.bounds, to: nil))
        // SidebarTopBar: title area, 2 pt, then the 36 pt pill.
        return rect.maxY - CraMetrics.titleAreaHeight - 2 - 36
    }

    /// Whether a button (screen rect) sits in a bar above a page rather than in the sidebar.
    private func isInPaneBar(_ button: NSRect) -> Bool {
        guard shell.panesShowBars, let window else { return false }
        let mid = NSPoint(x: button.midX, y: button.midY)
        return shell.paneCards.contains { card in
            window.convertToScreen(card.toolbarHost.convert(card.toolbarHost.bounds, to: nil)).contains(mid)
        }
    }

    /// Under the extension's pinned toolbar button when the toolbar shows one, else under the
    /// toolbar at the card's right end.
    fileprivate func extensionPopupAnchor(_ id: String) -> NSPoint? {
        guard let bar = toolbarBottomOnScreen() else { return nil }
        if shell.panesShowBars, let button = (shell.focusedCard?.toolbarHost as? PaneToolbarView)?.extensionButtonFrameOnScreen(id) {
            return NSPoint(x: button.maxX, y: bar.y)
        }
        return NSPoint(x: bar.cardMaxX - 8, y: bar.y)
    }

    /// Runs an extension's toolbar action on the focused page, like Arc's toolbar buttons and
    /// Dia's Extensions menu. The popup hangs under the toolbar, its right edge at `buttonRightX`
    /// (screen x of the clicked button; nil = the extension's toolbar button or the card's right end),
    /// its top at `buttonBottomY` (nil = under the URL bar).
    func runExtensionAction(_ id: String, buttonRightX: CGFloat? = nil, buttonBottomY: CGFloat? = nil) {
        let bar = toolbarBottomOnScreen()
        let browser = currentBrowser
        let anchor = bar.map { bar in
            // Under the URL bar, or under a grid pin lower down.
            buttonRightX.map { x in NSPoint(x: x, y: buttonBottomY ?? urlBarBottomOnScreen() ?? bar.y) } ?? extensionPopupAnchor(id) ?? NSPoint(x: bar.cardMaxX - 8, y: bar.y)
        }
        let available = profileExtensions
        switch ExtensionLaunch.decide(id, available: available, hasPage: bar != nil && browser != nil) {
        case .nothing: return
        case .runAction:
            guard let browser, let anchor else { return }
            let inDefaultProfile = profileDirectoryName == "Default"
            Task {
                if await !ExtensionActions.shared.run(id, on: browser, anchor: anchor, inDefaultProfile: inDefaultProfile),
                   let e = available.first(where: { $0.id == id }) {
                    self.perform(ExtensionLaunch.fallback(e), anchor: anchor)
                }
            }
        case let fallback: perform(fallback, anchor: anchor)
        }
    }

    /// The extensions installed in the focused page's profile, turned on or not.
    private var profileExtensions: [ExtensionLaunch.Extension] {
        let profile = profileDirectoryName
        return ExtensionStore.shared.entries.filter { $0.isInstalled(inProfile: profile) }.map {
            ExtensionLaunch.Extension(id: $0.extensionID, popupPath: $0.popupPath, optionsPath: $0.optionsPath, enabled: $0.isEnabled(inProfile: profile))
        }
    }

    /// The Chromium profile folder the focused page loads in.
    var profileDirectoryName: String { selectedTabID.map(store.profileDirectoryName(item:)) ?? store.profileDirectoryName(space: focusedSpaceID) }

    /// The extensions installed in the focused page's profile.
    var extensionEntries: [ExtensionStore.Entry] { ExtensionStore.shared.entries(inProfile: profileDirectoryName) }

    /// The pinned-extension button under the pointer (screen rect), in the toolbar or the
    /// sidebar's grid (also in the floating sidebar's panel), so a popup hangs from the same
    /// place wherever the button was clicked (GitHub #8).
    private static func extensionButtonUnderPointer() -> NSRect? {
        buttonFrameUnderPointer { $0 is ToolbarGlyphButton }
    }

    /// The button under the pointer (screen rect): the one just clicked.
    private static func buttonFrameUnderPointer(_ isButton: (NSView) -> Bool) -> NSRect? {
        let mouse = NSEvent.mouseLocation
        let number = NSWindow.windowNumber(at: mouse, belowWindowWithWindowNumber: 0)
        guard let w = NSApp.window(withWindowNumber: number), let content = w.contentView else { return nil }
        let p = w.convertPoint(fromScreen: mouse)
        var v = content.hitTest(content.superview?.convert(p, from: nil) ?? p)
        while let view = v, !isButton(view) { v = view.superview }
        return v.map { w.convertToScreen($0.convert($0.bounds, to: nil)) }
    }

    /// No page for Chrome's popup to attach to (no tab open, no DevTools pipe, a page it
    /// cannot reach): ExtensionLaunch picks the popup page in a popup-sized window under the
    /// button, else the options page, else Chrome's details page for the extension.
    private func perform(_ launch: ExtensionLaunch, anchor: NSPoint?) {
        switch launch {
        case .nothing, .runAction: break
        case .popupWindow(let url):
            let fallback = window.map { NSPoint(x: $0.frame.maxX - 16, y: $0.frame.maxY - CraMetrics.toolbarHeight) } ?? .zero
            ExtensionPageWindow.open(url: url, anchor: anchor ?? fallback, app: app)
        case .openTab(let url):
            app.openExtensionPage(url, window: windowID)
        }
    }

    func debugSiteControls() { showToolbarExtensionsMenu() }

    func debugTabSwitcher() {
        let theme = focusedSpace.theme
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        tabSwitcher.isDark = dark
        tabSwitcher.highlight = theme.switcherHighlight(dark: dark)
        tabSwitcher.palette = theme.palette
        tabSwitcher.debugOpen(openRecentTabs(limit: TabSwitcherMetrics.maxItems).compactMap { id in
            guard let it = store.item(id), let tab = it.tab else { return nil }
            return TabSwitcher.Item(id: id, title: it.displayTitle, iconKey: tab.iconKey, snapshot: browsers.runtime(for: id)?.snapshot)
        })
    }

    /// Selects a split pane and brings the shell along at once (refresh otherwise runs on the next
    /// turn), so the focused card, the visible page and the profile are that pane's when the
    /// caller reads them.
    private func focusPaneNow(_ id: UUID) {
        guard selectedTabID != id else { return }
        store.selectTab(id, window: windowID)
        refresh()
    }

    /// Arc's sliders button (toolbar and URL pill): the Site Control Center, hung under the
    /// button that was clicked (buttons are 32 × 28), not wherever the pointer is in it.
    /// The Site Control Center as if its sliders button was clicked, wherever the request came from
    /// (the protected media toast's Why?): under the toolbar's button, else under the sidebar's URL
    /// field at its right end, where that button sits. The arrow shows where to find it next time.
    func showSiteControlsFromTheirButton() {
        if let button = (shell.focusedCard?.toolbarHost as? PaneToolbarView)?.siteControlsButtonFrameOnScreen() {
            return showToolbarExtensionsMenu(from: button, inToolbar: true)
        }
        guard let button = (shell.sidebarHost as? SidebarView)?.siteControlsButtonFrameOnScreen else { return showToolbarExtensionsMenu() }
        showToolbarExtensionsMenu(from: button, inToolbar: false)
    }

    private func showToolbarExtensionsMenu(from anchor: NSRect? = nil, inToolbar: Bool = false) {
        // Decided now, while the click is the current event: the page is asked a question below.
        if siteControlCenter.closesInstead() { return }
        // A split pane's bar has the sliders even with the toolbar hidden: hang under that bar then.
        let pressed = anchor.map { inToolbar ? $0 : nil } ?? Self.buttonFrameUnderPointer { $0 is ToolbarGlyphButton }
        guard let window, let content = window.contentView,
              let y = pressed != nil && shell.panesShowBars ? toolbarBottomOnScreen()?.y : urlBarBottomOnScreen() else { return }
        ExtensionStore.shared.reload()
        let midX = (anchor ?? pressed ?? Self.buttonFrameUnderPointer { $0 is SidebarGlyphButton })?.midX ?? NSEvent.mouseLocation.x
        // Arc's popover overlaps the bar by 4 pt (popover top 71 under a bar ending at 75).
        let onScreen = Self.popoverAnchor(midX: midX, barBottom: y)
        let rect = content.convert(window.convertFromScreen(onScreen), from: nil)
        let url = selectedTabID.flatMap { store.item($0)?.tab?.url } ?? ""
        var actions = SiteControlCenterActions()
        actions.share = { [weak self] anchor in self?.shareCurrentPage(from: anchor) }
        actions.copyURL = { [weak self] in self?.app.perform("copyURL") }
        if url.hasPrefix("http") { actions.boost = { [weak self] in self?.openBoostEditor() } }
        actions.capture = { [weak self] in self?.capturePage() }
        actions.captureFullPage = { [weak self] in self?.captureFullPage() }
        if BookmarkEditPopover.canBookmark(url) {
            actions.bookmarked = BookmarkStore.shared.isBookmarked(url)
            // The popover goes, and the bookmark's card hangs where it was, under its button.
            actions.bookmark = { [weak self] in
                guard let self else { return }
                self.siteControlCenter.close()
                self.bookmarkCurrentPage(anchor: onScreen)
            }
        }
        actions.runExtension = { [weak self] id in self?.runExtensionAction(id) }
        actions.addExtension = { [weak self] in self?.openTab("https://chromewebstore.google.com/category/extensions") }
        actions.manageExtensions = { [weak self] in self?.openTab("chrome://extensions") }
        actions.clearCache = { [weak self] in self?.currentBrowser?.clearSiteDataAndReload(cookies: false) }
        actions.clearCookies = { [weak self] in self?.currentBrowser?.clearSiteDataAndReload(cookies: true) }
        let ssl = currentBrowser?.sslStatus()
        let secure = ConnectionSecurity.isSecure(url: url, status: ssl.map {
            ConnectionSecurity.Status(secureConnection: $0.secureConnection, certStatus: $0.certStatus, contentStatus: $0.contentStatus)
        })
        if ssl?.certificates.isEmpty == false { actions.showCertificate = { [weak self] in self?.showCertificate() } }
        actions.siteSettings = { [weak self] in
            guard let origin = URL(string: url).flatMap({ u in u.host.map { "\(u.scheme ?? "https")://\($0)" } }) else { return }
            self?.openTab("chrome://settings/content/siteDetails?site=" + (origin.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? origin))
        }
        actions.learnAboutProtectedMedia = { [weak self] in self?.openTab(Self.protectedMediaHelp) }
        actions.chooseSafariEngine = { [weak self] on in self?.chooseSafariEngine(on, for: url) }
        siteControlCenterSpaceID = focusedSpaceID
        let show = { [weak self] (safariEngine: Bool?) in
            guard let self, let window = self.window, window.isVisible else { return }
            // Light or dark with the window's space, as Translate and Blocked pop-ups (SpacePopoverTones).
            self.siteControlCenter.show(relativeTo: rect, of: content, url: url, secure: secure, dark: SpacePopoverTones(window: self.window).dark,
                                        profile: self.profileDirectoryName, tab: self.selectedTabID,
                                        protectedMedia: self.browsers.visibleTabID.flatMap { self.sidebarUI.navState(for: $0).protectedMedia },
                                        safariEngine: safariEngine, toggleChecked: true, store: self.store, actions: actions)
        }
        // The Safari's Engine switch: on for a WebKit page; for a Chromium page only once it asked
        // for Widevine (PageScript's `drm`), else no switch. Asked in Cra's world; a page that
        // doesn't answer within 0.3 s opens without it.
        guard let b = currentBrowser, url.hasPrefix("http") else { return show(nil) }
        if b is WebKitBrowser { return show(true) }
        var shown = false
        let once = { (value: Bool?) in if !shown { shown = true; show(value) } }
        b.evaluate(inIsolatedWorld: PageScript.world, params: #"{"expression":"window.__cra?.drm === true","returnByValue":true}"#) { result, _ in
            let drm = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                .flatMap { $0["result"] as? [String: Any] }?["value"] as? Bool == true
            DispatchQueue.main.async { once(drm ? false : nil) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { once(nil) }
    }

    func debugChooseSafariEngine(_ on: Bool) {
        if let url = currentBrowser?.currentURL { chooseSafariEngine(on, for: url) }
    }

    /// The Site Control Center's Safari's Engine switch: the site plays in WebKit (or Chromium)
    /// from now on, and the focused page opens again there. Choosing it is knowing about it: no toast.
    private func chooseSafariEngine(_ on: Bool, for url: String) {
        PageEngines.choose(on ? .webKit : .chromium, for: url)
        if on, let service = PageEngines.sites.serviceName(for: url) { PageEngines.told(service) }
        if let id = browsers.visibleTabID { browsers.reopenInItsEngine(id) }
    }

    /// The help centre's page on why Spotify, Netflix and the others play in Safari's engine.
    static let protectedMediaHelp = SiteLinks.tagged("\(Brand.site)/help/protected-media", from: .protectedMedia)

    func debugSiteControlsShown() -> Bool { siteControlCenter.isShown
    }

    /// Scenario hooks (#226): the sidebar's URL field hovered, its buttons logged as
    /// "url field: copyURL extensions" ("url field: none" while the toolbar has the address).
    func debugURLFieldHover(_ on: Bool) {
        let items = (shell.sidebarHost as? SidebarView)?.debugURLFieldHover(on)
        CraLog.note("url field: " + (items.map { $0.map(Self.debugName).joined(separator: " ") } ?? "none"))
    }

    /// A press on the URL field's button by name ("siteControls", "copyURL"), then whether the
    /// Site Control Center is open once it had time to (it waits up to 0.3 s on the page).
    /// `cra://debug?urlFieldClick=1`: the bar as a click on the address field opens it.
    func debugURLFieldClick() {
        let field = (shell.sidebarHost as? SidebarView)?.urlFieldFrameOnScreen
            ?? shell.paneCards.lazy.compactMap { ($0.toolbarHost as? PaneToolbarView)?.urlFieldFrameOnScreen() }.first
        guard let field else { CraLog.note("url field click: no field"); return }
        openCommandBar(.editURL, urlField: field)
    }

    /// `cra://debug?commandBarState=<label>`: the bar's shape and where it is, beside the address field.
    func debugCommandBarState(_ label: String) {
        func rect(_ r: NSRect?) -> String { r.map { "\(Int($0.minX)),\(Int($0.minY)),\(Int($0.width)),\(Int($0.height))" } ?? "-" }
        let field = (shell.sidebarHost as? SidebarView)?.urlFieldFrameOnScreen
        let dark = commandPanel.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        CraLog.note("command bar \(label): open=\(commandBar.isOpen ? 1 : 0) dropdown=\(commandBar.attached ? 1 : 0) "
            + "panel=\(rect(commandPanel.isVisible ? commandPanel.frame : nil)) field=\(rect(field)) window=\(rect(window?.frame)) "
            + "dark=\(dark ? 1 : 0)")
    }

    func debugURLFieldPress(_ name: String) {
        let item: ToolbarComposition.Item = name == "copyURL" ? .copyURL : .extensions
        let pressed = (shell.sidebarHost as? SidebarView)?.debugURLFieldPress(item) == true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            CraLog.note("url field press \(name): pressed \(pressed), site control center \(self?.siteControlCenter.isShown == true ? "shown" : "not shown")")
        }
    }

    /// `cra://debug?popoverTones=1`: the appearance each open popover took (the space's,
    /// SpacePopoverTones): Translate, Blocked pop-ups, Extensions, the bookmark card; "-" for one that isn't open.
    func debugPopoverTones() {
        CraLog.note("popover tones: translate=\(translatePopover.appearanceName) popups=\(blockedPopupsPopover.appearanceName) "
                    + "extensions=\(siteControlCenter.appearanceName) bookmark=\(BookmarkEditPopover.appearanceName(in: window))")
    }

    /// Scenario hooks (#310). "line": the sidebar URL field's translate line ("translate line:
    /// Translation Available", or "none"). "open": a press on it (or on the toolbar's button), then
    /// "translate popover: <prompt> | <buttons>". "press:<title>": a press on a popover button.
    /// "menu": the Options menu's items.
    func debugTranslate(_ step: String) {
        let sidebar = shell.sidebarHost as? SidebarView
        switch step {
        case "line":
            CraLog.note("translate line: " + (sidebar?.debugTranslateLine ?? "none"))
        case "open":
            guard let id = browsers.visibleTabID else { return CraLog.note("translate popover: no tab") }
            let toolbar = (shell.focusedCard?.toolbarHost as? PaneToolbarView)?.buttonFrameOnScreen("translate")
            showTranslate(id, from: toolbar ?? sidebar?.translateFrameOnScreen)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let v = self?.translatePopover.content, self?.translatePopover.isShown == true else {
                    return CraLog.note("translate popover: not shown")
                }
                CraLog.note("translate popover: \(v.prompt) | \(v.options.title), \(v.primary.title)")
            }
        case "menu":
            guard let v = translatePopover.content else { return CraLog.note("translate menu: no popover") }
            CraLog.note("translate menu: " + v.optionsMenu().items.map { $0.isSeparatorItem ? "|" : $0.title }.joined(separator: ", "))
        default:
            guard step.hasPrefix("press:"), let v = translatePopover.content else { return }
            let title = String(step.dropFirst(6))
            for b in [v.options, v.primary] where b.title == title { _ = b.accessibilityPerformPress() }
        }
    }

    private static func debugName(_ item: ToolbarComposition.Item) -> String {
        switch item {
        case .pinnedExtension(let id): return "pin:" + id
        case .copyURL: return "copyURL"
        case .extensions: return "siteControls"
        default: return String(describing: item)
        }
    }

    private func openTab(_ url: String) {
        store.createTab(url: url, select: true, window: windowID)
        showWindow(nil)
    }

    /// The share list over the Site Control Center's Share button; the control center stays
    /// open behind it, as in Arc.
    private func shareCurrentPage(from anchor: NSView) {
        guard let url = selectedTabID.flatMap({ store.item($0)?.tab?.url }).flatMap(URL.init(string:)) else { return }
        siteControlCenter.holdOpen(true)
        SharePicker.shared.show(url, relativeTo: anchor) { [weak self] chose in
            self?.siteControlCenter.holdOpen(false)
            // The service's own window (Mail, AirDrop) takes over.
            if chose { self?.siteControlCenter.close() }
        }
    }

    /// File ▸ Share… (GitHub #279), on the open tab.
    func shareSelectedPage() { PageCommands.share(self) }

    /// The lock in the Site Control Center: the certificate of the page on screen.
    private func showCertificate() {
        guard let b = currentBrowser, let window else { return }
        let host = URL(string: b.currentURL)?.host ?? ""
        guard let certificates = b.sslStatus()?.certificates, !certificates.isEmpty else { return }
        CertificateWindow.show(certificates, host: host, over: window)
    }

    // MARK: Boosts

    /// Arc's New Boost: the open site's boost (made if it has none) in the editor beside the page.
    func openBoostEditor() {
        guard let window, let url = selectedTabID.flatMap({ store.item($0)?.tab?.url }),
              let boost = BoostStore.shared.boostForSite(of: url) else { showToast("Boosts Work on Websites"); return }
        BoostEditorController.shared.open(boost, over: window, page: .init(
            zap: { [weak self] on in self?.setZapping(on) },
            pick: { [weak self] on in self?.setPicking(on) },
            toggleDevTools: { [weak self] in self?.browsers.runDevTools(.toggle) },
            devToolsOpen: { [weak self] in self?.browsers.visibleTabHasDevTools ?? false },
            reload: { [weak self] in self?.currentBrowser?.reload() }))
    }

    /// The code panel's eyedropper (BoostPicker): the page outlines the element under the pointer
    /// and the ones like it, and holds a click; Cra polls for it and offers Arc's menu there. The
    /// poll puts the picker back after a navigation.
    /// Testing without the pointer (cra://debug?boostPick=1|0|copyThis|copyRelated|zapRelated):
    /// on (answering the menu with that action) or off.
    func debugPick(_ value: String) {
        pickAnswer = BoostPicker.Action(rawValue: value)
        setPicking(value != "0")
    }

    private func setPicking(_ on: Bool) {
        pickTimer?.invalidate()
        pickTimer = nil
        pickBrowser?.executeJavaScript(BoostPicker.stopExpression)
        pickBrowser = nil
        guard on, let b = currentBrowser else { return }
        pickBrowser = b
        b.executeJavaScript(BoostPicker.script)
        let t = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.pollPick() } }
        RunLoop.main.add(t, forMode: .common)
        pickTimer = t
    }

    private func pollPick() {
        guard let b = pickBrowser else { return }
        guard b === currentBrowser else { setPicking(false); BoostEditorController.shared.stopPicking(); return }
        let expression = BoostPicker.script + ";" + BoostPicker.takeExpression
        guard let data = try? JSONSerialization.data(withJSONObject: ["expression": expression, "returnByValue": true]),
              let params = String(data: data, encoding: .utf8) else { return }
        b.sendDevToolsMethod("Runtime.evaluate", params: params) { [weak self, weak b] result, _ in
            MainActor.assumeIsolated {
                let o = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                guard let self, let b, b === self.pickBrowser,
                      let pick = BoostPicker.parse((o?["result"] as? [String: Any])?["value"] as? String ?? "") else { return }
                self.offerPick(pick, on: b)
            }
        }
    }

    /// Arc's menu after a click with the picker: copy this element's selector, or the related
    /// ones', or zap them all.
    private func offerPick(_ pick: BoostPicker.Pick, on b: CraBrowser) {
        CraLog.note("boost pick this=\(pick.this) related=\(pick.related) (\(pick.relatedCount))")
        defer { b.executeJavaScript(BoostPicker.resumeExpression) }
        if let answer = pickAnswer { runPick(answer, pick); return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for action in BoostPicker.Action.allCases {
            let item = BlockMenuItem(title: action.title) { [weak self] in self?.runPick(action, pick) }
            item.isEnabled = action.isEnabled(for: pick)
            menu.addItem(item)
        }
        let view = b.containerView
        let p = pick.point(inViewWidth: view.bounds.width)
        menu.popUp(positioning: nil, at: NSPoint(x: p.x, y: view.isFlipped ? p.y : view.bounds.height - p.y), in: view)
    }

    private func runPick(_ action: BoostPicker.Action, _ pick: BoostPicker.Pick) {
        guard action.isEnabled(for: pick) else { return }
        let selector = action.selector(for: pick)
        switch action {
        case .copyThis, .copyRelated:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selector, forType: .string)
            CraLog.note("boost pick copied \(selector)")
        case .zapRelated:
            BoostEditorController.shared.addZapped([selector])
        }
    }

    /// Zap: the page outlines what's under the pointer, and a click hides it and keeps a selector
    /// for it; when Zap ends the selectors go into the boost.
    /// Testing without the pointer (cra://debug?boostZap=1|0): Zap on or off, as its button does.
    func debugZap(_ on: Bool) { setZapping(on) }

    private func setZapping(_ on: Bool) {
        guard let b = currentBrowser else { return }
        if on { b.executeJavaScript(Self.zapScript); return }
        b.sendDevToolsMethod("Runtime.evaluate", params: #"{"expression":"(()=>{const z=window.__craZap;if(!z)return '[]';z.stop();return JSON.stringify(z.hidden)})()","returnByValue":true}"#) { result, _ in
            MainActor.assumeIsolated {
                let o = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                let text = (o?["result"] as? [String: Any])?["value"] as? String ?? "[]"
                let selectors = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String]) ?? []
                BoostEditorController.shared.addZapped(selectors)
            }
        }
    }

    private var pickTimer: Timer?
    private weak var pickBrowser: CraBrowser?
    private var pickAnswer: BoostPicker.Action?

    static let zapScript = """
    (()=>{if(window.__craZap)return;const hidden=[];let over=null;
    const sel=e=>{if(e.id)return '#'+CSS.escape(e.id);const p=[];for(let n=e;n&&n.nodeType===1&&n!==document.body&&p.length<5;n=n.parentElement){
    if(n.id){p.unshift('#'+CSS.escape(n.id));break}let i=1;for(let s=n.previousElementSibling;s;s=s.previousElementSibling)if(s.tagName===n.tagName)i++;
    p.unshift(n.tagName.toLowerCase()+':nth-of-type('+i+')')}return (p[0]&&p[0][0]==='#'?'':'body > ')+p.join(' > ')};
    const mark=e=>{if(over)over.style.outline=over.__craOutline||'';over=e;if(e){e.__craOutline=e.style.outline;e.style.outline='2px solid #ff3b30'}};
    const page=t=>t===document.body||t===document.documentElement;
    const move=ev=>mark(page(ev.target)?null:ev.target);
    const click=ev=>{ev.preventDefault();ev.stopPropagation();const t=ev.target;if(page(t))return;mark(null);hidden.push(sel(t));t.style.display='none'};
    document.addEventListener('mouseover',move,true);document.addEventListener('click',click,true);
    window.__craZap={hidden,stop(){document.removeEventListener('mouseover',move,true);document.removeEventListener('click',click,true);mark(null);delete window.__craZap}}})()
    """

    // MARK: Arc parity (docs/arc-parity.md)

    /// Arc's Window ▸ Stay On Top: the window floats over other apps' windows.
    var staysOnTop: Bool { window?.level == .floating }
    func toggleStayOnTop() { window?.level = staysOnTop ? .normal : .floating }

    /// Arc's Reveal Tab in Sidebar / Reveal Current Tab (⌃Space): the sidebar comes out with the
    /// open tab's folders and pinned section open, and scrolls to it.
    func revealSelectedTab() {
        guard let id = selectedTabID else { return }
        store.revealInSidebar(store.splitContaining(id)?.id ?? id)
        if sidebarUI.libraryPage != nil { closeLibrary() }
        if !sidebarVisible { toggleSidebar() }
        let ui = sidebarUI, space = focusedSpaceID
        DispatchQueue.main.async { SpaceListView.jumpToSelected(for: ui, space: space) }
    }

    /// Arc's Switch to Split View 1–4 (⌃⇧1…4): the n-th pane of the open split.
    func selectSplitPane(_ n: Int) {
        guard let current = selectedTabID else { return }
        let panes = store.paneTabIDs(for: current)
        guard panes.count > 1, n >= 1, n <= panes.count else { return }
        store.selectTab(panes[n - 1], window: windowID)
    }

    /// Chrome's extensions page, as the Site Control Center's Manage Extensions… opens it.
    func openExtensionsPage() { openTab("chrome://extensions") }

    /// Arc's Open Extensions (⌘E): the Site Control Center, as if its sliders were clicked.
    func openSiteControls() { showSiteControlsFromTheirButton() }

    /// Arc's Tabs ▸ Reset all tabs in this Space: every pinned tab away from its page goes back.
    func resetAllPinnedTabs() {
        guard !isStandalone else { return }
        let space = store.focusedSpace(window: windowID)
        for t in store.tabs(under: space.pinnedContainerID) where t.tab.map({ $0.url != $0.savedURL }) == true {
            resetPinnedTab(t.id)
        }
    }

    /// Arc's Edit ▸ Copy URL as Quote, Save Page As and the page captures, on the open tab (PageCommands).
    func copyURLAsQuote() { PageCommands.copyURLAsQuote(self) }
    func savePageAs() { PageCommands.savePageAs(self) }

    func captureFullPage() {
        captureOverlay?.close()
        PageCommands.captureFullPage(self)
    }

    func capturePortrait() {
        captureOverlay?.close()
        PageCommands.capturePortrait(self)
    }

    /// The toast's Save: Arc's "Save Capture Image" panel, in Downloads.
    private func saveCapture(_ png: Data, over sourceWindow: NSWindow? = nil) {
        guard let window = sourceWindow ?? window else { return }
        PageCommands.saveCapture(png, over: window, host: self)
    }

    // MARK: Tab switcher

    /// ⌃Tab / ⌃⇧Tab: Arc's switcher over the space's recent tabs.
    func cycleRecentTabs(_ delta: Int, event: NSEvent?) {
        let theme = focusedSpace.theme
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if !tabSwitcher.isOpen {
            tabSwitcher.isDark = dark
            tabSwitcher.highlight = theme.switcherHighlight(dark: dark)
            tabSwitcher.palette = theme.palette
        }
        tabSwitcher.cycle(delta, event: event) {
            openRecentTabs(limit: TabSwitcherMetrics.maxItems).compactMap { id in
                guard let it = store.item(id), let tab = it.tab else { return nil }
                return TabSwitcher.Item(id: id, title: it.displayTitle, iconKey: tab.iconKey, snapshot: browsers.runtime(for: id)?.snapshot)
            }
        }
        // The page on screen is the freshest thumbnail there is: retake it for its card.
        guard tabSwitcher.isOpen, let current = browsers.visibleTabID else { return }
        browsers.captureSnapshot(current) { [weak self] in
            guard let self else { return }
            self.tabSwitcher.updateSnapshot(current, self.browsers.runtime(for: current)?.snapshot)
        }
    }

    /// Centred on the whole window, like Arc (sidebar included).
    private func showTabSwitcherPanel() {
        guard let window else { return }
        let size = TabSwitcherMetrics.windowSize(count: tabSwitcher.items.count)
        let wf = window.frame
        tabSwitcherPanel.setFrame(NSRect(x: (wf.midX - size.width / 2).rounded(.down), y: (wf.midY - size.height / 2).rounded(.down),
                                         width: size.width, height: size.height), display: true)
        if tabSwitcherPanel.parent !== window { window.addChildWindow(tabSwitcherPanel, ordered: .above) }
        tabSwitcherPanel.orderFront(nil)
    }

    private func hideTabSwitcherPanel() {
        if tabSwitcherPanel.parent != nil { window?.removeChildWindow(tabSwitcherPanel) }
        tabSwitcherPanel.orderOut(nil)
    }

    // MARK: Command bar

    /// `urlField`: the address field that was clicked (screen rect), when the caller knows it;
    /// otherwise the click that is being handled says (clickedURLFieldOnScreen).
    func openCommandBar(_ mode: CommandBarMode, urlField: NSRect? = nil) {
        guard let window else { return }
        // ⌘L (or a click on the address) with the Library open: the drawer slides closed first, the
        // floating sidebar staying out, then the address opens on the sidebar's field (11 Nov 2026:
        // the bar opened over the Library and the drawer was cut and jumped about).
        if mode == .editURL, sidebarUI.libraryPage != nil, !libraryClosingForAddress, libraryClosing == nil,
           sidebarVisible || floatingSidebar?.isShown == true {
            openCommandBarAfterLibrary()
            return
        }
        // Over a video in full screen (⌘T, ⌘L): the page leaves full screen first.
        if ContentFullscreenExit.shouldExit(fullscreenTab: contentFullscreenTab, shownTabs: browsers.visibleTabIDs, commandBarOpening: true) {
            exitContentFullscreen()
        }
        // A click on the address that closed the bar leaves it closed (Arc, GitHub #88).
        if mode == .editURL, NSApp.currentEvent?.type == .leftMouseUp,
           commandBarClosingClick.isClosingClick(lastMouseDown: ProcessInfo.processInfo.systemUptime
                - CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)) {
            return
        }
        // An empty split pane gets Arc's "Search or Enter URL…" bar; the result fills the pane.
        let fillingEmptyPane = selectedTab?.isEmptyTab == true
        let prefill = mode == .editURL && !fillingEmptyPane ? selectedTab?.tab?.url : nil
        let effectiveMode: CommandBarMode = (mode == .editURL && (selectedTab == nil || fillingEmptyPane)) ? .newTab : mode
        commandBar.theme = focusedSpace.theme.shown
        commandBar.focusedSpaceID = focusedSpaceID
        commandBar.open(mode: effectiveMode, prefill: prefill)
        // Arc draws the New Tab row as the active one while the bar makes a new tab; the
        // sidebar scrolls to it (SpaceListView.revealActiveRow).
        sidebarUI.newTabPlaceholderActive = effectiveMode == .newTab && !fillingEmptyPane
        // Opened by a click on the address (the sidebar's field or a bar's): a narrow dropdown over
        // that field, its list running down from it (CommandBarLayout). Otherwise (⌘L, ⌘T, the
        // menus) the palette, centred in the window.
        commandBarAnchor = mode == .editURL && !fillingEmptyPane ? (urlField ?? clickedURLFieldOnScreen()) : nil
        commandBar.attached = commandBarAnchor != nil
        commandBar.panelWidth = commandBarAnchor != nil ? CGFloat(CommandBarLayout.dropdownWidth)
            : min(CraMetrics.commandBarWidth, window.frame.width - 80)
        // The panel keeps no appearance of its own, so it follows macOS like the menus, sheets and
        // popovers (#171): Arc's bar is dark over a light space while the Mac runs dark (#187).
        positionCommandPanel()
        if commandPanel.parent == nil { window.addChildWindow(commandPanel, ordered: .above) }
        // Opened from the floating sidebar's field: the sidebar stays out (staysShown) and the
        // dropdown stays above it.
        commandBarOverFloatingSidebar = commandBarAnchor != nil && floatingSidebar?.isShown == true
        if commandBarOverFloatingSidebar { DispatchQueue.main.async { [weak self] in self?.raiseOverlayPanels() } }
        commandBarOpenedAt = Date()
        if !HitchMonitor.background { NSApp.activate(ignoringOtherApps: true) }
        // Key immediately (typing never waits); CommandBarView fades itself in.
        commandPanel.makeKeyAndOrderFront(nil)
        observeCommandBar()
    }

    private func observeCommandBar() {
        guard !commandObserving else { return }
        commandObserving = true
        withObservationTracking {
            _ = commandBar.result.items.count
            _ = commandBar.isOpen
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.commandObserving = false
                guard let self, self.commandBar.isOpen else { return }
                self.positionCommandPanel()
                self.observeCommandBar()
            }
        }
    }

    private func positionCommandPanel() {
        guard let window else { return }
        let rows = commandBar.result.items.count
        let h = CommandBarView.height(forRows: rows)
        let w = commandBar.panelWidth
        let wf = window.frame
        if let a = commandBarAnchor {
            // Over the address field, its input where the address was, kept inside the window.
            commandPanel.setFrame(CommandBarLayout.dropdownFrame(field: a, window: wf, rows: rows), display: true)
            return
        }
        // The field stays put and rows hang below it: centred as a full bar would be, so a
        // shorter list while typing doesn't move what you type into.
        let top = wf.midY + CommandBarView.height(forRows: SuggestionEngine.maxRows) / 2 + 40
        commandPanel.setFrame(NSRect(x: wf.midX - w / 2, y: top - h, width: w, height: h), display: true)
    }

    /// The address field the click that opened the bar landed on (screen rect): the sidebar's, else
    /// the focused page's bar's; nil for a key press or a click elsewhere.
    private func clickedURLFieldOnScreen() -> NSRect? {
        guard let e = NSApp.currentEvent, [.leftMouseDown, .leftMouseUp].contains(e.type) else { return nil }
        let m = NSEvent.mouseLocation
        if let r = (shell.sidebarHost as? SidebarView)?.urlFieldFrameOnScreen, r.insetBy(dx: -2, dy: -2).contains(m) { return r }
        for card in shell.paneCards {
            if let r = (card.toolbarHost as? PaneToolbarView)?.urlFieldFrameOnScreen(), r.insetBy(dx: -2, dy: -2).contains(m) { return r }
        }
        return nil
    }

    /// ⌘L with the Library open (11 Nov 2026): the Library slides back to the space exactly as its
    /// ← and Escape do (the swipe's spring: the Library goes left as the tab list comes in, the
    /// drawer narrowing with it), the floating sidebar staying out under the pointer. The bar opens
    /// at once but unseen, so whatever is typed meanwhile goes into it, and shows on the sidebar's
    /// address field once the tabs are back. Closing the Library directly first (⇧⌘L's way) cut it
    /// off at the sidebar's width before the tabs came back.
    private func openCommandBarAfterLibrary() {
        libraryClosingForAddress = true
        CraLog.note("command bar waits for the Library to slide back")
        openCommandBar(.editURL)
        commandPanel.alphaValue = 0
        let reveal = { [weak self] in
            guard let self else { return }
            self.libraryClosingForAddress = false
            self.libraryLeft = nil
            guard self.commandBar.isOpen else { self.commandPanel.alphaValue = 1; return }
            let sidebar = self.shell.sidebarHost as? SidebarView
            sidebar?.layoutSubtreeIfNeeded()
            if let field = sidebar?.urlFieldFrameOnScreen {
                self.commandBarAnchor = field
                self.commandBar.attached = true
                self.commandBar.panelWidth = CGFloat(CommandBarLayout.dropdownWidth)
                self.commandBarOverFloatingSidebar = self.floatingSidebar?.isShown == true
                self.positionCommandPanel()
                self.raiseOverlayPanels()
            }
            self.commandPanel.alphaValue = 1
            CraLog.note("command bar opens on the address after the Library (\(self.commandBar.attached ? "on its field" : "centred"))")
        }
        libraryLeft = reveal
        leaveLibrary()
        // Without a slide (Reduce Motion, a window out of sight) the Library has gone already.
        if sidebarUI.libraryPage == nil, libraryLeft != nil { reveal() }
    }

    /// Runs once the Library has slid back to the space (finishLibrarySwipe).
    private var libraryLeft: (() -> Void)?

    /// The bar was opened as the dropdown over the floating sidebar's address field.
    private(set) var commandBarOverFloatingSidebar = false
    /// ⌘L closes the Library before the address opens: the floating sidebar stays out meanwhile.
    private(set) var libraryClosingForAddress = false

    private func hideCommandPanel() {
        sidebarUI.newTabPlaceholderActive = false
        commandBarOverFloatingSidebar = false
        if commandPanel.parent != nil { window?.removeChildWindow(commandPanel) }
        let panel = commandPanel!
        // Let CommandBarView's fade-out (0.08 s) play before the panel goes away.
        panel.orderOut(nil)
        // ⌘T from a Peek and Escape: the keys go back to the Peek still over its tab (#379).
        if let peek = peeks.first(where: { !$0.isParked && $0.window?.isVisible == true }) {
            peek.window?.makeKeyAndOrderFront(nil)
            peek.focusPage()
            return
        }
        window?.makeKeyAndOrderFront(nil)
        currentBrowser?.setFocused(true)
    }

    private func handleCommit(_ s: Suggestion?, typed: String, mode: CommandBarMode) {
        let query = commandBar.query
        func open(_ url: String) {
            store.recordQuerySelection(query: query, url: url)
            let fillsEmptyPane = selectedTab?.isEmptyTab == true
            // A pinned tab keeps to its host: another host's address opens a Today tab (Arc).
            let leavesPinned = !fillsEmptyPane && selectedTabID.map(store.isPinned) == true
                && PinnedNavigation.typedURLOpensNewTab(url, from: selectedTab?.tab?.url ?? "")
            if mode == .editURL || fillsEmptyPane, selectedTabID != nil, !leavesPinned {
                loadInSelectedTab(url)
            } else {
                store.createTab(url: url, window: windowID)
            }
        }
        guard let s else {
            if typed.isEmpty { return }
            open(SuggestionEngine.looksLikeURL(typed) ? SuggestionEngine.urlFromInput(typed) : commandBar.engine.searchURL(typed))
            return
        }
        switch s.kind {
        case .switchToTab(let id):
            store.recordQuerySelection(query: query, url: s.url ?? "")
            store.selectTab(id, window: windowID)
        case .archived(let id):
            store.restoreArchived(id)
        case .navigate:
            let url = typed == commandBar.query ? (s.url ?? SuggestionEngine.urlFromInput(typed)) : SuggestionEngine.urlFromInput(typed)
            open(url)
        case .search:
            open(s.url ?? commandBar.engine.searchURL(typed))
        case .history, .topDomain:
            open(s.url ?? "")
        case .command(let id):
            app.perform(id)
        case .switchSpace(let id):
            store.focusSpace(id, window: windowID)
        case .moveToSpace(let id):
            if let t = selectedTabID { store.moveTabAndFollow(t, toSpace: id, window: windowID) }
        case .moveToFolder(let id):
            if let t = selectedTabID { store.moveItem(t, to: id, index: nil) }
        }
    }

    /// ⌘Return in the bar (Arc): the row's page in a new background tab, the current tab staying
    /// in front; an open tab's row opens its address again rather than switching (GitHub #85).
    private func openInBackground(_ s: Suggestion?, typed: String) -> Bool {
        guard let url = pageURL(s, typed: typed) else { return false }
        store.recordQuerySelection(query: commandBar.query, url: url)
        let tab = store.createTab(url: url, select: false, window: windowID)
        store.markUnread(tab.id, false)  // Arc saves these read, unlike a link opened in the background
        // Creating the page takes key from the bar; it takes key back and stays open, as while
        // opening (windowDidResignKey).
        commandBarOpenedAt = Date()
        browsers.ensureRuntime(for: tab.id)  // load it so the title and favicon fill in
        // With the sidebar out the new row shows there; hidden, Arc says so in a toast.
        if !sidebarVisible { showToast(Self.newTabToast) }
        return true
    }

    /// ⌥Return in the bar: the row opens as a split pane beside the current tab instead of in its
    /// place, an open tab of this space joining the split as it is. False takes it as Return: no
    /// tab to split, an empty one (the row fills it), a tab in another space, a row with no page.
    private func openInSplit(_ s: Suggestion?, typed: String) -> Bool {
        guard let current = selectedTabID, store.item(current)?.isEmptyTab == false else { return false }
        if case .switchToTab(let id)? = s?.kind {
            guard id != current, store.spaceID(ofItem: id) == store.spaceID(ofItem: current) else { return false }
            if store.paneTabIDs(for: current).contains(id) {
                store.selectTab(id, window: windowID)
                return true
            }
        }
        guard store.paneTabIDs(for: current).count < 4 else {
            showToast("Cannot Add New Pane")
            return true
        }
        if case .switchToTab(let id)? = s?.kind {
            store.recordQuerySelection(query: commandBar.query, url: s?.url ?? "")
            let split = store.splitContaining(current).map { sp in store.addToSplit(sp.id, tabID: id, at: nil); return store.item(sp.id) }
                ?? store.createSplit(with: [current, id], at: current)
            store.selectTab(split.flatMap { store.paneID(for: id, in: $0) } ?? id, window: windowID)
            return true
        }
        guard let url = pageURL(s, typed: typed) else { return false }
        store.recordQuerySelection(query: commandBar.query, url: url)
        guard store.addEmptyPane(nextTo: current, url: url) != nil else { return false }
        refresh()
        return true
    }

    /// The page a row opens anew (⌘Return, ⌥Return), nil for rows that open none.
    private func pageURL(_ s: Suggestion?, typed: String) -> String? {
        let url: String?
        switch s?.kind {
        case nil:
            url = typed.isEmpty ? nil : SuggestionEngine.looksLikeURL(typed) ? SuggestionEngine.urlFromInput(typed) : commandBar.engine.searchURL(typed)
        case .navigate?:
            url = typed == commandBar.query ? (s?.url ?? SuggestionEngine.urlFromInput(typed)) : SuggestionEngine.urlFromInput(typed)
        case .search?:
            url = s?.url ?? commandBar.engine.searchURL(typed)
        case .switchToTab?, .archived?, .history?, .topDomain?:
            url = s?.url
        default:
            url = nil
        }
        return url?.isEmpty == false ? url : nil
    }

    /// The first time a service plays in a WebKit page (docs/protected-media.md): "Spotify plays
    /// with Safari's engine", with Why? (the Site Control Center says what that means). It stays
    /// until its ✕ is pressed, Why? included, so Cra knows it was seen; only then is the service told
    /// for good. Shown once a session per service: one left open shows again next launch.
    private func tellAboutProtectedMedia(_ service: String) {
        guard !PageEngines.wasTold(service), !offeredProtectedMedia.contains(service), window?.isVisible == true else { return }
        offeredProtectedMedia.insert(service)
        let told = { PageEngines.told(service) }
        // A moment after the page shows, so it isn't lost in the tab switch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, let window = self.window, let id = self.browsers.visibleTabID,
                  self.sidebarUI.navState(for: id).protectedMedia == service else {
                self?.offeredProtectedMedia.remove(service)
                return
            }
            let page = self.shell.webContainer.convert(self.shell.webContainer.bounds, to: nil)
            self.slowResponseToastTab = nil
            self.toast.show("\(service) plays with Safari's engine",
                            action: ShinyToast.Action(title: "Why?") { [weak self] in self?.showSiteControlsFromTheirButton() },
                            page: page, in: window, theme: self.focusedSpace.theme, onClose: told)
        }
    }

    /// Services whose toast was offered this session (they show once a session until answered).
    private var offeredProtectedMedia: Set<String> = []

    /// Arc's toast at the top right of the page (ShinyToast): Cra's confirmations.
    // MARK: Bookmarks and ⌘D

    private var pinGuard = FavoritePinGuard()

    /// ⌘D: pins or unpins the tab, as Arc does. On a favorite the first press only says it has its
    /// place up top already; a second press within 1.5 s pins a copy into this space (FavoritePinGuard).
    func pinTabGuarded(_ id: UUID) {
        let favorite = store.isFavorite(id)
        switch pinGuard.press(tab: id, isFavorite: favorite, now: ProcessInfo.processInfo.systemUptime) {
        case .warn:
            showToast("Already in Top Favorites")
        case .pin where favorite:
            guard let url = store.item(id)?.tab?.url else { return }
            store.createTab(url: url, title: store.item(id)?.displayTitle ?? "", in: focusedSpaceID, pinned: true, select: false, window: windowID)
            showToast("Added to Pinned Tabs")
        case .pin:
            store.togglePinned(id)
        }
    }

    /// ⇧⌘D and the star in the Extensions popover: the page is bookmarked (or its bookmark found)
    /// and its card opens under `anchor` (a screen rect), else under the Extensions button, else at
    /// the top of the page.
    func bookmarkCurrentPage(anchor: NSRect?) {
        guard let window, let tab = selectedTab, let url = tab.tab?.url, BookmarkEditPopover.canBookmark(url) else {
            showToast("Nothing to Bookmark Here")
            return
        }
        let existing = BookmarkStore.shared.bookmark(for: url)
        let b = existing ?? BookmarkStore.shared.add(url: url, title: tab.displayTitle)
        BookmarkEditPopover.show(b, from: anchor ?? bookmarkAnchorOnScreen(), in: window, isNew: existing == nil)
    }

    /// Where the card hangs from: exactly where the Extensions popover hangs from its button (the
    /// bar's, else the sidebar's address field's), so the two arrows are in one place; else the
    /// top middle of the page.
    private func bookmarkAnchorOnScreen() -> NSRect {
        if let r = (shell.focusedCard?.toolbarHost as? PaneToolbarView)?.siteControlsButtonFrameOnScreen(),
           let y = shell.panesShowBars ? toolbarBottomOnScreen()?.y : urlBarBottomOnScreen() {
            return Self.popoverAnchor(midX: r.midX, barBottom: y)
        }
        if shell.sidebarVisible || floatingSidebar?.isShown == true,
           let r = (shell.sidebarHost as? SidebarView)?.siteControlsButtonFrameOnScreen {
            return Self.popoverAnchor(midX: r.midX, barBottom: urlBarBottomOnScreen() ?? r.minY)
        }
        let card = shell.webContainer
        let top = card.window.map { $0.convertToScreen(card.convert(card.bounds, to: nil)) } ?? window?.frame ?? .zero
        return NSRect(x: top.midX - 1, y: top.maxY - 4, width: 2, height: 2)
    }

    /// The rect a site popover hangs from (screen): Arc's popover overlaps the bar by 4 pt.
    static func popoverAnchor(midX: CGFloat, barBottom y: CGFloat) -> NSRect {
        NSRect(x: midX - 16, y: y + 4, width: 32, height: 28)
    }

    /// `cra://debug?windowState`: which of its popovers are up ("extensions,bookmark", "-").
    var debugPopovers: String {
        let up = [siteControlCenter.isShown ? "extensions" : nil, BookmarkEditPopover.isOpen(in: window) ? "bookmark" : nil,
                  themePicker != nil ? "theme" : nil, translatePopover.isShown ? "translate" : nil,
                  blockedPopupsPopover.isShown ? "popups" : nil].compactMap { $0 }
        return up.isEmpty ? "-" : up.joined(separator: ",")
    }

    /// The theme picker open over this window (StyleEditorPanel), if any.
    private var themePicker: NSWindow? { window?.childWindows?.first { $0 is StyleEditorPanel && $0.isVisible } }
    /// The space the open theme picker edits (or previews on, for Create a Space).
    var themePickerSpaceID: UUID?

    // MARK: Settings (⌘,)

    /// ⌘, (Settings…): the settings page (cra://settings) in a tab, on `section` when given. The
    /// space on screen's settings tab comes to the front if it has one; otherwise a new tab opens.
    /// `address`: a page address to load instead of the section's own (Shortcuts on one command).
    func openSettingsTab(_ section: SettingsPage.Section?, address: String? = nil) {
        dismissTransientUI()
        let existing = store.allTabs().first { item in
            item.tab.map { SettingsPage.owns($0.url) } == true && store.spaceID(ofItem: item.id) == focusedSpaceID
        }
        if let item = existing {
            if let section {
                let url = address ?? SettingsPage.url(section)
                if let page = browsers.runtime(for: item.id)?.browser { page.loadURL(url) }
                else { store.updateTab(item.id, url: url) }
            }
            store.selectTab(item.id, window: windowID)
        } else {
            store.createTab(url: address ?? SettingsPage.url(section ?? .general), select: true, window: windowID)
        }
        CraLog.note("settings tab shown (\((section ?? .general).rawValue), \(existing == nil ? "new" : "existing"))")
    }

    /// The popovers hung from the sidebar and the bar (the Extensions popover, the bookmark card,
    /// Translate, Blocked pop-ups)
    /// go when what they belong to does: the floating sidebar starting to hide, another space.
    /// `spaceChange`: another space came up; the theme picker goes only when it belongs to another
    /// space than the one now shown (Edit Theme Color… on another space's icon opens it as that
    /// space slides in).
    func dismissPopovers(_ reason: String, spaceChange: Bool = false) {
        let up = debugPopovers
        guard up != "-" else { return }
        if siteControlCenter.isShown { siteControlCenter.close() }
        BookmarkEditPopover.close(in: window)
        // Translate and Blocked pop-ups hang from the same bar and URL field (#310, #357).
        if translatePopover.isShown { translatePopover.close() }
        if blockedPopupsPopover.isShown { blockedPopupsPopover.close() }
        if let picker = themePicker, !spaceChange || themePickerSpaceID != focusedSpaceID, sidebarUI.creatingSpace == nil {
            picker.close()
        }
        CraLog.note("popovers dismissed (\(up)): \(reason)")
    }

    /// A bookmark from the Library: a new tab with its page, and back to the space.
    private func openBookmark(_ b: Bookmark) {
        store.createTab(url: b.url, select: true, window: windowID)
        closeLibrary()
    }

    /// Arc's `backgroundTabCreated` toast, for a tab that opened without being shown: a link opened
    /// behind the page (⌘-click, a middle click, Open Link in New Tab) or one from another app.
    static let newTabToast = "New Tab Created"

    func browserManagerOpenedTab(_ tabID: UUID, background: Bool) {
        guard background else { return }
        showToast(Self.newTabToast, action: ShinyToast.Action(title: "Show") { [weak self] in
            guard let self else { return }
            self.store.selectTab(tabID, window: self.windowID)
        })
    }

    func showToast(_ text: String, keyCap: (keys: String, after: String)? = nil, action: ShinyToast.Action? = nil) {
        guard let window else { return }
        let page = shell.webContainer.convert(shell.webContainer.bounds, to: nil)
        slowResponseToastTab = nil
        toast.show(text, keyCap: keyCap, action: action, page: page, in: window, theme: focusedSpace.theme)
    }

    /// The update banner's news while this window's sidebar (which carries the banner) is hidden:
    /// Cra's toast with the banner's action, staying until its ✕ so it isn't missed.
    func showUpdateToast(_ notice: UpdateNotice) {
        guard let window else { return }
        let page = shell.webContainer.convert(shell.webContainer.bounds, to: nil)
        toast.show(notice.title, action: ShinyToast.Action(title: notice.button) { SoftwareUpdater.shared.act(on: notice) },
                   page: page, in: window, theme: focusedSpace.theme, onClose: {})
    }

    /// A Peek's page loads in the tab the Peek came from (⌘-click on Expand, GitHub #380): the tab
    /// comes to the front with the page, and a pinned one keeps its pinned address (updateTab).
    func loadPeekPage(_ url: String, inTab id: UUID) {
        guard store.item(id) != nil else { return }
        if selectedTabID != id { store.selectTab(id, window: windowID) }
        loadInSelectedTab(url)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Navigate the focused tab (an empty split pane gets its first page here).
    func loadInSelectedTab(_ url: String) {
        guard let id = selectedTabID else { return }
        let wasEmpty = store.item(id)?.isEmptyTab == true
        store.updateTab(id, url: url)
        if let rt = browsers.ensureRuntime(for: id), !wasEmpty { rt.browser.loadURL(url) }
        refresh()
        browsers.show(store.visiblePaneTabIDs(in: focusedSpaceID, window: windowID), focused: id, focus: true)
    }

    // MARK: Find

    func showFindBar() {
        syncAskOnPage()
        overlay.findVisible = true
        overlay.findFocusToken += 1
        shell.findVisible = true
        shell.layoutContentChildren()
        if let window, let find = findPanel {
            if find.parent !== window { window.addChildWindow(find, ordered: .above) }
            refitFindPanel()
            find.makeKeyAndOrderFront(nil)
        }
    }

    func hideFindBar() {
        overlay.findVisible = false
        overlay.findMatchCount = nil
        askOnPage.reset()
        shell.findVisible = false
        currentBrowser?.stopFinding(true)
        shell.layoutContentChildren()
        if let find = findPanel, let window {
            // Typing goes back to the page, unless focus already moved elsewhere.
            if find.isKeyWindow { browsers.visibleRuntime?.hostWindow?.makeKey() }
            window.removeChildWindow(find)
            find.orderOut(nil)
        }
        currentBrowser?.setFocused(true)
    }

    /// Arc's (and Chrome's) Edit ▸ Find ▸ Use Selection to Find: the page's selection becomes the
    /// search, on the find pasteboard too as macOS apps share it, and the bar finds it.
    func useSelectionForFind() {
        guard let b = currentBrowser else { return }
        b.sendDevToolsMethod("Runtime.evaluate", params: #"{"expression":"getSelection().toString()","returnByValue":true}"#) { [weak self] result, _ in
            MainActor.assumeIsolated {
                let o = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                let text = ((o?["result"] as? [String: Any])?["value"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let self, !text.isEmpty else { return }
                let pb = NSPasteboard(name: .find)
                pb.clearContents()
                pb.setString(text, forType: .string)
                self.overlay.findQuery = text
                self.showFindBar()
                self.find(text, forward: true)
            }
        }
    }

    /// Arc's (and Chrome's) Edit ▸ Find ▸ Jump to Selection (⌘J): the page scrolls its selection into view.
    func jumpToSelection() { PageCommands.jumpToSelection(currentBrowser) }

    func findNext(forward: Bool) {
        if !overlay.findVisible { showFindBar(); return }
        find(overlay.findQuery, forward: forward)
    }

    /// Always a follow-up find: CEF restarts the search when the text changes, and
    /// unlike a first request that selects a match (Chrome's find bar does this while
    /// typing), so the bar shows "1/3" rather than "0/3".
    private func find(_ q: String, forward: Bool) {
        guard let b = currentBrowser else { return }
        if q.isEmpty { overlay.findMatchCount = nil; lastFindText = ""; b.stopFinding(true); return }
        lastFindText = q
        b.findText(q, forward: forward, matchCase: false, findNext: true)
    }

    /// Ask on Page or the plain find bar, by the setting and the model; the card follows the page in
    /// front and the space's colour.
    func syncAskOnPage() {
        let enabled = store.settings.askOnPage && AskOnPageService.shared.isAvailable
        let state = askOnPage.state
        if state.enabled != enabled {
            state.enabled = enabled
            if !enabled { askOnPage.reset() }
        }
        shell.findHost.isHidden = enabled
        askOnPage.view.isHidden = !enabled
        let theme = focusedSpace.theme.shown
        let c = AskOnPageTone.accent(themeHex: theme.accent ?? theme.colors.first ?? "#DDDDDD", dark: theme.isDark)
        askOnPage.setAccent(c)
        let tab = browsers.visibleTabID
        askOnPage.pageChanged(tab: tab, url: tab.flatMap { store.item($0)?.tab?.url }.flatMap(URL.init(string:)))
        refitFindPanel()
    }

    /// The find panel takes the card's size, its top trailing corner where it was.
    private func refitFindPanel() {
        guard let window, let find = findPanel, overlay.findVisible, let page = lastFindPage else { return }
        let frame = findPanelFrame(page: page)
        if find.parent === window, find.frame != frame { find.setFrame(frame, display: true) }
    }

    // MARK: Sheets

    // MARK: Create a Space

    /// The space whose theme Create a Space previews: the one it was opened from.
    private var createPreviewSpace: UUID?
    /// Create a Space brought out a hidden sidebar; Cancel puts it away again.
    private var createShowedSidebar = false
    /// Create a Space opened in the floating sidebar over a hidden one.
    private var createFloats = false
    /// What runs with the new space's id once Create Space made it (Move to ▸ New Space…, #356).
    private var createCompletion: ((UUID) -> Void)?
    /// When the theme picker last closed: a press on Choose a Theme that closed it doesn't reopen it.
    private var createPickerClosedAt: TimeInterval = 0

    /// New Space…: Arc's Create a Space in place of the sidebar's content (CreateSpaceSheet). The
    /// window shows the new space's theme while it is picked (previewed on the space it was opened
    /// from, which gets its own back); Create Space makes the space, Cancel leaves everything as it was.
    /// `cra://debug?createSpace=<name>` makes the space being created under that name;
    /// `createSpace=cancel` cancels it.
    func debugCreateSpace(_ name: String) {
        guard let model = sidebarUI.creatingSpace else { return }
        if name == "cancel" { model.onCancel(); return }
        model.name = name
        model.onCreate()
    }

    func showCreateSpace(created: ((UUID) -> Void)? = nil) {
        guard let window else { return }
        if let created { createCompletion = created }
        if let open = sidebarUI.creatingSpace {
            (shell.sidebarHost.window ?? window).makeKey()
            open.focusName()
            return
        }
        if sidebarUI.libraryPage != nil { closeLibrary() }
        if !sidebarVisible {
            // The sidebar keeps its state: a hidden one comes out floating for the new space (and
            // stays out while it is made, staysShown) and goes back once it's made or cancelled.
            // It used to be docked for it, and stayed docked after Create Space.
            if let f = floatingSidebar {
                createFloats = true
                if !f.isShown { f.show() }
            } else {
                createShowedSidebar = true
                sidebarVisible = true
            }
        }
        let from = focusedSpace
        // Arc's New Space starts on the profile of the space it was opened from.
        let initialProfile = isStandalone ? nil : SpaceProfiles.forNewSpace(from: from, profiles: store.profiles)
        let model = CreateSpaceModel(theme: SpaceColorPresets.newSpaceTheme(opacity: store.settings.defaultSpaceOpacity), profile: .existing(initialProfile), profiles: store.profiles)
        createPreviewSpace = from.id
        store.previewTheme(model.theme, forSpace: from.id)
        model.onCreate = { [weak self, weak model] in self?.finishCreateSpace(model, create: true) }
        model.onCancel = { [weak self, weak model] in self?.finishCreateSpace(model, create: false) }
        model.onChooseTheme = { [weak self, weak model] row in if let model { self?.toggleCreateThemePicker(model, row: row) } }
        sidebarUI.creatingSpace = model
        // Its name field takes the keys: in the floating sidebar's panel when it floats.
        (shell.sidebarHost.window ?? window).makeKey()
    }

    private func finishCreateSpace(_ model: CreateSpaceModel?, create: Bool) {
        guard let model, sidebarUI.creatingSpace === model else { return }
        for p in window?.childWindows ?? [] where p is StyleEditorPanel { p.close() }
        if let id = createPreviewSpace { store.endThemePreview(forSpace: id, keep: false) }
        createPreviewSpace = nil
        let made = create && model.isValid
        // Cancel slides the card back out; Create Space goes on to the new space, which the pager
        // shows at once (no page spring under the slide).
        sidebarUI.createSpaceExit = made ? .creating : .cancelling
        sidebarUI.pagerJumpsOnce = made
        sidebarUI.creatingSpace = nil
        let completion = createCompletion
        createCompletion = nil
        if made {
            let id = store.createSpace(title: model.trimmedName, emoji: model.icon.emoji, symbol: model.icon.symbol, theme: model.theme).id
            switch model.profile {
            case .existing(let p): store.setProfile(p, forSpace: id)
            case .new: store.setProfile(store.createProfile(name: model.trimmedProfileName).id, forSpace: id)
            }
            completion?(id)
        }
        if createShowedSidebar { sidebarVisible = false }
        createShowedSidebar = false
        if createFloats {
            createFloats = false
            if let f = floatingSidebar, f.isShown, !pointerOnFloatingSidebar(width: shell.sidebarWidth) { f.hide(animated: true) }
        }
    }

    /// Choose a Theme: the picker beside the sidebar, centred on the row (kept inside the window),
    /// its arrow at the row. Every change shows in the window at once; the panel keeps the theme.
    private func toggleCreateThemePicker(_ model: CreateSpaceModel, row: CGRect) {
        guard let window else { return }
        let justClosed = ProcessInfo.processInfo.systemUptime - createPickerClosedAt < 0.3
        if model.pickingTheme || justClosed {
            for p in window.childWindows ?? [] where p is StyleEditorPanel { p.close() }
            return
        }
        // The arrow's tip just past the sidebar's edge, at the row.
        let place = placeThemePicker(sourceY: row.midY, edgeX: sidebarEdgeOnScreen ?? window.frame.minX + shell.sidebarWidth)
        let preview = createPreviewSpace, store = self.store
        model.pickingTheme = true
        ThemePickerPopover.present(on: window, theme: model.theme, topLeft: place.topLeft,
                                   arrowY: place.arrowY,
                                   onChange: { [weak model] theme in
                                       model?.theme = theme
                                       if let preview { store.previewTheme(theme, forSpace: preview) }
                                   },
                                   onClose: { [weak self, weak model] in
                                       model?.pickingTheme = false
                                       self?.createPickerClosedAt = ProcessInfo.processInfo.systemUptime
                                   })
    }

    /// `created` runs with a new space's id once it is made (Move to ▸ New Space…, #356).
    func showSpaceEditor(space: Space?, created: ((UUID) -> Void)? = nil) {
        // A new space is made in the sidebar, as in Arc; Edit Space… keeps its sheet.
        guard space != nil else { showCreateSpace(created: created); return }
        guard let window else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 651, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        // Arc's New Space starts on the profile of the space it was opened from.
        let initialProfile = space == nil && !isStandalone ? SpaceProfiles.forNewSpace(from: store.focusedSpace, profiles: store.profiles) : nil
        let store = self.store
        let profilePath = space.flatMap { store.profilePath(space: $0.id) } ?? store.profilePath(profile: initialProfile)
        let defaultEngine = SearchEngines.shared.defaultEngine(profilePath: profilePath, legacy: store.settings.searchEngine)
        let engines = ChromiumSearchEngine.spaceChoices(among: SearchEngines.shared.keywords(profilePath: profilePath))
        let view = SpaceEditorView(existing: space, profiles: store.profiles, initialProfile: initialProfile, searchEngines: engines,
                                   defaultEngineName: defaultEngine.name, onSave: { [weak panel] title, icon, theme, profile, newName, searchEngine in
            let id: UUID
            if let sid = space?.id, var s = store.space(sid) {
                s.title = title; s.icon = icon; s.theme = theme
                store.updateSpace(s)
                id = s.id
            } else {
                id = store.createSpace(title: title, emoji: icon.emoji, symbol: icon.symbol, theme: theme).id
            }
            switch profile {
            case .existing(let p): store.setProfile(p, forSpace: id)
            case .new: store.setProfile(store.createProfile(name: newName).id, forSpace: id)
            }
            store.setSearchEngine(searchEngine, forSpace: id)
            if let panel { window.endSheet(panel) }
            if space == nil { created?(id) }
        }, onCancel: { [weak panel] in if let panel { window.endSheet(panel) } }, onPreview: { theme in
            // A new space has nothing to draw on yet; the sheet's own preview shows it.
            if let sid = space?.id { store.previewTheme(theme, forSpace: sid) }
        })
        panel.contentView = NSHostingView(rootView: view)
        spaceEditor = panel
        window.beginSheet(panel) { [weak self] _ in
            // Closed without Save (Cancel, Escape, cra://dismiss): the stored theme comes back.
            // Save already wrote it, so this does nothing then.
            if let sid = space?.id { store.endThemePreview(forSpace: sid, keep: false) }
            self?.spaceEditor = nil
        }
    }

    /// Dia-style import window (UI/Onboarding): browser, spaces, extensions, progress.
    /// `firstRun` makes it the onboarding: shown instead of this window, not closable.
    func showImport(firstRun: Bool = false) {
        if let existing = importWindow { existing.window?.makeKeyAndOrderFront(nil); return }
        let controller = ImportWindowController(store: store, favicons: app.favicons, firstRun: firstRun,
                                                onFinish: { [weak self] outcome in self?.app.importFinished(outcome, firstRun: firstRun) },
                                                onClosed: { [weak self] in self?.importWindow = nil })
        importWindow = controller
        controller.show(over: firstRun ? nil : window)
    }

    /// Brings the import window forward if one is open (Dock clicks during onboarding).
    func raiseImport() -> Bool {
        guard let w = importWindow?.window else { return false }
        w.makeKeyAndOrderFront(nil)
        return true
    }

    var isImportVisible: Bool { importWindow?.window?.isVisible == true }

    /// Close whatever transient UI is up (used by cra://dismiss for scripting).
    /// Escape that reached the window (CraWindow.onEscape): a video's full screen ends, else what is
    /// open closes. Never the window's size (CraCore WindowEscape).
    func windowEscape() {
        let open = commandBar.isOpen || overlay.findVisible || siteControlCenter.isShown || window?.attachedSheet != nil
            || sidebarUI.creatingSpace != nil || BookmarkEditPopover.isOpen(in: window)
        let action = WindowEscape.action(pageFullscreen: contentFullscreenTab != nil, somethingOpen: open)
        CraLog.note("escape in window: \(action)")
        switch action {
        case .exitPageFullscreen: exitContentFullscreen()
        case .dismissOpen:
            dismissPopovers("escape")
            dismissTransientUI()
        case .nothing: break
        }
    }

    func dismissTransientUI() {
        if let creating = sidebarUI.creatingSpace { finishCreateSpace(creating, create: false) }
        if let sheet = window?.attachedSheet { window?.endSheet(sheet) }
        importWindow?.close()
        commandBar.close()
        if overlay.findVisible { hideFindBar() }
    }

    // MARK: NSWindowDelegate

    // MARK: Maximized (WindowFill)

    /// Where a zoom is taking the window, while its animation runs. The window counts as
    /// maximized (or not) from the zoom's start, and the card (with the sidebar toggle in its
    /// toolbar while the sidebar is hidden) moves with the window's frame on AppKit's own zoom
    /// animation, landing as the window does, both ways (ShellView.beginZoom). The green button
    /// with ⌥, Window ▸ Zoom and a title bar double-click all come through here.
    private var zoomTarget: NSRect?
    private var zoomGeneration = 0

    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
        guard window === self.window else { return true }
        ArcTooltipController.shared.holdForTransition(window.animationResizeTime(newFrame) + 0.2)
        let screenVisible = (NSScreen.screens.first { $0.frame.intersects(newFrame) } ?? window.screen)?.visibleFrame ?? .zero
        let maximized = WindowFill.isMaximized(frame: newFrame, visibleFrame: screenVisible)
        zoomTarget = newFrame
        zoomGeneration += 1
        let generation = zoomGeneration
        shell.beginZoom(from: window.frame, to: newFrame, maximized: maximized)
        // A zoom that never lands on its frame (a size limit) still hands back to the frame rule.
        DispatchQueue.main.asyncAfter(deadline: .now() + window.animationResizeTime(newFrame) + 0.15) { [weak self] in
            guard let self, self.zoomGeneration == generation, self.zoomTarget != nil else { return }
            self.zoomTarget = nil
            self.shell.endZoom()
            self.updateWindowFill()
        }
        return true
    }

    /// Whether the window fills its screen now; full screen counts on its own (windowFullscreen).
    private func updateWindowFill() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        if let target = zoomTarget {
            // Mid-zoom: keep what the zoom decided until it lands.
            guard abs(window.frame.minX - target.minX) < 0.5, abs(window.frame.minY - target.minY) < 0.5,
                  abs(window.frame.width - target.width) < 0.5, abs(window.frame.height - target.height) < 0.5 else { return }
            zoomTarget = nil
            shell.endZoom()
        }
        shell.windowMaximized = WindowFill.isMaximized(frame: window.frame, visibleFrame: window.screen?.visibleFrame ?? .zero)
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        updateWindowFill()
    }

    func windowDidResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        updateWindowFill()
        // Arc's Spaces page keeps the page its 56 pt while the window resizes; a drawer its share.
        if let page = sidebarUI.libraryPage, sidebarUI.libraryReveal == nil { shell.drawerWidth = libraryWidth(page) }
        shell.needsLayout = true
        browsers.layoutVisible()
        if commandBar.isOpen { positionCommandPanel() }
        floatingSidebar?.reposition()
        for p in peeks { p.repositionPeek() }
        // A toast that stays (the protected media one) follows the page's corner, once laid out.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            // The page behind a Peek shrinks around its new centre.
            if self.peekVeil.isOn { self.applyPeekVeil(duration: 0) }
            self.toast.follow(page: self.shell.webContainer.convert(self.shell.webContainer.bounds, to: nil), in: window)
        }
        saveFrame()
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        ArcTooltipController.shared.holdForTransition(0.3)
        // The area under the pages shows while they catch up; make sure it has their current colour.
        for id in browsers.visibleTabIDs { browsers.runtime(for: id)?.browser.probeBackgroundColor() }
    }

    func windowDidMove(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        if commandBar.isOpen { positionCommandPanel() }
        floatingSidebar?.reposition()
        saveFrame()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        refreshMaterialActive()
        browsers.windowVisibilityChanged(covered: false)
        reclaimPages()
    }

    func windowDidBecomeMain(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        reclaimPages()
    }

    /// Back in this window: pages that moved to another window come back (Arc's untargeted
    /// reparenting). After AppDelegate has made this the active window.
    /// This window shows the tab's blurred stand-in while another window holds its page.
    func isShowingElsewhere(_ tabID: UUID) -> Bool {
        !isTornDown && shell.paneCards.contains { $0.tabID == tabID && $0.showsElsewhere }
    }

    /// A page handed over by a window that is closing.
    func takePage(_ rt: TabRuntime) {
        browsers.adopt(rt.browser, for: rt.tabID, from: "another window's")
        refresh()
    }

    private func reclaimPages() {
        guard shell.paneCards.contains(where: \.showsElsewhere) else { return }
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    func windowDidResignKey(_ notification: Notification) {
        if (notification.object as? NSWindow) === window { leaveIfCovered() }
        guard (notification.object as? NSWindow) === commandPanel, commandBar.isOpen else { return }
        if Date().timeIntervalSince(commandBarOpenedAt) < 0.6 {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.commandBar.isOpen else { return }
                self.commandPanel.makeKeyAndOrderFront(nil)
            }
            return
        }
        let event = NSApp.currentEvent
        commandBarClosingClick.panelClosed(byMouseDownAt: event?.type == .leftMouseDown ? event?.timestamp : nil)
        commandBar.close()
    }

    /// This window as the next new window takes after it (CraCore NewWindowLayout); nil while it
    /// isn't on screen.
    var newWindowSource: NewWindowLayout.Source? {
        guard let window, window.isVisible, !window.isMiniaturized else { return nil }
        return NewWindowLayout.Source(frame: window.frame, windowedFrame: store.window(windowID).frame.map(NSRectFromString),
                                      fullScreen: window.styleMask.contains(.fullScreen), fullScreenForPage: enteredFullscreenForContent,
                                      sidebarVisible: sidebarVisible, visibleFrame: (window.screen ?? NSScreen.main)?.visibleFrame ?? .zero)
    }

    /// What runs once the window has gone full screen (or couldn't): a new window's command bar,
    /// placed for the full-screen frame rather than the one it was shown at.
    private var afterEnteringFullScreen: (() -> Void)?

    /// Where a window born in full screen goes the first time it leaves: the frame it would have
    /// had as a window (its session's), not the screen-sized one it was shown at.
    private var leaveFullScreenTo: NSRect?

    /// A new window that goes full screen like the one it came from is shown at its screen's size,
    /// so the first thing seen is the window filling the screen, not a smaller one over the
    /// full-screen Space it came from (12 Nov 2026: a cascaded rectangle showed for ~100 ms).
    func prepareForFullScreen(screen: NSRect) {
        guard let window, !screen.isEmpty else { return }
        leaveFullScreenTo = store.window(windowID).frame.map(NSRectFromString)
        window.setFrame(screen, display: false)
        // Not its frame as a window: the session keeps the one it would have had.
        frameSaveWork?.cancel()
        frameSaveWork = nil
    }

    /// A new window opened from a full-screen one (NewWindowLayout): into a full-screen Space of its
    /// own, as soon as it is on screen, rather than a rectangle over the one it came from.
    func enterFullScreen(then done: @escaping () -> Void) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return done() }
        afterEnteringFullScreen = done
        CraLog.note("new window goes full screen like the one it came from")
        window.toggleFullScreen(nil)
        // Neither "entered" nor "failed" came (another transition in the way): the bar opens anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.runAfterEnteringFullScreen() }
    }

    private func runAfterEnteringFullScreen() {
        guard let done = afterEnteringFullScreen else { return }
        afterEnteringFullScreen = nil
        CraLog.note("new window \(window?.styleMask.contains(.fullScreen) == true ? "is full screen" : "didn't go full screen"): its command bar opens")
        done()
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) { runAfterEnteringFullScreen() }

    // The sidebar header's toggle moves into the traffic lights' place while they are gone (Arc).
    func windowWillEnterFullScreen(_ notification: Notification) {
        ArcTooltipController.shared.holdForTransition(1)
        sidebarUI.windowFullscreen = true
        shell.windowFullscreen = true
    }
    func windowWillExitFullScreen(_ notification: Notification) {
        ArcTooltipController.shared.holdForTransition(1)
        sidebarUI.windowFullscreen = false
        shell.windowFullscreen = false
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        shell.needsLayout = true
        runAfterEnteringFullScreen()
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        // Left with the green button or ⌃⌘F while a video was fullscreen: the page leaves too.
        if let id = contentFullscreenTab { browsers.runtime(for: id)?.browser.exitFullscreen() }
        contentFullscreenTab = nil
        if shell.contentFullscreen {
            leaveContentFullscreenSidebar()
            shell.contentFullscreen = false
            sidebarUI.pageFullscreen = false
        }
        enteredFullscreenForContent = false
        // Born in full screen: to the frame it would have had as a window.
        if let frame = leaveFullScreenTo {
            leaveFullScreenTo = nil
            window?.setFrame(frame, display: true, animate: true)
        }
        // Back at the frame it had before: zoomed or not.
        updateWindowFill()
        shell.needsLayout = true
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        leaveIfCovered()
    }

    /// Arc's autoPictureInPictureOnWindowOccluded: a window that isn't key and is completely out
    /// of sight (another app or desktop in front, minimised) sends its video to Picture in
    /// Picture, checked when it resigns key and when what covers it changes; the video comes home
    /// when the window is key again (windowDidBecomeKey). Arc 1.171, 2 Nov 2026: hiding an Arc that
    /// had not been active opened nothing; losing focus with its window on another desktop did.
    /// A locked screen covers every window and leaves nothing.
    private func leaveIfCovered() {
        guard let window, !window.isKeyWindow, !window.occlusionState.contains(.visible), !Self.screenIsLocked else { return }
        browsers.windowVisibilityChanged(covered: true)
    }

    /// Asked once, then kept by the system's lock and unlock notifications: the session query is a
    /// WindowServer round trip, and every occlusion change of a fullscreen window asked it (#136).
    private static let screenLock = ScreenLockState()
    private static var screenIsLocked: Bool { screenLock.isLocked }

    @MainActor private final class ScreenLockState {
        private(set) var isLocked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
        private var observers: [NSObjectProtocol] = []

        init() {
            let center = DistributedNotificationCenter.default()
            observers = [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)].map { name, locked in
                center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.isLocked = locked }
                }
            }
        }
    }

    /// The frame lives in the store's observed prefs, which every sidebar row reads (selection):
    /// it is stored once a resize or move settles, not on every step of it.
    private func saveFrame() {
        frameSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveFrameNow() }
        frameSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    private var frameSaveWork: DispatchWorkItem?

    /// Quit can arrive before the move/resize debounce fires.
    func saveFrameNow() {
        frameSaveWork?.cancel()
        frameSaveWork = nil
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        store.updateWindow(windowID) { $0.frame = NSStringFromRect(window.frame) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === window { commandBar.close() }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        LinkSummaryPreviewController.shared.stop()
        tabSwitcher.cancel()
        app.mainWindowWillClose(self)
    }

    override func showWindow(_ sender: Any?) {
        app.browserWindowWillShow(self)
        super.showWindow(sender)
    }

    /// ⌘Q put Cra in the menu bar (#231): the window is out of sight and its pages are closed, as
    /// on a quit; the tabs stay. No page opens until `bringBack`.
    private(set) var isPutAway = false

    func putAway() {
        guard !isPutAway else { return }
        isPutAway = true
        dismissTransientUI()
        sidePanel.hide()
        for p in peeks { p.closeWindow() }
        browsers.closeAll()
        guard let window else { return }
        // Out of full screen first: a full-screen window ordered out leaves its Space behind.
        if window.styleMask.contains(.fullScreen) {
            fullScreenExit = NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window,
                                                                    queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.orderOutPutAway() }
            }
            window.toggleFullScreen(nil)
        } else {
            window.orderOut(nil)
        }
    }

    private var fullScreenExit: NSObjectProtocol?

    private func orderOutPutAway() {
        if let fullScreenExit { NotificationCenter.default.removeObserver(fullScreenExit) }
        fullScreenExit = nil
        if isPutAway { window?.orderOut(nil) }
    }

    /// Back from the menu bar: the open tab's page loads again, as after a launch.
    func bringBack() {
        guard isPutAway else { return }
        isPutAway = false
        refresh()
    }

    /// The window closed while others stay open: its pages close (the tabs stay in
    /// the sidebar) and it lets go of everything that would keep it alive.
    func tearDown() {
        isTornDown = true
        dismissTransientUI()
        sidePanel.hide()
        for p in peeks { p.closeWindow() }
        // A page another window shows behind its blurred stand-in moves there with its history
        // and state; closed with this window, that window loaded it again from scratch.
        for id in Array(browsers.runtimes.keys) {
            guard let other = app.mainWindows.first(where: { $0 !== self && $0.isShowingElsewhere(id) }),
                  let rt = browsers.release(id) else { continue }
            other.takePage(rt)
        }
        browsers.closeAll()
        for card in shell.paneCards { card.pageTopGrabber.removeFromSuperview() }
        for monitor in [scrollMonitor, childClickMonitor, middleClickMonitor, imageClickMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        imageClickMonitor = nil
        scrollMonitor = nil
        childClickMonitor = nil
        middleClickMonitor = nil
        bookmarkDragObservers.forEach(NotificationCenter.default.removeObserver)
        bookmarkDragObservers = []
        floatingSidebar?.didHide = nil
        floatingSidebar?.hide(animated: false)
        floatingSidebar = nil
        for child in window?.childWindows ?? [] {
            window?.removeChildWindow(child)
            child.orderOut(nil)
        }
    }
}


/// Window with Arc's taller title row: the traffic lights sit 24pt from the top.
/// They always show in colour, like Dia (Arc mutes them to grey discs until hovered).
final class CraWindow: NSWindow {
    /// Escape that nothing in the window took (CraCore WindowEscape): its controller closes what is
    /// open. AppKit's own cancelOperation: took a full-screen window out of full screen.
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }

    /// AppKit's private per-button hook: the window buttons keep their colours
    /// while the window or the app is inactive. Nothing else about the window's
    /// inactive look changes.
    @objc(_hasActiveAppearanceForStandardWindowButton:)
    func hasActiveAppearance(forStandardWindowButton type: UInt) -> Bool { true }

    /// The real title bar is hidden under the content, so double-clicks on the
    /// header strip never reach AppKit's zoom handling. The SwiftUI header rows
    /// call this on a double-click of their empty parts; it performs the system
    /// "double-click a window's title bar" action from System Settings.
    /// `action` stands in for the system setting (scenarios: cra://debug?titleDoubleClick=Maximize).
    func performTitleDoubleClickAction(_ action: String? = nil) {
        guard !styleMask.contains(.fullScreen) else { return }
        let action = action ?? UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
        switch action {
        case "None": break
        case "Minimize": miniaturize(nil)
        default: zoom(nil)   // "Maximize" and "Fill"
        }
    }

    /// The strip above the content card (the window's inset margin) stands in for the
    /// title bar there. It reaches 4 pt into the toolbar card, above its buttons, so a
    /// press just past the card's edge still counts. Movable-by-background only drags,
    /// and the toolbar takes a click as "edit URL", so the strip's presses are handled
    /// here: a double-click runs the title bar action, anything else drags the window.
    /// Edge to edge there is no margin, so only the 4 pt reaching into the toolbar (or the page) is left.
    private var titleStripHeight: CGFloat {
        (contentView as? ShellView)?.edgeToEdge == true ? 4 : CraMetrics.contentInset + 4
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, WindowDragRegion.allows(event, in: self),
           let content = contentView, event.locationInWindow.y >= content.bounds.height - titleStripHeight,
           isTitleStrip(content.hitTest(content.convert(event.locationInWindow, from: nil))) {
            if event.clickCount == 2 { performTitleDoubleClickAction() } else { performDrag(with: event) }
            return
        }
        super.sendEvent(event)
    }

    /// The sidebar, web content and native controls handle their own presses. Content
    /// fullscreen also leaves no title strip to drag.
    private func isTitleStrip(_ view: NSView?) -> Bool {
        var v = view
        while let current = v {
            if current is SidebarView || current is NSControl || current is NSTextView
                || NSStringFromClass(type(of: current)) == "WebContentsViewCocoa" { return false }
            if let shell = current as? ShellView, shell.contentFullscreen { return false }
            v = current.superview
        }
        return view != nil
    }

    /// Arc hides the traffic lights with the sidebar; the floating sidebar carries its
    /// own set (FloatingSidebarController). Full screen keeps them in the revealed title bar.
    /// How long the buttons take to fade: the sidebar's slide (MainWindowController.dockingMotion).
    var trafficLightsFade: TimeInterval = SidebarMotion.duration
    var trafficLightsHidden = false {
        didSet { if trafficLightsHidden != oldValue { updateTrafficLights(animated: isVisible) } }
    }
    private var appliedTrafficLightsHidden = false

    private func updateTrafficLights(animated: Bool) {
        let hide = trafficLightsHidden && !styleMask.contains(.fullScreen)
        guard hide != appliedTrafficLightsHidden else { return }
        appliedTrafficLightsHidden = hide
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { standardWindowButton($0) }
        // Hidden buttons rest at alpha 1: AppKit refuses to miniaturize a window whose
        // minimize button has alpha 0 (⌘M and the floating sidebar's yellow button did nothing).
        guard animated else {
            for b in buttons { b.alphaValue = 1; b.isHidden = hide }
            return
        }
        if !hide { for b in buttons where b.isHidden { b.alphaValue = 0; b.isHidden = false } }
        // Same timing as the sidebar's slide (ShellView.animateSidebar).
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = trafficLightsFade
            for b in buttons { b.animator().alphaValue = hide ? 0 : 1 }
        } completionHandler: { [weak self] in
            guard let self, self.appliedTrafficLightsHidden == hide else { return }
            for b in buttons { b.isHidden = hide; b.alphaValue = 1 }
        }
    }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        positionTrafficLights()
        updateTrafficLights(animated: false)
    }

    override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        positionTrafficLights()
    }

    private func positionTrafficLights() {
        guard !styleMask.contains(.fullScreen) else { return }
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (i, type) in buttons.enumerated() {
            guard let b = standardWindowButton(type), let sv = b.superview else { continue }
            let x: CGFloat = 13 + CGFloat(i) * 24
            let y = sv.bounds.height - CraMetrics.titleRowCenter - b.frame.height / 2
            let target = NSPoint(x: x, y: y)
            if abs(b.frame.origin.x - target.x) > 0.5 || abs(b.frame.origin.y - target.y) > 0.5 {
                b.setFrameOrigin(target)
            }
        }
    }
}
