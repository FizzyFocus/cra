import Foundation

/// The theme picker's feel under the pointer: the colour pad's handle is drawn to the six cardinal
/// hues, to the pad's neutral centre and to the Pastel catalogue's colours as it comes near them,
/// and the sliders tick every tenth. The picker plays a haptic tap on each snap and tick.
public enum ThemePickerSnap {
    /// Red, yellow, green, cyan, blue and magenta, in degrees on the pad (SpaceColorWheel).
    public static let cardinalHues: [Double] = [0, 60, 120, 180, 240, 300]
    /// How near a cardinal hue the handle is drawn to it, in degrees.
    public static let hueReach = 3.5
    /// Below this saturation the handle sits in the neutral centre.
    public static let neutralReach = 0.05
    /// How near a catalogue colour the handle lands on it, as a share of the pad's radius.
    public static let swatchReach = 0.05
    /// Hues are only drawn where there is colour to see.
    static let hueMinSaturation = 0.12

    public enum Target: Equatable {
        case neutral
        case swatch(String)
        case hue(Double)
    }

    /// Where the pad's handle lands for the pointer at `hue` (degrees) and `saturation` (0…1),
    /// and what drew it there; nil when nothing is near. A swatch hands back its own colour.
    public static func snap(hue: Double, saturation: Double, swatches: [String] = SpaceColorPresets.pastel)
        -> (hue: Double, saturation: Double, target: Target?) {
        let h = normalized(hue)
        if saturation < neutralReach { return (h, 0, .neutral) }
        let p = point(hue: h, saturation: saturation)
        var best: (hex: String, d: Double, hue: Double, sat: Double)?
        for hex in swatches {
            let w = SpaceColorWheel.hsb(hex)
            let q = point(hue: w.hue, saturation: w.saturation)
            let d = hypot(p.x - q.x, p.y - q.y)
            if d <= swatchReach, d < (best?.d ?? .infinity) { best = (hex, d, w.hue, w.saturation) }
        }
        if let b = best { return (b.hue, b.sat, .swatch(b.hex)) }
        if saturation >= hueMinSaturation, let c = cardinalHues.first(where: { angle(h, $0) <= hueReach }) {
            return (c, saturation, .hue(c))
        }
        return (h, saturation, nil)
    }

    /// The slider detents a move from `old` to `new` crosses or lands on (every `step`, ends
    /// included): a tick when it is at least one.
    public static func crossesDetent(from old: Double, to new: Double, step: Double = 0.1) -> Bool {
        guard old != new, step > 0 else { return false }
        let a = (old / step + 1e-9).rounded(.down), b = (new / step + 1e-9).rounded(.down)
        if a != b { return true }
        // Landing exactly on a detent from either side.
        return abs(new / step - (new / step).rounded()) < 1e-9
    }

    private static func normalized(_ h: Double) -> Double { (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }

    private static func angle(_ a: Double, _ b: Double) -> Double {
        let d = abs(normalized(a) - normalized(b))
        return min(d, 360 - d)
    }

    private static func point(hue: Double, saturation: Double) -> (x: Double, y: Double) {
        let r = hue * .pi / 180
        return (saturation * cos(r), saturation * sin(r))
    }
}

/// Where the theme picker opens: beside what opened it, its arrow at that row or point, the card
/// kept inside the window (screen coordinates, y up).
public enum ThemePickerPlacement {
    /// The arrow stays on the card's straight edge, clear of its rounded corners (22 pt) and of
    /// its own width (11 pt either side).
    public static let arrowInset: Double = 36

    /// The card's top and the arrow's distance down from it, for a card `height` tall pointing at
    /// `sourceY`, inside `windowMinY`…`windowMaxY` less `margin`.
    public static func place(sourceY: Double, cardHeight: Double, windowMinY: Double, windowMaxY: Double,
                             margin: Double = 6) -> (top: Double, arrowY: Double) {
        var top = sourceY + cardHeight / 2
        top = min(top, windowMaxY - margin)
        top = max(top, windowMinY + margin + cardHeight)
        let arrow = min(max(top - sourceY, arrowInset), cardHeight - arrowInset)
        return (top, arrow)
    }
}

/// A row of cards reordered by dragging one (Library ▸ Spaces): the slot the dragged card is over
/// and the order the others make room in, live while it moves.
public enum CardReorder {
    /// The slot a card that started at `from` is over after moving `offset` points along a row
    /// whose cards are `pitch` apart.
    public static func slot(from: Int, offset: Double, pitch: Double, count: Int) -> Int {
        guard count > 0, pitch > 0 else { return 0 }
        return min(max(0, from + Int((offset / pitch).rounded())), count - 1)
    }

    /// `ids` with the card at `from` moved to `to`.
    public static func order<T>(_ ids: [T], moving from: Int, to: Int) -> [T] {
        guard ids.indices.contains(from) else { return ids }
        var out = ids
        let item = out.remove(at: from)
        out.insert(item, at: min(max(0, to), out.count))
        return out
    }
}
