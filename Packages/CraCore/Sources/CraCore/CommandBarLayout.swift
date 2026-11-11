import CoreGraphics

/// The command bar's two shapes. ⌘T, ⌘L and the menus open the palette, centred in the window.
/// A click on the address field opens a dropdown instead (Arc 1.172, 10 Nov 2026): a narrow panel
/// whose own field lies over the address field, the current address selected in it, with the
/// suggestions and history running down from it. It's about 360 pt wide, wider than the sidebar's
/// field, and it never becomes the full palette.
public enum CommandBarLayout {
    public struct Metrics: Equatable, Sendable {
        /// The input row.
        public var fieldHeight: Double
        public var rowHeight: Double
        public var rowGap: Double
        /// Above the first row.
        public var listTop: Double
        /// Under the last row.
        public var listBottom: Double
        /// The typed text's size.
        public var fontSize: Double
        /// The panel's corners.
        public var corner: Double
        /// The rows' inset from the panel's sides.
        public var rowInset: Double

        /// The panel's height with `rows` suggestions.
        public func height(rows: Int) -> Double {
            rows == 0 ? fieldHeight : fieldHeight + listTop + Double(rows) * rowHeight + Double(rows - 1) * rowGap + listBottom
        }
    }

    /// The reference's palette.
    public static let palette = Metrics(fieldHeight: 64, rowHeight: 46, rowGap: 4, listTop: 6, listBottom: 12,
                                        fontSize: 18, corner: 12, rowInset: 10)
    /// The address field's dropdown.
    public static let dropdown = Metrics(fieldHeight: 40, rowHeight: 34, rowGap: 2, listTop: 4, listBottom: 6,
                                         fontSize: 14, corner: 10, rowInset: 6)

    /// The dropdown's width.
    public static let dropdownWidth: Double = 360
    /// How far the dropdown reaches past the field's left edge.
    public static let dropdownLead: Double = 6
    /// The least room between the dropdown and the window's sides.
    public static let windowMargin: Double = 8

    /// The dropdown's frame (y up, screen points) for an address field at `field` in a window at
    /// `window`, with `rows` suggestions: from just left of the field, its input row centred on the
    /// field so the typed text sits where the address was, and inside the window.
    public static func dropdownFrame(field: CGRect, window: CGRect, rows: Int) -> CGRect {
        let m = dropdown
        let w = min(max(dropdownWidth, field.width + 2 * dropdownLead), max(0, window.width - 2 * windowMargin))
        let x = min(max(field.minX - dropdownLead, window.minX + windowMargin), window.maxX - w - windowMargin)
        let top = (field.midY + m.fieldHeight / 2).rounded()
        let h = m.height(rows: rows)
        return CGRect(x: x, y: top - h, width: w, height: h)
    }
}
