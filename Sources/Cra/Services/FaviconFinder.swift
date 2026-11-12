import AppKit
import CraCEF

/// Runs a page's FaviconSearch (CraCore) on its browser: Chromium's image download for the
/// renderer attempts, the tab's own request context for the rest (decoded here by
/// FaviconImage). `found` gets the first icon that decodes, on the main thread.
@MainActor
final class FaviconFinder {
    private(set) weak var browser: CraBrowser?
    private var search = FaviconSearch()
    private let found: (NSImage, String) -> Void

    init(browser: CraBrowser, found: @escaping (NSImage, String) -> Void) {
        self.browser = browser
        self.found = found
    }

    /// Chromium's list of the page's icons changed (OnFaviconURLChange).
    func iconsChanged(_ urls: [String]) {
        guard let browser else { return }
        run(search.iconsChanged(urls, pageURL: browser.currentURL))
    }

    /// The page finished loading; `json` is what its DOM declares (FaviconSearch.pageIcons).
    func pageLoaded(iconsJSON json: String) {
        guard let browser else { return }
        run(search.pageLoaded(declared: FaviconSearch.pageIcons(json: json), pageURL: browser.currentURL))
    }

    private func run(_ attempt: FaviconSearch.Attempt?) {
        guard let attempt, let browser, !browser.isClosed else { return }
        switch attempt.fetch {
        case .renderer:
            // CraCEF answers on the main thread.
            browser.downloadFavicon(attempt.url) { [weak self] image in MainActor.assumeIsolated { self?.finish(attempt, image) } }
        case .session:
            // A data: icon (an SVG the renderer couldn't read) is its own bytes.
            if let inline = WebImagePreview.decodeDataURL(attempt.url) {
                finish(attempt, FaviconImage.decode(inline.data))
                return
            }
            browser.fetchImageData(attempt.url) { [weak self] status, mimeType, data in
                MainActor.assumeIsolated {
                    let usable = FaviconSearch.accepts(status: status, mimeType: mimeType)
                    self?.finish(attempt, usable ? data.flatMap(FaviconImage.decode) : nil)
                }
            }
        }
    }

    private func finish(_ attempt: FaviconSearch.Attempt, _ image: NSImage?) {
        let answers = search.current == attempt
        let next = search.finished(attempt, decoded: image != nil)
        if answers, let browser {
            let site = browser.isIncognito ? "(incognito)" : CraLog.host(search.pageURL)
            if let image {
                CraLog.note("favicon \(site): \(Self.name(attempt.url)) via \(attempt.fetch.rawValue)")
                found(image, attempt.url)
            } else if next == nil {
                CraLog.note("favicon \(site): no icon decoded")
            }
        }
        run(next)
    }

    /// What the log names an icon by: its file, never its query.
    private static func name(_ url: String) -> String {
        if url.lowercased().hasPrefix("data:") { return "data:" + (WebImagePreview.decodeDataURL(url)?.mimeType ?? "") }
        return URL(string: url).map { $0.lastPathComponent.isEmpty ? "/" : $0.lastPathComponent } ?? "?"
    }
}

/// An icon's bytes as Cra keeps it: whatever NSImage reads (PNG, ICO with all its sizes, WebP,
/// GIF, JPEG, BMP, SVG), drawn into a bitmap of at most 128 px a side, the size Chromium's own
/// download gives (64 pt at 2x). An SVG is drawn at that size. Nil for bytes that read as no
/// picture (an HTML page, a file mangled on the way).
enum FaviconImage {
    static let maxPixels = 128

    static func decode(_ data: Data) -> NSImage? {
        guard !data.isEmpty, let source = NSImage(data: data), source.size.width > 0, source.size.height > 0,
              source.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil else { return nil }
        // An SVG's (or PDF's) representation has no pixels of its own.
        let widest = source.representations.map(\.pixelsWide).max() ?? 0
        let side = widest <= 0 ? maxPixels : min(maxPixels, widest)
        let aspect = source.size.width / source.size.height
        let w = aspect >= 1 ? side : max(1, Int((CGFloat(side) * aspect).rounded()))
        let h = aspect >= 1 ? max(1, Int((CGFloat(side) / aspect).rounded())) : side
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: w, height: h))
        image.addRepresentation(rep)
        return image
    }
}
