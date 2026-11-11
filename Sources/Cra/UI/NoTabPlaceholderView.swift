import AppKit

/// What the content area shows while the space has no tab open: Arc's faint card over the
/// gradient, and in its middle a quiet note that no tab has the focus and how to open one. Without
/// it the empty card read as a page that hadn't loaded, above all with the sidebar hidden, where no
/// row shows that nothing is selected. It only draws: clicks fall through to the window.
final class NoTabPlaceholderView: NSView {
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "No Tab Open")
    private let hint = NSTextField(labelWithString: "")

    var isDark = false { didSet { if isDark != oldValue { refreshColors() } } }

    /// Under this the note doesn't fit and the card stays plain.
    private static let minimumSize = NSSize(width: 220, height: 140)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        icon.image = NSImage(systemSymbolName: "plus.rectangle.on.rectangle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 26, weight: .light))
        icon.imageScaling = .scaleNone
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        hint.font = .systemFont(ofSize: 11.5)
        for l in [title, hint] {
            l.alignment = .center
            l.lineBreakMode = .byTruncatingTail
        }
        for v in [icon, title, hint] as [NSView] { addSubview(v) }
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        refreshHint()
        refreshColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The shortcut can change in Settings ▸ Shortcuts while the note is away.
    override func viewDidUnhide() {
        super.viewDidUnhide()
        refreshHint()
    }

    private func refreshHint() {
        let keys = KeyBindingRegistry.shared.action("newTab")?.primary?.display
        hint.stringValue = keys.map { "Press \($0) to open a new tab" } ?? "Open a new tab to get started"
        setAccessibilityLabel("No tab open. " + hint.stringValue)
    }

    private func refreshColors() {
        let ink: NSColor = isDark ? .white : .black
        icon.contentTintColor = ink.withAlphaComponent(isDark ? 0.32 : 0.26)
        title.textColor = ink.withAlphaComponent(isDark ? 0.55 : 0.48)
        hint.textColor = ink.withAlphaComponent(isDark ? 0.38 : 0.34)
    }

    override func layout() {
        super.layout()
        let fits = bounds.width >= Self.minimumSize.width && bounds.height >= Self.minimumSize.height
        for v in [icon, title, hint] as [NSView] { v.isHidden = !fits }
        guard fits else { return }
        let iconSize: CGFloat = 36, gap: CGFloat = 10, titleH: CGFloat = 17, hintH: CGFloat = 15
        let total = iconSize + gap + titleH + 3 + hintH
        // A little above the middle, where the eye lands in an empty page.
        var y = (bounds.midY + total / 2 + bounds.height * 0.04).rounded()
        let w = min(bounds.width - 32, 320), x = (bounds.midX - w / 2).rounded()
        y -= iconSize
        icon.frame = NSRect(x: (bounds.midX - iconSize / 2).rounded(), y: y, width: iconSize, height: iconSize)
        y -= gap + titleH
        title.frame = NSRect(x: x, y: y, width: w, height: titleH)
        y -= 3 + hintH
        hint.frame = NSRect(x: x, y: y, width: w, height: hintH)
    }
}
