import AppKit

/// Chromium's views of its pages (WebContentsViewCocoa) wherever Pane shows one on the Chromium engine: a tab's page,
/// its DevTools, a Little Window's or Peek's page and theirs, an extension's popup or side panel. Chrome made each of
/// them for a window of its own that never shows (the engine's pages are views in Pane's windows), and a view Chrome
/// hid there, or never sized, came into Pane's window that way: a link's new tab (16 Nov 2026) and DevTools (17 Nov
/// 2026) were blank white with the page running behind them. Every place that puts one of them on screen goes through
/// `reveal`: shown, and as big as the view it sits in. Unhidden, Chromium's view tells its page it's visible again
/// (WebContentsViewCocoa's viewDidUnhide, Chrome's WasShown), and sized, its size (Chrome's SetSize).
@MainActor
enum ChromiumViews {
    /// Set by the app on the Chromium engine (CEF's pages and DevTools are in windows Chromium shows itself).
    static var isEnabled = false

    static let pageViewClass = "WebContentsViewCocoa"

    static func isPageView(_ view: NSView) -> Bool { NSStringFromClass(type(of: view)) == pageViewClass }

    /// Chromium's page views under `root`, outermost first: a page's own (not the views of pages inside it, such as a
    /// PDF's, which Chromium lays out itself).
    static func pageViews(in root: NSView) -> [NSView] {
        if isPageView(root) { return [root] }
        return root.subviews.flatMap { pageViews(in: $0) }
    }

    /// Shows and sizes Chromium's page views under `root` that Pane is showing (`root` is in a window, and nothing of
    /// Pane's above the view hides it): unhidden when Chromium's own window had hidden it, and filling the view it sits
    /// in when it had no size there. Returns how many it changed; `what` names them in the log.
    @discardableResult
    static func reveal(in root: NSView?, _ what: @autoclosure () -> String) -> Int {
        guard isEnabled, let root, root.window != nil, !root.isHiddenOrHasHiddenAncestor else { return 0 }
        var changed = 0
        for view in pageViews(in: root) {
            var done: [String] = []
            if view.isHidden {
                view.isHidden = false
                done.append("shown")
            }
            if let area = view.superview, area.bounds.width >= 1, area.bounds.height >= 1,
               view.frame.width < 1 || view.frame.height < 1 {
                view.frame = area.bounds
                view.autoresizingMask = [.width, .height]
                done.append("sized \(Int(view.frame.width))x\(Int(view.frame.height))")
            }
            guard !done.isEmpty else { continue }
            changed += 1
            CraLog.note("chromium view: \(what()) \(done.joined(separator: ", ")) (Chrome's window had left it hidden or empty)")
        }
        return changed
    }

    /// For `cra://debug?surfaces=<label>`: one line per Chromium page view in a window on screen, with what it is
    /// (`role`), the window it is in, whether it or a view above it is hidden, its size and whether it fills the view
    /// it sits in, its rect in the window (top-left origin, points) and whether that window is a child of another.
    static func readout(_ label: String, roles: [(String, NSView)]) -> [String] {
        var seen = Set<ObjectIdentifier>()
        var lines: [String] = []
        func line(_ role: String, _ view: NSView) {
            guard seen.insert(ObjectIdentifier(view)).inserted else { return }
            guard let window = view.window else {
                lines.append("surface \(label): \(role) window=- inWindow=0")
                return
            }
            let r = view.convert(view.bounds, to: nil)
            let top = (window.contentView?.bounds.height ?? window.frame.height) - r.maxY
            let ancestor = sequence(first: view.superview, next: { $0?.superview }).compactMap { $0 }.first { $0.isHidden }
            let area = view.superview?.bounds.size ?? .zero
            let fills = abs(view.frame.width - area.width) < 1 && abs(view.frame.height - area.height) < 1
            let occluded = !window.occlusionState.contains(.visible)
            // Chromium's frames come in a CALayerHost under the view's layers: none, and the page draws somewhere else
            // (the DevTools frontend drew into Chrome's never-shown window, 17 Nov 2026).
            // A page in one of Chrome's own windows (an extension's popup) draws with that window's compositor instead:
            // drawn=window.
            func hosts(_ layer: CALayer?) -> Bool {
                guard let layer else { return false }
                return NSStringFromClass(type(of: layer)) == "CALayerHost" || (layer.sublayers ?? []).contains { hosts($0) }
            }
            let drawn = hosts(view.layer) ? "1" : hosts(window.contentView?.layer) ? "window" : "0"
            lines.append("surface \(label): \(role) window=\(window.windowNumber) windowShown=\(window.isVisible ? 1 : 0) "
                + "parent=\(window.parent.map { "\($0.windowNumber)" } ?? "-") inWindow=1 selfHidden=\(view.isHidden ? 1 : 0) "
                + "hiddenBy=\(ancestor.map { "\(type(of: $0))" } ?? "-") size=\(Int(view.frame.width))x\(Int(view.frame.height)) "
                + "empty=\(view.frame.width < 1 || view.frame.height < 1 ? 1 : 0) fills=\(fills ? 1 : 0) "
                + "rect=\(Int(r.minX)),\(Int(top)),\(Int(r.width)),\(Int(r.height)) scale=\(window.backingScaleFactor) "
                + "drawn=\(drawn) occluded=\(occluded ? 1 : 0)")
        }
        for (role, root) in roles { for v in pageViews(in: root) { line(role, v) } }
        // Any other on screen, by its window's class (a view Pane doesn't know of is a finding too); a tab behind, which
        // Pane's own container hides, is not on screen.
        for window in NSApp.windows where window.isVisible {
            guard let cv = window.contentView else { continue }
            for v in pageViews(in: cv) where !(v.superview?.isHiddenOrHasHiddenAncestor ?? false) {
                line("other(\(type(of: window)))", v)
            }
        }
        return lines.isEmpty ? ["surface \(label): none"] : lines
    }
}
