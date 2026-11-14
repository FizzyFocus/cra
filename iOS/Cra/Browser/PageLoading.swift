import CraCore
import UIKit

/// The page-loading line along the top edge of the bar under the page (`MobileLoadingProgress`
/// decides; 14 Nov 2026): the accent running into pink, as wide as WebKit's estimated progress,
/// growing smoothly, then running to the end and fading out when the page has loaded.
final class LoadingProgressView: UIView {
    private let fill = UIView()
    private let gradient = CAGradientLayer()
    private var state = MobileLoadingProgress()
    private var fraction: CGFloat = 0
    /// Bumped on every step, so a fade that ends after a new load started leaves the bar alone.
    private var generation = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityIdentifier = "page-progress"
        alpha = 0
        fill.layer.addSublayer(gradient)
        fill.layer.cornerRadius = MobileLoadingProgress.height / 2
        fill.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        fill.clipsToBounds = true
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        addSubview(fill)
        applyColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: LoadingProgressView, _) in view.applyColors() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The shown page's progress changed.
    func update(progress: Double, isLoading: Bool) {
        apply(state.update(progress: progress, isLoading: isLoading))
    }

    /// Another page is shown: the bar takes up its load where it is, without animating.
    func follow(progress: Double, isLoading: Bool) {
        layer.removeAllAnimations()
        fill.layer.removeAllAnimations()
        let step = state.follow(progress: progress, isLoading: isLoading)
        if step == .hidden {
            generation += 1
            alpha = 0
            setFraction(0)
        }
        apply(step)
    }

    private func apply(_ step: MobileLoadingProgress.Step) {
        switch step {
        case .hidden:
            return
        case .show(let value, let restart):
            generation += 1
            if restart {
                layer.removeAllAnimations()
                UIView.performWithoutAnimation {
                    setFraction(CGFloat(value))
                    alpha = 1
                }
            } else {
                UIView.animate(withDuration: MobileLoadingProgress.growDuration, delay: 0,
                               options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction]) {
                    self.setFraction(CGFloat(value))
                    self.alpha = 1
                }
            }
        case .finish:
            generation += 1
            let finishing = generation
            UIView.animate(withDuration: MobileLoadingProgress.finishDuration, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
                self.setFraction(1)
            } completion: { _ in
                guard finishing == self.generation else { return }
                UIView.animate(withDuration: MobileLoadingProgress.fadeDuration, delay: 0, options: [.beginFromCurrentState]) {
                    self.alpha = 0
                } completion: { _ in
                    guard finishing == self.generation else { return }
                    self.setFraction(0)
                }
            }
        }
    }

    private func setFraction(_ value: CGFloat) {
        fraction = value
        layoutFill()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutFill()
    }

    private func layoutFill() {
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The gradient spans the whole width, so the colour under the head shows how far it is.
        gradient.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        CATransaction.commit()
    }

    private func applyColors() {
        let pink = Palette.dynamic(light: Palette.rgb(0xd76aa8), dark: Palette.rgb(0xff8fc8))
        gradient.colors = [Palette.accent, pink].map { $0.resolvedColor(with: traitCollection).cgColor }
    }
}

/// What stands in for a page until it first paints (14 Nov 2026): the app's backdrop, light or dark
/// as the phone is, grey for incognito, or the colour of the Space a tab was opened from, instead of
/// WebKit's empty canvas (black in dark mode). It fades out as the page draws.
final class PageLoadingCover: UIView {
    private let backdrop = BackdropView()
    private let spaceFill = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        accessibilityIdentifier = "page-loading-cover"
        addSubview(backdrop)
        addSubview(spaceFill)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `spaceColors`: the theme of the Space the tab came from (`MobileSpaces.coverColor`).
    func configure(spaceColors: [String]?, incognito: Bool) {
        backdrop.isIncognito = incognito
        let colors = incognito ? nil : spaceColors
        if let colors, MobileSpaces.coverColor(colors: colors, dark: false) != nil {
            spaceFill.isHidden = false
            spaceFill.backgroundColor = UIColor { traits in
                let hex = MobileSpaces.coverColor(colors: colors, dark: traits.userInterfaceStyle == .dark) ?? "#000000"
                return UIColor(hex: hex) ?? .systemBackground
            }
        } else {
            spaceFill.isHidden = true
        }
    }

    /// Shown while `visible`; fades when that changes with `animated`.
    func setVisible(_ visible: Bool, animated: Bool) {
        let target: CGFloat = visible ? 1 : 0
        guard alpha != target || isHidden == visible else { return }
        isHidden = false
        guard animated else {
            alpha = target
            isHidden = !visible
            return
        }
        UIView.animate(withDuration: visible ? 0.15 : 0.3, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.alpha = target
        } completion: { _ in
            if self.alpha == 0 { self.isHidden = true }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backdrop.frame = bounds
        spaceFill.frame = bounds
    }
}
