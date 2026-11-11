import Foundation

/// Chrome's download-started animation (DownloadBubbleStartedAnimationViews): a 64 pt round download
/// glyph that fades in over the page and flies to the toolbar's download button. Cra keeps Chrome's
/// toolbar hidden and plays Arc's animation instead, so the window is hidden as it appears. It is a
/// views popup created with accept_events = false (it ignores the mouse), 2 × kIconBackgroundRadius
/// 32 pt square. Until Chromium 156 it was a child of the page's window; since then it has no parent
/// (11 Nov 2026, measured: NativeWidgetMacNSWindow 64x64 parent=none), so asking for one let it
/// through and both animations played at once.
public enum ChromeDownloadAnimationWindow {
    public static let side: Double = 64

    public static func matches(className: String, ignoresMouse: Bool, width: Double, height: Double) -> Bool {
        className.contains("NativeWidgetMac") && ignoresMouse && width == side && height == side
    }
}
