import Foundation

/// Arc's Previews card beside a favorite (Gmail, Calendar), measured at 2x and 60 fps on Victor's
/// signed-in Arc 1.172.1, 8 Nov 2026.
public enum FavoritePreviewMetrics {
    /// The card: 238 pt wide, at most 270 pt tall; longer content scrolls under it.
    public static let width: CGFloat = 238
    public static let maxHeight: CGFloat = 270
    /// A mail row: 84 pt with a 1 pt line under it, its text 11 pt in from the card's edges.
    public static let mailRowHeight: CGFloat = 84
    public static let inset: CGFloat = 11
    /// The pointer's row: a lighter rounded card, 3 pt in from the row.
    public static let hoverInset: CGFloat = 3
    /// The round buttons at the bottom right (Gmail's ＋; Calendar's gear and ＋).
    public static let buttonSize: CGFloat = 32
    public static let buttonInset: CGFloat = 9.5
    public static let buttonGap: CGFloat = 8
    /// The Calendar card: 255 pt tall, an hour 42 pt with its label at the top left, events from
    /// 42 pt in (where the now line starts) to 5 pt from the right edge.
    public static let calendarHeight: CGFloat = 255
    public static let hourHeight: CGFloat = 42
    public static let eventsLeft: CGFloat = 42
    public static let eventsRight: CGFloat = 5
}

/// How Arc's Previews card comes and goes (60 fps capture, 8 Nov 2026): it shows about 0.25 s after
/// the pointer lands on the tile (once the content is in hand), grows from about 80 % while it
/// fades in over some 4 frames, and when the pointer leaves both the tile and the card, it waits
/// about 0.15 s, then fades out, shrinking a little, over about 4 frames.
public enum FavoritePreviewMotion {
    public static let showDelay: TimeInterval = 0.25
    public static let openScale: CGFloat = 0.8
    public static let openDuration: TimeInterval = 0.075
    public static let closeDelay: TimeInterval = 0.15
    public static let closeScale: CGFloat = 0.95
    public static let closeDuration: TimeInterval = 0.07
}

/// The Gmail and Calendar preview cards' colours (11 Nov 2026): Arc's dark card over a dark
/// sidebar, a light frosted one with dark text over a light one, so the card never stands out
/// black on a pastel space. Each is (r, g, b, alpha), 0…1.
public struct FavoritePreviewTones: Equatable, Sendable {
    public typealias RGBA = (r: Double, g: Double, b: Double, a: Double)
    public let fill: RGBA
    public let edge: RGBA
    public let line: RGBA
    public let text: RGBA
    public let secondary: RGBA
    public let hover: RGBA
    /// The round ＋ and gear buttons.
    public let button: RGBA

    public static func == (l: Self, r: Self) -> Bool {
        [l.fill, l.edge, l.line, l.text, l.secondary, l.hover, l.button].elementsEqual(
            [r.fill, r.edge, r.line, r.text, r.secondary, r.hover, r.button]) { $0 == $1 }
    }

    /// Arc's card: (25, 24, 23) with a (63, 62, 60) rim and white text.
    public static let dark = FavoritePreviewTones(
        fill: (25 / 255, 24 / 255, 23 / 255, 0.92), edge: (63 / 255, 62 / 255, 60 / 255, 1), line: (1, 1, 1, 0.08),
        text: (1, 1, 1, 0.9), secondary: (1, 1, 1, 0.5), hover: (1, 1, 1, 0.07), button: (0.14, 0.14, 0.14, 1))
    /// Over a light space: near-white frost, a hairline rim, near-black text.
    public static let light = FavoritePreviewTones(
        fill: (0.98, 0.98, 0.97, 0.82), edge: (0, 0, 0, 0.1), line: (0, 0, 0, 0.07),
        text: (0.1, 0.1, 0.1, 0.92), secondary: (0.1, 0.1, 0.1, 0.55), hover: (0, 0, 0, 0.05), button: (1, 1, 1, 1))

    /// The card's tones for a sidebar that is dark or not.
    public static func forSidebar(dark: Bool) -> FavoritePreviewTones { dark ? .dark : .light }

    /// How much darker than its fill the card's text is: high enough to read either way.
    public var contrast: Double {
        func lum(_ c: RGBA) -> Double { 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
        return abs(lum(fill) - lum(text))
    }
}
