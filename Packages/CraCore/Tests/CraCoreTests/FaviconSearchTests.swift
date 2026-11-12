import CraCore
import Testing

/// How a tab finds its icon when what the page declares doesn't decode (my.eskiz.uz, Nov 2026:
/// its `<link rel=icon href=favicon.png>` answered with the app's index.html, and the tab kept
/// the globe).
struct FaviconSearchTests {
    typealias Attempt = FaviconSearch.Attempt
    static let page = "https://my.eskiz.uz/dashboard"

    /// Runs the search, failing every attempt except those whose URL is in `decodes`; returns
    /// the attempts made, in order, as "fetch url".
    static func run(_ search: inout FaviconSearch, from first: Attempt?, decodes: Set<String> = []) -> [String] {
        var made: [String] = []
        var next = first
        while let a = next {
            made.append("\(a.fetch.rawValue) \(a.url)")
            next = search.finished(a, decoded: decodes.contains(a.url))
        }
        return made
    }

    @Test func aDeclaredIconThatIsntAnImageFallsBackToFaviconIco() {
        var s = FaviconSearch()
        let first = s.iconsChanged(["https://my.eskiz.uz/favicon.png"], pageURL: Self.page)
        let made = Self.run(&s, from: first, decodes: ["https://my.eskiz.uz/favicon.ico"])
        #expect(made == [
            "renderer https://my.eskiz.uz/favicon.png",
            "session https://my.eskiz.uz/favicon.ico",
        ])
        #expect(s.found == "https://my.eskiz.uz/favicon.ico")
    }

    @Test func theFirstIconThatDecodesWinsAndTheRestArentFetched() {
        var s = FaviconSearch()
        let first = s.iconsChanged(["https://a.com/broken.png", "https://a.com/good.png", "https://a.com/other.png"], pageURL: "https://a.com/")
        let made = Self.run(&s, from: first, decodes: ["https://a.com/good.png", "https://a.com/other.png"])
        #expect(made == ["renderer https://a.com/broken.png", "renderer https://a.com/good.png"])
        #expect(s.found == "https://a.com/good.png")
        #expect(s.current == nil)
    }

    @Test func bitmapsGoBeforeSVGAndAnSVGTheRendererCantReadIsFetchedForTheApp() {
        var s = FaviconSearch()
        let first = s.iconsChanged(["https://a.com/icon.svg", "https://a.com/i.png"], pageURL: "https://a.com/x")
        let made = Self.run(&s, from: first)
        #expect(made == [
            "renderer https://a.com/i.png",
            "renderer https://a.com/icon.svg",
            "session https://a.com/icon.svg",
            "session https://a.com/favicon.ico",
            "session https://a.com/i.png",
        ])
        #expect(s.found == nil)
    }

    @Test func anSVGOnlyPageGetsItsSVGFromTheSessionBeforeFaviconIco() {
        // The renderer can't read it; the app reads the session's copy.
        var s = FaviconSearch()
        var made: [String] = []
        var next = s.iconsChanged(["https://a.com/logo.svg?v=2"], pageURL: "https://a.com/")
        while let a = next {
            made.append("\(a.fetch.rawValue) \(a.url)")
            next = s.finished(a, decoded: a.fetch == .session)
        }
        #expect(made == ["renderer https://a.com/logo.svg?v=2", "session https://a.com/logo.svg?v=2"])
        #expect(s.found == "https://a.com/logo.svg?v=2")
    }

    @Test func aDataIconIsReadOnceUnlessItIsAnSVG() {
        var s = FaviconSearch()
        let png = "data:image/png;base64,AAAA", svg = "data:image/svg+xml,%3Csvg%3E%3C/svg%3E"
        let made = Self.run(&s, from: s.iconsChanged([png, svg], pageURL: "https://gitlab.com/p"))
        #expect(made == [
            "renderer \(png)", "renderer \(svg)",
            "session \(svg)", "session https://gitlab.com/favicon.ico",
        ])
    }

    @Test func chromiumsOwnFaviconIcoIsTriedOnceEachWay() {
        var s = FaviconSearch()
        let made = Self.run(&s, from: s.iconsChanged(["https://a.com/favicon.ico"], pageURL: "https://a.com/")
        )
        #expect(made == ["renderer https://a.com/favicon.ico", "session https://a.com/favicon.ico"])
    }

    // MARK: Load end

    @Test func withNoIconYetTheLoadedPagesDeclaredIconsAreTried() {
        var s = FaviconSearch()
        _ = Self.run(&s, from: s.iconsChanged(["https://a.com/favicon.ico"], pageURL: "https://a.com/"))
        let icons = [FaviconSearch.PageIcon(href: "https://a.com/touch.png", rel: "apple-touch-icon"),
                     FaviconSearch.PageIcon(href: "https://a.com/mask.svg", rel: "mask-icon"),
                     FaviconSearch.PageIcon(href: "https://a.com/old.png", rel: "apple-touch-icon-precomposed"),
                     FaviconSearch.PageIcon(href: "https://a.com/fav.png", rel: "Shortcut Icon")]
        let made = Self.run(&s, from: s.pageLoaded(declared: icons, pageURL: "https://a.com/"), decodes: ["https://a.com/touch.png"])
        // rel~=icon first, then the touch icons; Safari's mask-icon isn't one, favicon.ico was tried.
        #expect(made == [
            "renderer https://a.com/fav.png", "renderer https://a.com/touch.png",
        ])
        #expect(s.found == "https://a.com/touch.png")
    }

    @Test func aPageChromiumSentNoListForStartsAtLoadEndWithFaviconIco() {
        var s = FaviconSearch()
        let made = Self.run(&s, from: s.pageLoaded(declared: [], pageURL: "https://b.org/a?x=1#f"))
        #expect(made == ["session https://b.org/favicon.ico"])
    }

    @Test func loadEndChangesNothingOnceAnIconDecodedForTheSite() {
        var s = FaviconSearch()
        _ = Self.run(&s, from: s.iconsChanged(["https://a.com/i.png"], pageURL: "https://a.com/"), decodes: ["https://a.com/i.png"])
        #expect(s.pageLoaded(declared: [.init(href: "https://a.com/t.png", rel: "icon")], pageURL: "https://a.com/next") == nil)
        #expect(s.found == "https://a.com/i.png")
    }

    @Test func loadEndQueuesItsIconsBehindASearchStillRunning() {
        var s = FaviconSearch()
        let first = s.iconsChanged(["https://a.com/slow.png"], pageURL: "https://a.com/")
        #expect(s.pageLoaded(declared: [.init(href: "https://a.com/dom.png", rel: "icon")], pageURL: "https://a.com/") == nil)
        let made = Self.run(&s, from: first, decodes: ["https://a.com/dom.png"])
        #expect(made == [
            "renderer https://a.com/slow.png",
            "session https://a.com/favicon.ico",
            "session https://a.com/slow.png",
            "renderer https://a.com/dom.png",
        ])
    }

    @Test func aListThatComesAfterTheLoadKeepsThePagesIcons() {
        var s = FaviconSearch()
        let dom = s.pageLoaded(declared: [.init(href: "https://a.com/touch.png", rel: "apple-touch-icon")], pageURL: "https://a.com/")
        #expect(dom?.url == "https://a.com/touch.png")
        // Chromium's list lands while that runs: a new search, the page's icon still in it.
        let made = Self.run(&s, from: s.iconsChanged(["https://a.com/favicon.ico"], pageURL: "https://a.com/"), decodes: ["https://a.com/touch.png"])
        #expect(made == [
            "renderer https://a.com/favicon.ico", "session https://a.com/favicon.ico", "renderer https://a.com/touch.png",
        ])
        #expect(s.found == "https://a.com/touch.png")
        // Another site's list doesn't carry them over.
        var t = FaviconSearch()
        _ = Self.run(&t, from: t.pageLoaded(declared: [.init(href: "https://a.com/touch.png", rel: "apple-touch-icon")], pageURL: "https://a.com/"))
        #expect(Self.run(&t, from: t.iconsChanged(["https://b.com/favicon.ico"], pageURL: "https://b.com/"))
                == ["renderer https://b.com/favicon.ico", "session https://b.com/favicon.ico"])
    }

    @Test func loadEndOfAnotherSiteStartsOver() {
        var s = FaviconSearch()
        _ = Self.run(&s, from: s.iconsChanged(["https://a.com/i.png"], pageURL: "https://a.com/"), decodes: ["https://a.com/i.png"])
        let made = Self.run(&s, from: s.pageLoaded(declared: [], pageURL: "https://b.com/"))
        #expect(made == ["session https://b.com/favicon.ico"])
        #expect(s.found == nil)
    }

    @Test func pagesThatArentOnTheWebGetNoFallback() {
        var s = FaviconSearch()
        #expect(s.pageLoaded(declared: [.init(href: "file:///x.png", rel: "icon")], pageURL: "file:///tmp/a.html") == nil)
        #expect(s.pageLoaded(declared: [], pageURL: "chrome://history") == nil)
        #expect(s.iconsChanged(["javascript:alert(1)", "chrome://theme/x"], pageURL: "https://a.com/") == nil)
    }

    // MARK: Changes and stale answers

    @Test func theSameListForTheSameSiteIsntSearchedAgainOnceSettled() {
        var s = FaviconSearch()
        _ = Self.run(&s, from: s.iconsChanged(["https://a.com/i.png"], pageURL: "https://a.com/1"), decodes: ["https://a.com/i.png"])
        #expect(s.iconsChanged(["https://a.com/i.png"], pageURL: "https://a.com/2") == nil)
        // Every candidate failed: the next page on the site doesn't fetch them all again.
        var f = FaviconSearch()
        _ = Self.run(&f, from: f.iconsChanged(["https://my.eskiz.uz/favicon.png"], pageURL: Self.page))
        #expect(f.iconsChanged(["https://my.eskiz.uz/favicon.png"], pageURL: "https://my.eskiz.uz/cart") == nil)
        // On another site the same list is a new search.
        #expect(f.iconsChanged(["https://my.eskiz.uz/favicon.png"], pageURL: "https://eskiz.uz/") != nil)
    }

    @Test func theSameListWhileADownloadNeverAnsweredRetriesIt() {
        var s = FaviconSearch()
        let lost = s.iconsChanged(["https://www.youtube.com/s/favicon.ico"], pageURL: "https://www.youtube.com/")
        let retry = s.iconsChanged(["https://www.youtube.com/s/favicon.ico"], pageURL: "https://www.youtube.com/")
        #expect(retry?.url == lost?.url)
        #expect(retry?.round != lost?.round)
        // The lost one answering late changes nothing; the retry's answer counts.
        #expect(s.finished(lost!, decoded: true) == nil)
        #expect(s.found == nil)
        _ = s.finished(retry!, decoded: true)
        #expect(s.found == "https://www.youtube.com/s/favicon.ico")
    }

    @Test func aNewListOnTheSamePageIsANewSearch() {
        var s = FaviconSearch()
        _ = Self.run(&s, from: s.iconsChanged(["https://mail.a.com/unread-1.png"], pageURL: "https://mail.a.com/"), decodes: ["https://mail.a.com/unread-1.png"])
        let next = s.iconsChanged(["https://mail.a.com/unread-2.png"], pageURL: "https://mail.a.com/")
        #expect(next?.url == "https://mail.a.com/unread-2.png")
        #expect(s.found == nil)
    }

    @Test func anAnswerCountsOnce() {
        var s = FaviconSearch()
        let a = s.iconsChanged(["https://a.com/1.png", "https://a.com/2.png"], pageURL: "https://a.com/")!
        let b = s.finished(a, decoded: false)
        #expect(b?.url == "https://a.com/2.png")
        #expect(s.finished(a, decoded: false) == nil)
        #expect(s.current == b)
    }

    @Test func aLongListIsCut() {
        var s = FaviconSearch()
        let urls = (0..<40).map { "https://a.com/\($0).png" }
        let made = Self.run(&s, from: s.iconsChanged(urls, pageURL: "https://a.com/"))
        #expect(made.filter { $0.hasPrefix("renderer") }.count == FaviconSearch.maxCandidates)
    }

    // MARK: Helpers

    @Test func anHTMLPageIsNoIcon() {
        #expect(FaviconSearch.accepts(status: 200, mimeType: "image/x-icon"))
        #expect(FaviconSearch.accepts(status: 200, mimeType: ""))
        #expect(!FaviconSearch.accepts(status: 200, mimeType: "text/html; charset=utf-8"))
        #expect(!FaviconSearch.accepts(status: 200, mimeType: "TEXT/HTML"))
        #expect(!FaviconSearch.accepts(status: 404, mimeType: "image/png"))
        #expect(!FaviconSearch.accepts(status: 0, mimeType: ""))
    }

    @Test func theProbesAnswerReads() {
        let json = #"[{"href":"https://a.com/f.png","rel":"icon","sizes":"32x32"},{"href":"https://a.com/t.png","rel":"apple-touch-icon"}]"#
        #expect(FaviconSearch.pageIcons(json: json) == [.init(href: "https://a.com/f.png", rel: "icon"),
                                                         .init(href: "https://a.com/t.png", rel: "apple-touch-icon")])
        #expect(FaviconSearch.pageIcons(json: "nope").isEmpty)
    }

    @Test func faviconIcoSitsAtThePagesOrigin() {
        #expect(FaviconSearch.defaultIcon(of: "https://user:pw@a.com:8443/x/y?q=1#z") == "https://a.com:8443/favicon.ico")
        #expect(FaviconSearch.defaultIcon(of: "http://127.0.0.1:4000/page.html") == "http://127.0.0.1:4000/favicon.ico")
        #expect(FaviconSearch.defaultIcon(of: "file:///a.html") == nil)
    }

    @Test func svgIsToldByPathOrType() {
        #expect(FaviconSearch.isSVG("https://a.com/i.SVG?v=1"))
        #expect(FaviconSearch.isSVG("data:image/svg+xml;base64,AA"))
        #expect(!FaviconSearch.isSVG("https://a.com/svg/icon.png"))
        #expect(!FaviconSearch.isSVG("data:image/png;base64,AA"))
    }
}
