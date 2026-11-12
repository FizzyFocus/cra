import Foundation

/// The theme editor's preset swatches (Arc 1.171: SpaceStyleEditor's preset pages). Arc's colours
/// are named colours in ARCClients_BaseAssets' asset catalog, four groups of nine
/// (ColorPickerBrand1–9, Drab, Pastel, Greyscale), defined in sRGB, extended linear sRGB or
/// Display P3; these are their sRGB values, as Arc writes them to StorableSidebar.json (Brand8 →
/// 0.4236, 0.7286, 0.8512). A two-colour swatch is a catalog colour with its analogous colour added
/// (Arc: the preset view's `addComplimentary`, saved as an `analogous` wheel).
public enum SpaceColorPresets {
    public static let brand = ["#F2EAE4", "#F29BBB", "#A6729D", "#F25E6B", "#FF8558", "#F8D558", "#34E895", "#6CBAD9", "#666789"]
    public static let drab = ["#4E3A5A", "#693558", "#8F4042", "#B16D40", "#D7B35D", "#CDCCA4", "#7AA982", "#226149", "#26456B"]
    public static let pastel = ["#FEFBFA", "#FFE9F3", "#F1D1EC", "#FFCBD1", "#FFE0D3", "#FFF9E5", "#DEFDEB", "#DCF3FC", "#C5C6E5"]
    public static let greyscale = ["#FFFFFF", "#E6E6E6", "#CCCCCC", "#B2B2B2", "#808080", "#666666", "#333333", "#1A1A1A", "#000000"]
    /// The second colour Arc saves for each Brand pair (offline Arc 1.171, the page-2 swatches pressed over AX:
    /// `baseColors[1]` in StorableSidebar.json), 29–46° further round the hue wheel.
    public static let brandPairs = ["#EFF1E3", "#EFB19B", "#A6727F", "#EAAF5A", "#F0E941", "#A4F454", "#38E5E7", "#7F7EDC", "#7F6589"]

    /// One page of nine: a catalog group, alone or each colour with a second one.
    public struct Page: Equatable, Sendable {
        /// The catalog group: Brand, Drab, Pastel or Greyscale.
        public let group: String
        public let colors: [String]
        /// Each swatch's second colour, for a page of pairs.
        public let seconds: [String]?

        /// Arc's asset name of swatch `i` (ColorPickerBrand4), which its accessibility label names.
        public func name(_ i: Int) -> String { "ColorPicker\(group)\(i + 1)" }

        /// What each swatch puts on the pad: one colour, or two.
        public var swatches: [[String]] {
            guard let seconds else { return colors.map { [$0] } }
            return zip(colors, seconds).map { [$0, $1] }
        }
    }

    /// Arc's five pages (offline Arc 1.171, AX + captures): Brand, Brand pairs, Pastel, Drab, Greyscale.
    public static let pages: [Page] = [
        Page(group: "Brand", colors: brand, seconds: nil),
        Page(group: "Brand", colors: brand, seconds: brandPairs),
        Page(group: "Pastel", colors: pastel, seconds: nil),
        Page(group: "Drab", colors: drab, seconds: nil),
        Page(group: "Greyscale", colors: greyscale, seconds: nil),
    ]

    /// The page that holds a theme's pad colours, so the editor opens where they are; nil when
    /// they are no preset's.
    public static func page(of key: [String]) -> Int? {
        let k = key.map { $0.uppercased() }
        return pages.firstIndex { $0.swatches.contains(k) }
    }

    /// Where a new space starts: Pastel's sky, a clean light blue.
    public static let newSpaceIndex = 7

    /// A new space's theme: unthemed, nothing on the picker's pad (count 0, the neutral grey look),
    /// in Light, so it never starts on a dark look nobody picked (10 Nov 2026: a new space no
    /// longer starts on a colour of Cra's choosing). A tap on the pad or its + brings the first
    /// colour in (`firstPadColour`).
    /// `opacity`: how see-through it starts (Settings ▸ Appearance), a subtle frost by default.
    public static func newSpaceTheme(opacity: Double? = AppSettings.defaultSpaceOpacityDefault) -> SpaceTheme {
        SpaceThemeVariants.theme(key: [], intensity: unthemedIntensity, noise: unthemedNoise, appearance: unthemedAppearance, opacity: opacity)
    }

    /// The pad a new space starts on: no colours, Light, this intensity and no grain. Painted with
    /// Settings ▸ Appearance ▸ Default color (`defaultTint`, #DCF3FC unless changed).
    public static let unthemedAppearance = "light"
    public static let unthemedIntensity = 0.8
    public static let unthemedNoise = 0.0

    /// The theme editor's − (the pad's colours, look, intensity and grain after it): the last colour
    /// goes, and taking the only one left puts the pad back where a new space starts (no colours,
    /// Light, default intensity, no grain), so the space is painted the default tint again whatever
    /// look it had. Upstream (c1aadf7, #300) turned an empty pad into Arc's colourless purple theme.
    public static func removingColour(key: [String], appearance: String, intensity: Double, noise: Double)
        -> (key: [String], appearance: String, intensity: Double, noise: Double) {
        guard !key.isEmpty else { return (key, appearance, intensity, noise) }
        let rest = Array(key.dropLast())
        return rest.isEmpty ? ([], unthemedAppearance, unthemedIntensity, unthemedNoise) : (rest, appearance, intensity, noise)
    }

    /// A space with nothing on its pad is painted this (AppSettings.defaultSpaceTint): Arc's light
    /// pastel sky blue, see-through like any theme with an opacity under 1.
    public static let defaultTint = "#DCF3FC"

    /// `hex` as "#RRGGBB" in capitals when it is one, else nil.
    public static func validTint(_ hex: String) -> String? {
        let h = hex.trimmingCharacters(in: .whitespaces).uppercased()
        guard h.count == 7, h.hasPrefix("#"), h.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        return h
    }

    /// The colour the pad's + puts on an empty pad: Pastel's sky blue (`newSpaceIndex`).
    public static var firstPadColour: String { pastel[newSpaceIndex] }

    /// One of Arc's Pastel catalogue colours (warm off-white, blush, lilac, rose, peach, cream,
    /// mint, sky, periwinkle) alone on the pad, in Light: Arc's light pastel look whatever macOS is
    /// set to. What the + makes of an empty pad (`newSpaceIndex`).
    public static func pastelTheme(index: Int = newSpaceIndex) -> SpaceTheme {
        SpaceThemeVariants.theme(key: [pastel[index % pastel.count]], intensity: 0.8, noise: 0, appearance: "light")
    }

    /// The first space of a new install: Arc's warm off-white (ColorPickerBrand1), in Light, with
    /// the default frost (the desktop a little through it).
    public static func firstSpaceTheme() -> SpaceTheme {
        SpaceThemeVariants.theme(key: [brand[0]], intensity: 0.8, noise: 0, appearance: "light", opacity: AppSettings.defaultSpaceOpacityDefault)
    }
}

/// The editor pad's colour wheel: a colour's place is its HSB hue (angle) and saturation
/// (distance from the centre). A second and third colour sit `spread`° either side of the first
/// (Arc's saved pairs sit 29–46° away).
public enum SpaceColorWheel {
    public static let spread = 40.0

    /// The hue offset of pad colour `i`: 0 for the first, then +spread, −spread.
    public static func offset(_ i: Int) -> Double { i == 0 ? 0 : (i == 1 ? spread : -spread) }

    public static func hsb(_ hex: String) -> (hue: Double, saturation: Double, brightness: Double) {
        let c = HexColor.components(hex) ?? (0.5, 0.5, 0.5)
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == c.r { h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == c.g { h = (c.b - c.r) / d + 2 }
            else { h = (c.r - c.g) / d + 4 }
            h = (h * 60 + 360).truncatingRemainder(dividingBy: 360)
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    /// `hue` in degrees (any value, wrapped), saturation and brightness 0...1.
    public static func hex(hue: Double, saturation: Double, brightness: Double) -> String {
        let h = ((hue.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 60
        let s = max(0, min(1, saturation)), v = max(0, min(1, brightness))
        let c = v * s, x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double)
        switch Int(h) % 6 {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        func byte(_ v: Double) -> Int { Int(((v + m) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
