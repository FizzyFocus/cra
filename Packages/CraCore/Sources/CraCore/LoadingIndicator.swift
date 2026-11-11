import CoreGraphics

/// Arc's loading indicator, a bar at the top middle of the window chrome, in the margin above the
/// page card. Measured from a screen recording of Arc 1.171, 2 Nov 2026 (60 fps, 1.4 px per pt):
/// - Waiting: the request is out and no response has committed. A 48 pt pill fades in over 0.7 s,
///   out over 0.65 s and stays off for 0.25 s, at 75 % white.
/// - Loading: the page committed. The pill widens to a 130 pt track at 18 % white, and a 76 %
///   white segment sweeps it every 1.12 s: its head runs left to right in 0.37 s, then its tail
///   does, then the track stays empty for the rest of the cycle. Both edges move at a steady speed.
/// - Done: the whole track lights up, then it shrinks toward the middle and fades in 0.3 s.
/// The bar is 4 pt tall, centred in the top margin.
public enum LoadingIndicator {
    public enum Phase: Equatable, Sendable {
        case hidden
        case waiting
        case loading

        /// `committed`: the main frame's current navigation has a response (CEF's OnLoadStart).
        public init(isLoading: Bool, committed: Bool) {
            self = !isLoading ? .hidden : committed ? .loading : .waiting
        }
    }

    public static let pillWidth: Double = 48
    public static let trackWidth: Double = 130
    public static let height: Double = 4

    public static let brightAlpha: Double = 0.76
    public static let trackAlpha: Double = 0.18

    public static let pulsePeriod: Double = 1.6
    /// Opacity of the waiting pill through one pulse: time (0...1 of `pulsePeriod`) and value.
    public static let pulseKeyframes: [(time: Double, opacity: Double)] = [
        (0, 0), (0.7 / 1.6, 1), (1.35 / 1.6, 0), (1, 0),
    ]

    public static let sweepPeriod: Double = 1.12
    /// Where the segment's head has finished and its tail starts, as a fraction of the cycle. A
    /// waiting pill that widens into the track joins the cycle here: lit end to end.
    public static let sweepTailStart: Double = 0.37 / 1.12
    /// The segment through one sweep: time (0...1 of `sweepPeriod`) and its two ends (0...1 of
    /// the track). Between keyframes both ends move linearly.
    public static let sweepKeyframes: [(time: Double, start: Double, end: Double)] = [
        (0, 0, 0), (sweepTailStart, 0, 1), (0.74 / 1.12, 1, 1), (1, 1, 1),
    ]

    /// The segment's ends at `time` seconds into a sweep.
    public static func sweep(at time: Double) -> (start: Double, end: Double) {
        let t = (time / sweepPeriod).truncatingRemainder(dividingBy: 1)
        let k = sweepKeyframes
        for i in 1..<k.count where t <= k[i].time {
            let f = (t - k[i - 1].time) / (k[i].time - k[i - 1].time)
            return (k[i - 1].start + (k[i].start - k[i - 1].start) * f, k[i - 1].end + (k[i].end - k[i - 1].end) * f)
        }
        return (1, 1)
    }

    /// The least margin above the card that holds the bar.
    public static let minimumMargin: Double = height + 2
    /// With no margin, the bar's centre this far below the card's top edge, over the page.
    public static let insideInset: Double = 5

    /// Where the bar's view goes (y up, `bounds` the window's content): centred over the card at
    /// `content`, in the margin above it. Edge to edge (a maximized window with its sidebar hidden,
    /// a window in full screen, the setting) there is no margin, and the bar sat in none: every
    /// load went unseen (10 Nov 2026). It then lies just inside the card's top edge, over the page.
    /// A page in full screen (a video) has none; nil.
    public static func frame(content: CGRect, in bounds: CGRect, pageFullscreen: Bool) -> CGRect? {
        guard !pageFullscreen, !content.isEmpty else { return nil }
        let w = trackWidth + 2
        let x = (content.midX - w / 2).rounded()
        let margin = bounds.maxY - content.maxY
        if margin >= minimumMargin { return CGRect(x: x, y: content.maxY, width: w, height: margin) }
        let h = 2 * insideInset
        return CGRect(x: x, y: content.maxY - h, width: w, height: h)
    }

    /// The time the waiting pill takes to widen into the track.
    public static let expandDuration: Double = 0.35
    /// The time the finished track takes to shrink and fade.
    public static let finishDuration: Double = 0.3
    /// The width the finished track shrinks to as it fades.
    public static let finishWidth: Double = 75
}
