import CoreGraphics

/// Create a Space comes into the sidebar as the page after the last space (12 Nov 2026, the owner's
/// call): it slides in from the right while the favorites and the tab list slide out to the left,
/// on the spring the Library slides in on before the first space (LibrarySwipe's), instead of
/// fading in over the tabs. Cancel slides both back; Create Space carries on forward, the new
/// space's list coming in from the right as the card leaves to the left.
///
/// While it is open the space gestures do nothing (a swipe, a sideways wheel, a mouse's back and
/// forward buttons): the space under it stays until Create a Space is cancelled or made. Before,
/// a swipe switched spaces under the card, which stayed up over another space.
public enum CreateSpaceSlide {
    public enum Move: Equatable, Sendable {
        case opening
        case cancelling
        /// Create Space made the space: the column goes on to it.
        case creating
    }

    /// Where the Create a Space card and the space's list (favorites, tabs) sit at progress `p`
    /// (0…1) of `move`, as fractions of the column's width: 0 in place, 1 one width to the right.
    public static func offsets(_ move: Move, progress p: Double) -> (card: Double, list: Double) {
        let p = min(1, max(0, p))
        switch move {
        case .opening: return (1 - p, -p)
        case .cancelling: return (p, p - 1)
        case .creating: return (-p, 1 - p)
        }
    }

    /// The progress of `move` at which the card sits at `card`: a move that takes over from one still
    /// sliding (Cancel pressed while the card comes in) starts where the card is, so it turns round
    /// without a jump.
    public static func progress(_ move: Move, card: Double) -> Double {
        let p: Double
        switch move {
        case .opening: p = 1 - card
        case .cancelling: p = card
        case .creating: p = -card
        }
        return min(1, max(0, p))
    }

    /// The slide's progress `t` seconds after it started from `from`: the Library's zero-bounce spring.
    public static func progress(at t: Double, from: Double = 0) -> Double {
        Double(LibrarySwipe.settle(from: CGFloat(from), velocity: 0, to: 1, at: CGFloat(max(0, t))))
    }

    /// The slide is over, for a column `width` points wide.
    public static func isDone(at t: Double, from: Double = 0, width: Double) -> Bool {
        LibrarySwipe.isSettled(from: CGFloat(from), velocity: 0, to: 1, at: CGFloat(max(0.01, t)), width: CGFloat(width))
    }

    /// Whether a space gesture may switch spaces now.
    public static func allowsSpaceGesture(creatingSpace: Bool) -> Bool { !creatingSpace }
}
