import Foundation
import Testing
@testable import CraCore

/// The sidebar's undo and redo (12 Nov 2026): one action's change taken back and done again, without
/// undoing what happened since and without tearing the sidebar over a change made since.
struct SidebarUndoTests {
    /// A space's Today: tabs a, b, c, and folder F holding d and e, in that order.
    struct Fixture {
        var items: [UUID: SidebarItem] = [:]
        let today: SidebarItem
        var ids: [String: UUID] = [:]

        init() {
            let space = UUID()
            var t = SidebarItem.container(.today(spaceID: space))
            var f = SidebarItem.folder("F", parent: t.id)
            var made: [String: SidebarItem] = [:]
            for n in ["a", "b", "c"] { made[n] = .tab("https://\(n).example/", title: n, parent: t.id) }
            for n in ["d", "e"] { made[n] = .tab("https://\(n).example/", title: n, parent: f.id) }
            t.children = [made["a"]!.id, made["b"]!.id, f.id, made["c"]!.id]
            f.children = [made["d"]!.id, made["e"]!.id]
            today = t
            for (n, it) in made { items[it.id] = it; ids[n] = it.id }
            ids["F"] = f.id
            items[t.id] = t
            items[f.id] = f
        }

        subscript(_ n: String) -> UUID { ids[n]! }
        func kids(_ id: UUID) -> [UUID] { items[id]!.children }
        var todayKids: [UUID] { kids(today.id) }

        mutating func remove(_ id: UUID) {
            if let p = items[id]?.parentID { items[p]!.children.removeAll { $0 == id } }
            items[id] = nil
        }
        mutating func insert(_ id: UUID, into parent: UUID, at i: Int) {
            if let old = items[id]?.parentID { items[old]!.children.removeAll { $0 == id } }
            items[parent]!.children.insert(id, at: min(i, items[parent]!.children.count))
            items[id]!.parentID = parent
        }
        func state(archive: [ArchivedItem] = [], selected: UUID? = nil) -> SidebarState {
            SidebarState(items: items, archive: archive, selections: selected.map { [UUID(uuidString: "00000000-0000-0000-0000-000000000001")!: [today.id: $0]] } ?? [:])
        }
    }

    static let window = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static func applied(_ s: SidebarState, _ r: (items: [UUID: SidebarItem?], archive: [ArchivedItem], selections: [UUID: [UUID: UUID]])) -> SidebarState {
        var out = s
        for (id, it) in r.items { out.items[id] = it }
        out.archive = r.archive
        out.selections = r.selections
        return out
    }

    @Test func closingATabUndoesAndRedoes() throws {
        var f = Fixture()
        let before = f.state(selected: f["b"])
        let entry = ArchivedItem(archivedAt: Date(timeIntervalSince1970: 100), reason: .manual, sourceSpaceID: nil, wasPinned: false, item: f.items[f["b"]]!)
        f.remove(f["b"])
        let after = f.state(archive: [entry], selected: f["c"])
        let change = try #require(SidebarUndo.change("Close Tab", before: before, after: after))
        #expect(change.name == "Close Tab" && change.archiveAdded.count == 1)

        let undone = Self.applied(after, try #require(SidebarUndo.apply(change, undo: true, to: after)))
        #expect(undone.items == before.items, "the tab is back, between a and the folder, as it was")
        #expect(undone.archive.isEmpty, "and out of the archive")
        #expect(undone.selections[Self.window]?[f.today.id] == f["b"], "open again where it was open")

        let redone = Self.applied(undone, try #require(SidebarUndo.apply(change, undo: false, to: undone)))
        #expect(redone.items == after.items && redone.archive == after.archive)
        #expect(redone.selections[Self.window]?[f.today.id] == f["c"])
    }

    @Test func whatHappenedSinceStays() throws {
        var f = Fixture()
        let before = f.state()
        f.remove(f["b"])
        let after = f.state()
        let change = try #require(SidebarUndo.change("Close Tab", before: before, after: after))
        // Since: a link opened a tab at the top, and tab a went to another page.
        let x = SidebarItem.tab("https://x.example/", parent: f.today.id)
        f.items[x.id] = x
        f.items[f.today.id]!.children.insert(x.id, at: 0)
        if case .tab(var t) = f.items[f["a"]]!.data { t.url = "https://a.example/next"; f.items[f["a"]]!.data = .tab(t) }
        let now = f.state()
        let undone = Self.applied(now, try #require(SidebarUndo.apply(change, undo: true, to: now)))
        #expect(undone.items[f.today.id]!.children == [x.id, f["a"], f["b"], f["F"], f["c"]], "b goes back after a; x stays on top")
        #expect(undone.items[f["a"]] == now.items[f["a"]], "a keeps the page it went to")
    }

    @Test func noUndoOverAChangeMadeSince() throws {
        var f = Fixture()
        let before = f.state()
        f.insert(f["b"], into: f["F"], at: 0)
        let change = try #require(SidebarUndo.change("Move Tab", before: before, after: f.state()))
        f.insert(f["b"], into: f.today.id, at: 0)   // moved again since, not by this change
        #expect(SidebarUndo.apply(change, undo: true, to: f.state()) == nil)
        f.remove(f["b"])                               // or closed since
        #expect(SidebarUndo.apply(change, undo: true, to: f.state()) == nil)
    }

    @Test func aDeletedFolderComesBackWithItsTabsInOrder() throws {
        var f = Fixture()
        let before = f.state()
        let d = f.items[f["d"]]!, e = f.items[f["e"]]!
        let archive = [ArchivedItem(archivedAt: Date(timeIntervalSince1970: 1), reason: .manual, sourceSpaceID: nil, wasPinned: false, item: e),
                       ArchivedItem(archivedAt: Date(timeIntervalSince1970: 1), reason: .manual, sourceSpaceID: nil, wasPinned: false, item: d)]
        f.remove(f["d"]); f.remove(f["e"]); f.remove(f["F"])
        let after = f.state(archive: archive)
        let change = try #require(SidebarUndo.change("Delete Folder", before: before, after: after))
        let undone = Self.applied(after, try #require(SidebarUndo.apply(change, undo: true, to: after)))
        #expect(undone.items == before.items && undone.archive.isEmpty)
        #expect(undone.items[f.today.id]!.children == [f["a"], f["b"], f["F"], f["c"]])
        #expect(undone.items[f["F"]]!.children == [f["d"], f["e"]])
    }

    @Test func movesGoBackAndARenameIsPutBack() throws {
        var f = Fixture()
        let before = f.state()
        f.insert(f["c"], into: f["F"], at: 1)
        f.items[f["F"]]!.title = "Renamed"
        let after = f.state()
        let change = try #require(SidebarUndo.change("Move Tab", before: before, after: after))
        let undone = Self.applied(after, try #require(SidebarUndo.apply(change, undo: true, to: after)))
        #expect(undone.items == before.items)
        // A field changed again since keeps its newer value.
        var g = after
        g.items[f["F"]]!.title = "Newer"
        let kept = Self.applied(g, try #require(SidebarUndo.apply(change, undo: true, to: g)))
        #expect(kept.items[f["F"]]!.title == "Newer" && kept.items[f["F"]]!.children == [f["d"], f["e"]])
    }

    /// A drag within one parent changes only that parent's list: ⌘Z still puts the item back (it said
    /// "Undid Move Tab" and moved nothing, 12 Nov 2026).
    @Test func aMoveWithinOneParentUndoesAndRedoes() throws {
        var f = Fixture()
        let before = f.state()
        f.insert(f["a"], into: f.today.id, at: 3)          // a to the end: b, F, c, a
        let after = f.state()
        let change = try #require(SidebarUndo.change("Move Tab", before: before, after: after))
        #expect(change.edits[f["a"]] != nil, "the tab that moved is in the change, not only its parent's list")
        let undone = Self.applied(after, try #require(SidebarUndo.apply(change, undo: true, to: after)))
        #expect(undone.items[f.today.id]!.children == [f["a"], f["b"], f["F"], f["c"]])
        let redone = Self.applied(undone, try #require(SidebarUndo.apply(change, undo: false, to: undone)))
        #expect(redone.items[f.today.id]!.children == [f["b"], f["F"], f["c"], f["a"]] && redone.items == after.items)
        // A whole folder moved down past a tab, its tabs with it.
        var g = Fixture()
        let b2 = g.state()
        g.insert(g["F"], into: g.today.id, at: 4)
        let c2 = try #require(SidebarUndo.change("Move Folder", before: b2, after: g.state()))
        let u2 = Self.applied(g.state(), try #require(SidebarUndo.apply(c2, undo: true, to: g.state())))
        #expect(u2.items == b2.items)
    }

    @Test func onlyTheChildrenThatChangedOrderMove() {
        let ids = (0..<6).map { _ in UUID() }
        let moved = SidebarUndo.reordered([ids[1], ids[2], ids[0], ids[3], ids[4], ids[5]], from: ids)
        #expect(moved == [ids[0]], "one tab dragged down: just it")
        #expect(SidebarUndo.reordered(ids, from: ids).isEmpty)
    }

    /// A reopen made into an undo: its inverse closes the tab again, and undoing that reopens it.
    @Test func anInvertedReopenRedoesAsAClose() throws {
        var f = Fixture()
        let reopened = f.state()
        let entry = ArchivedItem(archivedAt: Date(timeIntervalSince1970: 5), reason: .manual, sourceSpaceID: nil, wasPinned: false, item: f.items[f["b"]]!)
        f.remove(f["b"])
        let closed = f.state(archive: [entry])
        let reopen = try #require(SidebarUndo.change("Reopen", before: closed, after: reopened))
        let close = reopen.inverted(name: "Close Tab")
        #expect(close.name == "Close Tab")
        let redone = Self.applied(reopened, try #require(SidebarUndo.apply(close, undo: false, to: reopened)))
        #expect(redone.items == closed.items && redone.archive == closed.archive, "⇧⌘Z closes it again, into the archive")
        let undone = Self.applied(redone, try #require(SidebarUndo.apply(close, undo: true, to: redone)))
        #expect(undone.items == reopened.items && undone.archive.isEmpty, "and ⌘Z brings it back")
    }

    @Test func nothingToUndoWithoutAnItemOrArchiveChange() {
        let f = Fixture()
        #expect(SidebarUndo.change("Select", before: f.state(selected: f["a"]), after: f.state(selected: f["b"])) == nil)
        #expect(SidebarUndo.depth == 50)
    }
}
