/// How often the floating sidebar samples the pointer (FloatingSidebarController), 11 Nov 2026.
/// Its 30 Hz timer ran whenever Cra was the active app, also with the sidebar docked, where every
/// tick returned at once: 30 wake-ups a second for nothing, and macOS flagged Cra as using
/// significant energy. It now runs only while there is something to reveal or hide, and slows
/// down once the pointer rests (any mouse event brings the fast rate back at once).
public enum FloatingSidebarPoll {
    /// Seconds between samples while the pointer moves: 30 Hz, the edge reveal's own pace (#293).
    public static let fast = 1.0 / 30
    /// Seconds between samples once the pointer has rested for `restAfter`: 4 Hz.
    public static let resting = 0.25
    public static let restAfter = 2.0

    /// Seconds between samples, or nil for none: in the background, and with the sidebar docked
    /// and not floating out, nothing is sampled.
    public static func interval(appActive: Bool, sidebarDocked: Bool, shown: Bool, pointerStillFor: Double) -> Double? {
        guard appActive, shown || !sidebarDocked else { return nil }
        return pointerStillFor >= restAfter ? resting : fast
    }
}
