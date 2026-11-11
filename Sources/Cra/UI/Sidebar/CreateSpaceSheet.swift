import AppKit
import SwiftUI

/// What Create a Space holds while it is open: the name, icon, theme and profile, and the actions
/// the window wires in. The window previews `theme` on the space it was opened from, so the whole
/// window shows the new space's look while it is picked (Arc), and puts that space's back after.
@MainActor @Observable
final class CreateSpaceModel {
    var name = ""
    var icon: SpaceIcon = .none
    var theme: SpaceTheme
    var profile: SpaceProfileChoice
    var newProfileName = ""
    /// The theme picker is open beside the sidebar (the Choose a Theme row stays lit).
    var pickingTheme = false
    let profiles: [BrowserProfile]

    @ObservationIgnored var onCreate: () -> Void = {}
    @ObservationIgnored var onCancel: () -> Void = {}
    /// Opens or closes the theme picker at the Choose a Theme row (its frame on screen).
    @ObservationIgnored var onChooseTheme: (CGRect) -> Void = { _ in }
    /// The sidebar's hosting view turns a frame in the panel into one on screen.
    @ObservationIgnored var toScreen: (CGRect) -> CGRect? = { _ in nil }
    /// Asks the name field for the keys (the panel was asked for again while open).
    @ObservationIgnored var focusName: () -> Void = {}

    init(theme: SpaceTheme, profile: SpaceProfileChoice, profiles: [BrowserProfile]) {
        self.theme = theme
        self.profile = profile
        self.profiles = profiles
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedProfileName: String { newProfileName.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// A name, and a name for a new profile when one is being made.
    var isValid: Bool { !trimmedName.isEmpty && (profile != .new || !trimmedProfileName.isEmpty) }
}

/// Arc's Create a Space, in place of the sidebar's content (Arc 1.17x; Sailfish's SpaceEditor
/// hierarchy, Apache-2.0): three tilted cards, "Create a Space" and its line, the name field with
/// the icon button, Profile with its pop-up and note, Choose a Theme (the picker opens beside the
/// sidebar, pointing at the row), then Create Space in the theme's colour and Cancel. Return
/// creates, Escape cancels. It comes in with a short spring, rows a beat after the cards.
struct CreateSpaceSheet: View {
    @Bindable var model: CreateSpaceModel
    @FocusState private var nameFocused: Bool
    @State private var pickingIcon = false
    @State private var appeared = false
    @State private var themeRow: CGRect = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: SpacePalette { model.theme.palette }
    private var dark: Bool { palette.isDark }
    /// Sailfish's measurements of Arc: the name field white 8 % / 60 %, the other rows white 10 % / black 5 %.
    private var fieldFill: Color { dark ? .white.opacity(0.08) : .white.opacity(0.6) }
    private var rowFill: Color { dark ? .white.opacity(0.1) : .black.opacity(0.05) }
    private var rowLit: Color { dark ? .white.opacity(0.16) : .black.opacity(0.09) }

    var body: some View {
        VStack(spacing: 8) {
            CreateSpaceIllustration(theme: model.theme)
                .padding(.top, 30)
                .scaleEffect(appeared ? 1 : 0.9)
            VStack(spacing: 6) {
                Text("Create a Space").font(.system(size: 17, weight: .semibold))
                Text("Separate your tabs for life, work, projects, and more.")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
            .padding(.top, 8)
            .padding(.bottom, 14)
            Group {
                nameRow
                profileRow
                if model.profile == .new { newProfileRow.transition(.move(edge: .top).combined(with: .opacity)) }
                themeButton
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 6)
            Spacer(minLength: 12)
            createButton
            Button("Cancel") { model.onCancel() }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(palette.textSecondary)
                .keyboardShortcut(.cancelAction)
                .padding(.top, 6)
                .padding(.bottom, 12)
        }
        .foregroundStyle(palette.textPrimary)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82)) { appeared = true }
            model.focusName = { nameFocused = true }
        }
        // After it appears, so the field also takes the keys when the window wasn't key yet.
        .task { nameFocused = true }
        .onPreferenceChange(ThemeRowFrame.self) { themeRow = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: model.profile == .new)
    }

    // MARK: Rows

    private func row(fill: Color, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 8) { content() }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
    }

    private var nameRow: some View {
        row(fill: fieldFill) {
            Button { pickingIcon.toggle() } label: {
                Group {
                    switch model.icon {
                    case .none:
                        Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                            .frame(width: 18, height: 18)
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                    case .emoji(let e): Text(e).font(.system(size: 15)).frame(width: 18, height: 18)
                    case .symbol(let s): Image(systemName: s).font(.system(size: 13, weight: .medium)).frame(width: 18, height: 18)
                    }
                }
                .foregroundStyle(palette.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Choose an Icon")
            .accessibilityLabel("Choose an Icon")
            .popover(isPresented: $pickingIcon, arrowEdge: .bottom) {
                SpaceIconPicker(current: model.icon.emoji, currentSymbol: model.icon.symbol,
                                onPick: { model.icon = .emoji($0); pickingIcon = false },
                                onPickSymbol: { model.icon = .symbol($0); pickingIcon = false },
                                onRemove: { model.icon = .none; pickingIcon = false })
                    .frame(width: 272, height: 272)
            }
            TextField("Space name…", text: $model.name)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($nameFocused)
                .onSubmit { if model.isValid { model.onCreate() } }
        }
    }

    private var profileName: String {
        switch model.profile {
        case .existing(nil): "Default"
        case .existing(let id?): model.profiles.first { $0.id == id }?.name ?? "Default"
        case .new: "New Profile"
        }
    }

    private var profileRow: some View {
        row(fill: rowFill) {
            Image(systemName: "face.smiling").font(.system(size: 13)).foregroundStyle(palette.textSecondary)
            Text("Profile").font(.system(size: 13, weight: .semibold))
            Menu {
                Picker("", selection: $model.profile) {
                    Text("Default").tag(SpaceProfileChoice.existing(nil))
                    ForEach(model.profiles) { p in Text(p.name).tag(SpaceProfileChoice.existing(p.id)) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Divider()
                Button("New Profile…") { model.profile = .new }
            } label: {
                HStack(spacing: 4) {
                    Text(profileName)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(rowLit, in: Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .controlSize(.small)
            .fixedSize()
            Spacer(minLength: 0)
            Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .help("Profiles make your Spaces truly separate with their own logins, cookies and site data. Spaces with the same Profile share them.")
        }
    }

    private var newProfileRow: some View {
        row(fill: fieldFill) {
            Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 13)).foregroundStyle(palette.textSecondary)
            TextField("Profile name", text: $model.newProfileName)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit { if model.isValid { model.onCreate() } }
        }
    }

    private var themeButton: some View {
        Button {
            if let screen = model.toScreen(themeRow) { model.onChooseTheme(screen) }
        } label: {
            row(fill: model.pickingTheme ? rowLit : rowFill) {
                Image(systemName: "paintbrush.pointed.fill").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                Text("Choose a Theme").font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                ThemeDots(theme: model.theme)
            }
        }
        .buttonStyle(.plain)
        .background(GeometryReader { g in Color.clear.preference(key: ThemeRowFrame.self, value: g.frame(in: .global)) })
        .animation(.easeOut(duration: 0.12), value: model.pickingTheme)
    }

    /// Not `.disabled`, which would dim the fill: before a name it only stops responding.
    private var createButton: some View {
        let tone = CreateSpaceTones.button(key: model.theme.key?.first ?? model.theme.colors.first, lightTheme: !dark, enabled: model.isValid)
        return Button { if model.isValid { model.onCreate() } } label: {
            Text("Create Space").font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 36)
                .foregroundStyle(Color(hex: tone.text))
                .background(Color(hex: tone.fill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .allowsHitTesting(model.isValid)
        .animation(.easeOut(duration: 0.15), value: model.isValid)
    }
}

/// The Choose a Theme row's frame, in the hosting view's space.
private struct ThemeRowFrame: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

/// The theme's colours as dots at the end of the Choose a Theme row.
private struct ThemeDots: View {
    let theme: SpaceTheme

    var body: some View {
        let colors = theme.key ?? Array(Set(theme.colors)).sorted()
        HStack(spacing: -4) {
            ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { _, hex in
                Circle().fill(Color(hex: hex)).frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
            }
        }
    }
}

/// Arc's three cards over the title: two tilted either side of a straight one, each a white card
/// with a picture, the pictures in the new space's colours.
private struct CreateSpaceIllustration: View {
    let theme: SpaceTheme

    var body: some View {
        let hexes = theme.key ?? theme.colors
        let tint = Color(hex: hexes.first ?? "#C5C6E5")
        ZStack {
            card("leaf.fill", tint: tint, angle: -14)
            card("camera.macro", tint: tint, angle: 14)
            card("laptopcomputer", tint: tint, angle: 0)
        }
        .frame(width: 76, height: 50)
    }

    private func card(_ symbol: String, tint: Color, angle: Double) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(.white)
            .frame(width: 36, height: 42)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tint.opacity(0.55))
                    .overlay(Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(.black.opacity(0.45)))
                    .frame(width: 30, height: 28)
                    .padding(.top, 3)
            }
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            .rotationEffect(.degrees(angle), anchor: .bottom)
            .offset(x: angle * 1.1)
    }
}
