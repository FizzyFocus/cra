import AppKit

extension NSPasteboard.PasteboardType {
    /// A bookmark or a bookmark folder dragged from the Library (BookmarkDrag).
    static let craBookmark = NSPasteboard.PasteboardType("dk.kildahl.cra.bookmark")
}

/// A Library bookmark drag in flight: what it carries, and word to every window so the page card
/// takes a drop of it (ShellView.pageDrop) before the page itself would.
enum BookmarkDrag {
    static let began = Notification.Name("CraBookmarkDragBegan")
    static let ended = Notification.Name("CraBookmarkDragEnded")

    static func data(_ key: BookmarkLibrary.OutlineRow.Key) -> Data? {
        switch key {
        case .bookmark(let id): return Data("bookmark:\(id.uuidString)".utf8)
        case .folder(let id): return Data("folder:\(id.uuidString)".utf8)
        case .empty: return nil
        }
    }

    static func key(_ pasteboard: NSPasteboard) -> BookmarkLibrary.OutlineRow.Key? {
        guard let d = pasteboard.data(forType: .craBookmark), let s = String(data: d, encoding: .utf8) else { return nil }
        let parts = s.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        return parts[0] == "folder" ? .folder(id) : .bookmark(id)
    }

    /// The address a dragged bookmark opens.
    @MainActor static func url(_ pasteboard: NSPasteboard) -> String? {
        guard case .bookmark(let id)? = key(pasteboard) else { return nil }
        return BookmarkStore.shared.library.bookmarks.first { $0.id == id }?.url
    }
}

/// Library ▸ Bookmarks: the folders and bookmarks drawn and moved the way the sidebar's pinned
/// list draws and moves its folders and tabs. Rows are 40 pt on a 41 pt pitch, 8 pt in from the
/// sides; a folder is Arc's folder glyph, which opens as its folder does, with the space header's
/// chevron turning on SpringMotion.disclosure at the row's end; a folder opens like an accordion,
/// its rows sliding down from under its row inside a clip that grows as the rows below move down,
/// on the list's own curve (SidebarListMetrics, FoldClipView), and closes back up into it.
///
/// The outline owns the hover: one tracking area and one lit row at most, found from where the
/// pointer really is (BookmarkLibrary.row(at:)) on every move, scroll and change of the rows. Rows
/// that each tracked themselves lit two at once after a fold or a reopen (10 Nov 2026).
///
/// Rows drag: into a folder (dropped on it or on a row inside it), to the top of the tree (the
/// blank space), onto the page card to open (ShellView.pageDrop) or out of Cra as a link. A closed
/// folder held under a drag opens.
final class BookmarkOutlineView: NSView, NSDraggingSource {
    typealias Row = BookmarkLibrary.OutlineRow

    var colors = SidebarColors() { didSet { if colors != oldValue { restyle() } } }
    /// The space's palette: the folder glyph's tones (its own colour first, FolderColor).
    var palette: SpacePalette? { didSet { restyle() } }
    var favicon: (String) -> NSImage? = { _ in nil }
    var toggle: (BookmarkFolder, Bool) -> Void = { _, _ in }
    var open: (Bookmark) -> Void = { _ in }
    /// A row's menu, or the blank space's (nil).
    var menuFor: (Row?, NSView?) -> NSMenu? = { _, _ in nil }

    private(set) var rows: [Row] = []
    private var views: [Row.Key: BookmarkOutlineCell] = [:]
    private var frames: [Row.Key: NSRect] = [:]
    /// Folds in flight: the clips a folder's rows move in.
    private var folds: [FoldClipView] = []
    /// The rows' height, without the blank below them.
    private(set) var contentHeight: CGFloat = 0
    private var laidOutWidth: CGFloat = 0
    /// The one row lit under the pointer.
    private var hoveredKey: Row.Key?
    /// The row being dragged from here, while its drag is on.
    private var draggedKey: Row.Key?
    /// The folder a drag over the outline would go into (its row lit).
    private var dropFolder: UUID?
    /// Where the drop on offer would go, for the haptic tick when that changes.
    private enum DropTarget: Equatable { case folder(UUID), top }
    private var offeredTarget: DropTarget?
    private var springTimer: Timer?
    private var springFolder: UUID?
    private var clipObserver: NSObjectProtocol?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.craBookmark])
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let clipObserver { NotificationCenter.default.removeObserver(clipObserver) }
    }

    override var isFlipped: Bool { true }

    override func menu(for event: NSEvent) -> NSMenu? { menuFor(nil, nil) }

    /// Shows `new`. `animated`: a folder opening or closing folds its rows; other rows come and go
    /// in place. A search, a theme or the page coming up shows them at once.
    func apply(_ new: [Row], animated: Bool) {
        settleFolds()
        let old = rows
        rows = new
        let oldOpen = Self.openFolders(old), newOpen = Self.openFolders(new)
        var oldParents: [Row.Key: UUID] = [:]
        for r in old { if let p = r.parent { oldParents[r.key] = p } }
        var folderParents: [UUID: UUID] = [:]
        for r in old + new { if case .folder(let f, _, _, _) = r, let p = f.parentId { folderParents[f.id] = p } }

        var fresh: [BookmarkOutlineCell] = []
        let keys = Set(new.map(\.key))
        var gone: [(Row.Key, BookmarkOutlineCell)] = []
        for (k, v) in views where !keys.contains(k) { gone.append((k, v)) }
        for (k, _) in gone { views[k] = nil }
        for r in new {
            let toggled: Bool
            if case .folder(let f, _, let open, _) = r, let was = oldOpen[f.id] { toggled = was != open } else { toggled = false }
            let v: BookmarkOutlineCell
            if let existing = views[r.key] {
                v = existing
            } else {
                v = BookmarkOutlineCell()
                views[r.key] = v
                addSubview(v)
                fresh.append(v)
            }
            configure(v, r, animated: animated && toggled)
        }
        layoutRows()
        let motion = animated && window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard motion else {
            for r in new { views[r.key]?.frame = frames[r.key] ?? .zero; views[r.key]?.alphaValue = 1 }
            gone.forEach { $0.1.removeFromSuperview() }
            refreshHover()
            return
        }
        place(fresh: fresh, gone: gone, oldOpen: oldOpen, newOpen: newOpen, oldParents: oldParents, folderParents: folderParents)
        refreshHover()
    }

    private func configure(_ v: BookmarkOutlineCell, _ r: Row, animated: Bool) {
        let icon: NSImage?
        if case .bookmark(let b, _) = r { icon = favicon(b.url) } else { icon = nil }
        v.show(r, icon: icon, colors: colors, palette: palette, animated: animated)
        v.onClick = { [weak self] in
            switch r {
            case .folder(let f, _, let open, _): self?.toggle(f, !open)
            case .bookmark(let b, _): self?.open(b)
            case .emptyFolder: break
            }
        }
        v.menuProvider = { [weak self, weak v] in self?.menuFor(r, v) }
        v.beginDrag = { [weak self, weak v] event in if let v { self?.beginDrag(v, event: event) } }
        v.hovering = r.key == hoveredKey
        v.dropTarget = dropFolder.map { r.key == .folder($0) } ?? false
    }

    private func restyle() {
        for r in rows { if let v = views[r.key] { configure(v, r, animated: false) } }
    }

    private static func openFolders(_ rows: [Row]) -> [UUID: Bool] {
        var out: [UUID: Bool] = [:]
        for r in rows { if case .folder(let f, _, let open, _) = r { out[f.id] = open } }
        return out
    }

    // MARK: Layout

    /// The pinned list's stack: rows 1 pt apart, 8 pt in from the sides.
    private func layoutRows() {
        let width = bounds.width
        let inner = max(0, width - 2 * CraMetrics.rowInset)
        var y: CGFloat = 0
        frames = [:]
        for (i, r) in rows.enumerated() {
            if i > 0 { y += CraMetrics.rowSpacing }
            let h = BookmarkOutlineCell.height(r)
            frames[r.key] = NSRect(x: CraMetrics.rowInset, y: y, width: inner, height: h)
            y += h
        }
        contentHeight = y
        laidOutWidth = width
        let height = max(y + 12, superview?.bounds.height ?? 0)
        if frame.height != height { setFrameSize(NSSize(width: width, height: height)) }
    }

    override func layout() {
        super.layout()
        guard bounds.width != laidOutWidth else { return }
        settleFolds()
        layoutRows()
        for r in rows { views[r.key]?.frame = frames[r.key] ?? .zero }
        refreshHover()
    }

    /// The scroll view resized: the document fills it, rows keep their places.
    func fit(width: CGFloat) {
        guard width != frame.width || frame.height < (superview?.bounds.height ?? 0) else { return }
        setFrameSize(NSSize(width: width, height: max(contentHeight + 12, superview?.bounds.height ?? 0)))
        needsLayout = true
    }

    // MARK: The fold (SpaceListView.placeViews, for this list)

    private func place(fresh: [BookmarkOutlineCell], gone: [(Row.Key, BookmarkOutlineCell)], oldOpen: [UUID: Bool],
                       newOpen: [UUID: Bool], oldParents: [Row.Key: UUID], folderParents: [UUID: UUID]) {
        let freshSet = Set(fresh.map(ObjectIdentifier.init))
        /// The folder that opened (or closed) outermost above an item: its rows, nested ones too, fold with it.
        func root(from parent: UUID?, opening: Bool) -> (frame: NSRect, view: BookmarkOutlineCell)? {
            var found: (NSRect, BookmarkOutlineCell)?
            var next = parent, steps = 0
            while let id = next, steps < 64 {
                if newOpen[id] == opening, oldOpen[id] == !opening, let f = frames[.folder(id)], let v = views[.folder(id)] { found = (f, v) }
                next = folderParents[id]
                steps += 1
            }
            return found.map { (frame: $0.0, view: $0.1) }
        }
        struct Group { var folder: NSRect; var folderView: BookmarkOutlineCell; var rows: [(NSView, NSRect)] }
        var opening: [ObjectIdentifier: Group] = [:]
        for r in rows {
            guard let v = views[r.key], freshSet.contains(ObjectIdentifier(v)), let target = frames[r.key] else { continue }
            if r.depth > 0, let g = root(from: r.parent, opening: true) {
                opening[ObjectIdentifier(g.view), default: Group(folder: g.frame, folderView: g.view, rows: [])].rows.append((v, target))
            } else {
                v.frame = target
                v.alphaValue = 0
            }
        }
        var closing: [ObjectIdentifier: Group] = [:]
        for (k, v) in gone {
            guard let g = root(from: oldParents[k], opening: false) else { continue }
            closing[ObjectIdentifier(g.view), default: Group(folder: g.frame, folderView: g.view, rows: [])].rows.append((v, v.frame))
        }
        let width = bounds.width
        var clipped = Set<ObjectIdentifier>()
        var moves: [(NSView, NSRect)] = []
        var fadingIn: [NSView] = []
        var clips: [FoldClipView] = []
        // Opening: the clip grows from the folder row's bottom edge; the rows inside start a clip's
        // height up, so their bottom rides its edge down.
        for g in opening.values {
            let top = g.folder.maxY, from = g.folderView.frame.maxY
            let height = max(0, (g.rows.map(\.1.maxY).max() ?? top) - top)
            let clip = FoldClipView(frame: NSRect(x: 0, y: from, width: width, height: 0))
            addSubview(clip, positioned: .below, relativeTo: g.folderView)
            clips.append(clip)
            for (v, target) in g.rows {
                clip.addSubview(v)
                v.alphaValue = 0
                fadingIn.append(v)
                v.frame = NSRect(x: target.minX, y: target.minY - top - height, width: target.width, height: target.height)
                moves.append((v, NSRect(x: target.minX, y: target.minY - top, width: target.width, height: target.height)))
                clipped.insert(ObjectIdentifier(v))
            }
            moves.append((clip, NSRect(x: 0, y: top, width: width, height: height)))
        }
        // Closing: the rows slide up by the clip's height while it shrinks to the folder row's edge.
        var folded: [NSView] = []
        for g in closing.values {
            let from = g.folderView.frame.maxY, to = g.folder.maxY
            let height = max(0, (g.rows.map(\.1.maxY).max() ?? from) - from)
            let clip = FoldClipView(frame: NSRect(x: 0, y: from, width: width, height: height))
            addSubview(clip, positioned: .below, relativeTo: g.folderView)
            clips.append(clip)
            for (v, f) in g.rows {
                clip.addSubview(v)
                let inside = NSRect(x: f.minX, y: f.minY - from, width: f.width, height: f.height)
                v.frame = inside
                moves.append((v, inside.offsetBy(dx: 0, dy: -height)))
                clipped.insert(ObjectIdentifier(v))
                folded.append(v)
            }
            moves.append((clip, NSRect(x: 0, y: to, width: width, height: 0)))
        }
        folds += clips
        let goneViews = gone.map(\.1)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = SidebarListMetrics.duration
            ctx.timingFunction = SidebarListMetrics.timing
            ctx.allowsImplicitAnimation = true
            for r in rows {
                guard let v = views[r.key], !clipped.contains(ObjectIdentifier(v)), let f = frames[r.key] else { continue }
                if v.frame != f { v.animator().frame = f }
                if freshSet.contains(ObjectIdentifier(v)) { v.animator().alphaValue = 1 }
            }
            for (v, f) in moves { v.animator().frame = f }
            for v in fadingIn { v.animator().alphaValue = 1 }
            for v in goneViews where !clipped.contains(ObjectIdentifier(v)) { v.animator().alphaValue = 0 }
        } completionHandler: { [weak self] in
            goneViews.forEach { $0.removeFromSuperview() }
            for clip in clips { self?.settle(clip) }
            self?.refreshHover()
        }
        // Closing rows are gone a little before the fold shuts.
        if !folded.isEmpty {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = SidebarListMetrics.duration * 0.7
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                for v in folded { v.animator().alphaValue = 0 }
            }
        }
    }

    private func settleFolds() {
        for clip in folds { settle(clip) }
    }

    /// A fold's rows go back into the list where they belong; rows that left go for good.
    private func settle(_ clip: FoldClipView) {
        guard let i = folds.firstIndex(where: { $0 === clip }) else { return }
        folds.remove(at: i)
        var placedByView: [ObjectIdentifier: NSRect] = [:]
        for r in rows { if let v = views[r.key], let f = frames[r.key] { placedByView[ObjectIdentifier(v)] = f } }
        for v in clip.subviews {
            guard let f = placedByView[ObjectIdentifier(v)] else { v.removeFromSuperview(); continue }
            addSubview(v, positioned: .below, relativeTo: clip)
            v.layer?.removeAllAnimations()
            v.frame = f
            v.alphaValue = 1
        }
        clip.removeFromSuperview()
    }
}

// MARK: Hover

extension BookmarkOutlineView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        refreshHover()
    }

    override func mouseEntered(with event: NSEvent) { refreshHover() }
    override func mouseMoved(with event: NSEvent) { refreshHover() }
    override func mouseExited(with event: NSEvent) { setHover(nil) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshHover()
    }

    /// Scrolling moves the rows under a still pointer: the hover follows the scroll.
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let clipObserver { NotificationCenter.default.removeObserver(clipObserver) }
        clipObserver = nil
        guard let clip = superview as? NSClipView else { return }
        clip.postsBoundsChangedNotifications = true
        clipObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.refreshHover() }
        }
    }

    /// The row under the pointer, found from where it really is; none while a drag is on.
    func refreshHover() {
        guard let w = window, w.isVisible, !isHiddenOrHasHiddenAncestor, draggedKey == nil else { return setHover(nil) }
        let p = convert(w.mouseLocationOutsideOfEventStream, from: nil)
        guard visibleRect.contains(p) else { return setHover(nil) }
        setHover(row(at: p)?.key)
    }

    /// The row at a point in the outline: exactly one or none (the 1 pt between rows is neither's).
    func row(at p: NSPoint) -> Row? {
        let spans = rows.map { r -> (top: Double, height: Double) in
            let f = frames[r.key] ?? .zero
            return (Double(f.minY), Double(f.height))
        }
        guard let i = BookmarkLibrary.row(at: Double(p.y), frames: spans), let f = frames[rows[i].key],
              p.x >= f.minX, p.x < f.maxX else { return nil }
        return rows[i]
    }

    /// Lights `key`'s row and puts every other one out: never two at once.
    private func setHover(_ key: Row.Key?) {
        hoveredKey = key
        for (k, v) in views where v.hovering != (k == key) { v.hovering = k == key }
    }
}

// MARK: Drag and drop

extension BookmarkOutlineView {
    /// A row pulled past the drag threshold: it carries its bookmark (and, out of Cra, its link).
    func beginDrag(_ cell: BookmarkOutlineCell, event: NSEvent) {
        let key = cell.row.key
        guard let data = BookmarkDrag.data(key) else { return }
        let pb = NSPasteboardItem()
        pb.setData(data, forType: .craBookmark)
        if case .bookmark(let b, _) = cell.row {
            pb.setString(b.url, forType: .URL)
            pb.setString(b.url, forType: .string)
        }
        let item = NSDraggingItem(pasteboardWriter: pb)
        let image = dragImage(of: cell.row, width: cell.bounds.width)
        item.setDraggingFrame(NSRect(origin: .zero, size: image.size), contents: image)
        draggedKey = key
        setHover(nil)
        NotificationCenter.default.post(name: BookmarkDrag.began, object: nil)
        cell.beginDraggingSession(with: [item], event: event, source: self)
    }

    /// What rides under the pointer: the row drawn as a sidebar tab is while dragged (SpaceListView's
    /// drag image), at the top level whatever its depth, 40 pt tall, its title in the tab's 14 pt, on
    /// a card with the row's 10 pt corners. A tab has its ✕; a bookmark has none.
    private func dragImage(of row: Row, width: CGFloat) -> NSImage {
        let flat: Row
        switch row {
        case .folder(let f, _, let open, let empty): flat = .folder(f, depth: 0, open: open, empty: empty)
        case .bookmark(let b, _): flat = .bookmark(b, depth: 0)
        case .emptyFolder(let id, _): flat = .emptyFolder(in: id, depth: 0)
        }
        let ghost = BookmarkOutlineCell()
        ghost.frame = NSRect(x: 0, y: 0, width: width, height: CraMetrics.rowHeight)
        let icon: NSImage?
        if case .bookmark(let b, _) = flat { icon = favicon(b.url) } else { icon = nil }
        ghost.show(flat, icon: icon, colors: colors, palette: palette, animated: false)
        // Drawn in the window (its appearance and scale), gone again before anything shows.
        addSubview(ghost)
        ghost.layoutSubtreeIfNeeded()
        let rep = ghost.bitmapImageRepForCachingDisplay(in: ghost.bounds)
        if let rep { ghost.cacheDisplay(in: ghost.bounds, to: rep) }
        ghost.removeFromSuperview()
        let fill = colors.isDark ? NSColor(white: 0.18, alpha: 0.92) : NSColor(white: 1, alpha: 0.92)
        return NSImage(size: ghost.bounds.size, flipped: false) { r in
            fill.setFill()
            NSBezierPath(roundedRect: r, xRadius: CraMetrics.rowCorner, yRadius: CraMetrics.rowCorner).fill()
            rep?.draw(in: r)
            return true
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy, .generic] : .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        draggedKey = nil
        setDropFolder(nil, offered: false)
        NotificationCenter.default.post(name: BookmarkDrag.ended, object: nil)
        refreshHover()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dragUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dragUpdated(sender) }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropFolder(nil, offered: false)
        holdOver(nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let key = BookmarkDrag.key(sender.draggingPasteboard) else { return false }
        let target = dropTarget(at: convert(sender.draggingLocation, from: nil))
        setDropFolder(nil, offered: false)
        holdOver(nil)
        return BookmarkStore.shared.move(key, into: target)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        setDropFolder(nil, offered: false)
        holdOver(nil)
    }

    /// Over a folder: into it; over a row inside a folder: into that folder; over the blank space:
    /// to the top of the tree.
    private func dropTarget(at p: NSPoint) -> UUID? { row(at: p)?.dropFolder }

    private func dragUpdated(_ info: NSDraggingInfo) -> NSDragOperation {
        guard let key = BookmarkDrag.key(info.draggingPasteboard) else { return [] }
        let p = convert(info.draggingLocation, from: nil)
        let target = dropTarget(at: p)
        // A closed folder held under the drag opens, as Finder's do.
        if case .folder(let f, _, let open, _)? = row(at: p), !open { holdOver(f.id) } else { holdOver(nil) }
        guard BookmarkStore.shared.library.canMove(key, into: target) else {
            setDropFolder(nil, offered: false)
            return []
        }
        setDropFolder(target, offered: true)
        return .move
    }

    private func setDropFolder(_ folder: UUID?, offered: Bool) {
        let lit = offered ? folder : nil
        let target: DropTarget? = offered ? (folder.map(DropTarget.folder) ?? .top) : nil
        // A tick each time the drop would go somewhere else (a folder lighting, the top of the
        // tree), as the sidebar ticks when a row starts offering to take a tab.
        if let target, target != offeredTarget {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
        }
        offeredTarget = target
        guard lit != dropFolder || (!offered && dropFolder != nil) else { return }
        dropFolder = lit
        for (k, v) in views { v.dropTarget = lit.map { k == .folder($0) } ?? false }
    }

    /// Spring-loading: 0.7 s on a closed folder opens it.
    private func holdOver(_ folder: UUID?) {
        guard folder != springFolder else { return }
        springFolder = folder
        springTimer?.invalidate()
        springTimer = nil
        guard let folder else { return }
        springTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.springFolder == folder, let f = BookmarkStore.shared.library.folder(folder) else { return }
                self.springFolder = nil
                self.toggle(f, true)
            }
        }
    }
}

/// One row of the outline. A folder is the pinned list's folder row (FolderRowView): Arc's
/// folder glyph, opening and closing with its folder, 14 pt medium title, the closed folder's
/// count on hover, and the space header's chevron at its end, turned a quarter on
/// SpringMotion.disclosure. A bookmark is a pinned tab's row: its icon and title.
final class BookmarkOutlineCell: NSView {
    typealias Row = BookmarkLibrary.OutlineRow

    private let fill = CALayer()
    private let folderGlyph = FolderGlyphView(frame: NSRect(x: 0, y: 0, width: CraMetrics.favicon, height: 20))
    private let icon = NSImageView()
    private let title = NSTextField.sidebarLabel(size: 14, weight: .medium)
    private let count = NSTextField.sidebarLabel(size: 11, weight: .medium)
    /// Holds the chevron at a fixed frame, so it turns about its own centre (SpaceHeaderView).
    private let chevronBox = NSView()
    private let chevron = NSImageView()
    private(set) var row: Row = .emptyFolder(in: UUID(), depth: 0)
    private var colors = SidebarColors()
    var onClick: () -> Void = {}
    var menuProvider: (() -> NSMenu?)?
    /// Pulled past the drag threshold: the outline starts the drag.
    var beginDrag: (NSEvent) -> Void = { _ in }
    /// Lit by the outline, which owns the hover (one row at most).
    var hovering = false { didSet { if hovering != oldValue { refreshHover() } } }
    /// A folder a drag over the outline would go into.
    var dropTarget = false { didSet { if dropTarget != oldValue { refreshHover() } } }
    private var downAt: NSPoint?
    private var dragged = false

    static func height(_ r: Row) -> CGFloat {
        if case .emptyFolder = r { return 32 }
        return CraMetrics.rowHeight
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        fill.cornerRadius = CraMetrics.rowCorner
        fill.cornerCurve = .continuous
        fill.actions = ["backgroundColor": NSNull(), "position": NSNull(), "bounds": NSNull()]
        layer?.addSublayer(fill)
        icon.imageScaling = .scaleProportionallyDown
        chevron.image = SidebarSymbols.image("chevron.down", size: 12.5, weight: .bold)
        chevron.imageScaling = .scaleNone
        chevron.wantsLayer = true
        chevron.frame = NSRect(x: 0, y: 0, width: 20, height: 20)
        chevronBox.addSubview(chevron)
        for v in [folderGlyph, icon, title, count, chevronBox] as [NSView] { addSubview(v) }
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

    func show(_ r: Row, icon image: NSImage?, colors: SidebarColors, palette: SpacePalette?, animated: Bool) {
        row = r
        self.colors = colors
        title.textColor = colors.textPrimary
        count.textColor = colors.textTertiary
        chevron.contentTintColor = colors.textSecondary
        switch r {
        case .folder(let f, _, let open, _):
            let tones = palette?.folderColors(nil, color: f.color)
            folderGlyph.isHidden = false
            folderGlyph.show(expanded: open, tint: tones.map { NSColor($0.tint) } ?? colors.textSecondary,
                             fillColor: tones.map { NSColor($0.fill) } ?? colors.hoverFill,
                             backColor: tones.map { NSColor($0.back) }, animated: animated && window != nil)
            icon.isHidden = true
            title.stringValue = f.title
            title.font = .systemFont(ofSize: 14, weight: .medium)
            let n = BookmarkStore.shared.library.bookmarkCount(in: f.id)
            count.stringValue = "\(n)"
            chevronBox.isHidden = false
            turnChevron(open: open, animated: animated)
            toolTip = nil
            setAccessibilityLabel("\(f.title), folder, \(open ? "open" : "closed")")
        case .bookmark(let b, _):
            folderGlyph.isHidden = true
            icon.isHidden = false
            icon.image = image ?? SidebarSymbols.image("globe", size: 14)
            icon.contentTintColor = image == nil ? colors.textTertiary : nil
            title.stringValue = b.title
            // A tab row's title: 14 pt regular (a folder's is medium, as the pinned list's).
            title.font = .systemFont(ofSize: 14)
            chevronBox.isHidden = true
            toolTip = b.url
            setAccessibilityLabel(b.title)
        case .emptyFolder:
            folderGlyph.isHidden = true
            icon.isHidden = true
            title.stringValue = "Folder is empty"
            title.font = NSFontManager.shared.convert(.systemFont(ofSize: 12), toHaveTrait: .italicFontMask)
            title.textColor = colors.textTertiary
            chevronBox.isHidden = true
            toolTip = nil
            setAccessibilityLabel("Folder is empty")
        }
        refreshHover()
        needsLayout = true
    }

    /// Where the row's fill starts: after its indent, as a nested pinned row's does (#139).
    private var fillLeading: CGFloat { CGFloat(row.depth) * CraMetrics.indent }

    override func layout() {
        super.layout()
        let h = bounds.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = CGRect(x: fillLeading, y: SidebarRowView.fillInset, width: max(0, bounds.width - fillLeading),
                            height: max(0, h - 2 * SidebarRowView.fillInset))
        CATransaction.commit()
        var x = CraMetrics.rowLeading + CGFloat(row.depth) * CraMetrics.indent
        folderGlyph.frame = NSRect(x: x, y: (h - 20) / 2, width: CraMetrics.favicon, height: 20)
        icon.frame = NSRect(x: x, y: (h - CraMetrics.favicon) / 2, width: CraMetrics.favicon, height: CraMetrics.favicon)
        if case .emptyFolder = row {
            // In line with the titles of the rows beside it.
        } else {
            x += CraMetrics.favicon + 11
        }
        var right = bounds.width - 8
        if !chevronBox.isHidden {
            chevronBox.frame = NSRect(x: right - 20, y: (h - 20) / 2, width: 20, height: 20)
            right -= 20 + 4
        }
        if !count.isHidden {
            count.sizeToFit()
            let s = count.frame.size
            count.frame = NSRect(x: right - s.width, y: (h - s.height) / 2, width: s.width, height: s.height)
            right -= s.width + 8
        }
        let th = title.intrinsicContentSize.height
        title.frame = NSRect(x: x - SidebarText.inset, y: (h - th) / 2, width: max(0, right - x) + 2 * SidebarText.inset, height: th)
    }

    private func refreshHover() {
        var interactive = true
        if case .emptyFolder = row { interactive = false }
        let fillColor: NSColor = dropTarget ? colors.selectedFill : (hovering && interactive ? colors.hoverFill : .clear)
        fill.backgroundColor = fillColor.cgColor
        // A closed folder shows how many bookmarks it holds under the pointer, as a pinned folder its tabs.
        if case .folder(_, _, let open, _) = row { count.isHidden = !(hovering && !open) } else { count.isHidden = true }
        needsLayout = true
    }

    // MARK: The chevron (SpaceHeaderView.turnChevron)

    private var chevronTurn: (start: CFTimeInterval, from: CGFloat, to: CGFloat)?
    private var chevronLink: CADisplayLink?

    /// Down while the folder is open, right while it is closed, a quarter turn between on the
    /// disclosure spring, picked up from wherever it is; at once with Reduce Motion.
    private func turnChevron(open: Bool, animated: Bool) {
        let degrees: CGFloat = open ? 0 : 90
        guard animated, window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            stopChevron()
            chevron.frameCenterRotation = degrees
            return
        }
        chevronTurn = (CACurrentMediaTime(), chevron.frameCenterRotation, degrees)
        if chevronLink == nil {
            let l = displayLink(target: self, selector: #selector(stepChevron))
            l.add(to: .main, forMode: .common)
            chevronLink = l
        }
    }

    @objc private func stepChevron(_ link: CADisplayLink) {
        guard let turn = chevronTurn else { stopChevron(); return }
        let spring = SpringMotion.disclosure
        let t = link.targetTimestamp - turn.start
        guard t < spring.settlingDuration else {
            chevron.frameCenterRotation = turn.to
            stopChevron()
            return
        }
        chevron.frameCenterRotation = turn.to + (turn.from - turn.to) * CGFloat(spring.offset(at: t))
    }

    private func stopChevron() {
        chevronTurn = nil
        chevronLink?.invalidate()
        chevronLink = nil
    }

    // MARK: Pointer

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil, let turn = chevronTurn {
            stopChevron()
            chevron.frameCenterRotation = turn.to
        }
    }

    override func mouseDown(with event: NSEvent) {
        downAt = event.locationInWindow
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downAt, !dragged else { return }
        if case .emptyFolder = row { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 4 else { return }
        dragged = true
        beginDrag(event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { downAt = nil }
        guard !dragged, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick()
        return true
    }
}

/// Icon Color's own colours (FolderColor), for pinned folders and bookmark folders: each with its
/// swatch, the folder's ticked.
@MainActor
enum FolderColorMenu {
    static func add(to menu: NSMenu, current: String?, set: @escaping (String?) -> Void) {
        menu.addItem(.separator())
        for c in FolderColor.catalogue {
            let on = current.map { $0.caseInsensitiveCompare(c.hex) == .orderedSame } ?? false
            MenuItems.add(menu, c.name, on: on, image: swatch(c.hex)) { set(c.hex) }
        }
    }

    /// A 12 pt dot of the colour with a faint rim, so a light one shows on a light menu.
    static func swatch(_ hex: String) -> NSImage {
        let color = NSColor(hex: hex)
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { r in
            color.setFill()
            NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5)).fill()
            NSColor.black.withAlphaComponent(0.18).setStroke()
            let rim = NSBezierPath(ovalIn: r.insetBy(dx: 0.5, dy: 0.5))
            rim.lineWidth = 0.5
            rim.stroke()
            return true
        }
        return image
    }
}
