import CraCore
import SwiftUI

final class SpacesModel: ObservableObject {
    enum State {
        case loading, unavailable, nothingSynced
        case spaces(SidebarDocument)
    }

    @Published var state: State = .loading
    /// What the phone opened or shut itself, by row id; everything else is as the Mac has it.
    @Published var toggled: [UUID: Bool] = [:]
    @Published var selected: UUID?
    /// When the Mac wrote the Spaces shown, for "Updated just now".
    @Published var writtenAt: Date?
    /// What a refresh is waiting for, while it waits.
    @Published var activity: SyncedSidebar.Activity?
    var open: (String) -> Void = { _ in }
    var favicon: (String) -> UIImage? = { _ in nil }
    var close: () -> Void = {}
    private var watcher: SyncedSidebar.Watcher?
    private var foreground: NSObjectProtocol?
    private var refreshing = false
    private var refreshAgain = false
    private var finished: [() -> Void] = []
    private var watcherDebounce: DispatchWorkItem?

    var spaces: [MobileSpaces.SpaceView] {
        guard case .spaces(let document) = state else { return [] }
        return MobileSpaces.spaces(in: document, toggled: toggled)
    }

    /// The sheet opened: the Spaces on the phone at once, then the Mac's newest from iCloud Drive;
    /// again whenever the app comes back to the front, and whenever iCloud Drive brings a newer
    /// file down while the sheet is open.
    func appear() {
        if watcher == nil {
            watcher = SyncedSidebar.Watcher { [weak self] in self?.folderChanged() }
        }
        if foreground == nil {
            foreground = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil,
                                                                queue: .main) { [weak self] _ in self?.refresh() }
        }
        refresh()
    }

    func disappear() {
        watcher?.stop()
        watcher = nil
        if let foreground { NotificationCenter.default.removeObserver(foreground) }
        foreground = nil
    }

    deinit { watcher?.stop() }

    /// A presenter's note comes for every file of a bundle: one refresh after the last of them.
    private func folderChanged() {
        watcherDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        watcherDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Asks iCloud Drive for the newest Spaces and shows them; `done` once it has them, or has
    /// waited long enough. A refresh asked for while one runs runs again after it.
    func refresh(_ done: @escaping () -> Void = {}) {
        finished.append(done)
        guard !refreshing else { refreshAgain = true; return }
        refreshing = true
        SyncedSidebar.refresh { [weak self] progress in
            guard let self else { return }
            switch progress {
            case .read(let result): self.show(result)
            case .waiting(let activity): self.activity = activity
            case .finished(let result):
                self.show(result)
                self.activity = nil
                self.refreshing = false
                if self.refreshAgain {
                    self.refreshAgain = false
                    self.refresh()
                } else {
                    let callbacks = self.finished
                    self.finished = []
                    callbacks.forEach { $0() }
                }
            }
        }
    }

    /// Pull to refresh.
    @MainActor func pullToRefresh() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            refresh { continuation.resume() }
        }
    }

    private func show(_ result: SyncedSidebar.State) {
        switch result {
        case .spaces(let document, let written):
            let old: SidebarDocument? = { if case .spaces(let d) = state { return d } else { return nil } }()
            guard old != document || written != writtenAt else { return }
            // The phone's own choices stay unless the Mac opened or shut that row since.
            toggled = MobileSpaces.keptToggles(toggled, from: old, to: document)
            state = .spaces(document)
            writtenAt = written
            if selected == nil || !spaces.contains(where: { $0.id == selected }) { selected = spaces.first?.id }
        case .nothingSynced:
            if case .spaces = state { return }
            state = .nothingSynced
        case .unavailable:
            state = .unavailable
        }
    }

    func isOpen(_ row: MobileSpaces.Row) -> Bool { row.isOpen ?? true }

    func toggle(_ row: MobileSpaces.Row) {
        guard let open = row.isOpen else { return }
        toggled[row.id] = !open
    }

    /// The folder picked in Files to read the Mac's Spaces from (Pane: the Mac syncs into iCloud Drive).
    func choose(_ folder: URL) {
        guard SyncedSidebar.choose(folder) else { return }
        state = .loading
        disappear()
        appear()
    }
}

/// Arc Search's Spaces view: the desktop's Spaces, one a page, each tinted with its colour: the
/// Space's name, its Favorites, the Pinned header over its pinned tabs and folders, then Today with
/// its sections; the Spaces' icons along the bottom, and over it all a line saying how fresh they are.
struct SpacesView: View {
    @ObservedObject var model: SpacesModel

    var body: some View {
        let spaces = model.spaces
        ZStack {
            tint(for: spaces.first { $0.id == model.selected }).ignoresSafeArea()
            if spaces.isEmpty {
                empty
            } else {
                VStack(spacing: 0) {
                    statusLine.padding(.top, 24).padding(.horizontal, 26).frame(maxWidth: .infinity, alignment: .leading)
                    TabView(selection: $model.selected) {
                        ForEach(spaces) { space in
                            page(space).tag(Optional(space.id))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    if spaces.count > 1 { icons(spaces) }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: model.close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.5))
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 22)
            .padding(.trailing, 24)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("spaces-close")
        }
        // White text on a dark Space, as Arc Search draws it (`MobileSpaces.sheetStyle`).
        .environment(\.colorScheme, style(for: spaces.first { $0.id == model.selected })?.lightText == true ? .dark : .light)
        .animation(.easeInOut(duration: 0.25), value: model.selected)
        .onAppear { model.appear() }
        .onDisappear { model.disappear() }
    }

    /// "Updated just now" with a dot, or what a refresh is waiting for with a spinner.
    private var statusLine: some View {
        TimelineView(.periodic(from: .now, by: 20)) { context in
            HStack(spacing: 7) {
                if let activity = model.activity {
                    ProgressView().controlSize(.mini)
                    Text(activity == .downloading ? MobileSpaces.downloadingLabel : MobileSpaces.checkingLabel)
                } else if let written = model.writtenAt {
                    let fresh = context.date.timeIntervalSince(written) < 60
                    Circle().fill(fresh ? Color.green : Color.primary.opacity(0.35)).frame(width: 6, height: 6)
                    Text(MobileSpaces.updatedLabel(writtenAt: written, now: context.date))
                }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary.opacity(0.55))
            .frame(height: 26)
            .animation(.easeInOut(duration: 0.2), value: model.activity)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("spaces-sync-status")
        }
    }

    private func page(_ space: MobileSpaces.SpaceView) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(space.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.9))
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                    .accessibilityIdentifier("space-title")
                if !space.favorites.isEmpty { favorites(space.favorites) }
                ForEach(space.rows) { row in
                    rowView(row).transition(.opacity)
                }
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.22), value: space.rows)
        }
        .refreshable { await model.pullToRefresh() }
    }

    /// The Space's Favorites as the Mac's tiles, four to a row.
    private func favorites(_ favorites: [MobileSpaces.Favorite]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(favorites) { favorite in
                Button { model.open(favorite.url) } label: {
                    FaviconView(image: model.favicon(favorite.url))
                        .scaleEffect(1.2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(favorite.title)
                .accessibilityIdentifier("space-favorite-\(favorite.title)")
            }
        }
        .padding(.bottom, 12)
    }

    @ViewBuilder private func rowView(_ row: MobileSpaces.Row) -> some View {
        switch row.kind {
        case .todayHeader:
            Rectangle().fill(Color.primary.opacity(0.15)).frame(height: 1).padding(.vertical, 12)
        case .pinnedHeader(let open):
            header(row, open: open, id: "space-pinned")
        case .section(let open):
            header(row, open: open, id: "space-section-\(row.title)")
        case .folder(let open):
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { model.toggle(row) }
            } label: {
                label(row, icon: Image(systemName: open ? "folder" : "folder.fill").foregroundStyle(.primary.opacity(0.55)),
                      trailing: open ? nil : row.count)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("space-folder-\(row.title)")
            .accessibilityValue(open ? "Open" : "Closed")
        case .tab(let url):
            Button { model.open(url) } label: {
                label(row, icon: FaviconView(image: model.favicon(url)), trailing: nil)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("space-tab-\(row.title)")
        }
    }

    /// The Pinned header and a section's: small caps-height text with a chevron that turns, and the
    /// count of what a closed one holds.
    private func header(_ row: MobileSpaces.Row, open: Bool, id: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { model.toggle(row) }
        } label: {
            HStack(spacing: 6) {
                Text(row.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                Spacer(minLength: 0)
                if !open, row.count > 0 { Text("\(row.count)").font(.system(size: 13, weight: .medium)).monospacedDigit() }
            }
            .foregroundStyle(.primary.opacity(0.5))
            .frame(height: 38)
            .padding(.leading, CGFloat(row.depth) * 22)
            .padding(.top, row.kind == .pinnedHeader(open: open) ? 0 : 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityValue(open ? "Open" : "Closed")
    }

    private func label(_ row: MobileSpaces.Row, icon: some View, trailing count: Int?) -> some View {
        HStack(spacing: 12) {
            icon.frame(width: 22, height: 22)
            Text(row.title).font(.system(size: 17, weight: .medium)).lineLimit(1).foregroundStyle(.primary.opacity(0.85))
            Spacer(minLength: 0)
            if let count, count > 0 {
                Text("\(count)").font(.system(size: 14, weight: .medium)).monospacedDigit().foregroundStyle(.primary.opacity(0.4))
            }
        }
        .frame(height: 56)
        .padding(.leading, CGFloat(row.depth) * 22)
        .contentShape(Rectangle())
    }

    private func icons(_ spaces: [MobileSpaces.SpaceView]) -> some View {
        HStack(spacing: 30) {
            ForEach(spaces) { space in
                Button { model.selected = space.id } label: {
                    Group {
                        if let symbol = space.symbol, UIImage(systemName: symbol) != nil {
                            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                        } else {
                            Text(space.emoji.isEmpty ? "•" : space.emoji).font(.system(size: 19))
                        }
                    }
                    .opacity(space.id == model.selected ? 1 : 0.4)
                    .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("space-icon-\(space.title)")
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder private var empty: some View {
        if case .loading = model.state {
            ProgressView().accessibilityIdentifier("spaces-loading")
        } else {
            // Signed in or not, iCloud Drive is the folder's business: the hint goes (Pane).
            SyncIntroView(iCloud: true, folder: SyncedSidebar.chosenName,
                          empty: { if case .nothingSynced = model.state { return true } else { return false } }(),
                          choose: model.choose)
        }
    }

    /// The Space's colour, softened as Arc Search's sheet is.
    private func tint(for space: MobileSpaces.SpaceView?) -> Color {
        guard let fill = style(for: space)?.fill, let color = UIColor(hex: fill) else { return Color(.systemGroupedBackground) }
        return Color(color)
    }

    private func style(for space: MobileSpaces.SpaceView?) -> MobileSpaces.SheetStyle? {
        space.flatMap { MobileSpaces.sheetStyle(colors: $0.colors) }
    }
}

extension UIColor {
    /// "#RRGGBB" or "RRGGBB".
    convenience init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255, blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }

    func blended(with other: UIColor, by amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0, r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * amount, green: g1 + (g2 - g1) * amount, blue: b1 + (b2 - b1) * amount, alpha: 1)
    }
}

/// Before anything has synced: Pane's version of Arc Search's "Sync with Arc Desktop" sheet
/// (`MobileSyncIntro`), pale with a coral and blue glow at the top, the logo, the title in
/// Arc's blue and two buttons; each leads to a page with a drawn smile and "Go back". The Mac one
/// ends in Pane's "Choose the Folder…", which opens Files on the folder the Mac syncs into.
struct SyncIntroView: View {
    let iCloud: Bool
    /// The folder picked already, and whether it holds no Spaces yet.
    var folder: String? = nil
    var empty = false
    var choose: (URL) -> Void = { _ in }
    @State private var page: MobileSyncIntro.Page = .intro
    @State private var picking = false

    private let blue = Color(red: 0.208, green: 0.31, blue: 1)

    var body: some View {
        ZStack {
            Color(red: 0.91, green: 0.94, blue: 0.99).ignoresSafeArea()
            VStack {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.75, green: 0.8, blue: 0.92), Color(red: 0.86, green: 0.89, blue: 0.96)], startPoint: .topLeading, endPoint: .bottom)
                    RadialGradient(colors: [Color(red: 0.95, green: 0.55, blue: 0.57).opacity(0.85), .clear], center: .init(x: 0.75, y: 0.15), startRadius: 0, endRadius: 260)
                }
                .frame(height: 320)
                .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
                Spacer()
            }
            .ignoresSafeArea()
            Group {
                switch page {
                case .intro: intro
                case .haveMac: detail(MobileSyncIntro.haveMacTitle, MobileSyncIntro.haveMacBody(iCloud: iCloud), picksFolder: true)
                case .noMac: detail(MobileSyncIntro.noMacTitle, MobileSyncIntro.noMacBody)
                }
            }
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.3), value: page)
        .environment(\.colorScheme, .light)
        // A container, so the identifier isn't copied onto every text inside.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spaces-empty")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { choose(url) }
        }
        // A folder picked that holds nothing yet: straight to where another one is picked.
        .onAppear { if empty { page = .haveMac } }
    }

    private var intro: some View {
        VStack(spacing: 10) {
            Spacer()
            Image("LaunchMark").resizable().frame(width: 30, height: 30).accessibilityHidden(true)
            Text(MobileSyncIntro.title).font(.system(size: 30, weight: .heavy)).foregroundStyle(blue).multilineTextAlignment(.center)
                .accessibilityIdentifier("sync-title")
            Text(MobileSyncIntro.body).font(.system(size: 16)).foregroundStyle(Color(white: 0.25)).multilineTextAlignment(.center)
            Spacer()
            button(MobileSyncIntro.haveMacButton, id: "sync-have-mac") { page = .haveMac }
            button(MobileSyncIntro.noMacButton, id: "sync-no-mac") { page = .noMac }
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 22)
    }

    private func detail(_ title: String, _ body: String, picksFolder: Bool = false) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Smile().stroke(blue, style: StrokeStyle(lineWidth: 6, lineCap: .round)).frame(width: 64, height: 56).accessibilityHidden(true)
            Text(title).font(.system(size: 30, weight: .heavy)).foregroundStyle(blue).multilineTextAlignment(.center)
                .accessibilityIdentifier("sync-detail-title")
            Text(body).font(.system(size: 16)).foregroundStyle(Color(white: 0.3)).multilineTextAlignment(.center)
            if picksFolder {
                if let folder, empty {
                    Text(MobileSyncIntro.nothingIn(folder)).font(.system(size: 14)).foregroundStyle(Color(white: 0.4)).multilineTextAlignment(.center)
                        .accessibilityIdentifier("sync-folder-empty")
                }
                button(folder == nil ? MobileSyncIntro.chooseFolder : MobileSyncIntro.chooseAnotherFolder, id: "sync-choose-folder") { picking = true }
                    .padding(.top, 6)
            }
            Spacer()
            Spacer()
            Button { page = .intro } label: {
                Label(MobileSyncIntro.goBack, systemImage: "arrow.left").font(.system(size: 16, weight: .medium)).foregroundStyle(.black)
            }
            .accessibilityIdentifier("sync-go-back")
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 44)
    }

    private func button(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 17, weight: .medium)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// Arc Search's drawn smile: two short strokes for eyes over a curve.
private struct Smile: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.36, y: 0)); path.addLine(to: CGPoint(x: rect.width * 0.33, y: rect.height * 0.4))
        path.move(to: CGPoint(x: rect.width * 0.66, y: rect.height * 0.05)); path.addLine(to: CGPoint(x: rect.width * 0.66, y: rect.height * 0.38))
        path.move(to: CGPoint(x: 0, y: rect.height * 0.7))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: rect.height * 0.85), control: CGPoint(x: rect.width * 0.45, y: rect.height * 1.15))
        return path
    }
}
