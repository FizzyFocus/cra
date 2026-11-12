import Foundation

/// Settings is a page of its own (10 Nov 2026), in a tab like Chrome's chrome://settings and Arc's
/// own pages: `pane://settings`, the section after a slash (`pane://settings/search-engines`). ⌘, opens
/// it, or brings its tab to the front. Cra's `cra://settings` (saved tabs, bookmarks) is the same
/// page. Every section is in the page, Profiles, Extensions, Plugins, Max and Performance too (no
/// window of their own since 11 Nov 2026).
public enum SettingsPage {
    public static let scheme = InternalScheme.name
    public static let host = "settings"
    public static let address = "pane://settings"

    /// The page's sections, in its sidebar.
    public enum Section: String, CaseIterable, Sendable {
        case general
        case search = "search-engines"
        case appearance
        case tabs = "tabs-and-spaces"
        case shortcuts
        case privacy
        case advanced
        case profiles
        case extensions
        case plugins
        case max
        case performance

        public var title: String {
            switch self {
            case .general: return "General"
            case .search: return "Search Engines"
            case .appearance: return "Appearance"
            case .tabs: return "Tabs & Spaces"
            case .shortcuts: return "Shortcuts"
            case .privacy: return "Privacy"
            case .advanced: return "Advanced"
            case .profiles: return "Profiles"
            case .extensions: return "Extensions"
            case .plugins: return "Plugins"
            case .max: return "Max"
            case .performance: return "Performance"
            }
        }
    }

    /// Whether `url` is the settings page, at any section ("pane://settings", "pane://settings/",
    /// "pane://settings/privacy", any case), under Cra's scheme too ("cra://settings").
    public static func owns(_ url: String) -> Bool {
        guard let u = URLComponents(string: url), InternalScheme.owns(scheme: u.scheme), u.host?.lowercased() == host else { return false }
        return true
    }

    /// The section `url` opens; General for the page itself and for one it doesn't know.
    public static func section(of url: String) -> Section {
        guard owns(url), let path = URLComponents(string: url)?.path else { return .general }
        let name = path.split(separator: "/").first.map { $0.lowercased() } ?? ""
        return Section(rawValue: name) ?? .general
    }

    /// The address of `section`; General's is the page's own.
    public static func url(_ section: Section) -> String {
        section == .general ? address : "\(address)/\(section.rawValue)"
    }

    /// Shortcuts with one command picked out (Use Both's "Edit the shortcut", #374): the page filters
    /// its list to `action` (`?action=<id>`; the section is still the path's).
    public static func shortcutURL(action: String) -> String {
        var c = URLComponents(string: url(.shortcuts))!
        c.queryItems = [URLQueryItem(name: "action", value: action)]
        return c.string ?? url(.shortcuts)
    }

    /// The command `url` picks out in Shortcuts, as shortcutURL wrote it.
    public static func shortcutAction(of url: String) -> String? {
        guard owns(url), section(of: url) == .shortcuts else { return nil }
        return URLComponents(string: url)?.queryItems?.first { $0.name == "action" }?.value.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The tab's title.
    public static let title = "Settings"
}

/// What the settings page sends Cra (window.craSettings in the page): a read of the whole state, a
/// setting written, or an action Cra runs (a sheet, another page, a file picker).
public enum SettingsBridge {
    public enum Message: Equatable, Sendable {
        case state
        case set(key: String, value: SettingsValue)
        case action(name: String, args: [String: SettingsValue])
        case section(SettingsPage.Section)
        /// A question the page asks in Cra's own dialog (the one Quit Cra? uses, in the space's colours).
        case dialog(Dialog)

        public struct Dialog: Equatable, Sendable {
            public var title: String
            public var message: String
            /// A text field holding this, or none.
            public var input: String?
            public var placeholder: String
            public var confirmLabel: String
            public var destructive: Bool
            public var requiresInput: Bool

            public init(title: String, message: String, input: String?, placeholder: String, confirmLabel: String,
                        destructive: Bool, requiresInput: Bool) {
                self.title = title
                self.message = message
                self.input = input
                self.placeholder = placeholder
                self.confirmLabel = confirmLabel
                self.destructive = destructive
                self.requiresInput = requiresInput
            }
        }

        /// The page's message body (`{op, key, value}`, `{op, name, args}`, `{op, section}`); nil for one
        /// it doesn't make.
        public init?(body: Any) {
            guard let d = body as? [String: Any], let op = d["op"] as? String else { return nil }
            switch op {
            case "state": self = .state
            case "set":
                guard let key = d["key"] as? String, let value = d["value"].flatMap(SettingsValue.init(json:)) else { return nil }
                self = .set(key: key, value: value)
            case "action":
                guard let name = d["name"] as? String else { return nil }
                let raw = d["args"] as? [String: Any] ?? [:]
                self = .action(name: name, args: raw.compactMapValues(SettingsValue.init(json:)))
            case "section":
                guard let s = (d["section"] as? String).flatMap(SettingsPage.Section.init(rawValue:)) else { return nil }
                self = .section(s)
            case "dialog":
                guard let title = d["title"] as? String, !title.isEmpty else { return nil }
                self = .dialog(Dialog(title: title, message: d["message"] as? String ?? "", input: d["input"] as? String,
                                      placeholder: d["placeholder"] as? String ?? "", confirmLabel: d["confirmLabel"] as? String ?? "OK",
                                      destructive: (d["destructive"] as? Bool) ?? false, requiresInput: (d["requiresInput"] as? Bool) ?? false))
            default: return nil
            }
        }
    }

    /// The settings the page writes as they are saved in settings.json. Everything else (where a
    /// window was, what was migrated, the lists other screens edit) the page reads but can't write.
    public static let editableKeys: Set<String> = [
        // General
        "restoreWindows", "startOnNewTab", "warnBeforeQuitting", "keepInMenuBar", "tabSleepTimerEnabled",
        "tabSleepAfter", "tabSleepOnMemoryPressure",
        // Search Engines
        "searchSuggestions",
        // Appearance
        "websiteAppearance", "defaultSpaceOpacity", "defaultSpaceTint", "animateSidebarDocking", "showToolbar", "edgeToEdgeContent", "toolbarShowsFullURL",
        "soundEffects", "shareThemeWithWebsites",
        // Tabs & Spaces
        "newTabsAtTop", "newTabButtonAtTop", "hapticFeedbackOnReorder", "middleClickUnloadsTab", "folderPreviews",
        "favoritePreviews", "calendarHoverPreview", "outlookCalendarPreviews", "outlookMailPreviews", "recentPagesPreviews", "notionCalendarPreviews", "favoriteLogoOutline", "autoPictureInPicture", "showSpaceHeaderOnSingleSpace",
        "littleWindowShortcutEverywhere", "littleWindowOnOptionCommandClick", "littleWindowArchiveAfter", "peekLinksToOtherSites", "peekInEveryTab", "peekExpandInSourceTab",
        "peekOnShiftClick", "openLinksInForeground", "autoArchiveEnabled", "autoArchive",
        // Privacy
        "blockAdsAndTrackers", "blockCookieBanners", "fingerprintingProtection", "httpsOnly", "perfHidesSiteNames", "allowAppleEventsJavaScript",
        // Advanced
        "commandBarCurrentSpaceOnly", "chromeEngine", "pageTopWindowDrag", "boostsEnabled", "hardwareAcceleration", "perfRecording",
        // Max
        "tidyTabs", "tidyTabTitles", "tidyDownloads", "fiveSecondPreviews",
    ]

    public enum Failure: Error, Equatable {
        case notEditable(String)
        case invalid(String)
    }

    /// `settings` with `key` set to `value`, read back the way settings.json is, so a value of the
    /// wrong type or out of range (an unknown case) is refused rather than half applied.
    public static func applying(_ key: String, _ value: SettingsValue, to settings: AppSettings) throws -> AppSettings {
        guard editableKeys.contains(key) else { throw Failure.notEditable(key) }
        var object = try json(settings)
        var v = value
        // A colour's opacity: the slider's 0…1, kept to what a theme takes.
        if key == "defaultSpaceOpacity", case .number(let n) = value { v = .number(ThemeOpacity.clamped(n)) }
        if key == "defaultSpaceTint" {
            guard let hex = value.string.flatMap(SpaceColorPresets.validTint) else { throw Failure.invalid(key) }
            v = .string(hex)
        }
        object[key] = v.json
        do {
            let data = try JSONSerialization.data(withJSONObject: object)
            let back = try JSONDecoder().decode(AppSettings.self, from: data)
            // The decoder falls back to the default for a value it can't read: that's a refusal here.
            guard try json(back)[key].map({ SettingsValue(json: $0) == v }) ?? false else { throw Failure.invalid(key) }
            return back
        } catch let f as Failure {
            throw f
        } catch {
            throw Failure.invalid(key)
        }
    }

    /// The settings as one JSON object, keyed as settings.json is.
    public static func json(_ settings: AppSettings) throws -> [String: Any] {
        let data = try JSONEncoder().encode(settings)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

/// A JSON value from the page: what a WKScriptMessage body holds, made Equatable.
public enum SettingsValue: Equatable, Sendable {
    case bool(Bool)
    case number(Double)
    case string(String)
    case null

    public init?(json: Any) {
        switch json {
        case let n as NSNumber:
            // JSONSerialization and WebKit both hand booleans over as NSNumber's CFBoolean.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) } else { self = .number(n.doubleValue) }
        case let b as Bool: self = .bool(b)
        case let d as Double: self = .number(d)
        case let i as Int: self = .number(Double(i))
        case let s as String: self = .string(s)
        case is NSNull: self = .null
        default: return nil
        }
    }

    public var json: Any {
        switch self {
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .null: return NSNull()
        }
    }

    public var string: String? { if case .string(let s) = self { return s } else { return nil } }
    public var bool: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    public var number: Double? { if case .number(let n) = self { return n } else { return nil } }
}

extension LinkDestination {
    /// How the settings page's menus name a destination (Air Traffic Control): "recent",
    /// "space:<id>", "little" (the Little Window in use) and "little:<id>".
    public var settingsToken: String {
        switch self {
        case .mostRecentSpace: return "recent"
        case .space(let id): return "space:" + id.uuidString
        case .littleWindow(let id): return id.map { "little:" + $0.uuidString } ?? "little"
        }
    }

    public init?(settingsToken token: String) {
        let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count) {
        case ("recent", 1): self = .mostRecentSpace
        case ("little", 1): self = .littleWindowInUse
        case ("little", 2):
            guard let id = UUID(uuidString: parts[1]) else { return nil }
            self = .littleWindow(space: id)
        case ("space", 2):
            guard let id = UUID(uuidString: parts[1]) else { return nil }
            self = .space(id)
        default: return nil
        }
    }
}
