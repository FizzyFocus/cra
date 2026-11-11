/// A tab loading off screen (a link opened in the background, a tab left while it loads): Arc-like,
/// an arc spins round its favicon, which dims, and both settle back once it has loaded (11 Nov
/// 2026). The tab on screen has the window's loading bar instead, and an unloaded tab has its
/// dashed ring.
public enum TabLoadingIndicator {
    public static func shows(loading: Bool, onScreen: Bool, unloaded: Bool) -> Bool {
        loading && !onScreen && !unloaded
    }

    /// How much of the ring the arc covers (270°, its tail fading out behind the head), its stroke,
    /// how long a clockwise turn takes, its fade out, and the favicon's strength meanwhile.
    public static let arcLength = 0.75
    public static let stroke = 1.5
    public static let turn = 0.9
    public static let fadeOut = 0.25
    public static let faviconAlpha = 0.55
    /// The tail is drawn in this many steps, each a little fainter toward the end.
    public static let tailSegments = 18

    /// Segment `i` of `tailSegments` (0 at the tail's end, the last at the head): where it starts
    /// and ends as fractions of a turn, and its opacity (rising to 1 at the head).
    public static func segment(_ i: Int) -> (start: Double, end: Double, opacity: Double) {
        let n = Double(tailSegments), step = arcLength / n
        let t = (Double(i) + 1) / n
        return (Double(i) * step, Double(i + 1) * step, t * t)
    }
}
