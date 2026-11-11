import CoreGraphics
import Foundation

/// When a sidebar swipe between pages (the spaces, and the Library before the first one) asks
/// the trackpad for a tick.
///
/// While the fingers move it ticks each time the page nearest the strip changes, as Arc 1.171's
/// `PageSwipeController` does (`performsPageDetentHaptics`, `lastDetentPageID`: the position
/// rounded half away from zero, checked only in its tracking loop, never in the settle or for a
/// wheel). That alone leaves a flick silent: it changes the page from a quarter of the way
/// across, so no detent is crossed (issue #260). So the release also ticks when the page the
/// swipe lands on is not the one that last ticked. Every page change then ends on exactly one
/// tick for the page it lands on, and a swipe that settles back where its last tick was says
/// nothing more.
///
/// Pages are counted from where the swipe began (0), + toward the next space; the Library is −1
/// from the first space.
public struct PageDetentHaptics: Sendable, Equatable {
    /// The page the last tick was for, or the swipe's starting page before any tick.
    public private(set) var page: Int

    public init(page: Int = 0) {
        self.page = page
    }

    /// The strip at `position` pages while the fingers move, `pages` being the ones it can land
    /// on (the rubber band past either end is not a page). Returns whether to tick.
    public mutating func track(position: CGFloat, pages: ClosedRange<Int>) -> Bool {
        guard position.isFinite else { return false }
        let nearest = Int(position.rounded(.toNearestOrAwayFromZero))
        guard pages.contains(nearest), nearest != page else { return false }
        page = nearest
        return true
    }

    /// The fingers lifted and the strip settles on page `target`. Returns whether to tick.
    public mutating func land(on target: Int) -> Bool {
        guard target != page else { return false }
        page = target
        return true
    }
}

/// Which space a swipe between spaces lands on, decided as the fingers move, not only at the
/// release: past half way, or moving faster than a flick (pages a second), it is the next or
/// previous space. A commit made by speed holds while the fingers keep moving that way at half a
/// flick's speed or more, so a swipe near the flick speed doesn't flip back and forth; it lets
/// go when they slow down short of half way. The release lands where this says, and the trackpad
/// taps each time it changes (`changed`): exactly once per page crossed, while the fingers are
/// still on the glass, where a Force Touch tap is felt. A flick used to tap only after the
/// fingers had lifted, so it was felt only some of the time.
public struct SpaceSwipeCommit: Sendable, Equatable {
    /// Pages a second that commit a swipe to the next or previous space (the release's rule).
    public static let flick: CGFloat = 0.8
    /// Below this a commit made by speed lets go (unless the strip is past half way).
    public static let hold: CGFloat = 0.4

    /// -1, 0 or +1: the space before, the one the swipe began on, or the next.
    public private(set) var step = 0
    /// The pages the swipe can land on, from where it began (0).
    public let pages: ClosedRange<Int>

    public init(pages: ClosedRange<Int> = -1...1) {
        self.pages = pages.clamped(to: -1...1)
    }

    /// One sample: where the strip is (pages from the start, + toward the next space) and how fast
    /// it moves (pages a second). Returns whether the landing space changed: the tap.
    public mutating func update(position: CGFloat, velocity: CGFloat) -> Bool {
        guard position.isFinite, velocity.isFinite else { return false }
        let byPosition = abs(position) > 0.5 ? (position > 0 ? 1 : -1) : 0
        var next: Int
        if abs(velocity) > Self.flick {
            next = velocity > 0 ? 1 : -1
        } else if step != 0, abs(velocity) >= Self.hold, (velocity > 0) == (step > 0) {
            next = step
        } else {
            next = byPosition
        }
        if !pages.contains(next) { next = 0 }
        guard next != step else { return false }
        step = next
        return true
    }
}
