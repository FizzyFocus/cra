import Foundation
import Testing
@testable import CraCore

@Suite struct ThemeOpacityTests {
    private func roundTrip(_ t: SpaceTheme) throws -> SpaceTheme {
        try JSONDecoder().decode(SpaceTheme.self, from: JSONEncoder().encode(t))
    }

    /// A space made see-through stays see-through after a relaunch: the opacity is in sidebar.json.
    @Test func opacityIsSavedWithTheTheme() throws {
        let t = SpaceThemeVariants.theme(key: ["#DCF3FC", "#C5C6E5"], intensity: 0.8, noise: 0, appearance: "light", opacity: 0.45)
        #expect(t.opacity == 0.45)
        let back = try roundTrip(t)
        #expect(back == t && back.opacity == 0.45)
        #expect(ThemeOpacity.alphas(back.resolved(systemDark: false)) == (0.45, 0.45, true))
    }

    /// Both halves of an Auto theme show it, macOS light or dark.
    @Test func autoKeepsItsOpacityInBothModes() throws {
        let t = try roundTrip(SpaceThemeVariants.theme(key: ["#8389FF"], intensity: 0.8, noise: 0, appearance: "auto", opacity: 0.6))
        for dark in [false, true] { #expect(t.resolved(systemDark: dark).opacity == 0.6) }
    }

    /// A theme saved before the slider, or written by hand, keeps its look: no key, or a bad one.
    @Test func olderThemesKeepTheirOwnLook() throws {
        let old = ##"{"colors":["#F25E6B","#F25E6B"],"intensity":1,"noise":0,"appearance":"light","solid":true}"##
        let t = try JSONDecoder().decode(SpaceTheme.self, from: Data(old.utf8))
        #expect(t.opacity == nil)
        #expect(ThemeOpacity.alphas(t).top == ThemeOpacity.solidAlpha(intensity: 1))
        let bad = ##"{"colors":["#F25E6B"],"intensity":1,"noise":0,"appearance":"light","opacity":"half"}"##
        #expect(try JSONDecoder().decode(SpaceTheme.self, from: Data(bad.utf8)).opacity == nil)
        // An opaque theme without the key doesn't gain one when saved again.
        let opaque = SpaceTheme(colors: ["#1C242B", "#3A3660"], intensity: 0.85, noise: 0.18, appearance: "dark")
        #expect(!String(decoding: try JSONEncoder().encode(opaque), as: UTF8.self).contains("opacity"))
    }

    /// The slider runs from nearly clear to a solid window, and lands on opaque near its end.
    @Test func sliderRangeAndOpaqueEnd() {
        #expect(ThemeOpacity.clamped(0) == 0.2)
        #expect(ThemeOpacity.clamped(0.5) == 0.5)
        #expect(ThemeOpacity.clamped(0.98) == 1)
        let opaque = SpaceThemeVariants.theme(key: ["#F25E6B"], intensity: 0.8, noise: 0, appearance: "light", opacity: 1)
        #expect(ThemeOpacity.alphas(opaque) == (1, 1, false), "100 % is a solid window, also for a one-colour fill")
    }

    /// Unset, the slider shows the look's own: opaque for a gradient, Arc's fill for one colour.
    @Test func sliderStartsOnTheLooksOwnOpacity() {
        let gradient = SpaceThemeVariants.theme(key: ["#DCF3FC", "#C5C6E5"], intensity: 0.8, noise: 0, appearance: "light")
        #expect(ThemeOpacity.shown(gradient) == 1)
        let fill = SpaceThemeVariants.theme(key: ["#DCF3FC"], intensity: 0.8, noise: 0, appearance: "light")
        #expect(abs(ThemeOpacity.shown(fill) - ThemeOpacity.solidAlpha(intensity: 0.8)) < 1e-9)
    }
}

@Suite struct ThemePickerSnapTests {
    @Test func theHandleIsDrawnToCardinalHues() {
        let near = ThemePickerSnap.snap(hue: 238, saturation: 0.7, swatches: [])
        #expect(near.hue == 240 && near.saturation == 0.7 && near.target == .hue(240))
        let wrap = ThemePickerSnap.snap(hue: 358, saturation: 0.7, swatches: [])
        #expect(wrap.hue == 0 && wrap.target == .hue(0))
        let free = ThemePickerSnap.snap(hue: 225, saturation: 0.7, swatches: [])
        #expect(free.hue == 225 && free.target == nil)
    }

    @Test func theCentreIsNeutral() {
        let s = ThemePickerSnap.snap(hue: 100, saturation: 0.03, swatches: [])
        #expect(s.saturation == 0 && s.target == .neutral)
        // Near the centre a hue isn't worth drawing to.
        #expect(ThemePickerSnap.snap(hue: 119, saturation: 0.08, swatches: []).target == nil)
    }

    @Test func pastelSwatchesPullTheHandleOntoThem() {
        let sky = SpaceColorWheel.hsb("#DCF3FC")
        let s = ThemePickerSnap.snap(hue: sky.hue + 2, saturation: sky.saturation + 0.01)
        #expect(s.target == .swatch("#DCF3FC"))
        #expect(s.hue == sky.hue && s.saturation == sky.saturation)
    }

    @Test func slidersTickEveryTenth() {
        #expect(ThemePickerSnap.crossesDetent(from: 0.48, to: 0.52))
        #expect(!ThemePickerSnap.crossesDetent(from: 0.51, to: 0.55))
        #expect(ThemePickerSnap.crossesDetent(from: 0.55, to: 0.5), "landing on one")
        #expect(ThemePickerSnap.crossesDetent(from: 0.62, to: 0.38))
        #expect(!ThemePickerSnap.crossesDetent(from: 0.3, to: 0.3))
    }
}

@Suite struct ThemePickerPlacementTests {
    @Test func theArrowPointsAtTheSource() {
        let p = ThemePickerPlacement.place(sourceY: 500, cardHeight: 300, windowMinY: 0, windowMaxY: 1000)
        #expect(p.top == 650 && p.arrowY == 150)
    }

    /// Near the window's top or bottom the card stays inside; the arrow moves along its edge.
    @Test func theCardStaysInTheWindow() {
        let top = ThemePickerPlacement.place(sourceY: 980, cardHeight: 300, windowMinY: 0, windowMaxY: 1000)
        #expect(top.top == 994 && top.arrowY == ThemePickerPlacement.arrowInset)
        let bottom = ThemePickerPlacement.place(sourceY: 40, cardHeight: 300, windowMinY: 0, windowMaxY: 1000)
        #expect(bottom.top == 306 && bottom.arrowY == 300 - ThemePickerPlacement.arrowInset, "clear of the corner")
    }
}

@Suite struct CardReorderTests {
    @Test func theSlotFollowsTheDraggedCardsCentre() {
        #expect(CardReorder.slot(from: 1, offset: 0, pitch: 264, count: 4) == 1)
        #expect(CardReorder.slot(from: 1, offset: 140, pitch: 264, count: 4) == 2)
        #expect(CardReorder.slot(from: 1, offset: -400, pitch: 264, count: 4) == 0)
        #expect(CardReorder.slot(from: 1, offset: 5000, pitch: 264, count: 4) == 3)
    }

    @Test func theOthersMakeRoom() {
        #expect(CardReorder.order(["a", "b", "c", "d"], moving: 0, to: 2) == ["b", "c", "a", "d"])
        #expect(CardReorder.order(["a", "b", "c", "d"], moving: 3, to: 0) == ["d", "a", "b", "c"])
        #expect(CardReorder.order(["a"], moving: 2, to: 0) == ["a"])
    }
}

@Suite struct PopoverOutSpringTests {
    /// The picker shrinks back without bouncing past its arrow.
    @Test func closingNeverOvershoots() {
        let s = SpringMotion.popoverOut
        for t in stride(from: 0.0, through: 0.5, by: 0.01) { #expect(s.offset(at: t) >= 0) }
        #expect(s.offset(at: 0.25) < 0.01)
    }
}
