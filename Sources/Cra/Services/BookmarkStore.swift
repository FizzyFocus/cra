import AppKit
import Observation

/// Real bookmarks (BookmarkLibrary): the address bar's star, ⇧⌘D, the Library's Bookmarks page and
/// the command bar's Bookmark rows read and change them here; they live in the data folder's
/// bookmarks.json. Apart from the sidebar's pinned tabs and favorites, which are tabs.
@MainActor
@Observable
final class BookmarkStore {
    static let shared = BookmarkStore()
    @ObservationIgnored private let file = JSONStore<BookmarkLibrary>("bookmarks.json")
    private(set) var library: BookmarkLibrary

    private init() {
        library = file.load(or: { BookmarkLibrary() })
        // A count only (no addresses): scenarios read that a relaunch kept them.
        CraLog.note("bookmarks: \(library.bookmarks.count) loaded")
        // Chromium's bookmark manager (where Chrome's importer puts bookmarks): read in after launch,
        // whenever Cra comes to the front and whenever a profile's file changes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.watchChromium() }
        activation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncChromium() }
        }
    }

    // MARK: Importing

    /// Library ▸ Bookmarks ▸ Import: a Netscape bookmarks.html (every browser's export), its folders
    /// kept; an address already bookmarked isn't added twice. nil when the file can't be read.
    @discardableResult
    func importHTML(_ url: URL) -> BookmarkLibrary.MergeResult? {
        guard let data = try? Data(contentsOf: url),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        let tree = NetscapeBookmarks.parse(html)
        guard !tree.isEmpty else { return nil }
        let r = library.merge(tree, now: Date())
        file.save(library)
        CraLog.note("bookmarks imported from html: \(r.bookmarks) bookmarks, \(r.folders) folders")
        return r
    }

    @ObservationIgnored private var activation: NSObjectProtocol?
    @ObservationIgnored private var watchers: [String: DispatchSourceFileSystemObject] = [:]
    @ObservationIgnored private var seen: [String: Date] = [:]
    @ObservationIgnored private var syncWork: DispatchWorkItem?

    /// Each Chromium profile's `Bookmarks` file (Chromium/<profile>/Bookmarks): what is new in it
    /// since it was last read comes into the library, the bookmark bar's at the top. Deleted here,
    /// an imported bookmark stays deleted (BookmarkLibrary.importedIDs).
    func syncChromium() {
        var changed = false
        for profile in ExtensionStore.chromiumProfiles() {
            let url = AppPaths.chromiumCache.appendingPathComponent(profile, isDirectory: true).appendingPathComponent("Bookmarks")
            guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  modified != seen[profile], let data = try? Data(contentsOf: url) else { continue }
            seen[profile] = modified
            let before = library.importedIDs
            let r = library.merge(ChromiumBookmarks.parse(data), now: Date())
            if r.bookmarks + r.folders > 0 {
                CraLog.note("bookmarks from Chromium (\(profile)): \(r.bookmarks) bookmarks, \(r.folders) folders")
            }
            changed = changed || r.bookmarks + r.folders > 0 || library.importedIDs != before
        }
        if changed { file.save(library) }
    }

    /// A watch on each profile folder: Chromium replaces its Bookmarks file when it saves.
    private func watchChromium() {
        syncChromium()
        for profile in ExtensionStore.chromiumProfiles() where watchers[profile] == nil {
            let dir = AppPaths.chromiumCache.appendingPathComponent(profile, isDirectory: true)
            let fd = open(dir.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename], queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // Chromium writes in bursts: read once it has settled.
                    self.syncWork?.cancel()
                    let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.syncChromium() } }
                    self.syncWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
                }
            }
            source.setCancelHandler { close(fd) }
            source.resume()
            watchers[profile] = source
        }
    }

    func bookmark(for url: String) -> Bookmark? { library.bookmark(for: url) }
    func isBookmarked(_ url: String) -> Bool { library.isBookmarked(url) }

    /// Bookmarks the page (or hands back the bookmark it has).
    @discardableResult
    func add(url: String, title: String) -> Bookmark {
        let b = library.add(url: url, title: title, now: Date())
        file.save(library)
        CraLog.note("bookmark added")
        return b
    }

    func update(_ b: Bookmark) {
        library.update(b)
        file.save(library)
    }

    func remove(_ id: UUID) {
        library.remove(id)
        file.save(library)
        CraLog.note("bookmark removed")
    }

    @discardableResult
    func addFolder(title: String, parentId: UUID? = nil) -> BookmarkFolder {
        let f = library.addFolder(title: title, parentId: parentId, now: Date())
        file.save(library)
        return f
    }

    /// Delete Folder: its bookmarks and folders go with it (the Library asks first when there are any).
    func removeFolder(_ id: UUID, keepContents: Bool = false) {
        library.removeFolder(id, keepContents: keepContents)
        file.save(library)
    }

    func renameFolder(_ id: UUID, to title: String) {
        library.renameFolder(id, to: title)
        file.save(library)
    }

    /// The folder's disclosure on the Library's Bookmarks page, kept for next time.
    func setExpanded(_ id: UUID, _ open: Bool) {
        library.setExpanded(id, open)
        file.save(library)
    }

    /// Icon Color (FolderColor): the folder's glyph in `hex`, nil for the theme's.
    func setColor(_ id: UUID, _ hex: String?) {
        library.setColor(id, hex)
        file.save(library)
    }

    /// A drag in the Library: a bookmark or a folder into `folder` (nil: the top of the tree).
    @discardableResult
    func move(_ item: BookmarkLibrary.OutlineRow.Key, into folder: UUID?) -> Bool {
        guard library.move(item, into: folder) else { return false }
        file.save(library)
        CraLog.note("bookmark moved")
        return true
    }
}
