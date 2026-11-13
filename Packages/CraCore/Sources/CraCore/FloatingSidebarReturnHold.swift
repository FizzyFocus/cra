/// Back from the Library to a floating sidebar (12 Nov 2026, the owner's call): the sidebar stays out
/// although the pointer is off it, as it was while the Library slid back, until the pointer moves on
/// away from it, comes onto it (then leaving takes it away as usual), or clicks outside it. Before,
/// it went the moment the slide back landed with the pointer off it.
public struct FloatingSidebarReturnHold: Equatable, Sendable {
    /// How much further from the sidebar than where it was when the hold began the pointer has to go.
    public static let release: Double = 48

    /// The pointer's distance from the sidebar when it came back.
    public let startDistance: Double

    public init(distanceFromSidebar: Double) { startDistance = max(0, distanceFromSidebar) }

    public enum Verdict: Equatable, Sendable {
        /// Keep the sidebar out.
        case hold
        /// The pointer came onto the sidebar: the hold is over, the sidebar stays.
        case visited
        /// The pointer went on away (or clicked outside): the sidebar may go.
        case release
    }

    /// The pointer `distanceFromSidebar` away from it now (0: on it), `clicked` outside it.
    public func verdict(distanceFromSidebar d: Double, clicked: Bool = false) -> Verdict {
        if d <= 0 { return .visited }
        if clicked || d >= startDistance + Self.release { return .release }
        return .hold
    }

    /// How far a point is from the sidebar's rectangle (0 inside), in points, from any side: a pointer
    /// left of the window is off the sidebar too, as the sidebar's own leave test has it.
    public static func distance(x: Double, y: Double, sidebarMinX: Double, sidebarMaxX: Double, top: Double, bottom: Double) -> Double {
        let dx = max(0, max(sidebarMinX - x, x - sidebarMaxX))
        let dy = max(0, max(bottom - y, y - top))
        return (dx * dx + dy * dy).squareRoot()
    }
}
