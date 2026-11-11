import Foundation
import Testing
@testable import CraCore

/// Bookmarks brought in from bookmarks.html and from Chromium's bookmark manager (BookmarkImport).
struct BookmarkImportTests {
    private let t0 = Date(timeIntervalSince1970: 0)

    /// Chrome's own export, as it writes it: no closing <DT>, <p> after each list, entities.
    static let chromeExport = """
    <!DOCTYPE NETSCAPE-Bookmark-file-1>
    <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
    <TITLE>Bookmarks</TITLE>
    <H1>Bookmarks</H1>
    <DL><p>
        <DT><H3 ADD_DATE="1700000000" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks bar</H3>
        <DL><p>
            <DT><A HREF="https://www.youtube.com/" ADD_DATE="1700000100" ICON="data:image/png;base64,AA==">YouTube</A>
            <DT><H3>Reading &amp; Notes</H3>
            <DL><p>
                <DT><A HREF="https://example.com/a?x=1&amp;y=2">A &lt;page&gt;</A>
                <DT><A HREF='https://example.com/b'>B</A>
            </DL><p>
            <DT><A HREF="javascript:alert(1)">Bookmarklet</A>
        </DL><p>
        <DT><A HREF="https://top.test/">Top &#8212; level</A>
    </DL><p>
    """

    @Test func netscapeFilesKeepTheirFolders() {
        let tree = NetscapeBookmarks.parse(Self.chromeExport)
        #expect(tree.count == 2, "the bar and the loose bookmark; the page's own heading is no folder")
        guard case .folder(let bar, let barKids, _) = tree.first else { Issue.record("no bar"); return }
        #expect(bar == "Bookmarks bar")
        #expect(barKids.count == 2, "the bookmarklet is left out")
        #expect(barKids.first == .bookmark(title: "YouTube", url: "https://www.youtube.com/", added: Date(timeIntervalSince1970: 1_700_000_100), id: nil))
        guard case .folder(let reading, let readingKids, _) = barKids.last else { Issue.record("no folder"); return }
        #expect(reading == "Reading & Notes")
        #expect(readingKids == [.bookmark(title: "A <page>", url: "https://example.com/a?x=1&y=2", added: nil, id: nil),
                                .bookmark(title: "B", url: "https://example.com/b", added: nil, id: nil)])
        #expect(tree.last == .bookmark(title: "Top — level", url: "https://top.test/", added: nil, id: nil))
    }

    @Test func aBrokenFileKeepsWhatItHad() {
        let tree = NetscapeBookmarks.parse("<DL><DT><H3>Open</H3><DL><DT><A HREF=\"https://a.test\">A</A>")
        #expect(tree.first?.counts.bookmarks == 1)
    }

    static let chromiumFile = """
    {"checksum":"x","roots":{
      "bookmark_bar":{"children":[
        {"guid":"g-yt","name":"YouTube","type":"url","url":"https://www.youtube.com/","date_added":"13340000000000000"},
        {"guid":"g-dev","name":"Dev","type":"folder","children":[
          {"guid":"g-gh","name":"GitHub","type":"url","url":"https://github.com/"}]}],
        "name":"Bookmarks bar","type":"folder","guid":"bar"},
      "other":{"children":[{"guid":"g-o","name":"","type":"url","url":"https://other.test/"}],"name":"Other bookmarks","type":"folder","guid":"other"},
      "synced":{"children":[],"name":"Mobile bookmarks","type":"folder","guid":"synced"}},"version":1}
    """

    @Test func chromiumsBookmarkBarComesToTheTop() {
        let tree = ChromiumBookmarks.parse(Data(Self.chromiumFile.utf8))
        #expect(tree.count == 3, "YouTube, Dev, and Other Bookmarks (the empty Mobile folder is left out)")
        guard case .bookmark(_, _, let added, let id) = tree.first else { Issue.record("no first"); return }
        #expect(id == "g-yt" && added != nil && abs(added!.timeIntervalSince1970 - (13_340_000_000 - 11_644_473_600)) < 1)
        guard case .folder(let other, let kids, _) = tree.last else { Issue.record("no other"); return }
        #expect(other == "Other Bookmarks" && kids == [.bookmark(title: "https://other.test/", url: "https://other.test/", added: nil, id: "g-o")])
    }

    @Test func mergingAddsFoldersAndSkipsWhatIsThere() {
        var lib = BookmarkLibrary()
        lib.add(url: "https://www.youtube.com", title: "Mine", now: t0)
        let r = lib.merge(NetscapeBookmarks.parse(Self.chromeExport), now: t0)
        #expect(r == .init(bookmarks: 3, folders: 2), "YouTube was bookmarked already")
        let bar = lib.folders.first { $0.title == "Bookmarks bar" }
        let reading = lib.folders.first { $0.title == "Reading & Notes" }
        #expect(bar != nil && reading?.parentId == bar?.id)
        #expect(lib.bookmarks.filter { $0.folderId == reading?.id }.count == 2)
        let again = lib.merge(NetscapeBookmarks.parse(Self.chromeExport), now: t0)
        #expect(again == .init(), "the same file twice adds nothing")
    }

    @Test func chromiumsBookmarksComeInOnceAndStayDeleted() {
        var lib = BookmarkLibrary()
        let tree = ChromiumBookmarks.parse(Data(Self.chromiumFile.utf8))
        #expect(lib.merge(tree, now: t0) == .init(bookmarks: 3, folders: 2))
        let gh = lib.bookmarks.first { $0.url == "https://github.com/" }!
        lib.remove(gh.id)
        let dev = lib.folders.first { $0.title == "Dev" }!
        lib.removeFolder(dev.id)
        #expect(lib.merge(tree, now: t0) == .init(), "deleted here, not brought back by the next read")
        #expect(lib.folder(dev.id) == nil && !lib.isBookmarked("https://github.com/"))
        let grown = Self.chromiumFile.replacingOccurrences(of: #"{"guid":"g-gh","name":"GitHub","type":"url","url":"https://github.com/"}"#,
            with: #"{"guid":"g-gh","name":"GitHub","type":"url","url":"https://github.com/"},{"guid":"g-new","name":"New","type":"url","url":"https://new.test/"}"#)
        let r = lib.merge(ChromiumBookmarks.parse(Data(grown.utf8)), now: t0)
        #expect(r.bookmarks == 1 && lib.isBookmarked("https://new.test/"), "only what is new comes in")
        let enc = JSONEncoder(), dec = JSONDecoder()
        #expect(try! dec.decode(BookmarkLibrary.self, from: enc.encode(lib)).importedIDs == lib.importedIDs)
    }
}
