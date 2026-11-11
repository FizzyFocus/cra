import Foundation
import Testing
@testable import CraCore

@Suite struct BookmarksTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func oneAddressHoweverItIsTyped() {
        var lib = BookmarkLibrary()
        let b = lib.add(url: "https://Example.com/docs/", title: "Docs", now: t0)
        #expect(lib.isBookmarked("https://example.com/docs#intro"))
        #expect(lib.add(url: "https://example.com/docs", title: "Again", now: t0) == b, "no second bookmark for it")
        #expect(!lib.isBookmarked("https://example.com/other"))
    }

    /// bookmarks.json's own field names, and one entry that can't be read doesn't lose the rest.
    @Test func theFileRoundTripsAndSurvivesABadEntry() throws {
        var lib = BookmarkLibrary()
        let f = lib.addFolder(title: "Work", now: t0)
        lib.add(url: "https://a.test/", title: "A", folderId: f.id, now: t0)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(lib)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"folderId\"") && json.contains("\"createdAt\"") && json.contains("\"tags\""))
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        #expect(try dec.decode(BookmarkLibrary.self, from: data) == lib)
        let bad = ##"{"version":1,"folders":[],"bookmarks":[{"id":"nope"},{"id":"E3000000-0000-0000-0000-000000000001","url":"https://b.test/"}]}"##
        let read = try dec.decode(BookmarkLibrary.self, from: Data(bad.utf8))
        #expect(read.bookmarks.count == 1 && read.bookmarks[0].title == "https://b.test/")
    }

    @Test func foldersMakeATree() {
        var lib = BookmarkLibrary()
        let work = lib.addFolder(title: "Work", now: t0)
        let docs = lib.addFolder(title: "Docs", parentId: work.id, now: t0)
        let art = lib.addFolder(title: "Art", now: t0)
        #expect(lib.addFolder(title: "work", now: t0) == work, "same name, same place: the same folder")
        #expect(lib.folderTree().map(\.folder.title) == ["Art", "Work", "Docs"])
        #expect(lib.folderTree().map(\.depth) == [0, 0, 1])
        #expect(lib.path(of: docs.id) == "Work ▸ Docs")
        let b = lib.add(url: "https://d.test/", title: "D", folderId: docs.id, now: t0)
        lib.removeFolder(work.id)
        #expect(lib.folder(docs.id)?.parentId == nil && lib.bookmarks.first { $0.id == b.id }?.folderId == docs.id)
        lib.removeFolder(docs.id)
        #expect(lib.bookmarks.first { $0.id == b.id }?.folderId == nil, "its bookmarks move up")
        _ = art
    }

    @Test func searchMatchesTitlesAddressesAndTags() {
        var lib = BookmarkLibrary()
        var b = lib.add(url: "https://swift.org/documentation", title: "Swift Docs", now: t0)
        b.tags = ["lang"]
        lib.update(b)
        lib.add(url: "https://rust-lang.org", title: "Rust", now: t0.addingTimeInterval(1))
        #expect(lib.search("swift docs").map(\.title) == ["Swift Docs"])
        #expect(lib.search("LANG").count == 2, "a tag and an address")
        #expect(lib.search("").map(\.title) == ["Rust", "Swift Docs"], "newest first")
    }
}

@Suite struct FavoritePinGuardTests {
    private let tab = UUID()

    @Test func anOrdinaryTabPinsAtOnce() {
        var g = FavoritePinGuard()
        #expect(g.press(tab: tab, isFavorite: false, now: 0) == .pin)
    }

    @Test func aFavoriteWarnsThenPinsOnASecondPress() {
        var g = FavoritePinGuard()
        #expect(g.press(tab: tab, isFavorite: true, now: 10) == .warn)
        #expect(g.press(tab: tab, isFavorite: true, now: 11) == .pin)
        #expect(g.press(tab: tab, isFavorite: true, now: 12) == .warn, "the next one warns again")
    }

    @Test func tooLateOrAnotherTabWarnsAgain() {
        var g = FavoritePinGuard()
        #expect(g.press(tab: tab, isFavorite: true, now: 0) == .warn)
        #expect(g.press(tab: tab, isFavorite: true, now: 2) == .warn, "past 1.5 s")
        #expect(g.press(tab: UUID(), isFavorite: true, now: 2.5) == .warn)
    }
}

@Suite struct BookmarkStarTests {
    @Test func theStarSitsBesideTheExtensionsButton() {
        let bar = ToolbarComposition(kind: .normal, inSplit: false, sidebarVisible: true, focusedPane: true, canGoBack: false,
                                     canGoForward: false, isLoading: false, pinnedExtensions: ["x"], bookmarkStar: true)
        #expect(bar.right == [.pinnedExtension("x"), .bookmark(on: true), .extensions, .addSplit])
        #expect(ToolbarComposition.urlFieldAccessories(pinnedExtensions: [], fieldWidth: 300, bookmarkStar: false)
                == [.copyURL, .bookmark(on: false), .extensions])
    }

    @Test func noStarWithoutAPageOrWhenLeftOut() {
        let none = ToolbarComposition(kind: .noTab, inSplit: false, sidebarVisible: true, focusedPane: true, canGoBack: false,
                                      canGoForward: false, isLoading: false, pinnedExtensions: [], bookmarkStar: true)
        #expect(!none.right.contains(.bookmark(on: true)))
        #expect(ToolbarComposition.urlFieldAccessories(pinnedExtensions: [], fieldWidth: 300) == [.copyURL, .extensions], "Arc's, unchanged")
    }
}

@Suite struct BookmarkOutlineTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Folders are real folders: their own rows, open or closed, empty ones say so.
    @Test func foldersOpenAndCloseLikePinnedFolders() {
        var lib = BookmarkLibrary()
        let work = lib.addFolder(title: "Work", now: t0)
        let empty = lib.addFolder(title: "awd", now: t0)
        lib.add(url: "https://w.test/", title: "Wiki", folderId: work.id, now: t0)
        lib.add(url: "https://g.test/", title: "Gemini", now: t0)
        #expect(lib.outline() == [
            .folder(lib.folder(empty.id)!, depth: 0, open: true, empty: true), .emptyFolder(in: empty.id, depth: 1),
            .folder(lib.folder(work.id)!, depth: 0, open: true, empty: false), .bookmark(lib.bookmarks[0], depth: 1),
            .bookmark(lib.bookmarks[1], depth: 0),
        ])
        lib.setExpanded(work.id, false)
        #expect(lib.outline().count == 4, "a closed folder hides what is in it")
    }

    /// A deleted bookmark leaves its folder behind, empty and still there.
    @Test func aFolderOutlivesItsBookmarks() {
        var lib = BookmarkLibrary()
        let f = lib.addFolder(title: "Work", now: t0)
        let b = lib.add(url: "https://w.test/", title: "Wiki", folderId: f.id, now: t0)
        lib.remove(b.id)
        #expect(lib.outline() == [.folder(lib.folder(f.id)!, depth: 0, open: true, empty: true), .emptyFolder(in: f.id, depth: 1)])
    }

    @Test func searchingOpensTheFoldersThatLeadToMatches() {
        var lib = BookmarkLibrary()
        let a = lib.addFolder(title: "A", now: t0)
        let sub = lib.addFolder(title: "Sub", parentId: a.id, now: t0)
        lib.addFolder(title: "Other", now: t0)
        lib.setExpanded(a.id, false)
        lib.add(url: "https://x.test/", title: "Needle", folderId: sub.id, now: t0)
        let rows = lib.outline(matching: "needle")
        #expect(rows.count == 3)
        if case .folder(let f, 0, true, false) = rows[0] { #expect(f.id == a.id) } else { Issue.record("A first, opened") }
    }

    @Test func renameAndDeleteWithOrWithoutContents() {
        var lib = BookmarkLibrary()
        let f = lib.addFolder(title: "Old", now: t0)
        let sub = lib.addFolder(title: "Sub", parentId: f.id, now: t0)
        lib.add(url: "https://a.test/", title: "A", folderId: sub.id, now: t0)
        lib.renameFolder(f.id, to: "  New ")
        #expect(lib.folder(f.id)?.title == "New")
        #expect(lib.bookmarkCount(in: f.id) == 1)
        var keep = lib
        keep.removeFolder(f.id)
        #expect(keep.bookmarks.count == 1 && keep.folder(sub.id)?.parentId == nil)
        lib.removeFolder(f.id, keepContents: false)
        #expect(lib.bookmarks.isEmpty && lib.folders.isEmpty)
    }

    /// Folders saved before they could close come back open.
    @Test func olderFoldersReadAsOpen() throws {
        let json = ##"{"folders":[{"id":"E3000000-0000-0000-0000-000000000009","title":"awd","createdAt":"2026-11-10T08:00:00Z"}],"bookmarks":[]}"##
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        #expect(try d.decode(BookmarkLibrary.self, from: Data(json.utf8)).folders.first?.expanded == true)
    }
}

/// The Library's drag and drop: bookmarks and folders move between folders, never into
/// themselves; a drop on a row goes into that row's folder.
struct BookmarkMoveTests {
    private let t0 = Date(timeIntervalSince1970: 0)

    @Test func bookmarksMoveBetweenFoldersAndToTheTop() {
        var lib = BookmarkLibrary()
        let work = lib.addFolder(title: "Work", now: t0), home = lib.addFolder(title: "Home", now: t0)
        let b = lib.add(url: "https://a.test/", title: "A", folderId: work.id, now: t0)
        lib.setExpanded(home.id, false)
        #expect(!lib.canMove(.bookmark(b.id), into: work.id), "already there")
        let moved = lib.move(.bookmark(b.id), into: home.id)
        #expect(moved)
        #expect(lib.bookmarks.first?.folderId == home.id && lib.folder(home.id)?.expanded == true,
                "moved, and the closed folder it went into opens to show it")
        let top = lib.move(.bookmark(b.id), into: nil)
        #expect(top && lib.bookmarks.first?.folderId == nil, "to the top of the tree")
        let nowhere = lib.move(.bookmark(b.id), into: UUID())
        #expect(!nowhere, "not into a folder that isn't there")
        #expect(lib.folder(work.id) != nil, "the folder it left stays")
    }

    @Test func aFolderNeverGoesIntoItselfOrOneInsideIt() {
        var lib = BookmarkLibrary()
        let a = lib.addFolder(title: "A", now: t0)
        let b = lib.addFolder(title: "B", parentId: a.id, now: t0)
        let c = lib.addFolder(title: "C", now: t0)
        #expect(!lib.canMove(.folder(a.id), into: a.id) && !lib.canMove(.folder(a.id), into: b.id))
        let intoB = lib.move(.folder(c.id), into: b.id)
        #expect(intoB && lib.folder(c.id)?.parentId == b.id)
        #expect(!lib.canMove(.folder(a.id), into: c.id), "C is inside A now")
        let out = lib.move(.folder(b.id), into: nil)
        #expect(out && lib.folder(b.id)?.parentId == nil && lib.folder(c.id)?.parentId == b.id,
                "a folder takes what's in it along")
        #expect(!lib.canMove(.empty(a.id), into: nil))
    }

    @Test func aDropOnARowGoesIntoItsFolder() {
        var lib = BookmarkLibrary()
        let f = lib.addFolder(title: "F", now: t0), e = lib.addFolder(title: "E", now: t0)
        _ = lib.add(url: "https://in.test/", title: "In", folderId: f.id, now: t0)
        _ = lib.add(url: "https://top.test/", title: "Top", now: t0)
        let rows = lib.outline()
        #expect(rows.map(\.dropFolder) == [e.id, e.id, f.id, f.id, nil],
                "E, its empty line, F, the bookmark in F, the bookmark at the top")
    }

    /// Hover and drops find exactly one row; the 1 pt between two rows is neither's.
    @Test func aPointFallsOnOneRowAtMost() {
        let frames: [(top: Double, height: Double)] = [(0, 40), (41, 40), (82, 32)]
        #expect(BookmarkLibrary.row(at: 0, frames: frames) == 0)
        #expect(BookmarkLibrary.row(at: 39.9, frames: frames) == 0)
        #expect(BookmarkLibrary.row(at: 40.5, frames: frames) == nil)
        #expect(BookmarkLibrary.row(at: 41, frames: frames) == 1)
        #expect(BookmarkLibrary.row(at: 113.9, frames: frames) == 2)
        #expect(BookmarkLibrary.row(at: 200, frames: frames) == nil && BookmarkLibrary.row(at: -1, frames: frames) == nil)
    }
}

