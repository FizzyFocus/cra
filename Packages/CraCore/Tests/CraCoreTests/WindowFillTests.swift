import CoreGraphics
import CraCore
import Testing

/// A window that fills its screen drops the margin and rounded card, as the edge to edge setting does.
struct WindowFillTests {
    /// A 1512 × 982 screen with a 33 pt menu bar and the Dock hidden.
    let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)

    @Test func aZoomedWindowFillsItsScreen() {
        #expect(WindowFill.isMaximized(frame: visible, visibleFrame: visible))
        // AppKit rounds the standard frame to whole points.
        #expect(WindowFill.isMaximized(frame: visible.insetBy(dx: 1, dy: 1), visibleFrame: visible))
    }

    @Test func aSmallerWindowDoesNot() {
        #expect(!WindowFill.isMaximized(frame: CGRect(x: 100, y: 80, width: 1200, height: 800), visibleFrame: visible))
        // Full width but not full height (a left/right tile, a window dragged tall).
        #expect(!WindowFill.isMaximized(frame: CGRect(x: 0, y: 0, width: 1512, height: 900), visibleFrame: visible))
        // Tiled with macOS's margins.
        #expect(!WindowFill.isMaximized(frame: visible.insetBy(dx: 8, dy: 8), visibleFrame: visible))
    }

    @Test func aWindowOnAnotherScreenComparesWithThatScreen() {
        let second = CGRect(x: 1512, y: -200, width: 2560, height: 1415)
        #expect(WindowFill.isMaximized(frame: second, visibleFrame: second))
        #expect(!WindowFill.isMaximized(frame: second, visibleFrame: visible))
    }

    @Test func noScreenIsNeverMaximized() {
        #expect(!WindowFill.isMaximized(frame: .zero, visibleFrame: .zero))
        #expect(!WindowFill.isMaximized(frame: visible, visibleFrame: .zero))
    }

    /// The card's margin goes with the window during a zoom and lands with it, both ways.
    @Test func zoomProgressFollowsTheWindow() {
        let small = CGRect(x: 200, y: 150, width: 1000, height: 700)
        #expect(WindowFill.zoomProgress(start: small, target: visible, current: small) == 0)
        #expect(WindowFill.zoomProgress(start: small, target: visible, current: visible) == 1)
        let halfway = CGRect(x: 100, y: 75, width: 1256, height: 824.5)
        #expect(abs(WindowFill.zoomProgress(start: small, target: visible, current: halfway) - 0.5) < 0.01)
        // Restoring reads the same way: from the zoomed frame back toward the window's own.
        #expect(abs(WindowFill.zoomProgress(start: visible, target: small, current: halfway) - 0.5) < 0.01)
        #expect(WindowFill.zoomProgress(start: small, target: small, current: small) == 1, "a zoom that moves nothing has landed")
        #expect(WindowFill.zoomProgress(start: small, target: visible, current: visible.insetBy(dx: -10, dy: -10)) == 1, "past the end stays at 1")
    }

    @Test func theMarginShrinksOnTheHalfPoint() {
        #expect(WindowFill.inset(10, progress: 0) == 10)
        #expect(WindowFill.inset(10, progress: 1) == 0)
        #expect(WindowFill.inset(10, progress: 0.33) == 6.5)
        #expect(WindowFill.inset(10, progress: 2) == 0)
    }

    @Test func edgeToEdgeFollowsTheSettingOrAFilledScreen() {
        #expect(!WindowFill.edgeToEdge(setting: false, maximized: false, fullscreen: false, sidebarShown: true), "a normal window keeps its margin")
        #expect(!WindowFill.edgeToEdge(setting: false, maximized: false, fullscreen: false, sidebarShown: false))
        #expect(WindowFill.edgeToEdge(setting: true, maximized: false, fullscreen: false, sidebarShown: true))
        #expect(WindowFill.edgeToEdge(setting: false, maximized: false, fullscreen: true, sidebarShown: false))
    }

    /// Full screen beside the docked sidebar keeps Arc's inset card, as a maximized window does.
    @Test func fullScreenKeepsItsInsetWhileTheSidebarShows() {
        #expect(!WindowFill.edgeToEdge(setting: false, maximized: false, fullscreen: true, sidebarShown: true))
    }

    /// DevTools open in the window: the card keeps its margin and outline, in a maximized window and
    /// beside the docked sidebar, whatever the setting.
    @Test func devToolsKeepTheCardsMargin() {
        for setting in [false, true] {
            #expect(!WindowFill.edgeToEdge(setting: setting, maximized: true, fullscreen: false, sidebarShown: false, devTools: true))
            #expect(!WindowFill.edgeToEdge(setting: setting, maximized: false, fullscreen: true, sidebarShown: true, devTools: true))
        }
    }

    /// In full screen with the sidebar hidden or floating, the page and docked DevTools go flush to
    /// the screen's edges like a page alone (11 Nov 2026: they kept the inset card's margin and corners).
    @Test func devToolsGoEdgeToEdgeInFullScreenWithTheSidebarAway() {
        for setting in [false, true] {
            #expect(WindowFill.edgeToEdge(setting: setting, maximized: false, fullscreen: true, sidebarShown: false, devTools: true))
        }
    }

    @Test func aMaximizedWindowKeepsItsInsetWhileTheSidebarShows() {
        #expect(!WindowFill.edgeToEdge(setting: false, maximized: true, fullscreen: false, sidebarShown: true),
                "Arc's inset card beside the sidebar")
        #expect(WindowFill.edgeToEdge(setting: false, maximized: true, fullscreen: false, sidebarShown: false),
                "nothing beside the page: it meets the screen's edges")
        #expect(WindowFill.edgeToEdge(setting: true, maximized: true, fullscreen: false, sidebarShown: true), "the setting still wins")
    }
}
