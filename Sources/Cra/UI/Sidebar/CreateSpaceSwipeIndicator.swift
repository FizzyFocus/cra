import AppKit

/// Swiping on past the last space (SpaceCreateSwipe): a + in a circle at the sidebar's edge, its
/// ring stroked round as the fingers go on; full, it turns the space's ink and gives a little
/// pulse, and letting go opens Create a Space. Fades and grows in with the fill.
final class CreateSpaceSwipeIndicator: NSView {
    static let side: CGFloat = 44
    private let track = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let plus = CAShapeLayer()
    private var full = false
    var colors = SidebarColors() { didSet { paint() } }

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        wantsLayer = true
        let b = CGRect(x: 0, y: 0, width: Self.side, height: Self.side)
        let circle = CGMutablePath()
        // From 12 o'clock, clockwise (the layer is flipped: y down).
        circle.addArc(center: CGPoint(x: b.midX, y: b.midY), radius: Self.side / 2 - 2, startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: false)
        for l in [track, ring] {
            l.path = circle
            l.fillColor = nil
            l.lineWidth = 2.5
            l.lineCap = .round
            l.frame = b
        }
        ring.strokeEnd = 0
        let p = CGMutablePath()
        p.move(to: CGPoint(x: b.midX - 7, y: b.midY)); p.addLine(to: CGPoint(x: b.midX + 7, y: b.midY))
        p.move(to: CGPoint(x: b.midX, y: b.midY - 7)); p.addLine(to: CGPoint(x: b.midX, y: b.midY + 7))
        plus.path = p
        plus.lineWidth = 2.5
        plus.lineCap = .round
        plus.frame = b
        for l in [track, ring, plus] { layer?.addSublayer(l) }
        alphaValue = 0
        setAccessibilityElement(false)
        paint()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func paint() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.strokeColor = colors.textPrimary.withAlphaComponent(0.14).cgColor
        ring.strokeColor = (full ? colors.textPrimary : colors.textPrimary.withAlphaComponent(0.7)).cgColor
        plus.strokeColor = colors.textPrimary.withAlphaComponent(full ? 0.95 : 0.6).cgColor
        CATransaction.commit()
    }

    /// The fill, 0…1; nil once the swipe is over (it fades out).
    func show(fill: Double?) {
        guard let fill else {
            full = false
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                animator().alphaValue = 0
            }
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.18)
            ring.strokeEnd = 0
            CATransaction.commit()
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.strokeEnd = CGFloat(fill)
        let s = 0.6 + 0.4 * CGFloat(fill)
        layer?.sublayerTransform = CATransform3DTranslate(CATransform3DMakeScale(s, s, 1),
                                                          Self.side / 2 * (1 - s) / s, Self.side / 2 * (1 - s) / s, 0)
        CATransaction.commit()
        alphaValue = min(1, CGFloat(fill) * 3)
        let nowFull = SpaceCreateSwipe.commits(fill: fill)
        if nowFull != full {
            full = nowFull
            paint()
            if full, let layer, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
                pulse.values = [1, 1.12, 1]
                pulse.duration = 0.22
                pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
                plus.add(pulse, forKey: "pulse")
                _ = layer
            }
        }
    }
}
