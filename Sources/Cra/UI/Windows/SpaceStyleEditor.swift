import AppKit
import SwiftUI

/// Arc 1.171's theme editor (SpaceStyleEditor), which Edit Theme Color… opens beside the
/// sidebar and the Edit Space sheet shows inline. Measured from 2x captures of an offline Arc
/// (1 Nov): a 355 × 503 pt card, the window behind it darkened by ~58%; a 340 pt dotted colour pad
/// with Auto / Light / Dark on top and − / + (one to three colours) at the bottom; nine swatches
/// between paging arrows, five pages of Arc's catalog colours (SpaceColorPresets); a wave slider
/// for the intensity and a dotted dial for the grain. Every change goes to `onChange` at once (the
/// caller previews it); nothing here writes. Like Arc's editor state it keeps the pad's colours,
/// the intensity, the grain and Auto / Light / Dark, and builds the theme from them
/// (SpaceThemeVariants): one colour is Arc's one-dot fill, two or three a gradient, and Auto
/// always gets a light and a dark half (#155).
///
/// Below Arc's controls Cra adds an Opacity slider (ThemeOpacity): from a mostly see-through window
/// over the blurred desktop to a solid one, saved with the theme. Under the pointer the pad's handle
/// is drawn to the cardinal hues, the neutral centre and the Pastel colours, and the sliders tick
/// every tenth, each with a haptic tap (ThemePickerSnap).
///
/// The card follows the look being picked (CreateSpaceTones.pickerIsLight): in Light, and before
/// any colour is picked on a light Mac, black ink on a light card (the colours lifted toward white);
/// otherwise white ink on the space's colours darkened ~58%. `arrowY` points a popover arrow from
/// the card's leading edge at what opened it (Create a Space's "Choose a Theme" row), or from its
/// trailing edge when the card opened on the left of it (`arrowOnTrailing`, 13 Nov 2026).
struct SpaceStyleEditor: View {
    @State private var theme: SpaceTheme
    @State private var pad: PadState
    let onChange: (SpaceTheme) -> Void
    var arrowY: CGFloat? = nil
    var arrowOnTrailing = false

    init(theme: SpaceTheme, arrowY: CGFloat? = nil, arrowOnTrailing: Bool = false, onChange: @escaping (SpaceTheme) -> Void) {
        self.arrowY = arrowY
        self.arrowOnTrailing = arrowOnTrailing
        _theme = State(initialValue: theme)
        // A one-colour theme stores its colour twice (a flat fill): one handle on the pad.
        let key = theme.key ?? (theme.solid || Set(theme.colors).count == 1 ? Array(theme.colors.prefix(1)) : theme.colors)
        _pad = State(initialValue: PadState(key: key, intensity: theme.intensity, noise: theme.noise, appearance: theme.appearance,
                                            opacity: theme.opacity))
        // The page with the space's colour, else the one shown last (Arc: currentThemeEditorPresetPage).
        let last = UserDefaults.standard.integer(forKey: Self.pageKey)
        _swatchPage = State(initialValue: SpaceColorPresets.page(of: key)
            ?? (SpaceColorPresets.pages.indices.contains(last) ? last : 0))
        self.onChange = onChange
    }

    private static let pageKey = "themeEditorPresetPage"
    @State private var swatchPage: Int
    /// The card: Arc's 355 × 503 pt, and the Opacity row under it.
    static let cardSize = CGSize(width: 355, height: 541)

    var body: some View {
        VStack(spacing: 0) {
            ColorPad(pad: $pad)
                .frame(width: 340, height: 340)
                .padding(.top, 9)
            HStack(spacing: 0) {
                pageArrow("chevron.left", to: swatchPage - 1, label: "Move to previous preset page.")
                HStack(spacing: 5.5) {
                    let page = SpaceColorPresets.pages[swatchPage]
                    ForEach(Array(page.swatches.enumerated()), id: \.offset) { i, colors in
                        Button { pad.key = colors } label: {
                            Circle()
                                .fill(LinearGradient(colors: colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 24, height: 24)
                                .contentShape(Circle())
                        }
                        .buttonStyle(ColorPillButtonStyle())
                        // Arc: "Set space color to Catalog color: … ColorPickerBrandN".
                        .accessibilityLabel("Set space color to \(page.name(i))")
                    }
                }
                pageArrow("chevron.right", to: swatchPage + 1, label: "Move to next preset page.")
            }
            .padding(.top, 16.75)
            HStack(spacing: 0) {
                WaveSlider(value: $pad.intensity).frame(width: 224, height: 50)
                Spacer(minLength: 0)
                GrainDial(value: $pad.noise).frame(width: 70, height: 70)
            }
            .frame(height: 70)
            .padding(.leading, 17)
            .padding(.trailing, 23)
            .padding(.top, 22)
            OpacitySlider(value: Binding(get: { pad.opacity ?? ThemeOpacity.shown(theme.shown) }, set: { pad.opacity = $0 }))
                .frame(height: 30)
                .padding(.horizontal, 17)
                .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .frame(width: Self.cardSize.width, height: Self.cardSize.height)
        // The card's fill reaches the arrow's depth past its leading edge, so the arrow has
        // something to show: clipped to the card's own frame it was all but gone.
        .background(alignment: arrowOnTrailing ? .trailing : .leading) {
            let d = arrowY == nil ? 0 : PickerCardShape.arrowDepth
            card.frame(width: Self.cardSize.width + d, height: Self.cardSize.height)
                .clipShape(PickerCardShape(arrowY: arrowY, leading: arrowOnTrailing ? 0 : d, trailing: arrowOnTrailing ? d : 0))
                .offset(x: arrowOnTrailing ? d : -d)
        }
        .environment(\.colorScheme, light ? .light : .dark)
        .environment(\.pickerInk, light ? .black : .white)
        .animation(.easeOut(duration: 0.18), value: light)
        // Opening the editor leaves the theme as it is; the first change rebuilds it from the pad.
        .onChange(of: pad) { _, p in
            theme = SpaceThemeVariants.theme(key: p.key, intensity: p.intensity, noise: p.noise, appearance: p.appearance, opacity: p.opacity)
            onChange(theme)
        }
    }

    /// Light or dark, from what is on the pad (CreateSpaceTones.pickerIsLight).
    private var light: Bool {
        CreateSpaceTones.pickerIsLight(key: pad.key, appearance: pad.appearance, systemDark: SystemAppearance.shared.isDark)
    }

    /// The card: the space's own theme, darkened ~58% (Arc: #CDC2A5 behind → #554F37), or lifted
    /// halfway to white for a light look; a near-white card before any colour is picked.
    @ViewBuilder private var card: some View {
        if pad.key.isEmpty, light {
            Color(white: 0.975)
        } else {
            ZStack {
                SpaceBackground(palette: theme.palette)
                light ? Color.white.opacity(0.55) : Color.black.opacity(0.58)
            }
        }
    }

    private func pageArrow(_ symbol: String, to page: Int, label: String) -> some View {
        let ok = SpaceColorPresets.pages.indices.contains(page)
        return PageArrow(symbol: symbol, enabled: ok, label: label) {
            swatchPage = page
            UserDefaults.standard.set(page, forKey: Self.pageKey)
        }
    }
}

/// The ink the picker draws in: white on its dark card, black on its light one.
private struct PickerInkKey: EnvironmentKey {
    static let defaultValue = Color.white
}

extension EnvironmentValues {
    var pickerInk: Color {
        get { self[PickerInkKey.self] }
        set { self[PickerInkKey.self] = newValue }
    }
}

/// The picker's card, 22 pt continuous corners, with a popover arrow on its leading edge at
/// `arrowY` (from the top) pointing at what opened it, or on its trailing edge pointing right.
struct PickerCardShape: Shape {
    var radius: CGFloat = 22
    var arrowY: CGFloat?
    /// How far the shape's rect reaches past the card's leading edge, for the arrow.
    var leading: CGFloat = 0
    /// Or past its trailing edge: the arrow is there instead.
    var trailing: CGFloat = 0
    /// The arrow: NSPopover's (the Extensions popover's) turned to point left from the card's edge.
    static let arrowDepth: CGFloat = 10.5
    static let arrowHalf: CGFloat = 14

    func path(in r: CGRect) -> Path {
        let card = CGRect(x: r.minX + leading, y: r.minY, width: max(0, r.width - leading - trailing), height: r.height)
        let body = Path(roundedRect: card, cornerRadius: radius, style: .continuous)
        guard let arrowY else { return body }
        let y = min(max(card.minY + arrowY, card.minY + radius + Self.arrowHalf), card.maxY - radius - Self.arrowHalf)
        return body.union(trailing > 0 ? Self.arrow(edgeX: card.maxX, y: y, pointingRight: true) : Self.arrow(edgeX: card.minX, y: y))
    }

    /// The popover arrow's outline: shoulders that leave the card's edge along it (concave), sides
    /// that run toward the tip, and a tip rounded over, as NSPopover draws its own (10 Nov 2026).
    /// It starts 1 pt inside the card, so the union has no seam.
    static func arrow(edgeX x0: CGFloat, y: CGFloat, pointingRight: Bool = false) -> Path {
        // Drawn pointing left; mirrored about the edge to point right.
        let d = pointingRight ? -arrowDepth : arrowDepth, h = arrowHalf, inside: CGFloat = pointingRight ? -1 : 1
        var a = Path()
        a.move(to: CGPoint(x: x0 + inside, y: y - h))
        a.addLine(to: CGPoint(x: x0, y: y - h))
        a.addCurve(to: CGPoint(x: x0 - d * 0.76, y: y - h * 0.17),
                   control1: CGPoint(x: x0, y: y - h * 0.55), control2: CGPoint(x: x0 - d * 0.56, y: y - h * 0.31))
        a.addCurve(to: CGPoint(x: x0 - d * 0.76, y: y + h * 0.17),
                   control1: CGPoint(x: x0 - d * 1.03, y: y - h * 0.09), control2: CGPoint(x: x0 - d * 1.03, y: y + h * 0.09))
        a.addCurve(to: CGPoint(x: x0, y: y + h),
                   control1: CGPoint(x: x0 - d * 0.56, y: y + h * 0.31), control2: CGPoint(x: x0, y: y + h * 0.55))
        a.addLine(to: CGPoint(x: x0 + inside, y: y + h))
        a.closeSubpath()
        return a
    }
}

/// A paging arrow: white 0.55, brighter under the pointer with a pointing hand (Arc's
/// SpaceStyleButtonStyle); the arrow past the last page is 0.2 and does neither. Not a SwiftUI
/// Button: a Button keeps the plain arrow pointer whatever pointer style it's given.
private struct PageArrow: View {
    let symbol: String
    let enabled: Bool
    let label: String
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pickerInk) private var ink

    var body: some View {
        let hot = enabled && isHovered
        Image(systemName: symbol).font(.system(size: 15, weight: .medium)).frame(width: 36, height: 30)
            .contentShape(Rectangle())
            .foregroundStyle(ink.opacity(enabled ? (hot ? 0.85 : 0.55) : 0.2))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hot)
            .onHover { isHovered = $0 }
            .onTapGesture { if enabled { action() } }
            .editorPointer(enabled ? .link : nil)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
            .accessibilityAction { if enabled { action() } }
    }
}

/// What the editor's controls set (Arc: SpaceStyleEditor.State's colours, factors and darkModeBiasSetting).
struct PadState: Equatable {
    var key: [String]
    var intensity: Double
    var noise: Double
    /// "auto", "light" or "dark".
    var appearance: String
    /// The Opacity slider's value once moved; nil keeps the look's own (ThemeOpacity).
    var opacity: Double? = nil
}

/// The picker's tap under the fingers: a snap or a slider's tick (ThemePickerSnap).
@MainActor
enum PickerHaptics {
    static func tick() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default) }
}

/// The dotted pad, a colour wheel: a handle's angle (clockwise from three o'clock) is its hue and its
/// distance from the centre its saturation (full at 153 pt), brightness 0.95. A second and third
/// colour follow the first 40° either side; dragging any handle turns the set.
private struct ColorPad: View {
    @Binding var pad: PadState
    @State private var hoveredKnob: Int?
    @State private var draggingKnob: Int?
    /// What the main handle is held by right now (ThemePickerSnap), so each new snap taps once.
    @State private var snappedTo: ThemePickerSnap.Target?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pickerInk) private var ink
    private static let reach: CGFloat = 153

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ink.opacity(0.04))
                Canvas { ctx, s in
                    var p = Path()
                    for x in stride(from: 4.0, to: s.width, by: 4) {
                        for y in stride(from: 4.0, to: s.height, by: 4) { p.addEllipse(in: CGRect(x: x - 0.5, y: y - 0.5, width: 1, height: 1)) }
                    }
                    ctx.fill(p, with: .color(ink.opacity(0.12)))
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
                // Arc: pressing anywhere on the pad brings the main colour there, and it follows the drag.
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in place(handle: 0, at: g.location, centre: centre) }
                    .onEnded { _ in snappedTo = nil })
                if pad.key.isEmpty {
                    Text("Tap to pick a color for this space")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ink.opacity(0.78))
                        .allowsHitTesting(false)
                }
                ForEach(Array(pad.key.prefix(3).enumerated()), id: \.offset) { i, hex in
                    let main = i == 0
                    Circle()
                        .fill(Color(hex: hex))
                        .overlay(Circle().strokeBorder(.white, lineWidth: main ? 4.5 : 2.5))
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                        .frame(width: main ? 44 : 27, height: main ? 44 : 27)
                        // Arc's PadWheel knob: grows under the pointer, shrinks while held (the
                        // swatches' scales); an open hand over it, a closed one while dragging.
                        .scaleEffect(draggingKnob == i ? ColorPillButtonStyle.pressed : hoveredKnob == i ? ColorPillButtonStyle.hovered : 1)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredKnob == i)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: draggingKnob == i)
                        .onHover { inside in
                            if inside { hoveredKnob = i } else if hoveredKnob == i { hoveredKnob = nil }
                        }
                        // Arc: an open hand over a knob, a closed one while dragging it.
                        .editorPointer(draggingKnob == i ? .grabbing : .grab)
                        .position(Self.point(for: hex, centre: centre))
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                // SwiftUI re-reads pointer styles on moves, not drags: hold the closed hand.
                                if #available(macOS 15, *) { NSCursor.closedHand.set() }
                                draggingKnob = i
                                place(handle: i, at: g.location, centre: centre)
                            }
                            .onEnded { _ in
                                draggingKnob = nil
                                snappedTo = nil
                            })
                }
                VStack {
                    AppearanceToggles(appearance: $pad.appearance).padding(.top, 24)
                    Spacer()
                    HStack(spacing: 16) {
                        // Down to none and up to three; a new space starts on none. Taking the last colour
                        // goes back to that unthemed pad: Light, painted the default tint (removingColour).
                        padButton("minus", enabled: !pad.key.isEmpty) {
                            let r = SpaceColorPresets.removingColour(key: pad.key, appearance: pad.appearance, intensity: pad.intensity, noise: pad.noise)
                            var p = pad
                            (p.key, p.appearance, p.intensity, p.noise) = (r.key, r.appearance, r.intensity, r.noise)
                            pad = p
                        }
                        padButton("plus", enabled: pad.key.count < 3) { addColor() }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private func padButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium)).frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(SpaceStyleButtonStyle(opacity: enabled ? 0.55 : 0.18, enabled: enabled))
        .disabled(!enabled)
    }

    /// Handle `i` goes under the pointer; the others keep their place around it. The main handle is
    /// drawn to a cardinal hue, the neutral centre or a Pastel colour near it, with a tap as it lands.
    private func place(handle i: Int, at p: CGPoint, centre c: CGPoint) {
        let dx = p.x - c.x, dy = p.y - c.y
        var angle = atan2(dy, dx) * 180 / .pi - Self.offset(i)
        angle = (angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        var sat = min(1, hypot(dx, dy) / Self.reach)
        var exact: String?
        if i == 0 {
            let snap = ThemePickerSnap.snap(hue: Double(angle), saturation: Double(sat))
            if snap.target != snappedTo {
                if snap.target != nil { PickerHaptics.tick() }
                snappedTo = snap.target
            }
            angle = CGFloat(snap.hue)
            sat = CGFloat(snap.saturation)
            if case .swatch(let hex)? = snap.target { exact = hex }
        }
        let count = max(1, pad.key.count)
        pad.key = (0..<count).map { n in n == 0 && exact != nil ? exact! : Self.hex(hue: angle + Self.offset(n), saturation: sat) }
    }

    /// The next colour beside the first; on an empty pad the first one, at the default colour's place
    /// (Pastel's sky blue), spawned there.
    private func addColor() {
        guard let first = pad.key.first else {
            pad.key = [SpaceColorPresets.firstPadColour]
            PickerHaptics.tick()
            return
        }
        let (h, s) = Self.wheel(first)
        pad.key.append(Self.hex(hue: h + Self.offset(pad.key.count), saturation: s))
    }

    private static func offset(_ i: Int) -> CGFloat { CGFloat(SpaceColorWheel.offset(i)) }

    private static func hex(hue: CGFloat, saturation: CGFloat) -> String {
        SpaceColorWheel.hex(hue: Double(hue), saturation: Double(saturation), brightness: 0.95)
    }

    private static func wheel(_ hex: String) -> (CGFloat, CGFloat) {
        let w = SpaceColorWheel.hsb(hex)
        return (CGFloat(w.hue), CGFloat(w.saturation))
    }

    static func point(for hex: String, centre c: CGPoint) -> CGPoint {
        let (h, s) = wheel(hex)
        let a = h * .pi / 180, r = s * reach
        return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
    }
}

/// Auto (sparkles), Light (sun) and Dark (moon) over the pad; the chosen one on a 32 pt tile.
private struct AppearanceToggles: View {
    @Binding var appearance: String
    @Environment(\.pickerInk) private var ink

    var body: some View {
        HStack(spacing: 7.5) {
            toggle("auto", symbol: "sparkles")
            toggle("light", symbol: "sun.max.fill")
            toggle("dark", symbol: "moon.stars.fill")
        }
    }

    private func toggle(_ value: String, symbol: String) -> some View {
        Button { appearance = value } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ink.opacity(appearance == value ? 0.12 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(SpaceStyleButtonStyle(opacity: appearance == value ? 0.8 : 0.55, enabled: appearance != value))
    }
}

/// The intensity: a wave over a 15 pt track with a white 16 × 46.5 pt thumb; the wave grows with the
/// value and is bright up to the thumb, faint after it.
private struct WaveSlider: View {
    @Binding var value: Double
    @Environment(\.pickerInk) private var ink

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let x = 8 + (w - 16) * CGFloat(value)
            let wave = Path { p in
                let amp = 3 + (h / 2 - 12) * CGFloat(value)
                for px in stride(from: 8.0, through: w - 8, by: 1) {
                    let y = h / 2 - amp * sin((px - 8) / (w - 16) * CGFloat.pi * 14)
                    px == 8 ? p.move(to: CGPoint(x: px, y: y)) : p.addLine(to: CGPoint(x: px, y: y))
                }
            }
            let style = StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
            ZStack(alignment: .leading) {
                Capsule().fill(ink.opacity(0.1)).frame(height: 15)
                wave.stroke(ink.opacity(0.25), style: style)
                wave.stroke(ink.opacity(0.75), style: style).mask(Rectangle().frame(width: x).frame(maxWidth: .infinity, alignment: .leading))
                Capsule().fill(ink).frame(width: 16, height: 46.5).position(x: x, y: h / 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let new = Double(min(max((g.location.x - 8) / (w - 16), 0), 1))
                if ThemePickerSnap.crossesDetent(from: value, to: new) { PickerHaptics.tick() }
                value = new
            })
        }
    }
}

/// The grain: a dark disc showing it, a ring of dots lit from twelve o'clock round to a white knob;
/// turning the knob sets the value one dot (a 24th) at a time, with a haptic tap at each.
private struct GrainDial: View {
    @Binding var value: Double
    @Environment(\.pickerInk) private var ink
    private let count = 24

    var body: some View {
        GeometryReader { geo in
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let knob = value * 2 * .pi - .pi / 2
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    let a = Double(i) / Double(count) * 2 * .pi - .pi / 2
                    Circle()
                        .fill(ink.opacity(Double(i) / Double(count) <= value ? 0.55 : 0.18))
                        .frame(width: 3.5, height: 3.5)
                        .position(x: c.x + 34 * cos(a), y: c.y + 34 * sin(a))
                }
                Circle().fill(.black.opacity(0.12)).overlay(NoiseDisc(amount: value)).clipShape(Circle())
                    .overlay(Circle().strokeBorder(ink.opacity(0.12), lineWidth: 1))
                    .frame(width: 41, height: 41)
                Capsule().fill(ink).frame(width: 4.5, height: 12)
                    .rotationEffect(.radians(knob + .pi / 2))
                    .position(x: c.x + 31 * cos(knob), y: c.y + 31 * sin(knob))
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                var a = atan2(g.location.y - c.y, g.location.x - c.x) + .pi / 2
                if a < 0 { a += 2 * .pi }
                // The grain moves dot by dot round the dial (`count` steps), a tap at each.
                let new = Double((a / (2 * .pi) * CGFloat(count)).rounded()) / Double(count)
                guard new != value else { return }
                // A turn past twelve o'clock jumps to the other end without a tap.
                if abs(new - value) < 0.5 { PickerHaptics.tick() }
                value = new
            })
        }
    }
}

/// Opacity: a track that runs from the checks of a see-through window to solid ink, with the
/// sliders' white thumb; it ticks every tenth and lands on opaque at its end (ThemeOpacity).
private struct OpacitySlider: View {
    @Binding var value: Double
    @Environment(\.pickerInk) private var ink
    private let range = ThemeOpacity.range

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let share = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = 8 + (w - 16) * CGFloat(share)
            ZStack(alignment: .leading) {
                Capsule().fill(ImagePaint(image: Image(nsImage: Self.checks), scale: 0.5)).opacity(0.5).frame(height: 15)
                Capsule().fill(LinearGradient(colors: [ink.opacity(0.05), ink.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 15)
                Capsule().fill(ink).frame(width: 16, height: 28).position(x: x, y: h / 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let t = Double(min(max((g.location.x - 8) / (w - 16), 0), 1))
                let new = ThemeOpacity.clamped(range.lowerBound + t * (range.upperBound - range.lowerBound))
                if new != value, ThemePickerSnap.crossesDetent(from: value, to: new) || new == range.upperBound { PickerHaptics.tick() }
                value = new
            })
        }
        .help("Opacity")
        .accessibilityElement()
        .accessibilityLabel("Opacity")
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.1 : -0.1
            value = ThemeOpacity.clamped(value + step)
        }
    }

    /// A 2 pt checkerboard, drawn once.
    private static let checks: NSImage = {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { r in
            NSColor(white: 0.85, alpha: 1).setFill()
            r.fill()
            NSColor(white: 0.55, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 4, height: 4).fill()
            NSRect(x: 4, y: 4, width: 4, height: 4).fill()
            return true
        }
        return image
    }()
}

/// The dial's face: the theme's grain texture at the chosen strength.
private struct NoiseDisc: View {
    let amount: Double
    var body: some View {
        Rectangle().fill(ImagePaint(image: Image(nsImage: NoiseTexture.image), scale: 0.5)).opacity(0.15 + 0.6 * amount)
    }
}

/// Arc's ColorPillButtonStyle for the preset swatches: a circle grows a little under the pointer and
/// shrinks while pressed, both eased; scaled, never resized, so the row keeps its 29.5 pt pitch.
/// The pad's knobs use the same scales (GitHub #189).
struct ColorPillButtonStyle: ButtonStyle {
    static let hovered: CGFloat = 1.08
    static let pressed: CGFloat = 0.92
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Self.pressed : isHovered ? Self.hovered : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

/// Arc's SpaceStyleButtonStyle (paging arrows, − / +, Auto / Light / Dark): white at `opacity`,
/// brighter under the pointer while it can be pressed.
struct SpaceStyleButtonStyle: ButtonStyle {
    var opacity: Double
    var enabled = true
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.pickerInk) private var ink

    func makeBody(configuration: Configuration) -> some View {
        let hot = enabled && isHovered
        return configuration.label
            .foregroundStyle(ink.opacity(hot ? min(1, opacity + 0.3) : opacity))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hot)
            .onHover { isHovered = $0 }
    }
}

/// The pointer Arc shows over the editor: a pointing hand on a paging arrow, an open hand over a
/// pad knob and a closed one while dragging it. SwiftUI's pointer styles (macOS 15 and later; on 14
/// the arrow stays).
enum EditorPointer { case link, grab, grabbing }

extension View {
    @ViewBuilder func editorPointer(_ pointer: EditorPointer?) -> some View {
        if #available(macOS 15, *), let pointer {
            switch pointer {
            case .link: self.pointerStyle(.link)
            case .grab: self.pointerStyle(.grabIdle)
            case .grabbing: self.pointerStyle(.grabActive)
            }
        } else {
            self
        }
    }
}
