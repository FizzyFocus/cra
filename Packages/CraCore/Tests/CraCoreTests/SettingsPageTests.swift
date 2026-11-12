import CraCore
import Foundation
import Testing

/// Settings is the page pane://settings (10 Nov 2026; cra://settings before the rebrand), its sections after a slash, and it writes
/// settings through SettingsBridge.
struct SettingsPageTests {
    @Test func addressAndSections() {
        #expect(SettingsPage.owns("pane://settings"))
        #expect(SettingsPage.owns("pane://settings/"))
        #expect(SettingsPage.owns("PANE://Settings/privacy"))
        #expect(!SettingsPage.owns("pane://debug?windowState=x"))
        #expect(!SettingsPage.owns("https://settings.example.com"))
        #expect(!SettingsPage.owns("chrome://settings"))
        #expect(SettingsPage.section(of: "pane://settings") == .general)
        #expect(SettingsPage.section(of: "pane://settings/search-engines") == .search)
        #expect(SettingsPage.section(of: "pane://settings/tabs-and-spaces/") == .tabs)
        #expect(SettingsPage.section(of: "pane://settings/nonsense") == .general)
        #expect(SettingsPage.url(.general) == "pane://settings")
        #expect(SettingsPage.url(.shortcuts) == "pane://settings/shortcuts")
        #expect(SettingsPage.Section.allCases.map(\.title)
            == ["General", "Search Engines", "Appearance", "Tabs & Spaces", "Shortcuts", "Privacy", "Advanced",
                "Profiles", "Extensions", "Plugins", "Max", "Performance"])
        #expect(SettingsPage.section(of: "pane://settings/performance") == .performance, "every section is in the page")
        for s in SettingsPage.Section.allCases { #expect(SettingsPage.section(of: SettingsPage.url(s)) == s) }
    }

    /// Cra's address (a saved tab, a bookmark, upstream code) is still the settings page (12 Nov 2026).
    @Test func craAddressIsAnAlias() {
        #expect(SettingsPage.owns("cra://settings"))
        #expect(SettingsPage.owns("CRA://Settings/privacy"))
        #expect(!SettingsPage.owns("cra://debug?windowState=x"))
        #expect(SettingsPage.section(of: "cra://settings/search-engines") == .search)
        #expect(SettingsPage.section(of: "cra://settings/nonsense") == .general)
    }

    @Test func messagesFromThePage() {
        #expect(SettingsBridge.Message(body: ["op": "state"]) == .state)
        #expect(SettingsBridge.Message(body: ["op": "set", "key": "httpsOnly", "value": NSNumber(value: true)])
            == .set(key: "httpsOnly", value: .bool(true)))
        #expect(SettingsBridge.Message(body: ["op": "set", "key": "defaultSpaceOpacity", "value": NSNumber(value: 0.5)])
            == .set(key: "defaultSpaceOpacity", value: .number(0.5)))
        #expect(SettingsBridge.Message(body: ["op": "action", "name": "addSite", "args": ["name": "Yummy", "shortcut": "ya"]])
            == .action(name: "addSite", args: ["name": .string("Yummy"), "shortcut": .string("ya")]))
        #expect(SettingsBridge.Message(body: ["op": "section", "section": "privacy"]) == .section(.privacy))
        #expect(SettingsBridge.Message(body: ["op": "section", "section": "nowhere"]) == nil)
        // Questions go to Cra's own dialog, the one every alert uses (11 Nov 2026).
        let ask = SettingsBridge.Message(body: ["op": "dialog", "title": "Delete “Work”?", "message": "Gone for good.",
                                               "confirmLabel": "Delete Profile", "destructive": true])
        #expect(ask == .dialog(.init(title: "Delete “Work”?", message: "Gone for good.", input: nil, placeholder: "",
                                     confirmLabel: "Delete Profile", destructive: true, requiresInput: false)))
        #expect(SettingsBridge.Message(body: ["op": "dialog"]) == nil, "a question needs a title")
        #expect(SettingsBridge.Message(body: ["op": "set", "key": "httpsOnly"]) == nil)
        #expect(SettingsBridge.Message(body: "state") == nil)
    }

    @Test func writesASettingTheWaySettingsJSONReadsIt() throws {
        var s = AppSettings()
        s.httpsOnly = false
        let on = try SettingsBridge.applying("httpsOnly", .bool(true), to: s)
        #expect(on.httpsOnly)
        let later = try SettingsBridge.applying("tabSleepAfter", .string("oneHour"), to: s)
        #expect(later.tabSleepAfter == .oneHour)
        let dark = try SettingsBridge.applying("websiteAppearance", .string("dark"), to: s)
        #expect(dark.websiteAppearance == .dark)
        let faint = try SettingsBridge.applying("defaultSpaceOpacity", .number(0.01), to: s)
        #expect(faint.defaultSpaceOpacity == ThemeOpacity.range.lowerBound, "kept to what a theme takes")
        // Everything else stays as it was.
        #expect(on.tabSleepAfter == s.tabSleepAfter && on.customSiteSearches == s.customSiteSearches)
    }

    @Test func refusesWhatThePageMayNotWrite() {
        let s = AppSettings()
        #expect(throws: SettingsBridge.Failure.notEditable("developerHosts")) {
            try SettingsBridge.applying("developerHosts", .string("x"), to: s)
        }
        #expect(throws: SettingsBridge.Failure.notEditable("hasSeenImportPrompt")) {
            try SettingsBridge.applying("hasSeenImportPrompt", .bool(true), to: s)
        }
        #expect(throws: SettingsBridge.Failure.invalid("httpsOnly")) {
            try SettingsBridge.applying("httpsOnly", .string("yes"), to: s)
        }
        #expect(throws: SettingsBridge.Failure.invalid("tabSleepAfter")) {
            try SettingsBridge.applying("tabSleepAfter", .string("forever"), to: s)
        }
    }

    /// Air Traffic Control's destinations as the page's menus name them, and back.
    @Test func linkDestinationTokens() {
        let id = UUID()
        for d in [LinkDestination.mostRecentSpace, .space(id), .littleWindowInUse, .littleWindow(space: id)] {
            #expect(LinkDestination(settingsToken: d.settingsToken) == d)
        }
        #expect(LinkDestination.mostRecentSpace.settingsToken == "recent")
        #expect(LinkDestination.littleWindowInUse.settingsToken == "little")
        #expect(LinkDestination(settingsToken: "space:nope") == nil)
        #expect(LinkDestination(settingsToken: "elsewhere") == nil)
    }

    /// Every key the page writes is one settings.json has, so none is silently dropped.
    @Test func editableKeysAreSettings() throws {
        let keys = Set(try SettingsBridge.json(AppSettings()).keys)
        #expect(SettingsBridge.editableKeys.subtracting(keys).isEmpty)
    }

    /// View ▸ Developer ▸ View Source does nothing on the settings page (upstream #348's ViewSource
    /// rule, which replaced SettingsPageBrowser's own empty viewSource()).
    @Test func theSettingsPageHasNoSource() {
        #expect(ViewSource.address(for: SettingsPage.address) == nil)
        #expect(ViewSource.address(for: SettingsPage.address + "/privacy") == nil)
    }

    /// Settings ▸ Privacy ▸ Fingerprinting protection (upstream 3e3a82b's switch, on the page here):
    /// off by default, and the page's switch writes it as settings.json reads it.
    @Test func fingerprintingProtectionIsThePrivacySwitch() throws {
        let s = AppSettings()
        #expect(!s.fingerprintingProtection)
        #expect(SettingsBridge.editableKeys.contains("fingerprintingProtection"))
        let on = try SettingsBridge.applying("fingerprintingProtection", .bool(true), to: s)
        #expect(on.fingerprintingProtection && on.httpsOnly == s.httpsOnly)
        let off = try SettingsBridge.applying("fingerprintingProtection", .bool(false), to: on)
        #expect(!off.fingerprintingProtection)
    }
}
