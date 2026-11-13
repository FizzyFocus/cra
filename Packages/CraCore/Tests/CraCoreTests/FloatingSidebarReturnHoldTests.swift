import Testing
@testable import CraCore

/// Back from the Library, the floating sidebar waits for the pointer to move on away (12 Nov 2026).
struct FloatingSidebarReturnHoldTests {
    @Test func holdsUntilThePointerMovesOnAway() {
        let hold = FloatingSidebarReturnHold(distanceFromSidebar: 300)
        #expect(hold.verdict(distanceFromSidebar: 300) == .hold, "where it rested: stays")
        #expect(hold.verdict(distanceFromSidebar: 200) == .hold, "toward the sidebar: stays")
        #expect(hold.verdict(distanceFromSidebar: 340) == .hold, "a small drift: stays")
        #expect(hold.verdict(distanceFromSidebar: 348) == .release, "48 pt further out: it may go")
        #expect(hold.verdict(distanceFromSidebar: 0) == .visited, "onto the sidebar: the hold is over")
        #expect(hold.verdict(distanceFromSidebar: 310, clicked: true) == .release, "a click outside lets it go")
    }

    @Test func distanceFromTheSidebarsRectangle() {
        #expect(FloatingSidebarReturnHold.distance(x: 100, y: 300, sidebarMinX: 0, sidebarMaxX: 250, top: 800, bottom: 0) == 0)
        #expect(FloatingSidebarReturnHold.distance(x: 400, y: 300, sidebarMinX: 0, sidebarMaxX: 250, top: 800, bottom: 0) == 150)
        #expect(FloatingSidebarReturnHold.distance(x: 250, y: 840, sidebarMinX: 0, sidebarMaxX: 250, top: 800, bottom: 0) == 40)
        #expect(FloatingSidebarReturnHold.distance(x: -30, y: 300, sidebarMinX: 0, sidebarMaxX: 250, top: 800, bottom: 0) == 30,
                "left of the window is off the sidebar too")
    }
}
