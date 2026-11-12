import AppKit

/// Cra became Pane on 12 Nov 2026 (CraCore Brand): a new bundle id, a new data folder and a new
/// defaults domain. The first launch of Pane brings everything over before anything reads it:
/// Cra's data folder (spaces, tabs, history, Chromium's profile with its sign-ins and
/// extensions, settings), Cra's defaults (the app icon, window frames) and Cra's WebKit stores.
/// Cra's own files stay where they were, so the old Cra.app still opens as it was.
/// Runs from main.swift once the NSApplication exists, before AppDelegate loads the store.
enum LegacyDataMigration {
    @MainActor static func runIfNeeded() {
        let fm = FileManager.default
        let plan = DataFolder.plan(target: AppPaths.defaultSupportDir, legacy: AppPaths.legacySupportDir,
                                   overridden: AppPaths.dataDirOverride != nil) { fm.fileExists(atPath: $0.path) }
        guard case .copy(let from, let to) = plan else { return }
        let legacyID = AppPaths.isDevBuild ? Brand.Legacy.devBundleIdentifier : Brand.Legacy.bundleIdentifier
        // Chromium's databases are only whole while no Cra has them open.
        waitForCraToQuit(bundleID: legacyID)
        do {
            try DataFolder.copy(from, to: to)
        } catch {
            let alert = AppDialog(title: "\(Brand.name) couldn’t bring over your \(Brand.Legacy.name) data",
                                  message: "\(error.localizedDescription) Nothing was changed; \(Brand.name) tries again the next time it opens.")
            alert.runModal()
            exit(1)
        }
        copyDefaults(from: legacyID, folder: from, to: to)
        copyWebKitStores(from: legacyID)
        NSLog("\(Brand.name): brought over \(Brand.Legacy.name)'s data from %@ to %@", from.path, to.path)
    }

    /// Cra's defaults into Pane's: Cra's values win over any a test copy wrote first. Paths into
    /// Cra's data folder (the custom app icon's) point into Pane's.
    private static func copyDefaults(from legacyID: String, folder: URL, to target: URL) {
        let defaults = UserDefaults.standard
        guard let id = Bundle.main.bundleIdentifier, id != legacyID,
              let old = defaults.persistentDomain(forName: legacyID), !old.isEmpty else { return }
        var merged = defaults.persistentDomain(forName: id) ?? [:]
        let oldPrefix = folder.path + "/", newPrefix = target.path + "/"
        for (key, value) in old {
            if let path = value as? String, path.hasPrefix(oldPrefix) {
                merged[key] = newPrefix + path.dropFirst(oldPrefix.count)
            } else {
                merged[key] = value
            }
        }
        defaults.setPersistentDomain(merged, forName: id)
        defaults.synchronize()
    }

    /// ~/Library/WebKit/<Cra's id>/WebsiteDataStore/<uuid> → Pane's: the cookies and storage of the
    /// pages WebKit shows (DRM sites). WebKitStores keeps the uuids (AppPaths.identityDir).
    private static func copyWebKitStores(from legacyID: String) {
        guard let id = Bundle.main.bundleIdentifier, id != legacyID else { return }
        let fm = FileManager.default
        let webKit = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/WebKit", isDirectory: true)
        let old = webKit.appendingPathComponent("\(legacyID)/WebsiteDataStore", isDirectory: true)
        let new = webKit.appendingPathComponent("\(id)/WebsiteDataStore", isDirectory: true)
        guard let stores = try? fm.contentsOfDirectory(atPath: old.path), !stores.isEmpty else { return }
        try? fm.createDirectory(at: new, withIntermediateDirectories: true)
        for store in stores where !fm.fileExists(atPath: new.appendingPathComponent(store).path) {
            do { try DataFolder.copy(old.appendingPathComponent(store), to: new.appendingPathComponent(store)) } catch {
                NSLog("\(Brand.name): WebKit store %@ not brought over: %@", store, error.localizedDescription)
            }
        }
    }

    /// A running Cra is asked to quit (its own "Quit Cra?" may come up); the user can cancel,
    /// which leaves Pane closed and the migration for the next launch.
    @MainActor private static func waitForCraToQuit(bundleID: String) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        // By pid, as NewestCopy waits: NSRunningApplication's state follows the run loop, not running yet.
        func open() -> [NSRunningApplication] { apps.filter { kill($0.processIdentifier, 0) == 0 || errno != ESRCH } }
        guard !open().isEmpty else { return }
        let ask = AppDialog(title: "Quit \(Brand.Legacy.name) to move to \(Brand.name)?",
                            message: "\(Brand.name) brings over your spaces, tabs, history, sign-ins, extensions and settings from \(Brand.Legacy.name). \(Brand.Legacy.name) has to be closed while it copies them.",
                            actions: [DialogAction("Quit \(Brand.Legacy.name)"), .cancel])
        guard ask.runModal() == .alertFirstButtonReturn else { exit(0) }
        var forced = false
        while true {
            for app in open() {
                if forced { app.forceTerminate() } else { app.terminate() }
            }
            let deadline = Date().addingTimeInterval(10)
            while !open().isEmpty, Date() < deadline { usleep(100_000) }
            if open().isEmpty { break }
            let again = AppDialog(title: "\(Brand.Legacy.name) is still open",
                                  message: "If it asked whether to quit, choose Quit.",
                                  actions: [DialogAction("Try Again"), DialogAction("Force Quit", role: .destructive), .cancel])
            switch again.runModal() {
            case .alertFirstButtonReturn: forced = false
            case .alertSecondButtonReturn: forced = true
            default: exit(0)
            }
        }
        // As NewestCopy does: give Chromium a moment to let go of the profile.
        usleep(300_000)
    }
}
