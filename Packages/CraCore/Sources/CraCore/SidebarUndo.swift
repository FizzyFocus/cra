import Foundation

/// The sidebar's undo and redo (⌘Z, ⇧⌘Z; 12 Nov 2026, the owner's call, after Arc's): every change
/// the user makes to the sidebar (closing tabs, folders and sections made, renamed or removed, tabs
/// moved, pinned or made favorites, Tidy Tabs) can be taken back and done again.
///
/// A change is what one action did, read off the sidebar before and after it: each item it touched
/// (made, removed, moved, edited) with its place among its siblings, the archive entries it added or
/// took, and the open tab of each window and space it changed. Undoing puts exactly those back and
/// leaves everything else as it is now, so a page that navigated since, or a tab a link opened, stays.
///
/// - A field is put back only if nothing changed it since the action (a tab's page went on to
///   another address: that stays). Parents and places always go back.
/// - An item goes back beside the sibling it was after (or before) at the time, else at its old index.
/// - It won't undo over a change made since to one of the same items (moved again, closed): `apply`
///   answers nil and the change is dropped rather than tearing the sidebar.
public struct SidebarChange: Equatable {
    /// Where an item sat: its parent, its index there, and its neighbours then.
    public struct Place: Equatable {
        public var parent: UUID
        public var index: Int
        public var previous: UUID?
        public var next: UUID?
    }

    public struct Edit: Equatable {
        public var before: SidebarItem?
        public var after: SidebarItem?
        public var placeBefore: Place?
        public var placeAfter: Place?
    }

    public struct Removed: Equatable {
        public var index: Int
        public var entry: ArchivedItem
    }

    /// What the action was called ("Close Tab", "Tidy Tabs"): the toast says "Undid …".
    public let name: String
    public let edits: [UUID: Edit]
    public let archiveAdded: [Removed]
    public let archiveRemoved: [Removed]
    /// Window → space → open tab, for the windows and spaces whose open tab the action changed.
    public let selectionBefore: [UUID: [UUID: UUID?]]
    public let selectionAfter: [UUID: [UUID: UUID?]]
    /// Spaces the action made, removed or changed (a name, an icon, a theme, a profile; 13 Nov 2026).
    public var spaceEdits: [UUID: SpaceEdit] = [:]
    /// The spaces' order before and after, when the action changed it.
    public var orderBefore: [UUID]? = nil
    public var orderAfter: [UUID]? = nil
    /// Sections collapsed (true) or open before and after, for the ones the action changed: a section
    /// removed and brought back comes back as it was.
    public var collapsedBefore: [UUID: Bool] = [:]
    public var collapsedAfter: [UUID: Bool] = [:]

    public struct SpaceEdit: Equatable {
        public var before: Space?
        public var after: Space?
    }
}

extension SidebarChange {
    /// The same change the other way round, under `name`: what was added is taken, what moved moves back.
    /// ⌘Z with nothing left to undo reopens the tab closed last; its inverse ("Close Tab") goes on the
    /// redo list, so ⇧⌘Z closes it again and the two keys go back and forth.
    public func inverted(name: String) -> SidebarChange {
        SidebarChange(name: name,
                      edits: edits.mapValues { .init(before: $0.after, after: $0.before, placeBefore: $0.placeAfter, placeAfter: $0.placeBefore) },
                      archiveAdded: archiveRemoved, archiveRemoved: archiveAdded,
                      selectionBefore: selectionAfter, selectionAfter: selectionBefore,
                      spaceEdits: spaceEdits.mapValues { .init(before: $0.after, after: $0.before) },
                      orderBefore: orderAfter, orderAfter: orderBefore,
                      collapsedBefore: collapsedAfter, collapsedAfter: collapsedBefore)
    }
}

/// The sidebar as undo sees it.
public struct SidebarState: Equatable {
    public var items: [UUID: SidebarItem]
    public var archive: [ArchivedItem]
    /// Window → space → open tab.
    public var selections: [UUID: [UUID: UUID]]
    /// The spaces, their order, and the sections shown collapsed.
    public var spaces: [UUID: Space]
    public var spaceOrder: [UUID]
    public var collapsed: Set<UUID>

    public init(items: [UUID: SidebarItem], archive: [ArchivedItem], selections: [UUID: [UUID: UUID]],
                spaces: [UUID: Space] = [:], spaceOrder: [UUID] = [], collapsed: Set<UUID> = []) {
        self.items = items
        self.archive = archive
        self.selections = selections
        self.spaces = spaces
        self.spaceOrder = spaceOrder
        self.collapsed = collapsed
    }
}

/// What `SidebarUndo.apply` turns the sidebar into: only what differs from now.
public struct SidebarUndoResult: Equatable {
    /// Items that change (nil: removed).
    public var items: [UUID: SidebarItem?]
    public var archive: [ArchivedItem]
    public var selections: [UUID: [UUID: UUID]]
    /// Spaces that change (nil: removed), the order when it changes, and the collapsed sections.
    public var spaces: [UUID: Space?]
    public var spaceOrder: [UUID]?
    public var collapsed: Set<UUID>
}

public enum SidebarUndo {
    /// How many changes ⌘Z can go back.
    public static let depth = 50

    /// What the action that turned `before` into `after` did; nil when it changed no item and no
    /// archive entry (a selection on its own isn't something to undo).
    public static func change(_ name: String, before: SidebarState, after: SidebarState) -> SidebarChange? {
        var edits: [UUID: SidebarChange.Edit] = [:]
        for id in Set(before.items.keys).union(after.items.keys) {
            let b = before.items[id], a = after.items[id]
            guard b != a else { continue }
            edits[id] = .init(before: b, after: a, placeBefore: place(of: id, in: before.items), placeAfter: place(of: id, in: after.items))
        }
        // A drag within one parent changes only the parent's list of children: the item that moved is the
        // same item. Each child that changed its order (not in the longest run of children that kept theirs)
        // is an edit too, so undo puts it back beside its old neighbours (12 Nov 2026: such a move's ⌘Z said
        // "Undid Move Tab" and moved nothing).
        for (_, e) in edits {
            guard let b = e.before, let a = e.after, b.children != a.children else { continue }
            let was = Set(b.children)
            let common = a.children.filter(was.contains)
            for c in reordered(common, from: b.children) where edits[c] == nil {
                guard let item = after.items[c] else { continue }
                edits[c] = .init(before: before.items[c], after: item, placeBefore: place(of: c, in: before.items),
                                 placeAfter: place(of: c, in: after.items))
            }
        }
        func key(_ e: ArchivedItem) -> String { "\(e.id)|\(e.archivedAt.timeIntervalSinceReferenceDate)" }
        let beforeKeys = Set(before.archive.map(key)), afterKeys = Set(after.archive.map(key))
        let added = after.archive.enumerated().filter { !beforeKeys.contains(key($0.element)) }.map { SidebarChange.Removed(index: $0.offset, entry: $0.element) }
        let removed = before.archive.enumerated().filter { !afterKeys.contains(key($0.element)) }.map { SidebarChange.Removed(index: $0.offset, entry: $0.element) }
        var spaceEdits: [UUID: SidebarChange.SpaceEdit] = [:]
        for id in Set(before.spaces.keys).union(after.spaces.keys) where before.spaces[id] != after.spaces[id] {
            spaceEdits[id] = .init(before: before.spaces[id], after: after.spaces[id])
        }
        let orderChanged = before.spaceOrder != after.spaceOrder
        // An open or collapsed section on its own isn't a step, as an open tab isn't.
        guard !edits.isEmpty || !added.isEmpty || !removed.isEmpty || !spaceEdits.isEmpty || orderChanged else { return nil }
        var collapsedBefore: [UUID: Bool] = [:], collapsedAfter: [UUID: Bool] = [:]
        for id in before.collapsed.symmetricDifference(after.collapsed) {
            collapsedBefore[id] = before.collapsed.contains(id)
            collapsedAfter[id] = after.collapsed.contains(id)
        }
        var selBefore: [UUID: [UUID: UUID?]] = [:], selAfter: [UUID: [UUID: UUID?]] = [:]
        for w in Set(before.selections.keys).union(after.selections.keys) {
            let b = before.selections[w] ?? [:], a = after.selections[w] ?? [:]
            for s in Set(b.keys).union(a.keys) where b[s] != a[s] {
                // .some: a nil assigned to a dictionary of optionals would drop the key, not record "none".
                selBefore[w, default: [:]][s] = .some(b[s])
                selAfter[w, default: [:]][s] = .some(a[s])
            }
        }
        return SidebarChange(name: name, edits: edits, archiveAdded: added, archiveRemoved: removed,
                             selectionBefore: selBefore, selectionAfter: selAfter, spaceEdits: spaceEdits,
                             orderBefore: orderChanged ? before.spaceOrder : nil, orderAfter: orderChanged ? after.spaceOrder : nil,
                             collapsedBefore: collapsedBefore, collapsedAfter: collapsedAfter)
    }

    /// Of `now` (children in their new order, all of them in `was` too), the ones whose order changed:
    /// those outside a longest subsequence that keeps the order they had in `was`.
    static func reordered(_ now: [UUID], from was: [UUID]) -> [UUID] {
        let at = Dictionary(was.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let seq = now.map { at[$0] ?? 0 }
        // Longest increasing subsequence (patience sorting), keeping each element's predecessor.
        var tails: [Int] = [], tailIndex: [Int] = [], prev = Array(repeating: -1, count: seq.count)
        for (i, v) in seq.enumerated() {
            var lo = 0, hi = tails.count
            while lo < hi { let mid = (lo + hi) / 2; if tails[mid] < v { lo = mid + 1 } else { hi = mid } }
            if lo > 0 { prev[i] = tailIndex[lo - 1] }
            if lo == tails.count { tails.append(v); tailIndex.append(i) } else { tails[lo] = v; tailIndex[lo] = i }
        }
        var keep = Set<Int>()
        var k = tailIndex.last ?? -1
        while k >= 0 { keep.insert(k); k = prev[k] }
        return now.enumerated().filter { !keep.contains($0.offset) }.map(\.element)
    }

    static func place(of id: UUID, in items: [UUID: SidebarItem]) -> SidebarChange.Place? {
        guard let p = items[id]?.parentID, let kids = items[p]?.children, let i = kids.firstIndex(of: id) else { return nil }
        return .init(parent: p, index: i, previous: i > 0 ? kids[i - 1] : nil, next: i + 1 < kids.count ? kids[i + 1] : nil)
    }

    /// The sidebar with `change` undone (`undo`) or done again: the items that differ from `current`
    /// (nil: removed), the archive and the open tabs as they become. Nil when something the change
    /// touched was changed since in a way it can't go back over.
    public static func apply(_ change: SidebarChange, undo: Bool, to current: SidebarState) -> SidebarUndoResult? {
        let from: (SidebarChange.Edit) -> SidebarItem? = { undo ? $0.after : $0.before }
        let to: (SidebarChange.Edit) -> SidebarItem? = { undo ? $0.before : $0.after }
        let placeFrom: (SidebarChange.Edit) -> SidebarChange.Place? = { undo ? $0.placeAfter : $0.placeBefore }
        let placeTo: (SidebarChange.Edit) -> SidebarChange.Place? = { undo ? $0.placeBefore : $0.placeAfter }

        // Each item is where the change left it: there, and under the same parent. Each space too.
        for (id, e) in change.edits {
            let now = current.items[id], was = from(e)
            guard (now == nil) == (was == nil) else { return nil }
            if let now, let was, now.parentID != was.parentID { return nil }
        }
        for (id, e) in change.spaceEdits {
            guard (current.spaces[id] == nil) == ((undo ? e.after : e.before) == nil) else { return nil }
        }

        var items = current.items
        var touched = Set<UUID>()
        func detach(_ id: UUID) {
            guard let p = items[id]?.parentID, var parent = items[p] else { return }
            parent.children.removeAll { $0 == id }
            items[p] = parent
            touched.insert(p)
        }
        // Which items take a new place: ones coming back, and ones whose parent or order changes.
        var placing: [(UUID, SidebarChange.Place)] = []
        for (id, e) in change.edits {
            guard let target = to(e) else {
                // Going: out of its parent and the sidebar.
                if items[id] != nil { detach(id); items[id] = nil; touched.insert(id) }
                continue
            }
            if from(e) == nil {
                // Coming back: as it was, its children placed one by one below (all of them are edits).
                // A container too (a deleted space's lists; 13 Nov 2026: it stayed gone, and its tabs
                // had nowhere to go back to).
                var it = target
                it.children = []
                items[id] = it
                touched.insert(id)
            }
            guard let p = placeTo(e) else { continue }   // a container: no parent of its own
            if from(e) == nil || placeFrom(e) != p { placing.append((id, p)) }
        }
        // Fields go back where nothing changed them since; parents and children follow the places.
        for (id, e) in change.edits {
            guard let target = to(e), let was = from(e), var now = items[id] else { continue }
            let merged = merge(now, from: was, to: target)
            if merged != now { now = merged; items[id] = now; touched.insert(id) }
        }
        for (id, _) in placing where current.items[id] != nil { detach(id) }
        // Siblings in the order they had: each goes beside the neighbour it had, if that is there.
        for (id, p) in placing.sorted(by: { $0.1.index < $1.1.index }) {
            guard var parent = items[p.parent] else { return nil }
            var kids = parent.children
            kids.removeAll { $0 == id }
            let at: Int
            if let prev = p.previous, let i = kids.firstIndex(of: prev) { at = i + 1 }
            else if let next = p.next, let i = kids.firstIndex(of: next) { at = i }
            else { at = min(p.index, kids.count) }
            kids.insert(id, at: at)
            parent.children = kids
            items[p.parent] = parent
            items[id]?.parentID = p.parent
            touched.formUnion([id, p.parent])
        }

        // The archive: what the action added goes, what it took comes back at its place.
        var archive = current.archive
        let adds = undo ? change.archiveAdded : change.archiveRemoved
        let takes = undo ? change.archiveRemoved : change.archiveAdded
        for r in adds {
            archive.removeAll { $0.id == r.entry.id && $0.archivedAt == r.entry.archivedAt }
        }
        for r in takes.sorted(by: { $0.index < $1.index }) where !archive.contains(where: { $0.id == r.entry.id && $0.archivedAt == r.entry.archivedAt }) {
            archive.insert(r.entry, at: min(r.index, archive.count))
        }

        // The open tabs: back to what they were, where that tab is there; none that is gone.
        var selections = current.selections
        for (w, spaces) in undo ? change.selectionBefore : change.selectionAfter {
            for (s, tab) in spaces {
                if let tab, items[tab]?.isTab == true { selections[w, default: [:]][s] = tab }
                else if let shown = selections[w]?[s], items[shown] == nil { selections[w]?[s] = nil }
            }
        }
        for (w, spaces) in selections {
            for (s, tab) in spaces where items[tab] == nil { selections[w]?[s] = nil }
        }

        // Spaces: back as they were, a field changed since keeping its newer value; one made goes, one
        // removed comes back; the order as it was, with any space made since kept after.
        var spaces: [UUID: Space?] = [:]
        var kept = Set(current.spaceOrder)
        for (id, e) in change.spaceEdits {
            let was = undo ? e.after : e.before, target = undo ? e.before : e.after
            switch (current.spaces[id], target) {
            case (_, nil): spaces[id] = .some(nil); kept.remove(id)
            case (nil, let t?): spaces[id] = t; kept.insert(id)
            case (let now?, let t?):
                let merged = was.map { mergeSpace(now, from: $0, to: t) } ?? t
                if merged != now { spaces[id] = merged }
            }
        }
        var order: [UUID]?
        if let target = undo ? change.orderBefore : change.orderAfter {
            let o = target.filter(kept.contains) + current.spaceOrder.filter { kept.contains($0) && !target.contains($0) }
            if o != current.spaceOrder { order = o }
        } else if spaces.values.contains(where: { $0 == nil }) {
            order = current.spaceOrder.filter(kept.contains)
        }
        // Sections open or collapsed as they were, where they are there.
        var collapsed = current.collapsed
        for (id, on) in undo ? change.collapsedBefore : change.collapsedAfter {
            if on, items[id] != nil { collapsed.insert(id) } else { collapsed.remove(id) }
        }

        var out: [UUID: SidebarItem?] = [:]
        for id in touched where items[id] != current.items[id] { out[id] = .some(items[id]) }
        return SidebarUndoResult(items: out, archive: archive, selections: selections, spaces: spaces, spaceOrder: order, collapsed: collapsed)
    }

    /// `now` with each of a space's fields `from` → `to` changed back, if it is still what `from` left.
    static func mergeSpace(_ now: Space, from: Space, to: Space) -> Space {
        var out = now
        func take<T: Equatable>(_ kp: WritableKeyPath<Space, T>) {
            if from[keyPath: kp] != to[keyPath: kp], now[keyPath: kp] == from[keyPath: kp] { out[keyPath: kp] = to[keyPath: kp] }
        }
        take(\.title)
        take(\.emoji)
        take(\.symbol)
        take(\.theme)
        take(\.profileID)
        take(\.favoritesContainerID)
        take(\.searchEngine)
        return out
    }

    /// `now` with each field `from` → `to` changed back, if it is still what `from` left.
    static func merge(_ now: SidebarItem, from: SidebarItem, to: SidebarItem) -> SidebarItem {
        var out = now
        func take<T: Equatable>(_ kp: WritableKeyPath<SidebarItem, T>) {
            if from[keyPath: kp] != to[keyPath: kp], now[keyPath: kp] == from[keyPath: kp] { out[keyPath: kp] = to[keyPath: kp] }
        }
        take(\.title)
        take(\.isUnread)
        take(\.data)
        take(\.folderIcon)
        take(\.folderColor)
        take(\.folderSymbol)
        take(\.liveFolder)
        take(\.tabGroup)
        take(\.tidyPolicy)
        return out
    }
}
