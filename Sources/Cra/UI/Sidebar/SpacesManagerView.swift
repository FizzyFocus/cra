import AppKit

/// Arc 1.171's Library ▸ Spaces, which "Manage Spaces…" opens (spaceManager). Measured from a 2x
/// capture of Arc's window (1 Nov): every space is a 240 pt card in its own theme, 24 pt apart,
/// starting 27 pt right of the rail, 48 pt below the window top and above its bottom. A card has
/// the space's icon, name and a brush (Edit Theme Color…) on a row 25 pt down, its pinned and
/// Today lists from 64 pt down, and a move handle and a ••• menu 21 pt above its bottom. A blue +
/// (New Space) sits 34 pt after the last card, centred.
enum SpacesManagerMetrics {
    static let card: CGFloat = 240
    static let gap: CGFloat = 24
    static let lead: CGFloat = 27
    static let inset: CGFloat = 48
    static let plus: CGFloat = 29
    static let plusGap: CGFloat = 34
    static let trail: CGFloat = 37.5
    /// What the page keeps beside the Spaces page, whatever the window's width (Arc 1.171).
    static let pageRoom: CGFloat = 56

    /// The Library's width on this page: Arc widens the sidebar to fit every card.
    static func width(spaces n: Int) -> CGFloat {
        LibraryMetrics.rail + lead + CGFloat(n) * card + CGFloat(max(0, n - 1)) * gap + plusGap + plus + trail
    }
}

@MainActor
final class SpacesManagerView: NSView {
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let actions: SidebarActions
    private let favicons: FaviconCache
    private let scroll = SpacesStripScrollView()
    private let document = FlippedView()
    private var cards: [UUID: SpaceManagerCard] = [:]
    private var order: [UUID] = []
    private lazy var plus: NSButton = {
        let b = NSButton(image: SidebarSymbols.image("plus", size: 14, weight: .bold) ?? NSImage(), target: self, action: #selector(newSpace))
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = SpacesManagerMetrics.plus / 2
        b.layer?.backgroundColor = accent.fill.cgColor
        b.contentTintColor = accent.ink
        b.toolTip = "New Space"
        b.setAccessibilityLabel("New Space")
        return b
    }()

    /// The + takes the window's space colours (Arc 1.172.1, 8 Nov 2026: a cream disc with a dark +
    /// in an olive space; the blue one measured 1 Nov was a blue space's).
    var accent: (fill: NSColor, ink: NSColor) = (NSColor(hex: "#2147F5"), .white) {
        didSet { plus.layer?.backgroundColor = accent.fill.cgColor; plus.contentTintColor = accent.ink }
    }

    init(store: SidebarStore, ui: SidebarUIState, actions: SidebarActions, favicons: FaviconCache) {
        self.store = store
        self.ui = ui
        self.actions = actions
        self.favicons = favicons
        super.init(frame: .zero)
        scroll.drawsBackground = false
        // The window's full-size content would otherwise push the cards down by the title bar.
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        scroll.documentView = document
        addSubview(scroll)
        document.addSubview(plus)
        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func sync() {
        let ids = withObservationTracking { store.orderedSpaces.filter { !store.isIncognito(space: $0.id) }.map(\.id) } onChange: { [weak self] in
            Task { @MainActor in self?.sync() }
        }
        for id in cards.keys where !ids.contains(id) { cards.removeValue(forKey: id)?.removeFromSuperview() }
        for id in ids where cards[id] == nil {
            let c = SpaceManagerCard(spaceID: id, store: store, ui: ui, actions: actions, favicons: favicons)
            c.onMove = { [weak self] dx in self?.drag(id, by: dx) }
            c.onMoveEnd = { [weak self] in self?.drop(id) }
            cards[id] = c
            document.addSubview(c)
        }
        order = ids
        needsLayout = true
    }

    @objc private func newSpace() { actions.editSpace(nil) }

    /// Scenario hook (13 Nov 2026): each card's profile pill as drawn.
    static func debugBadges(in root: NSView) -> String? {
        guard let v = find(root) else { return nil }
        return v.order.compactMap { id in v.cards[id].map { "\(v.store.space(id)?.title ?? "?")=\($0.debugBadge)" } }.joined(separator: " ")
    }

    private static func find(_ v: NSView) -> SpacesManagerView? {
        if let m = v as? SpacesManagerView { return m }
        for s in v.subviews { if let m = find(s) { return m } }
        return nil
    }

    private var dragging: (id: UUID, dx: CGFloat)?
    /// The slot the dragged card is over (CardReorder): the others make room for it as it moves.
    private var dragSlot: Int?
    private static var pitch: CGFloat { SpacesManagerMetrics.card + SpacesManagerMetrics.gap }

    /// The dragged card follows the pointer; as its centre passes a neighbour that card springs
    /// aside into the gap it leaves (the dock's spring, with its haptic tick), live, not on release.
    private func drag(_ id: UUID, by dx: CGFloat) {
        guard let from = order.firstIndex(of: id) else { return }
        // The card in hand stays its size (a scale clipped its contents inside the card's rounded
        // mask, a sudden zoom); it rides above the others while they glide aside.
        if dragging == nil, let c = cards[id] { document.addSubview(c, positioned: .above, relativeTo: nil) }
        dragging = (id, dx)
        let slot = CardReorder.slot(from: from, offset: Double(dx), pitch: Double(Self.pitch), count: order.count)
        let moved = slot != (dragSlot ?? from)
        dragSlot = slot
        if moved, store.settings.hapticFeedbackOnReorder {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        placeCards(springing: moved)
    }

    /// Let go: the card springs into the slot it was over, and that order is saved.
    private func drop(_ id: UUID) {
        guard dragging != nil, let from = order.firstIndex(of: id) else { return }
        let to = dragSlot ?? from
        dragging = nil
        dragSlot = nil
        let target = to != from ? store.spaceOrder.firstIndex(of: order[to]) : nil
        order = CardReorder.order(order, moving: from, to: to)
        placeCards(springing: true)
        if let target { store.moveSpace(id, to: target) }
    }

    /// Each card's frame: in `order`, or while dragging in the order it makes room for, the dragged
    /// one under the pointer.
    private func cardFrames() -> [UUID: NSRect] {
        typealias M = SpacesManagerMetrics
        let cardH = max(0, bounds.height - 2 * M.inset)
        var shown = order
        if let d = dragging, let from = order.firstIndex(of: d.id), let slot = dragSlot {
            shown = CardReorder.order(order, moving: from, to: slot)
        }
        var frames: [UUID: NSRect] = [:]
        for (i, id) in shown.enumerated() {
            frames[id] = NSRect(x: M.lead + CGFloat(i) * Self.pitch, y: M.inset, width: M.card, height: cardH)
        }
        if let d = dragging, let from = order.firstIndex(of: d.id) {
            frames[d.id] = NSRect(x: M.lead + CGFloat(from) * Self.pitch + d.dx, y: M.inset, width: M.card, height: cardH)
        }
        return frames
    }

    private func placeCards(springing: Bool) {
        for (id, f) in cardFrames() {
            guard let c = cards[id] else { continue }
            if springing, id != dragging?.id { SpaceDockView.slide(c, to: f) } else { c.frame = f }
        }
    }

    override func layout() {
        super.layout()
        typealias M = SpacesManagerMetrics
        scroll.frame = bounds
        let h = bounds.height
        for (id, f) in cardFrames() { cards[id]?.frame = f }
        var x = M.lead + CGFloat(order.count) * Self.pitch
        x += M.plusGap - M.gap
        plus.frame = NSRect(x: x, y: (h - M.plus) / 2, width: M.plus, height: M.plus)
        document.frame = NSRect(x: 0, y: 0, width: x + M.plus + M.trail, height: h)
    }
}

/// One space's card: its theme behind its header row, tab list and footer.
@MainActor
private final class SpaceManagerCard: NSView {
    private let spaceID: UUID
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let actions: SidebarActions
    private let background: PaletteBackgroundView
    private let emoji = NSTextField.sidebarLabel(size: 14.5)
    private let symbol = NSImageView()
    private let title = NSTextField.sidebarLabel(size: 13, weight: .semibold)
    /// The space's profile beside its name, with more than one profile (ProfileBadge, 13 Nov 2026).
    private let badge = ProfileBadgeView()
    private var showsBadge = false
    private let list: SpaceListView
    private lazy var brush = SidebarGlyphButton(symbol: "paintbrush.pointed.fill", size: 26, iconSize: 13, help: "Edit Theme Color",
                                                colors: colors) { [weak self] in
        guard let self, let s = self.store.space(self.spaceID) else { return }
        self.actions.editSpaceThemeBeside(s, self)
    }
    /// Dragging it carries the card along the row; where it is let go is the space's new place.
    private let move = SpaceMoveHandle()
    var onMove: ((CGFloat) -> Void)?
    var onMoveEnd: (() -> Void)?
    private lazy var more = SidebarGlyphButton(symbol: "ellipsis", size: 26, iconSize: 13, help: "", colors: colors) { [weak self] in
        self?.showMenu()
    }
    private var colors = SidebarColors()

    init(spaceID: UUID, store: SidebarStore, ui: SidebarUIState, actions: SidebarActions, favicons: FaviconCache) {
        self.spaceID = spaceID
        self.store = store
        self.ui = ui
        self.actions = actions
        let palette = store.space(spaceID)?.theme.palette ?? SpaceTheme.presets[0].palette
        background = PaletteBackgroundView(palette: palette)
        list = SpaceListView(spaceID: spaceID, store: store, ui: ui, actions: actions, favicons: favicons)
        list.showsNewTab = false
        super.init(frame: .zero)
        move.onDrag = { [weak self] dx in self?.onMove?(dx) }
        move.onEnd = { [weak self] in self?.onMoveEnd?() }
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        symbol.imageScaling = .scaleNone
        badge.isHidden = true
        for v in [background, emoji, symbol, title, badge, list, brush, move, more] as [NSView] { addSubview(v) }
        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func sync() {
        withObservationTracking {
            guard let s = store.space(spaceID) else { return }
            emoji.stringValue = s.emoji
            symbol.image = s.symbol.flatMap { SidebarSymbols.image($0, size: 13, weight: .medium) }
            title.stringValue = s.title
            background.palette = s.theme.palette
            colors = SidebarColors(s.theme.palette)
            let profile = store.profileBadge(space: spaceID, in: .library)
            showsBadge = profile != nil
            if let profile { badge.show(name: profile.name, look: profile.look, colors: colors) }
        } onChange: { [weak self] in
            Task { @MainActor in self?.sync() }
        }
        title.textColor = colors.textSecondary
        symbol.contentTintColor = colors.textSecondary
        for b in [brush, more] { b.colors = colors }
        move.tint = colors.isDark ? NSColor.white.withAlphaComponent(0.55) : colors.glyph
        needsLayout = true
    }

    var debugBadge: String { badge.isHidden ? "none" : "\(badge.name)\(badge.showsName ? "" : "(icon only)")" }

    private func showMenu() {
        guard let event = NSApp.currentEvent,
              let down = NSEvent.mouseEvent(with: .rightMouseDown, location: event.locationInWindow, modifierFlags: [],
                                            timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
                                            eventNumber: 0, clickCount: 1, pressure: 1),
              let m = SpaceMenu.make(spaceID: spaceID, store: store, ui: ui, actions: actions, anchor: self, from: .library, rename: {}) else { return }
        NSMenu.popUpContextMenu(m, with: down, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        SpaceMenu.make(spaceID: spaceID, store: store, ui: ui, actions: actions, anchor: self, from: .library, rename: {})
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        background.frame = bounds
        let es = emoji.intrinsicContentSize
        let ew = ceil(emoji.attributedStringValue.size().width)
        emoji.frame = NSRect(x: 25.5 - ew / 2 - SidebarText.inset, y: 25 - es.height / 2, width: ew + 2 * SidebarText.inset, height: es.height)
        symbol.frame = NSRect(x: 12.5, y: 12, width: 26, height: 26)
        let th = title.intrinsicContentSize.height
        let tw = badge.place(besideTitle: ceil(title.attributedStringValue.size().width), from: 44, to: 213 - 13 - 4, midY: 25, shown: showsBadge)
        title.frame = NSRect(x: 44 - SidebarText.inset, y: 25 - th / 2, width: tw + 2 * SidebarText.inset, height: th)
        brush.frame = NSRect(x: 213 - 13, y: 12, width: 26, height: 26)
        // The first pinned row is centred 64 pt down: rows are 41 pt, 3 pt into the list.
        list.frame = NSRect(x: 0, y: 40.5, width: w, height: max(0, h - 40.5 - 42))
        move.frame = NSRect(x: 22 - 13, y: h - 21 - 13, width: 26, height: 26)
        more.frame = NSRect(x: 217.5 - 13, y: h - 21 - 13, width: 26, height: 26)
    }
}

/// The card's move handle (Arc's four-way arrow): reports how far it has been dragged.
private final class SpaceMoveHandle: NSView {
    var onDrag: (CGFloat) -> Void = { _ in }
    var onEnd: () -> Void = {}
    var tint: NSColor = .secondaryLabelColor { didSet { glyph.contentTintColor = tint } }
    private let glyph = NSImageView()
    private var start: CGFloat?

    override init(frame: NSRect) {
        super.init(frame: frame)
        glyph.image = SidebarSymbols.image("arrow.up.and.down.and.arrow.left.and.right", size: 13, weight: .medium)
        glyph.imageScaling = .scaleNone
        glyph.autoresizingMask = [.width, .height]
        addSubview(glyph)
        setAccessibilityLabel("Move Space")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        glyph.frame = bounds
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        start = event.locationInWindow.x
        NSCursor.closedHand.push()
    }
    override func mouseDragged(with event: NSEvent) {
        if let start { onDrag(event.locationInWindow.x - start) }
    }
    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil
        NSCursor.pop()
        onEnd()
    }
}

/// The cards' row. Like the tab lists (SidebarListScrollView) it stays off responsive scrolling,
/// which would take a gesture's events past the window's scroll monitor once it starts here:
/// a swipe that starts with the cards at their end has to reach the monitor to leave the Library.
final class SpacesStripScrollView: NSScrollView {
    override class var isCompatibleWithResponsiveScrolling: Bool { false }
}
