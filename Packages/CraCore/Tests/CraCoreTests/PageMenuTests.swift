@testable import CraCore
import Testing

struct PageMenuTests {
    private func titles(_ c: PageMenu.Context) -> [String] { PageMenu.items(c).map { $0.isSeparator ? "-" : $0.title } }

    @Test func aPlainPageHasNavigationSaveAndInspect() {
        var c = PageMenu.Context()
        c.canGoBack = true
        #expect(titles(c) == ["Back", "Forward", "Reload", "-", "Save As…", "Print…", "-", "View Page Source", "-", "Inspect"])
        let items = PageMenu.items(c)
        #expect(items.first { $0.action == .back }?.enabled == true)
        #expect(items.first { $0.action == .forward }?.enabled == false)
    }

    @Test func aLinkOpensEveryWayAndCopiesItsAddress() {
        var c = PageMenu.Context()
        c.link = "https://example.com/a"
        #expect(titles(c) == ["Open Link in New Tab", "Open Link in New Window", "Open Link in Split View",
                              "Open Link in Little Window", "Open Link in Incognito Window", "-", "Copy Link Address", "-", "Inspect"])
        c.newTabTitle = "Link in neuem Tab öffnen"
        #expect(titles(c).first == "Link in neuem Tab öffnen")
    }

    @Test func peekAndPreviewWhereTheWindowHasThem() {
        var c = PageMenu.Context()
        c.link = "https://example.com/a"
        c.image = "https://example.com/i.png"
        c.canPeek = true
        c.canPreviewImage = true
        let t = titles(c)
        #expect(t.firstIndex(of: "Open Link in Peek")! < t.firstIndex(of: "Copy Link Address")!)
        #expect(t.firstIndex(of: "Open Image in Preview") == t.firstIndex(of: "Open Image in New Tab")! + 1)
        c.incognito = true
        #expect(!titles(c).contains("Open Link in Peek"))
    }

    @Test func incognitoAndLittleWindowsLeaveOutWhatTheyCantOpen() {
        var c = PageMenu.Context()
        c.link = "https://example.com/a"
        c.incognito = true
        #expect(!titles(c).contains("Open Link in Little Window") && !titles(c).contains("Open Link in Incognito Window"))
        c.incognito = false
        c.littleWindow = true
        #expect(!titles(c).contains("Open Link in Split View") && !titles(c).contains("Open Link in Little Window"))
    }

    @Test func anImageInALinkHasBoth() {
        var c = PageMenu.Context()
        c.link = "https://example.com/a"
        c.image = "https://example.com/i.png"
        let t = titles(c)
        #expect(t.contains("Copy Link Address") && t.contains("Copy Image") && t.contains("Copy Image Address") && t.last == "Inspect")
        #expect(!t.contains("Back"))
    }

    @Test func aSelectionCopiesAndSearches() {
        var c = PageMenu.Context()
        c.selection = "a rather long piece of selected text\nover two lines"
        c.searchName = "Kagi"
        #expect(titles(c) == ["Copy", "Search Kagi for “a rather long piece of selected…”", "-", "Inspect"])
    }

    @Test func aFieldEditsAndCopiesOnlyWithASelection() {
        var c = PageMenu.Context()
        c.editable = true
        let items = PageMenu.items(c)
        #expect(items.compactMap(\.action) == [.cut, .copy, .paste, .selectAll, .inspect])
        #expect(items.first { $0.action == .cut }?.enabled == false && items.first { $0.action == .paste }?.enabled == true)
        c.selection = "word"
        #expect(PageMenu.items(c).first { $0.action == .copy }?.enabled == true)
    }

    @Test func aRecordCountsOnlyWhenRecent() {
        let fresh = #"{"rec":{"link":"https://x","image":"","selection":"","editable":false,"x":3,"y":4,"prevented":false,"settled":true,"at":1000},"now":1200}"#
        #expect(PageMenu.record(snapshot: fresh)?.link == "https://x")
        let stale = #"{"rec":{"link":"https://x","image":"","selection":"","editable":false,"x":3,"y":4,"prevented":false,"settled":true,"at":1000},"now":9000}"#
        #expect(PageMenu.record(snapshot: stale) == nil)
        #expect(PageMenu.record(snapshot: #"{"rec":null,"now":5}"#) == nil)
        #expect(PageMenu.record(snapshot: "nonsense") == nil)
    }
}
