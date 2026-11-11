import CraCore
import Testing

/// Settings ▸ Search Engines shows each engine's icon, found from its address (11 Nov 2026), and the
/// favorite preview cards take the sidebar's light or dark (11 Nov 2026).
struct SettingsSearchAndPreviewTests {
    @Test func engineHostsForTheirIcons() {
        #expect(ChromiumSearchEngine.siteHost(of: "{google:baseURL}search?q={searchTerms}&{google:RLZ}") == "www.google.com",
                "Google's template starts with a placeholder: it showed a letter, not Google's icon")
        #expect(ChromiumSearchEngine.siteHost(of: "https://duckduckgo.com/?q={searchTerms}") == "duckduckgo.com")
        #expect(ChromiumSearchEngine.siteHost(of: "https://yummyani.me/search?word=%s") == "yummyani.me")
        #expect(ChromiumSearchEngine.siteHost(of: "not a url") == "")
    }

    @Test func previewCardFollowsTheSidebar() {
        let light = FavoritePreviewTones.forSidebar(dark: false)
        let dark = FavoritePreviewTones.forSidebar(dark: true)
        #expect(light == .light && dark == .dark)
        // A light sidebar gets a light card with dark text, not Arc's black card.
        #expect(light.fill.r > 0.9 && light.text.r < 0.3)
        #expect(dark.fill.r < 0.2 && dark.text.r > 0.9)
        #expect(light.contrast > 0.6 && dark.contrast > 0.6)
    }
}
