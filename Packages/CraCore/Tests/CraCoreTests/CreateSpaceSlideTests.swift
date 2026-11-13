import Testing
@testable import CraCore

/// Create a Space slides in as the page after the last space and locks the space gestures (12 Nov 2026).
struct CreateSpaceSlideTests {
    @Test func opensFromTheRightAsTheListLeavesLeft() {
        #expect(CreateSpaceSlide.offsets(.opening, progress: 0) == (card: 1, list: 0))
        #expect(CreateSpaceSlide.offsets(.opening, progress: 1) == (card: 0, list: -1))
        let mid = CreateSpaceSlide.offsets(.opening, progress: 0.25)
        #expect(mid.card == 0.75 && mid.list == -0.25, "side by side, one width apart")
    }

    @Test func cancelGoesBackAndCreateGoesOn() {
        #expect(CreateSpaceSlide.offsets(.cancelling, progress: 0) == (card: 0, list: -1))
        #expect(CreateSpaceSlide.offsets(.cancelling, progress: 1) == (card: 1, list: 0))
        #expect(CreateSpaceSlide.offsets(.creating, progress: 0) == (card: 0, list: 1))
        #expect(CreateSpaceSlide.offsets(.creating, progress: 1) == (card: -1, list: 0))
        for move in [CreateSpaceSlide.Move.opening, .cancelling, .creating] {
            for p in [0.0, 0.3, 0.8, 1] {
                let o = CreateSpaceSlide.offsets(move, progress: p)
                #expect(abs(abs(o.card - o.list) - 1) < 1e-9, "the card and the list stay one width apart")
            }
        }
    }

    @Test func aCancelMidSlideTurnsRoundWhereTheCardIs() {
        let card = CreateSpaceSlide.offsets(.opening, progress: 0.4).card
        let p = CreateSpaceSlide.progress(.cancelling, card: card)
        #expect(abs(CreateSpaceSlide.offsets(.cancelling, progress: p).card - card) < 1e-9)
        #expect(CreateSpaceSlide.progress(.opening, card: 1) == 0)
        #expect(CreateSpaceSlide.progress(.creating, card: 0.5) == 0, "clamped: Create starts from the card in place")
    }

    @Test func theLibrarysSpringSettlesWithoutOvershoot() {
        #expect(CreateSpaceSlide.progress(at: 0) == 0)
        var last = 0.0
        for i in 1...60 {
            let p = CreateSpaceSlide.progress(at: Double(i) / 60)
            #expect(p >= last && p <= 1 + 1e-9)
            last = p
        }
        #expect(!CreateSpaceSlide.isDone(at: 0.05, width: 300))
        #expect(CreateSpaceSlide.isDone(at: 1, width: 300))
    }

    @Test func noSpaceGestureWhileCreatingASpace() {
        #expect(CreateSpaceSlide.allowsSpaceGesture(creatingSpace: false))
        #expect(!CreateSpaceSlide.allowsSpaceGesture(creatingSpace: true))
    }
}
