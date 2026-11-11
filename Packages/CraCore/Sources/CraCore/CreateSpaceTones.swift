/// The tones of Arc's Create a Space panel and its theme picker. Dark-theme shades and the picker's
/// light/dark rule follow Sailfish's measurements of Arc (Apache-2.0, macOS/Sailfish/Window/Theme.swift
/// and Spaces/ThemePicker.swift); the light-theme button is fitted to an Arc 1.17x capture of the
/// panel over a periwinkle space (the disabled button ≈ #9C9CF5 with #CCCCFA text).
public enum CreateSpaceTones {
    /// The picker draws black on a light panel in Light, and before any colour is picked while macOS is
    /// light (Arc's "Tap to pick a color" card); otherwise white on a dark one.
    public static func pickerIsLight(key: [String], appearance: String, systemDark: Bool) -> Bool {
        switch appearance {
        case "light": return true
        case "dark": return false
        default: return key.isEmpty && !systemDark
        }
    }

    /// The Create Space button in the theme's hue: a full accent once the space has a name, washed
    /// out before. Greys (the off-whites, the greyscale page) stay grey rather than take hue 0's red.
    public static func button(key: String?, lightTheme: Bool, enabled: Bool) -> (fill: String, text: String) {
        let hsb = key.map(SpaceColorWheel.hsb) ?? (hue: 240, saturation: 0.3, brightness: 0.9)
        let grey = hsb.saturation < 0.08
        func shade(_ s: Double, _ b: Double) -> String { SpaceColorWheel.hex(hue: hsb.hue, saturation: grey ? 0 : s, brightness: b) }
        switch (lightTheme, enabled) {
        case (true, true): return (shade(0.55, 0.78), "#FFFFFF")
        case (true, false): return (shade(0.37, 0.96), shade(0.2, 0.98))
        case (false, true): return (shade(0.68, 0.81), "#FFFFFF")
        case (false, false): return (shade(0.8, 0.48), shade(0.55, 0.78))
        }
    }
}
