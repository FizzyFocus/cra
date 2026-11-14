import CraCore
import Foundation

/// The Mac's sidebar, as it arrives through sync. Upstream's phone reads the Mac's iCloud
/// container; Pane's free Apple team has none (14 Nov 2026), so the Mac syncs into a folder in
/// iCloud Drive (Settings ▸ General ▸ Sync ▸ Use a Folder…) and the phone reads that folder, which
/// the user picks once in Files (kept as a security-scoped bookmark). `-CraSyncDir <folder>` points
/// a test at a folder instead.
enum SyncedSidebar {
    enum State {
        case spaces(SidebarDocument)
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

    /// Reads the synced sidebar off the main thread. A file another device wrote may still be on its
    /// way down from iCloud Drive (reading it asks for it), so an empty answer is looked at again a few
    /// times, two seconds apart, before it stands.
    static func load(_ done: @escaping (State) -> Void) { load(tries: 4, done) }

    private static func load(tries: Int, _ done: @escaping (State) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let state = read()
            DispatchQueue.main.async {
                if case .nothingSynced = state, tries > 1, LaunchOptions.value("CraSyncDir") == nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { load(tries: tries - 1, done) }
                    return
                }
                done(state)
            }
        }
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

    /// A made-up Mac sidebar for tests and screenshots: "Personal" with a pinned tab, a folder
    /// holding one, and a Today tab; and an empty "Play".
    private static func demo() -> SidebarDocument {
        var document = SidebarDocument.fresh()
        let space = document.spaces[0]
        var inbox = SidebarItem.tab("data:text/html,<title>Inbox</title><h1>Inbox</h1>", title: "Inbox", parent: space.pinnedContainerID)
        inbox.title = "Inbox"
        var work = SidebarItem.folder("Work", parent: space.pinnedContainerID)
        let docs = SidebarItem.tab("https://example.com/docs", title: "Docs", parent: work.id)
        work.children = [docs.id]
        let story = SidebarItem.tab("https://example.com/story", title: "A Story", parent: space.todayContainerID)
        document.items += [inbox, work, docs, story]
        for (container, children) in [(space.pinnedContainerID, [inbox.id, work.id]), (space.todayContainerID, [story.id])] {
            if let index = document.items.firstIndex(where: { $0.id == container }) { document.items[index].children = children }
        }
        let playID = UUID()
        let containers = [SidebarItem.container(.favorites(spaceID: playID)), .container(.pinned(spaceID: playID)), .container(.today(spaceID: playID))]
        document.items += containers
        document.spaces.append(Space(id: playID, title: "Play", emoji: "🎮", theme: SpaceTheme.presets[min(2, SpaceTheme.presets.count - 1)],
                                     favoritesContainerID: containers[0].id, pinnedContainerID: containers[1].id,
                                     todayContainerID: containers[2].id, createdAt: Date()))
        document.spaceOrder.append(playID)
        return document
    }

    private static func read() -> State {
        if LaunchOptions.value("CraSyncDir") == "demo" { return .spaces(demo()) }
        let testFolder = LaunchOptions.value("CraSyncDir").map { URL(fileURLWithPath: $0, isDirectory: true) }
        guard let pickedFolder = testFolder ?? picked() else { return .unavailable }
        let scoped = pickedFolder.startAccessingSecurityScopedResource()
        defer { if scoped { pickedFolder.stopAccessingSecurityScopedResource() } }
        let manager = FileManager.default
        // The Mac writes into a "Pane" folder inside the one it was given (SettingsSync): the user may
        // have picked either.
        let folder = SettingsSync.bundleFolder(in: pickedFolder) { manager.fileExists(atPath: $0.path) }
        let file = folder.appendingPathComponent(SettingsSync.sidebarName)
        // iCloud Drive keeps another device's file in the cloud until it is asked for.
        try? manager.startDownloadingUbiquitousItem(at: file)
        var data: Data?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &error) { url in data = try? Data(contentsOf: url) }
        guard let data, let document = MobileSpaces.document(from: data) else { return .nothingSynced }
        return .spaces(document)
    }
}
