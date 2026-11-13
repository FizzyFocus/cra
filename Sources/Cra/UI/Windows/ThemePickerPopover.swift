import AppKit
import SwiftUI

/// Arc's theme picker as a popover: the SpaceStyleEditor card in its own borderless panel beside
/// what opened it (StyleEditorPanel), its arrow at that row or at the pointer, growing out of the
/// arrow on a spring and shrinking back into it as it fades when it closes. Edit Theme Color… points
/// it at the space header, dock icon or row it was asked from; Create a Space's "Choose a Theme" at
/// that row (MainWindowController.placeThemePicker, ThemePickerPlacement).
@MainActor
enum ThemePickerPopover {
    /// The panel: the card 12 pt into it (19 pt above the bottom, 13.5 pt either side), room for
    /// its shadow and arrow.
    static let cardTop: CGFloat = 12
    static let cardLeading: CGFloat = 13.5
    static let cardSize = NSSize(width: SpaceStyleEditor.cardSize.width, height: SpaceStyleEditor.cardSize.height)
    static let panelSize = NSSize(width: 382, height: cardSize.height + cardTop + 19)

    /// Opens the picker with the panel's top-left at `topLeft` (screen). `arrowY`, from the card's
    /// top, points its arrow at the row that opened it; the card then grows out of the arrow's tip,
    /// else out of its top-left corner by the sidebar.
    @discardableResult
    static func present(on window: NSWindow, theme: SpaceTheme, topLeft: NSPoint, arrowY: CGFloat? = nil, arrowOnTrailing: Bool = false,
                        onChange: @escaping (SpaceTheme) -> Void, onClose: @escaping () -> Void) -> StyleEditorPanel {
        for open in window.childWindows ?? [] where open is StyleEditorPanel { open.close() }
        let frame = NSRect(x: topLeft.x.rounded(), y: (topLeft.y - panelSize.height).rounded(), width: panelSize.width, height: panelSize.height)
        let panel = StyleEditorPanel(contentRect: frame, onClose: onClose)
        let editor = SpaceStyleEditor(theme: theme, arrowY: arrowY, arrowOnTrailing: arrowOnTrailing, onChange: onChange)
        let host = NSHostingView(rootView: editor.shadow(color: .black.opacity(0.3), radius: 10, y: 4)
            .padding(.top, cardTop).padding(.horizontal, cardLeading).padding(.bottom, panelSize.height - cardTop - cardSize.height))
        host.sizingOptions = []
        host.wantsLayer = true
        panel.contentView = host
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        // The point it grows from, in the host's (flipped) space: the arrow's tip, or the card's corner.
        let tipX = arrowOnTrailing ? cardLeading + cardSize.width + PickerCardShape.arrowDepth : cardLeading - PickerCardShape.arrowDepth
        let origin = arrowY.map { CGPoint(x: tipX, y: cardTop + $0) }
            ?? CGPoint(x: cardLeading, y: cardTop)
        springIn(host, from: origin)
        panel.closeAnimation = { [weak host] done in
            guard let host else { done(); return }
            springOut(host, to: origin, done: done)
        }
        return panel
    }

    /// The way it came, backwards: shrinks toward `origin` on SpringMotion.popoverOut as it fades,
    /// from wherever an opening still in flight has it. `done` once it is gone.
    private static func springOut(_ host: NSView, to origin: CGPoint, done: @escaping () -> Void) {
        guard let layer = host.layer else { done(); return }
        let o = CGPoint(x: origin.x, y: host.isFlipped ? origin.y : layer.bounds.height - origin.y)
        var end = CATransform3DMakeTranslation(o.x, o.y, 0)
        end = CATransform3DScale(end, 0.86, 0.86, 1)
        end = CATransform3DTranslate(end, -o.x, -o.y, 0)
        let spring = SpringMotion.popoverOut
        let shrink = CASpringAnimation(keyPath: "sublayerTransform")
        shrink.fromValue = NSValue(caTransform3D: layer.presentation()?.sublayerTransform ?? CATransform3DIdentity)
        shrink.toValue = NSValue(caTransform3D: end)
        shrink.mass = 1
        shrink.stiffness = spring.stiffness
        shrink.damping = spring.damping
        shrink.duration = min(0.24, spring.settlingDuration)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? 1
        fade.toValue = 0
        fade.duration = 0.14
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        for a in [shrink, fade] as [CAAnimation] {
            a.fillMode = .forwards
            a.isRemovedOnCompletion = false
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { done() } }
        layer.removeAnimation(forKey: "pickerGrow")
        layer.removeAnimation(forKey: "pickerFade")
        layer.add(shrink, forKey: "pickerShrink")
        layer.add(fade, forKey: "pickerFadeOut")
        CATransaction.commit()
    }

    /// Scales from 86 % at `origin` to full size on SpringMotion.popover while fading in over its
    /// first ~0.1 s. Through the hosting view's sublayers, which AppKit leaves alone.
    private static func springIn(_ host: NSView, from origin: CGPoint) {
        guard let layer = host.layer, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        // The layer's own space is bottom-up; the point came from SwiftUI's top-down one.
        let o = CGPoint(x: origin.x, y: host.isFlipped ? origin.y : layer.bounds.height - origin.y)
        var start = CATransform3DMakeTranslation(o.x, o.y, 0)
        start = CATransform3DScale(start, 0.86, 0.86, 1)
        start = CATransform3DTranslate(start, -o.x, -o.y, 0)
        let spring = SpringMotion.popover
        let grow = CASpringAnimation(keyPath: "sublayerTransform")
        grow.fromValue = NSValue(caTransform3D: start)
        grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        grow.mass = 1
        grow.stiffness = spring.stiffness
        grow.damping = spring.damping
        grow.duration = grow.settlingDuration
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.1
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(grow, forKey: "pickerGrow")
        layer.add(fade, forKey: "pickerFade")
    }
}
