// Renders Cra's app icons from the brand marks (brand/*.svg), all on Apple's icon grid: the tile
// is 824 of 1024 px, centred, with a clear margin round it, as on every macOS icon (Arc's too).
// - resources/AppIcon.icns, the bundled icon (Segments), from a 1024 px render.
// - resources/app-icons/<id>.png, the alternates in Settings ▸ General ▸ App Icon, 512 px (Dock
//   tiles top out at 128 pt). segments.png is the picker's preview of the bundled icon.
// The bundled icon was drawn edge to edge until 11 Nov 2026: Finder and the idle Dock fit it onto
// the grid themselves, but where the running app's tile drew the file as it is, Cra stood a fifth
// larger than Arc beside it. lint's app-icon-grid rule checks every image.
// WebKit draws them so the ribbons' multiply blending survives (see brand/README.md).
//   swift scripts/make-app-icons.swift
import AppKit
import WebKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
func brand(_ name: String) -> String { try! String(contentsOf: root.appendingPathComponent("brand/\(name).svg"), encoding: .utf8) }

let sand = ##"<stop offset="0" stop-color="#f2e3c4"/><stop offset="1" stop-color="#e8d3aa"/>"##
let segments = brand("cra-segments-icon")
// The mono mark's ribbons, white, with the icon's drop shadow under them.
let monoRibbons = brand("cra-segments-mono")
    .replacingOccurrences(of: #"^<svg[^>]*>"#, with: "", options: .regularExpression)
    .replacingOccurrences(of: "</svg>", with: "")
    .replacingOccurrences(of: "currentColor", with: "#fff")
let shadow = segments.range(of: #"<g opacity=".18".*?</g>"#, options: .regularExpression).map { String(segments[$0]) }!
// The 19-wide white edge under the ribbons, and the four coloured ribbons (12 wide, multiplied).
let edge = segments.ranges(of: #/<path [^>]*stroke="#fff" stroke-width="19"[^>]*/>/#).map { String(segments[$0]) }.joined()
let ribbons = segments.ranges(of: #/<path [^>]*stroke-width="12"[^>]*/>/#).map { String(segments[$0]) }.joined()
// Arc's family (#259): yellow, green, coral, blue become warm, magenta, orchid, blue-violet.
let violetRibbons = [("#f6c34a", "#f3b985"), ("#4fbe7e", "#e438a7"), ("#f0574f", "#c33bd1"), ("#3f6df5", "#7b5cff")]
    .reduce(ribbons) { $0.replacingOccurrences(of: $1.0, with: $1.1) }

let icons: [String: String] = [
    // Dark tile; on dark, the ribbons blend normally (brand/README.md).
    "segments": segments,
    "midnight": segments
        .replacingOccurrences(of: sand, with: ##"<stop offset="0" stop-color="#2c2e36"/><stop offset="1" stop-color="#16171b"/>"##)
        .replacingOccurrences(of: "mix-blend-mode:multiply", with: "mix-blend-mode:normal"),
    // The shadow follows the 12-wide ribbons here, not the 19-wide white edge.
    "mono": ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64"><defs><linearGradient id="t" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#5a84f8"/><stop offset="1" stop-color="#2f58d8"/></linearGradient></defs><rect width="64" height="64" rx="14.3" fill="url(#t)"/><g transform="translate(3.84 3.84) scale(0.88)">"##
        + shadow.replacingOccurrences(of: #"stroke-width="19""#, with: #"stroke-width="12""#) + monoRibbons + "</g></svg>",
    // Arc's flat #100146 tile, with the edge in the #220a7e of the rim round Arc's mark. The
    // ribbons are isolated, so multiply darkens only where they overlap; against the dark
    // edge it would turn them almost black.
    "violet": ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64"><rect width="64" height="64" rx="14.3" fill="#100146"/><g transform="translate(3.84 3.84) scale(0.88)">"##
        + shadow + edge.replacingOccurrences(of: ##"stroke="#fff""##, with: ##"stroke="#220a7e""##)
        + #"<g style="isolation:isolate">"# + violetRibbons + "</g></g></svg>",
]

/// One icon to draw: its SVG on the grid at `pixels` a side, handed to `write`.
struct Job {
    let id: String
    let svg: String
    let pixels: Int
    let write: (NSBitmapImageRep) -> Void
}

final class Renderer: NSObject, WKNavigationDelegate {
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 256, height: 256))
    var queue: [Job]
    init(_ jobs: [Job]) { queue = jobs }

    func next() {
        guard let job = queue.first else { exit(0) }
        // Half the pixels in points: a Retina screen draws it 1:1, a 1x one is scaled by the snapshot.
        view.window?.setContentSize(NSSize(width: job.pixels / 2, height: job.pixels / 2))
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        // Only the <svg> tag's size: the tile <rect> has the same attributes.
        let tag = job.svg.range(of: #"width="64" height="64""#)!
        let sized = job.svg.replacingCharacters(in: tag, with: #"style="display:block;width:80.46875vw;height:80.46875vw;margin:9.765625vw""#)
        view.loadHTMLString("<!doctype html><html><body style='margin:0;background:transparent;overflow:hidden'>\(sized)</body></html>", baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let job = queue.removeFirst()
        // The job's pixels on any display.
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Double(job.pixels) / Double(webView.window?.backingScaleFactor ?? 2))
        webView.takeSnapshot(with: config) { image, error in
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                fatalError("\(job.id): \(error?.localizedDescription ?? "no image")")
            }
            let rep = NSBitmapImageRep(cgImage: cg)
            guard rep.pixelsWide == job.pixels else { fatalError("\(job.id): \(rep.pixelsWide) px, not \(job.pixels)") }
            job.write(rep)
            self.next()
        }
    }
}

func writePNG(_ rep: NSBitmapImageRep, to out: URL) {
    try! FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! rep.representation(using: .png, properties: [:])!.write(to: out)
    print("wrote \(out.path) (\(rep.pixelsWide) px)")
}

/// An icon's premultiplied RGBA, in the render's own colour space (nothing converted).
struct Pixels {
    let px: Int
    let bytes: [UInt8]
    let space: CGColorSpace

    init(px: Int, bytes: [UInt8], space: CGColorSpace) {
        self.px = px
        self.bytes = bytes
        self.space = space
    }

    init(_ image: CGImage) {
        px = image.width
        space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        var bytes = [UInt8](repeating: 0, count: px * px * 4)
        let ctx = CGContext(data: &bytes, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
        self.bytes = bytes
    }

    /// Half the size, each pixel the average of the four under it: the tile's edge keeps its true
    /// coverage at every size (CoreGraphics' own downscale left the 32 px edge half as opaque).
    func halved() -> Pixels {
        let n = px / 2, row = px * 4
        var out = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                for c in 0..<4 {
                    let i = 2 * y * row + 2 * x * 4 + c
                    let sum = Int(bytes[i]) + Int(bytes[i + 4]) + Int(bytes[i + row]) + Int(bytes[i + row + 4])
                    out[(y * n + x) * 4 + c] = UInt8((sum + 2) / 4)
                }
            }
        }
        return Pixels(px: n, bytes: out, space: space)
    }

    func png() -> Data {
        var copy = bytes
        let ctx = CGContext(data: &copy, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    }
}

/// AppIcon.icns from the 1024 px render, through iconutil.
func writeICNS(_ full: NSBitmapImageRep) {
    var sizes = [1024: Pixels(full.cgImage!)]
    for px in [512, 256, 128, 64, 32, 16] { sizes[px] = sizes[px * 2]!.halved() }
    let set = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
    try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: set) }
    for pt in [16, 32, 128, 256, 512] {
        try! sizes[pt]!.png().write(to: set.appendingPathComponent("icon_\(pt)x\(pt).png"))
        try! sizes[pt * 2]!.png().write(to: set.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
    }
    let out = root.appendingPathComponent("resources/AppIcon.icns")
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", set.path, "-o", out.path]
    try! iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed (\(iconutil.terminationStatus))") }
    print("wrote \(out.path) (16 to 1024 px)")
}

let jobs = [Job(id: "AppIcon", svg: segments, pixels: 1024, write: writeICNS)]
    + icons.sorted { $0.key < $1.key }.map { id, svg in
        Job(id: id, svg: svg, pixels: 512) { writePNG($0, to: root.appendingPathComponent("resources/app-icons/\(id).png")) }
    }

let app = NSApplication.shared
let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 256, height: 256), styleMask: .borderless, backing: .buffered, defer: false)
window.backingType = .buffered
let renderer = Renderer(jobs)
window.contentView = renderer.view
window.orderBack(nil)
renderer.next()
app.run()
