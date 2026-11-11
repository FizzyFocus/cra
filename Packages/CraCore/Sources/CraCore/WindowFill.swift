import CoreGraphics

/// When the page fills the window edge to edge: no margin round the card, square corners, no
/// card shadow. Settings ▸ "Pages fill the window edge to edge" (#24) does it always. A window that
/// fills its screen (zoomed to the visible frame: the green button with ⌥, a title bar
/// double-click, Window ▸ Fill; or macOS full screen) does it only while the sidebar is hidden (or
/// floats over the page): with the sidebar docked the card keeps Arc's inset, outline and rounded
/// corners, and the page meets the screen's edges only once nothing sits beside it. With DevTools
/// open in the window the card always keeps its margin and outline. Back in a smaller window the
/// margin and the rounded card return.
public enum WindowFill {
    /// How far a zoomed frame may sit from the screen's visible frame and still fill it: AppKit
    /// rounds the standard frame to whole points.
    public static let tolerance: CGFloat = 2

    /// Whether a window at `frame` fills `visibleFrame` (its screen less the menu bar and Dock).
    public static func isMaximized(frame: CGRect, visibleFrame: CGRect) -> Bool {
        guard !visibleFrame.isEmpty, !frame.isEmpty else { return false }
        return abs(frame.minX - visibleFrame.minX) <= tolerance && abs(frame.maxX - visibleFrame.maxX) <= tolerance
            && abs(frame.minY - visibleFrame.minY) <= tolerance && abs(frame.maxY - visibleFrame.maxY) <= tolerance
    }

    /// Whether the page goes edge to edge. `sidebarShown`: the sidebar is docked beside the page
    /// (not hidden, not floating over it). `devTools`: DevTools are open docked in the window: the
    /// card keeps its margin, except in full screen with the sidebar away, where the page and
    /// DevTools meet the screen's edges and each other with no margin, outline or corner (11 Nov
    /// 2026: they kept the window's inset card there).
    public static func edgeToEdge(setting: Bool, maximized: Bool, fullscreen: Bool, sidebarShown: Bool, devTools: Bool = false) -> Bool {
        if devTools { return fullscreen && !sidebarShown }
        return setting || ((maximized || fullscreen) && !sidebarShown)
    }

    /// How far a zoom has brought the window from `start` toward `target`, 0…1, read on the side
    /// that moves most (AppKit moves every side on one curve), so the card's margin shrinks or
    /// grows with the window and lands with it. 1 when the zoom moves nothing.
    public static func zoomProgress(start: CGRect, target: CGRect, current: CGRect) -> CGFloat {
        let sides: [(from: CGFloat, to: CGFloat, now: CGFloat)] = [
            (start.width, target.width, current.width), (start.height, target.height, current.height),
            (start.minX, target.minX, current.minX), (start.maxY, target.maxY, current.maxY),
        ]
        guard let side = sides.max(by: { abs($0.to - $0.from) < abs($1.to - $1.from) }), abs(side.to - side.from) > 0.5 else { return 1 }
        return min(1, max(0, (side.now - side.from) / (side.to - side.from)))
    }

    /// The card's margin on the way to edge to edge: all of `inset` at progress 0, none at 1, on the
    /// half point so its edges stay crisp at 2x.
    public static func inset(_ inset: CGFloat, progress: CGFloat) -> CGFloat {
        (inset * (1 - min(1, max(0, progress))) * 2).rounded() / 2
    }
}
