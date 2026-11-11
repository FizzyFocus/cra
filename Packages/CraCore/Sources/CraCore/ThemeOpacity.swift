import Foundation

/// How see-through a space's colours are over the blurred desktop: the theme's own look (Arc's
/// opaque gradient, its vibrant imports, its one-colour fill), or the Opacity the theme picker sets
/// (SpaceTheme.opacity), from near-clear acrylic to a solid window.
public enum ThemeOpacity {
    /// The picker's slider: from mostly desktop to fully opaque.
    public static let range: ClosedRange<Double> = 0.2...1
    /// Within this of 1 the slider lands on opaque (its magnetic end).
    public static let opaqueSnap = 0.03

    /// Arc 1.171 over solid white and black backdrops (31 Oct 2026, nine colours, sRGB after
    /// undoing the display's P3): out = α·colour + (1 − α)·(66 + 0.52·backdrop) while active,
    /// α·colour + (1 − α)·212 while inactive, with α = 0.19 + 0.55·intensity (fits 0.191,
    /// 0.459, 0.742 at 0, 0.5, 1; within 3/255). isVibrant and the text appearance don't matter.
    public static func solidAlpha(intensity: Double) -> Double { 0.19 + 0.55 * max(0, min(1, intensity)) }

    /// The colours' opacity at the top and bottom of the sidebar, and whether the window lets the
    /// desktop through at all, for a theme as shown (resolved to light or dark).
    public static func alphas(_ t: SpaceTheme) -> (top: Double, bottom: Double, seeThrough: Bool) {
        if let o = t.opacity {
            let a = clamped(o)
            return a >= 1 ? (1, 1, false) : (a, a, true)
        }
        if t.solid {
            let a = solidAlpha(intensity: t.intensity)
            return (a, a, true)
        }
        guard t.vibrant else { return (1, 1, false) }
        // Fitted to Arc's Victor theme (intensity 0.25) over white and black backdrops (Theme.swift).
        if t.isDark {
            let a = max(0.35, min(0.9, t.intensity * 2.2))
            return (a, a, true)
        }
        return (min(0.95, t.intensity * 1.70), min(0.95, t.intensity * 2.35), true)
    }

    /// What the picker's slider shows for a theme: its set opacity, else its look's own at the top.
    public static func shown(_ t: SpaceTheme) -> Double { clamped(t.opacity ?? alphas(t).top) }

    /// A slider position as an opacity: inside `range`, and opaque near its end.
    public static func clamped(_ value: Double) -> Double {
        let v = min(range.upperBound, max(range.lowerBound, value))
        return v >= range.upperBound - opaqueSnap ? range.upperBound : v
    }
}
