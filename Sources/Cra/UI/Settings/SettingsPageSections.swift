import AppKit
import CraCEF
import UniformTypeIdentifiers

/// The settings page's sections beyond the plain switches (11 Nov 2026): Profiles, Extensions,
/// Plugins, Max and Performance (no window of their own any more), Sync and the App Icon under
/// General, Air Traffic Control under Tabs & Spaces, and the built-in site searches that can be
/// edited and taken off the list. Their state is merged into SettingsPageBridge.state; their
/// actions come through SettingsPageBridge.run.
extension SettingsPageBridge {
    // MARK: State

    func sectionsState() -> [String: Any] {
        guard let app else { return [:] }
        let store = app.store
        return [
            "profiles": profilesState(store),
            "extensions": extensionsState(store),
            "plugins": pluginsState(),
            "max": maxState(),
            "performance": PerformanceSettingsData.json(),
            "sync": syncState(app.composition.sync),
            "appIcon": appIconState(),
            "routes": routesState(store),
            "prompt": pendingPrompt as Any? ?? NSNull(),
            "hiddenSites": store.settings.hiddenSiteSearches.sorted(),
        ]
    }

    private func profilesState(_ store: SidebarStore) -> [String: Any] {
        func entry(_ id: UUID?, _ name: String) -> [String: Any] {
            let spaces = store.spaces(usingProfile: id)
            let location = store.settings.downloadLocation(profileID: id)
            let folder = DownloadDestinations.folder(profileID: id)
            let languages = BrowserLanguages.summary(Self.languages(store, profileID: id))
            return ["id": id?.uuidString ?? "default", "name": name,
                    "spaces": spaces.isEmpty ? "No Spaces" : spaces.map(\.labeled).joined(separator: ", "),
                    "canDelete": id != nil && spaces.isEmpty, "hasSpace": !spaces.isEmpty,
                    "downloads": ["path": Self.pretty(folder.path), "folderName": folder.lastPathComponent, "ask": location.askWhereToSave],
                    "languages": languages.isEmpty ? "Chromium’s default languages" : languages]
        }
        // The spaces a new profile can be given (Create Profile's second step): not incognito ones.
        let spaces = store.orderedSpaces.filter { !store.isIncognito(space: $0.id) }.map { sp -> [String: Any] in
            let profile = sp.profileID.flatMap { id in store.profiles.first { $0.id == id }?.name } ?? "Default"
            return ["id": sp.id.uuidString, "name": sp.labeled, "profile": profile]
        }
        return ["list": [entry(nil, "Default")] + store.profiles.map { entry($0.id, $0.name) },
                "spaces": spaces, "canRebuildFromArc": ArcProfileRebuilder.isAvailable]
    }

    /// What Chromium holds for the profile now, else what its Preferences file saved.
    private static func languages(_ store: SidebarStore, profileID: UUID?) -> [String] {
        let path = store.profilePath(profile: profileID)
        if let json = CraCEFRuntime.preference(BrowserLanguages.pref, forProfile: path) { return BrowserLanguages.codes(json) }
        let folder = path.map { URL(fileURLWithPath: $0) } ?? AppPaths.chromiumCache.appendingPathComponent("Default")
        return (try? Data(contentsOf: folder.appendingPathComponent("Preferences"))).flatMap(BrowserLanguages.codes(preferencesFile:)) ?? []
    }

    private func extensionsState(_ store: SidebarStore) -> [String: Any] {
        let x = ExtensionStore.shared
        return ["list": x.entries.map { e in
                    ["id": e.id, "name": e.name, "version": e.version, "description": e.description,
                     "managedByChrome": e.managedByChrome, "extensionID": e.extensionID]
                },
                "chromeEngine": store.settings.chromeEngine, "needsRestart": x.needsRestart]
    }

    private func pluginsState() -> [String: Any] {
        let r = LiveFolderPluginStore.shared
        return ["list": r.packages.sorted { $0.manifest.name < $1.manifest.name }.map { p in
                    ["id": p.manifest.id, "name": p.manifest.name, "version": p.manifest.version,
                     "bundled": r.isBundled(p), "enabled": r.isEnabled(p.manifest.id)]
                },
                "reloading": r.reloading, "failures": r.failures]
    }

    private func maxState() -> [String: Any] {
        let status = TidyTabsService.shared.status
        return ["available": status == .available, "explanation": status.explanation, "canOpenSettings": status.canOpenSettings]
    }

    private func syncState(_ sync: SettingsSyncService) -> [String: Any] {
        var location: Any = NSNull()
        var folder = ""
        switch sync.location {
        case .iCloud?: location = "icloud"
        case .folder(let path)?: location = "folder"; folder = Self.pretty(path)
        case nil: break
        }
        let status: String
        if let error = sync.error { status = error }
        else if sync.awaitingDownload { status = "Waiting for iCloud to download your other Mac’s sidebar…" }
        else if sync.pendingChoice != nil { status = "Waiting for your choice" }
        else if let date = sync.lastSync { status = "Synced " + Self.relative.localizedString(for: date, relativeTo: Date()) }
        else { status = "Not synced yet" }
        return [
            "location": location, "folder": folder, "iCloudAvailable": sync.iCloudAvailable,
            "iCloudReason": FileManager.default.ubiquityIdentityToken == nil
                ? "Sign in to iCloud in System Settings to sync this way." : "This build of Cra cannot use iCloud. The signed release can.",
            "status": status, "failed": sync.error != nil, "otherDevices": sync.otherDevices,
            "pending": sync.pendingChoice.map { Self.describe($0) + " Using it replaces this Mac’s sidebar, settings and shortcuts." } as Any? ?? NSNull(),
            "notice": syncNotice as Any? ?? NSNull(),
        ]
    }

    private func appIconState() -> [String: Any] {
        let icons = AppIconManager.shared
        return ["selected": icons.selectedID, "hasCustom": icons.customImage != nil,
                "list": AppIconManager.presets.map { ["id": $0.id, "name": $0.name] } + [["id": AppIconManager.customID, "name": "Custom"]]]
    }

    private func routesState(_ store: SidebarStore) -> [String: Any] {
        let spaces = store.orderedSpaces
        func shown(_ d: LinkDestination) -> String {
            // A route to a deleted space opens in the most recent one: show it that way.
            switch d {
            case .space(let id) where !spaces.contains(where: { $0.id == id }): return LinkDestination.mostRecentSpace.settingsToken
            case .littleWindow(let id?) where !spaces.contains(where: { $0.id == id }): return LinkDestination.littleWindowInUse.settingsToken
            default: return d.settingsToken
            }
        }
        return [
            "list": store.settings.linkRoutes.map { ["id": $0.id.uuidString, "match": $0.match.rawValue, "text": $0.text, "destination": shown($0.destination)] },
            "default": shown(store.settings.defaultLinkDestination),
            "spaces": spaces.map { ["id": $0.id.uuidString, "name": $0.labeled] },
            "matchStyles": LinkMatchStyle.allCases.map { ["value": $0.rawValue, "label": $0.label] },
        ]
    }

    static func pretty(_ path: String) -> String { (path as NSString).abbreviatingWithTildeInPath }

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static func describe(_ s: SyncBundleSummary) -> String {
        let when = s.writtenAt.formatted(date: .abbreviated, time: .shortened)
        return "\(s.device) saved \(s.spaces) \(s.spaces == 1 ? "space" : "spaces") and \(s.tabs) \(s.tabs == 1 ? "tab" : "tabs") on \(when)."
    }

    // MARK: Actions

    /// One of the sections' actions: nil when `name` isn't one of them, else what to tell the user
    /// (.some(nil) when it went).
    func runSection(_ name: String, _ args: [String: SettingsValue]) async -> String?? {
        guard let app else { return .some("Cra isn’t ready.") }
        let store = app.store
        let window = page?.windowController
        let sheetWindow = window?.window ?? NSApp.keyWindow
        func uuid(_ key: String) -> UUID? { args[key]?.string.flatMap(UUID.init(uuidString:)) }
        func profile() -> UUID? { uuid("profile") }
        switch name {
        // Profiles
        // The page asks with its own dialogs (in its light or dark, 11 Nov 2026); these just do it.
        case "createProfile":
            let name = (args["name"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return .some("Give the Profile a name.") }
            let ids = Set((args["spaces"]?.string ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) })
            let p = store.createProfile(name: name)
            for s in store.orderedSpaces where ids.contains(s.id) && !store.isIncognito(space: s.id) { store.setProfile(p.id, forSpace: s.id) }
            CraLog.note("settings page created a profile for \(ids.count) space\(ids.count == 1 ? "" : "s")")
        case "renameProfile":
            let name = (args["name"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let id = uuid("id"), store.profiles.contains(where: { $0.id == id }), !name.isEmpty else { return .some(nil) }
            store.renameProfile(id, to: name)
        case "deleteProfile":
            guard let id = uuid("id"), store.profiles.contains(where: { $0.id == id }) else { return .some(nil) }
            guard store.spaces(usingProfile: id).isEmpty else { return .some("Only Profiles not assigned to any Spaces can be deleted.") }
            store.deleteProfile(id)
        case "newProfileDialog":
            // Create a new Profile: Cra's dialog, the same one Spaces ▸ Change Profile opens, in the space's colours.
            guard let controller = window ?? app.mainWindows.first, let w = controller.window else { return .some(nil) }
            controller.showNewProfileDialog(over: w)
        case "dismissPrompt":
            pendingPrompt = nil
            pendingPlugin = nil
            pendingImport = nil
        case "installPlugin":
            guard let archive = pendingPlugin else { return .some(nil) }
            pendingPrompt = nil
            pendingPlugin = nil
            do { try await LiveFolderPluginStore.shared.install(archive.package.directory) } catch { return .some(error.localizedDescription) }
        case "syncImportConfirm":
            guard let url = pendingImport else { return .some(nil) }
            pendingPrompt = nil
            pendingImport = nil
            syncNotice = app.composition.sync.importBundle(from: url) ? "Settings imported." : "The folder holds no Cra settings."
        case "rebuildArcProfiles":
            ArcProfileRebuilder.run(store: store) { [weak app] in app?.relaunch() }
        case "openProfilePage":
            guard let url = args["url"]?.string else { return .some(nil) }
            let target = window ?? app.useNormalWindow()
            app.openExtensionPage(url, window: target.windowID, profile: store.profile(profile())?.directoryName ?? "Default", singleton: true)
        case "profileDownloads":
            var l = store.settings.downloadLocation(profileID: profile())
            switch args["choice"]?.string {
            case "ask": l.askWhereToSave = true
            case "folder": l.askWhereToSave = false
            case "other":
                guard let url = await chooseFolder(in: sheetWindow, start: DownloadDestinations.folder(profileID: profile()),
                                                   message: "Choose where downloaded files are saved.") else { return .some(nil) }
                l.folder = url.standardizedFileURL.path == DownloadDestinations.downloadsFolder.standardizedFileURL.path ? nil : url.path
                l.askWhereToSave = false
            default: return .some(nil)
            }
            store.settings.setDownloadLocation(l, profileID: profile())

        // Extensions
        case "addExtension":
            guard let url = await chooseFolder(in: sheetWindow, start: nil, prompt: "Add",
                                               message: "Choose an unpacked extension folder (it holds manifest.json).") else { return .some(nil) }
            do { try ExtensionStore.shared.add(folder: url) } catch { return .some(error.localizedDescription) }
        case "removeExtension":
            guard let id = args["id"]?.string, let e = ExtensionStore.shared.entries.first(where: { $0.id == id }) else { return .some(nil) }
            if e.managedByChrome {
                _ = store.createTab(url: "chrome://extensions/?id=\(e.extensionID)", select: true, window: window?.windowID)
            } else {
                ExtensionStore.shared.remove(e)
            }

        // Plugins
        case "setPluginEnabled":
            guard let id = args["id"]?.string, let on = args["on"]?.bool else { return .some(nil) }
            await LiveFolderPluginStore.shared.setEnabled(on, id: id)
        case "reloadPlugins":
            await LiveFolderPluginStore.shared.reload()
            await LiveFolderManager.shared.migrateFolders()
            LiveFolderManager.shared.refreshStale()
        case "removePlugin":
            guard let id = args["id"]?.string, let p = LiveFolderPluginStore.shared.packages.first(where: { $0.manifest.id == id }) else { return .some(nil) }
            do { try await LiveFolderPluginStore.shared.remove(p) } catch { return .some(error.localizedDescription) }
        case "addPlugin":
            return .some(await addPlugin(in: sheetWindow))

        // Max
        case "maxRefresh":
            TidyTabsService.shared.refresh()
        case "openAppleIntelligence":
            TidyTabsService.shared.openSystemSettings()

        // Performance
        case "perfRefresh":
            PerformanceSettingsData.refresh(recording: store.settings.perfRecording) { [weak self] in self?.push() }
        case "perfCopySummary":
            if !PerformanceSettingsData.copySummary() { return .some("Nothing recorded yet.") }
        case "perfClear":
            PerformanceSettingsData.clear()

        // Sync
        case "syncICloud":
            syncNotice = nil
            if args["on"]?.bool == true {
                if case .failed(let reason) = app.composition.sync.enableICloud() { syncNotice = reason }
            } else {
                app.composition.sync.disable()
            }
        case "syncFolder":
            guard let url = await chooseFolder(in: sheetWindow, start: nil, prompt: "Sync Here",
                                               message: "Choose a folder your Macs share, in Dropbox, OneDrive or a similar service. Cra keeps its files in a “Cra” folder inside it.") else { return .some(nil) }
            syncNotice = nil
            if case .failed(let reason) = app.composition.sync.enable(folder: url) { syncNotice = reason }
        case "syncStop":
            app.composition.sync.disable()
        case "syncUseRemote":
            app.composition.sync.useRemote()
        case "syncUseLocal":
            app.composition.sync.useLocal()
        case "syncExport":
            guard let url = await chooseFolder(in: sheetWindow, start: nil, prompt: "Export",
                                               message: "Choose where to save a “Cra” folder with your sidebar, settings and shortcuts.") else { return .some(nil) }
            syncNotice = app.composition.sync.export(to: url).map { "Not exported: \($0)" } ?? "Exported to \(Self.pretty(url.path))/Cra."
        case "syncImport":
            guard let url = await chooseFolder(in: sheetWindow, start: nil, prompt: "Import",
                                               message: "Choose the folder that holds the exported “Cra” folder, or that folder itself.") else { return .some(nil) }
            guard let summary = app.composition.sync.summary(ofBundleIn: url) else {
                syncNotice = "The folder holds no Cra settings."
                return .some(nil)
            }
            pendingImport = url
            pendingPrompt = ["title": "Import these settings?",
                             "message": Self.describe(summary) + " Importing replaces this Mac’s sidebar, settings and shortcuts.",
                             "confirm": "syncImportConfirm", "confirmLabel": "Import"]
        case "openICloudSettings":
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings")!)

        // App icon
        case "appIcon":
            guard let id = args["id"]?.string else { return .some(nil) }
            if id == AppIconManager.customID, AppIconManager.shared.customImage == nil { return .some(await chooseAppIcon(in: sheetWindow)) }
            AppIconManager.shared.select(id)
        case "appIconChoose":
            return .some(await chooseAppIcon(in: sheetWindow))
        case "appIconRemoveCustom":
            AppIconManager.shared.removeCustom()

        // Air Traffic Control
        case "addRoute":
            store.settings.linkRoutes.append(LinkRoute())
        case "removeRoute":
            guard let id = uuid("id") else { return .some(nil) }
            store.settings.linkRoutes.removeAll { $0.id == id }
        case "editRoute":
            guard let id = uuid("id"), let i = store.settings.linkRoutes.firstIndex(where: { $0.id == id }) else { return .some(nil) }
            if let m = args["match"]?.string.flatMap(LinkMatchStyle.init(rawValue:)) { store.settings.linkRoutes[i].match = m }
            if let t = args["text"]?.string { store.settings.linkRoutes[i].text = t }
            if let d = args["destination"]?.string.flatMap(LinkDestination.init(settingsToken:)) { store.settings.linkRoutes[i].destination = d }
        case "setDefaultDestination":
            guard let d = args["destination"]?.string.flatMap(LinkDestination.init(settingsToken:)) else { return .some(nil) }
            store.settings.defaultLinkDestination = d

        // Built-in site searches
        case "hideSite":
            guard let host = args["host"]?.string?.lowercased() else { return .some(nil) }
            store.settings.hiddenSiteSearches.insert(host)
        case "restoreSites":
            store.settings.hiddenSiteSearches = []
        default:
            return nil
        }
        push()
        return .some(nil)
    }

    func chooseFolder(in window: NSWindow?, start: URL?, prompt: String = "Select", message: String) async -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = start
        panel.prompt = prompt
        panel.message = message
        let response = window != nil ? await panel.beginSheetModal(for: window!) : panel.runModal()
        return response == .OK ? panel.url : nil
    }

    private func chooseAppIcon(in window: NSWindow?) async -> String? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image for Cra’s icon"
        panel.prompt = "Use as Icon"
        let response = window != nil ? await panel.beginSheetModal(for: window!) : panel.runModal()
        guard response == .OK, let url = panel.url else { return nil }
        do { try AppIconManager.shared.setCustom(from: url) } catch { return "“\(url.lastPathComponent)” isn’t an image Cra can read." }
        return nil
    }

    /// Add Plugin…: the ZIP, then what it may reach, said before it is installed.
    private func addPlugin(in window: NSWindow?) async -> String? {
        guard let window else { return nil }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Plugin"
        panel.message = "Choose a ZIP archive containing a live folder plugin."
        guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return nil }
        let archive: LiveFolderPluginArchive
        do { archive = try await Task.detached { try LiveFolderPluginArchive(url: url) }.value } catch { return error.localizedDescription }
        let package = archive.package
        var permissions = package.manifest.sessionOrigins.map { "• " + $0 }
        if package.manifest.sessionSetting != nil { permissions.append("• The address you enter when you add its folder") }
        let message = permissions.isEmpty
            ? "This plugin doesn’t use your browser session. It can’t read files or reach the network."
            : "This plugin can load pages from these sites signed in as you, with the profile of the Space its folder is in, "
                + "and can send what it reads to any of them:\n\n" + permissions.joined(separator: "\n")
                + "\n\nOnly add plugins from people you trust."
        // The page asks (its dialog), then installPlugin installs it.
        pendingPlugin = archive
        pendingPrompt = ["title": "Add “\(package.manifest.name)”?", "message": message, "confirm": "installPlugin", "confirmLabel": "Add Plugin"]
        return nil
    }
}
