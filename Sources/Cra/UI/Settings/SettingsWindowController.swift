import Foundation

/// The sections of Settings by the names the app's menus and `cra://debug?settingsPane=` use. Every
/// one is a section of the settings page, cra://settings (SettingsPageBrowser): the SwiftUI panes
/// and their window went on 11 Nov 2026. `advanced` is its own section again.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, search, appearance, tabs, shortcuts, privacy, profiles, extensions, plugins, max, performance, advanced
    var id: String { rawValue }

    /// The settings page's section for this pane.
    var pageSection: SettingsPage.Section {
        switch self {
        case .general: return .general
        case .search: return .search
        case .appearance: return .appearance
        case .tabs: return .tabs
        case .shortcuts: return .shortcuts
        case .privacy: return .privacy
        case .advanced: return .advanced
        case .profiles: return .profiles
        case .extensions: return .extensions
        case .plugins: return .plugins
        case .max: return .max
        case .performance: return .performance
        }
    }
}
