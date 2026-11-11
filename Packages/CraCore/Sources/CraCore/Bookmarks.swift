import Foundation

/// A real bookmark (⇧⌘D, the address bar's star): a page kept by address in a folder tree of its
/// own, apart from the sidebar's pinned tabs and favorites (which are tabs). Saved in the data
/// folder's bookmarks.json.
public struct Bookmark: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var url: String
    /// The folder it is in; nil is the top of the tree.
    public var folderId: UUID?
    public var createdAt: Date
    public var tags: [String]

    public init(id: UUID = UUID(), title: String, url: String, folderId: UUID? = nil, createdAt: Date, tags: [String] = []) {
        self.id = id
        self.title = title
        self.url = url
        self.folderId = folderId
        self.createdAt = createdAt
        self.tags = tags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        url = try c.decode(String.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? url
        folderId = try c.decodeIfPresent(UUID.self, forKey: .folderId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

public struct BookmarkFolder: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    /// The folder it is in; nil is the top of the tree.
    public var parentId: UUID?
    public var createdAt: Date
    /// Open in the Library (its disclosure turned down), as a pinned folder is in the sidebar.
    public var expanded: Bool
    /// Its glyph's colour (FolderColor, a hex); nil follows the space's theme.
    public var color: String?

    public init(id: UUID = UUID(), title: String, parentId: UUID? = nil, createdAt: Date, expanded: Bool = true, color: String? = nil) {
        self.id = id
        self.title = title
        self.parentId = parentId
        self.createdAt = createdAt
        self.expanded = expanded
        self.color = color
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Folder"
        parentId = try c.decodeIfPresent(UUID.self, forKey: .parentId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date(timeIntervalSince1970: 0)
        expanded = try c.decodeIfPresent(Bool.self, forKey: .expanded) ?? true
        color = try? c.decodeIfPresent(String.self, forKey: .color)
    }
}

/// bookmarks.json: the folders and the bookmarks in them, and what the address bar's star, the
/// Library's Bookmarks page and the command bar ask of them.
public struct BookmarkLibrary: Codable, Equatable, Sendable {
    public var version = 1
    public var folders: [BookmarkFolder] = []
    public var bookmarks: [Bookmark] = []
    /// The ids (Chromium's GUIDs) of what was brought in from a profile's bookmark manager, so a
    /// later read adds only what is new and leaves deleted ones deleted (`merge`).
    public var importedIDs: Set<String> = []

    public init(folders: [BookmarkFolder] = [], bookmarks: [Bookmark] = []) {
        self.folders = folders
        self.bookmarks = bookmarks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        // One entry that can't be read is dropped, not the whole file.
        folders = (try? c.decodeIfPresent([Lossy<BookmarkFolder>].self, forKey: .folders))??.compactMap(\.value) ?? []
        bookmarks = (try? c.decodeIfPresent([Lossy<Bookmark>].self, forKey: .bookmarks))??.compactMap(\.value) ?? []
        importedIDs = (try? c.decodeIfPresent(Set<String>.self, forKey: .importedIDs)) ?? []
    }

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    /// One address however it was typed: scheme and host in lower case, no fragment, no trailing
    /// slash, so the star lights for https://Example.com/ and https://example.com#top alike.
    public static func key(_ url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let hash = s.firstIndex(of: "#") { s = String(s[..<hash]) }
        if var c = URLComponents(string: s) {
            c.scheme = c.scheme?.lowercased()
            c.host = c.host?.lowercased()
            s = c.string ?? s
        }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    public func bookmark(for url: String) -> Bookmark? {
        let k = Self.key(url)
        return k.isEmpty ? nil : bookmarks.first { Self.key($0.url) == k }
    }

    public func isBookmarked(_ url: String) -> Bool { bookmark(for: url) != nil }

    /// Bookmarks `url` (the one already there for it, if any).
    @discardableResult
    public mutating func add(url: String, title: String, folderId: UUID? = nil, now: Date) -> Bookmark {
        if let b = bookmark(for: url) { return b }
        let b = Bookmark(title: title.isEmpty ? url : title, url: url, folderId: folder(folderId)?.id, createdAt: now)
        bookmarks.append(b)
        return b
    }

    public mutating func update(_ b: Bookmark) {
        guard let i = bookmarks.firstIndex(where: { $0.id == b.id }) else { return }
        var b = b
        if folder(b.folderId) == nil { b.folderId = nil }
        bookmarks[i] = b
    }

    public mutating func remove(_ id: UUID) { bookmarks.removeAll { $0.id == id } }

    @discardableResult
    public mutating func addFolder(title: String, parentId: UUID? = nil, now: Date) -> BookmarkFolder {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let same = folders.first(where: { $0.parentId == parentId && $0.title.caseInsensitiveCompare(name) == .orderedSame }) { return same }
        let f = BookmarkFolder(title: name.isEmpty ? "New Folder" : name, parentId: folder(parentId)?.id, createdAt: now)
        folders.append(f)
        return f
    }

    /// A folder goes. `keepContents`: what was in it moves up to its parent; otherwise its bookmarks
    /// and folders go with it (the Library's Delete Folder, asked first when there are any).
    public mutating func removeFolder(_ id: UUID, keepContents: Bool = true) {
        guard let f = folder(id) else { return }
        if keepContents {
            for i in bookmarks.indices where bookmarks[i].folderId == id { bookmarks[i].folderId = f.parentId }
            for i in folders.indices where folders[i].parentId == id { folders[i].parentId = f.parentId }
            folders.removeAll { $0.id == id }
            return
        }
        let gone = Set([id] + descendants(of: id))
        bookmarks.removeAll { $0.folderId.map(gone.contains) ?? false }
        folders.removeAll { gone.contains($0.id) }
    }

    /// The folders inside `id`, at any depth.
    public func descendants(of id: UUID) -> [UUID] {
        var out: [UUID] = [], queue = [id], steps = 0
        while let next = queue.popLast(), steps < 10_000 {
            let kids = folders.filter { $0.parentId == next }.map(\.id)
            out += kids
            queue += kids
            steps += 1
        }
        return out
    }

    /// The bookmarks in `id` and the folders inside it.
    public func bookmarkCount(in id: UUID) -> Int {
        let all = Set([id] + descendants(of: id))
        return bookmarks.filter { $0.folderId.map(all.contains) ?? false }.count
    }

    public mutating func renameFolder(_ id: UUID, to title: String) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].title = name
    }

    public mutating func setExpanded(_ id: UUID, _ open: Bool) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].expanded = open
    }

    /// Folder Color: one of FolderColor's, or nil for the theme's.
    public mutating func setColor(_ id: UUID, _ hex: String?) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].color = hex
    }

    // MARK: Moving (the Library's drag and drop)

    /// Whether a dragged row can go into `folder` (nil: the top of the tree): not into a folder
    /// that isn't there, a folder not into itself or one inside it, and not where it already is.
    public func canMove(_ item: OutlineRow.Key, into folder: UUID?) -> Bool {
        if let folder, self.folder(folder) == nil { return false }
        switch item {
        case .bookmark(let id):
            guard let b = bookmarks.first(where: { $0.id == id }) else { return false }
            return b.folderId != folder
        case .folder(let id):
            guard let f = self.folder(id) else { return false }
            if let folder, folder == id || descendants(of: id).contains(folder) { return false }
            return f.parentId != folder
        case .empty:
            return false
        }
    }

    /// Moves a bookmark or a folder (with everything in it) into `folder`; false when it can't go.
    @discardableResult
    public mutating func move(_ item: OutlineRow.Key, into folder: UUID?) -> Bool {
        guard canMove(item, into: folder) else { return false }
        switch item {
        case .bookmark(let id):
            guard let i = bookmarks.firstIndex(where: { $0.id == id }) else { return false }
            bookmarks[i].folderId = folder
        case .folder(let id):
            guard let i = folders.firstIndex(where: { $0.id == id }) else { return false }
            folders[i].parentId = folder
            // A folder dropped into a closed one would vanish from sight: the target opens.
        case .empty:
            return false
        }
        if let folder, let i = folders.firstIndex(where: { $0.id == folder }) { folders[i].expanded = true }
        return true
    }

    /// One row of the Library's Bookmarks page, a Finder-like outline.
    public enum OutlineRow: Equatable, Sendable {
        /// A folder: its disclosure open or not, and whether anything is in it at all.
        case folder(BookmarkFolder, depth: Int, open: Bool, empty: Bool)
        case bookmark(Bookmark, depth: Int)
        /// Under an open folder with nothing in it: "Folder is empty".
        case emptyFolder(in: UUID, depth: Int)

        /// What the row shows, kept by the row's view while the outline changes around it.
        public enum Key: Hashable, Sendable { case folder(UUID), bookmark(UUID), empty(UUID) }

        public var key: Key {
            switch self {
            case .folder(let f, _, _, _): return .folder(f.id)
            case .bookmark(let b, _): return .bookmark(b.id)
            case .emptyFolder(let id, _): return .empty(id)
            }
        }

        /// The folder the row is in; nil at the top of the tree.
        public var parent: UUID? {
            switch self {
            case .folder(let f, _, _, _): return f.parentId
            case .bookmark(let b, _): return b.folderId
            case .emptyFolder(let id, _): return id
            }
        }

        public var depth: Int {
            switch self {
            case .folder(_, let d, _, _), .bookmark(_, let d), .emptyFolder(_, let d): return d
            }
        }

        /// Where a drop on this row goes: into the folder itself, or into the folder a bookmark (or
        /// a "Folder is empty" line) is in.
        public var dropFolder: UUID? {
            switch self {
            case .folder(let f, _, _, _): return f.id
            case .bookmark(let b, _): return b.folderId
            case .emptyFolder(let id, _): return id
            }
        }
    }

    /// The row a point falls on, by the rows' tops and heights down the outline (`y` from its
    /// top): exactly one row or none, the 1 pt between two rows belonging to neither, so two rows
    /// never light together.
    public static func row(at y: Double, frames: [(top: Double, height: Double)]) -> Int? {
        frames.firstIndex { y >= $0.top && y < $0.top + $0.height }
    }

    /// The page's rows: at each level the folders (by name) then the bookmarks (by title), an open
    /// folder's contents under it one level in. With a query only the matching bookmarks show, in
    /// the folders that lead to them, opened.
    public func outline(matching query: String = "") -> [OutlineRow] {
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        let shown = Set(search(query).map(\.id))
        let byName: (BookmarkFolder, BookmarkFolder) -> Bool = { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        func hasMatches(_ id: UUID) -> Bool {
            let all = Set([id] + descendants(of: id))
            return bookmarks.contains { b in shown.contains(b.id) && (b.folderId.map(all.contains) ?? false) }
        }
        var out: [OutlineRow] = []
        func level(_ parent: UUID?, _ depth: Int) {
            guard depth < 64 else { return }
            for f in folders.filter({ $0.parentId == parent }).sorted(by: byName) {
                if searching, !hasMatches(f.id) { continue }
                let empty = !bookmarks.contains { $0.folderId == f.id } && !folders.contains { $0.parentId == f.id }
                let open = searching || f.expanded
                out.append(.folder(f, depth: depth, open: open, empty: empty))
                guard open else { continue }
                if empty { out.append(.emptyFolder(in: f.id, depth: depth + 1)) } else { level(f.id, depth + 1) }
            }
            let items = bookmarks.filter { $0.folderId == parent && shown.contains($0.id) }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            out += items.map { .bookmark($0, depth: depth) }
        }
        level(nil, 0)
        return out
    }

    public func folder(_ id: UUID?) -> BookmarkFolder? { id.flatMap { id in folders.first { $0.id == id } } }

    /// "Work ▸ Docs": the folder and those it is in, from the top.
    public func path(of id: UUID?) -> String {
        var names: [String] = []
        var next = folder(id), steps = 0
        while let f = next, steps < 64 { names.insert(f.title, at: 0); next = folder(f.parentId); steps += 1 }
        return names.joined(separator: " ▸ ")
    }

    /// Every folder in tree order (a parent before its children, each level by name), with its depth.
    public func folderTree() -> [(folder: BookmarkFolder, depth: Int)] {
        var out: [(BookmarkFolder, Int)] = []
        func walk(_ parent: UUID?, _ depth: Int) {
            for f in folders.filter({ $0.parentId == parent }).sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) {
                out.append((f, depth))
                if depth < 64 { walk(f.id, depth + 1) }
            }
        }
        walk(nil, 0)
        return out
    }

    /// Bookmarks whose title, address or tags hold every word of `query`, newest first.
    public func search(_ query: String) -> [Bookmark] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return bookmarks.sorted { $0.createdAt > $1.createdAt } }
        return bookmarks.filter { b in
            let hay = ([b.title, b.url] + b.tags).joined(separator: " ").lowercased()
            return words.allSatisfy { hay.contains($0) }
        }.sorted { $0.createdAt > $1.createdAt }
    }
}

/// ⌘D on a tab that is one of the favorites: Arc would pin it into the space, where it already has
/// its place up top. The first press only says so ("Already in Top Favorites"); pressing again
/// within `window` seconds goes ahead and pins a copy into the space's pinned tabs. Any other tab
/// pins or unpins at once.
public struct FavoritePinGuard: Sendable, Equatable {
    public static let window: TimeInterval = 1.5

    public enum Outcome: Equatable, Sendable {
        /// Pin (or unpin) as ⌘D always does; for a favorite, a pinned copy.
        case pin
        /// Say it is a favorite already, and wait for a second press.
        case warn
    }

    private var warned: (tab: UUID, at: TimeInterval)?

    public init() {}

    public mutating func press(tab: UUID, isFavorite: Bool, now: TimeInterval) -> Outcome {
        guard isFavorite else { warned = nil; return .pin }
        if let w = warned, w.tab == tab, now - w.at <= Self.window {
            warned = nil
            return .pin
        }
        warned = (tab, now)
        return .warn
    }

    public static func == (a: Self, b: Self) -> Bool { a.warned?.tab == b.warned?.tab && a.warned?.at == b.warned?.at }
}
