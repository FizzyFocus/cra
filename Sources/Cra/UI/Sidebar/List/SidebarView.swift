import AppKit
import SwiftUI

/// The whole left column in AppKit, laid out like Arc: traffic lights + sidebar toggle with the
/// nav buttons at the right of the top row, then the static chrome's favorites (global, never on
/// a space's page), the space pager (header, tab list), the update banner and the dock. The
/// Library takes the column over while it is open.
@MainActor
final class SidebarView: NSView {
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let actions: SidebarActions
    private let favicons: FaviconCache
    private let tabs = FlippedView()
    private let topBar: SidebarTopBarView

    /// The URL field's sliders button (screen rect), nil while the toolbar has it.
    var siteControlsButtonFrameOnScreen: NSRect? { topBar.siteControlsButtonFrameOnScreen }

    /// The swipe past the last space: the ring's fill, nil once it's over.
    func showCreateSwipe(_ fill: Double?) { createSwipe.show(fill: fill) }
    /// The URL field (screen rect), while the sidebar shows it.
    var urlFieldFrameOnScreen: NSRect? { topBar.urlFieldFrameOnScreen }
    /// The URL field's "Translation Available" (screen rect), nil while it isn't shown (#310).
    var translateFrameOnScreen: NSRect? { topBar.translateFrameOnScreen }
    /// The URL field's "Pop-ups Blocked" (#357), on the translate line's place.
    var blockedPopupsFrameOnScreen: NSRect? { topBar.translateFrameOnScreen }
    /// Scenario hook (#310): what the URL field's translate line says, nil while it isn't shown.
    var debugTranslateLine: String? { topBar.debugTranslateLine }
    /// Scenario hooks (#226): the URL field as if the pointer were over the header, and a press on
    /// one of its buttons. nil while the toolbar has the address.
    func debugURLFieldHover(_ on: Bool) -> [ToolbarComposition.Item]? { topBar.debugURLFieldHover(on) }
    func debugURLFieldPress(_ item: ToolbarComposition.Item) -> Bool { topBar.debugURLFieldPress(item) }
    private let pager: SpacePagerView
    /// Arc's top apps, pinned under the URL field outside the pager: still while spaces change.
    private let favorites: FavoritesGridView
    private let trayHost: DownloadsTrayView
    /// Swiping on past the last space: the ring that opens Create a Space (SpaceCreateSwipe).
    private let createSwipe = CreateSpaceSwipeIndicator()
    private let player: NowPlayingTrayView
    private let trayMask = CAGradientLayer()
    private let bannerHost = UpdateBannerView()
    private let dock: SpaceDockView
    private var libraryHost: LibraryView?
    /// Create a Space, in place of the favorites, the pager and the trays while it is open.
    private var createHost: NSHostingView<CreateSpaceSheet>?
    /// The views Create a Space stands in for.
    private var createCovers: [NSView] { [favorites, pager, player, trayHost, bannerHost] }
    /// The palette drawn now; the theme-shown scenario hook reads it (#155).
    private(set) var palette: SpacePalette
    private var lastSpaceID: UUID?
    private var shownTheme: SpaceTheme?
    private var shownLibrary: LibraryPage?

    init(store: SidebarStore, ui: SidebarUIState, actions: SidebarActions, favicons: FaviconCache) {
        self.store = store
        self.ui = ui
        self.actions = actions
        self.favicons = favicons
        palette = store.focusedSpace(window: ui.windowID).theme.palette
        topBar = SidebarTopBarView(store: store, ui: ui, actions: actions)
        pager = SpacePagerView(store: store, ui: ui, actions: actions, favicons: favicons)
        favorites = FavoritesGridView(store: store, ui: ui, actions: actions, favicons: favicons)
        trayHost = DownloadsTrayView(ui: ui)
        player = NowPlayingTrayView(store: store, ui: ui, favicons: favicons)
        dock = SpaceDockView(store: store, ui: ui, actions: actions)
        super.init(frame: .zero)
        wantsLayer = true
        pager.wantsLayer = true
        trayMask.startPoint = CGPoint(x: 0.5, y: 0)
        trayMask.endPoint = CGPoint(x: 0.5, y: 1)
        // The favorites above the pager: the strip slides under them.
        for v in [topBar, pager, favorites, player, trayHost, bannerHost, dock, createSwipe] as [NSView] { tabs.addSubview(v) }
        addSubview(tabs)
        favorites.onHeightChange = { [weak self] animated in self?.placeFavorites(animated: animated) }
        player.onCountChange = { [weak self] in self?.needsLayout = true }
        // A plain click anywhere in the sidebar that isn't a row, tile, button or control (its
        // background, a header, a divider, the space's name, a gutter) drops a ⌘/⇧-click tab
        // selection (11 Nov 2026). Seen before the click is handled; it goes on as it would.
        backgroundClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
            MainActor.assumeIsolated { self?.backgroundClick(e) }
            return e
        }
        ui.observeLibraryReveal { [weak self] in self?.applyLibraryReveal() }
        observe()
        observeRenameCard()
    }

    // MARK: Tidy Downloads' card

    private var renameCard: DownloadRenameCard?

    /// The card for a download this window renamed: in over the bin, out after 8 s or a click.
    private func observeRenameCard() {
        let window = ui.windowID
        observeChanges(of: { TidyDownloadsService.shared.card.flatMap { $0.window == window ? $0 : nil } }) { [weak self] card in
            self?.showRenameCard(card)
        }
    }

    private func showRenameCard(_ mine: TidyDownloadsService.Rename?) {
        guard mine?.id != renameCard?.rename.id else { return }
        if let old = renameCard {
            renameCard = nil
            old.disappear { old.removeFromSuperview() }
        }
        guard let r = mine else { return }
        let v = DownloadRenameCard(rename: r, colors: SidebarColors(palette))
        let service = TidyDownloadsService.shared
        let toast = actions.showToast
        let ui = self.ui
        v.onClose = { service.dismiss() }
        v.onHover = { service.hold($0) }
        v.onOpen = { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: r.newPath)]) }
        v.onRevert = {
            let ok = service.revert(r) { _, back in
                if var recent = ui.recentDownload, recent.id == r.download {
                    recent.path = back
                    ui.recentDownload = recent
                }
            }
            if ok { toast("Download name reverted!") }
        }
        tabs.addSubview(v)
        renameCard = v
        layoutRenameCard()
        v.appear()
    }

    private func layoutRenameCard() {
        guard let v = renameCard, let anchor = ui.libraryAnchor as? LibraryButtonView else { return }
        let bin = anchor.convert(anchor.binFrame, to: tabs)
        // Arc: the tail's tip ends 1 pt above the bin's 38 pt box, ~4 pt above its 32 pt thumbnail.
        let w = tabs.bounds.width - 16
        v.frame = NSRect(x: 8, y: bin.minY - 4 - DownloadRenameCard.height, width: w, height: DownloadRenameCard.height)
        v.tailX = bin.midX - 8
    }

    deinit { backgroundClickMonitor.map(NSEvent.removeMonitor) }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func observe() {
        var bannerHeight: CGFloat = 0
        var creating: CreateSpaceModel?
        let (space, library, trayOpen, recentCount) = withObservationTracking {
            let space = store.focusedSpace(window: ui.windowID)
            _ = SystemAppearance.shared.isDark
            bannerHeight = UpdateBannerView.preferredHeight
            creating = ui.creatingSpace
            return (space, ui.libraryPage, ui.downloadsListOpen, DownloadHistory.shared.recent.count)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        let paletteChanged = lastSpaceID == nil || space.theme.shown != shownTheme || space.id != lastSpaceID
        shownTheme = space.theme.shown
        if space.id != lastSpaceID {
            // A drag that hovered another space's icon carries the picks there; its end clears them.
            if lastSpaceID != nil, ui.draggingID == nil { ui.clearPicks() }
            lastSpaceID = space.id
        }
        if paletteChanged || palette.isDark != space.theme.palette.isDark {
            palette = space.theme.palette
            let colors = SidebarColors(palette)
            trayHost.colors = colors
            createSwipe.colors = colors
            bannerHost.colors = colors
            let shown = space.theme.shown
            bannerHost.themeColor = shown.accent ?? shown.colors.first
            player.setTheme(shown.accent ?? shown.colors.first, dark: palette.isDark)
            libraryHost?.palette = palette
        }
        self.bannerHeight = bannerHeight
        updateTrayMask(open: trayOpen, rows: recentCount)
        showLibrary(library)
        showCreateSpace(creating)
        needsLayout = true
    }

    // MARK: Create a Space

    /// Create a Space comes in where the favorites and the tab list were, which fade out under it;
    /// the top row and the dock stay. Closing gives them back.
    private func showCreateSpace(_ model: CreateSpaceModel?) {
        guard model !== createHost?.rootView.model else { return }
        if let old = createHost {
            createHost = nil
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                old.animator().alphaValue = 0
                for v in createCovers { v.isHidden = false; v.animator().alphaValue = 1 }
            } completionHandler: {
                old.removeFromSuperview()
            }
            // The downloads tray shows only with downloads to list (updateTrayMask's rule).
            trayHost.isHidden = DownloadHistory.shared.recent.isEmpty
        }
        guard let model else { return }
        let host = NSHostingView(rootView: CreateSpaceSheet(model: model))
        host.sizingOptions = []
        model.toScreen = { [weak host] r in
            guard let host, let window = host.window else { return nil }
            // SwiftUI's global space is the hosting view's own, flipped like it.
            return window.convertToScreen(host.convert(r, to: nil))
        }
        tabs.addSubview(host)
        createHost = host
        layoutCreateHost()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for v in createCovers { v.animator().alphaValue = 0 }
        } completionHandler: { [weak self] in
            // Faded isn't gone: the favorites' tooltips and the list's hover would still answer.
            guard let self, self.createHost === host else { return }
            for v in self.createCovers { v.isHidden = true }
        }
    }

    /// Between the top row and the dock.
    private func layoutCreateHost() {
        guard let host = createHost else { return }
        let top = topBar.frame.maxY
        host.frame = NSRect(x: 0, y: top, width: tabs.bounds.width, height: max(0, dock.frame.minY - 6 - top))
    }

    private var bannerHeight: CGFloat = 0

    /// DownloadsTrayMask: the tab list is hidden from 3 pt above the downloads list's first row
    /// and fades back in over the 170 pt above that.
    private func updateTrayMask(open: Bool, rows: Int) {
        let h = max(pager.bounds.height, 1)
        let clearTop = max(0, h - DownloadsTrayMetrics.listHeight(rows: rows) - DownloadsTrayMetrics.bottomClearance - 3)
        let fadeTop = max(0, clearTop - DownloadsTrayMetrics.fade)
        CATransaction.begin()
        CATransaction.setAnimationDuration(open ? 0.18 : 0.13)
        if !open { CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut)) }
        trayMask.frame = pager.bounds
        trayMask.locations = [0, NSNumber(value: Double(fadeTop / h)), NSNumber(value: Double(clearTop / h)), 1]
        let opaque = NSColor.black.cgColor, clear = NSColor.clear.cgColor
        trayMask.colors = open ? [opaque, opaque, clear, clear] : [opaque, opaque, opaque, opaque]
        CATransaction.commit()
        if pager.layer?.mask !== trayMask { pager.layer?.mask = trayMask }
        trayHost.isHidden = rows == 0
    }

    /// The Library takes over the column: in from a little to the left, out to the left past its
    /// rail while the tab list fades back in.
    private func showLibrary(_ page: LibraryPage?) {
        guard page != shownLibrary, ui.libraryReveal == nil else { return }
        let opening = shownLibrary == nil && page != nil
        shownLibrary = page
        if let page {
            let host = libraryHost ?? makeLibraryHost(page)
            host.page = page
            host.frame = bounds
            if opening {
                host.alphaValue = 0
                host.frame = bounds.offsetBy(dx: -24, dy: 0)
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.05
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                host.animator().alphaValue = 1
                host.animator().frame = bounds
                tabs.animator().alphaValue = 0
            }
            // Faded out isn't gone: the favorites' tracking areas would still show their tooltips and
            // preview cards through the Library. Hidden once the 0.05 s fade is over (a timer, as an
            // animation's completion can wait while the window is off screen).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                guard let self, self.shownLibrary != nil, self.ui.libraryReveal == nil else { return }
                self.tabs.isHidden = true
                CraLog.note("library covers the tab list")
            }
        } else if let host = libraryHost {
            libraryHost = nil
            tabs.isHidden = false
            if ui.libraryCloseCut {
                // ⇧⌘L: the drawer closed over the Library; the tab list is simply there.
                ui.libraryCloseCut = false
                host.removeFromSuperview()
                tabs.alphaValue = 1
                return
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                host.animator().alphaValue = 0
                host.animator().frame = bounds.offsetBy(dx: -LibraryMetrics.rail, dy: 0)
                tabs.animator().alphaValue = 1
            } completionHandler: {
                host.removeFromSuperview()
            }
        }
    }

    private func makeLibraryHost(_ page: LibraryPage) -> LibraryView {
        let h = LibraryView(page: page, palette: palette, store: store, ui: ui, actions: actions, favicons: favicons)
        addSubview(h)
        libraryHost = h
        return h
    }

    /// A swipe's reveal `r` (SidebarUIState.libraryReveal): the Library is the page before the
    /// first space and the two slide side by side like space pages while the sidebar widens under
    /// them (LibrarySwipe). Each keeps its own width, so neither lays out again as it moves. Once
    /// the swipe has landed the window controller has set the page, and the column takes that state.
    private func applyLibraryReveal() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let r = ui.libraryReveal else {
            layer?.masksToBounds = false
            tabs.setFrameOrigin(.zero)
            if let page = ui.libraryPage {
                let host = libraryHost ?? makeLibraryHost(page)
                host.page = page
                host.alphaValue = 1
                host.frame = bounds
                tabs.alphaValue = 0
                tabs.isHidden = true
                if shownLibrary != page { host.focusSearch() }
                shownLibrary = page
            } else {
                libraryHost?.removeFromSuperview()
                libraryHost = nil
                tabs.alphaValue = 1
                tabs.isHidden = false
                shownLibrary = nil
            }
            return
        }
        let page = ui.libraryPage ?? ui.libraryRevealPage
        let host = libraryHost ?? makeLibraryHost(page)
        host.page = page
        host.alphaValue = 1
        tabs.alphaValue = 1
        tabs.isHidden = false
        // Neither page shows outside the column, under the card's inset.
        layer?.masksToBounds = true
        let base = ui.libraryRevealBase, library = ui.libraryRevealWidth
        host.frame = NSRect(x: LibrarySwipe.libraryX(reveal: r, base: base, library: library), y: 0, width: library, height: bounds.height)
        tabs.frame = NSRect(x: LibrarySwipe.spaceX(reveal: r, base: base, library: library), y: 0, width: base, height: bounds.height)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let host = libraryHost {
            // `point` is in the superview's space; the host sits in this (flipped) view's.
            let p = convert(point, from: superview)
            return host.hitTest(p) ?? (bounds.contains(p) ? self : nil)
        }
        return super.hitTest(point)
    }

    override func layout() {
        super.layout()
        if ui.libraryReveal == nil {
            tabs.frame = bounds
            libraryHost?.frame = bounds
            libraryHost?.heldWidth = ui.libraryHeldWidth
        } else {
            applyLibraryReveal()
        }
        // The column's own size: during a Library swipe it keeps the sidebar's width as that widens.
        let b = tabs.bounds
        let th = topBar.preferredHeight
        topBar.frame = NSRect(x: 0, y: 0, width: b.width, height: th)
        // Arc's list viewport ends 50 pt above the window bottom; the dock sits centred in that band.
        let dockH: CGFloat = 36
        dock.frame = NSRect(x: 10, y: b.height - 6 - dockH, width: b.width - 20, height: dockH)
        let bannerTop = b.height - 6 - dockH - 8 - bannerHeight
        bannerHost.frame = NSRect(x: 0, y: bannerTop, width: b.width, height: bannerHeight)
        // The player rests where the list ends and takes that room from it; opened, it grows over the list.
        player.frame = NSRect(x: 0, y: th, width: b.width, height: max(0, bannerTop - th))
        let listBottom = bannerTop - NowPlayingMetrics.restHeight(cards: player.shownCount)
        pager.frame = NSRect(x: 0, y: th, width: b.width, height: max(0, listBottom - th))
        placeFavorites(animated: false)
        layoutCreateHost()
        let rows = DownloadHistory.shared.recent.count
        // The rows end just above the list's area; the view runs on down to the Library button
        // (4 pt into the dock), so moving up from the button to the rows never leaves it (11 Nov
        // 2026: the empty strip between closed the list on the way). Only the rows take clicks.
        let listTop = pager.frame.maxY - (DownloadsTrayMetrics.listHeight(rows: rows) + 2) - DownloadsTrayMetrics.bottomClearance
        trayHost.frame = NSRect(x: 0, y: listTop, width: b.width, height: max(0, dock.frame.minY + 4 - listTop))
        // At the column's right edge, where the strip pulls away past the last space.
        let side = CreateSpaceSwipeIndicator.side
        createSwipe.frame = NSRect(x: b.width - side - 16, y: (pager.frame.midY - side / 2).rounded(), width: side, height: side)
        updateTrayMask(open: ui.downloadsListOpen, rows: rows)
        if renameCard?.layer?.animationKeys()?.isEmpty ?? true { layoutRenameCard() }
    }

    private var backgroundClickMonitor: Any?

    private func backgroundClick(_ e: NSEvent) {
        guard !ui.multiSelection.isEmpty, e.modifierFlags.intersection([.command, .shift]).isEmpty,
              let w = window, e.window === w, let root = w.contentView?.superview ?? w.contentView else { return }
        let hit = root.hitTest(root.convert(e.locationInWindow, from: nil))
        _ = clearPicksIfBackground(hit)
    }

    /// The sidebar's own clickable things: a plain click on them does what it does (a tab row
    /// selects just its tab), so the picks are theirs to handle.
    private static func isInteractive(_ v: NSView) -> Bool {
        v is TabRowView || v is FolderRowView || v is SplitRowView || v is NewTabRowView || v is GroupHeaderRowView
            || v is LiveStatusRowView || v is PinPlaceholderRowView || v is NSControl || v is SidebarGlyphButton
            || v is FavoriteTileView || v is SidebarURLPill || v is LibraryButtonView || v is DownloadsTrayView
            || v is NowPlayingCardView || v is LibraryView || v is BookmarkOutlineView || v is FavoritesEmptyCard
            || v is SpaceDockView || v is NSScroller || v is NSTextView
    }

    /// A click landed on `hit`: in the sidebar and on nothing interactive, the picks go.
    @discardableResult
    func clearPicksIfBackground(_ hit: NSView?) -> Bool {
        guard let hit, hit === self || hit.isDescendant(of: self) else { return false }
        var v: NSView? = hit
        while let x = v, x !== self {
            if Self.isInteractive(x) { return false }
            v = x.superview
        }
        guard !ui.multiSelection.isEmpty else { return false }
        ui.clearPicks()
        CraLog.note("tab picks cleared: a click on the sidebar's \(type(of: hit))")
        return true
    }

    /// `cra://debug?downloadsGeometry=`: the open list's rows, the gap from its last row to the dock,
    /// and whether its hover area reaches down into the dock (no dead strip on the way up).
    func debugDownloadsHit(_ label: String) {
        layoutSubtreeIfNeeded()
        let h = ui.downloadsTray?.debugHits() ?? (gap: "-", below: "-")
        CraLog.note("downloads list hit \(label): gap=\(h.gap) below=\(h.below)")
    }

    func debugDownloadsGeometry(_ label: String) {
        layoutSubtreeIfNeeded()
        let rows = DownloadHistory.shared.recent.count
        let lastBottom = trayHost.frame.minY + 2 + DownloadsTrayMetrics.listHeight(rows: rows)
        let gap = dock.frame.minY - lastBottom
        let reaches = trayHost.frame.maxY >= dock.frame.minY
        CraLog.note("downloads list \(label): rows=\(rows) gapToDock=\(Int(gap.rounded())) reachesButton=\(reaches ? 1 : 0) open=\(ui.downloadsListOpen ? 1 : 0)")
    }

    /// The favorites where the space pages used to carry them: from the pager's top, 8 pt in from
    /// both sides. Each page leaves their room above its header (SpaceColumnView.place). A row
    /// coming or going, or a drag opening the "Add to Favorites" strip, moves the pages' headers
    /// and lists on Arc's 0.15 s ease-out; a list swapped for another lands in one frame.
    private func placeFavorites(animated: Bool) {
        let w = max(0, tabs.bounds.width - 16)
        let f = NSRect(x: 8, y: pager.frame.minY, width: w, height: favorites.height(forWidth: w))
        let bottom = favorites.tilesBottom(forWidth: w)
        guard animated, window != nil else {
            if favorites.frame != f { favorites.frame = f }
            pager.setFavoritesBottom(bottom, animated: false)
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            favorites.animator().frame = f
            pager.setFavoritesBottom(bottom, animated: true)
        }
    }
}

/// A container that lays its subviews out from the top.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Top bar

/// Row 1: traffic lights, the sidebar toggle right after them, nav buttons right-aligned. When
/// the toolbar is hidden the URL pill moves into the sidebar on a second row.
///
/// Toolbar hidden, measured on Arc 1.170 (window capture and AX tree, 26 Oct): toggle and
/// ← → ↻ are 32 pt buttons centred 1 pt above the traffic lights, the nav buttons 2 pt apart
/// and 6 pt from the sidebar edge, no ⌄ menu. The URL pill spans the sidebar 8 pt in from each
/// side, 36 pt tall, 2 pt under the title area, radius 10, the bare host in 13 pt at 12 pt in.
/// Its accessories (pinned extensions, copy link, site controls) show while the header is hovered.
/// Pins that would crowd the address out move to a grid over the favorites instead, as in Arc
/// 1.171 (PinnedExtensionGrid.fitsInURLField, FavoritesGridView; 4 Nov).
final class SidebarTopBarView: NSView {
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let actions: SidebarActions
    private var colors = SidebarColors()
    private var compact = false
    /// Toolbar hidden and the sidebar under 214 pt: ← → ••• with no toggle (#287).
    private var narrow = false
    /// The sidebar is under 212 pt, whatever the header carries.
    private var narrowWidth = false
    private var toggleShown = true
    private var morePanel: SidebarMorePanel?
    private var devNav = false
    private var fullscreen = false
    private var buttons: [String: SidebarGlyphButton] = [:]
    private var rowButtons: [SidebarGlyphButton] = []
    private var chevron: NSView?
    private let pill = SidebarURLPill()

    /// The URL field (screen rect); nil while it isn't shown (the toolbar has it).
    var urlFieldFrameOnScreen: NSRect? {
        guard !pill.isHiddenOrHasHiddenAncestor, let window else { return nil }
        return window.convertToScreen(pill.convert(pill.bounds, to: nil))
    }

    /// Where the URL field's sliders button is or appears on hover (screen rect): its last
    /// accessory, 28 pt ending 5 pt in. nil while the field isn't shown (the toolbar has it).
    var siteControlsButtonFrameOnScreen: NSRect? {
        guard !pill.isHiddenOrHasHiddenAncestor, let window else { return nil }
        let f = window.convertToScreen(pill.convert(pill.bounds, to: nil))
        return NSRect(x: f.maxX - 5 - 28, y: f.minY + (f.height - 28) / 2, width: 28, height: 28)
    }
    private var hoverHeader = false { didSet { if hoverHeader != oldValue { pill.showAccessories = hoverHeader } } }

    func debugURLFieldHover(_ on: Bool) -> [ToolbarComposition.Item]? {
        hoverHeader = on
        layoutSubtreeIfNeeded()
        return pill.isHidden ? nil : pill.shownItems
    }

    func debugURLFieldPress(_ item: ToolbarComposition.Item) -> Bool { !pill.isHidden && pill.debugPress(item) }
    private var syncQueued = false

    var preferredHeight: CGFloat { CraMetrics.titleAreaHeight + (compact ? 2 + pill.height + 8 : 0) }

    var translateFrameOnScreen: NSRect? {
        guard !pill.isHiddenOrHasHiddenAncestor, let window, let f = pill.translateFrame else { return nil }
        return window.convertToScreen(pill.convert(f, to: nil))
    }
    var debugTranslateLine: String? { pill.isHidden ? nil : pill.translateTitle }

    init(store: SidebarStore, ui: SidebarUIState, actions: SidebarActions) {
        self.store = store
        self.ui = ui
        self.actions = actions
        super.init(frame: .zero)
        pill.actions = actions
        addSubview(pill)
        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // The floating panel and the window place the toggle differently in fullscreen.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }

    private func sync() {
        syncQueued = false
        withObservationTracking { apply() } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.syncQueued else { return }
                self.syncQueued = true
                self.sync()
            }
        }
    }

    private func button(_ key: String, symbol: String, help: String, size: CGFloat, height: CGFloat, iconSize: CGFloat,
                        weight: NSFont.Weight = .regular, active: Bool?, enabled: Bool = true, animated: Bool = false,
                        action: @escaping () -> Void) -> SidebarGlyphButton {
        let b = buttons[key] ?? {
            let b = SidebarGlyphButton(symbol: symbol, size: size, height: height, iconSize: iconSize, weight: weight, help: help, colors: colors, action: action)
            buttons[key] = b
            addSubview(b)
            return b
        }()
        b.setSymbol(symbol, iconSize: iconSize, weight: weight, help: help, animated: animated)
        b.colors = colors
        b.active = active
        b.enabled = enabled
        b.action = action
        return b
    }

    private func apply() {
        let wasCompact = compact
        let wasHeight = preferredHeight
        compact = !store.settings.showToolbar
        colors = SidebarColors(store.focusedSpace(window: ui.windowID).theme.palette)
        let tab = store.selectedTab(window: ui.windowID)
        devNav = !compact && (tab?.tab.map { store.settings.isDeveloperMode(url: $0.url) } ?? false)
        let active = ui.appActive
        let reloadSymbol = ui.isLoading ? "xmark" : "arrow.clockwise"
        fullscreen = ui.windowFullscreen
        // Arc 1.171: the header always carries the sidebar toggle; the toolbar has one only while the
        // sidebar is hidden (PaneToolbarView), so a floating sidebar shows both.
        let help = store.window(ui.windowID).sidebarVisible ? "Hide Sidebar (⌘S)" : "Show Sidebar (⌘S)"
        // Below 212 pt Arc's header goes narrow (#287): where it carries ← → ↻ (toolbar hidden, or
        // a Developer Mode page) the toggle goes and ← → ••• take its place, Reload and Toggle
        // Sidebar under the •••; with only the toggle, the toggle shrinks to 28 pt.
        narrowWidth = SidebarHeaderLayout.isNarrow(width: Double(bounds.width))
        narrow = (compact || devNav) && narrowWidth
        if !narrow, let p = morePanel {
            morePanel = nil
            p.onClose = nil
            p.dismiss()
        }
        let toggle = narrowWidth
            ? button("toggleS", symbol: "sidebar.left", help: help, size: 28, height: 28, iconSize: 15.5, active: active) { [weak self] in self?.actions.toggleSidebar() }
            : button("toggle", symbol: "sidebar.left", help: help, size: 32, height: 32, iconSize: 15.5, active: active) { [weak self] in self?.actions.toggleSidebar() }
        var shown = narrow ? [] : [toggle]
        if narrow {
            shown.append(button("nback", symbol: "arrow.left", help: "Go Back (⌘[)", size: 28, height: 28, iconSize: 15, active: active, enabled: ui.canGoBack) { [weak self] in self?.actions.goBack() })
            shown.append(button("nforward", symbol: "arrow.right", help: "Go Forward (⌘])", size: 28, height: 28, iconSize: 15, active: active, enabled: ui.canGoForward) { [weak self] in self?.actions.goForward() })
            shown.append(button("more", symbol: morePanel == nil ? "ellipsis" : "xmark", help: "More options", size: 28, height: 28, iconSize: 15,
                                weight: .semibold, active: active) { [weak self] in self?.toggleMorePanel() })
        } else if compact {
            shown.append(button("back", symbol: "arrow.left", help: "Go Back (⌘[)", size: 32, height: 32, iconSize: 15, active: active, enabled: ui.canGoBack) { [weak self] in self?.actions.goBack() })
            shown.append(button("forward", symbol: "arrow.right", help: "Go Forward (⌘])", size: 32, height: 32, iconSize: 15, active: active, enabled: ui.canGoForward) { [weak self] in self?.actions.goForward() })
            shown.append(button("reload", symbol: reloadSymbol, help: "Refresh (⌘R)", size: 32, height: 32, iconSize: 15, active: active, animated: true) { [weak self] in self?.actions.reload() })
        } else if devNav {
            shown.append(button("dback", symbol: "arrow.left", help: "Go Back (⌘[)", size: 34, height: 28, iconSize: 15, active: nil, enabled: ui.canGoBack) { [weak self] in self?.actions.goBack() })
            shown.append(button("dforward", symbol: "arrow.right", help: "Go Forward (⌘])", size: 34, height: 28, iconSize: 15, active: nil, enabled: ui.canGoForward) { [weak self] in self?.actions.goForward() })
            shown.append(button("dreload", symbol: reloadSymbol, help: "Refresh (⌘R)", size: 24, height: 24, iconSize: 15, active: nil, animated: true) { [weak self] in self?.actions.reload() })
        }
        for (k, b) in buttons where !shown.contains(where: { $0 === b }) {
            b.removeFromSuperview()
            buttons[k] = nil
        }
        rowButtons = shown
        toggleShown = !narrow
        if devNav, !narrow, chevron == nil {
            let c = DevMenuChevron(actions: actions)
            addSubview(c)
            chevron = c
        } else if !devNav || narrow, let c = chevron {
            c.removeFromSuperview()
            chevron = nil
        }
        (chevron as? DevMenuChevron)?.tint = colors.textTertiary
        pill.isHidden = !compact
        if compact, ui.pageFullscreen {
            // Arc 1.172: with a page in full screen the pill is its way out.
            pill.showExitFullscreen(colors: colors)
        } else if compact {
            let url = tab?.tab?.url ?? ""
            let host = URL(string: url)?.host ?? ""
            let text = tab == nil ? "Search or Enter URL…" : (host.isEmpty ? SuggestionEngine.humanURL(url) : host.replacingOccurrences(of: "www.", with: ""))
            let ext = ExtensionStore.shared
            let profile = tab.map { store.profileDirectoryName(item: $0.id) }
                ?? store.profileDirectoryName(space: store.focusedSpaceID(window: ui.windowID))
            let entries = ext.entries(inProfile: profile)
            let pinned = ext.pinnedIDs(inProfile: profile).compactMap { id in
                entries.first { $0.extensionID == id }.map {
                    (id, $0.name, ext.badged(ext.toolbarIcon(for: $0, profile: profile, tab: tab?.id),
                                             ext.badge(for: $0, profile: profile, tab: tab?.id), tint: colors.textSecondary))
                }
            }
            let translation = tab.flatMap { ui.navState(for: $0.id).translation }
            // Blocked pop-ups (#357) take the translate line while they wait: they go with the
            // page's next navigation.
            let popups = tab.map { ui.navState(for: $0.id).blockedPopups } ?? 0
            let line = popups > 0 ? BlockedPopups.buttonTitle(count: popups)
                : translation?.offersTranslation == true ? (narrowWidth ? "Translate" : "Translation Available") : nil
            pill.show(text: text, url: url, hasTab: tab != nil, colors: colors, active: active,
                      pinned: pinned, protectedMedia: tab.flatMap { ui.navState(for: $0.id).protectedMedia },
                      translate: line)
            let tabID = tab?.id
            pill.onTranslate = { [weak self] in
                guard let self, let tabID else { return }
                if popups > 0 { self.actions.showBlockedPopups(tabID, self.translateFrameOnScreen) }
                else { self.actions.showTranslate(tabID, self.translateFrameOnScreen) }
            }
        }
        needsLayout = true
        if wasCompact != compact || wasHeight != preferredHeight { superview?.superview?.needsLayout = true }
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        // A drag across 212 pt swaps the header's layout (#287).
        if SidebarHeaderLayout.isNarrow(width: Double(w)) != narrowWidth { apply() }
        // Row 1: 71 pt for the traffic lights, then the toggle. In fullscreen the lights belong to
        // the menu bar's title bar, never the sidebar (anchored or floating), and Arc draws the
        // toggle from 20 pt in (glyph 20–38.5 pt). It moves left to stay 2 pt clear of ← when the
        // sidebar is just wide enough for both.
        let lights = !fullscreen
        // Full screen in or out: the toggle glides into the lights' place or out of it instead of
        // jumping. Started as the window's transition starts and over well before it ends, so the
        // lights coming back on the way out never land on it.
        let docking = laidOutLights.map { $0 != lights } == true && window != nil
        laidOutLights = lights
        let nav = toggleShown ? Array(rowButtons.dropFirst()) : rowButtons
        let afterLights: CGFloat = lights ? 6 + 71 + 2 : 13
        var toggleFrame: NSRect?
        if toggleShown, let t = rowButtons.first {
            let size = t.size.width
            toggleFrame = NSRect(x: afterLights, y: CraMetrics.titleRowCenter - 1 - size / 2, width: size, height: size)
        }
        if narrow {
            for (b, box) in zip(nav, SidebarHeaderLayout.navButtons(width: Double(w))) {
                b.frame = NSRect(x: box.x, y: CraMetrics.titleRowCenter - 1 - box.size / 2, width: box.size, height: box.size)
            }
        }
        if compact {
            // ← → ↻ 2 pt apart (32 pt), or ← → ••• touching (28 pt) when narrow; 6 pt from the
            // edge, centred on the same line.
            if !narrow {
                for (b, box) in zip(nav, SidebarHeaderLayout.navButtons(width: Double(w))) {
                    b.frame = NSRect(x: box.x, y: CraMetrics.titleRowCenter - 1 - box.size / 2, width: box.size, height: box.size)
                }
            }
            pill.frame = NSRect(x: 8, y: CraMetrics.titleAreaHeight + 2, width: w - 16, height: pill.height)
        } else if devNav, !narrow {
            let y = CraMetrics.titleRowCenter - 14
            var x = w - 6
            if let c = chevron {
                x -= 12
                c.frame = NSRect(x: x, y: y, width: 12, height: 28)
            }
            for b in nav.reversed() {
                x -= b.size.width
                b.frame = NSRect(x: x, y: y + (28 - b.size.height) / 2, width: b.size.width, height: b.size.height)
            }
        }
        // The toggle steps left to stay 2 pt clear of ← (Arc, #287).
        if toggleShown, compact || devNav, !narrow {
            toggleFrame?.origin.x = SidebarHeaderLayout.toggleX(width: Double(w), afterLights: afterLights, developer: devNav)
        }
        if let t = rowButtons.first, let f = toggleFrame { placeToggle(t, at: f, docking: docking) }
    }

    /// Whether the last layout left room for the traffic lights (nil before the first).
    private var laidOutLights: Bool?
    private static let dockDuration: TimeInterval = 0.22

    private func placeToggle(_ toggle: NSView, at f: NSRect, docking: Bool) {
        guard docking else {
            // Layout passes during a glide (the window resizing under it) leave it to finish.
            if toggle.frame != f { toggle.frame = f }
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.dockDuration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            ctx.allowsImplicitAnimation = true
            toggle.animator().frame = f
        }
    }

    /// The narrow header's ••• (Arc 1.17x, #287): Reload and Toggle Sidebar with their shortcuts,
    /// in a popover under the button, which shows ✕ while it's open.
    private func toggleMorePanel() {
        if let p = morePanel { p.dismiss(); return }
        guard let window, let b = buttons["more"] else { return }
        let keys = { (id: String) in KeyBindingRegistry.shared.action(id)?.primary?.caps ?? [] }
        let hasTab = store.selectedTab(window: ui.windowID) != nil
        let panel = SidebarMorePanel(items: [
            .init(symbol: "arrow.clockwise", title: "Reload", keys: keys("reload"), enabled: hasTab) { [weak self] in self?.actions.reload() },
            .init(symbol: "sidebar.left", title: "Toggle Sidebar", keys: keys("toggleSidebar"), enabled: true) { [weak self] in self?.actions.toggleSidebar() },
        ], ink: store.focusedSpace(window: ui.windowID).theme.shadedDark)
        panel.onClose = { [weak self] in
            self?.morePanel = nil
            self?.apply()
        }
        morePanel = panel
        panel.show(under: window.convertToScreen(b.convert(b.bounds, to: nil)), in: window)
        apply()
    }

    // A double click on the empty strip does the title bar's double-click action; a drag moves
    // the window (from the floating sidebar too, without tearing its panel off).
    override var mouseDownCanMoveWindow: Bool { false }
    private var press = WindowDragGesture()
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, convert(event.locationInWindow, from: nil).y < CraMetrics.titleAreaHeight {
            _ = press.finish()
            actions.titleBarDoubleClick()
            return
        }
        press.begin(event)
    }
    override func mouseDragged(with event: NSEvent) { press.drag(event) }
    override func mouseUp(with event: NSEvent) { _ = press.finish() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hoverHeader = true }
    override func mouseExited(with event: NSEvent) { hoverHeader = false }
}

/// The ⌄ after the developer-mode nav buttons: page actions in a menu.
private final class DevMenuChevron: NSView {
    private let actions: SidebarActions
    private let image = NSImageView()
    var tint: NSColor = .tertiaryLabelColor { didSet { image.contentTintColor = tint } }

    init(actions: SidebarActions) {
        self.actions = actions
        super.init(frame: .zero)
        image.image = SidebarSymbols.image("chevron.down", size: 8, weight: .bold)
        image.imageScaling = .scaleNone
        image.autoresizingMask = [.width, .height]
        addSubview(image)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }
    override func layout() {
        super.layout()
        image.frame = bounds
    }

    override func mouseDown(with event: NSEvent) {
        let m = NSMenu()
        m.autoenablesItems = false
        let a = actions
        // Arc's menu (Reload ✓ ⌘R, Refresh (Ignore Cache) ⇧⌘R | Clear Cookies and Refresh) in the
        // registry's words, with Clear Cache beside Clear Cookies and Cra's developer items under
        // them (#89).
        for group in [["reload", "hardReload"], ["clearCookies", "clearCache"], ["viewSource", "devTools"]] {
            if m.numberOfItems > 0 { m.addItem(.separator()) }
            for id in group { MenuItems.add(m, action: id, on: id == "reload" ? true : nil) { a.performAction(id) } }
        }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: self)
    }
}

/// The URL pill on the sidebar's second row while the toolbar is hidden.
final class SidebarURLPill: NSView {
    var actions: SidebarActions?
    var showAccessories = false { didSet { if showAccessories != oldValue { refreshAccessories(animated: true) } } }
    private let label = NSTextField.sidebarLabel(size: 13)
    private let tip: ArcTooltipAnchorView
    private var accessories: [NSView] = []
    /// What each of `accessories` is, in order.
    private(set) var shownItems: [ToolbarComposition.Item] = []
    private var hovering = false { didSet { if hovering != oldValue { refreshFill() } } }
    private var colors = SidebarColors()
    private var hasTab = false
    /// Scenarios (cra://debug?hover=SidebarURLPill): the pill as the pointer leaves it hovered (#293).
    func debugHover() { hovering = true }
    private var model: (pinned: [(String, String, NSImage?)], active: Bool)?

    override init(frame: NSRect) {
        tip = ArcTooltipAnchorView(frame: .zero)
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        label.lineBreakMode = .byTruncatingMiddle
        addSubview(label)
        translateLine.isHidden = true
        tip.followsCursor = true
        tip.autoresizingMask = [.width, .height]
        addSubview(tip)
        addSubview(translateLine)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    /// "Exit Fullscreen" with Arc's ⤡ while a page in this window is in full screen; a click leaves it.
    private(set) var exitsFullscreen = false
    private lazy var exitGlyph: NSImageView = {
        let v = NSImageView()
        v.imageScaling = .scaleNone
        return v
    }()

    func showExitFullscreen(colors: SidebarColors) {
        exitsFullscreen = true
        self.colors = colors
        hasTab = true
        tip.text = ""
        label.stringValue = "Exit Fullscreen"
        // One line: no "Translation Available" under it.
        translateLine.isHidden = true
        label.textColor = colors.textPrimary
        exitGlyph.image = SidebarSymbols.image("arrow.down.right.and.arrow.up.left", size: 11, weight: .medium)
        exitGlyph.contentTintColor = colors.textSecondary
        if exitGlyph.superview == nil { addSubview(exitGlyph) }
        exitGlyph.isHidden = false
        model = ([], false)
        accessories.forEach { $0.removeFromSuperview() }
        accessories = []
        shownItems = []
        refreshFill()
        needsLayout = true
    }

    /// Arc's "Translation Available" under the address (#310): a second line in the field, the
    /// address's left edge, 17 pt tall, opening the translate popover. Arc 1.17x AX (10 Nov): the
    /// address at 6 pt from the field's top, the line at 23 pt, the tab list 2 pt under it.
    private let translateLine = TranslateLineButton()
    var onTranslate: () -> Void = {}
    var translateTitle: String? { translateLine.isHidden ? nil : translateLine.title }
    var translateFrame: NSRect? { translateLine.isHidden ? nil : translateLine.frame }
    /// 36 pt, or 42 with the translate line.
    var height: CGFloat { translateLine.isHidden ? 36 : 42 }

    func show(text: String, url: String, hasTab: Bool, colors: SidebarColors, active: Bool,
              pinned: [(String, String, NSImage?)], protectedMedia: String? = nil, translate: String? = nil) {
        exitsFullscreen = false
        exitGlyph.isHidden = true
        self.protectedMedia = protectedMedia
        translateLine.isHidden = translate == nil
        translateLine.title = translate ?? ""
        translateLine.tint = colors.textSecondary
        translateLine.hoverTint = colors.textPrimary
        translateLine.action = { [weak self] in self?.onTranslate() }
        self.colors = colors
        self.hasTab = hasTab
        tip.text = url
        label.stringValue = text
        label.textColor = hasTab ? colors.textPrimary : colors.textTertiary
        model = (pinned, active)
        refreshAccessories(animated: false)
        refreshFill()
        needsLayout = true
    }

    private func refreshFill() {
        layer?.backgroundColor = (hovering ? colors.pillHoverFill : colors.pillFill).cgColor
    }

    /// Whether the pins go in this field (else in the grid over the favorites), for its width.
    private var pinsInField = true
    /// A WebKit page's service: the pins dim and say why (docs/protected-media.md).
    private var protectedMedia: String?

    /// Arc's URL-bar accessories (ToolbarComposition.urlFieldAccessories): pinned extensions
    /// (while they leave the address room), Copy Link, then the Site Control Center's sliders,
    /// which show with no extension installed too (#226).
    private func refreshAccessories(animated: Bool) {
        accessories.forEach { $0.removeFromSuperview() }
        accessories = []
        shownItems = []
        guard showAccessories, hasTab, let m = model, let actions else { needsLayout = true; return }
        pinsInField = PinnedExtensionGrid.fitsInURLField(count: m.pinned.count, fieldWidth: bounds.width)
        let icons = Dictionary(m.pinned.map { ($0.0, $0.2) }, uniquingKeysWith: { a, _ in a })
        for item in ToolbarComposition.urlFieldAccessories(pinnedExtensions: m.pinned.map(\.0), fieldWidth: bounds.width) {
            switch item {
            case .pinnedExtension(let id):
                let b = ToolbarGlyphButton()
                // Arc's pinned extension buttons have no tooltip (#106), unless they can't run here.
                b.configure(symbol: nil, image: icons[id] ?? nil, help: protectedMedia.map(ExtensionStore.offOnProtectedMedia) ?? "",
                            enabled: protectedMedia == nil, width: 28, iconSize: 16, tint: colors.textSecondary)
                b.action = { actions.runExtension(id) }
                b.menuProvider = { ExtensionStore.shared.entries.first { $0.extensionID == id }.map(ExtensionsMenu.iconMenu) }
                accessories.append(b)
            case .copyURL:
                let copy = SidebarGlyphButton(symbol: "link", size: 28, height: 28, iconSize: 14, weight: .regular, help: "Copy URL (⇧⌘C)", colors: colors) {}
                // Arc confirms a click here in place as well as with the toast; ⇧⌘C only toasts (#361).
                copy.action = { [weak copy] in
                    actions.performAction("copyURL")
                    copy?.playCopyCheck(glyphSize: 14)
                }
                copy.active = m.active
                accessories.append(copy)
            case .extensions:
                let e = SidebarGlyphButton(symbol: "slider.horizontal.2.square", size: 28, height: 28, iconSize: 15, weight: .regular, help: "Extensions", colors: colors) { actions.showExtensionsMenu() }
                e.active = m.active
                accessories.append(e)
            default:
                continue
            }
            shownItems.append(item)
        }
        for v in accessories {
            addSubview(v)
            if animated {
                v.alphaValue = 0
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    v.animator().alphaValue = 1
                }
            }
        }
        needsLayout = true
    }

    /// The accessories' hover fill is the sidebar's, not the toolbar's.
    override func layout() {
        super.layout()
        if let m = model, showAccessories, PinnedExtensionGrid.fitsInURLField(count: m.pinned.count, fieldWidth: bounds.width) != pinsInField {
            refreshAccessories(animated: false)
        }
        let h = bounds.height
        // Arc 1.171 (4 Nov): one every 28 pt, the last centred 19 pt in from the end.
        var right = bounds.width - 5
        for v in accessories.reversed() {
            right -= 28
            v.frame = NSRect(x: right, y: (h - 28) / 2, width: 28, height: 28)
        }
        var x: CGFloat = 12
        if exitsFullscreen {
            exitGlyph.frame = NSRect(x: 12, y: (h - 16) / 2, width: 16, height: 16)
            x = 12 + 16 + 8
        }
        let lh = label.intrinsicContentSize.height
        let labelY = translateLine.isHidden ? (h - lh) / 2 : 6 + (18 - lh) / 2
        label.frame = NSRect(x: x - SidebarText.inset, y: labelY, width: max(0, right - x) + 2 * SidebarText.inset, height: lh)
        tip.frame = NSRect(x: 0, y: 0, width: right, height: h)
        if !translateLine.isHidden {
            let tw = min(translateLine.fittingWidth, max(0, right - x))
            translateLine.frame = NSRect(x: x, y: 23, width: tw, height: 17)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        if exitsFullscreen { actions?.exitPageFullscreen(); return }
        actions?.openCommandBar(hasTab ? .editURL : .newTab)
    }

    /// Runs the shown button's own action, as a click on it would (scenario hook, #226).
    func debugPress(_ item: ToolbarComposition.Item) -> Bool {
        guard let i = shownItems.firstIndex(of: item) else { return false }
        switch accessories[i] {
        case let b as SidebarGlyphButton: b.action()
        case let b as ToolbarGlyphButton: b.action()
        default: return false
        }
        return true
    }
}

/// The URL field's "Translation Available" line (#310): plain text in the field's secondary ink,
/// the primary on hover, that opens Arc's translate popover. Arc's AX frame is 122 × 17 pt, the
/// width of the title in 12 pt.
final class TranslateLineButton: NSView {
    var action: () -> Void = {}
    private let label = NSTextField.sidebarLabel(size: 12)
    var tint = NSColor.secondaryLabelColor { didSet { refresh() } }
    var hoverTint = NSColor.labelColor { didSet { refresh() } }
    private var hovering = false { didSet { refresh() } }
    var title: String {
        get { label.stringValue }
        set {
            label.stringValue = newValue
            setAccessibilityLabel(newValue)
            needsLayout = true
        }
    }
    /// The title's own width (Arc's button is as wide as its text).
    var fittingWidth: CGFloat {
        ceil((label.stringValue as NSString).size(withAttributes: [.font: label.font ?? .systemFont(ofSize: 12)]).width) + 1
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private func refresh() { label.textColor = hovering ? hoverTint : tint }

    override func layout() {
        super.layout()
        let h = label.intrinsicContentSize.height
        label.frame = NSRect(x: -SidebarText.inset, y: (bounds.height - h) / 2, width: bounds.width + 2 * SidebarText.inset, height: h)
    }

    override func accessibilityPerformPress() -> Bool { action(); return true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}

// MARK: - Dock

/// Bottom row like Arc's: the Library at the left, tiny space icons in the middle (inactive ones
/// dimmed, icon-less ones dots), "+" at the right. Arc 1.170 (SidebarDock, an NSCollectionView):
/// 34×32 pt cells side by side with no gap, so a press anywhere between two icons still lands on a
/// space. Widths and what each cell draws come from CraCore's SpaceDock.
final class SpaceDockView: NSView {
    static let cell = CGSize(width: 34, height: 32)
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let actions: SidebarActions
    private let library: LibraryButtonView
    private let plus: SidebarGlyphButton
    private let creationMenu = SidebarCreationMenuController()
    private var cells: [UUID: SpaceCellView] = [:]
    private var order: [UUID] = []
    private var focused: UUID?
    private var incognito = false
    private var colors = SidebarColors()
    private var hovered: UUID? { didSet { if hovered != oldValue { refreshCells() } } }
    private var reorder: (id: UUID, from: Int, to: Int, start: NSPoint, moved: Bool)?
    private var syncQueued = false

    init(store: SidebarStore, ui: SidebarUIState, actions: SidebarActions) {
        self.store = store
        self.ui = ui
        self.actions = actions
        library = LibraryButtonView(ui: ui, actions: actions)
        // Arc 1.172.1: a 32 pt button (sidebarPlusButton) with no tooltip.
        plus = SidebarGlyphButton(symbol: "plus", size: 32, height: 32, iconSize: 14, help: "", colors: SidebarColors(), action: {})
        super.init(frame: .zero)
        plus.setMenuOpen(false)
        plus.action = { [weak self] in self?.toggleCreationMenu() }
        addSubview(library)
        addSubview(plus)
        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { creationMenu.close(animated: false) }
        super.viewWillMove(toWindow: newWindow)
    }

    private func toggleCreationMenu() {
        guard !store.isBlank(window: ui.windowID) else { return }
        ArcTooltipController.shared.dismiss()
        let selected = store.selectedTabID(window: ui.windowID)
        let url = selected.flatMap { store.item($0)?.tab?.url }.flatMap(URL.init(string:))
        let canBoost = ["http", "https"].contains(url?.scheme?.lowercased() ?? "") && url?.host != nil
        let canSplit = selected.map { store.paneTabIDs(for: $0).count < 4 } ?? false
        let entries: [(String, String, String, Bool)] = [
            ("newSpace", "New Space", "plus.rectangle.on.rectangle", true),
            ("newFolder", "New Folder", "folder", true),
            ("newEasel", "New Easel", "scribble", true),
            ("newBoost", "New Boost", "paintbrush.pointed", canBoost),
            ("addSplitView", "New Split", "rectangle.split.2x1", canSplit),
            ("newTab", "New Tab", "plus.rectangle", true),
        ]
        let items = entries.map { id, title, symbol, enabled in
            SidebarCreationMenuItem(title: title, symbol: symbol, shortcut: KeyBindingRegistry.shared.action(id)?.primary?.display ?? "",
                                    enabled: enabled) { [actions] in actions.performAction(id) }
        }
        let tones = ArcMenuTones(theme: store.focusedSpace(window: ui.windowID).theme.shown)
        func ink(_ c: RGB) -> NSColor { NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1) }
        let colors = SidebarCreationMenuColors(fill: ink(tones.fill), hover: ink(tones.hover), separator: ink(tones.separator),
                                               shortcut: ink(tones.shortcut), disabled: ink(tones.disabled))
        creationMenu.toggle(from: plus, items: items, colors: colors) { [weak plus] open in
            plus?.highlighted = open
            plus?.setMenuOpen(open)
        }
    }

    private func sync() {
        syncQueued = false
        var spaces: [Space] = []
        withObservationTracking {
            colors = SidebarColors(store.focusedSpace(window: ui.windowID).theme.palette)
            incognito = store.window(ui.windowID).isIncognito
            let f = store.focusedSpaceID(window: ui.windowID)
            focused = f
            // Arc's single-space mode drops the lone space icon along with the header; incognito and
            // Blank Windows show no space icons (Arc 1.172 keeps the + in a Blank Window).
            spaces = store.isStandalone(window: ui.windowID) || store.hidesSpaceHeader(f) ? [] : store.orderedSpaces
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.syncQueued else { return }
                self.syncQueued = true
                self.sync()
            }
        }
        library.colors = colors
        plus.colors = colors
        plus.isHidden = incognito
        let ids = spaces.map(\.id)
        for (id, c) in cells where !ids.contains(id) {
            c.removeFromSuperview()
            cells[id] = nil
        }
        for s in spaces {
            let c = cells[s.id] ?? {
                let c = SpaceCellView(spaceID: s.id, store: store, ui: ui)
                cells[s.id] = c
                addSubview(c)
                return c
            }()
            c.show(icon: s.icon, title: s.title)
        }
        order = ids
        refreshCells()
        needsLayout = true
    }

    private func refreshCells() {
        let squeezed = SpaceDock.isSqueezed(count: order.count, room: room)
        for (id, c) in cells {
            c.setState(selected: id == focused, hovered: hovered == id && reorder == nil, pressed: reorder?.id == id,
                       squeezed: squeezed, colors: colors)
        }
    }

    /// The room between the Library and + buttons: 217 pt in a 300 pt sidebar.
    private var room: CGFloat { max(0, bounds.width - 63) }

    /// SpaceDock's widths, Arc's: 34 pt each until the share drops under 22, then the open space
    /// keeps 22 and the others split the rest. The strip stays centred, so it never runs past the
    /// buttons.
    private var cellWidths: [CGFloat] {
        SpaceDock.widths(count: order.count, open: focused.flatMap { order.firstIndex(of: $0) }, room: room)
    }

    /// Left edges of the cells, in order.
    private var cellXs: [CGFloat] {
        let ws = cellWidths
        var x = (bounds.width - ws.reduce(0, +)) / 2
        return ws.map { w in defer { x += w }; return x }
    }

    /// The width a dragged space moves by per cell (the cells other than the open one).
    private var pitch: CGFloat { cellWidths.min() ?? Self.cell.width }

    override func layout() {
        super.layout()
        let h = bounds.height
        library.frame = NSRect(x: 0, y: (h - 28) / 2, width: 28, height: 28)
        plus.frame = NSRect(x: bounds.width - plus.size.width, y: (h - plus.size.height) / 2,
                            width: plus.size.width, height: plus.size.height)
        // A narrower sidebar can squeeze the dock into dots.
        refreshCells()
        placeCells(animated: false)
    }

    /// The dragged space follows the pointer; the ones it passes slide a cell the other way, like
    /// the gap Arc's collection view opens at the proposed drop index, on a spring that picks up
    /// from wherever a cell is, so a quick drag back and forth never jumps.
    private func placeCells(animated: Bool, dragX: CGFloat = 0) {
        let ws = cellWidths, xs = cellXs, step = pitch
        let y = (bounds.height - Self.cell.height) / 2
        for (i, id) in order.enumerated() {
            guard let c = cells[id] else { continue }
            var x = xs[i]
            if let r = reorder {
                if r.id == id { x += dragX } else if r.from < i && i <= r.to { x -= step } else if r.to <= i && i < r.from { x += step }
            }
            let f = NSRect(x: x, y: y, width: ws[i], height: Self.cell.height)
            if animated && reorder?.id != id { Self.slide(c, to: f) } else if c.frame != f { c.frame = f }
        }
        if let r = reorder, let c = cells[r.id], subviews.last !== c { c.removeFromSuperview(); addSubview(c) }
    }

    /// The dock's reorder spring: quick, a touch of give (SwiftUI's .spring(response: 0.28, dampingFraction: 0.78)).
    static let reorderSpring = SpringMotion(response: 0.28, dampingFraction: 0.78)

    /// A cell to `f` on the reorder spring, from where it shows now (an earlier slide included).
    /// A reordered item springs from where it shows to `f` (the dock's cells, the Library's space cards).
    static func slide(_ c: NSView, to f: NSRect, completion: (() -> Void)? = nil) {
        let shownX = c.layer?.presentation()?.frame.minX ?? c.frame.minX
        c.frame = f
        guard let layer = c.layer, abs(shownX - f.minX) > 0.25, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            c.layer?.removeAnimation(forKey: "dockSlide")
            completion?()
            return
        }
        let s = CASpringAnimation(keyPath: "position.x")
        s.isAdditive = true
        s.fromValue = shownX - f.minX
        s.toValue = 0
        s.mass = 1
        s.stiffness = reorderSpring.stiffness
        s.damping = reorderSpring.damping
        s.duration = s.settlingDuration
        CATransaction.begin()
        CATransaction.setCompletionBlock { completion?() }
        layer.add(s, forKey: "dockSlide")
        CATransaction.commit()
    }

    /// The pressed space lifts while it is dragged (a little larger, over the others) and settles
    /// back as it lands, on the same spring. Scaled through the sublayers, which AppKit leaves alone.
    private static func lift(_ c: NSView, _ up: Bool) {
        guard let layer = c.layer else { return }
        let b = layer.bounds
        func scaled(_ k: CGFloat) -> CATransform3D {
            var t = CATransform3DMakeTranslation(b.midX, b.midY, 0)
            t = CATransform3DScale(t, k, k, 1)
            return CATransform3DTranslate(t, -b.midX, -b.midY, 0)
        }
        let to = up ? scaled(1.18) : CATransform3DIdentity
        let from = layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = to
        CATransaction.commit()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let s = CASpringAnimation(keyPath: "sublayerTransform")
        s.fromValue = NSValue(caTransform3D: from)
        s.toValue = NSValue(caTransform3D: to)
        s.mass = 1
        s.stiffness = reorderSpring.stiffness
        s.damping = reorderSpring.damping
        s.duration = s.settlingDuration
        layer.add(s, forKey: "dockLift")
    }

    private func index(at p: NSPoint) -> Int? {
        guard p.y >= 0, p.y <= bounds.height else { return nil }
        let ws = cellWidths
        return cellXs.indices.first { p.x >= cellXs[$0] && p.x < cellXs[$0] + ws[$0] }
    }

    // Arc's dock items take the mouse themselves (SidebarDockItemView overrides mouseDown:/mouseUp:):
    // a press never moves the window, and every click counts.
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        if index(at: p) != nil { return self }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    private func point(_ e: NSEvent) -> NSPoint { convert(e.locationInWindow, from: nil) }

    override func mouseMoved(with event: NSEvent) {
        guard reorder == nil else { return }
        let i = index(at: point(event))
        hovered = i.map { order[$0] }
        // The new cell first: its tip replaces the shown one in place. Leaving the old cell first
        // faded that tip out while the new one popped in, two tips for 60 ms (#152).
        if let i, let c = cells[order[i]] { ArcTooltipController.shared.mouseMoved(in: c) }
        for (j, id) in order.enumerated() where j != i { if let c = cells[id] { ArcTooltipController.shared.mouseExited(c) } }
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) {
        if reorder == nil { hovered = nil }
        for c in cells.values { ArcTooltipController.shared.mouseExited(c) }
    }

    override func mouseDown(with event: NSEvent) {
        let p = point(event)
        guard let i = index(at: p) else { return }
        reorder = (order[i], i, i, p, false)
        refreshCells()
    }

    override func mouseDragged(with event: NSEvent) {
        guard var r = reorder else { return }
        let p = point(event)
        let dx = p.x - r.start.x
        if !r.moved && abs(dx) < 3 && abs(p.y - r.start.y) < 3 { return }
        if !r.moved {
            // Picked up: it lifts over the others, and its tip gets out of the way.
            if let c = cells[r.id] { Self.lift(c, true) }
            for c in cells.values { ArcTooltipController.shared.mouseExited(c) }
        }
        r.moved = true
        let w = pitch
        let clamped = min(max(dx, -CGFloat(r.from) * w), CGFloat(order.count - 1 - r.from) * w)
        let to = min(max(r.from + Int((clamped / w).rounded()), 0), order.count - 1)
        let changed = to != r.to
        r.to = to
        reorder = r
        if changed, store.settings.hapticFeedbackOnReorder {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        placeCells(animated: changed, dragX: clamped)
    }

    /// A release inside the pressed cell that didn't move the space switches to it, so a shaky
    /// click still counts; a moved space slides into its cell and the order is saved.
    override func mouseUp(with event: NSEvent) {
        guard let r = reorder else { return }
        let p = point(event)
        if r.moved, let c = cells[r.id] { Self.lift(c, false) }
        guard r.to != r.from else {
            reorder = nil
            if index(at: p) == r.from { store.focusSpace(r.id, window: ui.windowID) }
            hovered = index(at: p).map { order[$0] }
            // A drag let go where it started: everything springs home.
            placeCells(animated: true)
            refreshCells()
            return
        }
        // `moveSpace` indexes the full space order; land next to the space now in that cell.
        let target = store.spaceOrder.firstIndex(of: order[r.to]) ?? r.to
        let dropped = cells[r.id]
        let slot = cellXs.indices.contains(r.to) ? cellXs[r.to] : (cellXs.first ?? 0) + CGFloat(r.to) * pitch
        // The others are already in their places; the dropped space springs into its cell, then the
        // order is saved and the dock lays out as it now is (nothing moves: every cell is in place).
        placeCells(animated: false, dragX: CGFloat(r.to - r.from) * pitch)
        guard let dropped else {
            reorder = nil
            store.moveSpace(r.id, to: target)
            return
        }
        Self.slide(dropped, to: NSRect(x: slot, y: dropped.frame.minY, width: dropped.frame.width, height: dropped.frame.height)) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reorder = nil
                self.store.moveSpace(r.id, to: target)
                self.refreshCells()
            }
        }
    }

    /// A space's icon takes the same menu as its header (SpaceMenu: Change Space Icon…, Rename
    /// Space…, Edit Theme Color…, Set Profile, New Folder, … Delete Space). Rename goes to that
    /// space and edits its header in place; the icon picker points at the dock icon.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let i = index(at: point(event)), let cell = cells[order[i]] else { return nil }
        let id = order[i], store = self.store, ui = self.ui
        hovered = nil
        for c in cells.values { ArcTooltipController.shared.mouseExited(c) }
        return SpaceMenu.make(spaceID: id, store: store, ui: ui, actions: actions, anchor: cell, from: .dock) {
            store.focusSpace(id, window: ui.windowID)
            ui.renameSpaceRequest = id
        }
    }
}

/// One space in the dock: its emoji or symbol, dimmed and desaturated unless selected, hovered or
/// pressed, or Arc's dot: for a space with no icon, and for every space but the open one when the
/// dock is squeezed (#252). A tab dragged onto it moves there; held over it, Arc switches to that
/// space so the tab can be carried into its list.
final class SpaceCellView: NSView, ArcTooltipTarget {
    private let spaceID: UUID
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let emoji = NSTextField.sidebarLabel(size: 13)
    private let emojiHolder = NSView()
    /// An Icon-tab glyph (Space.symbol) in the emoji's place.
    private let symbol = NSImageView()
    private var symbolName: String?
    /// Arc's dot, outside `emojiHolder` so its own ink sets how faint it is.
    private let dot = CALayer()
    private var icon = SpaceIcon.none
    private var mark = SpaceDockMark.dot(diameter: SpaceDock.dotDiameter)
    private var title = ""
    private var selected = false
    private var colors = SidebarColors()
    private var state: (Bool, Bool, Bool)?
    private var targeted = false { didSet { if targeted != oldValue { refreshFill() } } }
    private var lit = false

    init(spaceID: UUID, store: SidebarStore, ui: SidebarUIState) {
        self.spaceID = spaceID
        self.store = store
        self.ui = ui
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        emojiHolder.wantsLayer = true
        emojiHolder.layerUsesCoreImageFilters = true
        emoji.alignment = .center
        emojiHolder.addSubview(emoji)
        addSubview(emojiHolder)
        dot.actions = ["bounds": NSNull(), "position": NSNull(), "backgroundColor": NSNull(), "hidden": NSNull(), "cornerRadius": NSNull()]
        layer?.addSublayer(dot)
        registerForDraggedTypes([.craSidebarItem])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(icon: SpaceIcon, title: String) {
        self.icon = icon
        self.title = title
        setAccessibilityLabel(title)
        needsLayout = true
    }

    /// `squeezed`: the dock is too narrow for icons, so every space but the open one is a dot.
    func setState(selected: Bool, hovered: Bool, pressed: Bool, squeezed: Bool, colors: SidebarColors) {
        self.selected = selected
        self.colors = colors
        lit = selected || hovered || pressed
        let mark = SpaceDock.mark(for: icon, isOpen: selected, squeezed: squeezed)
        if mark != self.mark { self.mark = mark; needsLayout = true }
        switch mark {
        case .emoji(let e):
            emoji.stringValue = e
            showSymbol(nil)
        case .symbol(let name):
            emoji.stringValue = ""
            showSymbol(name)
        case .dot:
            emoji.stringValue = ""
            showSymbol(nil)
        }
        emojiHolder.isHidden = { if case .dot = mark { return true } else { return false } }()
        dot.isHidden = !emojiHolder.isHidden
        dot.backgroundColor = (colors.isDark ? NSColor.white : NSColor.black)
            .withAlphaComponent(SpaceDock.dotAlpha(dark: colors.isDark, lit: lit)).cgColor
        emojiHolder.alphaValue = lit ? 1 : 0.45
        symbol.contentTintColor = colors.textPrimary
        emojiHolder.layer?.filters = lit ? nil : [CIFilter(name: "CIColorControls", parameters: ["inputSaturation": 0.2])!]
        refreshFill(hovered || pressed)
    }

    private func showSymbol(_ name: String?) {
        guard symbolName != name else { return }
        symbolName = name
        symbol.image = name.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        symbol.isHidden = name == nil
        if symbol.superview == nil { symbol.imageScaling = .scaleNone; emojiHolder.addSubview(symbol) }
    }

    /// Arc's hovered/pressed cell on a dark space: white at ~7.8%, 6 pt corners.
    private func refreshFill(_ on: Bool? = nil) {
        let fill = colors.isDark ? NSColor.white.withAlphaComponent(0.078) : NSColor.black.withAlphaComponent(0.05)
        let show = targeted || (on ?? (lit && !selected))
        layer?.backgroundColor = (show ? fill : .clear).cgColor
    }

    override func layout() {
        super.layout()
        emojiHolder.frame = bounds
        // An icon only shows in a cell of 22 pt or more (squeezed cells are dots), so it keeps its size.
        let size: CGFloat = 13
        if emoji.font?.pointSize != size { emoji.font = .systemFont(ofSize: size) }
        let h = emoji.intrinsicContentSize.height
        emoji.frame = NSRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
        symbol.frame = bounds
        symbol.symbolConfiguration = .init(pointSize: size - 2, weight: .medium)
        if case .dot(let d) = mark {
            dot.bounds = CGRect(x: 0, y: 0, width: d, height: d)
            dot.cornerRadius = d / 2
            dot.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        store.focusSpace(spaceID, window: ui.windowID)
        return true
    }

    private func draggedID(_ info: NSDraggingInfo) -> UUID? {
        guard let data = info.draggingPasteboard.data(forType: .craSidebarItem),
              let d = try? JSONDecoder().decode(SidebarDragItem.self, from: data) else { return nil }
        return d.id
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggedID(sender) != nil else { return [] }
        targeted = true
        if !selected {
            let id = spaceID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.targeted else { return }
                self.store.focusSpace(id, window: self.ui.windowID)
            }
        }
        return sender.draggingSourceOperationMask.contains(.move) ? .move : .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggedID(sender) == nil ? [] : (sender.draggingSourceOperationMask.contains(.move) ? .move : .copy)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { targeted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { targeted = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        targeted = false
        guard let id = draggedID(sender) else { return false }
        // A picked tab takes the other picks along, as a drop in the list does.
        store.moveTabs(ui.group(for: id, in: store), toSpace: spaceID)
        if store.focusedSpaceID(window: ui.windowID) != spaceID { ui.clearPicks() }
        return true
    }

    // Arc's tip: the space's name, its profile in a pill, then Go to Space N's keys for the
    // space's place in the order (⌃1–⌃9, the user's own if rebound; none past the ninth).
    var text: String { title }
    var keys: [String] {
        guard let i = store.spaceOrder.firstIndex(of: spaceID), i < 9 else { return [] }
        return KeyBindingRegistry.shared.action("space\(i + 1)")?.primary?.caps ?? []
    }
    var badge: String? { store.profile(store.space(spaceID)?.profileID)?.name ?? "Default" }
    // Arc 1.171: ~0.62 s after the pointer stops (two 120 Hz recordings, 3 Nov 2026), sooner
    // than a control's tip. Cra's panel takes ~0.07 s more to reach the screen.
    var idleDelay: TimeInterval { 0.55 }
    var placement: ArcTooltipPlacement { .above }
    var followsCursor: Bool { false }
    var subtitle: String? { nil }
    var optionText: String? { nil }
    var onShow: (() -> Void)? { nil }
    var screenFrame: NSRect { window?.convertToScreen(convert(bounds, to: nil)) ?? .zero }
    var hostWindow: NSWindow? { window }
}

/// Arc's Library button (a box with a confetti puff, drawn by LibraryGlyph) and, over it, the
/// latest download's "bin" (DownloadsUI.DownloadToLibrary): the file's thumbnail, 32 pt with
/// 8 pt corners, up and to the right of the glyph. It drops in from 6 pt above, overshoots 12 pt
/// below and settles (Arc 1.170 at 60 fps), and is faint while the window is in the background.
/// When hovering opens the downloads list, the bin flies up into it as its newest row (the same
/// file), leaving the button and its "View Library" tip clear, and comes back down as the list
/// closes; it stayed put over the tip (10 Nov 2026).
final class LibraryButtonView: NSView {
    private let ui: SidebarUIState
    private let actions: SidebarActions
    private let glyph = NSImageView()
    private let tip: ArcTooltipAnchorView
    private let bin = NSView()
    private let binImage = CALayer()
    private let binTip: ArcTooltipAnchorView
    /// The ring on the bin's corner while downloads run (#272).
    private let badge = DownloadProgressBadgeView()
    private var shownDownload: UInt32?
    /// The bin is up in the open downloads list (or on its way there).
    private var tucked = false
    private var binAlpha: CGFloat = 1
    private var hovering = false { didSet { if hovering != oldValue { refresh() } } }
    var colors = SidebarColors() { didSet { if colors != oldValue { glyph.image = LibraryGlyph.image(dark: colors.isDark); badge.colors = colors; refresh() } } }
    static let binOffset = CGSize(width: 9, height: -12)
    /// The download bin's frame, for Tidy Downloads' card to point at.
    var binFrame: NSRect { bin.frame }

    init(ui: SidebarUIState, actions: SidebarActions) {
        self.ui = ui
        self.actions = actions
        tip = ArcTooltipAnchorView(frame: .zero)
        binTip = ArcTooltipAnchorView(frame: .zero)
        super.init(frame: .zero)
        wantsLayer = true
        // Round the glyph's hover fill. Rounding the button itself clips the overhanging thumbnail.
        glyph.wantsLayer = true
        glyph.layer?.cornerRadius = 7
        glyph.layer?.cornerCurve = .continuous
        glyph.imageScaling = .scaleNone
        glyph.image = LibraryGlyph.image(dark: false)
        addSubview(glyph)
        (tip.text, tip.keys) = ArcTooltipLabel.split("View Library (⇧⌘L)")
        tip.placement = .trailing
        addSubview(tip)
        bin.wantsLayer = true
        binImage.cornerRadius = 8
        binImage.cornerCurve = .continuous
        binImage.masksToBounds = true
        binImage.contentsGravity = .resizeAspectFill
        bin.layer?.addSublayer(binImage)
        bin.addSubview(binTip)
        bin.addSubview(badge)
        bin.isHidden = true
        addSubview(bin)
        ui.libraryAnchor = self
        observe()
        observeProgress()
    }

    private struct Progress: Equatable {
        var running: Double?
        var bin: UInt32?
    }

    /// The badge follows every running download together; when the last one ends, a check if the
    /// bin's download finished with a file, else it just goes.
    private func observeProgress() {
        observeChanges(of: { [ui] in Progress(running: DownloadHistory.shared.progress, bin: ui.recentDownload?.id) }) { [weak self] p in
            guard let self else { return }
            let finished = p.bin.map { id in !DownloadHistory.shared.live.contains { $0.id == id } } ?? false
            self.badge.show(progress: p.bin == nil ? nil : p.running, finished: finished)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private func observe() {
        let (download, active, listOpen) = withObservationTracking { (ui.recentDownload, ui.appActive, ui.downloadsListOpen) } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        guard let download else { putAway(); return }
        bin.layer?.removeAnimation(forKey: "putAway")
        bin.isHidden = false
        binImage.contents = download.image
        binAlpha = active ? 1 : 0.4
        if !tucked { bin.alphaValue = binAlpha }
        binTip.text = (download.path as NSString).lastPathComponent
        if shownDownload != download.id {
            shownDownload = download.id
            if !listOpen { drop() }
        }
        setTucked(listOpen)
    }

    /// The bin's time is up: it shrinks a little as it fades, on a spring with no bounce, then goes.
    private func putAway() {
        shownDownload = nil
        let wasTucked = tucked
        tucked = false
        badge.isHidden = false
        guard !bin.isHidden, !wasTucked, let layer = bin.layer, window != nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            bin.isHidden = true
            return
        }
        let spring = SpringMotion(response: 0.32, dampingFraction: 1)
        let fade = CASpringAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? 1
        fade.toValue = 0
        let shrink = CASpringAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1
        shrink.toValue = 0.7
        for a in [fade, shrink] {
            a.mass = 1
            a.stiffness = spring.stiffness
            a.damping = spring.damping
            a.duration = a.settlingDuration
            a.fillMode = .forwards
            a.isRemovedOnCompletion = false
        }
        let group = CAAnimationGroup()
        group.animations = [fade, shrink]
        group.duration = fade.settlingDuration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.ui.recentDownload == nil else { return }
                self.bin.isHidden = true
                self.bin.layer?.removeAnimation(forKey: "putAway")
            }
        }
        layer.add(group, forKey: "putAway")
        CATransaction.commit()
    }

    /// Where the bin rests: up and to the right of the glyph.
    private var restBinFrame: NSRect {
        let c = NSPoint(x: bounds.midX + Self.binOffset.width, y: bounds.midY + Self.binOffset.height)
        return NSRect(x: c.x - 16, y: c.y - 16, width: 32, height: 32)
    }

    /// The list opening: the bin rises to its newest row's thumbnail, growing to it and fading as
    /// the row fades in there; closing, it comes back down from there into its place. On the
    /// list's own curve (SidebarListMetrics); at once with Reduce Motion or nothing to fly to.
    private func setTucked(_ tuck: Bool) {
        guard tuck != tucked else { return }
        tucked = tuck
        badge.isHidden = tuck
        if !bin.isHidden { CraLog.note(tuck ? "library bin rises into the downloads list" : "library bin comes back to the Library button") }
        let rest = restBinFrame
        guard !bin.isHidden, window != nil, let target = ui.downloadsTray?.newestThumbnailInWindow().map({ convert($0, from: nil) }),
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            bin.layer?.removeAllAnimations()
            bin.frame = rest
            binImage.frame = CGRect(origin: .zero, size: rest.size)
            bin.alphaValue = tuck ? 0 : binAlpha
            return
        }
        bin.layer?.removeAnimation(forKey: "drop")
        bin.layer?.removeAnimation(forKey: "fade")
        if !tuck {
            // Back from the row it became.
            bin.frame = target
            binImage.frame = CGRect(origin: .zero, size: target.size)
            bin.alphaValue = 0
        }
        let to = tuck ? target : rest
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = tuck ? 0.26 : 0.22
            ctx.timingFunction = SidebarListMetrics.timing
            ctx.allowsImplicitAnimation = true
            bin.animator().frame = to
            bin.animator().alphaValue = tuck ? 0 : binAlpha
            CATransaction.begin()
            CATransaction.setAnimationDuration(ctx.duration)
            CATransaction.setAnimationTimingFunction(SidebarListMetrics.timing)
            binImage.frame = CGRect(origin: .zero, size: to.size)
            binImage.cornerRadius = tuck ? 6 : 8
            CATransaction.commit()
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.tucked == tuck else { return }
                if tuck {
                    // Out of sight in the list: home again, invisible, for the way back.
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self.bin.frame = self.restBinFrame
                    self.binImage.frame = CGRect(origin: .zero, size: self.restBinFrame.size)
                    self.binImage.cornerRadius = 8
                    CATransaction.commit()
                }
            }
        }
    }

    private func drop() {
        let y = CAKeyframeAnimation(keyPath: "transform.translation.y")
        // Flipped view: positive y is down on screen.
        y.values = [-6, 12, 12, -2, 0].map { NSNumber(value: Double($0) * (bin.layer?.isGeometryFlipped == true ? 1 : -1)) }
        y.keyTimes = [0, 0.15, 0.2, 0.33, 0.4].map { NSNumber(value: $0 / 0.4) }
        y.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .linear),
                             CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        y.duration = 0.4
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.05
        bin.layer?.add(y, forKey: "drop")
        bin.layer?.add(fade, forKey: "fade")
    }

    private func refresh() {
        glyph.layer?.backgroundColor = (hovering ? colors.hoverFill : .clear).cgColor
    }

    override func layout() {
        super.layout()
        glyph.frame = bounds
        tip.frame = bounds
        // Not while it flies to or from the downloads list.
        if bin.layer?.animationKeys()?.isEmpty ?? true {
            bin.frame = restBinFrame
            binImage.frame = bin.bounds
        }
        binTip.frame = NSRect(origin: .zero, size: restBinFrame.size)
        // Over the bin's bottom right corner, 4 pt out (the bin isn't flipped).
        let b = DownloadProgressBadgeView.size
        badge.frame = NSRect(x: bin.bounds.maxX - b + 4, y: -4, width: b, height: b)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        if !bin.isHidden, !tucked, bin.frame.contains(p) { return self }
        return bounds.contains(p) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { setHovering(true) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if !bin.isHidden, !tucked, bin.frame.contains(p), let path = ui.recentDownload?.path {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else if bounds.contains(p) {
            actions.toggleLibrary()
            // The Library slides in under the pointer (or the sidebar moves into its floating
            // panel), and no exit comes for a view that moved away: look again once it has.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.syncHover() }
        }
        syncHover()
    }

    private func setHovering(_ on: Bool) {
        guard on != hovering || ui.libraryHovered != on else { return }
        hovering = on
        ui.libraryHovered = on
        ui.downloadsHoverChanged()
    }

    /// The fill follows where the pointer really is. A tracking area sends no exit when its view
    /// moves out from under the pointer, is hidden, or changes window (the floating sidebar's
    /// panel), which left the button lit after the Library opened.
    func syncHover() {
        guard let window, !isHiddenOrHasHiddenAncestor else { setHovering(false); return }
        let p = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let inside = (bounds.contains(p) || (!bin.isHidden && !tucked && bin.frame.contains(p))) && window.isVisible
        setHovering(inside)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncHover()
    }

    override func viewDidHide() {
        super.viewDidHide()
        setHovering(false)
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        if hovering { syncHover() }
    }
}
