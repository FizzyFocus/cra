import CoreGraphics
import CraCore
import Testing

/// A click on the address field opens a 360 pt dropdown over the field, not the palette (10 Nov 2026).
struct CommandBarLayoutTests {
    let window = CGRect(x: 100, y: 100, width: 1200, height: 800)

    @Test func dropdownLiesOverTheSidebarField() {
        // The sidebar's field: 10 pt in, 36 pt tall, near the window's top.
        let field = CGRect(x: 110, y: 850, width: 220, height: 36)
        let f = CommandBarLayout.dropdownFrame(field: field, window: window, rows: 5)
        #expect(f.width == 360)
        #expect(f.minX == 108, "kept 8 pt inside the window")
        #expect(f.maxY == 888, "the input row centred on the field (868 + 20)")
        let expected: CGFloat = 228 // 40 + 4 + 5 × 34 + 4 × 2 + 6
        #expect(f.height == expected)
        #expect(f.width < 766, "never the palette's width")
    }

    @Test func dropdownGrowsWithAWideFieldAndStaysInTheWindow() {
        let wide = CGRect(x: 600, y: 850, width: 600, height: 30)
        let f = CommandBarLayout.dropdownFrame(field: wide, window: window, rows: 0)
        #expect(f.width == 612)
        #expect(f.minX == 594)
        #expect(f.height == 40, "the input row alone")
        let nearRight = CGRect(x: 1150, y: 850, width: 120, height: 30)
        #expect(CommandBarLayout.dropdownFrame(field: nearRight, window: window, rows: 1).maxX == window.maxX - 8)
    }

    @Test func paletteKeepsTheReferenceSizes() {
        #expect(CommandBarLayout.palette.height(rows: 0) == 64)
        let full: Double = 328 // 64 + 5 × 46 + 4 × 4 + 18
        #expect(CommandBarLayout.palette.height(rows: 5) == full)
        #expect(CommandBarLayout.dropdown.fontSize < CommandBarLayout.palette.fontSize)
    }
}
