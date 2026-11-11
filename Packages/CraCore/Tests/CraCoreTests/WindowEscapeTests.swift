import CraCore
import Testing

/// Escape in a maximized or full-screen window (11 Nov 2026): it closes things, never the window's size.
struct WindowEscapeTests {
    @Test func escapeOnlyCloses() {
        #expect(WindowEscape.action(pageFullscreen: true, somethingOpen: true) == .exitPageFullscreen, "a video's full screen first")
        #expect(WindowEscape.action(pageFullscreen: false, somethingOpen: true) == .dismissOpen)
        #expect(WindowEscape.action(pageFullscreen: false, somethingOpen: false) == .nothing, "not out of full screen, not un-zoomed")
        #expect(!WindowEscape.resizesWindow)
    }
}
