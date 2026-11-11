import CraCore
import Testing

struct ChromeDownloadAnimationWindowTests {
    /// Chromium 156 shows it with no parent window: it must still be hidden (11 Nov 2026, both the
    /// white Chrome glyph and Arc's played at once).
    @Test func theAnimationIsHiddenWithOrWithoutAParent() {
        #expect(ChromeDownloadAnimationWindow.matches(className: "NativeWidgetMacNSWindow", ignoresMouse: true, width: 64, height: 64))
    }

    @Test func otherChromeWindowsStay() {
        // The 1 pt helper window, a popup that takes clicks, a bubble of another size, Cra's own panels.
        #expect(!ChromeDownloadAnimationWindow.matches(className: "NativeWidgetMacNSWindow", ignoresMouse: true, width: 1, height: 1))
        #expect(!ChromeDownloadAnimationWindow.matches(className: "NativeWidgetMacNSWindow", ignoresMouse: false, width: 64, height: 64))
        #expect(!ChromeDownloadAnimationWindow.matches(className: "NativeWidgetMacNSWindow", ignoresMouse: true, width: 320, height: 64))
        #expect(!ChromeDownloadAnimationWindow.matches(className: "NSPanel", ignoresMouse: true, width: 64, height: 64))
    }
}
