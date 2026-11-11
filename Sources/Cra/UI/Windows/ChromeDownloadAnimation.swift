import AppKit

/// Hides Chrome's download-started animation as it appears (CraCore ChromeDownloadAnimationWindow
/// says which window it is). Chrome has no switch for it (only reduced motion), so for a couple of
/// seconds after a download starts every window is checked 120 times a second.
@MainActor
enum ChromeDownloadAnimation {
    /// Chrome posts the animation once the toolbar's download button has animated in.
    private static let watchDuration: TimeInterval = 2
    private static var watchUntil = Date.distantPast
    private static var timer: Timer?
    private static var hidden: Set<Int> = []

    /// Call when a download starts: as soon as Chromium asks where to save it (the animation can
    /// play before Cra hears the download's first update) and again on that update.
    static func suppress() {
        watchUntil = Date().addingTimeInterval(watchDuration)
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
    }

    private static func tick() {
        // Chrome sets the window's opacity on every frame of its animation: kept at 0 and out.
        for w in NSApp.windows where isAnimationWindow(w) && (w.isVisible || w.alphaValue > 0) {
            w.alphaValue = 0
            w.orderOut(nil)
            if hidden.insert(w.windowNumber).inserted {
                CraLog.note("chrome download animation hidden (\(Int(w.frame.width))x\(Int(w.frame.height)))")
            }
        }
        if Date() >= watchUntil {
            timer?.invalidate()
            timer = nil
        }
    }

    private static func isAnimationWindow(_ w: NSWindow) -> Bool {
        ChromeDownloadAnimationWindow.matches(className: NSStringFromClass(type(of: w)), ignoresMouse: w.ignoresMouseEvents,
                                              width: w.frame.width, height: w.frame.height)
    }
}
