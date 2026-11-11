import AppKit
import UniformTypeIdentifiers

/// Arc's downloads list: hovering the Library button lists the recent downloads over the
/// bottom of the sidebar, newest at the bottom, and the tab list behind them fades out.
/// Its rows are on Cra's grid (CraCore DownloadsTrayLayout, 11 Nov 2026): 48 pt rows, the icon a
/// 32 pt square 12 pt in, the name (14 pt) and its age (12 pt) 10 pt after it, the hover fill the
/// whole row with 8 pt corners. From Arc 1.170 (27 Oct 2026): the tab list is hidden from 3 pt
/// above the first row and fades back in over the 170 pt above that; it opens 0.2 s into the
/// hover, rows rising 5 pt and fading in bottom first 25 ms apart, and closes 0.07 s after the
/// pointer leaves.
enum DownloadsTrayMetrics {
    static let rowPitch = CGFloat(DownloadsTrayLayout.rowPitch)
    /// The icon's square.
    static let thumbnail = CGFloat(DownloadsTrayLayout.icon)
    static let fade: CGFloat = 170
    /// Between the newest row and the bottom of the list's area (the dock is 8 pt under that):
    /// Arc's rows sit right above the dock, with no gap the pointer has to cross (11 Nov 2026).
    static let bottomClearance = CGFloat(DownloadsTrayLayout.bottomGap)
    static func listHeight(rows: Int) -> CGFloat { CGFloat(DownloadsTrayLayout.listHeight(rows: rows)) }
}

extension SidebarUIState {
    func downloadsHoverChanged() {
        // Riding away with the floating sidebar: it closes once the sidebar is gone, in one motion.
        if let until = downloadsRideAlongUntil, until > Date() { return }
        downloadsListWork?.cancel()
        let open = DownloadsTrayHold.isOpen(hovered: libraryHovered || downloadsListHovered, previewOpen: downloadsPreviewOpen,
                                            graceUntil: downloadsGraceUntil, now: Date(), hasRows: !DownloadHistory.shared.recent.isEmpty)
        guard open != downloadsListOpen else { return }
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.downloadsListOpen = open } }
        downloadsListWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (open ? 0.2 : 0.07), execute: work)
    }

    /// A preview opened from a tray row: the tray stays out behind it.
    func downloadsPreviewOpened() {
        downloadsPreviewOpen = true
        downloadsGraceUntil = nil
        downloadsHoverChanged()
    }

    /// The preview closed: the tray waits DownloadsTrayHold.grace for the pointer, then goes unless
    /// the pointer is on it or the Library button.
    func downloadsPreviewClosed() {
        downloadsPreviewOpen = false
        let grace = DownloadsTrayHold.grace
        downloadsGraceUntil = Date().addingTimeInterval(grace)
        downloadsGraceGeneration &+= 1
        let generation = downloadsGraceGeneration
        downloadsTray?.syncHover()
        downloadsHoverChanged()
        CraLog.note("downloads list waits \(Int(grace)) s after the preview")
        DispatchQueue.main.asyncAfter(deadline: .now() + grace + 0.02) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.downloadsGraceGeneration == generation else { return }
                self.downloadsGraceUntil = nil
                self.downloadsTray?.syncHover()
                self.downloadsHoverChanged()
            }
        }
    }

    /// The floating sidebar is sliding away: an open tray goes with it as it is (no closing of its
    /// own on the way), then closes out of sight (`downloadsRodeAway`).
    func downloadsRideAway(for duration: TimeInterval) {
        guard downloadsListOpen else { return }
        downloadsListWork?.cancel()
        downloadsPreviewOpen = false
        downloadsGraceUntil = nil
        downloadsGraceGeneration &+= 1
        downloadsRideAlongUntil = Date().addingTimeInterval(duration)
        CraLog.note("downloads list leaves with the floating sidebar")
    }

    func downloadsRodeAway() {
        guard downloadsRideAlongUntil != nil else { return }
        downloadsRideAlongUntil = nil
        libraryHovered = false
        downloadsListHovered = false
        downloadsListOpen = false
    }
}

/// The list itself, pinned to the bottom of the tab list's area.
@MainActor
final class DownloadsTrayView: NSView {
    private let ui: SidebarUIState
    var colors = SidebarColors() { didSet { if colors.isDark != oldValue.isDark { for r in rows { r.colors = colors } } } }
    private var rows: [DownloadsTrayRowView] = []
    private var shownOpen = false
    private var ticker: Timer?

    init(ui: SidebarUIState) {
        self.ui = ui
        super.init(frame: .zero)
        wantsLayer = true
        ui.downloadsTray = self
        observe()
    }

    /// The newest row's thumbnail (the bottom row, by the Library button), in window coordinates:
    /// the Library button's bin flies there as the list opens, and back from there as it closes.
    func newestThumbnailInWindow() -> NSRect? {
        layoutSubtreeIfNeeded()
        guard let r = rows.last, window != nil else { return nil }
        return r.convert(r.iconRect, to: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func observe() {
        let (entries, open, _) = withObservationTracking {
            (DownloadHistory.shared.recent, ui.downloadsListOpen, DownloadHistory.shared.thumbnails.count)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        while rows.count < entries.count {
            let r = DownloadsTrayRowView()
            r.colors = colors
            r.onOpen = { [weak self] path, thumbnail in self?.open(path, from: thumbnail) }
            r.alphaValue = shownOpen ? 1 : 0
            rows.append(r)
            addSubview(r)
        }
        while rows.count > entries.count { rows.removeLast().removeFromSuperview() }
        for (r, e) in zip(rows, entries) { r.show(e) }
        refreshAges()
        if open != shownOpen { animate(open: open) }
        // TimelineView(.periodic(by: 1)): the ages tick while the list is up.
        if open, ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshAges() }
            }
        } else if !open {
            ticker?.invalidate()
            ticker = nil
        }
        needsLayout = true
    }

    /// A finished download clicked: Arc's preview over the window, stepping through the tray's
    /// other files (11 Nov 2026); one it can't show (an archive, a disk image) opens in its app.
    func open(_ path: String, from thumbnail: NSRect?) {
        guard let window, MediaPreviewController.shared.showDownload(path, in: DownloadHistory.shared.recent, from: thumbnail, over: window,
                                                                     origin: { [weak self] in self?.thumbnailOnScreen(for: $0) },
                                                                     onClose: { [weak self] in self?.ui.downloadsPreviewClosed() }) else {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return
        }
        // The tray stays out behind the preview, for it to close back into its row (DownloadsTrayHold).
        ui.downloadsPreviewOpened()
    }

    /// Where `path`'s thumbnail is on screen while the tray is out, for the preview to shrink into.
    func thumbnailOnScreen(for path: String) -> NSRect? {
        guard shownOpen, let w = window, w.isVisible, !isHiddenOrHasHiddenAncestor,
              let r = rows.first(where: { $0.path == path }) else { return nil }
        return w.convertToScreen(r.convert(r.iconRect, to: nil))
    }

    /// The pointer as it is now (a preview over the tray just closed and no move told the tray).
    func syncHover() { updateHoveredRow() }

    private func refreshAges() {
        let now = Date()
        for r in rows { r.now = now }
    }

    /// Opening, the rows glide up into place on a spring and fade in, bottom row first, 25 ms
    /// apart; closing, they settle back down as they fade, faster (CraCore DownloadsTrayLayout's
    /// motion, 11 Nov 2026: it was a flat 0.12 s fade). Interrupted, each starts from where it is.
    private func animate(open: Bool) {
        shownOpen = open
        let L = DownloadsTrayLayout.self
        let glide = CGFloat(L.glide)
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let n = rows.count
        for (i, r) in rows.enumerated() {
            guard let layer = r.layer else { continue }
            let fromBottom = Double(n - 1 - i)
            let delay = open ? fromBottom * L.stagger : fromBottom * L.stagger / 2
            let fromOpacity = layer.presentation()?.opacity ?? layer.opacity
            let fromShift = (layer.presentation()?.value(forKeyPath: "sublayerTransform.translation.y") as? CGFloat) ?? (open ? glide : 0)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            r.alphaValue = open ? 1 : 0
            layer.sublayerTransform = CATransform3DMakeTranslation(0, open ? 0 : glide * 0.6, 0)
            CATransaction.commit()
            let begin = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = fromOpacity
            fade.toValue = open ? 1 : 0
            fade.duration = open ? 0.18 : L.closeDuration
            fade.timingFunction = CAMediaTimingFunction(name: open ? .easeOut : .easeIn)
            fade.beginTime = begin
            fade.fillMode = .backwards
            layer.add(fade, forKey: "openCloseFade")
            let target = open ? 0 : glide * 0.6
            if reduce {
                layer.removeAnimation(forKey: "openCloseGlide")
                continue
            }
            if open {
                let spring = CASpringAnimation(keyPath: "sublayerTransform.translation.y")
                spring.mass = 1
                spring.stiffness = L.springStiffness
                spring.damping = L.springDamping
                spring.fromValue = fromShift
                spring.toValue = target
                spring.duration = spring.settlingDuration
                spring.beginTime = begin
                spring.fillMode = .backwards
                layer.add(spring, forKey: "openCloseGlide")
            } else {
                let settle = CABasicAnimation(keyPath: "sublayerTransform.translation.y")
                settle.fromValue = fromShift
                settle.toValue = target
                settle.duration = L.closeDuration
                settle.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.9, 0.6)
                settle.beginTime = begin
                settle.fillMode = .backwards
                layer.add(settle, forKey: "openCloseGlide")
            }
        }
        updateHoveredRow()
    }

    /// The row under the pointer, lit; only one, and none while the list is closed or the pointer
    /// is off it. The tray decides for all its rows at once (each row's own tracking area could
    /// leave one lit when its exit went missing, so several showed a fill at once, 11 Nov 2026).
    private func updateHoveredRow(_ event: NSEvent? = nil) {
        var lit: DownloadsTrayRowView?
        var inside = false
        if shownOpen, let w = window, w.isVisible, !isHiddenOrHasHiddenAncestor {
            let p = convert(event?.locationInWindow ?? w.mouseLocationOutsideOfEventStream, from: nil)
            inside = bounds.contains(p)
            if inside { lit = rows.first { $0.frame.contains(p) } }
        }
        // Opening under a resting pointer (it was where the Library button's bin flew up from): the
        // list counts as hovered, or the button lost the pointer with its bin and the list closed,
        // the bin came back and it opened again, over and over (11 Nov 2026).
        if event == nil { setHovered(inside) }
        for r in rows where r.hovering && r !== lit { ArcTooltipController.shared.mouseExited(r) }
        for r in rows { r.hovering = r === lit }
        // The file's whole name beside the row, in Cra's tooltip panel (its own window above the
        // sidebar): nothing under the list gets the pointer.
        if let lit { ArcTooltipController.shared.mouseMoved(in: lit) }
    }


    override func layout() {
        super.layout()
        // DownloadsTrayLayout's rows, 2 pt lower than the area.
        for (i, r) in rows.enumerated() {
            let f = DownloadsTrayLayout.row(i, width: Double(bounds.width))
            r.frame = NSRect(x: f.x, y: 2 + f.y, width: f.width, height: f.height)
        }
    }

    // MARK: Pointer

    /// The open list is one surface: a click on a row opens it, a click between rows or beside
    /// them lands here and does nothing (it went through to the tab under the list, 11 Nov 2026).
    /// The view reaches down to the Library button so the pointer's way up from it never leaves the
    /// list (it closed on the empty strip between); that strip lets clicks through to the button
    /// (CraCore DownloadsTrayLayout.clickArea).
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard shownOpen, let hit = super.hitTest(point) else { return nil }
        guard hit === self else { return hit }
        return takesClicks(at: convert(point, from: superview)) ? self : nil
    }

    func takesClicks(at p: NSPoint) -> Bool {
        guard let a = DownloadsTrayLayout.clickArea(rows: rows.count, width: Double(bounds.width)) else { return false }
        return NSRect(x: a.x, y: a.y, width: a.width, height: a.height).contains(p)
    }

    // Between the rows: nothing happens, and nothing under the list hears it.
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func menu(for event: NSEvent) -> NSMenu? { nil }
    override var mouseDownCanMoveWindow: Bool { false }

    /// cra://debug?downloadsHit: what a click between the first two rows, and one just below the
    /// last row (over the Library button), reach, through the window's own hit test.
    func debugHits() -> (gap: String, below: String) {
        guard let w = window, let root = w.contentView?.superview, rows.count > 1 else { return ("-", "-") }
        let L = DownloadsTrayLayout.self
        let gap = NSPoint(x: bounds.midX, y: CGFloat(2 + L.rowHeight + L.rowGap / 2))
        let below = NSPoint(x: bounds.midX, y: CGFloat(2 + L.listHeight(rows: rows.count) + L.bottomGap + 4))
        // The frame view is the window's root: its frame is the window's coordinates.
        func name(_ p: NSPoint) -> String { root.hitTest(convert(p, to: nil)).map { "\(type(of: $0))" } ?? "nothing" }
        return (name(gap), name(below))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { setHovered(ui.downloadsListOpen); updateHoveredRow(event) }
    override func mouseMoved(with event: NSEvent) { setHovered(ui.downloadsListOpen); updateHoveredRow(event) }
    override func mouseExited(with event: NSEvent) {
        setHovered(false)
        for r in rows {
            if r.hovering { ArcTooltipController.shared.mouseExited(r) }
            r.hovering = false
        }
    }

    private func setHovered(_ h: Bool) {
        guard ui.downloadsListHovered != h else { return }
        ui.downloadsListHovered = h
        ui.downloadsHoverChanged()
    }
}

private final class DownloadsTrayRowView: NSView, NSDraggingSource, ArcTooltipTarget {
    // ArcTooltipTarget: the file's whole name (Arc's tip beside a download row).
    var text: String { name.stringValue }
    var keys: [String] { [] }
    var followsCursor: Bool { false }
    var subtitle: String? { nil }
    var optionText: String? { nil }
    var onShow: (() -> Void)? { nil }
    var screenFrame: NSRect { window.map { $0.convertToScreen(convert(bounds, to: nil)) } ?? .zero }
    var hostWindow: NSWindow? { window }
    var placement: ArcTooltipPlacement { .trailing }

    var colors = SidebarColors() { didSet { refresh(); refreshHover() } }
    /// The rounded fill behind the row under the pointer, as on the tab list's rows. Set by the
    /// tray (DownloadsTrayView.updateHoveredRow), which lights one row at most.
    private let hoverFill = CALayer()
    var hovering = false { didSet { if hovering != oldValue { refreshHover() } } }
    private var listed: DownloadHistory.Listed?
    /// The finished file this row stands for (live rows have nothing to open or drag yet).
    private var entry: DownloadHistory.Entry? {
        if case .finished(let e)? = listed { return e }
        return nil
    }
    var path: String? { entry?.path }
    var now = Date() { didSet { refreshAge() } }
    private let thumb = NSView()
    private let name = NSTextField.sidebarLabel(size: 14)
    private let age = NSTextField.sidebarLabel(size: 12)
    private var downAt: NSPoint?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        hoverFill.cornerRadius = CGFloat(DownloadsTrayLayout.corner)
        hoverFill.cornerCurve = .continuous
        hoverFill.actions = ["bounds": NSNull(), "position": NSNull()]
        hoverFill.opacity = 0
        layer?.addSublayer(hoverFill)
        thumb.wantsLayer = true
        thumb.layer?.cornerCurve = .continuous
        addSubview(thumb)
        name.lineBreakMode = .byTruncatingMiddle
        addSubview(name)
        addSubview(age)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Also when only a thumbnail arrived, and on every progress report.
    func show(_ l: DownloadHistory.Listed) {
        listed = l
        refresh()
    }

    private func refresh() {
        let ink: NSColor = colors.isDark ? .white : .black
        name.textColor = ink.withAlphaComponent(0.82)
        age.textColor = ink.withAlphaComponent(0.5)
        guard let listed else { return }
        var image: NSImage?
        switch listed {
        case .finished(let e):
            name.stringValue = (e.path as NSString).lastPathComponent
            image = DownloadHistory.shared.thumbnail(for: e.path)
        case .live(let l):
            // Still running, failed or cancelled: the file type's icon, as in the bin before it lands.
            name.stringValue = l.name
            image = NSWorkspace.shared.icon(for: UTType(filenameExtension: (l.name as NSString).pathExtension) ?? .data)
        }
        if let image {
            let scale = window?.backingScaleFactor ?? 2
            var rect = NSRect(x: 0, y: 0, width: DownloadsTrayMetrics.thumbnail, height: DownloadsTrayMetrics.thumbnail)
            let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: scale)])
            // A preview fills the square, rounded; an icon (a Word or ZIP file's) is drawn whole in it,
            // so every row's picture and text line up the same (DownloadsTrayLayout.fillsSquare).
            let fills = cg.map { DownloadsTrayLayout.fillsSquare(cornerAlphas: Self.cornerAlphas($0)) } ?? false
            thumb.layer?.contents = cg
            thumb.layer?.contentsScale = scale
            thumb.layer?.contentsGravity = fills ? .resizeAspectFill : .resizeAspect
            thumb.layer?.cornerRadius = fills ? 6 : 0
            thumb.layer?.masksToBounds = fills
            thumb.layer?.backgroundColor = nil
        } else {
            thumb.layer?.contents = nil
            thumb.layer?.cornerRadius = 6
            thumb.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        }
        refreshAge()
    }

    /// "54 seconds ago", "6 minutes ago"; progress, "Failed to Download" or "Cancelled" (DownloadRow).
    private func refreshAge() {
        guard let listed else { return }
        let state: DownloadRow.State
        switch listed {
        case .finished(let e): state = .finished(at: e.date)
        case .live(let l): state = l.row
        }
        let s = DownloadRow.subtitle(state, now: now)
        if age.stringValue != s { age.stringValue = s }
    }

    private func refreshHover() {
        let ink: NSColor = colors.isDark ? .white : .black
        let fill = colors.hoverFill.alphaComponent > 0 ? colors.hoverFill : ink.withAlphaComponent(colors.isDark ? 0.1 : 0.06)
        hoverFill.backgroundColor = fill.cgColor
        // Lit at once, out in a short fade, as the tab rows do.
        CATransaction.begin()
        CATransaction.setAnimationDuration(hovering ? 0 : 0.12)
        hoverFill.opacity = hovering ? 1 : 0
        CATransaction.commit()
    }

    /// The icon's square in the row.
    var iconRect: NSRect {
        let f = DownloadsTrayLayout.iconFrame
        return NSRect(x: f.x, y: f.y, width: f.size, height: f.size)
    }

    /// The alpha of the picture's four corner pixels, 0…1.
    private static func cornerAlphas(_ image: CGImage) -> [Double] {
        let w = image.width, h = image.height
        guard w > 1, h > 1, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return [] }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.assumingMemoryBound(to: UInt8.self)
        return [(1, 1), (w - 2, 1), (1, h - 2), (w - 2, h - 2)].map { x, y in Double(px[(y * w + x) * 4 + 3]) / 255 }
    }

    override func layout() {
        super.layout()
        let L = DownloadsTrayLayout.self
        // The fill is the row, the icon a square 12 pt in, the two lines after it (DownloadsTrayLayout).
        hoverFill.frame = bounds
        thumb.frame = iconRect
        let x = CGFloat(L.textX), w = max(0, bounds.width - x - 10)
        name.frame = NSRect(x: x - SidebarText.inset, y: CGFloat(L.nameY), width: w + 2 * SidebarText.inset, height: CGFloat(L.nameHeight))
        age.frame = NSRect(x: x - SidebarText.inset, y: CGFloat(L.ageY), width: w + 2 * SidebarText.inset, height: CGFloat(L.ageHeight))
    }

    // MARK: Click and drag

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) { downAt = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downAt, let entry else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 3 else { return }
        downAt = nil
        let item = NSDraggingItem(pasteboardWriter: URL(fileURLWithPath: entry.path) as NSURL)
        let image = DownloadHistory.shared.thumbnail(for: entry.path) ?? NSWorkspace.shared.icon(forFile: entry.path)
        item.setDraggingFrame(thumb.frame, contents: image)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    /// The tray opens the file (DownloadsTrayView.open): the preview, or its app.
    var onOpen: ((String, NSRect?) -> Void)?

    override func mouseUp(with event: NSEvent) {
        defer { downAt = nil }
        guard downAt != nil, let entry, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        let thumbnail = window.map { $0.convertToScreen(convert(thumb.frame, to: nil)) }
        if let onOpen { onOpen(entry.path, thumbnail) } else { NSWorkspace.shared.open(URL(fileURLWithPath: entry.path)) }
    }

    /// Arc's Download Context Menu, as on Library ▸ Downloads (#272): Cancel Download on a running
    /// row, Open, Copy and Show in Finder on a finished one.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let listed else { return nil }
        let menu = NSMenu()
        DownloadRowMenu.fill(menu, for: listed)
        return menu.items.isEmpty ? nil : menu
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .generic] : .copy
    }
}
