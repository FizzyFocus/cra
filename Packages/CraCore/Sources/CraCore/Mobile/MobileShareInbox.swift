import Foundation
#if os(iOS)
import Security
#endif

/// Links saved from other apps' share sheets (the "Pane" share extension), waiting for the app. Upstream
/// keeps them as `share-inbox.json` in an App Group; Pane's free Apple team has no App Groups, so on
/// the phone they wait in a Keychain item both claim (`updateInKeychain`, 14 Nov 2026). Arc Search's extension shows "Saved" with a
/// picker of where the link goes and remembers the last place; here the places are the phone's
/// tabs and "Favorite in App". The app takes the links the next time it comes to the front.
public struct MobileShareInbox: Codable, Equatable {
    public static let fileName = "share-inbox.json"
    /// The Keychain item the inbox is on the phone: its service and account.
    public static let keychainService = "uz.pane.ios.share-inbox"
    public static let keychainAccount = "inbox"
    /// More waiting than this and the oldest go: the extension can run many times before the app does.
    public static let limit = 50

    public enum Destination: String, Codable, CaseIterable, Identifiable {
        /// A new tab in the tab row (not opened over what is on screen).
        case tabs
        /// "Favorite in App": under the empty search field.
        case favorites

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .tabs: return "Tabs"
            case .favorites: return "Favorites"
            }
        }

        public var symbol: String {
            switch self {
            case .tabs: return "square.on.square"
            case .favorites: return "pin.fill"
            }
        }
    }

    public struct Item: Codable, Equatable {
        public var url: String
        public var title: String
        public var destination: Destination
        public var savedAt: Date

        public init(url: String, title: String, destination: Destination, savedAt: Date) {
            self.url = url
            self.title = title
            self.destination = destination
            self.savedAt = savedAt
        }
    }

    public var items: [Item] = []
    /// Where the picker starts next time.
    public var lastDestination: Destination = .tabs

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decodeIfPresent([Item].self, forKey: .items)) ?? []
        lastDestination = (try? c.decodeIfPresent(Destination.self, forKey: .lastDestination)) ?? .tabs
    }

    private enum CodingKeys: String, CodingKey { case items, lastDestination }

    /// Keeps a web page for the app. Anything but an http(s) address is refused; the same page
    /// for the same place waiting already is kept once. Returns whether it was kept.
    @discardableResult
    public mutating func save(url: String, title: String, to destination: Destination, at date: Date) -> Bool {
        guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased(),
              scheme == "https" || scheme == "http", parsed.host?.isEmpty == false else { return false }
        lastDestination = destination
        items.removeAll { $0.url == url && $0.destination == destination }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        items.append(Item(url: url, title: name.isEmpty ? (parsed.host ?? url) : name, destination: destination, savedAt: date))
        if items.count > Self.limit { items.removeFirst(items.count - Self.limit) }
        return true
    }

    /// The waiting links, oldest first, leaving the inbox empty (the last place stays).
    public mutating func take() -> [Item] {
        defer { items = [] }
        return items
    }

    /// Reads, changes and writes the inbox in `folder` as one coordinated step, so the extension
    /// and the app never write over each other.
    @discardableResult
    public static func update<T>(in folder: URL, _ change: (inout MobileShareInbox) -> T) -> T? {
        let file = folder.appendingPathComponent(fileName)
        var result: T?
        var error: NSError?
        NSFileCoordinator().coordinate(writingItemAt: file, options: [], error: &error) { url in
            let (value, data) = update(stored: try? Data(contentsOf: url), change)
            result = value
            guard let data else { return }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        return result
    }

    /// The inbox `stored` holds (an empty one for nil or what doesn't read), changed by `change`:
    /// what the change returned, and the bytes to keep, nil when nothing changed. Wherever it lives.
    public static func update<T>(stored: Data?, _ change: (inout MobileShareInbox) -> T) -> (result: T, data: Data?) {
        var inbox = stored.flatMap { try? JSONDecoder.inbox.decode(MobileShareInbox.self, from: $0) } ?? MobileShareInbox()
        let before = inbox
        let result = change(&inbox)
        guard inbox != before, let data = try? JSONEncoder.inbox.encode(inbox) else { return (result, nil) }
        return (result, data)
    }
}

#if os(iOS)
extension MobileShareInbox {
    /// The Keychain access group both targets claim, team prefix included (Info.plist's
    /// PaneKeychainGroup, from $(AppIdentifierPrefix)).
    static var keychainGroup: String? { Bundle.main.object(forInfoDictionaryKey: "PaneKeychainGroup") as? String }

    /// `update(stored:)` on the phone's Keychain item. A build that may not use the group (the
    /// Simulator, unsigned) keeps the item in its own default group instead.
    @discardableResult
    public static func updateInKeychain<T>(_ change: (inout MobileShareInbox) -> T) -> T {
        func query(_ group: String?) -> [String: Any] {
            var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: keychainService,
                                    kSecAttrAccount as String: keychainAccount]
            if let group { q[kSecAttrAccessGroup as String] = group }
            return q
        }
        func read(_ group: String?) -> (data: Data?, status: OSStatus) {
            var q = query(group)
            q[kSecReturnData as String] = true
            q[kSecMatchLimit as String] = kSecMatchLimitOne
            var out: CFTypeRef?
            let status = SecItemCopyMatching(q as CFDictionary, &out)
            return (out as? Data, status)
        }
        var group = keychainGroup
        var stored = read(group)
        if stored.status == errSecMissingEntitlement {
            group = nil
            stored = read(nil)
        }
        let (result, data) = update(stored: stored.data, change)
        guard let data else { return result }
        let changes = [kSecValueData as String: data] as CFDictionary
        if stored.data != nil, SecItemUpdate(query(group) as CFDictionary, changes) == errSecSuccess { return result }
        var add = query(group)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(add as CFDictionary, nil) == errSecDuplicateItem { SecItemUpdate(query(group) as CFDictionary, changes) }
        return result
    }
}
#endif

private extension JSONDecoder {
    static var inbox: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var inbox: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
