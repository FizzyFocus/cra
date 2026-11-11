import AppKit

/// The colour of a site search's pill (the command bar's chip after Tab, and its rows while scoped):
/// the colour picked for it in Settings ▸ Search Engines, else Arc's measured brand colour, else the
/// most common vivid colour of the site's icon (FaviconColor), else none (the space's colour).
@MainActor
final class SiteSearchColors {
    static let shared = SiteSearchColors()
    /// Per host: the icon's colour, or nil once it had none.
    private var fromIcons: [String: String?] = [:]

    /// The host a site search runs on (its address template's), for its icon.
    static func host(of site: SiteSearch) -> String? {
        let probe = site.url.replacingOccurrences(of: "%s", with: "q").replacingOccurrences(of: "{searchTerms}", with: "q")
            .replacingOccurrences(of: "{google:baseURL}", with: "https://www.google.com/")
        return URL(string: probe)?.host?.lowercased()
    }

    /// The pill's colour as "#RRGGBB"; nil for the space's. `fetched` runs when an icon that wasn't
    /// at hand arrives, so the pill can take its colour then.
    func hex(for site: SiteSearch, settings: AppSettings, favicons: FaviconCache, fetched: @escaping () -> Void = {}) -> String? {
        if let own = settings.siteSearchColors[site.host.lowercased()] { return own }
        if let color = site.color { return color }
        guard let host = Self.host(of: site) else { return nil }
        if let known = fromIcons[host] { return known }
        let key = FaviconKey.key(for: "https://\(host)/")
        guard let image = favicons.image(forKey: key) else {
            SiteIconLoader.shared.load(host: host, into: favicons) { [weak self] in
                self?.fromIcons[host] = nil
                fetched()
            }
            return nil
        }
        let hex = Self.dominant(image)
        fromIcons[host] = .some(hex)
        return hex
    }

    /// The icon drawn into 32 × 32 RGBA pixels and read by FaviconColor.
    static func dominant(_ image: NSImage) -> String? {
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            var rect = NSRect(x: 0, y: 0, width: side, height: side)
            guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? FaviconColor.dominant(rgba: pixels, width: side, height: side) : nil
    }
}
