import CraCore
import Testing

/// 11 Nov 2026: tips in the space's light or dark, and the background-loading arc on tab rows.
struct TooltipAndLoadingTests {
    @Test func lightSpacesGetALightTip() {
        let pastel = SpaceThemeVariants.theme(key: ["#DCF3FC"], intensity: 0.8, noise: 0, appearance: "light")
        let tip = TooltipTones.forSpace(pastel)
        #expect(tip.light, "not the dark #0A1318 capsule over a light sidebar")
        func lum(_ c: RGB) -> Double { 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
        #expect(lum(tip.fill) > 0.9 && lum(tip.title) < 0.15, "a pale fill, near-black text")
        #expect(tip.edgeAlpha > 0 && tip.edgeAlpha < 0.2, "a fine dark hairline")
        let dark = SpaceThemeVariants.theme(key: ["#2861B3"], intensity: 0.8, noise: 0, appearance: "dark")
        #expect(TooltipTones.forSpace(dark) == TooltipTones(theme: dark), "a dark space keeps Arc's palette slots (#152)")
        #expect(!TooltipTones.forSpace(dark).light)
    }

    @Test func loadingArcOnlyOffScreen() {
        #expect(TabLoadingIndicator.shows(loading: true, onScreen: false, unloaded: false), "a link opened in the background")
        #expect(!TabLoadingIndicator.shows(loading: true, onScreen: true, unloaded: false), "on screen: the window's loading bar")
        #expect(!TabLoadingIndicator.shows(loading: false, onScreen: false, unloaded: false))
        #expect(!TabLoadingIndicator.shows(loading: true, onScreen: false, unloaded: true), "unloaded: its dashed ring")
        #expect(TabLoadingIndicator.faviconAlpha < 1)
        // A 270° sweep in 1.5 pt, its tail fading toward the end (11 Nov 2026).
        #expect(TabLoadingIndicator.arcLength == 0.75 && TabLoadingIndicator.stroke == 1.5)
        let n = TabLoadingIndicator.tailSegments
        let first = TabLoadingIndicator.segment(0), last = TabLoadingIndicator.segment(n - 1)
        #expect(first.start == 0 && abs(last.end - 0.75) < 1e-9, "the segments cover the 270° exactly")
        #expect(first.opacity < 0.05 && last.opacity == 1, "faint at the tail, solid at the head")
        #expect((0..<n - 1).allSatisfy { TabLoadingIndicator.segment($0).opacity < TabLoadingIndicator.segment($0 + 1).opacity })
    }
}
