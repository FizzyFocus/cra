// sample-png.swift <png> <x> <y> <w> <h>: the average colour of that pixel rect of the PNG (inset by a tenth on
// each side, away from the card's rounded corners) and the share of it that is near white, for scenario.sh's
// expect-pixels. Prints "avg=#rrggbb white=<0…1>".
import AppKit

let a = CommandLine.arguments
guard a.count == 6, let image = NSImage(contentsOfFile: a[1]),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let x = Int(a[2]), let y = Int(a[3]), let w = Int(a[4]), let h = Int(a[5]), w > 0, h > 0 else {
    print("usage: sample-png <png> <x> <y> <w> <h>"); exit(2)
}
let rep = NSBitmapImageRep(cgImage: cg)
let x0 = max(0, x + w / 10), y0 = max(0, y + h / 10)
let x1 = min(rep.pixelsWide, x + w - w / 10), y1 = min(rep.pixelsHigh, y + h - h / 10)
guard x1 > x0, y1 > y0 else { print("rect outside the image \(rep.pixelsWide)x\(rep.pixelsHigh)"); exit(2) }
var r = 0.0, g = 0.0, b = 0.0, white = 0, n = 0
for py in stride(from: y0, to: y1, by: 4) {
    for px in stride(from: x0, to: x1, by: 4) {
        guard let c = rep.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) else { continue }
        r += c.redComponent; g += c.greenComponent; b += c.blueComponent; n += 1
        if c.redComponent > 0.94, c.greenComponent > 0.94, c.blueComponent > 0.94 { white += 1 }
    }
}
guard n > 0 else { print("no pixels"); exit(2) }
let hex = String(format: "#%02x%02x%02x", Int(r / Double(n) * 255), Int(g / Double(n) * 255), Int(b / Double(n) * 255))
print("avg=\(hex) white=\(String(format: "%.2f", Double(white) / Double(n)))")
