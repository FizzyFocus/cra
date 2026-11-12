import CraCore
import Foundation
import Testing

/// Cra became Pane on 12 Nov 2026: pane:// with cra:// as an alias, and a first launch that copies
/// Cra's data folder.
struct BrandTests {
    @Test func internalScheme() {
        #expect(InternalScheme.owns(scheme: "pane"))
        #expect(InternalScheme.owns(scheme: "PANE"))
        #expect(InternalScheme.owns(scheme: "cra"), "Cra's scheme stays an alias")
        #expect(!InternalScheme.owns(scheme: "https"))
        #expect(!InternalScheme.owns(scheme: "craft"))
        #expect(!InternalScheme.owns(scheme: nil))
        for url in ["pane://settings", "pane:debug", "Pane://open?url=x", "cra://action/newTab", "CRA:dismiss"] {
            #expect(InternalScheme.isInternal(url), "\(url)")
        }
        for url in ["", "pane", "https://pane.uz", "crab://x", "craft://x", "javascript:cra://x", "file:///cra://"] {
            #expect(!InternalScheme.isInternal(url), "\(url)")
        }
        #expect(InternalScheme.canonical("cra://settings/privacy") == "pane://settings/privacy")
        #expect(InternalScheme.canonical("CRA://settings") == "pane://settings")
        #expect(InternalScheme.canonical("pane://settings") == "pane://settings")
        #expect(InternalScheme.canonical("https://cra.example/cra://x") == "https://cra.example/cra://x")
        #expect(InternalScheme.canonical("craft://x") == "craft://x")
    }

    @Test func folderNames() {
        #expect(DataFolder.name(dev: false) == "Pane")
        #expect(DataFolder.name(dev: true) == "PaneDev")
        #expect(DataFolder.legacyName(dev: false) == "Cra")
        #expect(DataFolder.legacyName(dev: true) == "CraDev")
        #expect(Brand.bundleIdentifier == "uz.pane.browser")
        #expect(Brand.Legacy.bundleIdentifier == "dk.kildahl.cra")
    }

    @Test func migratesOnlyIntoAMissingFolderFromAnExistingOne() {
        let pane = URL(fileURLWithPath: "/AS/Pane"), cra = URL(fileURLWithPath: "/AS/Cra")
        func plan(_ present: Set<String>, overridden: Bool = false) -> DataFolder.Plan {
            DataFolder.plan(target: pane, legacy: cra, overridden: overridden) { present.contains($0.lastPathComponent) }
        }
        #expect(plan(["Cra"]) == .copy(from: cra, to: pane))
        #expect(plan(["Cra", "Pane"]) == .none, "already migrated, or Pane made its own")
        #expect(plan(["Pane"]) == .none)
        #expect(plan([]) == .none, "a new Mac starts empty")
        #expect(plan(["Cra"], overridden: true) == .none, "CRA_DATA_DIR copies never migrate")
    }

    @Test func copySkipsChromiumsLocksOnly() {
        #expect(DataFolder.skips("Chromium/SingletonLock"))
        #expect(DataFolder.skips("Chromium/SingletonSocket"))
        #expect(DataFolder.skips("Chromium/SingletonCookie"))
        #expect(!DataFolder.skips("Chromium/Default/SingletonLock"))
        #expect(!DataFolder.skips("SingletonLock"))
        #expect(!DataFolder.skips("Chromium/Default"))
        #expect(!DataFolder.skips("sidebar.json"))
    }

    @Test func copyKeepsFilesFoldersAndLinks() throws {
        let fm = FileManager.default
        // Short, so the socket's path fits sockaddr_un.
        let root = URL(fileURLWithPath: "/tmp/pb-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let cra = root.appendingPathComponent("Cra", isDirectory: true), pane = root.appendingPathComponent("Pane", isDirectory: true)
        try fm.createDirectory(at: cra.appendingPathComponent("Chromium/Default/Extensions/abc"), withIntermediateDirectories: true)
        try fm.createDirectory(at: cra.appendingPathComponent("Favicons"), withIntermediateDirectories: true)
        try Data(#"{"spaces":[]}"#.utf8).write(to: cra.appendingPathComponent("sidebar.json"))
        try Data("cookies".utf8).write(to: cra.appendingPathComponent("Chromium/Default/Cookies"))
        try Data("{}".utf8).write(to: cra.appendingPathComponent("Chromium/Default/Extensions/abc/manifest.json"))
        try fm.createSymbolicLink(atPath: cra.appendingPathComponent("Chromium/SingletonLock").path, withDestinationPath: "mac-123")
        try fm.createSymbolicLink(atPath: cra.appendingPathComponent("Chromium/RunningChromeVersion").path, withDestinationPath: "156.0")
        // A socket, as the MCP server leaves one in the folder.
        let socketPath = cra.appendingPathComponent("mcp.sock").path
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            for (i, b) in socketPath.utf8.prefix(buf.count - 1).enumerated() { buf[i] = b }
        }
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }

        try DataFolder.copy(cra, to: pane)

        #expect(try String(contentsOf: pane.appendingPathComponent("sidebar.json"), encoding: .utf8) == #"{"spaces":[]}"#)
        #expect(try String(contentsOf: pane.appendingPathComponent("Chromium/Default/Cookies"), encoding: .utf8) == "cookies")
        #expect(fm.fileExists(atPath: pane.appendingPathComponent("Chromium/Default/Extensions/abc/manifest.json").path))
        #expect(fm.fileExists(atPath: pane.appendingPathComponent("Favicons").path))
        #expect(try fm.destinationOfSymbolicLink(atPath: pane.appendingPathComponent("Chromium/RunningChromeVersion").path) == "156.0")
        #expect(!fm.fileExists(atPath: pane.appendingPathComponent("Chromium/SingletonLock").path))
        #expect(bound == 0)
        if bound == 0 { #expect(!fm.fileExists(atPath: pane.appendingPathComponent("mcp.sock").path)) }
        // Cra's folder is left as it was, and no half-made folder stays beside the new one.
        #expect(fm.fileExists(atPath: cra.appendingPathComponent("sidebar.json").path))
        #expect(try fm.contentsOfDirectory(atPath: root.path).sorted() == ["Cra", "Pane"])
    }

    @Test func aFailedCopyLeavesNoFolder() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("brand-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try DataFolder.copy(root.appendingPathComponent("Missing"), to: root.appendingPathComponent("Pane")) }
        #expect(try fm.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    /// An agent set up for Cra lists the browser as "cra": Pane shows it as outdated, and adding
    /// writes "pane" in its place instead of a second entry.
    @Test func mcpEntryUnderCrasNameIsReplaced() throws {
        let json = MCPConfigFormat.json(key: "mcpServers", stdioType: false)
        let pane = MCPServerEntry(name: "pane", command: "/Applications/Pane.app/Contents/MacOS/Pane", args: ["--mcp", "/s.sock"])
        #expect(MCPAgentSetup.legacyName(of: "pane") == "cra")
        #expect(MCPAgentSetup.legacyName(of: "pane-dev") == "cra-dev")
        let old = Data(#"{"mcpServers": {"cra": {"command": "/Applications/Cra.app/Contents/MacOS/Cra", "args": ["--mcp", "/c.sock"]}, "other": {"command": "x"}}}"#.utf8)
        #expect(MCPAgentSetup.stateCountingLegacy(of: pane, in: old, format: json) == .outdated)
        let fixed = try MCPAgentSetup.addingReplacingLegacy(pane, to: old, format: json)
        let servers = try #require((try JSONSerialization.jsonObject(with: fixed) as? [String: Any])?["mcpServers"] as? [String: Any])
        #expect(servers["cra"] == nil)
        #expect(servers["pane"] != nil)
        #expect(servers["other"] != nil, "other servers stay")
        #expect(MCPAgentSetup.stateCountingLegacy(of: pane, in: fixed, format: json) == .current)
        #expect(MCPAgentSetup.stateCountingLegacy(of: pane, in: Data("{}".utf8), format: json) == .absent)

        let toml = Data("[mcp_servers.cra]\ncommand = \"/Old/Cra\"\nargs = [\"--mcp\", \"/c.sock\"]\n".utf8)
        #expect(MCPAgentSetup.stateCountingLegacy(of: pane, in: toml, format: .codexTOML) == .outdated)
        let text = String(decoding: try MCPAgentSetup.addingReplacingLegacy(pane, to: toml, format: .codexTOML), as: UTF8.self)
        #expect(text.contains("[mcp_servers.pane]"))
        #expect(!text.contains("mcp_servers.cra"))
    }

    /// A sync folder set up before the rebrand holds a "Cra" bundle folder: it's still the one used.
    @Test func syncFolderKeepsCrasBundle() {
        let picked = URL(fileURLWithPath: "/Dropbox", isDirectory: true)
        func folder(_ present: Set<String>) -> String {
            SettingsSync.bundleFolder(in: picked) { present.contains($0.lastPathComponent) }.path
        }
        #expect(folder([]) == "/Dropbox/Pane")
        #expect(folder(["Cra"]) == "/Dropbox/Cra")
        #expect(folder(["Pane", "Cra"]) == "/Dropbox/Pane")
        #expect(SettingsSync.bundleFolder(in: URL(fileURLWithPath: "/Dropbox/Cra")) { _ in false }.path == "/Dropbox/Cra")
        #expect(SettingsSync.bundleFolder(in: URL(fileURLWithPath: "/Dropbox/Pane")) { _ in false }.path == "/Dropbox/Pane")
    }
}
