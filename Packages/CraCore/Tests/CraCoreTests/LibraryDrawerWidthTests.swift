import CraCore
import Testing

/// Library drawers (Media, Downloads, Easels, Boosts, Archived Tabs) open the sidebar to ~400 pt.
struct LibraryDrawerWidthTests {
    @Test func aboutFourHundredInARoomyWindow() {
        #expect(LibraryDrawerWidth.width(sidebar: 328, window: 1440) == 400)
        #expect(LibraryDrawerWidth.width(sidebar: 260, window: 2560) == 400, "a wide window doesn't make it wider")
    }

    @Test func atMostNearlyHalfANarrowWindow() {
        #expect(LibraryDrawerWidth.width(sidebar: 300, window: 800) == 360)
    }

    @Test func neverNarrowerThanTheTabSidebar() {
        #expect(LibraryDrawerWidth.width(sidebar: 460, window: 1440) == 460)
        #expect(LibraryDrawerWidth.width(sidebar: 328, window: 600) == 328)
    }
}
