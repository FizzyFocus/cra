import SwiftUI

/// Pane's mark: the app icon's tile edge to edge (brand/pane-icon.svg) and the panes alone in black,
/// rendered into resources/brand by scripts/make-app-icons.swift.
struct BrandMark: View {
    var size: CGFloat = 48
    var mono = false

    private static let colour: NSImage? = load("pane-mark@2x")
    private static let monoImage: NSImage? = load("pane-mark-mono")

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "brand") else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        if let img = mono ? BrandMark.monoImage : BrandMark.colour {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityLabel("Pane")
        }
    }
}
