/// What Escape does once nothing in the window took it (11 Nov 2026). AppKit's own answer was to
/// take a full-screen window out of full screen: Escape shrank a window someone had made big. It
/// now only ever closes things: a page's video full screen first (as browsers do), else whatever
/// is open over the window (popovers, the command bar, the find bar, a sheet). The window keeps its
/// size, full screen or zoomed; the green button, the title bar and Window ▸ Zoom change that.
public enum WindowEscape: Equatable, Sendable {
    case exitPageFullscreen
    case dismissOpen
    case nothing

    public static func action(pageFullscreen: Bool, somethingOpen: Bool) -> WindowEscape {
        if pageFullscreen { return .exitPageFullscreen }
        return somethingOpen ? .dismissOpen : .nothing
    }

    /// Whether Escape may change the window's size or leave full screen: never.
    public static let resizesWindow = false
}
