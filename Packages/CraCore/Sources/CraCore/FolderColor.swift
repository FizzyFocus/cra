import Foundation

/// A folder's own colour (Cra's; Arc has only Auto, White and Black): pinned folders and the
/// Library's bookmark folders take one from Icon Color, and nil follows the space's theme. The
/// glyph is drawn in it the way the theme's folder is drawn from the theme colour: the front in
/// the colour itself, so the folder reads as that colour on any theme, the outline in its shaded
/// dark (its tinted light on a dark theme), the back panel between the two.
public enum FolderColor {
    /// The choices, in the menu's order: the rainbow, then grey.
    public static let catalogue: [(name: String, hex: String)] = [
        ("Red", "#F0625D"), ("Orange", "#F39A45"), ("Yellow", "#F2C94C"), ("Green", "#5DBB78"),
        ("Mint", "#4FC4AE"), ("Blue", "#4F8FEA"), ("Indigo", "#7472E6"), ("Purple", "#A673E3"),
        ("Pink", "#EC74B0"), ("Gray", "#9C9CA3"),
    ]

    /// The catalogue's name for a saved colour, nil for one it doesn't have (a newer Cra's).
    public static func name(of hex: String?) -> String? {
        guard let hex else { return nil }
        return catalogue.first { $0.hex.caseInsensitiveCompare(hex) == .orderedSame }?.name
    }

    /// The glyph's outline, front and back panel in `hex`, for a light or a dark sidebar; nil for
    /// a string that isn't a colour (the theme's tones then).
    public static func tones(_ hex: String, dark: Bool) -> FolderTones? {
        guard let c = HexColor.components(hex) else { return nil }
        let front = RGB(c.r, c.g, c.b)
        let outline = dark ? SpaceTheme.tintedLight(hex) : SpaceTheme.shadedDark(hex)
        return FolderTones(outline: outline, front: front, back: front.mixed(with: SpaceTheme.shadedDark(hex), 0.3))
    }
}
