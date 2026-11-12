import CoreGraphics
import CraCore
import Testing

/// A new window takes after the window in use (12 Nov 2026: ⇧⌘N from a full-screen window with its
/// sidebar hidden opened as a docked rectangle over it).
struct NewWindowLayoutTests {
    // A 1512 × 982 pt screen less a 33 pt menu bar and a 70 pt Dock.
    static let visible = CGRect(x: 0, y: 70, width: 1512, height: 879)

    static func source(frame: CGRect = CGRect(x: 100, y: 200, width: 1200, height: 700), windowed: CGRect? = nil,
                       fullScreen: Bool = false, forPage: Bool = false, sidebar: Bool = true) -> NewWindowLayout.Source {
        .init(frame: frame, windowedFrame: windowed, fullScreen: fullScreen, fullScreenForPage: forPage, sidebarVisible: sidebar,
              visibleFrame: visible)
    }

    @Test func aWindowedSourceIsCascadedOneStep() {
        let l = NewWindowLayout.from(Self.source())
        #expect(l == NewWindowLayout(frame: CGRect(x: 122, y: 178, width: 1200, height: 700), sidebarVisible: true, fullScreen: false))
    }

    @Test func aHiddenSidebarStaysHidden() {
        #expect(NewWindowLayout.from(Self.source(sidebar: false)).sidebarVisible == false)
        #expect(NewWindowLayout.from(Self.source(fullScreen: true, sidebar: false)).sidebarVisible == false)
    }

    @Test func fullScreenGoesFullScreenFromItsWindowedFrame() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let l = NewWindowLayout.from(Self.source(frame: screen, windowed: CGRect(x: 100, y: 200, width: 1200, height: 700), fullScreen: true))
        #expect(l.fullScreen)
        // Out of full screen later, it is where a cascaded window would be, not the screen's size.
        #expect(l.frame == CGRect(x: 122, y: 178, width: 1200, height: 700))
        // Never saved outside full screen: the default place.
        #expect(NewWindowLayout.from(Self.source(frame: screen, fullScreen: true)).frame == nil)
    }

    @Test func aPagesVideoInFullScreenIsntPassedOn() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let l = NewWindowLayout.from(Self.source(frame: screen, windowed: CGRect(x: 100, y: 200, width: 1200, height: 700),
                                                 fullScreen: true, forPage: true))
        #expect(!l.fullScreen)
        #expect(l.frame == CGRect(x: 122, y: 178, width: 1200, height: 700))
    }

    @Test func aZoomedWindowsTwinFillsTheScreenToo() {
        let zoomed = Self.visible.insetBy(dx: 1, dy: 1)
        #expect(NewWindowLayout.from(Self.source(frame: zoomed)).frame == Self.visible)
    }

    @Test func oneThatWouldLeaveTheScreenStartsAgainAtItsTopLeft() {
        // Near the bottom right: a step on would cross the screen's edge.
        let l = NewWindowLayout.from(Self.source(frame: CGRect(x: 300, y: 80, width: 1200, height: 700)))
        #expect(l.frame == CGRect(x: 22, y: 949 - 22 - 700, width: 1200, height: 700))
    }

    @Test func aWindowTallerThanTheScreenIsCutToIt() {
        let l = NewWindowLayout.from(Self.source(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000)))
        let f = l.frame!
        #expect(f.width == Self.visible.width && f.height == Self.visible.height)
        #expect(Self.visible.contains(f))
    }

    @Test func noWindowInUseOpensAtTheDefaultPlace() {
        #expect(NewWindowLayout.from(nil) == NewWindowLayout(frame: nil, sidebarVisible: true, fullScreen: false))
    }
}
