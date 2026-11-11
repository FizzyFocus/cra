import CraCore
import Testing

struct LibraryCloseTests {
    /// ⇧⌘L with the Library in the floating sidebar and the pointer on it: the ← slide back, not the
    /// docked sidebar's narrowing, which cut the Library in half (11 Nov 2026).
    @Test func underThePointerItSlidesBack() {
        #expect(LibraryClose.motion(floatingSidebarOut: true, pointerOnSidebar: true) == .slideBack)
    }

    @Test func awayFromThePointerItLeavesWithTheSidebar() {
        #expect(LibraryClose.motion(floatingSidebarOut: true, pointerOnSidebar: false) == .withFloatingSidebar)
    }

    @Test func dockedItNarrows() {
        #expect(LibraryClose.motion(floatingSidebarOut: false, pointerOnSidebar: true) == .narrow)
        #expect(LibraryClose.motion(floatingSidebarOut: false, pointerOnSidebar: false) == .narrow)
    }
}
