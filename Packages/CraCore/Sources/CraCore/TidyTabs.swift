import Foundation

/// Arc's Tidy Tabs (Arc Max, `createUnpinnedTabGroups()`), done with the Mac's own Apple Intelligence
/// model instead of Arc's server. The divider's Tidy button sorts a space's loose Today tabs under
/// named group headers (Arc's `SidebarItemData.tabGroup`): the model only proposes names and members;
/// everything here decides what the sidebar does with that answer. Arc 1.171, 4 Nov 2026.
public enum TidyTabs {
    /// Tidy is on the divider, without a hover, once Today holds more than this many tabs, grouped
    /// ones included (12 Nov 2026, the owner's call; Arc 1.171 offered it from six, on hover only).
    public static let shownAbove = 10
    /// A model answer can't hold a sidebar's worth of tabs: the on-device model reads ~4K tokens.
    public static let maximumTabs = 60
    static let maximumTitleLength = 80
    static let maximumNameLength = 32

    /// One loose Today tab as the model sees it: its place in the prompt is its id.
    public struct Tab: Equatable, Sendable {
        public var title: String
        public var host: String
        public init(title: String, host: String) {
            self.title = title
            self.host = host
        }
    }

    /// One group of the model's answer: tab ids from the prompt.
    public struct Proposal: Equatable, Sendable {
        public var name: String
        public var tabs: [Int]
        public init(name: String, tabs: [Int]) {
            self.name = name
            self.tabs = tabs
        }
    }

    /// What the sidebar does: new groups, in order, and tabs added to groups Today already has.
    public struct Plan: Equatable, Sendable {
        public var newGroups: [Proposal]
        /// Existing group index (as passed in) → tab ids joining it.
        public var joins: [Int: [Int]]
        public init(newGroups: [Proposal], joins: [Int: [Int]]) {
            self.newGroups = newGroups
            self.joins = joins
        }
        public var isEmpty: Bool { newGroups.isEmpty && joins.isEmpty }
    }

    /// When the divider shows Tidy.
    public enum Visibility: Equatable, Sendable {
        /// Nothing loose to sort: no Tidy.
        case hidden
        /// Shown only while Shift is held.
        case withShift
        /// Shown all the time, hover or not.
        case shown
    }

    /// The divider shows Tidy whenever Today holds more than `shownAbove` tabs, and with fewer while
    /// Shift is held; either way only with a loose tab left to sort (Tidy sorts loose tabs only). It
    /// no longer hides after a run until a new tab comes, as Arc's did (12 Nov 2026).
    public static func visibility(todayTabs: Int, looseTabs: Int) -> Visibility {
        guard looseTabs > 0 else { return .hidden }
        return todayTabs > shownAbove ? .shown : .withShift
    }

    /// Whether Tidy is on the divider now.
    public static func shows(_ v: Visibility, shiftHeld: Bool) -> Bool {
        switch v {
        case .hidden: false
        case .withShift: shiftHeld
        case .shown: true
        }
    }

    public static let instructions = """
    You sort a person's open browser tabs into groups, like tidying loose papers into labelled folders. \
    Put tabs about the same topic, task or project in one group, even when they come from different websites. \
    Make two to six groups and give each tab to exactly one group if it fits; a group needs at least two tabs. \
    Name each group with the topic, not the website.
    """

    /// The request: Arc's "Here are my tabs, in the format 'id: title':", plus the site, and the
    /// groups Today already has so new tabs can join them (Arc does that on a second Tidy).
    public static func prompt(tabs: [Tab], existingGroups: [String]) -> String {
        var lines = ["Here are my tabs, as 'id: title (site)':"]
        for (i, t) in tabs.prefix(maximumTabs).enumerated() {
            let title = clip(t.title.isEmpty ? t.host : t.title, maximumTitleLength)
            lines.append(t.host.isEmpty ? "\(i): \(title)" : "\(i): \(title) (\(t.host))")
        }
        if !existingGroups.isEmpty {
            lines.append("")
            lines.append("I already have these groups; reuse a name exactly to add tabs to it: "
                         + existingGroups.map { "\"\($0)\"" }.joined(separator: ", ") + ".")
        }
        return lines.joined(separator: "\n")
    }

    /// The model's answer made safe: ids in range and used once (first group wins), names trimmed
    /// and capped, a name that matches an existing group (any case) adds to it, two new groups with
    /// one name merge, and a new group needs two tabs. New groups keep the order of their first tab.
    public static func plan(_ proposals: [Proposal], tabCount: Int, existingGroups: [String]) -> Plan {
        var used = Set<Int>()
        var joins: [Int: [Int]] = [:]
        var newGroups: [Proposal] = []
        let existing = existingGroups.map(key)
        for p in proposals {
            let name = clip(p.name.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)), maximumNameLength)
            guard !name.isEmpty else { continue }
            var ids: [Int] = []
            for id in p.tabs where id >= 0 && id < min(tabCount, maximumTabs) && !used.contains(id) {
                used.insert(id)
                ids.append(id)
            }
            guard !ids.isEmpty else { continue }
            if let e = existing.firstIndex(of: key(name)) {
                joins[e, default: []].append(contentsOf: ids)
            } else if let n = newGroups.firstIndex(where: { key($0.name) == key(name) }) {
                newGroups[n].tabs.append(contentsOf: ids)
            } else {
                newGroups.append(Proposal(name: name, tabs: ids))
            }
        }
        newGroups = newGroups.filter { $0.tabs.count >= 2 }.map { Proposal(name: $0.name, tabs: $0.tabs.sorted()) }
        newGroups.sort { ($0.tabs.first ?? 0) < ($1.tabs.first ?? 0) }
        return Plan(newGroups: newGroups, joins: joins.mapValues { $0.sorted() })
    }

    /// Today's top level after a tidy: loose tabs left over first, in their order (Arc keeps new
    /// tabs above the groups), then the groups Today had, then the new ones. `Item` is either a loose
    /// tab or a group; `isGroup` tells them apart.
    public static func order<ID: Hashable>(today: [ID], isGroup: (ID) -> Bool, grouped: Set<ID>, newGroups: [ID]) -> [ID] {
        let loose = today.filter { !isGroup($0) && !grouped.contains($0) }
        let groups = today.filter(isGroup)
        return loose + groups + newGroups
    }

    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }

    static func clip(_ s: String, _ n: Int) -> String {
        let one = s.split(whereSeparator: \.isNewline).joined(separator: " ")
        return one.count <= n ? one : String(one.prefix(n - 1)) + "…"
    }
}

/// Sections: the named headers over tabs in Today (Arc's tab groups, which Tidy Tabs makes; 12 Nov 2026,
/// the owner's calls). A header collapses and expands its section like a folder, is dragged or moved
/// up and down among Today's items, and the user makes one by hand from picked tabs or a single tab.
public enum TabGroups {
    /// What the sidebar calls them.
    public static let noun = "Section"
    /// The name a section made by hand starts with, selected in its header for typing over.
    public static let newName = "New Section"

    /// Where a section made by hand from `picked` goes in Today (`today`: Today's children). The
    /// picks are tabs (or splits) listed top to bottom; `topLevel` is each one's item in Today, the
    /// pick itself when it is loose, the section holding it otherwise. The new section goes where the
    /// first pick is: in its place when it is loose, right after its section when it is in one (that
    /// section keeps the rest of its tabs). Nil when no pick is in Today.
    public static func newSectionIndex<ID: Equatable>(picked: [ID], today: [ID], topLevel: (ID) -> ID?) -> Int? {
        for p in picked {
            guard let top = topLevel(p), let i = today.firstIndex(of: top) else { continue }
            return top == p ? i : i + 1
        }
        return nil
    }

    /// The rows a group lists under its header, top to bottom: all of them open; collapsed, only the
    /// child holding the open tab (a tab, or the split it is a pane of), as a closed folder keeps
    /// its open tab in sight (FolderPeek).
    public static func listed<ID: Hashable>(children: [ID], collapsed: Bool, holdsOpenTab: (ID) -> Bool) -> [ID] {
        collapsed ? children.filter(holdsOpenTab) : children
    }

    public enum Direction: Sendable { case up, down }

    /// Today's children after moving `group` past the next group above or below it, loose tabs
    /// between staying where they are; nil when there is no group that way (Move Up on the top one).
    public static func moving<ID: Equatable>(_ group: ID, _ direction: Direction, in today: [ID], isGroup: (ID) -> Bool) -> [ID]? {
        guard let at = today.firstIndex(of: group) else { return nil }
        let groups = today.indices.filter { isGroup(today[$0]) }
        guard let g = groups.firstIndex(of: at) else { return nil }
        let other: Int
        switch direction {
        case .up: guard g > 0 else { return nil }; other = groups[g - 1]
        case .down: guard g + 1 < groups.count else { return nil }; other = groups[g + 1]
        }
        var out = today
        out.swapAt(at, other)
        return out
    }
}
