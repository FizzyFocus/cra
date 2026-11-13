import AppKit
import SwiftUI

/// Arc's Boost editor (Arc 1.172.1, captured 7 Nov 2026; docs/screenshots/arc-boost-*.png): a
/// 183 × 588 pt floating panel 10 pt in from the window's right edge and 215 pt down. Header: a grey
/// ✕ (Done), "My Boost ⌄" (Rename this Boost…, Shuffle, Reset all Edits, Delete this Boost, All
/// Boosts…), Undo. Then a 147 pt colour wheel, three 42 × 38 buttons (Invert lightness, Advanced
/// colour controls: Contrast, Brightness, Original Saturation; Reset to original colours), a white
/// card of 20 "Aa" fonts, Size and Case, Zap ⚡ and Code {} (which widens the panel to 480 pt with a
/// CSS / JS switch; under the code, the eyedropper (Show Selector Picker), the hammer (Show
/// Developer Tools) and, for JavaScript, Refresh this Page). Every change shows on the page at once.
@MainActor
final class BoostEditorController {
    static let shared = BoostEditorController()
    private var panel: NSPanel?
    private var model: BoostEditorModel?

    /// What the editor does to the page beside it.
    struct PageActions {
        var zap: (Bool) -> Void
        var pick: (Bool) -> Void
        var toggleDevTools: () -> Void
        var devToolsOpen: () -> Bool
        var reload: () -> Void
        /// What each zap hides on the page (ZapFacts), for the zap list.
        var inspectZaps: ([String], @escaping ([ZapFacts]) -> Void) -> Void = { _, done in done([]) }
        /// The ghost of a zapped element in its place on the page; nil takes it away.
        var ghost: (String?) -> Void = { _ in }
        /// Restore: what these zaps hid shows on the page at once (BoostScript.unzap).
        var unzap: ([String]) -> Void = { _ in }
    }

    func open(_ boost: Boost, over window: NSWindow, page: PageActions) {
        close()
        let m = BoostEditorModel(boost: boost)
        m.page = page
        m.devToolsOpen = page.devToolsOpen()
        m.onClose = { [weak self] in self?.close() }
        // Another of the site's boosts, or a new one for it, in the editor in its place (13 Nov 2026).
        m.onSwitch = { [weak self, weak window] id in
            guard let self, let window, let b = BoostStore.shared.boost(id) else { return }
            BoostStore.shared.noteOpened(b)
            self.open(b, over: window, page: page)
            CraLog.note("boost editor switched to \(b.name)")
        }
        m.onNewBoost = { [weak self, weak window, weak m] in
            guard let self, let window, let host = m?.boost.host else { return }
            let b = BoostStore.shared.newBoost(host: host)
            BoostStore.shared.noteOpened(b)
            self.open(b, over: window, page: page)
            CraLog.note("boost editor made \(b.name) for \(host)")
        }
        m.onWidth = { [weak self] w in self?.resize(width: w) }
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isOpaque = false
        p.becomesKeyOnlyIfNeeded = true
        let host = FirstClickHostingView(rootView: BoostEditorView(model: m))
        host.sizingOptions = []
        p.contentView = host
        let f = window.frame
        p.setFrame(NSRect(x: f.maxX - 10 - 183, y: f.maxY - 215 - 588, width: 183, height: 588), display: false)
        window.addChildWindow(p, ordered: .above)
        p.orderFront(nil)
        panel = p
        model = m
        growIn(p, host)
    }

    private static var easeOut: CAMediaTimingFunction {
        let (x1, y1, x2, y2) = BoostEditorMotion.easeOut
        return CAMediaTimingFunction(controlPoints: Float(x1), Float(y1), Float(x2), Float(y2))
    }

    /// Arc's opening (BoostEditorMotion): drawn at 85 % and grown to full size about the middle of
    /// its right edge. The window's shadow can't scale, so the content carries one meanwhile.
    private func growIn(_ panel: NSPanel, _ view: NSView) {
        view.wantsLayer = true
        guard let layer = view.layer, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let b = view.bounds
        let s = BoostEditorMotion.openScale
        // The layer scales about its anchor point; move the pivot to the right edge's middle.
        let dx = b.width * (BoostEditorMotion.openAnchor.x - layer.anchorPoint.x)
        let dy = b.height * (BoostEditorMotion.openAnchor.y - layer.anchorPoint.y)
        var t = CATransform3DMakeTranslation(dx, dy, 0)
        t = CATransform3DScale(t, s, s, 1)
        t = CATransform3DTranslate(t, -dx, -dy, 0)
        panel.hasShadow = false
        layer.shadowPath = CGPath(roundedRect: b, cornerWidth: 12, cornerHeight: 12, transform: nil)
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: -3)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak panel, weak layer] in
            layer?.shadowOpacity = 0
            panel?.hasShadow = true
            panel?.invalidateShadow()
        }
        let a = CABasicAnimation(keyPath: "transform")
        a.fromValue = NSValue(caTransform3D: t)
        a.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        a.duration = BoostEditorMotion.openDuration
        a.timingFunction = Self.easeOut
        layer.add(a, forKey: "craBoostGrow")
        CATransaction.commit()
    }

    func close() {
        model?.ghost(nil)
        model?.finishZap()
        model?.finishPicking()
        if let panel { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
        panel = nil
        model = nil
    }

    var isOpen: Bool { panel != nil }
    /// The browser window it is open over.
    var window: NSWindow? { panel?.parent }
    /// The boost open in the editor.
    var editingBoostID: UUID? { model?.boost.id }

    /// Scenario hooks: what the editor shows, and its zap menu's "Show All Zapped Elements".
    var debugState: String {
        guard let model else { return "closed" }
        return "open \(model.boost.name) zapped=\(model.boost.zapped.count) zapping=\(model.zapping ? 1 : 0)"
    }

    func debugShowAllZapped() { model?.change { $0.zapped = [] } }

    /// The zap list as it would show: each zap's label and size, from the page.
    func debugZapList(_ label: String) {
        guard let model else { CraLog.note("zap list \(label): no editor"); return }
        model.page.inspectZaps(model.boost.zapped) { facts in
            CraLog.note("zap list \(label): " + facts.map { "\($0.label) [\($0.detail)]" }.joined(separator: " | "))
        }
    }

    /// A zap row hovered (its index; -1 off the list), and its Restore.
    func debugZapHover(_ index: Int) {
        guard let model else { return }
        model.ghost(model.boost.zapped.indices.contains(index) ? model.boost.zapped[index] : nil)
    }

    func debugShowZapList(_ on: Bool) { model?.showingZaps = on }

    /// The zap list's button `title` ("Restore", "Restore All") clicked where it is.
    func debugClickZapList(_ title: String) -> String {
        func find(_ v: NSView) -> ZapListAnchorView? {
            if let a = v as? ZapListAnchorView { return a }
            for s in v.subviews { if let a = find(s) { return a } }
            return nil
        }
        guard let root = panel?.contentView, let anchor = find(root) else { return "no zap count" }
        return anchor.debugClick(title) ?? "clicked \(title)"
    }

    /// Its name menu's rows: another of the site's boosts by name, New Boost for the site, Turn Off/On.
    func debugMenu(_ row: String) {
        guard let model else { return }
        switch row {
        case "new": model.onNewBoost()
        case "toggle": model.change { $0.enabled.toggle() }
        default:
            if let b = BoostStore.shared.boosts(forHost: model.boost.host).first(where: { $0.name == row }) { model.onSwitch(b.id) }
        }
    }

    /// Only the page's part of Restore, the boost left as it is (a scenario's proof it needs no reload).
    func debugUnzapOnly(_ index: Int) {
        guard let model, model.boost.zapped.indices.contains(index) else { return }
        model.page.unzap([model.boost.zapped[index]])
    }

    func debugZapRestore(_ index: Int) {
        guard let model, model.boost.zapped.indices.contains(index) else { return }
        model.restore([model.boost.zapped[index]])
    }

    /// Its Zap button pressed to `on`; false with the editor closed.
    func debugZap(_ on: Bool) -> Bool {
        guard let model else { return false }
        if model.zapping != on { model.toggleZap() }
        return true
    }

    /// The picker ends (its page went to the back).
    func stopPicking() { model?.finishPicking() }

    /// DevTools opened or closed (the hammer, ⌥⌘I or their own close button).
    func devToolsChanged() { if let model { model.devToolsOpen = model.page.devToolsOpen() } }

    /// What Zap hid, into its boost at once: through the editor while it shows that boost (one Undo
    /// step a take), else straight into BoostStore, so a zap made just before the editor closed is
    /// kept too (13 Nov 2026: it was dropped with the editor).
    func addZapped(_ selectors: [String], to boostID: UUID?) {
        guard !selectors.isEmpty else { return }
        CraLog.note("zap kept \(selectors.count) selector\(selectors.count == 1 ? "" : "s")")
        if let model, boostID == nil || model.boost.id == boostID {
            model.change { b in b.zapped += selectors.filter { !b.zapped.contains($0) } }
            return
        }
        guard let id = boostID, var b = BoostStore.shared.boost(id) else { return }
        b.zapped += selectors.filter { !b.zapped.contains($0) }
        BoostStore.shared.update(b)
    }

    private func resize(width: CGFloat) {
        guard let panel else { return }
        var f = panel.frame
        let duration = BoostEditorMotion.resizeDuration(fromWidth: f.width, to: width)
        f.origin.x = f.maxX - width
        f.size.width = width
        // Arc: Code widens the panel in 0.35 s, Back narrows it in 0.13 s, both easing out.
        guard duration > 0, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { panel.setFrame(f, display: true); return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = Self.easeOut
            panel.animator().setFrame(f, display: true)
        }
    }
}

@MainActor
@Observable
final class BoostEditorModel {
    var boost: Boost { didSet { if boost != oldValue { BoostStore.shared.update(boost) } } }
    var history: [Boost] = []
    var showingCode = false
    var codeIsJS = false
    var zapping = false
    var picking = false
    var devToolsOpen = false
    @ObservationIgnored var page = BoostEditorController.PageActions(zap: { _ in }, pick: { _ in }, toggleDevTools: {}, devToolsOpen: { false }, reload: {})
    /// The zap list's facts, by selector (asked when the list opens).
    var zapFacts: [String: ZapFacts] = [:]
    /// The zap list is open (the count beside Zap).
    var showingZaps = false
    /// Where the list's Restore All and first Restore are, in its window (scenario hook clicks).
    @ObservationIgnored var zapButtonFrames: [String: CGRect] = [:]
    /// The zap whose ghost shows on the page.
    var ghosted: String?

    func inspectZaps() {
        page.inspectZaps(boost.zapped) { [weak self] facts in
            self?.zapFacts = Dictionary(facts.map { ($0.selector, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }

    /// The pointer over a zap in the list (nil: off it).
    func ghost(_ selector: String?) {
        guard ghosted != selector else { return }
        ghosted = selector
        page.ghost(selector)
    }

    /// Restore: the zap goes and its element shows again (the ghost first taken away, so it
    /// doesn't put the element's hiding back after).
    func restore(_ selectors: [String]) {
        ghost(nil)
        // On the page at once, not only once the boost is applied again (13 Nov 2026).
        page.unzap(selectors)
        let gone = Set(selectors)
        change { $0.zapped.removeAll { gone.contains($0) } }
        CraLog.note("zap restored \(selectors.count), \(boost.zapped.count) left")
    }
    @ObservationIgnored var onClose: () -> Void = {}
    @ObservationIgnored var onSwitch: (UUID) -> Void = { _ in }
    @ObservationIgnored var onNewBoost: () -> Void = {}
    @ObservationIgnored var onWidth: (CGFloat) -> Void = { _ in }

    init(boost: Boost) { self.boost = boost }

    /// One step of the editor, undoable.
    func change(_ edit: (inout Boost) -> Void) {
        history.append(boost)
        var b = boost
        edit(&b)
        boost = b
    }

    func undo() { if let last = history.popLast() { boost = last } }

    func shuffle() {
        change {
            $0.hue = Double.random(in: 0..<1)
            $0.strength = Double.random(in: 0.3...0.8)
            $0.font = Int.random(in: 0..<Boost.fonts.count)
        }
    }

    func resetAll() {
        change { b in
            let fresh = Boost(id: b.id, host: b.host, name: b.name)
            b = fresh
        }
    }

    func toggleZap() {
        finishPicking()
        zapping.toggle()
        page.zap(zapping)
    }

    func finishZap() { if zapping { zapping = false; page.zap(false) } }

    /// The eyedropper: outline elements on the page; a click offers their selectors.
    func togglePicker() {
        finishZap()
        picking.toggle()
        page.pick(picking)
    }

    func finishPicking() { if picking { picking = false; page.pick(false) } }

    func toggleDevTools() {
        page.toggleDevTools()
        devToolsOpen.toggle()
    }

    func setCode(_ on: Bool) {
        if !on { finishPicking() }
        showingCode = on
        onWidth(on ? 480 : 183)
    }
}

private enum BoostStyle {
    static let panel = Color(red: 0.976, green: 0.976, blue: 0.984)
    static let button = Color(red: 0.91, green: 0.91, blue: 0.925)
    static let ink = Color(white: 0.2)
    static let secondary = Color(white: 0.55)
}

private struct BoostEditorView: View {
    @Bindable var model: BoostEditorModel
    @State private var showColors = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            if model.showingCode { code } else { controls }
        }
        // Arc lays the panel out at its final width and keeps it centred while the window
        // widens or narrows, so both sides are clipped meanwhile.
        .frame(width: model.showingCode ? 480 : 183)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BoostStyle.panel))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .environment(\.colorScheme, .light)
    }

    /// The code panel's header is only Back and the CSS / JS switch, centred (Arc 1.172.1).
    @ViewBuilder private var header: some View {
        if model.showingCode {
            ZStack {
                Picker("", selection: $model.codeIsJS) {
                    Text("CSS").tag(false)
                    Text("JS").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 92)
                HStack {
                    Button { model.setCode(false) } label: {
                        Label("Back", systemImage: "arrow.left").font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(BoostStyle.ink).padding(.leading, 10)
                    Spacer()
                }
            }
            .frame(height: 40)
        } else {
            boostHeader
        }
    }

    private var boostHeader: some View {
        HStack(spacing: 0) {
            Button { model.onClose() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(Color(white: 0.6))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain).help("Done")
            Spacer(minLength: 0)
            Menu {
                // The site's boosts, all on together (13 Nov 2026): the one shown ticked, another a pick away.
                let site = BoostStore.shared.boosts(forHost: model.boost.host)
                if site.count > 1 {
                    Section("Boosts for \(model.boost.host)") {
                        ForEach(site) { b in
                            Toggle(b.enabled ? b.name : "\(b.name) (Off)",
                                   isOn: Binding(get: { b.id == model.boost.id }, set: { _ in if b.id != model.boost.id { model.onSwitch(b.id) } }))
                        }
                    }
                }
                Button(model.boost.enabled ? "Turn Off This Boost" : "Turn On This Boost") { model.change { $0.enabled.toggle() } }
                Button("New Boost for \(model.boost.host)") { model.onNewBoost() }
                Divider()
                Button("Rename this Boost…") { rename() }
                Button("Shuffle") { model.shuffle() }
                Button("Reset all Edits") { model.resetAll() }
                Button("Delete this Boost") { delete() }
                Divider()
                Button("All Boosts…") { NotificationCenter.default.post(name: .craShowBoostsLibrary, object: nil) }
            } label: {
                HStack(spacing: 4) {
                    Text(model.boost.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(BoostStyle.ink).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(BoostStyle.ink)
                }
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            Spacer(minLength: 0)
            Button { model.undo() } label: {
                Image(systemName: "arrow.counterclockwise").font(.system(size: 14, weight: .semibold)).frame(width: 40, height: 40)
            }
            .buttonStyle(.plain).foregroundStyle(model.history.isEmpty ? Color(white: 0.75) : BoostStyle.ink).disabled(model.history.isEmpty).help("Undo")
        }
        .frame(height: 40)
    }

    private var controls: some View {
        VStack(spacing: 14) {
            ColorWheel(hue: model.boost.hue, strength: model.boost.strength) { h, s in
                model.change { $0.hue = h; $0.strength = s }
            }
            .frame(width: 147, height: 147)
            .padding(.top, 18)
            HStack(spacing: 10) {
                square("lightbulb", on: model.boost.invert, help: "Invert lightness") { model.change { $0.invert.toggle() } }
                square("slider.horizontal.3", on: showColors, help: "Advanced color controls",
                       active: model.boost.contrast != 50 || model.boost.brightness != 50 || model.boost.saturation != 50) { showColors.toggle() }
                    .popover(isPresented: $showColors, arrowEdge: .leading) { advanced }
                square("nosign", on: false, help: "Reset to original colors") {
                    model.change { $0.hue = 0; $0.strength = 0; $0.invert = false; $0.contrast = 50; $0.brightness = 50; $0.saturation = 50 }
                }
                .opacity(model.boost.colorsUntouched ? 0.45 : 1)
            }
            fonts
            // Size and Case say what they are set to, and stand out while it isn't the site's own (13 Nov 2026).
            HStack(spacing: 9) {
                Menu {
                    ForEach([0.8, 0.9, 1, 1.1, 1.25, 1.5], id: \.self) { s in
                        Toggle(s == 1 ? "Original" : "\(Int((s * 100).rounded())) %",
                               isOn: Binding(get: { model.boost.textScale == s }, set: { _ in model.change { $0.textScale = s } }))
                    }
                } label: { wide(Boost.sizeTitle(model.boost.textScale), trailing: nil, active: model.boost.textScale != 1) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).help("Change text size")
                Menu {
                    ForEach(Boost.TextCase.allCases, id: \.self) { c in
                        Toggle(c.title, isOn: Binding(get: { model.boost.textCase == c }, set: { _ in model.change { $0.textCase = c } }))
                    }
                } label: { wide(model.boost.textCase.buttonTitle, trailing: nil, active: model.boost.textCase != .none) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).help("Change text case")
            }
            .frame(width: 147)
            zapRow
            Button { model.setCode(true) } label: {
                wide("Code", trailing: "curlybraces", active: !model.boost.css.isEmpty || !model.boost.js.isEmpty)
            }
            .buttonStyle(.plain)
            .help(model.boost.css.isEmpty && model.boost.js.isEmpty ? "Your own CSS and JavaScript" : "This boost has its own CSS or JavaScript")
            Spacer(minLength: 0)
        }
        .frame(width: 183)
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 10) {
            slider("Contrast", \.contrast)
            slider("Brightness", \.brightness)
            slider("Original Saturation", \.saturation)
        }
        .padding(18)
        .frame(width: 250)
    }

    private func slider(_ title: String, _ key: WritableKeyPath<Boost, Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .medium))
            Slider(value: Binding(get: { model.boost[keyPath: key] }, set: { v in model.change { $0[keyPath: key] = v } }), in: 0...100)
        }
    }

    private var fonts: some View {
        let columns = Array(repeating: GridItem(.fixed(26), spacing: 1.5), count: 5)
        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Boost.fonts.indices, id: \.self) { i in
                Button { model.change { $0.font = $0.font == i ? nil : i } } label: {
                    Text("Aa").font(.custom(Boost.fonts[i] == "-apple-system" ? "Helvetica Neue" : Boost.fonts[i], size: 13))
                        .foregroundStyle(model.boost.font == i ? Color.accentColor : BoostStyle.secondary)
                        .frame(width: 26, height: 26)
                        // The font in use on a tinted tile of its own (13 Nov 2026).
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(model.boost.font == i ? 0.14 : 0)))
                }
                .accessibilityAddTraits(model.boost.font == i ? .isSelected : [])
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 5)
        .frame(width: 147)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white).shadow(color: .black.opacity(0.08), radius: 4, y: 1))
    }

    /// `on`: a mode that is on (Zap, the colour controls open). `active`: a setting away from the site's
    /// own (13 Nov 2026), in the accent, tinted and ringed.
    private func square(_ symbol: String, on: Bool, help: String, size: CGFloat = 42, active: Bool = false,
                        _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15))
                .foregroundStyle(on ? .white : active ? Color.accentColor : BoostStyle.ink)
                .frame(width: size, height: 38)
                .background(controlFill(on: on, active: active))
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    private func wide(_ title: String, trailing: String?, on: Bool = false, active: Bool = false, width: CGFloat = 147) -> some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .semibold))
            if let trailing { Spacer(); Image(systemName: trailing).font(.system(size: 13, weight: .semibold)) }
        }
        .foregroundStyle(on ? .white : active ? Color.accentColor : BoostStyle.ink)
        .padding(.horizontal, 12)
        .frame(maxWidth: trailing == nil ? .infinity : width, minHeight: 38)
        .frame(width: trailing == nil ? nil : width)
        .background(controlFill(on: on, active: active))
        .accessibilityValue(active ? "changed" : "")
    }

    @ViewBuilder private func controlFill(on: Bool, active: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if on {
            shape.fill(BoostStyle.ink)
        } else {
            shape.fill(BoostStyle.button)
                .overlay(shape.fill(Color.accentColor.opacity(active ? 0.12 : 0)))
                .overlay(shape.strokeBorder(Color.accentColor.opacity(active ? 0.7 : 0), lineWidth: 1.5))
        }
    }

    /// Zap, and once the boost has zaps, how many beside it (13 Nov 2026): that count opens the
    /// zap list, each zap named as the page shows it, its ghost on the page under the pointer.
    private var zapRow: some View {
        let zapped = model.boost.zapped
        return HStack(spacing: 6) {
            Button { model.toggleZap() } label: { wide("Zap", trailing: "bolt.fill", on: model.zapping, width: zapped.isEmpty ? 147 : 103) }
                .buttonStyle(.plain)
                .help("Click things on the page to hide them")
            if !zapped.isEmpty {
                Button { model.showingZaps.toggle() } label: {
                    Text("\(zapped.count)")
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(model.showingZaps ? .white : BoostStyle.ink)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(model.showingZaps ? BoostStyle.ink : BoostStyle.button))
                }
                .buttonStyle(.plain)
                .help("\(zapped.count) zapped \(zapped.count == 1 ? "element" : "elements")")
                .accessibilityLabel("\(zapped.count) zapped")
                // A panel like the editor's, not SwiftUI's popover: a click on Restore lands on the first
                // press and the list stays until a click outside it (13 Nov 2026: Restore closed it unpressed).
                .background(ZapListAnchor(model: model, shown: model.showingZaps, count: zapped.count))
            }
        }
        .frame(width: 147)
        .onChange(of: zapped.isEmpty) { _, none in if none { model.showingZaps = false } }
    }

    /// A selector short enough for a menu row.
    private static func short(_ selector: String) -> String {
        selector.count <= 40 ? selector : "…" + selector.suffix(39)
    }

    private var code: some View {
        VStack(spacing: 0) {
            CodeEditor(text: Binding(get: { model.codeIsJS ? model.boost.js : model.boost.css },
                                     set: { v in if model.codeIsJS { model.boost.js = v } else { model.boost.css = v } }))
            // Arc: 38 pt squares 15 pt in, in a 69 pt strip under the 479 pt editor.
            HStack(spacing: 10) {
                square("eyedropper", on: model.picking, help: model.picking ? "Hide Selector Picker" : "Show Selector Picker", size: 38) {
                    model.togglePicker()
                }
                square("hammer", on: model.devToolsOpen, help: model.devToolsOpen ? "Hide Developer Tools" : "Show Developer Tools", size: 38) {
                    model.toggleDevTools()
                }
                if model.codeIsJS {
                    square("arrow.clockwise", on: false, help: "Refresh this Page", size: 38) { model.page.reload() }
                }
                Spacer()
            }
            .padding(.horizontal, 15)
            .frame(height: 69).background(BoostStyle.panel)
        }
        .frame(width: 480)
    }

    private func rename() {
        let alert = NSAlert()
        alert.messageText = "Rename this Boost"
        let field = NSTextField(string: model.boost.name)
        field.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty { model.change { $0.name = field.stringValue } }
    }

    private func delete() {
        let alert = NSAlert()
        alert.messageText = "Delete this Boost?"
        alert.informativeText = "Its changes to \(model.boost.host) go away."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        BoostStore.shared.delete(model.boost.id)
        model.onClose()
    }
}

/// Arc's colour wheel: a rounded square in a grey gradient frame, dotted inside; the big handle is
/// the tint (hue round the middle, strength out from it), the small one sits at the middle.
private struct ColorWheel: View {
    let hue: Double
    let strength: Double
    let set: (Double, Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let size = geo.size.width, inner = size - 14, c = size / 2
            let angle = hue * 2 * .pi, r = strength * (inner / 2 - 18)
            let handle = CGPoint(x: c + cos(angle) * r, y: c - sin(angle) * r)
            ZStack {
                // Arc's frame: brushed metal, dark at the top left and right, light at the bottom.
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(AngularGradient(colors: [Color(white: 0.55), Color(white: 0.25), Color(white: 0.45), Color(white: 0.85),
                                                   Color(white: 0.95), Color(white: 0.7), Color(white: 0.55)], center: .center, angle: .degrees(180)))
                    .overlay(strength > 0 ? RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color(hue: hue, saturation: 0.5, brightness: 0.8).opacity(0.35)) : nil)
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white).padding(7)
                Canvas { ctx, s in
                    for x in stride(from: 12.0, to: s.width - 12, by: 6) {
                        for y in stride(from: 12.0, to: s.height - 12, by: 6) {
                            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.black.opacity(0.12)))
                        }
                    }
                }
                // Arc's second, smaller handle: the darker end of the tint, between the middle and the big one.
                Circle().fill(Color(white: 0.17)).frame(width: 22, height: 22).overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 1.5)
                    .position(x: c + (handle.x - c) * 0.55 - 8, y: c + (handle.y - c) * 0.55 + 22)
                Circle().fill(strength > 0 ? Color(hue: hue, saturation: 0.6, brightness: 0.8) : Color(white: 0.45))
                    .frame(width: 32, height: 32).overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 2)
                    .position(handle)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let dx = g.location.x - c, dy = c - g.location.y
                var a = atan2(dy, dx) / (2 * .pi)
                if a < 0 { a += 1 }
                set(a, min(1, hypot(dx, dy) / (inner / 2 - 18)))
            })
        }
    }
}

/// The Code panel's editor: dark, monospaced, no smart quotes.
private struct CodeEditor: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.backgroundColor = NSColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1)
        tv.textColor = NSColor(white: 0.92, alpha: 1)
        tv.insertionPointColor = .white
        tv.textContainerInset = NSSize(width: 10, height: 10)
        tv.delegate = context.coordinator
        tv.string = text
        return scroll
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        let tv = view.documentView as! NSTextView
        if tv.string != text { tv.string = text }
        context.coordinator.text = $text
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ n: Notification) { if let tv = n.object as? NSTextView { text.wrappedValue = tv.string } }
    }
}

/// The editor sits beside the page, which keeps the keyboard: its first click acts, as Arc's does.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The zap list beside the count that opens it, in a panel of its own like the editor's: its content
/// takes the first click (a SwiftUI popover off the editor's panel, which never becomes key, closed
/// on the click meant for Restore and restored nothing), and it closes on a click outside it, the
/// count pressed again, or Escape (13 Nov 2026).
private struct ZapListAnchor: NSViewRepresentable {
    let model: BoostEditorModel
    let shown: Bool
    let count: Int

    func makeNSView(context: Context) -> ZapListAnchorView { ZapListAnchorView() }

    func updateNSView(_ view: ZapListAnchorView, context: Context) {
        view.model = model
        view.set(shown: shown)
        view.fit()
    }
}

final class ZapListAnchorView: NSView {
    var model: BoostEditorModel?
    /// The list's own panel, a child of the editor's: like the editor, it never takes key and its
    /// content takes the first click.
    private var panel: NSPanel?
    private var host: NSView?
    private var outsideClicks: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func set(shown: Bool) {
        if shown, panel == nil, let model, let parent = window {
            // Light, as the editor beside it is.
            let content = ZapList(model: model)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BoostStyle.panel))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .environment(\.colorScheme, .light)
            let host = FirstClickHostingView(rootView: content)
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .floating
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            p.becomesKeyOnlyIfNeeded = true
            p.contentView = host
            self.host = host
            panel = p
            place()
            parent.addChildWindow(p, ordered: .above)
            p.orderFront(nil)
            // A press anywhere but in the list (or on the count, which toggles it) closes it; so does Escape.
            outsideClicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] e in
                guard let self, let p = self.panel else { return e }
                if e.type == .keyDown {
                    if e.keyCode == 53 { self.model?.showingZaps = false; return nil }
                    return e
                }
                let onCount = e.window === self.window && self.bounds.contains(self.convert(e.locationInWindow, from: nil))
                if e.window !== p && !onCount { self.model?.showingZaps = false }
                return e
            }
        } else if !shown, let p = panel {
            panel = nil
            host = nil
            if let m = outsideClicks { NSEvent.removeMonitor(m); outsideClicks = nil }
            p.parent?.removeChildWindow(p)
            p.orderOut(nil)
            model?.ghost(nil)
        }
    }

    /// Left of the count, 8 pt clear, centred on it and kept on its screen; its size the list's.
    private func place() {
        guard let panel, let host, let w = window else { return }
        let size = host.fittingSize
        let anchor = w.convertToScreen(convert(bounds, to: nil))
        var frame = NSRect(x: anchor.minX - 8 - size.width, y: anchor.midY - size.height / 2, width: size.width, height: size.height)
        if let screen = w.screen?.visibleFrame {
            frame.origin.y = min(max(frame.minY, screen.minY + 6), screen.maxY - 6 - size.height)
            frame.origin.x = max(frame.minX, screen.minX + 6)
        }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    /// The list grows and shrinks with its zaps.
    func fit() { place() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { set(shown: false) }
    }

    /// Scenario hook: the list's button titled `title`, pressed with a click posted where it is, as the
    /// pointer would press it. Nil once posted, else why not.
    func debugClick(_ title: String) -> String? {
        guard let host, let w = panel else { return "no list" }
        guard let f = model?.zapButtonFrames[title] else { return "no button \(title)" }
        // SwiftUI's global space runs from the hosting view's top; the window's from its bottom.
        let inView = NSPoint(x: f.midX, y: host.isFlipped ? f.midY : host.bounds.height - f.midY)
        TestGesture.click(at: host.convert(inView, to: nil), in: w)
        return nil
    }
}

extension Notification.Name {
    static let craShowBoostsLibrary = Notification.Name("craShowBoostsLibrary")
}

/// The editor's zap list (13 Nov 2026, the owner's call): each zap by the name and size of what it
/// hides on the page (ZapFacts), its ghost in its place on the page while the pointer is on its
/// row, a Restore for it and one for them all.
private struct ZapList: View {
    let model: BoostEditorModel

    var body: some View {
        let zapped = model.boost.zapped
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(zapped.count == 1 ? "1 Zapped Element" : "\(zapped.count) Zapped Elements")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Restore All") { model.restore(zapped) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .background(ZapButtonFrame(model: model, title: "Restore All"))
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(zapped, id: \.self) { s in ZapRow(selector: s, facts: model.zapFacts[s], model: model, first: s == zapped.first) }
                }
                .padding(6)
            }
            // A row is 58 pt; more than five scroll.
            .frame(height: min(5, CGFloat(zapped.count)) * 60 + 12)
        }
        .frame(width: 300)
        .onAppear { model.inspectZaps() }
        .onDisappear { model.ghost(nil) }
        .onChange(of: zapped) { _, _ in model.inspectZaps() }
    }
}

private struct ZapRow: View {
    let selector: String
    let facts: ZapFacts?
    let model: BoostEditorModel
    var first = false
    @State private var hovering = false

    var body: some View {
        let onPage = (facts?.count ?? 1) > 0
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: onPage ? "eye.slash" : "questionmark.square.dashed")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(facts?.label ?? "…").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(facts?.detail ?? " ").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Text(selector).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Button("Restore") { model.restore([selector]) }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(hovering ? 0.1 : 0.06)))
                .background(first ? ZapButtonFrame(model: model, title: "Restore") : nil)
                .help("Show it on the page again")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            // Its ghost on the page while the pointer is on the row; off it, gone.
            if inside { model.ghost(onPage ? selector : nil) } else if model.ghosted == selector { model.ghost(nil) }
        }
    }
}


/// Where a zap-list button is drawn, in its window's coordinates from the top, for the scenario hook
/// that clicks it (ZapListAnchorView.debugClick).
private struct ZapButtonFrame: View {
    let model: BoostEditorModel
    let title: String

    var body: some View {
        GeometryReader { g in
            Color.clear
                .onAppear { model.zapButtonFrames[title] = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, f in model.zapButtonFrames[title] = f }
        }
    }
}
