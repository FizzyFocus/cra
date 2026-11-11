import Foundation

/// A site search the user added in Settings ▸ Search Engines (Add Site Search…): typed `shortcut`
/// then Tab scopes the command bar to it, as Arc's sites and Chromium's keywords do. Its pill takes
/// `color` when one was picked, else the colour of the site's icon (FaviconColor).
public struct CustomSiteSearch: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// What is typed before Tab ("ya" for YummyAni).
    public var shortcut: String
    /// The search address with `%s` where the query goes.
    public var url: String
    /// "#RRGGBB"; nil takes the icon's colour.
    public var color: String?

    public init(id: UUID = UUID(), name: String, shortcut: String, url: String, color: String? = nil) {
        self.id = id
        self.name = name
        self.shortcut = shortcut
        self.url = url
        self.color = color
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        shortcut = try c.decode(String.self, forKey: .shortcut)
        url = try c.decode(String.self, forKey: .url)
        color = try? c.decodeIfPresent(String.self, forKey: .color)
    }

    /// The shortcut as it is matched: lower case, no spaces.
    public var key: String { shortcut.lowercased().filter { !$0.isWhitespace } }

    /// The host the search runs on, for its icon.
    public var host: String? { URL(string: url.replacingOccurrences(of: "%s", with: "q"))?.host?.lowercased() }

    /// What the add sheet checks: a name, a shortcut without spaces, an http(s) address with `%s`.
    public static func problem(name: String, shortcut: String, url: String, taken: [String]) -> String? {
        let n = name.trimmingCharacters(in: .whitespaces), s = shortcut.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return "Give it a name." }
        if s.isEmpty || s.contains(" ") || s.contains("/") { return "The shortcut is one word, without spaces." }
        if taken.contains(s.lowercased()) { return "Another site search has that shortcut." }
        guard url.contains("%s") else { return "Put %s in the address where the search goes." }
        guard let u = URL(string: url.replacingOccurrences(of: "%s", with: "q")), let scheme = u.scheme?.lowercased(),
              ["http", "https"].contains(scheme), u.host != nil else { return "The address starts with https://." }
        return nil
    }
}

extension SiteSearch {
    public init(_ custom: CustomSiteSearch) {
        self.init(name: custom.name, host: custom.key, url: custom.url, color: custom.color)
    }

    /// `match`, with the user's own site searches first: a shortcut typed out in full wins over
    /// everything, one started (two letters on) comes after Arc's sites, before Chromium's keywords.
    public static func match(_ q: String, completion: String?, keywords: [ChromiumSearchEngine] = [],
                             custom: [CustomSiteSearch], hidden: Set<String> = []) -> SiteSearch? {
        var t = q.lowercased()
        if t.hasPrefix("www.") { t.removeFirst(4) }
        guard !t.isEmpty, !t.contains(" "), !t.contains("/") else { return nil }
        if let exact = custom.first(where: { $0.key == t }) { return SiteSearch(exact) }
        if let site = match(q, completion: completion, keywords: [], hidden: hidden) { return site }
        if t.count >= 2, let started = custom.first(where: { $0.key.hasPrefix(t) }) { return SiteSearch(started) }
        return match(q, completion: completion, keywords: keywords, hidden: hidden)
    }
}

/// The colour a site search's pill takes from the site's icon when none is set: the icon's most
/// common vivid hue, averaged over the pixels of that hue (CoreGraphics draws the icon into
/// `rgba`; this only reads the pixels). Greys, near-white and near-black don't count.
public enum FaviconColor {
    /// `rgba`: width × height pixels, 4 bytes each (premultiplied or not). nil when nothing in it
    /// is vivid (a black-and-white logo): the pill then takes the space's colour.
    public static func dominant(rgba: [UInt8], width: Int, height: Int) -> String? {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return nil }
        let bins = 24
        var weight = [Double](repeating: 0, count: bins)
        var sum = [(r: Double, g: Double, b: Double)](repeating: (0, 0, 0), count: bins)
        for p in 0..<(width * height) {
            let a = Double(rgba[p * 4 + 3]) / 255
            guard a > 0.5 else { continue }
            // Undo premultiplication when there was any.
            let r = min(1, Double(rgba[p * 4]) / 255 / a), g = min(1, Double(rgba[p * 4 + 1]) / 255 / a), b = min(1, Double(rgba[p * 4 + 2]) / 255 / a)
            let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
            let s = mx > 0 ? d / mx : 0
            guard s > 0.35, mx > 0.25, d > 0.12 else { continue }
            var h: Double
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
            let bin = min(bins - 1, Int(h * Double(bins)))
            // Vivid, bright pixels count most.
            let w = s * mx * a
            weight[bin] += w
            sum[bin].r += r * w; sum[bin].g += g * w; sum[bin].b += b * w
        }
        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 0 else { return nil }
        let w = weight[best]
        func byte(_ v: Double) -> Int { Int((v / w * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(sum[best].r), byte(sum[best].g), byte(sum[best].b))
    }
}
