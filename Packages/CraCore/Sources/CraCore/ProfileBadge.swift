import Foundation

/// How a profile shows on its badge (13 Nov 2026): an emoji and one of the accents, both optional.
/// Settings ▸ Profiles ▸ Edit… chooses them. A colour this build doesn't know reads as none, so a
/// file from a newer build still loads.
public struct ProfileLook: Codable, Equatable {
    public var icon: String?
    public var color: String?

    public init(icon: String? = nil, color: String? = nil) {
        self.icon = icon
        self.color = color
    }

    public var accent: ProfileAccent? { color.flatMap(ProfileAccent.init(rawValue:)) }
    public var isEmpty: Bool { (icon ?? "").isEmpty && accent == nil }

    /// What an edit saves: a blank icon is none, an icon is its first character (one emoji, flags
    /// and skin tones included), and an unknown colour is none.
    public static func cleaned(icon: String?, color: String?) -> ProfileLook {
        let i = icon?.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init)
        return ProfileLook(icon: i, color: color.flatMap(ProfileAccent.init(rawValue:))?.rawValue)
    }
}

/// The accents a profile can take: macOS's own accent colours, as sRGB.
public enum ProfileAccent: String, CaseIterable, Codable, Sendable {
    case blue, purple, pink, red, orange, yellow, green, graphite

    public var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    public var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .blue: (0.0, 0.478, 1.0)
        case .purple: (0.584, 0.239, 0.588)
        case .pink: (0.969, 0.31, 0.62)
        case .red: (0.878, 0.22, 0.243)
        case .orange: (0.969, 0.51, 0.106)
        case .yellow: (1.0, 0.776, 0.0)
        case .green: (0.384, 0.729, 0.275)
        case .graphite: (0.596, 0.596, 0.596)
        }
    }

    /// "#RRGGBB", for the settings page's swatches.
    public var hex: String {
        let c = rgb
        return String(format: "#%02X%02X%02X", Int((c.r * 255).rounded()), Int((c.g * 255).rounded()), Int((c.b * 255).rounded()))
    }
}

/// The space's profile, named in a small pill (13 Nov 2026, the owner's call): on Library ▸ Spaces'
/// cards and beside the space's name at the top of the sidebar. With only the Default profile
/// there is nothing to tell apart, so neither shows it.
public enum ProfileBadge {
    public enum Place { case sidebar, library }

    /// `profiles` counts Default. Incognito spaces and Blank Windows' spaces have no profile of
    /// their own to show; the sidebar's pill follows Settings ▸ "Show profile indicator in sidebar".
    public static func shows(profiles: Int, in place: Place, setting: Bool, incognito: Bool = false, blank: Bool = false) -> Bool {
        guard profiles > 1, !incognito, !blank else { return false }
        return place == .library || setting
    }

    /// The pill's width for a name `nameWidth` wide: the name gives way first, down to the icon
    /// alone, then the pill goes. `room` is what the row leaves it after `minTitle` for the title.
    public static func width(name nameWidth: Double, hasIcon: Bool, room: Double, maxWidth: Double = 104) -> (width: Double, showsName: Bool)? {
        let lead = hasIcon ? iconWidth + iconGap : dotWidth + iconGap
        let full = min(maxWidth, padding * 2 + lead + nameWidth)
        if full <= room { return (full, true) }
        let compact = padding * 2 + (hasIcon ? iconWidth : dotWidth)
        // The name stays while a few letters of it still fit.
        if room >= padding * 2 + lead + 24 { return (room, true) }
        return compact <= room ? (compact, false) : nil
    }

    public static let height: Double = 18
    public static let padding: Double = 6
    public static let iconWidth: Double = 12
    public static let dotWidth: Double = 7
    public static let iconGap: Double = 4
}
