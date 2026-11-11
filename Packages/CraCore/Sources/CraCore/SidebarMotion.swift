import Foundation

/// How the sidebar hides and comes back on ⌘S (Arc 1.172.1, Victor's Arc, 8 Nov 2026, recorded with
/// `screencapture -V` at 60 fps, four runs): the page's edge covers 42–44 %, 71–73 %, 89 %, 97–98 % of its
/// travel after frames 1–4 when hiding, 25–35 %, 66–72 %, 86–92 %, 96–99 % when showing, done in about
/// 5 frames. Arc 1.170 recorded with ffmpeg (66/87/96/99 %) had dropped the first frames.
public enum SidebarMotion {
    public static let duration: TimeInterval = 0.085
    /// The cubic Bézier's control points (CAMediaTimingFunction), fitted to those frames.
    public static let curve: (Double, Double, Double, Double) = (0.3, 0.7, 0.5, 1)

    /// Settings ▸ Appearance ▸ Sidebar ▸ "Animate sidebar docking" (11 Nov 2026, off by default):
    /// docking the sidebar (⌘S, from floating too) and putting it away glide over a longer, softer
    /// ease, the card easing into its inset frame like a damped spring settling, instead of Arc's
    /// near-instant slide.
    public static let smoothDuration: TimeInterval = 0.42
    public static let smoothCurve: (Double, Double, Double, Double) = (0.16, 1, 0.3, 1)

    /// The slide for docking and undocking: Arc's, or the smooth one when the setting is on.
    public static func docking(animated: Bool) -> (duration: TimeInterval, curve: (Double, Double, Double, Double)) {
        animated ? (smoothDuration, smoothCurve) : (duration, curve)
    }

    /// The share of the travel done `t` seconds in.
    public static func progress(at t: TimeInterval, curve c: (Double, Double, Double, Double) = curve, duration: TimeInterval = duration) -> Double {
        let x = min(1, max(0, t / duration))
        var lo = 0.0, hi = 1.0
        for _ in 0..<50 {
            let s = (lo + hi) / 2
            let bx = 3 * (1 - s) * (1 - s) * s * c.0 + 3 * (1 - s) * s * s * c.2 + s * s * s
            if bx < x { lo = s } else { hi = s }
        }
        let s = (lo + hi) / 2
        return 3 * (1 - s) * (1 - s) * s * c.1 + 3 * (1 - s) * s * s * c.3 + s * s * s
    }
}
