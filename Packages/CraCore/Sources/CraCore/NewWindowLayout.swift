import CoreGraphics

/// How a new window (⌘N, ⇧⌘N, ⌃⌘N, a page's Open Link in New Window) opens: as a continuation of
/// the window in use. It keeps that window's sidebar (docked, or hidden and floating in from the
/// edge), goes full screen when it is (into a full-screen Space of its own, not a rectangle over
/// that one), fills the screen when it does (zoomed), and is otherwise its size, one cascade step
/// down and right, kept on its screen. A window in full screen only for a page's video passes
/// that on as a window, not as full screen. With no window in use it opens at the default place.
/// The toolbar (Settings) and the space's theme are the app's and the space's, the same in any window.
public struct NewWindowLayout: Equatable, Sendable {
    /// Where it opens; nil for the default place (centred, 1400 × 880).
    public var frame: CGRect?
    public var sidebarVisible: Bool
    public var fullScreen: Bool

    public init(frame: CGRect?, sidebarVisible: Bool, fullScreen: Bool) {
        self.frame = frame
        self.sidebarVisible = sidebarVisible
        self.fullScreen = fullScreen
    }

    /// The window in use, as the new one takes after it.
    public struct Source: Equatable, Sendable {
        /// Its frame on screen (in full screen, the screen's).
        public var frame: CGRect
        /// The frame it has outside full screen (what it saved), when known.
        public var windowedFrame: CGRect?
        public var fullScreen: Bool
        /// In full screen only while a page's video is.
        public var fullScreenForPage: Bool
        public var sidebarVisible: Bool
        /// Its screen's visible frame (no menu bar or Dock).
        public var visibleFrame: CGRect

        public init(frame: CGRect, windowedFrame: CGRect?, fullScreen: Bool, fullScreenForPage: Bool = false,
                    sidebarVisible: Bool, visibleFrame: CGRect) {
            self.frame = frame
            self.windowedFrame = windowedFrame
            self.fullScreen = fullScreen
            self.fullScreenForPage = fullScreenForPage
            self.sidebarVisible = sidebarVisible
            self.visibleFrame = visibleFrame
        }
    }

    /// One cascade step: down and to the right, as macOS cascades document windows.
    public static let cascade: CGFloat = 22

    public static let standalone = NewWindowLayout(frame: nil, sidebarVisible: true, fullScreen: false)

    public static func from(_ source: Source?) -> NewWindowLayout {
        guard let source else { return standalone }
        let visible = source.visibleFrame
        let windowed = source.fullScreen ? source.windowedFrame : source.frame
        return NewWindowLayout(frame: windowed.flatMap { cascaded($0, in: visible) }, sidebarVisible: source.sidebarVisible,
                               fullScreen: source.fullScreen && !source.fullScreenForPage)
    }

    /// `frame` one step on, inside `visible`: a zoomed window's twin fills the screen too; one that
    /// would leave the screen starts again one step in from its top left.
    static func cascaded(_ frame: CGRect, in visible: CGRect) -> CGRect? {
        guard !frame.isEmpty else { return nil }
        guard !visible.isEmpty else { return frame.offsetBy(dx: cascade, dy: -cascade) }
        if WindowFill.isMaximized(frame: frame, visibleFrame: visible) { return visible }
        let size = CGSize(width: min(frame.width, visible.width), height: min(frame.height, visible.height))
        var next = CGRect(origin: CGPoint(x: frame.minX + cascade, y: frame.maxY - cascade - size.height), size: size)
        if !visible.contains(next) {
            next.origin = CGPoint(x: visible.minX + cascade, y: visible.maxY - cascade - size.height)
            next.origin.x = min(next.minX, visible.maxX - size.width)
            next.origin.y = max(next.minY, visible.minY)
        }
        return next
    }
}
