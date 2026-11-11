import CraCore
import Testing

/// Arc's Create a Space panel and theme picker tones.
struct CreateSpaceTonesTests {
    @Test func pickerIsLightInLightAndOnAnEmptyPadInALightMac() {
        #expect(CreateSpaceTones.pickerIsLight(key: ["#C5C6E5"], appearance: "light", systemDark: true))
        #expect(!CreateSpaceTones.pickerIsLight(key: ["#C5C6E5"], appearance: "dark", systemDark: false))
        #expect(!CreateSpaceTones.pickerIsLight(key: ["#C5C6E5"], appearance: "auto", systemDark: false), "Auto with a colour: Arc's dark card")
        #expect(CreateSpaceTones.pickerIsLight(key: [], appearance: "auto", systemDark: false), "Tap to pick a color, on a light Mac")
        #expect(!CreateSpaceTones.pickerIsLight(key: [], appearance: "auto", systemDark: true))
    }

    /// Fitted to Arc over a periwinkle space: the washed button ≈ #9C9CF5, its text ≈ #CCCCFA.
    @Test func washedButtonOnAPeriwinkleSpace() {
        let b = CreateSpaceTones.button(key: "#C5C6E5", lightTheme: true, enabled: false)
        func near(_ hex: String, _ r: Double, _ g: Double, _ bl: Double) -> Bool {
            guard let c = HexColor.components(hex) else { return false }
            return abs(c.r * 255 - r) <= 12 && abs(c.g * 255 - g) <= 12 && abs(c.b * 255 - bl) <= 12
        }
        #expect(near(b.fill, 156, 156, 245))
        #expect(near(b.text, 204, 204, 250))
    }

    @Test func greysStayGrey() {
        for key in ["#F2EAE4", "#FFFFFF", "#808080"] {
            for light in [true, false] {
                for enabled in [true, false] {
                    let fill = CreateSpaceTones.button(key: key, lightTheme: light, enabled: enabled).fill
                    #expect(SpaceColorWheel.hsb(fill).saturation == 0, "\(key) gives a grey \(fill)")
                }
            }
        }
    }

    @Test func enabledReadsWhiteOnTheAccent() {
        #expect(CreateSpaceTones.button(key: "#FFCBD1", lightTheme: true, enabled: true).text == "#FFFFFF")
        #expect(CreateSpaceTones.button(key: "#6CBAD9", lightTheme: false, enabled: true).text == "#FFFFFF")
    }
}
