import Foundation

/// Tabs opened from a tab line up under it in the order they were opened: the first link right
/// below its tab, the next below that one, and so on, each new tab after the run of tabs that came
/// from it (and from those). `lineage` maps a tab to the tab it was opened from, for this session;
/// a tab moved by hand leaves it and starts a line of its own (SidebarStore).
public enum TabLineage {
    /// Where a tab opened from `parent` goes among `siblings` (its list, in order): just after the
    /// parent's run. nil when the parent isn't in the list.
    public static func insertionIndex(after parent: UUID, in siblings: [UUID], lineage: [UUID: UUID]) -> Int? {
        guard let p = siblings.firstIndex(of: parent) else { return nil }
        var i = p + 1
        while i < siblings.count, descends(siblings[i], from: parent, lineage: lineage) { i += 1 }
        return i
    }

    /// Whether `id` was opened from `parent`, directly or through tabs opened from it.
    public static func descends(_ id: UUID, from parent: UUID, lineage: [UUID: UUID]) -> Bool {
        var next = lineage[id], steps = 0
        while let p = next, steps < 256 {
            if p == parent { return true }
            next = lineage[p]
            steps += 1
        }
        return false
    }
}
