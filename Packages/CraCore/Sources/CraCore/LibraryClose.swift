import Foundation

/// How ⇧⌘L (and the Library button) closes the Library when it is open and at rest (11 Nov 2026).
public enum LibraryClose {
    public enum Motion: String, Equatable, Sendable {
        /// Docked: the drawer narrows back to the sidebar's width over the Library, and the tab list
        /// is there as it lands (no slide past the tab list, 10 Nov 2026).
        case narrow
        /// In the floating sidebar under the pointer: the Library slides back to the space exactly as
        /// its ← and Escape do, the sidebar staying out under the pointer. Narrowing there cut the
        /// Library in half at the sidebar's width before the tabs came back.
        case slideBack
        /// In the floating sidebar with the pointer elsewhere: the sidebar slides away at the
        /// Library's width, the Library going once it's out of sight.
        case withFloatingSidebar
    }

    public static func motion(floatingSidebarOut: Bool, pointerOnSidebar: Bool) -> Motion {
        guard floatingSidebarOut else { return .narrow }
        return pointerOnSidebar ? .slideBack : .withFloatingSidebar
    }
}
