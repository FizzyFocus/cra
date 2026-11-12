import Testing
@testable import CraCore

/// The theme editor's presets (#170): Arc's catalog colours on five pages, one colour by default.
struct SpaceColorPresetsTests {
    /// Arc's ColorPicker colours as Arc writes them (sRGB): Brand4 is the CloudDev red, Brand8 is
    /// the 0.4236, 0.7286, 0.8512 Arc saved for a picked swatch.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/170"))
    func catalogColours() {
        for group in [SpaceColorPresets.brand, SpaceColorPresets.drab, SpaceColorPresets.pastel, SpaceColorPresets.greyscale] {
            #expect(group.count == 9 && Set(group).count == 9)
            #expect(group.allSatisfy { HexColor.components($0) != nil })
        }
        #expect(SpaceColorPresets.brand[3] == "#F25E6B")
        #expect(SpaceColorPresets.brand[7] == "#6CBAD9")
        #expect(SpaceColorPresets.greyscale.first == "#FFFFFF" && SpaceColorPresets.greyscale.last == "#000000")
    }

    /// Five pages of nine as in Arc: Brand, Brand pairs, Pastel, Drab, Greyscale.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/170"))
    func pages() {
        #expect(SpaceColorPresets.pages.map(\.group) == ["Brand", "Brand", "Pastel", "Drab", "Greyscale"])
        #expect(SpaceColorPresets.pages.map { $0.seconds != nil } == [false, true, false, false, false])
        for page in SpaceColorPresets.pages {
            #expect(page.swatches.count == 9)
            #expect(page.swatches.allSatisfy { $0.count == (page.seconds == nil ? 1 : 2) })
        }
    }

    /// The editor opens on the page holding the space's colours.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/170"))
    func pageOfAKey() {
        for (i, page) in SpaceColorPresets.pages.enumerated() {
            for swatch in page.swatches { #expect(SpaceColorPresets.page(of: swatch) == i) }
        }
        #expect(SpaceColorPresets.page(of: ["#f25e6b"]) == 0)
        #expect(SpaceColorPresets.page(of: ["#123456"]) == nil)
    }

    /// One colour on Auto follows macOS like every Auto space (#155): the colour, flat, while macOS
    /// is light (a pastel of it when it reads dark) and the colour's hue, dark, while macOS is dark.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/155"), arguments: 0..<9)
    func oneColourOnAutoFollowsMacOS(index: Int) {
        let hex = SpaceColorPresets.brand[index]
        let theme = SpaceThemeVariants.theme(key: [hex], intensity: 0.8, noise: 0, appearance: "auto")
        #expect(theme.key == [hex] && theme.appearance == "auto" && theme.dark != nil)
        let light = theme.resolved(systemDark: false), dark = theme.resolved(systemDark: true)
        #expect(light.solid && light.colors.count == 2 && light.colors[0] == light.colors[1] && !light.isDark)
        #expect(dark.colors.count == 2 && dark.colors[0] == dark.colors[1] && dark.isDark)
    }

    /// A new space starts in Arc's light pastel look, whatever macOS is set to: one Pastel colour,
    /// flat, in Light, light in both of macOS's modes.
    @Test(arguments: 0..<9)
    func newSpaceIsOnePastelColourInLight(index: Int) {
        let hex = SpaceColorPresets.pastel[index]
        let theme = SpaceColorPresets.pastelTheme(index: index)
        #expect(theme.key == [hex] && theme.appearance == "light")
        for systemDark in [false, true] {
            let shown = theme.resolved(systemDark: systemDark)
            #expect(shown.solid && shown.colors == [hex, hex] && !shown.isDark)
        }
    }

    /// With nothing picked a new space is unthemed (no colour on the pad) in Light, never a dark
    /// look; the pad's + brings Pastel's sky blue.
    @Test func newSpaceStartsUnthemed() {
        let theme = SpaceColorPresets.newSpaceTheme()
        #expect((theme.key ?? []).isEmpty && theme.appearance == "light")
        #expect(!theme.resolved(systemDark: true).isDark && !theme.resolved(systemDark: false).isDark)
        #expect(SpaceColorPresets.firstPadColour == "#DCF3FC")
        #expect(SpaceColorPresets.pastelTheme().key == ["#DCF3FC"])
    }

    /// A new install's first space is Arc's warm off-white, light.
    @Test func firstSpaceIsWarmOffWhite() {
        let theme = SidebarDocument.fresh().spaces[0].theme
        #expect(theme == SpaceColorPresets.firstSpaceTheme() && theme.key == ["#F2EAE4"])
        #expect(!theme.resolved(systemDark: true).isDark && !theme.resolved(systemDark: false).isDark)
    }

    /// Arc's pairs: each Brand colour with the second colour Arc saved for it, which keeps roughly
    /// its brightness and lies 29–46° further round the hue wheel.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/170"), arguments: 0..<9)
    func brandPairs(index: Int) {
        let swatch = SpaceColorPresets.pages[1].swatches[index]
        #expect(swatch == [SpaceColorPresets.brand[index], SpaceColorPresets.brandPairs[index]])
        #expect(SpaceColorPresets.brandPairs[3] == "#EAAF5A")
        let a = SpaceColorWheel.hsb(swatch[0]), b = SpaceColorWheel.hsb(swatch[1])
        #expect(abs(a.brightness - b.brightness) < 0.06)
        if a.saturation > 0.05 {
            let turn = (b.hue - a.hue + 360).truncatingRemainder(dividingBy: 360)
            #expect(turn > 25 && turn < 50)
        }
    }

    /// hsb and hex are inverse to the byte.
    @Test(arguments: SpaceColorPresets.brand + SpaceColorPresets.pastel + SpaceColorPresets.greyscale)
    func wheelRoundTrips(hex: String) {
        let w = SpaceColorWheel.hsb(hex)
        #expect(SpaceColorWheel.hex(hue: w.hue, saturation: w.saturation, brightness: w.brightness) == hex)
    }

    /// The editor's − (this fork's take on upstream c1aadf7): with colours left it only takes the last
    /// one; taking the only one puts the pad back on a new space's unthemed pad whatever look it had,
    /// so the space is painted the default tint (#DCF3FC) in Light again, its opacity its own.
    @Test func removingTheLastColourGoesBackToUnthemed() {
        let two = SpaceColorPresets.removingColour(key: ["#8389FF", "#FF8389"], appearance: "dark", intensity: 0.4, noise: 0.3)
        #expect(two.key == ["#8389FF"] && two.appearance == "dark" && two.intensity == 0.4 && two.noise == 0.3)
        let last = SpaceColorPresets.removingColour(key: ["#8389FF"], appearance: "dark", intensity: 0.4, noise: 0.3)
        #expect(last.key.isEmpty && last.appearance == "light")
        let theme = SpaceThemeVariants.theme(key: last.key, intensity: last.intensity, noise: last.noise, appearance: last.appearance, opacity: 0.7)
        #expect(theme == SpaceColorPresets.newSpaceTheme(opacity: 0.7))
        let painted = theme.paintingUnthemed(with: SpaceColorPresets.defaultTint)
        #expect(!painted.isDark && painted.colors.allSatisfy { $0.uppercased() == SpaceColorPresets.defaultTint } && painted.opacity == 0.7)
        let none = SpaceColorPresets.removingColour(key: [], appearance: "auto", intensity: 0.5, noise: 0.1)
        #expect(none.key.isEmpty && none.appearance == "auto", "an empty pad has nothing to take")
    }
}
