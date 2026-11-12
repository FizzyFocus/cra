import AppKit
import CraCore

/// Arc's permission request card (PermissionRequests/PermissionRequestPopoverView, Arc 1.172.2,
/// captured at 2x on 12 Nov 2026 from a Little Arc asking for MIDI, #371). It is not a sheet and
/// has no arrow: a card floats over the page's top left corner, 12 pt in from both edges, and
/// the page, the tabs and the rest of the window stay usable while it is up. Cra's sheet blocked
/// the whole window until it was answered.
///
/// The card is 232 pt wide, #050627 with 10 pt corners and a soft shadow. A 24 pt badge (#090D4F,
/// 4 pt corners, the `info` glyph) 16 pt in and 20 pt down, the question in 13 pt semibold white
/// from 48 pt in, centred on the badge; "Click the 🔒 to change this any time" in 11 pt medium
/// 8 pt under it; two 96 × 32 pt buttons 8 pt apart, 22 pt under that, 16 pt from the edges:
/// Not Now (no fill, a 1 pt #2A2B47 lip) and Allow (#434BDF, a 1 pt #232441 lip), 5 pt corners,
/// 13 pt semibold labels. 126 pt tall with a two-line question.
///
/// Pane keeps that layout but draws the card as its other popovers over the page (Translate, Blocked
/// pop-ups): AppKit's frosted popover material, light or dark with the window's space, and the
/// space's dialog tones (SpacePopoverTones) for the ink, the badge and the buttons, instead of
/// Arc's navy.
///
/// The card sits in a borderless child panel of the page's window, so it shows over a page that
/// lives in a window of its own too, and it follows the page when the window or the page moves.
@MainActor
final class PermissionPopover: NSObject {
    let title: String
    let actions: DialogActions
    private var completion: ((NSApplication.ModalResponse) -> Void)?
    private var panel: NSPanel?
    private weak var page: NSView?
    private var pageRect = NSRect.zero
    private var observers: [NSObjectProtocol] = []
    private(set) var card: PermissionCardView?

    /// How far the card sits in from the page's top left corner.
    static let inset: CGFloat = 12
    /// Room around the card for its shadow.
    private static let margin: CGFloat = 24

    /// The cards up, for scenarios and for ordering the window's child panels.
    private static let showing = NSHashTable<PermissionPopover>.weakObjects()

    init(title: String, actions: [DialogAction]) {
        self.title = title
        self.actions = DialogActions(actions)
    }

    var isUp: Bool { completion != nil }

    /// The card in the top left corner of `rect` (the page's area in `view`); `completion` gets
    /// `.alertFirstButtonReturn` and on for the button pressed, or `.abort` when AppKit took the
    /// card down unanswered (its page left the window).
    func present(relativeTo rect: NSRect, of view: NSView, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard let window = view.window else { completion(.abort); return }
        self.completion = completion
        page = view
        pageRect = rect
        let tones = SpacePopoverTones(window: window)
        let card = PermissionCardView(title: title, actions: actions.buttons, tones: tones) { [weak self] index in self?.finish(index) }
        self.card = card
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.appearance = tones.appearance
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isMovable = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        p.animationBehavior = .none
        let host = NSView()
        host.addSubview(card)
        p.contentView = host
        panel = p
        place()
        window.addChildWindow(p, ordered: .above)
        p.orderFront(nil)
        Self.showing.add(self)
        // The page moves with the sidebar, a split's divider and the window's own size.
        view.postsFrameChangedNotifications = true
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSView.frameDidChangeNotification, object: view, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.follow() }
            },
            center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.follow() }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.end(.abort) }
            },
        ]
        CraLog.note("permission card: \(title)")
    }

    /// Takes the card down as if nothing was chosen: its completion gets `.abort`.
    func close() { end(.abort) }

    private func finish(_ index: Int) {
        end(NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + index))
    }

    private func end(_ response: NSApplication.ModalResponse) {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers = []
        Self.showing.remove(self)
        if let panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
        panel = nil
        let done = completion
        completion = nil
        done?(response)
    }

    private func follow() {
        guard let page else { return }
        pageRect = page.bounds
        place()
    }

    private func place() {
        guard let panel, let card, let page, let window = page.window else { return }
        let size = card.fittingSize
        let m = Self.margin
        let onScreen = window.convertToScreen(page.convert(pageRect, to: nil))
        let frame = NSRect(x: onScreen.minX + Self.inset - m, y: onScreen.maxY - Self.inset - size.height - m,
                           width: size.width + 2 * m, height: size.height + 2 * m)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        card.frame = NSRect(x: m, y: m, width: size.width, height: size.height)
    }

    /// The window's cards, to keep above its page windows (MainWindowController.raiseOverlayPanels).
    static func panels(over window: NSWindow) -> [NSWindow] {
        showing.allObjects.compactMap(\.panel).filter { $0.parent === window && $0.isVisible }
    }

    /// `cra://debug?permissionCard[=<button>]`: the card up (its question, size and where it sits
    /// on its page), after pressing the named button when one is given.
    static func debug(press button: String?) -> String {
        guard let up = showing.allObjects.first, let card = up.card, let page = up.page, let panel = up.panel else {
            return "permission card: none"
        }
        let pageOnScreen = page.window.map { $0.convertToScreen(page.convert(page.bounds, to: nil)) } ?? .zero
        let cardOnScreen = panel.convertToScreen(card.frame)
        let at = "\(Int(cardOnScreen.minX - pageOnScreen.minX)),\(Int(pageOnScreen.maxY - cardOnScreen.maxY))"
        let line = "permission card: \(up.title) (\(Int(card.frame.width))x\(Int(card.frame.height)) at \(at) on the page; key window \(NSApp.keyWindow === panel ? "the card" : "unchanged"))"
        guard let button else { return line }
        guard let i = up.actions.buttons.firstIndex(where: { $0.title == button }) else { return line + "; no button \(button)" }
        up.finish(i)
        return line + "; pressed \(button)"
    }
}

/// The card's contents, laid out top down.
final class PermissionCardView: NSView {
    static let width: CGFloat = 232
    private let badge = NSView()
    private let glyph = NSImageView()
    private let question = NSTextField(wrappingLabelWithString: "")
    private let hint = NSTextField(labelWithString: "")
    private(set) var buttons: [PermissionCardButton] = []

    /// The frosted material under everything, clipped to the card's corners.
    private let material = NSVisualEffectView()

    init(title: String, actions: [DialogAction], tones: SpacePopoverTones, press: @escaping (Int) -> Void) {
        super.init(frame: .zero)
        appearance = tones.appearance
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -3)

        // Pane: the popovers' own frosted material (NSPopover's), not Arc's navy fill, with a hairline
        // rim in the space's tone as the native popover has.
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 10
        material.layer?.cornerCurve = .continuous
        material.layer?.masksToBounds = true
        material.layer?.borderWidth = 0.5
        material.layer?.borderColor = tones.divider.cgColor

        badge.wantsLayer = true
        badge.layer?.backgroundColor = tones.badge.cgColor
        badge.layer?.cornerRadius = 4
        badge.layer?.cornerCurve = .continuous
        glyph.image = NSImage(systemSymbolName: "info", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .bold))
        glyph.contentTintColor = tones.title
        glyph.imageAlignment = .alignCenter
        badge.addSubview(glyph)

        question.stringValue = title
        question.font = .systemFont(ofSize: 13, weight: .semibold)
        question.textColor = tones.title
        question.maximumNumberOfLines = 0
        question.setAccessibilityLabel(title)

        // Arc's words, the lock drawn inline as the toolbar's and the Site Control Center's.
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let ink = tones.muted
        let text = NSMutableAttributedString(string: "Click the ", attributes: [.font: font, .foregroundColor: ink])
        if let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "lock")?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold)) {
            // An attachment draws its image as it is: the lock is painted in the hint's ink first.
            let tinted = NSImage(size: lock.size, flipped: false) { rect in
                lock.draw(in: rect)
                ink.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let attachment = NSTextAttachment()
            attachment.image = tinted
            attachment.bounds = NSRect(x: 0, y: -0.5, width: lock.size.width, height: lock.size.height)
            text.append(NSAttributedString(attachment: attachment))
        }
        text.append(NSAttributedString(string: " to change this any time", attributes: [.font: font, .foregroundColor: ink]))
        hint.attributedStringValue = text

        // Arc: the cancel button first, then the one that allows.
        let order = actions.indices.sorted { (actions[$0].role == .cancel ? 0 : 1) < (actions[$1].role == .cancel ? 0 : 1) }
        buttons = order.map { i in
            let b = PermissionCardButton(title: actions[i].title, prominent: actions[i].role != .cancel, tones: tones)
            b.action = { press(i) }
            return b
        }
        for v in [material, badge, question, hint] + buttons as [NSView] { addSubview(v) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private struct Layout { var question: NSRect; var hint: NSRect; var buttonsTop: CGFloat; var height: CGFloat }

    private var metrics: Layout {
        let inset: CGFloat = 16
        let textX: CGFloat = 48
        let q = question.sizeThatFits(NSSize(width: Self.width - textX - inset, height: 400))
        // The question centres on the badge (20…44); a longer one runs down from 16.
        let qTop = max(16, 32 - q.height / 2)
        let rowBottom = max(48, qTop + q.height)
        let h = hint.intrinsicContentSize
        let hintTop = rowBottom + 8
        let buttonsTop = hintTop + 22
        return Layout(question: NSRect(x: textX, y: qTop, width: Self.width - textX - inset, height: q.height),
                      hint: NSRect(x: inset, y: hintTop, width: Self.width - 2 * inset, height: h.height),
                      buttonsTop: buttonsTop, height: buttonsTop + 32 + 16)
    }

    override var fittingSize: NSSize { NSSize(width: Self.width, height: metrics.height) }

    override func layout() {
        super.layout()
        let m = metrics
        material.frame = bounds
        // The card's own layer has no fill now: its shadow follows the rounded card, not the subviews.
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 10, cornerHeight: 10, transform: nil)
        badge.frame = NSRect(x: 16, y: 20, width: 24, height: 24)
        glyph.frame = badge.bounds
        question.frame = m.question
        hint.frame = m.hint
        let w: CGFloat = 96
        for (i, b) in buttons.enumerated() {
            b.frame = NSRect(x: 16 + CGFloat(i) * (w + 8), y: m.buttonsTop, width: w, height: 33)
        }
    }

    /// The card takes clicks without making Cra's window lose key, as Arc's does.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Arc's card buttons, each with a 1 pt lip under its 32 pt face, in the space's tones as Pane's
/// other popovers' buttons (SpacePopoverTones): Allow the space's primary hue with its stroke as
/// the lip, Not Now the plain button's fill. Hover and press as the dialogs' buttons
/// (SpacePopoverTones.fill).
final class PermissionCardButton: NSView {
    var action: () -> Void = {}
    private let face = NSView()
    private let lip = NSView()
    private let label = NSTextField(labelWithString: "")
    private let prominent: Bool
    private let tones: SpacePopoverTones
    private var hovering = false { didSet { refresh() } }
    private var pressed = false { didSet { refresh() } }

    init(title: String, prominent: Bool, tones: SpacePopoverTones) {
        self.prominent = prominent
        self.tones = tones
        super.init(frame: .zero)
        wantsLayer = true
        for v in [lip, face] {
            v.wantsLayer = true
            v.layer?.cornerRadius = 5
            v.layer?.cornerCurve = .continuous
            addSubview(v)
        }
        label.stringValue = title
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = prominent ? tones.primaryText : tones.secondaryText
        label.alignment = .center
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    var title: String { label.stringValue }

    private func refresh() {
        lip.layer?.backgroundColor = (prominent ? tones.primaryStroke : tones.divider).cgColor
        let base = prominent ? tones.primaryFill : tones.secondaryFill
        face.layer?.backgroundColor = tones.fill(base, prominent: prominent, hovering: hovering, pressed: pressed).cgColor
    }

    override func layout() {
        super.layout()
        face.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 32)
        lip.frame = NSRect(x: 0, y: 1, width: bounds.width, height: 32)
        let h = label.intrinsicContentSize.height
        label.frame = NSRect(x: 0, y: (32 - h) / 2, width: bounds.width, height: h)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
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
