import Foundation

/// The product's name and what is derived from it. Cra was rebranded Pane (pane.uz) on 12 Nov
/// 2026: what a person sees, the app bundle, the data folder and the internal URL scheme say
/// Pane, while module, target and type names keep Cra (CraCore, CraBrowser, CraWindow…) so
/// commits from upstream VictorKildahl/cra still port with few conflicts.
public enum Brand {
    public static let name = "Pane"
    public static let site = "https://pane.uz"
    public static let bundleIdentifier = "uz.pane.browser"
    public static let devBundleIdentifier = "uz.pane.browser.dev"

    /// The names before the rebrand: what a first launch of Pane migrates from.
    public enum Legacy {
        public static let name = "Cra"
        public static let bundleIdentifier = "dk.kildahl.cra"
        public static let devBundleIdentifier = "dk.kildahl.cra.dev"
    }
}

/// Pane's own URL scheme: `pane://settings`, `pane://open?url=…`, `pane://debug?…`. Cra's
/// `cra://` stays an alias, so bookmarks, saved tabs, scripts and upstream code that name it
/// still resolve; anything Pane writes or shows says `pane://`.
public enum InternalScheme {
    public static let name = "pane"
    public static let legacy = "cra"

    /// Whether `scheme` (any case) is Pane's own or Cra's alias.
    public static func owns(scheme: String?) -> Bool {
        guard let s = scheme?.lowercased() else { return false }
        return s == name || s == legacy
    }

    /// Whether `url` is an internal address: "pane:…" or "cra:…", any case, with or without "//".
    public static func isInternal(_ url: String) -> Bool {
        guard let colon = url.firstIndex(of: ":") else { return false }
        return owns(scheme: String(url[..<colon]))
    }

    /// `url` with Cra's scheme spelled as Pane's ("cra://settings/privacy" → "pane://settings/privacy");
    /// any other address as it is.
    public static func canonical(_ url: String) -> String {
        guard let colon = url.firstIndex(of: ":"), url[..<colon].lowercased() == legacy else { return url }
        return name + url[colon...]
    }
}

/// The data folder in Application Support: Pane (PaneDev for the dev build) since the rebrand.
/// A first launch finds no Pane folder but Cra's, and copies it over before anything reads it,
/// so spaces, tabs, history, sign-ins, extensions and settings come along. Cra's folder stays
/// as it was (a backup, and what an old Cra.app still opens).
public enum DataFolder {
    public static func name(dev: Bool) -> String { dev ? Brand.name + "Dev" : Brand.name }
    public static func legacyName(dev: Bool) -> String { dev ? Brand.Legacy.name + "Dev" : Brand.Legacy.name }

    public enum Plan: Equatable, Sendable {
        /// Nothing to do: the folder is there, there is no Cra folder, or CRA_DATA_DIR picks another one.
        case none
        /// Cra's folder is copied to the new one first.
        case copy(from: URL, to: URL)
    }

    /// What a launch does before it reads `target`, its data folder. `overridden`: the folder came
    /// from CRA_DATA_DIR (a test copy), which never migrates.
    public static func plan(target: URL, legacy: URL, overridden: Bool, exists: (URL) -> Bool) -> Plan {
        guard !overridden, !exists(target), exists(legacy) else { return .none }
        return .copy(from: legacy, to: target)
    }

    /// Entries a copy leaves out: Chromium's single-instance lock, socket and cookie name the
    /// process that had the profile open (a copy would point at Cra's), and sockets aren't data.
    public static func skips(_ relativePath: String) -> Bool {
        let name = (relativePath as NSString).lastPathComponent
        return name.hasPrefix("Singleton") && relativePath.hasPrefix("Chromium/") && !relativePath.dropFirst(9).contains("/")
    }

    /// Copies `source` to `destination` (which must not exist): through a folder beside it that
    /// is renamed into place last, so a copy cut short leaves nothing a later launch would take
    /// for a migrated folder. Files are cloned on APFS (no extra space, instant), copied
    /// elsewhere; symbolic links stay links; sockets and `skips` are left out.
    public static func copy(_ source: URL, to destination: URL, fileManager fm: FileManager = .default) throws {
        let partial = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent)-migrating-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: partial, withIntermediateDirectories: true)
            try copyContents(of: source, into: partial, relative: "", fm: fm)
            try fm.moveItem(at: partial, to: destination)
        } catch {
            try? fm.removeItem(at: partial)
            throw error
        }
    }

    private static func copyContents(of dir: URL, into out: URL, relative: String, fm: FileManager) throws {
        for name in try fm.contentsOfDirectory(atPath: dir.path) {
            let rel = relative.isEmpty ? name : relative + "/" + name
            if skips(rel) { continue }
            let from = dir.appendingPathComponent(name), to = out.appendingPathComponent(name)
            let type = try fm.attributesOfItem(atPath: from.path)[.type] as? FileAttributeType
            switch type {
            case .typeDirectory?:
                try fm.createDirectory(at: to, withIntermediateDirectories: false)
                try copyContents(of: from, into: to, relative: rel, fm: fm)
            case .typeSymbolicLink?:
                try fm.createSymbolicLink(atPath: to.path, withDestinationPath: fm.destinationOfSymbolicLink(atPath: from.path))
            case .typeRegular?:
                // COPYFILE_CLONE falls back to a plain copy where cloning isn't possible.
                if copyfile(from.path, to.path, nil, copyfile_flags_t(COPYFILE_CLONE | COPYFILE_ALL)) != 0 {
                    throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: from.path,
                                                                   NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)])
                }
            default:
                continue  // sockets, pipes, devices
            }
        }
    }
}
