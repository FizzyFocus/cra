import Foundation

/// The login Keychain item Chromium derives its cookie, password and card key from ("<Name> Safe
/// Storage"). Pane's own since 13 Nov 2026: "Pane Safe Storage", account "Pane", named in CEF's
/// framework by scripts/cef-keychain-item.py. Before that it was Cra's, which the CEF builds
/// still name when that script can't change one. The build writes the framework's service into
/// Info.plist (CraKeychainService), so the app always uses the item its Chromium reads.
public struct SafeStorageItem: Equatable, Sendable, CustomStringConvertible {
    public let service: String
    public let account: String

    public static let pane = SafeStorageItem(service: "Pane Safe Storage", account: "Pane")
    public static let cra = SafeStorageItem(service: "Cra Safe Storage", account: "Chromium")
    static let known: [SafeStorageItem] = [.pane, .cra]

    /// The item of a framework that reads `service`; nil for one Pane doesn't make (stock CEF's
    /// shared "Chromium Safe Storage") or a bundle that names none.
    public init?(bundledService service: String?) {
        guard let item = Self.known.first(where: { $0.service == service }) else { return nil }
        self = item
    }

    private init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    /// The other items Pane or Cra kept the same secret in, where a profile's secret may still be.
    public var predecessors: [SafeStorageItem] { Self.known.filter { $0 != self } }

    public var description: String { service }
}

/// What the launch does with the item before Chromium starts (SafeStorage.swift).
public enum SafeStorageStep: Equatable, Sendable {
    /// Its secret is the key: the item is there, or nothing holds the profile's secret any more
    /// (Chromium would make a new one anyway).
    case use
    /// The profile's secret is in an older item (Cra's, before 13 Nov 2026): copied into this one
    /// once, so the cookies and passwords it encrypted still open.
    case copy(from: SafeStorageItem)
    /// The profile stays on the mock keychain.
    case mock

    /// `encrypted`: the profile is already encrypted with a Keychain secret. `mayMoveProfile`: a fresh
    /// profile may move to the Keychain now (no other copy has it open, and the app is signed by a
    /// team, so macOS keeps trusting it across rebuilds). `exists` asks the Keychain without reading
    /// the secret, which never makes macOS ask.
    public static func plan(item: SafeStorageItem, encrypted: Bool, mayMoveProfile: Bool,
                            exists: (SafeStorageItem) -> Bool) -> SafeStorageStep {
        if exists(item) { return encrypted || mayMoveProfile ? .use : .mock }
        let older = item.predecessors.first(where: exists)
        if encrypted { return older.map { .copy(from: $0) } ?? .use }
        // A fresh profile (a test's, a new install's) never makes this item while an older one
        // still holds the real profile's secret: the real profile's copy would then find this new
        // secret and its cookies would no longer open.
        return mayMoveProfile && older == nil ? .use : .mock
    }
}
