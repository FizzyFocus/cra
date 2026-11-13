import Testing
@testable import CraCore

/// Zap keeps each click at once, with a selector that finds the element again (13 Nov 2026).
struct BoostZapTests {
    @Test func aTakeHandsOverStringsOnce() {
        #expect(BoostZap.selectors(##"["#a","div > span:nth-of-type(2)","#a"," ",3]"##) == ["#a", "div > span:nth-of-type(2)"])
        #expect(BoostZap.selectors("[]").isEmpty && BoostZap.selectors("nonsense").isEmpty)
    }

    @Test func theScriptKeepsEachClickAndMarksWhatItHid() {
        let s = BoostZap.script
        #expect(s.contains(BoostPicker.selectorHelpers), "the picker's unique selector, from an id or the body at any depth")
        #expect(!s.contains("p.length<5"), "not cut off five levels up (a deeper element's selector never matched again)")
        #expect(s.contains("take()") && s.contains("data-cra-zapped") && s.contains("data-cra-zap-pending"))
        #expect(BoostZap.takeExpression.contains("take()") && BoostZap.stopExpression.contains("stop()"))
        // A zap taken back shows the element again on the page it was zapped on.
        #expect(BoostScript.runtime.contains("[data-cra-zapped]:not([data-cra-zap-pending])"))
    }

    /// Restore acts on the page at once (13 Nov 2026): the rule out of every Boost sheet, what it hid
    /// shown again whichever script hid it, and no more hiding of it as elements come.
    @Test func restoreActsOnThePageAtOnce() {
        let js = BoostScript.unzap(["#a", "div.b"])
        #expect(js.hasPrefix(BoostScript.runtime) && js.hasSuffix(##"(...[["#a","div.b"]]);"##))
        #expect(js.contains("deleteRule") && js.contains("data-cra-boost-hidden") && js.contains("__craBoostForget(sels)"))
        #expect(BoostScript.runtime.contains("setAttribute('data-cra-boost-hidden'"), "what the runtime hides is marked in the page")
    }
}

/// The zap list names elements as a person sees them (13 Nov 2026).
struct ZapFactsTests {
    @Test func namesComeFromTheElement() {
        #expect(ZapFacts(selector: "x", count: 1, tag: "div", aria: "  Site   notice ").label == "Site notice", "its accessibility label first")
        #expect(ZapFacts(selector: "x", count: 1, tag: "div", classes: "promo-card shadow").label == "Promo Card")
        #expect(ZapFacts(selector: "x", count: 1, tag: "div", id: "header-banner").label == "Header Banner")
        #expect(ZapFacts(selector: "x", count: 1, tag: "div", classes: "cookie-consent").label == "Cookie Notice")
        #expect(ZapFacts(selector: "x", count: 3, tag: "aside", classes: "sidebar").label == "Sidebar ×3")
        #expect(ZapFacts(selector: "x", count: 1, tag: "nav").label == "Navigation", "a landmark by its tag")
        #expect(ZapFacts(selector: "x", count: 1, tag: "div", role: "complementary").label == "Sidebar", "or its role")
        #expect(ZapFacts(selector: "x", count: 1, tag: "img", alt: "Summer sale").label == "Image “Summer sale”")
        #expect(ZapFacts(selector: "x", count: 1, tag: "section", heading: "Trending now", text: "Trending now 1 2 3").label == "“Trending now”")
        #expect(ZapFacts(selector: "x", count: 1, tag: "span", text: "Deep").label == "Text “Deep”")
        #expect(ZapFacts(selector: "x", count: 1, tag: "div").label == "Block")
    }

    @Test func sizeAndDetail() {
        let f = ZapFacts(selector: "x", count: 1, tag: "aside", w: 300, h: 250)
        #expect(f.size == "300 × 250" && f.detail == "aside · 300 × 250")
        #expect(ZapFacts(selector: "x", count: 1, tag: "div", w: 0, h: 0).size == nil)
        #expect(ZapFacts(selector: "x", count: 0).detail == "Not on this page")
    }
}
