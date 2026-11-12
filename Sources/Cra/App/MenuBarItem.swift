import AppKit

/// The menu bar item of Settings ▸ Advanced ▸ "Keep Pane in the menu bar" (GitHub #231). Arc has
/// none, so it is a plain macOS status item: Pane's mark as a template image, and a menu that
/// AppDelegate builds each time it opens (the shortcuts follow Settings ▸ Shortcuts).
@MainActor
final class MenuBarItem: NSObject, NSMenuDelegate {
    private let item: NSStatusItem
    private let build: (NSMenu) -> Void

    init(build: @escaping (NSMenu) -> Void) {
        self.build = build
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.image = Self.icon
        item.button?.setAccessibilityLabel("Pane")
        item.button?.toolTip = "Pane"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func remove() { NSStatusBar.system.removeStatusItem(item) }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        build(menu)
    }

    /// brand/pane-mark-mono, simplified for 16 pt: a pane outlined behind and to the left, and the
    /// front pane filled over it, its sidebar's edge cut out. Like the system's own items.
    static let icon: NSImage = {
        let side: CGFloat = 16
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            let back = NSBezierPath(roundedRect: NSRect(x: 1.25, y: 2.25, width: 9.5, height: 7.5), xRadius: 2.2, yRadius: 2.2)
            back.lineWidth = 1.5
            NSColor.black.setStroke()
            back.stroke()
            // The front pane, with a clear ring round it so the outline behind stops short of it.
            let front = NSRect(x: 5, y: 6, width: 10, height: 8)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(roundedRect: front.insetBy(dx: -1.25, dy: -1.25), xRadius: 3.4, yRadius: 3.4).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(roundedRect: front, xRadius: 2.2, yRadius: 2.2).fill()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSRect(x: front.minX + 3, y: front.minY + 1.75, width: 1, height: front.height - 3.5).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return true
        }
        image.isTemplate = true
        return image
    }()
}
