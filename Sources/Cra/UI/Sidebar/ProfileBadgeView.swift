import AppKit

/// The space's profile in a small pill (13 Nov 2026, ProfileBadge): its emoji, or a dot in its
/// accent, then its name, on the accent at a low alpha (the space's own pill fill without one).
/// The space header puts it beside the space's name; Library ▸ Spaces' cards likewise.
final class ProfileBadgeView: NSView {
    private let icon = NSTextField.sidebarLabel(size: 10)
    private let dot = NSView()
    private let label = NSTextField.sidebarLabel(size: 11, weight: .semibold)
    private(set) var showsName = true
    private(set) var name = ""
    private(set) var look = ProfileLook()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = ProfileBadge.height / 2
        layer?.cornerCurve = .continuous
        dot.wantsLayer = true
        dot.layer?.cornerRadius = ProfileBadge.dotWidth / 2
        for v in [icon, dot, label] { addSubview(v) }
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(name: String, look: ProfileLook, colors: SidebarColors) {
        self.name = name
        self.look = look
        label.stringValue = name
        icon.stringValue = look.icon ?? ""
        let accent = look.accent.map { NSColor(srgbRed: $0.rgb.r, green: $0.rgb.g, blue: $0.rgb.b, alpha: 1) }
        layer?.backgroundColor = (accent?.withAlphaComponent(colors.isDark ? 0.3 : 0.2) ?? (colors.isDark ? NSColor.white.withAlphaComponent(0.1) : colors.hoverFill)).cgColor
        label.textColor = colors.textSecondary
        dot.layer?.backgroundColor = (accent ?? colors.textTertiary).cgColor
        toolTip = "Profile: \(name)"
        setAccessibilityLabel("Profile: \(name)")
        needsLayout = true
    }

    var hasIcon: Bool { !(look.icon ?? "").isEmpty }
    var nameWidth: CGFloat { ceil(label.attributedStringValue.size().width) }

    /// The pill's width for `room` beside the title, or nil when not even its icon fits.
    func fit(room: CGFloat) -> CGFloat? {
        guard let f = ProfileBadge.width(name: Double(nameWidth), hasIcon: hasIcon, room: Double(room)) else { return nil }
        showsName = f.showsName
        return CGFloat(f.width)
    }

    /// Beside a title `textWidth` wide that may run from `x` to `end`: the title keeps its width
    /// while both fit, then gives way down to a few letters, the pill taking what is left (its
    /// name shortening, then its icon alone, then none). Returns the title's width.
    func place(besideTitle textWidth: CGFloat, from x: CGFloat, to end: CGFloat, midY: CGFloat, shown: Bool) -> CGFloat {
        let avail = max(0, end - x)
        guard shown, let full = fit(room: .greatestFiniteMagnitude) else {
            isHidden = true
            return min(textWidth, avail)
        }
        let gap: CGFloat = 6
        let titleW = textWidth + gap + full <= avail ? textWidth : min(textWidth, max(min(textWidth, 56), avail - gap - full))
        guard let w = fit(room: avail - titleW - gap) else {
            isHidden = true
            return min(textWidth, avail)
        }
        isHidden = false
        let h = CGFloat(ProfileBadge.height)
        let f = NSRect(x: x + titleW + gap, y: (midY - h / 2).rounded(), width: w, height: h)
        if frame != f { frame = f }
        needsLayout = true
        return titleW
    }

    override func layout() {
        super.layout()
        let h = bounds.height, p = CGFloat(ProfileBadge.padding)
        icon.isHidden = !hasIcon
        dot.isHidden = hasIcon
        label.isHidden = !showsName
        let lead: CGFloat = hasIcon ? CGFloat(ProfileBadge.iconWidth) : CGFloat(ProfileBadge.dotWidth)
        let ih = icon.intrinsicContentSize.height
        icon.frame = NSRect(x: p - SidebarText.inset - 1, y: (h - ih) / 2, width: lead + 2 * SidebarText.inset + 2, height: ih)
        let d = CGFloat(ProfileBadge.dotWidth)
        dot.frame = NSRect(x: p, y: (h - d) / 2, width: d, height: d)
        let x = p + lead + CGFloat(ProfileBadge.iconGap)
        let lh = label.intrinsicContentSize.height
        label.frame = NSRect(x: x - SidebarText.inset, y: (h - lh) / 2, width: max(0, bounds.width - x - p) + 2 * SidebarText.inset, height: lh)
    }
}
