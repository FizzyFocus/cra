import Foundation

/// An image on a web page opened in Cra's preview (11 Nov 2026), the card Library ▸ Media and
/// Downloads use: from the image's context menu ("Open Image in Preview"), or by a Shift-click on
/// it. The preview grows out of the image where it sits on the page.
public enum WebImagePreview {
    /// A Shift-click (Shift alone, a click, not a drag) previews the image under the pointer, unless
    /// the image is a link: Shift-clicking a link stays what it was (Peek, PeekTrigger).
    public static func shiftClickPreviews(shiftOnly: Bool, isImage: Bool, insideLink: Bool) -> Bool {
        shiftOnly && isImage && !insideLink
    }

    /// The image under (x, y), device pixels in the page's view: its source, whether it's inside a
    /// link and where it is, in device pixels too (ContentCapture.elementRect reads that). Nil
    /// where there is no image. Runs in Cra's isolated world.
    public static func imageScript(x: CGFloat, y: CGFloat) -> String {
        """
        (() => {
          const vv = visualViewport, dpr = devicePixelRatio, k = vv.scale;
          const px = \(Double(x)) / dpr / k + vv.offsetLeft, py = \(Double(y)) / dpr / k + vv.offsetTop;
          const img = document.elementsFromPoint(px, py).find(e => e.tagName === 'IMG');
          if (!img) return null;
          const r = img.getBoundingClientRect();
          return {src: img.currentSrc || img.src, link: !!img.closest('a[href]'),
                  x: (r.left - vv.offsetLeft) * k * dpr, y: (r.top - vv.offsetTop) * k * dpr,
                  width: r.width * k * dpr, height: r.height * k * dpr};
        })()
        """
    }

    /// A `data:` URL's bytes and type; nil for anything else or a malformed one.
    public static func decodeDataURL(_ url: String) -> (data: Data, mimeType: String)? {
        guard url.lowercased().hasPrefix("data:"), let comma = url.firstIndex(of: ",") else { return nil }
        let meta = url[url.index(url.startIndex, offsetBy: 5)..<comma]
        let payload = String(url[url.index(after: comma)...])
        let parts = meta.split(separator: ";").map(String.init)
        let mime = parts.first.flatMap { $0.isEmpty ? nil : $0.lowercased() } ?? "text/plain"
        if parts.contains(where: { $0.lowercased() == "base64" }) {
            guard let d = Data(base64Encoded: payload.removingPercentEncoding ?? payload, options: .ignoreUnknownCharacters) else { return nil }
            return (d, mime)
        }
        guard let text = payload.removingPercentEncoding else { return nil }
        return (Data(text.utf8), mime)
    }

    static let extensions: [String: String] = ["image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/webp": "webp",
                                               "image/svg+xml": "svg", "image/avif": "avif", "image/heic": "heic", "image/bmp": "bmp",
                                               "image/tiff": "tiff", "image/x-icon": "ico", "image/vnd.microsoft.icon": "ico"]

    /// The preview's file name: the address's own when it names an image ("photo.jpg"), else
    /// "Image" with the type's extension ("Image.png").
    public static func fileName(url: String, mimeType: String?) -> String {
        let fromType = mimeType.flatMap { extensions[$0.lowercased().split(separator: ";").first.map(String.init) ?? $0] }
        if !url.lowercased().hasPrefix("data:"), let u = URL(string: url) {
            let last = u.lastPathComponent.removingPercentEncoding ?? u.lastPathComponent
            if MediaPreview.kind(of: last) == .image, !last.hasPrefix(".") { return last }
            if let ext = fromType, !last.isEmpty, last != "/", !last.contains(".") { return last + "." + ext }
        }
        return "Image." + (fromType ?? "png")
    }
}
