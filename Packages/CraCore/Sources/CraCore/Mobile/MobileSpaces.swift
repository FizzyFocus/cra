import Foundation

/// The Mac's sidebar as the iPhone shows it: Arc Search's Spaces view, one Space per page, with
/// the Mac's sidebar in it (14 Nov 2026, the owner's call): the Space's Favorites as tiles, a
/// Pinned header that folds the pinned area, folders that open and close with their tabs nested
/// under them, then Today with its sections (Tidy Tabs' groups) under headers that collapse. Each
/// starts open or shut as the Mac shows it (`SidebarLayout` in the synced sidebar.json); a tap on
/// the phone changes it there. Read from the `sidebar.json` the Mac app syncs (`SettingsSync`); the
/// phone opens things from it and does not write it.
public enum MobileSpaces {
    public struct Row: Equatable, Identifiable {
        public enum Kind: Equatable {
            case tab(url: String)
            /// A folder; `open` when its tabs show under it.
            case folder(open: Bool)
            /// A section: Tidy Tabs' named header over Today's tabs, which collapses like a folder.
            case section(open: Bool)
            /// The head of a Space's pinned tabs and folders, which folds them away as clicking the
            /// Space's name does on the Mac.
            case pinnedHeader(open: Bool)
            /// The line between the pinned part and Today.
            case todayHeader
        }

        /// The item's id; for the pinned header, the Space's pinned container; for Today's line,
        /// its Today container. The id a tap toggles (`toggled`).
        public var id: UUID
        public var kind: Kind
        public var title: String
        /// How deep inside folders the row sits.
        public var depth: Int
        /// The tabs inside a folder, a section or the pinned area, nested ones too: what a closed
        /// one holds. 0 for a tab.
        public var count: Int

        public init(id: UUID, kind: Kind, title: String, depth: Int, count: Int = 0) {
            self.id = id
            self.kind = kind
            self.title = title
            self.depth = depth
            self.count = count
        }

        /// Open or shut, for a row that folds; nil for one that doesn't.
        public var isOpen: Bool? {
            switch kind {
            case .folder(let open), .section(let open), .pinnedHeader(let open): return open
            case .tab, .todayHeader: return nil
            }
        }
    }

    /// One of a Space's Favorites, the tiles over its pinned tabs.
    public struct Favorite: Equatable, Identifiable {
        public var id: UUID
        public var url: String
        public var title: String
    }

    public struct SpaceView: Equatable, Identifiable {
        public var id: UUID
        public var title: String
        /// The Space's emoji, or empty when it uses a symbol.
        public var emoji: String
        public var symbol: String?
        /// The theme's colours as "#RRGGBB".
        public var colors: [String]
        /// The Favorites: the Space's own, or its profile's when the Mac shares them (the Space
        /// points at that list).
        public var favorites: [Favorite]
        /// The Pinned header and what it holds, then Today's line and Today.
        public var rows: [Row]
    }

    /// The title a pinned area's header shows.
    public static let pinnedTitle = "Pinned"

    /// Every Space in the Mac's order. `toggled` holds what the phone opened or shut itself, by row
    /// id; everything else is as the Mac shows it (`isOpenOnMac`). Blank-window spaces are left out.
    public static func spaces(in document: SidebarDocument, toggled: [UUID: Bool] = [:]) -> [SpaceView] {
        let items = Dictionary(document.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byID = Dictionary(document.spaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = document.spaceOrder.compactMap { byID[$0] } + document.spaces.filter { !document.spaceOrder.contains($0.id) }
        let macOpen = OpenOnMac(document)

        func open(_ id: UUID) -> Bool { toggled[id] ?? macOpen[id] ?? true }

        /// The tabs under `id`, through folders, sections and splits (a bound for a cycle).
        func tabCount(under id: UUID, depth: Int = 0) -> Int {
            guard depth < 64, let item = items[id] else { return 0 }
            return item.children.reduce(0) { sum, child in
                guard let c = items[child] else { return sum }
                return sum + (c.isTab ? 1 : tabCount(under: child, depth: depth + 1))
            }
        }

        func rows(under parent: UUID, depth: Int, nesting: Int = 0) -> [Row] {
            guard nesting < 64, let container = items[parent] else { return [] }
            return container.children.flatMap { id -> [Row] in
                guard let item = items[id] else { return [] }
                switch item.data {
                case .tab:
                    return [Row(id: id, kind: .tab(url: item.tab?.url ?? ""), title: item.displayTitle, depth: depth)]
                case .folder where item.isTabGroup:
                    // A section's tabs line up under its header, as in the Mac's Today.
                    let isOpen = open(id)
                    let header = Row(id: id, kind: .section(open: isOpen), title: nonEmpty(item.title) ?? TabGroups.noun, depth: depth,
                                     count: tabCount(under: id))
                    return [header] + (isOpen ? rows(under: id, depth: depth, nesting: nesting + 1) : [])
                case .folder:
                    let isOpen = open(id)
                    let folder = Row(id: id, kind: .folder(open: isOpen), title: nonEmpty(item.title) ?? "Folder", depth: depth,
                                     count: tabCount(under: id))
                    return [folder] + (isOpen ? rows(under: id, depth: depth + 1, nesting: nesting + 1) : [])
                case .split, .container:
                    // A split's tabs are its children: listed one by one.
                    return rows(under: id, depth: depth, nesting: nesting + 1)
                }
            }
        }

        func favorites(in container: UUID) -> [Favorite] {
            func tabs(under id: UUID, nesting: Int) -> [SidebarItem] {
                guard nesting < 64, let item = items[id] else { return [] }
                return item.children.compactMap { items[$0] }.flatMap { $0.isTab ? [$0] : tabs(under: $0.id, nesting: nesting + 1) }
            }
            return tabs(under: container, nesting: 0).compactMap { item in
                guard let tab = item.tab, !item.isEmptyTab else { return nil }
                return Favorite(id: item.id, url: tab.url, title: item.displayTitle)
            }
        }

        return ordered.filter { $0.standaloneWindowID == nil }.map { space in
            var list: [Row] = []
            let pinned = rows(under: space.pinnedContainerID, depth: 0)
            if !pinned.isEmpty {
                let isOpen = open(space.pinnedContainerID)
                list.append(Row(id: space.pinnedContainerID, kind: .pinnedHeader(open: isOpen), title: pinnedTitle, depth: 0,
                                count: tabCount(under: space.pinnedContainerID)))
                if isOpen { list += pinned }
            }
            let today = rows(under: space.todayContainerID, depth: 0)
            if !today.isEmpty {
                list.append(Row(id: space.todayContainerID, kind: .todayHeader, title: "Today", depth: 0, count: tabCount(under: space.todayContainerID)))
                list += today
            }
            return SpaceView(id: space.id, title: space.title, emoji: space.emoji, symbol: space.symbol,
                             colors: space.theme.colors, favorites: favorites(in: space.favoritesContainerID), rows: list)
        }
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return s
    }

    /// Open or shut on the Mac, by row id (`Row.id`): a folder when the Mac has it open, a section
    /// and a pinned area unless collapsed there. A sidebar from a Mac that sends no layout (before
    /// 14 Nov 2026) shows everything open, as the phone did then.
    private struct OpenOnMac {
        private var folders: Set<UUID> = []
        private var sections: Set<UUID> = []
        private var pinnedAreas: [UUID: UUID] = [:]
        private let layout: SidebarLayout?

        init(_ document: SidebarDocument) {
            layout = document.layout
            for item in document.items where item.isFolder {
                if item.isTabGroup { sections.insert(item.id) } else { folders.insert(item.id) }
            }
            for space in document.spaces { pinnedAreas[space.pinnedContainerID] = space.id }
        }

        subscript(id: UUID) -> Bool? {
            if let space = pinnedAreas[id] { return !(layout?.collapsedPinnedSpaces.contains(space) ?? false) }
            if sections.contains(id) { return !(layout?.collapsedSections.contains(id) ?? false) }
            if folders.contains(id) { return layout.map { $0.expandedFolders.contains(id) } ?? true }
            return nil
        }
    }

    /// Whether the Mac shows the folder, section or pinned area `id` (a `Row.id`) open; nil for
    /// anything else.
    public static func isOpenOnMac(_ id: UUID, in document: SidebarDocument) -> Bool? {
        OpenOnMac(document)[id]
    }

    /// What the phone opened or shut that still stands once a newer sidebar arrives: a choice
    /// stays while the Mac shows that row as it did, and goes when the Mac opened or shut it
    /// since (its newer state wins), or the row is gone.
    public static func keptToggles(_ toggled: [UUID: Bool], from old: SidebarDocument?, to new: SidebarDocument) -> [UUID: Bool] {
        guard let old else { return [:] }
        let before = OpenOnMac(old), after = OpenOnMac(new)
        return toggled.filter { id, _ in
            guard let now = after[id] else { return false }
            return before[id] == now
        }
    }

    /// Reads a synced `sidebar.json`, with the Mac's dates as it writes them (ISO 8601 text,
    /// `JSONStore` and `SettingsSyncService`).
    public static func document(from data: Data) -> SidebarDocument? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SidebarDocument.self, from: data)
    }

    /// When the Mac wrote the bundle, from its `manifest.json`.
    public static func writtenAt(manifest data: Data) -> Date? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(SyncManifest.self, from: data))?.writtenAt
    }

    /// The line over the Spaces that says how fresh they are: when the Mac wrote what the phone
    /// shows. "Updated just now" under a minute (or a Mac clock a little ahead of the phone's),
    /// then minutes, hours, "yesterday" and days.
    public static func updatedLabel(writtenAt: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(writtenAt)
        if seconds < 60 { return "Updated just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "Updated \(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "Updated \(hours) hr ago" }
        let days = hours / 24
        return days == 1 ? "Updated yesterday" : "Updated \(days) days ago"
    }

    /// While the phone asks iCloud Drive for the Mac's newest Spaces.
    public static let checkingLabel = "Checking for updates…"
    /// While iCloud Drive brings a newer copy down.
    public static let downloadingLabel = "Downloading from iCloud Drive…"
}

extension MobileSpaces {
    /// The Spaces sheet's colour and its text: the Space's first colour softened a third of the
    /// way to white, and white text where that comes out dark enough (Arc Search's purple Space,
    /// #a687c8 in TidBITS' screenshot, has white text).
    public struct SheetStyle: Equatable {
        public var fill: String
        public var lightText: Bool

        public init(fill: String, lightText: Bool) {
            self.fill = fill
            self.lightText = lightText
        }
    }

    public static func sheetStyle(colors: [String]) -> SheetStyle? {
        guard let first = colors.first, let c = HexColor.components(first) else { return nil }
        func softened(_ v: Double) -> Double { v + (1 - v) * 0.35 }
        let (r, g, b) = (softened(c.r), softened(c.g), softened(c.b))
        let fill = String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
        return SheetStyle(fill: fill, lightText: (HexColor.luminance(fill) ?? 1) < 0.62)
    }

    /// What a page opened from a Space stands on until it paints (14 Nov 2026): the Space's sheet
    /// colour in light mode, and in dark mode its first colour sunk most of the way into the app's
    /// dark backdrop (#1C1B22), so a dark phone never flashes a pale screen. Nil for a Space with no
    /// colour: the app's own backdrop then.
    public static func coverColor(colors: [String], dark: Bool) -> String? {
        guard !dark else {
            guard let first = colors.first, let c = HexColor.components(first) else { return nil }
            let base = (r: 0x1C / 255.0, g: 0x1B / 255.0, b: 0x22 / 255.0)
            func sunk(_ v: Double, _ b: Double) -> Int { Int(((b + (v - b) * 0.22) * 255).rounded()) }
            return String(format: "#%02X%02X%02X", sunk(c.r, base.r), sunk(c.g, base.g), sunk(c.b, base.b))
        }
        return sheetStyle(colors: colors)?.fill
    }
}

/// "Favorite in App": the sites the phone keeps under the empty search field. `favorites.json`.
public struct MobileFavorites: Codable, Equatable {
    public struct Site: Codable, Equatable, Identifiable {
        public var url: String
        public var title: String
        public var id: String { url }

        public init(url: String, title: String) {
            self.url = url
            self.title = title
        }
    }

    public var sites: [Site] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sites = try c.decodeIfPresent([Site].self, forKey: .sites) ?? []
    }

    private enum CodingKeys: String, CodingKey { case sites }

    /// A page counts as the favorite of its address without tracking parameters or fragment.
    static func key(_ url: String) -> String {
        var clean = CleanURL.withoutTrackers(url)
        if let hash = clean.firstIndex(of: "#") { clean = String(clean[..<hash]) }
        return clean.hasSuffix("/") ? String(clean.dropLast()) : clean
    }

    public func contains(_ url: String) -> Bool {
        sites.contains { Self.key($0.url) == Self.key(url) }
    }

    /// Adds the page, or removes it when it is already a favorite. Returns whether it is one now.
    @discardableResult
    public mutating func toggle(url: String, title: String) -> Bool {
        if contains(url) {
            sites.removeAll { Self.key($0.url) == Self.key(url) }
            return false
        }
        sites.append(Site(url: url, title: title.isEmpty ? (URL(string: url)?.host ?? url) : title))
        return true
    }

    public mutating func move(from source: Int, to destination: Int) {
        guard sites.indices.contains(source), (0..<sites.count).contains(destination) else { return }
        sites.insert(sites.remove(at: source), at: destination)
    }

    /// What shows under the empty search field: the first four, as in Arc Search.
    public func shown(limit: Int = MobileSearchSheet.visibleRows) -> [Site] {
        Array(sites.prefix(limit))
    }
}
