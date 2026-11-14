// Renders Pane's app icons, all on Apple's icon grid: the tile is 824 of 1024 px, centred, with a
// clear margin round it, as on every macOS icon (Arc's too). The SVGs are made here, from code:
// a continuous-corner squircle (Apple's corner curve) holding three frosted window panes that
// overlap down and to the right, the front one with a sidebar. Each pane's frost is the scene
// behind it, blurred and clipped to the pane, then milked, glossed and rimmed: real backdrop
// blur, not a flat tint. No letters.
// - resources/AppIcon.icns, the bundled icon (Arctic), from a 1024 px render.
// - resources/app-icons/<id>.png, the icons in Settings ▸ Appearance ▸ App Icon, 512 px (Dock
//   tiles top out at 128 pt). arctic.png is the picker's preview of the bundled icon.
// - resources/brand/pane-mark@2x.png (512 px) and pane-mark-mono.png (256 px), BrandMark's images:
//   the tile edge to edge, and the panes alone in black.
// - brand/pane-icon.svg and brand/pane-mark-mono.svg, the sources, for the site.
// The bundled icon was drawn edge to edge until 11 Nov 2026: Finder and the idle Dock fit it onto
// the grid themselves, but where the running app's tile drew the file as it is, the app stood a
// fifth larger than Arc beside it. lint's app-icon-grid rule checks every image.
// WebKit draws them (SVG filters and blending, as Safari would).
//   swift scripts/make-app-icons.swift
// With --ios it draws the iPhone app's instead (14 Nov 2026; upstream's --ios rendered Cra's):
// 1024 px, square and opaque, the tile edge to edge (iOS cuts the corners itself), into
// iOS/Cra/Resources/Assets.xcassets as the app icon (Arctic), its alternates (Midnight, Graphite and
// Rose in the slots upstream named Midnight, Mono and Violet) and the pictures the in-app picker
// shows; and the mark (the tile with its corners, 256 and 512 px) as LaunchMark and WidgetMark.
//   swift scripts/make-app-icons.swift --ios
import AppKit
import WebKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

func n(_ v: Double) -> String { String(format: "%.2f", v).replacingOccurrences(of: ".00", with: "") }

/// Apple's continuous corner (the curve of UIBezierPath's rounded rects and the macOS icon tile),
/// as reconstructed by PaintCode: each corner spans 1.52866 r of both edges, so the curvature
/// eases in instead of jumping as a circular arc's does.
func squircle(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> String {
    let (a, b, c, d, e, f, g) = (1.52866483, 1.08849323, 0.86840689, 0.66993427, 0.06549600, 0.40446551, 0.15885512)
    // Each corner: its point, the direction the path arrives in (u) and leaves in (v), y down.
    let corners: [((Double, Double), (Double, Double), (Double, Double))] = [
        ((x + w, y), (1, 0), (0, 1)), ((x + w, y + h), (0, 1), (-1, 0)),
        ((x, y + h), (-1, 0), (0, -1)), ((x, y), (0, -1), (1, 0)),
    ]
    func p(_ k: (Double, Double, Double), _ t: (Double, Double), _ u: (Double, Double), _ v: (Double, Double)) -> String {
        "\(n(t.0 - k.0 * r * u.0 + k.1 * r * v.0)) \(n(t.1 - k.0 * r * u.1 + k.1 * r * v.1))"
    }
    let tl = corners[3]
    var path = "M\(p((0, a, 0), tl.0, tl.1, tl.2))"
    for (t, u, v) in corners {
        path += "L\(p((a, 0, 0), t, u, v))"
        path += "C\(p((b, 0, 0), t, u, v)) \(p((c, 0, 0), t, u, v)) \(p((d, e, 0), t, u, v))"
        path += "C\(p((f, g, 0), t, u, v)) \(p((g, f, 0), t, u, v)) \(p((e, d, 0), t, u, v))"
        path += "C\(p((0, c, 0), t, u, v)) \(p((0, b, 0), t, u, v)) \(p((0, a, 0), t, u, v))"
    }
    return path + "Z"
}

/// One icon's colours. The tile runs from `top` (top left) to `bottom` (bottom right) with a glow
/// in each of those corners and an orb (`orbIn` to `orbOut`) behind the panes, which their frost
/// blurs; the panes are white frost whose milk runs from `frostTop` to `frostBottom` alpha, edged
/// in `edge`, casting `shadow`. `ink` is the front pane's sidebar.
struct Palette {
    let id: String
    let top: String, bottom: String
    let orbIn: String, orbOut: String
    let glowA: String, glowAOpacity: Double
    let glowB: String, glowBOpacity: Double
    let frostTop: Double, frostBottom: Double
    let edge: String, edgeOpacity: Double
    let shadow: String, shadowOpacity: Double
    let rim: Double
    let ink: Double
}

let palettes = [
    // The signature: arctic glass, cyan sky over deep ocean blue.
    Palette(id: "arctic", top: "#7fd3ff", bottom: "#1f4fd1", orbIn: "#f2fdff", orbOut: "#47d6ff", glowA: "#d4fbff", glowAOpacity: 0.85, glowB: "#3523b8", glowBOpacity: 0.55,
            frostTop: 0.42, frostBottom: 0.16, edge: "#0b2d7a", edgeOpacity: 0.20, shadow: "#06205e", shadowOpacity: 0.42, rim: 0.45, ink: 0.70),
    Palette(id: "midnight", top: "#2b3560", bottom: "#070a18", orbIn: "#c3b4ff", orbOut: "#5a3df0", glowA: "#5b7dff", glowAOpacity: 0.55, glowB: "#7a35e8", glowBOpacity: 0.45,
            frostTop: 0.24, frostBottom: 0.07, edge: "#000000", edgeOpacity: 0.30, shadow: "#000000", shadowOpacity: 0.60, rim: 0.30, ink: 0.50),
    Palette(id: "frost", top: "#f6f9fd", bottom: "#b8cbe2", orbIn: "#ffffff", orbOut: "#8fb7e8", glowA: "#ffffff", glowAOpacity: 1, glowB: "#8cb0dc", glowBOpacity: 0.7,
            frostTop: 0.66, frostBottom: 0.34, edge: "#3d5f88", edgeOpacity: 0.34, shadow: "#24446b", shadowOpacity: 0.32, rim: 0.85, ink: 0.0),
    Palette(id: "rose", top: "#ffc77e", bottom: "#d93a78", orbIn: "#fff6c9", orbOut: "#ff9a3d", glowA: "#fff0b8", glowAOpacity: 0.8, glowB: "#8f2fd0", glowBOpacity: 0.55,
            frostTop: 0.40, frostBottom: 0.15, edge: "#6e0f3c", edgeOpacity: 0.20, shadow: "#5c0b33", shadowOpacity: 0.40, rim: 0.45, ink: 0.70),
    Palette(id: "graphite", top: "#9aa1ab", bottom: "#24272d", orbIn: "#ffffff", orbOut: "#aeb7c3", glowA: "#e4e9f0", glowAOpacity: 0.55, glowB: "#0d0f12", glowBOpacity: 0.60,
            frostTop: 0.34, frostBottom: 0.11, edge: "#000000", edgeOpacity: 0.25, shadow: "#000000", shadowOpacity: 0.50, rim: 0.40, ink: 0.60),
]

/// Three panes, back to front, cascading down and to the right round the tile's centre.
let paneSize = (w: 520.0, h: 404.0, r: 70.0)
let panes = [(152.0, 214.0), (252.0, 310.0), (352.0, 406.0)]
/// How much of the frost each pane has, back to front: the ones behind read as further away.
let paneMilk = [0.62, 0.82, 1.0]
/// The orb behind the panes, peeking out past the back pane's top right.
let orb = (x: 724.0, y: 292.0, r: 156.0)

func iconSVG(_ p: Palette, square: Bool = false) -> String {
    // Square for iOS, which masks the corners itself (no rim along an edge it cuts off).
    let tile = square ? "M0 0H1024V1024H0Z" : squircle(0, 0, 1024, 1024, 230)
    var defs = """
    <clipPath id="tile"><path d="\(tile)"/></clipPath>
    <linearGradient id="bg" x1="0.15" y1="0" x2="0.85" y2="1"><stop offset="0" stop-color="\(p.top)"/><stop offset="1" stop-color="\(p.bottom)"/></linearGradient>
    <radialGradient id="ga" cx="0.2" cy="0.14" r="0.62"><stop offset="0" stop-color="\(p.glowA)" stop-opacity="\(p.glowAOpacity)"/><stop offset="1" stop-color="\(p.glowA)" stop-opacity="0"/></radialGradient>
    <radialGradient id="orb" cx="0.36" cy="0.32" r="0.74"><stop offset="0" stop-color="\(p.orbIn)"/><stop offset="1" stop-color="\(p.orbOut)"/></radialGradient>
    <radialGradient id="gb" cx="0.9" cy="0.94" r="0.66"><stop offset="0" stop-color="\(p.glowB)" stop-opacity="\(p.glowBOpacity)"/><stop offset="1" stop-color="\(p.glowB)" stop-opacity="0"/></radialGradient>
    <linearGradient id="tileRim" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="\(p.rim)"/><stop offset="0.35" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#fff" stop-opacity="\(p.rim * 0.25)"/></linearGradient>
    <linearGradient id="rim" x1="0" y1="0" x2="0.3" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.95"/><stop offset="0.5" stop-color="#fff" stop-opacity="0.35"/><stop offset="1" stop-color="#fff" stop-opacity="0.18"/></linearGradient>
    <linearGradient id="gloss" x1="0" y1="0" x2="0.62" y2="0.7"><stop offset="0" stop-color="#fff" stop-opacity="0.34"/><stop offset="0.5" stop-color="#fff" stop-opacity="0.06"/><stop offset="0.51" stop-color="#fff" stop-opacity="0"/></linearGradient>
    <filter id="frost" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="22"/></filter>
    <filter id="shadow" x="-30%" y="-30%" width="160%" height="170%"><feGaussianBlur stdDeviation="26"/></filter>
    """
    var body = """
    <g id="s0"><rect width="1024" height="1024" fill="url(#bg)"/><rect width="1024" height="1024" fill="url(#ga)"/><rect width="1024" height="1024" fill="url(#gb)"/><circle cx="\(n(orb.x))" cy="\(n(orb.y))" r="\(n(orb.r))" fill="url(#orb)"/></g>
    """
    for (i, (x, y)) in panes.enumerated() {
        let shape = squircle(x, y, paneSize.w, paneSize.h, paneSize.r)
        let milk = paneMilk[i]
        defs += """
        <clipPath id="c\(i)"><path d="\(shape)"/></clipPath>
        <linearGradient id="m\(i)" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="\(n(p.frostTop * milk))"/><stop offset="1" stop-color="#fff" stop-opacity="\(n(p.frostBottom * milk))"/></linearGradient>
        """
        let behind = "<use href=\"#s0\"/>" + (0..<i).map { "<use href=\"#p\($0)\"/>" }.joined()
        var pane = """
        <g id="p\(i)">
        <path d="\(shape)" transform="translate(0 \(n(18 + 8 * Double(i))))" fill="\(p.shadow)" opacity="\(n(p.shadowOpacity * (0.75 + 0.25 * milk)))" filter="url(#shadow)"/>
        <g clip-path="url(#c\(i))"><g filter="url(#frost)">\(behind)</g>
        <rect x="\(n(x))" y="\(n(y))" width="\(n(paneSize.w))" height="\(n(paneSize.h))" fill="url(#m\(i))"/>
        """
        if i == panes.count - 1 {
            // The front pane is a browser window: a sidebar with three tabs, then the page.
            let side = 146.0
            pane += """
            <rect x="\(n(x))" y="\(n(y))" width="\(n(side))" height="\(n(paneSize.h))" fill="#fff" fill-opacity="\(n(0.16 * p.ink + 0.04))"/>
            <rect x="\(n(x + side - 1))" y="\(n(y))" width="2.5" height="\(n(paneSize.h))" fill="\(p.ink > 0 ? "#fff" : p.edge)" fill-opacity="\(n(p.ink > 0 ? p.ink * 0.75 : 0.22))"/>
            """
            for (k, wide) in [(0, 78.0), (1, 64.0), (2, 72.0)] {
                pane += "<rect x=\"\(n(x + 30))\" y=\"\(n(y + 62 + Double(k) * 44))\" width=\"\(n(wide * 1.1))\" height=\"18\" rx=\"9\" fill=\"\(p.ink > 0 ? "#fff" : p.edge)\" fill-opacity=\"\(n((p.ink > 0 ? p.ink : 0.22) * (k == 0 ? 1 : 0.62)))\"/>"
            }
        }
        pane += """
        <rect x="\(n(x))" y="\(n(y))" width="\(n(paneSize.w))" height="\(n(paneSize.h))" fill="url(#gloss)"/></g>
        <path d="\(shape)" fill="none" stroke="\(p.edge)" stroke-opacity="\(p.edgeOpacity)" stroke-width="2"/>
        <path d="\(shape)" fill="none" stroke="url(#rim)" stroke-width="3" clip-path="url(#c\(i))"/>
        </g>
        """
        body += pane
    }
    if !square { body += "<path d=\"\(tile)\" fill=\"none\" stroke=\"url(#tileRim)\" stroke-width=\"8\"/>" }
    return #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="64" height="64"><defs>"#
        + defs.replacingOccurrences(of: "\n", with: "") + "</defs><g clip-path=\"url(#tile)\">"
        + body.replacingOccurrences(of: "\n", with: "") + "</g></svg>"
}

/// The panes alone, outlined in black (currentColor in brand/), the front one filled: the mono mark.
func monoSVG(color: String) -> String {
    let inset = 60.0
    let scale = (1024 - 2 * inset) / (panes[2].0 + paneSize.w - panes[0].0)
    var out = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="64" height="64">"#
    out += "<g transform=\"translate(\(n(inset - panes[0].0 * scale)) \(n(512 - (panes[0].1 + (panes[2].1 + paneSize.h - panes[0].1) / 2) * scale))) scale(\(n(scale)))\">"
    for (i, (x, y)) in panes.enumerated() {
        let shape = squircle(x, y, paneSize.w, paneSize.h, paneSize.r)
        out += i == panes.count - 1
            ? "<path d=\"\(shape)\" fill=\"\(color)\"/>"
            : "<path d=\"\(shape)\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"34\"/>"
    }
    return out + "</g></svg>"
}

/// One icon to draw: its SVG on the grid at `pixels` a side, handed to `write`.
struct Job {
    let id: String
    let svg: String
    let pixels: Int
    /// On Apple's grid (app icons), or edge to edge (BrandMark's images).
    var grid = true
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
        let sized = job.svg.replacingCharacters(in: tag, with: job.grid
            ? #"style="display:block;width:80.46875vw;height:80.46875vw;margin:9.765625vw""#
            : #"style="display:block;width:100vw;height:100vw;margin:0""#)
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

func writeSource(_ svg: String, _ name: String) {
    let out = root.appendingPathComponent("brand/\(name).svg")
    try! FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! (svg + "\n").write(to: out, atomically: true, encoding: .utf8)
    print("wrote \(out.path)")
}

let bundled = iconSVG(palettes[0])
let forIOS = CommandLine.arguments.contains("--ios")
if !forIOS {
    writeSource(bundled, "pane-icon")
    writeSource(monoSVG(color: "currentColor"), "pane-mark-mono")
    // Icons left from Cra (Segments, Mono, Violet) go: the picker lists only Pane's.
    for old in ["segments", "mono", "violet"] {
        try? FileManager.default.removeItem(at: root.appendingPathComponent("resources/app-icons/\(old).png"))
    }
}

// MARK: iPhone (--ios)

let iosCatalog = root.appendingPathComponent("iOS/Cra/Resources/Assets.xcassets")
/// The iOS icon set each palette fills: the app's own icon, and the alternates by the names
/// upstream gave them (MobileAppIcon's cases; their labels are Pane's).
let iosIcons = [("AppIcon", "arctic"), ("AppIcon-Midnight", "midnight"), ("AppIcon-Mono", "graphite"), ("AppIcon-Violet", "rose")]

/// Redrawn without an alpha channel: iOS (and App Store Connect) wants an opaque icon.
func opaque(_ rep: NSBitmapImageRep) -> Data {
    let px = rep.pixelsWide
    let context = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: px, height: px))
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

func writeIOSIcon(_ name: String, _ rep: NSBitmapImageRep) {
    let png = opaque(rep)
    // The sets' Contents.json name these files already.
    for (folder, file) in [("\(name).appiconset", "AppIcon.png"), ("\(name)-Preview.imageset", "icon.png")] {
        let out = iosCatalog.appendingPathComponent(folder).appendingPathComponent(file)
        try! png.write(to: out)
        print("wrote \(out.path) (\(rep.pixelsWide) px)")
    }
}

/// The mark (the tile with its corners, clear around them) at 1x or 2x, as the launch screen's and
/// the widgets' image set.
func writeIOSMark(_ rep: NSBitmapImageRep, scale: Int) {
    for set in [iosCatalog.appendingPathComponent("LaunchMark.imageset"),
                root.appendingPathComponent("iOS/CraWidgets/Assets.xcassets/WidgetMark.imageset")] {
        for old in ["cra-mark.png", "cra-mark@2x.png"] { try? FileManager.default.removeItem(at: set.appendingPathComponent(old)) }
        writePNG(rep, to: set.appendingPathComponent(scale == 1 ? "pane-mark.png" : "pane-mark@2x.png"))
        let info = #"  "info" : { "author" : "xcode", "version" : 1 }"#
        try! """
        {
          "images" : [
            { "filename" : "pane-mark.png", "idiom" : "universal", "scale" : "1x" },
            { "filename" : "pane-mark@2x.png", "idiom" : "universal", "scale" : "2x" }
          ],
        \(info)
        }

        """.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    }
}

let iosJobs = iosIcons.map { name, id in
    Job(id: name, svg: iconSVG(palettes.first { $0.id == id }!, square: true), pixels: 1024, grid: false) { writeIOSIcon(name, $0) }
} + [Job(id: "mark", svg: bundled, pixels: 256, grid: false) { writeIOSMark($0, scale: 1) },
     Job(id: "mark@2x", svg: bundled, pixels: 512, grid: false) { writeIOSMark($0, scale: 2) }]

let jobs = forIOS ? iosJobs : [Job(id: "AppIcon", svg: bundled, pixels: 1024, write: writeICNS)]
    + palettes.map { p in
        Job(id: p.id, svg: iconSVG(p), pixels: 512) { writePNG($0, to: root.appendingPathComponent("resources/app-icons/\(p.id).png")) }
    }
    + [Job(id: "mark", svg: bundled, pixels: 512, grid: false) { writePNG($0, to: root.appendingPathComponent("resources/brand/pane-mark@2x.png")) },
       Job(id: "mark-mono", svg: monoSVG(color: "#000"), pixels: 256, grid: false) {
           writePNG($0, to: root.appendingPathComponent("resources/brand/pane-mark-mono.png"))
       }]

let app = NSApplication.shared
let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 256, height: 256), styleMask: .borderless, backing: .buffered, defer: false)
window.backingType = .buffered
let renderer = Renderer(jobs)
window.contentView = renderer.view
window.orderBack(nil)
renderer.next()
app.run()
