import CraCore
import Foundation

/// The Mac's sidebar, as it arrives through sync. Upstream's phone reads the Mac's iCloud
/// container; Pane's free Apple team has none (14 Nov 2026), so the Mac syncs into a folder in
/// iCloud Drive (Settings ▸ General ▸ Sync ▸ Use a Folder…) and the phone reads that folder, which
/// the user picks once in Files (kept as a security-scoped bookmark). `-CraSyncDir <folder>` points
/// a test at a folder instead.
enum SyncedSidebar {
    enum State {
        /// The Mac's sidebar, and when the Mac wrote it (its manifest, else the file's date).
        case spaces(SidebarDocument, writtenAt: Date?)
        /// A folder is picked, but no Mac has synced into it yet (or iCloud Drive is still bringing it).
        case nothingSynced
        /// No folder picked yet, or the picked one can't be reached any more.
        case unavailable
    }

    private static let bookmarkKey = "PaneSyncFolderBookmark"

    /// Keeps `url`, a folder picked in Files, as the place to read from. False when iOS gives no
    /// lasting way back to it.
    @discardableResult
    static func choose(_ url: URL) -> Bool {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { return false }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        return true
    }

    /// The picked folder's name, for the sync sheet.
    static var chosenName: String? { picked()?.lastPathComponent }

    private static func picked() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale { choose(url) }
        return url
    }

    /// What `refresh` is waiting for, for the line over the Spaces.
    enum Activity {
        /// Asking iCloud Drive whether the Mac wrote something newer.
        case checking
        /// iCloud Drive is bringing a newer copy down.
        case downloading
    }

    /// How `refresh` gets on: what the phone holds now (shown at once), what it is waiting for,
    /// and what it ends with.
    enum Progress {
        case read(State)
        case waiting(Activity)
        case finished(State)
    }

    /// Asks iCloud Drive for the Mac's newest Spaces and reads them, off the main thread (14 Nov
    /// 2026, the owner's call: the phone fetches rather than waits for iCloud's own pace). It reads
    /// what is on the phone first, then asks iCloud Drive to bring the newest manifest and sidebar
    /// down and waits for them, up to `timeout`, then reads again. A folder picked where nothing
    /// has synced yet is looked at again until `timeout` too: iCloud Drive may still be listing it.
    static func refresh(timeout: TimeInterval = 12, _ report: @escaping (Progress) -> Void) {
        func send(_ progress: Progress) { DispatchQueue.main.async { report(progress) } }
        DispatchQueue.global(qos: .userInitiated).async {
            let first = read()
            send(.read(first))
            if case .unavailable = first { return send(.finished(first)) }
            if LaunchOptions.value("CraSyncDir") != nil { return send(.finished(first)) }
            let deadline = Date().addingTimeInterval(timeout)
            send(.waiting(.checking))
            var downloading = false
            var state = first
            while Date() < deadline {
                let pending = withFolder { folder in pendingFiles(in: folder) } ?? []
                if pending.isEmpty {
                    if case .nothingSynced = state { Thread.sleep(forTimeInterval: 1); state = read(); continue }
                    break
                }
                if !downloading {
                    downloading = true
                    send(.waiting(.downloading))
                }
                Thread.sleep(forTimeInterval: 0.4)
            }
            send(.finished(downloading ? read() : state))
        }
    }

    /// Asks iCloud Drive to bring the Mac's newest Spaces down without reading them: as the app
    /// comes to the front, so they are there by the time the Spaces sheet opens.
    static func requestDownload() {
        guard LaunchOptions.value("CraSyncDir") == nil, UserDefaults.standard.data(forKey: bookmarkKey) != nil else { return }
        DispatchQueue.global(qos: .utility).async { _ = withFolder { folder in pendingFiles(in: folder) } }
    }

    /// Whether the Mac's Spaces are on the phone already.
    static func hasSpaces(_ done: @escaping (Bool) -> Void) {
        if LaunchOptions.value("CraSyncDir") == nil, UserDefaults.standard.data(forKey: bookmarkKey) == nil { return done(false) }
        DispatchQueue.global(qos: .utility).async {
            let state = read()
            DispatchQueue.main.async {
                if case .spaces = state { done(true) } else { done(false) }
            }
        }
    }

    /// The bundle folder in the picked one (or the test folder), with the picked folder's access
    /// open while `body` runs. Nil with no folder picked.
    private static func withFolder<T>(_ body: (URL) -> T) -> T? {
        let testFolder = LaunchOptions.value("CraSyncDir").map { URL(fileURLWithPath: $0, isDirectory: true) }
        guard let pickedFolder = testFolder ?? picked() else { return nil }
        let scoped = pickedFolder.startAccessingSecurityScopedResource()
        defer { if scoped { pickedFolder.stopAccessingSecurityScopedResource() } }
        // The Mac writes into a "Pane" folder inside the one it was given (SettingsSync): the user may
        // have picked either.
        let folder = SettingsSync.bundleFolder(in: pickedFolder) { FileManager.default.fileExists(atPath: $0.path) }
        return body(folder)
    }

    /// The files the phone reads.
    private static let names = [SettingsSync.manifestName, SettingsSync.sidebarName]

    /// The bundle files iCloud Drive holds a newer copy of than the phone, or none yet: each is asked
    /// for (`startDownloadingUbiquitousItem`). A coordinated look at the folder first, so the
    /// provider lists what the Mac wrote since it last looked.
    private static func pendingFiles(in folder: URL) -> [String] {
        let manager = FileManager.default
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [], error: &error) { url in
            _ = try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey])
        }
        return names.filter { name in
            var file = folder.appendingPathComponent(name)
            file.removeAllCachedResourceValues()
            let placeholder = manager.fileExists(atPath: folder.appendingPathComponent(SettingsSync.placeholderName(for: name)).path)
            let values = try? file.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            let stale = values?.isUbiquitousItem == true && values?.ubiquitousItemDownloadingStatus != .current
            guard placeholder || stale else { return false }
            try? manager.startDownloadingUbiquitousItem(at: file)
            return true
        }
    }

    /// The folder the phone reads, watched while the Spaces sheet is open: iCloud Drive tells a
    /// file presenter when it brings a newer file down, and the sheet reads it then.
    final class Watcher: NSObject, NSFilePresenter {
        let presentedItemURL: URL?
        let presentedItemOperationQueue = OperationQueue.main
        private let picked: URL?
        private let scoped: Bool
        private let changed: () -> Void

        init?(changed: @escaping () -> Void) {
            let testFolder = LaunchOptions.value("CraSyncDir").flatMap { $0 == "demo" ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            guard let pickedFolder = testFolder ?? SyncedSidebar.picked() else { return nil }
            picked = pickedFolder
            scoped = pickedFolder.startAccessingSecurityScopedResource()
            presentedItemURL = SettingsSync.bundleFolder(in: pickedFolder) { FileManager.default.fileExists(atPath: $0.path) }
            self.changed = changed
            super.init()
            NSFileCoordinator.addFilePresenter(self)
        }

        func stop() {
            NSFileCoordinator.removeFilePresenter(self)
            if scoped { picked?.stopAccessingSecurityScopedResource() }
        }

        func presentedItemDidChange() { changed() }
        func presentedSubitemDidChange(at url: URL) { changed() }
        func presentedSubitemDidAppear(at url: URL) { changed() }
    }

    /// A made-up Mac sidebar for tests and screenshots: "Personal" with a favorite, a pinned tab, a
    /// folder holding a tab and a closed folder, a Today tab and a section; and an empty "Play".
    private static func demo() -> SidebarDocument {
        var document = SidebarDocument.fresh()
        let space = document.spaces[0]
        let calendar = SidebarItem.tab("data:text/html,<title>Calendar</title><h1>Calendar</h1>", title: "Calendar", parent: space.favoritesContainerID)
        var inbox = SidebarItem.tab("data:text/html,<title>Inbox</title><h1>Inbox</h1>", title: "Inbox", parent: space.pinnedContainerID)
        inbox.title = "Inbox"
        var work = SidebarItem.folder("Work", parent: space.pinnedContainerID)
        let docs = SidebarItem.tab("https://example.com/docs", title: "Docs", parent: work.id)
        var specs = SidebarItem.folder("Specs", parent: work.id)
        let spec = SidebarItem.tab("https://example.com/spec", title: "Spec", parent: specs.id)
        specs.children = [spec.id]
        work.children = [docs.id, specs.id]
        let story = SidebarItem.tab("https://example.com/story", title: "A Story", parent: space.todayContainerID)
        var reading = SidebarItem.tabGroup("Reading", parent: space.todayContainerID)
        let paper = SidebarItem.tab("https://example.com/paper", title: "A Paper", parent: reading.id)
        reading.children = [paper.id]
        document.items += [calendar, inbox, work, docs, specs, spec, story, reading, paper]
        for (container, children) in [(space.favoritesContainerID, [calendar.id]), (space.pinnedContainerID, [inbox.id, work.id]),
                                      (space.todayContainerID, [story.id, reading.id])] {
            if let index = document.items.firstIndex(where: { $0.id == container }) { document.items[index].children = children }
        }
        let playID = UUID()
        let containers = [SidebarItem.container(.favorites(spaceID: playID)), .container(.pinned(spaceID: playID)), .container(.today(spaceID: playID))]
        document.items += containers
        document.spaces.append(Space(id: playID, title: "Play", emoji: "🎮", theme: SpaceTheme.presets[min(2, SpaceTheme.presets.count - 1)],
                                     favoritesContainerID: containers[0].id, pinnedContainerID: containers[1].id,
                                     todayContainerID: containers[2].id, createdAt: Date()))
        document.spaceOrder.append(playID)
        // As the Mac shows it: Work open, Specs shut, the section open.
        document.layout = SidebarLayout(expandedFolders: [work.id])
        return document
    }

    private static func read() -> State {
        if LaunchOptions.value("CraSyncDir") == "demo" { return .spaces(demo(), writtenAt: Date().addingTimeInterval(-5)) }
        return withFolder { folder -> State in
            let manager = FileManager.default
            let file = folder.appendingPathComponent(SettingsSync.sidebarName)
            // iCloud Drive keeps another device's file in the cloud until it is asked for.
            try? manager.startDownloadingUbiquitousItem(at: file)
            func coordinatedRead(_ url: URL) -> Data? {
                var data: Data?
                var error: NSError?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { url in data = try? Data(contentsOf: url) }
                return data
            }
            guard let data = coordinatedRead(file), let document = MobileSpaces.document(from: data) else { return .nothingSynced }
            let written = coordinatedRead(folder.appendingPathComponent(SettingsSync.manifestName)).flatMap(MobileSpaces.writtenAt(manifest:))
                ?? (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return .spaces(document, writtenAt: written)
        } ?? .unavailable
    }
}
