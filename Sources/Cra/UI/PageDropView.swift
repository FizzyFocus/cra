import AppKit

/// Over the page card while a Library bookmark is dragged (BookmarkDrag): it takes the drop before
/// the page would (Chromium navigates the tab to a dropped link), and opens the bookmark in a new
/// tab, or with ⇧ held in the tab on screen. A tint over the card and a pill say which.
final class PageDropView: NSView {
    /// The bookmark's address, and whether it replaces the tab on screen.
    var onDrop: (String, Bool) -> Void = { _, _ in }
    var cornerRadius: CGFloat = CraMetrics.contentCornerRadius { didSet { layer?.cornerRadius = cornerRadius } }
    private let pill = NSView()
    private let label = NSTextField.sidebarLabel(size: 13, weight: .semibold)
    private var replace = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = cornerRadius
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 16
        pill.layer?.cornerCurve = .continuous
        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        label.textColor = .white
        label.alignment = .center
        pill.addSubview(label)
        addSubview(pill)
        registerForDraggedTypes([.craBookmark])
        isHidden = true
        show(lit: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Out while a bookmark drag is on, so it never takes the page's clicks.
    func setArmed(_ armed: Bool) {
        isHidden = !armed
        if !armed { show(lit: false) }
    }

    private func show(lit: Bool) {
        layer?.backgroundColor = (lit ? NSColor.controlAccentColor.withAlphaComponent(0.12) : .clear).cgColor
        layer?.borderWidth = lit ? 2 : 0
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        pill.isHidden = !lit
        label.stringValue = replace ? "Open in This Tab" : "Open in New Tab"
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let w = ceil(label.attributedStringValue.size().width) + 32
        pill.frame = NSRect(x: ((bounds.width - w) / 2).rounded(), y: ((bounds.height - 32) / 2).rounded(), width: w, height: 32)
        let th = label.intrinsicContentSize.height
        label.frame = NSRect(x: 0, y: (32 - th) / 2, width: w, height: th)
    }

    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard BookmarkDrag.url(sender.draggingPasteboard) != nil else { show(lit: false); return [] }
        replace = NSEvent.modifierFlags.contains(.shift)
        show(lit: true)
        return .copy
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { show(lit: false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = BookmarkDrag.url(sender.draggingPasteboard) else { return false }
        let here = NSEvent.modifierFlags.contains(.shift)
        show(lit: false)
        onDrop(url, here)
        return true
    }
}
