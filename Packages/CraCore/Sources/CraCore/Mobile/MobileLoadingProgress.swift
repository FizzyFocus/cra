import Foundation

/// The iPhone's page-loading bar (14 Nov 2026, the owner's call): a slim line along the top edge
/// of the bar under the page, as wide as WebKit's `estimatedProgress`. It shows a sliver at once,
/// so a tap is answered before the first byte; it never runs backwards during a load; a new
/// navigation that starts while one is under way starts it again from its own progress; and when
/// loading stops it runs to the end and fades out.
public struct MobileLoadingProgress: Equatable, Sendable {
    /// What the bar does after an update.
    public enum Step: Equatable, Sendable {
        /// Not showing, and nothing to do.
        case hidden
        /// Shown at `fraction` of the width. `restart`: jump there without animating (a new load,
        /// or another tab's), else grow there smoothly.
        case show(fraction: Double, restart: Bool)
        /// Loading stopped: run to the full width, then fade out.
        case finish
    }

    /// The least width the bar shows while loading.
    public static let minimum = 0.08
    /// A drop this large while loading is a new navigation, not a wobble in WebKit's estimate.
    public static let restartDrop = 0.25
    /// How long the bar takes to grow to a new width, run to the end and fade out.
    public static let growDuration = 0.25
    public static let finishDuration = 0.2
    public static let fadeDuration = 0.3
    /// The bar's thickness in points.
    public static let height = 2.5

    public private(set) var fraction: Double = 0
    public private(set) var isShowing = false

    public init() {}

    /// The page's progress (0...1) and whether it is loading.
    public mutating func update(progress: Double, isLoading: Bool) -> Step {
        let target = max(Self.minimum, min(progress.isFinite ? progress : 0, 1))
        guard isLoading else {
            guard isShowing else { return .hidden }
            isShowing = false
            fraction = 0
            return .finish
        }
        if !isShowing || target < fraction - Self.restartDrop {
            isShowing = true
            fraction = target
            return .show(fraction: target, restart: true)
        }
        fraction = max(fraction, target)
        return .show(fraction: fraction, restart: false)
    }

    /// Another page is shown now: the bar takes up its load as it is, without animating.
    public mutating func follow(progress: Double, isLoading: Bool) -> Step {
        self = MobileLoadingProgress()
        return isLoading ? update(progress: progress, isLoading: true) : .hidden
    }
}
