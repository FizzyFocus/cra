import AppKit

/// What the blocked pop-ups popover can do (#357): open one pop-up (nil: all of them) as a tab below
/// the page, and switch Chrome's per-site setting.
struct BlockedPopupsActions {
    var open: (_ popup: Int?) -> Void = { _ in }
    var setAllowed: (Bool) -> Void = { _ in }
}

/// Chrome's blocked pop-ups bubble (upstream 2a43142 showed it as a menu) as a popover in the space's
/// colours, the way the translate popover is (SpacePopoverTones): AppKit's frosted material, light or
/// dark with the space, CraCore BlockedPopups.rows top to bottom. A pop-up's row opens it, Open All is
/// the prominent button, Always Allow a row with a check; each closes the popover, as the menu did.
@MainActor
final class BlockedPopupsPopover: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    var isShown: Bool { popover?.isShown == true }
    /// For scenarios: the shown popover's appearance ("light", "dark"), "-" while none shows.
    var appearanceName: String {
        guard let p = popover, p.isShown else { return "-" }
        return p.appearance?.name == .darkAqua ? "dark" : "light"
    }
    /// When a click outside closed the popover: the same click on the button leaves it closed.
    private var closingClick: TimeInterval?

    func toggle(relativeTo rect: NSRect, of view: NSView, rows: [BlockedPopups.Row], actions: BlockedPopupsActions) {
        if let p = popover, p.isShown { p.performClose(nil); return }
        if let t = closingClick, let now = NSApp.currentEvent?.timestamp, now - t < 1, NSApp.currentEvent?.type == .leftMouseUp {
            closingClick = nil
            return
        }
        closingClick = nil
        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        p.delegate = self
        let tones = SpacePopoverTones(window: view.window)
        p.appearance = tones.appearance
        var acts = actions
        acts.open = { [weak p] id in p?.performClose(nil); actions.open(id) }
        acts.setAllowed = { [weak p] on in p?.performClose(nil); actions.setAllowed(on) }
        let v = BlockedPopupsView(rows: rows, tones: tones, actions: acts)
        let host = NSViewController()
        host.view = v
        host.preferredContentSize = v.frame.size
        p.contentViewController = host
        popover = p
        p.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    func close() { popover?.performClose(nil) }

    func popoverWillClose(_ notification: Notification) {
        if let e = NSApp.currentEvent, e.type == .leftMouseDown { closingClick = e.timestamp }
    }

    func popoverDidClose(_ notification: Notification) { popover = nil }
}

final class BlockedPopupsView: NSView {
    static let width: CGFloat = 280
    static let inset: CGFloat = 10
    static let rowHeight: CGFloat = 28
    /// Rows past this scroll (Chromium keeps up to 25 a page).
    static let visibleRows = 8

    private let tones: SpacePopoverTones
    private var placed: [(NSView, CGFloat)] = []

    init(rows: [BlockedPopups.Row], tones: SpacePopoverTones, actions: BlockedPopupsActions) {
        self.tones = tones
        super.init(frame: .zero)
        wantsLayer = true
        // No fill of its own: the popover's frosted material shows, as the Site Control Center's.
        layer?.backgroundColor = NSColor.clear.cgColor
        var popups: [NSView] = []
        func flushPopups() {
            guard !popups.isEmpty else { return }
            let list = FlippedStack(rows: popups, rowHeight: Self.rowHeight)
            let shown = CGFloat(min(popups.count, Self.visibleRows)) * Self.rowHeight
            if popups.count > Self.visibleRows {
                let scroll = NSScrollView()
                scroll.drawsBackground = false
                scroll.hasVerticalScroller = true
                scroll.scrollerStyle = .overlay
                scroll.documentView = list
                list.frame.size = NSSize(width: Self.width - 2 * Self.inset, height: CGFloat(popups.count) * Self.rowHeight)
                placed.append((scroll, shown))
            } else {
                placed.append((list, shown))
            }
            popups = []
        }
        for row in rows {
            switch row {
            case .heading(let title):
                let label = NSTextField(labelWithString: title)
                label.font = .systemFont(ofSize: 13, weight: .semibold)
                label.textColor = tones.title
                label.lineBreakMode = .byTruncatingTail
                placed.append((label, 22))
            case .popup(let id, let title, let url):
                let r = BlockedPopupRow(title: title, symbol: "rectangle.on.rectangle", on: nil, tones: tones) { actions.open(id) }
                r.toolTip = url
                popups.append(r)
            case .separator:
                flushPopups()
                let line = NSView()
                line.wantsLayer = true
                line.layer?.backgroundColor = tones.divider.cgColor
                placed.append((line, 1))
            case .openAll(let title):
                flushPopups()
                let b = TranslatePopoverButton(title: title, prominent: true, tones: tones)
                b.action = { actions.open(nil) }
                placed.append((b, 32))
            case .allow(let title, let on):
                flushPopups()
                placed.append((BlockedPopupRow(title: title, symbol: nil, on: on, tones: tones) { actions.setAllowed(!on) }, Self.rowHeight))
            }
        }
        flushPopups()
        for (v, _) in placed { addSubview(v) }
        let height = Self.inset * 2 + placed.reduce(0) { $0 + $1.1 } + CGFloat(max(0, placed.count - 1)) * 6
        setFrameSize(NSSize(width: Self.width, height: height))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        var y = Self.inset
        for (v, h) in placed {
            // A heading's text, a separator's hairline and Open All keep the inset; rows reach it too.
            let x: CGFloat = v is NSTextField ? Self.inset + 4 : Self.inset
            v.frame = NSRect(x: x, y: y, width: bounds.width - x - Self.inset, height: h)
            y += h + 6
        }
    }
}

/// Rows stacked top down at a fixed height (the pop-ups' list, scrolled past `visibleRows`).
private final class FlippedStack: NSView {
    private let rowHeight: CGFloat
    init(rows: [NSView], rowHeight: CGFloat) {
        self.rowHeight = rowHeight
        super.init(frame: .zero)
        for r in rows { addSubview(r) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        for (i, r) in subviews.enumerated() {
            r.frame = NSRect(x: 0, y: CGFloat(i) * rowHeight, width: bounds.width, height: rowHeight)
        }
    }
}

/// A row of the popover: a glyph and the title, or the title and a check (Always Allow); the space's
/// field tone under the pointer, 6 pt corners.
private final class BlockedPopupRow: NSView {
    private let tones: SpacePopoverTones
    private let label = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let check = NSImageView()
    private let action: () -> Void
    private var hovering = false { didSet { refresh() } }
    private var pressed = false { didSet { refresh() } }

    init(title: String, symbol: String?, on: Bool?, tones: SpacePopoverTones, action: @escaping () -> Void) {
        self.tones = tones
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        label.stringValue = title
        label.font = .systemFont(ofSize: 13)
        label.textColor = tones.title
        label.lineBreakMode = .byTruncatingMiddle
        addSubview(label)
        if let symbol {
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
            icon.contentTintColor = tones.body
            addSubview(icon)
        }
        if on == true {
            check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "On")?.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
            check.contentTintColor = tones.title
            addSubview(check)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(on == nil ? .button : .checkBox)
        setAccessibilityLabel(title)
        if let on { setAccessibilityValue(on ? 1 : 0) }
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func refresh() {
        let fill = tones.badge
        layer?.backgroundColor = (pressed ? fill : hovering ? fill.withAlphaComponent(fill.alphaComponent * 0.7) : .clear).cgColor
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        var x: CGFloat = 8
        if icon.superview != nil {
            icon.frame = NSRect(x: x, y: (h - 16) / 2, width: 16, height: 16)
            x += 22
        }
        let right: CGFloat = check.superview != nil ? 28 : 8
        if check.superview != nil { check.frame = NSRect(x: bounds.width - 24, y: (h - 16) / 2, width: 16, height: 16) }
        let lh = label.intrinsicContentSize.height
        label.frame = NSRect(x: x, y: (h - lh) / 2, width: max(0, bounds.width - x - right), height: lh)
    }

    override func accessibilityPerformPress() -> Bool { action(); return true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseUp(with event: NSEvent) {
        pressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}
