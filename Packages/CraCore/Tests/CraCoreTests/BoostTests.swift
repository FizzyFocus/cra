import CraCore
import Testing

/// Arc's Boosts (Arc 1.172.1): per-site restyles from the editor's controls.
struct BoostTests {
    @Test func aNewBoostChangesNothing() {
        let b = Boost(host: "www.Example.com")
        #expect(b.host == "example.com" && b.name == "My Boost" && b.enabled)
        #expect(b.colorsUntouched && b.stylesheet.isEmpty)
    }

    @Test func appliesToItsSiteAndSubdomains() {
        let b = Boost(host: "example.com")
        var off = Boost(host: "other.org"); off.enabled = false
        #expect(Boost.applying(to: "https://www.example.com/a", from: [b, off]).map(\.id) == [b.id])
        #expect(Boost.applying(to: "https://docs.example.com/", from: [b]).count == 1)
        #expect(Boost.applying(to: "https://notexample.com/", from: [b]).isEmpty)
        #expect(Boost.applying(to: "https://other.org/", from: [off]).isEmpty, "a disabled boost does nothing")
    }

    @Test func eachControlWritesItsRule() {
        var b = Boost(host: "example.com")
        b.invert = true
        b.contrast = 75
        b.font = 2
        b.textCase = .upper
        b.zapped = [".ad", "#banner"]
        b.css = "h1 { color: red }"
        let css = b.stylesheet
        #expect(css.contains("invert(1) hue-rotate(180deg)") && css.contains("contrast(1.5)"))
        #expect(css.contains("img, video") , "pictures are flipped back under an inverted page")
        #expect(css.contains("\"ui-serif\"") && css.contains("uppercase"))
        #expect(css.contains(".ad { display: none !important; }\n#banner { display: none !important; }") && css.hasSuffix("h1 { color: red }"))
    }

    /// A zap the page's CSS can't parse used to drop every other zap with it: one list, one rule
    /// (13 Nov 2026). Now each is its own rule.
    @Test func aBadZapDoesntUndoTheOthers() {
        var b = Boost(host: "example.com")
        b.zapped = ["#banner", "div:has-unknown((", "  ", ".late"]
        let rules = b.stylesheet.split(separator: "\n")
        #expect(rules == ["#banner { display: none !important; }", "div:has-unknown(( { display: none !important; }", ".late { display: none !important; }"])
    }

    /// Every page starts with its boosts on (BoostScript): the start script carries each enabled
    /// boost; none at all without one.
    @Test func theStartScriptCarriesTheEnabledBoosts() throws {
        var a = Boost(host: "example.com")
        a.zapped = ["#banner"]
        var off = Boost(host: "other.org")
        off.enabled = false
        off.zapped = [".x"]
        #expect(BoostScript.documentStart([off]).isEmpty, "no enabled boost: pages run nothing")
        let start = BoostScript.documentStart([a, off])
        #expect(start.hasPrefix(BoostScript.runtime))
        #expect(start.contains("\"host\":\"example.com\"") && !start.contains("other.org"))
        #expect(start.contains("window.top !== window"), "the top frame only, as a commit applies it")
        #expect(BoostScript.entries([a, off]) == [BoostScript.Entry(host: "example.com", css: a.stylesheet, zapped: ["#banner"])])
        let apply = BoostScript.apply(css: "p{}", zapped: ["#a\"b"])
        #expect(apply.hasSuffix(##"window.__craBoostRun(...["p{}",["#a\"b"]]);"##))
        // The runtime watches for elements as they come, and puts the sheet back if the page drops it.
        #expect(BoostScript.runtime.contains("MutationObserver") && BoostScript.runtime.contains("adoptedStyleSheets.includes"))
        #expect(BoostScript.runtime.contains("DOMContentLoaded"))
    }

    /// Several boosts for one site (13 Nov 2026): each new one is named apart, and all of them that are
    /// on apply, in the order they were made.
    @Test func aSiteHasSeveralBoosts() {
        #expect(Boost.nextName(taken: []) == "My Boost")
        #expect(Boost.nextName(taken: ["My Boost"]) == "My Boost 2")
        #expect(Boost.nextName(taken: ["My Boost", "My Boost 2", "Reading"]) == "My Boost 3")
        #expect(Boost.nextName(taken: ["My Boost 2"]) == "My Boost")
        var a = Boost(host: "example.com"), b = Boost(host: "example.com", name: "My Boost 2")
        a.css = "a{}"; b.css = "b{}"
        var off = Boost(host: "example.com", name: "Off")
        off.enabled = false
        #expect(Boost.applying(to: "https://example.com/x", from: [a, off, b]).map(\.name) == ["My Boost", "My Boost 2"])
        let start = BoostScript.documentStart([a, off, b])
        #expect(start.contains("a{}") && start.contains("b{}") && start.range(of: "a{}")!.lowerBound < start.range(of: "b{}")!.lowerBound)
    }

    /// Size and Case say what they are set to (13 Nov 2026).
    @Test func sizeAndCaseNameTheirSetting() {
        #expect(Boost.sizeTitle(1) == "Size" && Boost.sizeTitle(1.1) == "110%" && Boost.sizeTitle(1.25) == "125%" && Boost.sizeTitle(0.9) == "90%")
        #expect(Boost.TextCase.none.buttonTitle == "Case" && Boost.TextCase.upper.buttonTitle == "CASE"
                && Boost.TextCase.lower.buttonTitle == "case" && Boost.TextCase.capitalize.buttonTitle == "Case")
    }

    @Test func aTintNeedsStrength() {
        var b = Boost(host: "example.com")
        b.hue = 0.5
        #expect(b.stylesheet.isEmpty, "a hue alone, with the handle in the middle, tints nothing")
        b.strength = 0.6
        #expect(b.stylesheet.contains("sepia(0.6)"))
    }

    @Test func twentyFontsFiveToARow() {
        #expect(Boost.fonts.count == 20 && Set(Boost.fonts).count == 20)
    }
}

/// Arc's Boost editor motion, from 60 fps recordings of Arc 1.172.1.
struct BoostEditorMotionTests {
    @Test func opensByGrowingFromItsRightEdge() {
        #expect(BoostEditorMotion.openScale == 0.85 && BoostEditorMotion.openDuration == 0.28)
        #expect(BoostEditorMotion.openAnchor.x == 1 && BoostEditorMotion.openAnchor.y == 0.5)
    }

    @Test func codeWidensSlowlyAndBackNarrowsQuickly() {
        #expect(BoostEditorMotion.resizeDuration(fromWidth: 183, to: 480) == 0.35)
        #expect(BoostEditorMotion.resizeDuration(fromWidth: 480, to: 183) == 0.13)
        #expect(BoostEditorMotion.resizeDuration(fromWidth: 183, to: 183) == 0)
    }
}
