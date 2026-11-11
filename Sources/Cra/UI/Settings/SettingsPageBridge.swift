import AppKit
import CraCEF
import WebKit

/// `window.craSettings` on the settings page (SettingsPageBrowser): the page's reads, writes and
/// actions (CraCore SettingsBridge), answered with the whole state, and the state pushed to the
/// page whenever a setting, a shortcut or the system's answer changes.
@MainActor
final class SettingsPageBridge: NSObject, WKScriptMessageHandlerWithReply {
    private(set) weak var page: SettingsPageBrowser?
    /// What the last Sync action said (exported, imported, why iCloud couldn't start).
    var syncNotice: String?
    /// A question for the page to ask in its own dialog ({title, message, confirm, confirmLabel}),
    /// and what answering yes acts on: a plugin to install, a settings folder to import.
    var pendingPrompt: [String: Any]?
    var pendingPlugin: LiveFolderPluginArchive?
    var pendingImport: URL?
    private var pushQueued = false
    /// The shortcut being recorded (its action's id), and the key monitor doing it.
    private var recording: String?
    private var keyMonitor: Any?
    private var stopped = false
    private var readOnce = false

    init(page: SettingsPageBrowser) {
        self.page = page
    }

    var app: AppDelegate? { NSApp.delegate as? AppDelegate }

    func start() {
        watch()
        SystemIntegration.shared.refresh()
        SecureDNSSetting.shared.refresh()
    }

    func stop() {
        stopped = true
        stopRecording()
    }

    // MARK: Messages

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let m = SettingsBridge.Message(body: message.body) else { replyHandler(nil, "Cra doesn’t know that message."); return }
        handle(m, reply: replyHandler)
    }

    private func handle(_ m: SettingsBridge.Message, reply: @escaping @MainActor (Any?, String?) -> Void) {
        switch m {
        case .state:
            if !readOnce {
                readOnce = true
                CraLog.note("settings page read its state (\(SettingsPage.section(of: page?.currentURL ?? "").rawValue))")
            }
            reply(state(), nil)
        case .section(let s):
            page?.didShowSection(s)
            CraLog.note("settings page shows \(s.rawValue)")
            reply(nil, nil)
        case .set(let key, let value):
            if let error = set(key, value) { reply(nil, error) } else { reply(state(), nil) }
        case .dialog(let q):
            ask(q, reply: reply)
        case .action(let name, let args):
            Task { @MainActor in
                let error = await run(name, args)
                if let error { reply(nil, error) } else { reply(self.state(), nil) }
            }
        }
    }

    /// The page's question in Cra's own dialog over the window, in the space's colours (DialogTheme):
    /// the answer is {ok, value}.
    private func ask(_ q: SettingsBridge.Message.Dialog, reply: @escaping @MainActor (Any?, String?) -> Void) {
        guard let window = page?.windowController?.window ?? NSApp.keyWindow else { reply(["ok": false], nil); return }
        let dialog = AppDialog(title: q.title, message: q.message,
                               actions: [DialogAction(q.confirmLabel, role: q.destructive ? .destructive : .primary), .cancel],
                               input: q.input, placeholder: q.placeholder, requiresInput: q.requiresInput)
        dialog.present(over: window) { response in
            let ok = response == .alertFirstButtonReturn
            reply(["ok": ok, "value": ok ? (dialog.input ?? NSNull()) : NSNull()] as [String: Any], nil)
        }
    }

    /// One setting written; nil when it was, else what to tell the user.
    private func set(_ key: String, _ value: SettingsValue) -> String? {
        guard let store = app?.store else { return "Cra isn’t ready." }
        switch key {
        case "launchesAtLogin":
            guard let on = value.bool else { return "Cra couldn’t change that." }
            return SystemIntegration.shared.setLaunchAtLogin(on)
        case "automaticallyUpdates":
            guard let on = value.bool else { return "Cra couldn’t change that." }
            SoftwareUpdater.shared.automaticallyUpdates = on
        case "sharedFavorites":
            guard let on = value.bool else { return "Cra couldn’t change that." }
            store.setFavoritesShared(on)
        case "openExternalLinksInLittleWindow":
            guard let on = value.bool else { return "Cra couldn’t change that." }
            store.settings.openExternalLinksInLittleWindow = on
        default:
            do {
                store.settings = try SettingsBridge.applying(key, value, to: store.settings)
            } catch {
                CraLog.note("settings page: \(key) not written (\(error))")
                return "Cra couldn’t change that."
            }
        }
        CraLog.note("settings page set \(key)")
        if key == "websiteAppearance" { page?.followAppearance() }
        push()
        return nil
    }

    // MARK: Actions

    /// What the page asks Cra to do; nil when it went, else what to tell the user.
    private func run(_ name: String, _ args: [String: SettingsValue]) async -> String? {
        guard let app, let store = app.store as SidebarStore? else { return "Cra isn’t ready." }
        let window = page?.windowController
        CraLog.note("settings page action \(name)")
        switch name {
        case "defaultBrowser":
            await SystemIntegration.shared.makeDefaultBrowser()
        case "addToDock":
            if !SystemIntegration.shared.addToDock() { return "Cra could not be added to the Dock." }
        case "checkForUpdates":
            SoftwareUpdater.shared.checkForUpdates(nil)
        case "downloadLocation":
            var l = store.settings.downloadLocation(profileID: nil)
            switch args["choice"]?.string {
            case "ask": l.askWhereToSave = true
            case "folder": l.askWhereToSave = false
            case "other":
                guard let url = await chooseFolder(in: window?.window) else { return nil }
                l.folder = url.standardizedFileURL.path == DownloadDestinations.downloadsFolder.standardizedFileURL.path ? nil : url.path
                l.askWhereToSave = false
            default: return "Cra doesn’t know that choice."
            }
            store.settings.setDownloadLocation(l, profileID: nil)
        case "setEngine":
            guard let keyword = args["keyword"]?.string, let engine = engines().list.first(where: { $0.keyword == keyword }) else {
                return "Cra doesn’t have that search engine."
            }
            SearchEngines.shared.setDefault(engine, store: store)
        case "openURL":
            guard let url = args["url"]?.string else { return nil }
            _ = store.createTab(url: url, select: true, window: window?.windowID)
        case "addSite", "editSite":
            return saveSite(args, editing: name == "editSite")
        case "removeSite":
            guard let id = args["id"]?.string.flatMap(UUID.init(uuidString:)) else { return nil }
            store.settings.customSiteSearches.removeAll { $0.id == id }
        case "setSiteColor":
            guard let host = args["host"]?.string?.lowercased() else { return nil }
            store.settings.siteSearchColors[host] = args["color"]?.string
        case "editTheme":
            guard let window else { return nil }
            window.showSpaceStyleEditor(space: window.focusedSpace)
        case "manageSpaces":
            window?.showLibrary(.spaces)
        case "importData":
            (window ?? app.main)?.showImport()
        case "exportSpaces":
            SidebarExport.run(store, in: window?.window ?? NSApp.keyWindow)
        case "exportDiagnostics":
            Diagnostics.export(windows: app.mainWindows, store: store)
        case "showDataFolder":
            NSWorkspace.shared.activateFileViewerSelecting([AppPaths.supportDir])
        case "relaunch":
            app.relaunch()
        case "secureDNS":
            let choice: SecureDNSChoice
            switch args["choice"]?.string {
            case "automatic": choice = .automatic
            case "off": choice = .off
            case let s? where s.hasPrefix("provider:"):
                guard let p = SecureDNSProvider.all.first(where: { $0.id == String(s.dropFirst("provider:".count)) }) else { return nil }
                choice = .provider(p)
            default: return nil
            }
            guard let prefs = SecureDNSPrefs(choice), SecureDNSSetting.shared.apply(prefs) else { return "Cra couldn’t change secure DNS." }
        case "recordShortcut":
            guard let id = args["id"]?.string, app.bindings.action(id) != nil else { return nil }
            startRecording(id)
        case "stopRecording":
            stopRecording()
        case "resetShortcut":
            guard let id = args["id"]?.string else { return nil }
            app.bindings.resetShortcuts(for: id)
        case "resetAllShortcuts":
            app.bindings.resetOverrides()
        default:
            guard let answer = await runSection(name, args) else { return "Cra doesn’t know “\(name)”." }
            return answer
        }
        push()
        return nil
    }

    private func saveSite(_ args: [String: SettingsValue], editing: Bool) -> String? {
        guard let store = app?.store else { return nil }
        let id = args["id"]?.string.flatMap(UUID.init(uuidString:))
        let name = (args["name"]?.string ?? "").trimmingCharacters(in: .whitespaces)
        let shortcut = (args["shortcut"]?.string ?? "").trimmingCharacters(in: .whitespaces)
        let url = (args["url"]?.string ?? "").trimmingCharacters(in: .whitespaces)
        let taken = store.settings.customSiteSearches.filter { $0.id != id }.map(\.key)
        if let problem = CustomSiteSearch.problem(name: name, shortcut: shortcut, url: url, taken: taken) { return problem }
        let color = args["color"]?.string.flatMap { $0.hasPrefix("#") ? $0.uppercased() : nil }
        let site = CustomSiteSearch(id: id ?? UUID(), name: name, shortcut: shortcut, url: url, color: color)
        if editing, let i = store.settings.customSiteSearches.firstIndex(where: { $0.id == site.id }) {
            store.settings.customSiteSearches[i] = site
        } else {
            store.settings.customSiteSearches.append(site)
        }
        // A built-in site edited: the edited copy takes its place on the list and in the bar.
        if let replaced = args["replaces"]?.string?.lowercased(), !replaced.isEmpty {
            store.settings.hiddenSiteSearches.insert(replaced)
        }
        CraLog.note("settings page saved site search \(shortcut)")
        push()
        return nil
    }

    private func chooseFolder(in window: NSWindow?) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = DownloadDestinations.folder(profileID: nil)
        panel.prompt = "Select"
        panel.message = "Choose where downloaded files are saved."
        let response: NSApplication.ModalResponse
        if let window { response = await panel.beginSheetModal(for: window) } else { response = panel.runModal() }
        return response == .OK ? panel.url : nil
    }

    // MARK: Recording a shortcut

    private func startRecording(_ id: String) {
        stopRecording()
        recording = id
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            let code = e.keyCode
            let shortcut = Shortcut.from(event: e)
            // Every key goes to the recording (⌘T included) until it ends.
            let taken = MainActor.assumeIsolated { () -> Bool in
                guard let self, let id = self.recording else { return false }
                let bindings = KeyBindingRegistry.shared
                if code == 53 { self.stopRecording(); self.push(); return true }                              // esc
                if code == 51 || code == 117 { bindings.setShortcuts([], for: id); self.stopRecording(); self.push(); return true }
                guard let s = shortcut else { NSSound.beep(); return true }
                bindings.setShortcuts([s], for: id)
                CraLog.note("settings page recorded \(s.display) for \(id)")
                self.stopRecording()
                self.push()
                return true
            }
            return taken ? nil : e
        }
    }

    private func stopRecording() {
        recording = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }

    // MARK: Pushing the state

    /// What the page shows that changes elsewhere in Cra.
    private struct Watched: Equatable {
        var settings: AppSettings
        var shortcuts: [KeyAction]
        var system: [Bool]
        var updates: String
        var dns: String
        /// The sections' own sources (profiles, extensions, plugins, Max, sync, the app icon).
        var sections: [String]
    }

    /// Whatever the page shows changing anywhere in Cra (a toggle in a menu, the theme, a shortcut,
    /// the default browser) is pushed to the page.
    private func watch() {
        guard let app else { return }
        observeChanges(of: { [weak app] () -> Watched? in
            guard let app else { return nil }
            let sys = SystemIntegration.shared
            return Watched(settings: app.store.settings, shortcuts: app.bindings.actions,
                           system: [sys.isDefaultBrowser, sys.isPromptingDefault, sys.isInDock, sys.launchesAtLogin],
                           updates: SoftwareUpdater.shared.lastCheckSummary,
                           dns: SecureDNSSetting.shared.prefs.map { "\($0)" } ?? "",
                           sections: Self.sectionSources(app))
        }) { [weak self] _ in self?.push() }
    }

    /// What the sections show that changes outside the page, as text to compare.
    private static func sectionSources(_ app: AppDelegate) -> [String] {
        let sync = app.composition.sync
        let plugins = LiveFolderPluginStore.shared
        return [
            app.store.profiles.map { "\($0.id)\($0.name)" }.joined(),
            ExtensionStore.shared.entries.map(\.id).joined(separator: ",") + "\(ExtensionStore.shared.needsRestart)",
            plugins.packages.map(\.manifest.id).joined(separator: ",") + "\(plugins.reloading)\(plugins.failures)",
            "\(TidyTabsService.shared.status)",
            "\(String(describing: sync.location))\(sync.error ?? "")\(sync.pendingChoice != nil)\(String(describing: sync.lastSync))\(sync.awaitingDownload)",
            AppIconManager.shared.selectedID + "\(AppIconManager.shared.customImage != nil)",
            { let m = MCPServer.shared; return "\(m.enabled)\(m.status)\(m.lastTool)\(m.allowsScripts)\(m.allowsHistory)" + m.agents.map { "\($0.id)\($0.allowed)" }.joined()
                + "\(MCPAgentInstaller.shared.states)\(MCPAgentInstaller.shared.message)" }(),
        ]
    }

    func push() {
        guard !pushQueued, !stopped else { return }
        pushQueued = true
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopped else { return }
            self.pushQueued = false
            guard let data = try? JSONSerialization.data(withJSONObject: self.state()) else { return }
            self.page?.run("window.craSettings && window.craSettings._update(\(String(decoding: data, as: UTF8.self)))")
        }
    }

    // MARK: The state

    private func engines() -> (selected: String, list: [ChromiumSearchEngine]) {
        let store = app?.store
        let current = SearchEngines.shared.defaultEngine(profilePath: nil, legacy: store?.settings.searchEngine ?? .google)
        var list = SearchEngines.shared.keywords(profilePath: nil).filter(\.isBuiltIn)
        if !list.contains(where: { $0.keyword == current.keyword }) { list.insert(current, at: 0) }
        return (current.keyword, list)
    }

    private static func host(of template: String) -> String { ChromiumSearchEngine.siteHost(of: template) }

    /// Everything the page shows, as JSON.
    func state() -> [String: Any] {
        guard let app else { return [:] }
        let store = app.store
        let s = store.settings
        let favicons = app.favicons
        let sys = SystemIntegration.shared
        let updater = SoftwareUpdater.shared
        let dns = SecureDNSSetting.shared
        let location = s.downloadLocation(profileID: nil)
        let folder = DownloadDestinations.folder(profileID: nil)
        let (selected, engineList) = engines()

        let dnsChoice: String
        switch dns.prefs?.choice ?? .automatic {
        case .automatic: dnsChoice = "automatic"
        case .off: dnsChoice = "off"
        case .provider(let p): dnsChoice = "provider:" + p.id
        case .custom: dnsChoice = "custom"
        }

        var seen = Set<String>()
        let arc = SiteSearch.all.filter { seen.insert($0.name).inserted }
        let keywords = SearchEngines.shared.keywords(profilePath: nil).filter(\.takesTab).map(SiteSearch.init)
            .filter { k in !arc.contains { $0.host == k.host.lowercased() } }
        let sites: [[String: Any]] = (arc + keywords).filter { !s.hiddenSiteSearches.contains($0.host.lowercased()) }.map { site in
            let key = site.host.lowercased()
            return ["name": site.name, "host": key, "iconHost": Self.host(of: site.url).isEmpty ? key : Self.host(of: site.url),
                    "color": SiteSearchColors.shared.hex(for: site, settings: s, favicons: favicons) as Any? ?? NSNull(),
                    "own": s.siteSearchColors[key] != nil, "url": site.url.replacingOccurrences(of: "{searchTerms}", with: "%s")]
        }
        let custom: [[String: Any]] = s.customSiteSearches.map { c in
            ["id": c.id.uuidString, "name": c.name, "shortcut": c.shortcut, "url": c.url,
             "color": c.color as Any? ?? NSNull(), "host": c.host ?? "",
             "shownColor": SiteSearchColors.shared.hex(for: SiteSearch(c), settings: s, favicons: favicons) as Any? ?? NSNull()]
        }
        let bindings = app.bindings
        // Grouped as Settings ▸ Shortcuts shows them (CraCore ShortcutGroups), each key a cap of its own.
        let shortcuts: [[String: Any]] = bindings.actions.filter { $0.section != .none || !$0.shortcuts.isEmpty }.map { a in
            ["id": a.id, "name": a.name, "section": ShortcutGroups.group(id: a.id, section: a.section.rawValue),
             "keys": a.shortcuts.map(\.display), "caps": a.shortcuts.map(\.caps), "overridden": bindings.isOverridden(a.id)]
        }
        func choices<T: RawRepresentable>(_ all: [T], _ label: (T) -> String) -> [[String: Any]] where T.RawValue == String {
            all.map { ["value": $0.rawValue, "label": label($0)] }
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let theme: String = switch s.websiteAppearance { case .automatic: "auto"; case .light: "light"; case .dark: "dark" }

        return sectionsState().merging([
            "section": SettingsPage.section(of: page?.currentURL ?? SettingsPage.address).rawValue,
            "theme": theme,
            "version": "Cra \(version) · Chromium \(CraCEFRuntime.chromiumVersion())",
            "dataFolder": Self.pretty(AppPaths.supportDir.path),
            "settings": (try? SettingsBridge.json(s)) ?? [:],
            "extra": [
                "openExternalLinksInLittleWindow": s.openExternalLinksInLittleWindow,
                "sharedFavorites": s.sharedFavorites,
                "launchesAtLogin": sys.launchesAtLogin,
                "automaticallyUpdates": updater.automaticallyUpdates,
                "accelerationAtLaunch": SettingsLaunch.hardwareAcceleration ?? s.hardwareAcceleration,
            ],
            "system": [
                "isDefaultBrowser": sys.isDefaultBrowser,
                "defaultBrowserName": sys.defaultBrowserName as Any? ?? NSNull(),
                "isPromptingDefault": sys.isPromptingDefault,
                "inDock": sys.isInDock,
            ],
            "updates": ["available": updater.isAvailable, "summary": updater.lastCheckSummary],
            "downloads": ["path": Self.pretty(folder.path), "folderName": folder.lastPathComponent, "ask": location.askWhereToSave],
            "dns": [
                "choice": dnsChoice, "managed": dns.isManaged, "available": dns.prefs != nil,
                "summary": dns.inEffect?.summary ?? "",
                "providers": SecureDNSProvider.all.map { ["id": $0.id, "name": $0.name] },
            ],
            "options": [
                "tabSleepAfter": choices(TabSleepThreshold.allCases, \.label),
                "autoArchive": choices(AutoArchiveThreshold.allCases, \.label),
                "littleWindowArchiveAfter": choices(LittleWindowArchive.allCases, \.label),
                "websiteAppearance": choices(WebsiteAppearance.allCases, \.title),
            ],
            "engines": [
                "selected": selected,
                "list": engineList.map { ["keyword": $0.keyword, "name": $0.name, "host": Self.host(of: $0.url)] },
            ],
            "custom": custom,
            "sites": sites,
            "shortcuts": shortcuts,
            "shortcutGroups": ShortcutGroups.order,
            "recording": recording as Any? ?? NSNull(),
        ]) { _, new in new }
    }
}

/// What the app started with, for settings that only take effect at launch (hardware acceleration).
@MainActor
enum SettingsLaunch {
    static var hardwareAcceleration: Bool?
}
