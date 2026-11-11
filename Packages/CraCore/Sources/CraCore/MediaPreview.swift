import CoreGraphics
import Foundation

/// Arc's preview for a picture or video picked in Library ▸ Media (BaseHomeComponents'
/// MediaPreviewWindow, Arc 1.172.1, Victor's Arc, 8 Nov 2026), and since 11 Nov 2026 for a download
/// picked in the tray or Library ▸ Downloads: a panel over the dimmed window, the Library left as it
/// was. A 1728 × 1084 pt window gave a 1330 × 817 pt panel, 199 pt in from each
/// side and 133 pt from the top and bottom. Its 46 pt header holds ✕, ‹ ›, the file's name and age,
/// then ⋯ and "Open in Preview ↗"; the picture fits 15 pt inside the rest, over a blurred copy of
/// itself. It grows out of the picked thumbnail in about 0.21 s, easing out with a long settle.
public enum MediaPreview {
    public static let sideInset: CGFloat = 199.0 / 1728
    public static let topInset: CGFloat = 133.0 / 1084
    public static let headerHeight: CGFloat = 46
    public static let mediaInset: CGFloat = 15
    public static let cornerRadius: CGFloat = 16
    public static let openDuration: TimeInterval = 0.21
    public static let closeDuration: TimeInterval = 0.16
    /// Ease-out with a long, soft landing (the panel's last 10 % takes half the time).
    public static let curve: (Float, Float, Float, Float) = (0.2, 0.75, 0.25, 1)

    /// The panel in a window's content (points, origin at the bottom left).
    public static func panel(in bounds: CGRect) -> CGRect {
        let dx = (bounds.width * sideInset).rounded(), dy = (bounds.height * topInset).rounded()
        return bounds.insetBy(dx: dx, dy: dy)
    }

    /// The panel under its header, 15 pt in (bottom-left origin): a document fills it.
    public static func body(in panel: CGRect) -> CGRect {
        CGRect(x: panel.minX + mediaInset, y: panel.minY + mediaInset,
               width: max(0, panel.width - 2 * mediaInset), height: max(0, panel.height - headerHeight - 2 * mediaInset))
    }

    /// Where the picture goes in the panel (bottom-left origin): fitted inside, centred.
    public static func media(_ size: CGSize, in panel: CGRect) -> CGRect {
        let box = body(in: panel)
        guard size.width > 0, size.height > 0, box.width > 0, box.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        let w = (size.width * scale).rounded(), h = (size.height * scale).rounded()
        return CGRect(x: (box.midX - w / 2).rounded(), y: (box.midY - h / 2).rounded(), width: w, height: h)
    }

    /// What the preview shows a file as. Downloads open in it too since 11 Nov 2026 (from the tray
    /// over the Library button and Library ▸ Downloads, as picks in Library ▸ Media do), documents
    /// through Quick Look. A file it can't show (an archive, a disk image, an installer, an app, a
    /// type it doesn't know) opens in the Mac's app for it, as every download did before.
    public enum Kind: String, Equatable, Sendable {
        /// Drawn as a picture (a GIF moves).
        case image
        /// Played in the panel with Arc's round play/pause button.
        case video
        /// A video only WebKit plays (WebM), in a web view with its own controls.
        case webVideo
        /// Quick Look's view: PDFs, text, spreadsheets, Office and iWork files, sound.
        case document
    }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "tif", "bmp",
                                               "avif", "svg", "ico", "icns"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    static let webVideoExtensions: Set<String> = ["webm"]
    static let documentExtensions: Set<String> = [
        // PDF, text and data
        "pdf", "txt", "text", "md", "markdown", "csv", "tsv", "json", "xml", "log", "rtf", "rtfd", "html", "htm",
        "yaml", "yml", "toml", "ini", "ics", "vcf",
        // Source code (Quick Look shows it as text)
        "swift", "js", "ts", "py", "rb", "c", "h", "cpp", "m", "java", "go", "rs", "sh", "css",
        // Office and iWork
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key",
        // Sound (Quick Look plays it) and 3D
        "mp3", "m4a", "wav", "aac", "aif", "aiff", "flac", "usdz",
    ]

    /// How `path` is previewed, by its extension; nil opens it in its app.
    public static func kind(of path: String) -> Kind? {
        let ext = (path as NSString).pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        if webVideoExtensions.contains(ext) { return .webVideo }
        if documentExtensions.contains(ext) { return .document }
        return nil
    }

    /// What ‹ › step through after a pick in a list: the files in it the preview shows, in the
    /// list's order, and where the pick is among them. Nil when the pick isn't one of those (it
    /// opens in its app instead).
    public static func browse(_ paths: [String], picked: String) -> (paths: [String], index: Int)? {
        guard kind(of: picked) != nil else { return nil }
        let shown = paths.filter { kind(of: $0) != nil }
        guard let i = shown.firstIndex(of: picked) else { return ([picked], 0) }
        return (shown, i)
    }

    /// The header's hand-off button: "Open in Preview", "Open in QuickTime Player"; "Open" when no
    /// app takes the file.
    public static func openTitle(appName: String?) -> String {
        guard let name = appName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return "Open" }
        return "Open in " + (name.hasSuffix(".app") ? String(name.dropLast(4)) : name)
    }

    /// How the panel grows out of a picked item and shrinks back into it: the uniform scale about
    /// `about` (where the panel's layer has its anchor point, as Core Animation scales there), then
    /// the shift, that lay its picture (`media`) centred inside `origin`, the item's thumbnail, all
    /// in the overlay's coordinates. Nil when either is empty. The anchor is the layer's own: moving
    /// it to the centre for the animation didn't hold (AppKit puts a view's layer back at its corner),
    /// so the panel grew from a corner of the window instead of the picked item (11 Nov 2026).
    public static func origin(media: CGRect, about anchor: CGPoint, origin: CGRect) -> (scale: CGFloat, shift: CGPoint)? {
        guard media.width > 0, media.height > 0, origin.width > 0, origin.height > 0 else { return nil }
        let s = min(origin.width / media.width, origin.height / media.height)
        // Where the picture's centre lands after scaling about the anchor, then onto the item's.
        let scaled = CGPoint(x: anchor.x + (media.midX - anchor.x) * s, y: anchor.y + (media.midY - anchor.y) * s)
        return (s, CGPoint(x: origin.midX - scaled.x, y: origin.midY - scaled.y))
    }

    /// The shift that keeps `center` in place when a layer anchored at `anchor` scales by `scale`
    /// (the panel shrinking a touch in place, with no item to go back into).
    public static func shift(keeping center: CGPoint, about anchor: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(x: (center.x - anchor.x) * (1 - scale), y: (center.y - anchor.y) * (1 - scale))
    }

    /// ‹ and › step through the grid's order and stop at its ends.
    public static func step(_ index: Int, by delta: Int, count: Int) -> Int? {
        let next = index + delta
        return (0..<count).contains(next) ? next : nil
    }

    /// The header's age ("1 day ago", "5 minutes ago").
    public static func age(_ date: Date, now: Date, locale: Locale = Locale(identifier: "en_US")) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.unitsStyle = .full
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        return f.localizedString(for: min(date, now), relativeTo: now)
    }
}
