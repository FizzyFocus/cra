import Testing
@testable import CraCore

/// The favorites ride with the pages only between spaces whose lists differ (13 Nov 2026).
struct FavoritesSlideTests {
    // Pages: 0 and 1 share list "A" (one profile), 2 has "B" (another profile), 3 has "A" again.
    let lists = ["A", "A", "B", "A"]

    @Test func stillBetweenSpacesThatShareTheList() {
        for p in [0.0, 0.3, 0.5, 0.99, 1.0] {
            #expect(FavoritesSlide.place(position: p, lists: lists, shown: "A").isAtRest, "\(p)")
        }
    }

    @Test func anotherProfilesListRidesInWithItsPage() {
        // A quarter of the way from page 1 (A) to page 2 (B): A a quarter page left, B three quarters in from the right.
        let q = FavoritesSlide.place(position: 1.25, lists: lists, shown: "A")
        #expect(q.shown == -0.25)
        #expect(q.others == [FavoritesSlide.Other(page: 2, x: 0.75)])
        // After the release the grid shows B, and A goes out to the left the same way.
        let r = FavoritesSlide.place(position: 1.25, lists: lists, shown: "B")
        #expect(r.shown == 0.75 && r.others == [FavoritesSlide.Other(page: 1, x: -0.25)])
        #expect(FavoritesSlide.place(position: 2, lists: lists, shown: "B").isAtRest)
        // Going back the other way, from page 3 (A) to page 2 (B).
        let s = FavoritesSlide.place(position: 2.75, lists: lists, shown: "A")
        #expect(s.shown == 0.25 && s.others == [FavoritesSlide.Other(page: 2, x: -0.75)])
    }

    @Test func aJumpAcrossSpacesShowsWhateverListIsInSight() {
        // ⌘1 from page 3, the strip passing page 2 (B) on the way, the grid already showing A.
        let q = FavoritesSlide.place(position: 2.0, lists: lists, shown: "A")
        #expect(q.shown == nil && q.others == [FavoritesSlide.Other(page: 2, x: 0)])
    }

    @Test func pastEitherEndNothingMoves() {
        #expect(FavoritesSlide.place(position: -0.3, lists: lists, shown: "A").isAtRest)
        #expect(FavoritesSlide.place(position: 3.4, lists: lists, shown: "A").isAtRest)
        #expect(FavoritesSlide.place(position: 0.5, lists: [String](), shown: nil).isAtRest)
    }
}
