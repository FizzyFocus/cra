import AppKit
import Foundation
import Security
import SQLite3

/// Chromium encrypts cookies, saved passwords, card numbers and search engine hashes
/// ("v10" values, see ChromiumCrypto) with a key derived from the secret in a login Keychain
/// item. Stock Chromium calls it "Chromium Safe Storage", like every Chromium-based app
/// without its own name. Pane's is "Pane Safe Storage", account "Pane" (13 Nov 2026,
/// SafeStorageItem): scripts/cef-keychain-item.py names it in CEF's framework, and the build
/// writes the name the framework reads into Info.plist (CraKeychainService). Before, it was
/// Cra's "Cra Safe Storage" (account "Chromium", scripts/cef-patches/keychain-service-name.patch);
/// a profile encrypted under that item has its secret copied into Pane's once.
///
/// Cra used to start Chromium with --use-mock-keychain, whose secret is the public
/// constant "mock_password": anyone who could read the profile could decrypt it. The
/// first launch of a signed Pane re-encrypts such a profile with the Keychain secret
/// before Chromium opens it. Ad-hoc builds keep the mock keychain on profiles that
/// never used the Keychain: macOS ties the item to the app's signature, which changes
/// with every ad-hoc rebuild, and would ask for the login password each time. Local builds
/// sign with the Mac's own development identity when it has one (scripts/build.sh), so
/// macOS keeps trusting them across rebuilds.
enum SafeStorage {
    /// The item this build's Chromium reads; nil for a stock CEF, which keeps Chromium's own.
    static let item = SafeStorageItem(bundledService: Bundle.main.object(forInfoDictionaryKey: "CraKeychainService") as? String)

    /// Whether Chromium reads the Keychain item (false: --use-mock-keychain).
    private(set) static var usesKeychain = false
    /// The key Pane's profile is encrypted with, for the importer. nil when the Keychain
    /// did not hand out the secret.
    private(set) static var key: Data?

    private static let mockKey = ChromiumCrypto.key(fromSecret: "mock_password")
    /// Present once the profile is encrypted with the Keychain secret (named before Pane's item).
    private static var marker: URL { AppPaths.chromiumCache.appendingPathComponent("Cra Safe Storage") }
    private static let metaKey = "cra_safe_storage"
    private static let databases = ["Cookies", "Extension Cookies", "Safe Browsing Cookies", "Login Data",
                                    "Login Data For Account", "Web Data", "Account Web Data"]
    /// Upstream Cra's bundle: while it is installed, its item stays for it after the copy.
    private static let craBundleID = "dk.kildahl.cra"

    /// Called from main.swift before Chromium starts. Only migrates when `profileIsFree`
    /// (no other copy has the databases open).
    static func prepare(profileIsFree: Bool) {
        let encrypted = FileManager.default.fileExists(atPath: marker.path)
        guard let item else {
            usesKeychain = encrypted
            key = encrypted ? nil : mockKey
            if encrypted { NSLog("Cra: this build names no Keychain item for Chromium (Info.plist CraKeychainService)") }
            return
        }
        let step = SafeStorageStep.plan(item: item, encrypted: encrypted, mayMoveProfile: profileIsFree && isSignedByTeam,
                                        exists: exists)
        if encrypted {
            usesKeychain = true
            let found: String?
            if case .copy(let older) = step { found = copy(from: older, to: item) } else { found = secret(of: item) }
            key = found.map(ChromiumCrypto.key(fromSecret:))
            if key == nil { NSLog("Cra: no secret from the \(item) Keychain item") }
            return
        }
        key = mockKey
        guard step == .use, let secret = secret(of: item) else { return }
        let newKey = ChromiumCrypto.key(fromSecret: secret)
        guard migrate(to: newKey, item: item) else { return }
        try? FileManager.default.createDirectory(at: AppPaths.chromiumCache, withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: marker.path, contents: Data()) else { return }
        usesKeychain = true
        key = newKey
    }

    private static func query(_ item: SafeStorageItem) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: item.service,
         kSecAttrAccount as String: item.account, kSecMatchLimit as String: kSecMatchLimitOne]
    }

    /// Whether the item is there. Asks for no secret, so macOS never asks the person.
    private static func exists(_ item: SafeStorageItem) -> Bool {
        SecItemCopyMatching(query(item) as CFDictionary, nil) == errSecSuccess
    }

    private static func read(_ item: SafeStorageItem) -> (secret: String?, status: OSStatus) {
        var q = query(item)
        q[kSecReturnData as String] = true
        var result: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        return ((result as? Data).flatMap { String(data: $0, encoding: .utf8) }, status)
    }

    /// Made by Pane, so macOS lets Pane read it without asking.
    private static func add(_ item: SafeStorageItem, secret: String) -> OSStatus {
        let attributes: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: item.service,
                                         kSecAttrAccount as String: item.account, kSecAttrLabel as String: item.service,
                                         kSecValueData as String: Data(secret.utf8)]
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    /// The item's secret, made the way Chromium makes one (16 random bytes, base64) when
    /// there is none yet.
    private static func secret(of item: SafeStorageItem) -> String? {
        let (found, status) = read(item)
        if let found { return found }
        guard status == errSecItemNotFound else {
            NSLog("Cra: reading the \(item) Keychain item failed (\(status))")
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        let secret = Data(bytes).base64EncodedString()
        let added = add(item, secret: secret)
        guard added == errSecSuccess else {
            NSLog("Cra: creating the \(item) Keychain item failed (\(added))")
            return nil
        }
        return secret
    }

    /// The profile's secret, from the item an older build read into this one, once. macOS asks
    /// whether Pane may read the older item (it was made by another signature). Refused, Pane
    /// asks to try again: going on would let Chromium make a new secret, and the profile's
    /// cookies and passwords would no longer open.
    private static func copy(from older: SafeStorageItem, to item: SafeStorageItem) -> String? {
        while true {
            let (found, status) = read(older)
            if let found {
                let added = add(item, secret: found)
                if added == errSecDuplicateItem { return secret(of: item) }
                guard added == errSecSuccess else {
                    NSLog("Cra: copying the \(older) Keychain item's secret to \(item) failed (\(added))")
                    return found
                }
                NSLog("Cra: copied the \(older) Keychain item's secret to \(item)")
                if older == .cra, NSWorkspace.shared.urlForApplication(withBundleIdentifier: craBundleID) == nil {
                    let removed = SecItemDelete(query(older).filter { $0.key != kSecMatchLimit as String } as CFDictionary)
                    NSLog("Cra: removing the \(older) Keychain item: \(removed == errSecSuccess ? "done" : "failed (\(removed))")")
                }
                return found
            }
            if status == errSecItemNotFound { return secret(of: item) }
            NSLog("Cra: reading the \(older) Keychain item failed (\(status))")
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "\(Brand.name) needs the key to your saved passwords and cookies"
            alert.informativeText = "They are encrypted with a key in the Keychain item “\(older)”, which macOS did not let "
                + "\(Brand.name) read. \(Brand.name) moves it to its own item, “\(item)”, once: click Try Again, then "
                + "Always Allow, and enter your login password.\n\nWithout the key, websites sign you out and saved "
                + "passwords and cards can’t be used."
            alert.addButton(withTitle: "Try Again")
            alert.addButton(withTitle: "Quit \(Brand.name)")
            alert.addButton(withTitle: "Continue Without Them")
            switch alert.runModal() {
            case .alertFirstButtonReturn: continue
            case .alertSecondButtonReturn: exit(0)
            default:
                NSLog("Cra: going on without the \(older) Keychain item's secret")
                return secret(of: item)
            }
        }
    }

    /// Signed by a team (Developer ID, or the Mac's own Apple Development identity), so the
    /// Keychain keeps trusting Pane across updates and rebuilds.
    private static var isSignedByTeam: Bool {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return false }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] is String
    }

    /// Re-encrypts every mock-keychain value in every profile and the import's staged
    /// rows. All databases commit together or none does. Each one notes it in its meta
    /// table in the same transaction, so a later run never encrypts a value twice (a
    /// wrong key "decrypts" about once in 256, which tells nothing).
    private static func migrate(to newKey: Data, item: SafeStorageItem) -> Bool {
        let fm = FileManager.default
        let root = AppPaths.chromiumCache
        let profiles = ((try? fm.contentsOfDirectory(atPath: root.path)) ?? []).filter { $0 == "Default" || $0.hasPrefix("Profile ") }
        var open: [OpaquePointer] = []
        defer { open.forEach { sqlite3_close($0) } }
        var count = 0
        for profile in profiles {
            for name in databases {
                let path = root.appendingPathComponent(profile).appendingPathComponent(name).path
                guard fm.fileExists(atPath: path) else { continue }
                var db: OpaquePointer?
                guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
                    sqlite3_close(db)
                    NSLog("Cra: could not open \(profile)/\(name) to re-encrypt it")
                    return false
                }
                sqlite3_busy_timeout(db, 500)
                let hasMeta = !SQLite.rows(db, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'meta'").isEmpty
                if hasMeta, !SQLite.rows(db, "SELECT 1 FROM meta WHERE key = '\(metaKey)'").isEmpty {
                    sqlite3_close(db)
                    continue
                }
                open.append(db)
                guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK,
                      let n = reencrypt(db, from: mockKey, to: newKey),
                      !hasMeta || sqlite3_exec(db, "INSERT INTO meta (key, value) VALUES ('\(metaKey)', 'keychain')", nil, nil, nil) == SQLITE_OK else {
                    NSLog("Cra: could not re-encrypt \(profile)/\(name)")
                    open.forEach { sqlite3_exec($0, "ROLLBACK", nil, nil, nil) }
                    return false
                }
                count += n
            }
        }
        guard CredentialImport.reencryptPending(from: mockKey, to: newKey) else {
            open.forEach { sqlite3_exec($0, "ROLLBACK", nil, nil, nil) }
            return false
        }
        for db in open where sqlite3_exec(db, "COMMIT", nil, nil, nil) != SQLITE_OK {
            NSLog("Cra: committing re-encrypted values failed: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
        NSLog("Cra: moved \(count) encrypted values to the \(item) Keychain item")
        return true
    }

    /// Every BLOB that decrypts with `old`, in every table. Returns the number changed.
    private static func reencrypt(_ db: OpaquePointer, from old: Data, to new: Data) -> Int? {
        var changed = 0
        let tables = SQLite.rows(db, "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")
            .compactMap { $0["name"] as? String }
        for table in tables {
            let columns = SQLite.rows(db, "SELECT name FROM pragma_table_info('\(table)')").compactMap { $0["name"] as? String }
            for column in columns {
                // WITHOUT ROWID tables have no rowid; Chromium keeps no encrypted values in those.
                let rows = SQLite.rows(db, "SELECT rowid AS r, \"\(column)\" AS v FROM \"\(table)\" WHERE typeof(\"\(column)\") = 'blob' AND substr(\"\(column)\", 1, 3) = X'763130'")
                for row in rows {
                    guard let rowid = row["r"] as? Int64, let blob = row["v"] as? Data,
                          let plain = ChromiumCrypto.decrypt(blob, key: old) else { continue }
                    var stmt: OpaquePointer?
                    guard sqlite3_prepare_v2(db, "UPDATE \"\(table)\" SET \"\(column)\" = ? WHERE rowid = ?", -1, &stmt, nil) == SQLITE_OK else { return nil }
                    SQLite.bind(stmt, [ChromiumCrypto.encrypt(plain, key: new), rowid])
                    let done = sqlite3_step(stmt) == SQLITE_DONE
                    sqlite3_finalize(stmt)
                    guard done else { return nil }
                    changed += 1
                }
            }
        }
        return changed
    }
}
