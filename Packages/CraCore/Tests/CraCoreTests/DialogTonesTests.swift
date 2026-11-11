import CraCore
import Testing

/// Dialogs take the space's colours (11 Nov 2026): no navy card over a light pastel space.
struct DialogTonesTests {
    @Test func lightSpaceGetsALightTintedCardWithDarkText() {
        let t = DialogTones(base: "#DCF3FC", dark: false)
        #expect(!t.dark)
        #expect(DialogTones.luminance(t.card) > 0.8, "a light card")
        #expect(DialogTones.luminance(t.title) < 0.15, "dark text")
        #expect(t.card.alpha < 1, "frosted: the desktop shows a little through it")
        let c = HexColor.components(t.card.hex)!
        #expect(c.b > c.r, "the space's blue, not plain white")
    }

    @Test func darkSpaceGetsItsOwnDarkToneNotFlatBlack() {
        let t = DialogTones(base: "#8389FF", dark: true)
        #expect(DialogTones.luminance(t.card) < 0.05, "dark")
        let c = HexColor.components(t.card.hex)!
        #expect(c.b > c.r + 0.03, "tinted with the space's colour")
        #expect(t.title.hex == "#FFFFFF")
        #expect(DialogTones.luminance(t.secondaryFill) > DialogTones.luminance(t.card), "the buttons stand off the card")
    }

    @Test func baseColourOfASpace() {
        let pastel = SpaceColorPresets.pastelTheme(index: 7)
        #expect(DialogTones.base(of: pastel) == pastel.key?.first)
        let painted = SpaceColorPresets.newSpaceTheme().paintingUnthemed(with: "#DCF3FC")
        #expect(DialogTones.base(of: painted) == "#DCF3FC")
        #expect(DialogTones(base: "nonsense", dark: true) == .arc, "an unreadable colour falls back to Arc's navy")
    }
}
