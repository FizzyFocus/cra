/// When the sidebar list scrolls its active row into view. Arc 1.171 brings whatever becomes active
/// into view (a tab picked, ⌘T's New Tab row, Next Tab, a command bar commit), scrolling as little as
/// shows the row and leaving a list scrolled by hand alone otherwise. A space switch makes nothing
/// active: the space comes back scrolled where it was left. Before (16 Nov 2026), switching back
/// scrolled the list down to its active tab: a space out of sight has no active row, so its tab
/// looked newly active each time the space came back.
public enum ActiveRowReveal {
    /// One step of the list's sync. `shown`: the list's space is its window's. `active`: the row
    /// standing for what is open (only while shown). `spaceOwn`: the row of the space's own selected
    /// tab, which is active again once the space is shown. `last`: what the previous step remembered.
    /// Returns whether to scroll `active` into view, and what to remember for the next step.
    public static func step<Key: Equatable>(shown: Bool, active: Key?, spaceOwn: Key?, last: Key?) -> (reveal: Bool, remember: Key?) {
        // Out of sight, the list remembers the row that will be active when it's back, so coming
        // back is no change.
        guard shown else { return (false, spaceOwn) }
        return (active != nil && active != last, active)
    }

    /// The first sync of a list: nothing scrolls, whatever is active (or will be) is remembered.
    public static func first<Key>(shown: Bool, active: Key?, spaceOwn: Key?) -> Key? {
        shown ? active : spaceOwn
    }
}
