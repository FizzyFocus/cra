import Foundation

/// A page in full screen (a video, HTMLMediaElement.requestFullscreen) leaves it before anything
/// else takes the window: another tab shown in its place (a click in the floating sidebar, a link
/// from another app, a new tab), or the command bar opening over it (⌘T, ⌘L). The window then
/// comes back to its own layout first, as Chrome does on a tab switch.
public enum ContentFullscreenExit {
    /// Whether the page `fullscreenTab` (nil: none is in full screen) leaves full screen, with
    /// `shownTabs` the tabs about to be on screen.
    public static func shouldExit(fullscreenTab: UUID?, shownTabs: [UUID], commandBarOpening: Bool) -> Bool {
        guard let tab = fullscreenTab else { return false }
        return commandBarOpening || !shownTabs.contains(tab)
    }
}
