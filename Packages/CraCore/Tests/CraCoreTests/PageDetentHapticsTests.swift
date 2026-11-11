import CoreGraphics
import CraCore
import Testing

/// The trackpad tick of a sidebar swipe between spaces or into the Library (issue #260): Arc's
/// detent while the fingers move, and one tick on release for a page the drag never reached.
struct PageDetentHapticsTests {
    /// Moves the strip through `positions` (pages from the start) and lifts onto `target`;
    /// returns how many ticks the swipe asked for.
    private func ticks(_ positions: [CGFloat], landing target: Int, pages: ClosedRange<Int> = -1...1, from start: Int = 0) -> Int {
        var haptics = PageDetentHaptics(page: start)
        var count = positions.filter { haptics.track(position: $0, pages: pages) }.count
        if haptics.land(on: target) { count += 1 }
        return count
    }

    /// A flick changes the space from a fraction of a page (more than 0.8 pages a second); it
    /// never crossed a detent, so before #260 it changed the space without a tick.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/260"))
    func aFlickTicksOnce() {
        #expect(ticks([0.05, 0.1, 0.15], landing: 1) == 1)
        #expect(ticks([-0.05, -0.12], landing: -1) == 1)
    }

    /// A slow drag past half ticks there, as Arc does, and the landing on that page adds none.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/260"))
    func aDragPastHalfTicksOnce() {
        #expect(ticks([0.2, 0.4, 0.5, 0.7], landing: 1) == 1)
        // Arc rounds half away from zero: exactly half is the next page.
        var haptics = PageDetentHaptics()
        #expect(haptics.track(position: 0.49, pages: -1...1) == false)
        #expect(haptics.track(position: 0.5, pages: -1...1) == true)
    }

    /// A drag that goes nowhere is silent.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/260"))
    func aShortDragBackIsSilent() {
        #expect(ticks([0.1, 0.3, 0.1], landing: 0) == 0)
    }

    /// Out past half and back: a tick at each crossing (Arc's detent), none on landing home.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/260"))
    func outAndBackTicksAtEachCrossing() {
        #expect(ticks([0.3, 0.6, 0.3, 0.1], landing: 0) == 2)
    }

    /// Past half, then a flick back home: the last tick was for the next page, so the landing
    /// home ticks again and the last tick always names the page shown.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/260"))
    func aFlickBackFromPastHalfTicksForHome() {
        #expect(ticks([0.3, 0.6], landing: 0) == 2)
    }

    /// The rubber band past the last space is not a page: no tick, and none on settling back.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/260"))
    func theRubberBandIsSilent() {
        #expect(ticks([0.2, 0.4, 0.6], landing: 0, pages: -1...0) == 0)
    }

    /// The Library is the page before the first space: pulling it in ticks once, by drag or by
    /// flick, and pushing it out from the Library ticks once.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/260"))
    func theLibraryIsAPage() {
        #expect(ticks([-0.3, -0.6, -0.9], landing: -1, pages: -1...0) == 1)
        #expect(ticks([-0.2], landing: -1, pages: -1...0) == 1)
        #expect(ticks([-0.8, -0.3], landing: 0, pages: -1...0, from: -1) == 1)
    }

    @Test func aBrokenPositionIsSilent() {
        var haptics = PageDetentHaptics()
        #expect(haptics.track(position: .nan, pages: -1...1) == false)
        #expect(haptics.track(position: .infinity, pages: -1...1) == false)
        #expect(haptics.page == 0)
    }
}

@Suite struct SpaceSwipeCommitTests {
    /// A slow drag taps once at half way, and once more if it comes back.
    @Test func aSlowDragTapsAtHalfWay() {
        var c = SpaceSwipeCommit()
        let taps = [0.1, 0.3, 0.49, 0.51, 0.7].map { c.update(position: $0, velocity: 0.2) }
        #expect(taps == [false, false, false, true, false] && c.step == 1)
        let back = c.update(position: 0.4, velocity: -0.2)
        #expect(back && c.step == 0, "back short of half way")
    }

    /// A flick commits early, with the fingers still down: the tap comes then, not after the lift.
    @Test func aFlickTapsWhileTheFingersAreDown() {
        var c = SpaceSwipeCommit()
        let slow = c.update(position: 0.05, velocity: 0.5)
        let flick = c.update(position: 0.12, velocity: 1.6)
        let on = c.update(position: 0.2, velocity: 1.9)
        #expect(!slow && flick && !on && c.step == 1)
    }

    /// Hovering near the flick speed taps once, not on every sample that crosses it.
    @Test func nearTheFlickSpeedItDoesNotBuzz() {
        var c = SpaceSwipeCommit()
        var taps = 0
        for (i, v) in [0.85, 0.75, 0.82, 0.6, 0.9, 0.45].enumerated() where c.update(position: 0.1 + 0.03 * CGFloat(i), velocity: v) { taps += 1 }
        #expect(taps == 1 && c.step == 1)
        let letGo = c.update(position: 0.3, velocity: 0.1)
        #expect(letGo && c.step == 0, "slowing down short of half way lets go")
    }

    /// No space past the ends: nothing to commit to, nothing to tap.
    @Test func noTapPastTheEnds() {
        var c = SpaceSwipeCommit(pages: 0...1)
        let past = c.update(position: -0.8, velocity: -2)
        #expect(!past && c.step == 0)
        let next = c.update(position: 0.6, velocity: 0)
        #expect(next && c.step == 1)
    }
}
