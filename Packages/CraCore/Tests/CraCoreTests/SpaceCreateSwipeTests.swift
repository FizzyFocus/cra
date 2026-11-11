import Testing
@testable import CraCore

/// Swiping on past the last space fills a ring round a +; full on release opens Create a Space.
struct SpaceCreateSwipeTests {
    @Test func theRingFillsOverHalfASidebar() {
        #expect(SpaceCreateSwipe.fill(overscroll: -0.2) == 0)
        #expect(SpaceCreateSwipe.fill(overscroll: 0.25) == 0.5)
        #expect(SpaceCreateSwipe.fill(overscroll: 2) == 1)
        #expect(!SpaceCreateSwipe.commits(fill: 0.99) && SpaceCreateSwipe.commits(fill: 1))
    }

    @Test func aTickAtEachQuarterOnTheWayUpOnly() {
        var s = SpaceCreateSwipe()
        let a = s.update(fill: 0.1), b = s.update(fill: 0.26), c = s.update(fill: 0.3)
        #expect(!a && b && !c, "a tap at a quarter, none before or between")
        let d = s.update(fill: 0.8)
        #expect(d, "past a half and three quarters: one tap")
        let e = s.update(fill: 0.6), f = s.update(fill: 0.76), g = s.update(fill: 1)
        #expect(!e && f && g, "falling back doesn't tap; back up past three quarters does, and full")
        s.reset()
        #expect(s.reached == 0)
    }
}
