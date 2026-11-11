import Foundation
import Testing
@testable import CraCore

/// Settings ▸ Search Engines: the user's own site searches, and the pill's colour from a site's icon.
struct SiteSearchCustomTests {
    static let yummy = CustomSiteSearch(name: "YummyAni", shortcut: "ya", url: "https://yummyani.me/search?word=%s", color: nil)

    /// A built-in site taken off the list in Settings (11 Nov 2026): Tab no longer offers it, and the
    /// next site that matches comes up instead; the user's own copy of it still does.
    @Test func hiddenSitesAreNotOffered() {
        #expect(SiteSearch.match("you", completion: nil)?.name == "YouTube")
        #expect(SiteSearch.match("you", completion: nil, hidden: ["youtube.com"])?.name != "YouTube")
        let mine = CustomSiteSearch(name: "My YouTube", shortcut: "yt", url: "https://youtube.com/results?q=%s")
        #expect(SiteSearch.match("yt", completion: nil, custom: [mine], hidden: ["youtube.com"])?.name == "My YouTube")
        let keyword = ChromiumSearchEngine(name: "Wiki", keyword: "wiki", url: "https://en.wikipedia.org/w/index.php?search={searchTerms}")
        #expect(SiteSearch.match("wiki", completion: nil, keywords: [keyword])?.name == "Wiki")
        #expect(SiteSearch.match("wiki", completion: nil, keywords: [keyword], hidden: ["wiki"])?.name != "Wiki", "Arc's Wikipedia may answer, not the hidden keyword")
    }

    @Test func aShortcutTypedOutWinsAndAStartedOneComesAfterArcsSites() {
        let custom = [Self.yummy, CustomSiteSearch(name: "Wiki DE", shortcut: "wde", url: "https://de.wikipedia.org/w/index.php?search=%s")]
        #expect(SiteSearch.match("ya", completion: nil, custom: custom)?.name == "YummyAni")
        #expect(SiteSearch.match("yo", completion: nil, custom: custom)?.name == "YouTube", "Arc's sites keep their prefixes")
        #expect(SiteSearch.match("wd", completion: nil, custom: custom)?.name == "Wiki DE")
        #expect(SiteSearch.match("w", completion: nil, custom: custom)?.name == "Wikipedia", "one letter goes to Arc's list")
        #expect(SiteSearch.match("ya kimetsu", completion: nil, custom: custom) == nil, "a query with a space is a search, not a scope")
        let s = SiteSearch(Self.yummy)
        #expect(s.searchURL("one piece") == "https://yummyani.me/search?word=one%20piece")
        #expect(Self.yummy.host == "yummyani.me")
    }

    @Test func theAddSheetSaysWhatIsMissing() {
        let ok = CustomSiteSearch.problem(name: "Y", shortcut: "ya", url: "https://y.test/?q=%s", taken: [])
        #expect(ok == nil)
        #expect(CustomSiteSearch.problem(name: "", shortcut: "ya", url: "https://y.test/?q=%s", taken: []) != nil)
        #expect(CustomSiteSearch.problem(name: "Y", shortcut: "y a", url: "https://y.test/?q=%s", taken: []) != nil)
        #expect(CustomSiteSearch.problem(name: "Y", shortcut: "ya", url: "https://y.test/", taken: []) != nil, "no %s")
        #expect(CustomSiteSearch.problem(name: "Y", shortcut: "ya", url: "ftp://y.test/%s", taken: []) != nil)
        #expect(CustomSiteSearch.problem(name: "Y", shortcut: "YA", url: "https://y.test/?q=%s", taken: ["ya"]) != nil)
    }

    private func pixels(_ colors: [(UInt8, UInt8, UInt8, UInt8)]) -> [UInt8] { colors.flatMap { [$0.0, $0.1, $0.2, $0.3] } }

    @Test func theIconsMostCommonVividHueIsThePillsColour() {
        // 6 red, 3 blue, 4 white, 3 black, 2 transparent.
        let px = Array(repeating: (230, 20, 20, 255), count: 6) + Array(repeating: (20, 40, 220, 255), count: 3)
            + Array(repeating: (255, 255, 255, 255), count: 4) + Array(repeating: (0, 0, 0, 255), count: 3)
            + Array(repeating: (255, 0, 0, 0), count: 2)
        let hex = FaviconColor.dominant(rgba: pixels(px.map { (UInt8($0.0), UInt8($0.1), UInt8($0.2), UInt8($0.3)) }), width: 6, height: 3)
        #expect(hex == "#E61414")
        let grey = Array(repeating: (UInt8(128), UInt8(128), UInt8(128), UInt8(255)), count: 4) + Array(repeating: (UInt8(255), UInt8(255), UInt8(255), UInt8(255)), count: 5)
        #expect(FaviconColor.dominant(rgba: pixels(grey), width: 3, height: 3) == nil, "a grey logo has no colour to give")
        #expect(FaviconColor.dominant(rgba: [], width: 0, height: 0) == nil)
    }

    @Test func settingsKeepSiteSearchesAndColours() throws {
        var s = AppSettings()
        #expect(s.defaultSpaceOpacity == AppSettings.defaultSpaceOpacityDefault && s.hardwareAcceleration)
        s.customSiteSearches = [Self.yummy]
        s.siteSearchColors = ["youtube.com": "#123456"]
        s.hardwareAcceleration = false
        s.defaultSpaceOpacity = 0.6
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.customSiteSearches == [Self.yummy] && back.siteSearchColors == ["youtube.com": "#123456"])
        #expect(!back.hardwareAcceleration && back.defaultSpaceOpacity == 0.6)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(old.customSiteSearches.isEmpty && old.hardwareAcceleration && old.defaultSpaceOpacity == AppSettings.defaultSpaceOpacityDefault)
    }

    @Test func newSpacesStartALittleSeeThrough() {
        let t = SpaceColorPresets.newSpaceTheme()
        #expect(t.opacity == AppSettings.defaultSpaceOpacityDefault)
        #expect(ThemeOpacity.alphas(t).seeThrough)
        #expect(SpaceColorPresets.newSpaceTheme(opacity: 1).opacity == 1)
    }
}
