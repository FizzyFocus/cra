import Foundation

/// Swiping on past the last space: a ring fills round a + as the fingers go on, a haptic tick at
/// each quarter, and letting go with the ring full opens Create a Space, the new space at the end.
/// `overscroll` is how far past the last space the fingers are, in sidebar widths.
///
/// It takes a deliberate swipe (12 Nov 2026, the owner's call): the ring doesn't show for the first
/// `start` of a sidebar's width, the rubber band a casual swipe ends in, and fills only at a whole
/// sidebar's width past the last space, twice the travel it took before (half a sidebar).
public struct SpaceCreateSwipe: Equatable, Sendable {
    /// Past the last space, this much travel shows nothing yet.
    public static let start = 0.15
    /// A whole sidebar past the last space fills the ring.
    public static let fullAt = 1.0
    /// The ring's fill is ticked at each of these.
    public static let ticks: [Double] = [0.25, 0.5, 0.75, 1]

    /// How many of `ticks` the fill has reached (it ticks again only after falling back below).
    public private(set) var reached = 0

    public init() {}

    /// The ring's fill, 0…1.
    public static func fill(overscroll: Double) -> Double { min(1, max(0, overscroll - start) / (fullAt - start)) }

    /// A new fill: whether it crossed a tick on the way up (one tap however many it crossed).
    public mutating func update(fill: Double) -> Bool {
        let now = Self.ticks.filter { fill >= $0 - 1e-9 }.count
        defer { reached = now }
        return now > reached
    }

    /// Letting go here opens Create a Space.
    public static func commits(fill: Double) -> Bool { fill >= 1 - 1e-9 }

    public mutating func reset() { reached = 0 }
}
