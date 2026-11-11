/// The colours of Cra's dialogs (Quit Cra?, Delete Space, Create a new Profile, every alert) taken
/// from the space they open over (11 Nov 2026): a light space's pastel, frosted, with dark text; a
/// dark space's own dark tone, not a flat navy or black, with light text. Only the fills, edges and
/// text change; the blue and red buttons, the shapes and the spacing are Arc's. Each is "#RRGGBB"
/// and an alpha.
public struct DialogTones: Equatable, Sendable {
    public struct Tone: Equatable, Sendable {
        public var hex: String
        public var alpha: Double
        public init(_ hex: String, _ alpha: Double = 1) { self.hex = hex; self.alpha = alpha }
    }

    public var dark: Bool
    public var card, edge, title, body, muted, placeholder, fieldFill, fieldStroke: Tone
    public var secondaryFill, secondaryStroke, secondaryText, keyFill, keyText: Tone
    public var primaryFill, primaryStroke, primaryKeyFill: Tone
    public var avatarFace, avatarRim, avatarInk: Tone

    /// Tones for a space whose colour is `base` ("#RRGGBB"), light or dark.
    public init(base: String, dark: Bool) {
        let b = SpaceColorPresets.validTint(base) ?? "#3B3C8F"
        func at(_ l: Double) -> String { SpaceThemeVariants.shade(b, lightness: l) }
        self.dark = dark
        if dark {
            card = Tone(at(0.12)); edge = Tone("#FFFFFF", 0.08)
            title = Tone("#FFFFFF"); body = Tone("#FFFFFF", 0.72); muted = Tone("#FFFFFF", 0.52); placeholder = Tone("#FFFFFF", 0.4)
            fieldFill = Tone(at(0.2)); fieldStroke = Tone(at(0.38))
            secondaryFill = Tone(at(0.24)); secondaryStroke = Tone(at(0.4)); secondaryText = Tone("#EBEBEF")
            keyFill = Tone(at(0.33)); keyText = Tone("#FFFFFF", 0.72)
            primaryFill = Tone(at(0.32)); primaryStroke = Tone(at(0.46)); primaryKeyFill = Tone(at(0.4))
            avatarFace = Tone(at(0.22)); avatarRim = Tone(at(0.5)); avatarInk = Tone(at(0.86))
        } else {
            card = Tone(at(0.95), 0.86); edge = Tone("#000000", 0.1)
            title = Tone("#1D1D22"); body = Tone("#1D1D22", 0.72); muted = Tone("#1D1D22", 0.52); placeholder = Tone("#1D1D22", 0.36)
            fieldFill = Tone("#FFFFFF", 0.72); fieldStroke = Tone("#000000", 0.14)
            secondaryFill = Tone(at(0.88)); secondaryStroke = Tone("#000000", 0.12); secondaryText = Tone("#1D1D22")
            keyFill = Tone("#000000", 0.08); keyText = Tone("#1D1D22", 0.6)
            primaryFill = Tone(at(0.42)); primaryStroke = Tone(at(0.34)); primaryKeyFill = Tone(at(0.52))
            avatarFace = Tone(at(0.86)); avatarRim = Tone(at(0.55)); avatarInk = Tone(at(0.32))
        }
    }

    /// Arc's own dialog, before a space says otherwise: its navy.
    public static let arc = DialogTones(base: "#3B3C8F", dark: true)

    /// The base colour of a space's theme as shown: the pad's first colour, else its accent or top colour.
    public static func base(of theme: SpaceTheme) -> String {
        theme.key?.first ?? theme.accent ?? theme.colors.first ?? SpaceColorPresets.defaultTint
    }

    /// How bright a tone is, 0…1 (relative luminance of its colour).
    public static func luminance(_ t: Tone) -> Double { HexColor.luminance(t.hex) ?? 0 }
}
