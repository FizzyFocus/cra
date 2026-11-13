import Foundation

extension Easel {
    /// An address someone pasted or dropped, as a web address, or nil when it isn't one. Upstream keeps
    /// it in EaselObjects.swift (e4b7447, not in Pane); links dragged into the sidebar (SidebarLinkDrop,
    /// #419) need it, so it comes here on its own.
    public static func webAddress(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(where: \.isWhitespace), let u = URL(string: t),
              let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https", u.host?.isEmpty == false else { return nil }
        return t
    }
}
