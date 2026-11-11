import AppKit
import CraCEF
import WebKit

/// Settings as a tab (CraCore SettingsPage): `cra://settings` is an HTML page of Cra's own
/// (resources/web/settings) in a WKWebView, the way Chrome's settings are a page. Like EaselBrowser
/// it is a CraBrowser hosting its own view, so the tab, split view, the sidebar row, ⌘W and Peek
/// work as for any page. The page reads and writes settings through `window.craSettings`
/// (SettingsPageBridge); whatever changes them, here or anywhere in Cra, is pushed back to it.
final class SettingsPageBrowser: CraBrowser, NativePage, WKUIDelegate {
    nonisolated func owns(_ url: String) -> Bool { SettingsPage.owns(url) }

    private let container: NSView
    private var web: WKWebView?
    private var address: String
    private var closed = false
    private var bridge: SettingsPageBridge?
    /// macOS going light or dark, for Websites ▸ Automatic.
    private var appearanceWatch: NSKeyValueObservation?

    override init(frame: NSRect, url: String?, delegate: CraBrowserDelegate?, incognito: Bool, profilePath: String?) {
        container = NSView(frame: frame)
        address = url.flatMap { SettingsPage.owns($0) ? $0 : nil } ?? SettingsPage.address
        super.init()
        self.delegate = delegate
        MainActor.assumeIsolated { makePage() }
        // Like a page, it reports its address and title a turn later, once the tab holds it.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.closed else { return }
            self.delegate?.browser(self, didChangeURL: self.address)
            self.delegate?.browser(self, didChangeTitle: SettingsPage.title)
            self.delegate?.browser?(self, didChangeCommittedLoad: true)
            self.delegate?.browser(self, didChangeLoading: false, canGoBack: false, canGoForward: false)
            self.delegate?.browser(self, didFinishLoadingURL: self.address, title: SettingsPage.title, statusCode: 200)
        }
    }

    override convenience init(frame: NSRect, url: String?, delegate: CraBrowserDelegate?) {
        self.init(frame: frame, url: url, delegate: delegate, incognito: false, profilePath: nil)
    }

    override convenience init(frame: NSRect, url: String?, delegate: CraBrowserDelegate?, incognito: Bool) {
        self.init(frame: frame, url: url, delegate: delegate, incognito: incognito, profilePath: nil)
    }

    @MainActor private func makePage() {
        container.wantsLayer = true
        container.autoresizesSubviews = true
        let config = WKWebViewConfiguration()
        // Nothing to keep: the page holds no data of its own.
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(SettingsPageFiles(), forURLScheme: SettingsPage.scheme)
        let bridge = SettingsPageBridge(page: self)
        config.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: "craSettings")
        self.bridge = bridge
        let web = WKWebView(frame: container.bounds, configuration: config)
        web.autoresizingMask = [.width, .height]
        web.allowsBackForwardNavigationGestures = false
        web.allowsMagnification = false
        web.underPageBackgroundColor = .clear
        web.uiDelegate = self
        container.addSubview(web)
        self.web = web
        followAppearance()
        appearanceWatch = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.followAppearance() } }
        }
        if let u = URL(string: address) { web.load(URLRequest(url: u)) }
        bridge.start()
    }

    // MARK: The page's alert() and confirm(), as sheets on the window

    @MainActor func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                            initiatedByFrame frame: WKFrameInfo) async {
        _ = await sheet(message, buttons: ["OK"])
    }

    @MainActor func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                            initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await sheet(message, buttons: ["OK", "Cancel"]) == .alertFirstButtonReturn
    }

    @MainActor private func sheet(_ message: String, buttons: [String]) async -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = message
        for b in buttons { alert.addButton(withTitle: b) }
        guard let window = container.window else { return alert.runModal() }
        return await alert.beginSheetModal(for: window)
    }

    /// Websites ▸ Automatic: the page follows macOS, as the pages in other tabs do; Light or Dark
    /// sets it (the page also reads `theme` from the state).
    @MainActor func followAppearance() {
        guard let web else { return }
        switch (NSApp.delegate as? AppDelegate)?.store.settings.websiteAppearance ?? .automatic {
        case .automatic: web.appearance = NSApp.effectiveAppearance
        case .light: web.appearance = NSAppearance(named: .aqua)
        case .dark: web.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// The section the tab is on changed (the page's sidebar): the tab's address follows it.
    @MainActor func didShowSection(_ section: SettingsPage.Section) {
        let url = SettingsPage.url(section)
        guard url != address else { return }
        address = url
        delegate?.browser(self, didChangeURL: url)
    }

    /// Runs the page's own script (Cra moving it to a section, the state pushed to it).
    @MainActor func run(_ script: String) {
        web?.evaluateJavaScript(script, completionHandler: nil)
    }

    /// `cra://debug?settingsPageJS=<script>`: the script's answer (a promise is waited for).
    @MainActor func debugEvaluate(_ script: String, done: @escaping (String) -> Void) {
        guard let web else { done("no page"); return }
        web.callAsyncJavaScript("return await (\(script))", arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .success(let v): done("\(v)")
            case .failure(let e): done("error \((e as NSError).userInfo["WKJavaScriptExceptionMessage"] ?? e.localizedDescription)")
            }
        }
    }

    /// The window the page is in, for actions that open something there.
    @MainActor var windowController: MainWindowController? {
        guard let app = NSApp.delegate as? AppDelegate else { return nil }
        return app.mainWindows.first { $0.window != nil && $0.window === container.window } ?? app.main
    }

    override var containerView: NSView { container }
    override var hostWindow: NSWindow? { nil }
    override var currentURL: String { address }
    override var currentTitle: String { SettingsPage.title }
    override var isLoading: Bool { false }
    override var hasCommittedLoad: Bool { true }
    override var canGoBack: Bool { false }
    override var canGoForward: Bool { false }
    override var isCreated: Bool { !closed }
    override var isClosed: Bool { closed }
    override var hasDevTools: Bool { false }

    /// Another section of Settings stays in the page; any other address goes to a page of its own.
    override func loadURL(_ url: String) {
        guard SettingsPage.owns(url) else {
            _ = delegate?.browser?(self, handsOffNavigationToURL: url, method: "GET")
            return
        }
        let section = SettingsPage.section(of: url)
        MainActor.assumeIsolated {
            didShowSection(section)
            run("window.craSettingsShow && window.craSettingsShow(\(Self.quoted(section.rawValue)))")
        }
    }
    override func reload() { MainActor.assumeIsolated { _ = web?.reload() } }
    override func reloadIgnoringCache() { MainActor.assumeIsolated { _ = web?.reloadFromOrigin() } }
    override func stopLoading() {}
    override func goBack() {}
    override func goForward() {}
    override func setFocused(_ focused: Bool) {
        MainActor.assumeIsolated {
            guard focused, let web, let w = web.window else { return }
            w.makeFirstResponder(web)
        }
    }
    override func probeBackgroundColor() {}
    override func executeJavaScript(_ script: String) { MainActor.assumeIsolated { run(script) } }
    override func evaluate(inIsolatedWorld world: String, params: String, completion: @escaping (String?, String?) -> Void) {
        DispatchQueue.main.async { completion(nil, "Settings runs no page scripts") }
    }
    override func sendDevToolsMethod(_ method: String, params: String, completion: @escaping (String?, String?) -> Void) {
        DispatchQueue.main.async { completion(nil, "\(method): Settings has no DevTools") }
    }
    override func sslStatus() -> CraSSLStatus? { nil }
    override func print() {}
    override func viewSource() {}
    override func notifyMoveOrResizeStarted() {}

    override func close() {
        guard !closed else { return }
        closed = true
        MainActor.assumeIsolated {
            bridge?.stop()
            appearanceWatch = nil
            web?.configuration.userContentController.removeAllScriptMessageHandlers()
            web?.removeFromSuperview()
            web = nil
        }
        DispatchQueue.main.async { [self] in delegate?.browserDidClose(self) }
    }

    /// A JavaScript string literal.
    static func quoted(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }
}

/// The page's files, served at cra://settings/<file> from resources/web/settings in the app
/// (the source tree's in a build without a bundle), and the sites' icons at
/// cra://settings/favicon/<host> from the favicon cache. Every other path is the page itself, so
/// cra://settings/privacy opens it on Privacy.
final class SettingsPageFiles: NSObject, WKURLSchemeHandler {
    static var folder: URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("web/settings", isDirectory: true),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("index.html").path) {
            return bundled
        }
        // A test build without the app bundle: the source tree's copy.
        var source = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { source.deleteLastPathComponent() }
        return source.appendingPathComponent("resources/web/settings", isDirectory: true)
    }

    private static let types = ["html": "text/html", "css": "text/css", "js": "text/javascript", "svg": "image/svg+xml", "png": "image/png"]

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, SettingsPage.owns(url.absoluteString) else {
            task.didFailWithError(URLError(.unsupportedURL))
            return
        }
        let parts = url.path.split(separator: "/").map(String.init)
        if parts.count >= 2, ["favicon", "app-icon", "extension-icon", "agent-icon"].contains(parts[0]) {
            let key = parts[1].removingPercentEncoding ?? parts[1]
            let data: Data? = MainActor.assumeIsolated {
                switch parts[0] {
                case "app-icon": return Self.png(AppIconManager.shared.image(for: key), size: 64)
                case "extension-icon": return Self.png(ExtensionStore.shared.entries.first { $0.id == key }?.icon, size: 32)
                case "agent-icon": return Self.png(MCPAgentSetup.agents.first { $0.id == key }.flatMap(MCPAgentInstaller.shared.icon), size: 56)
                default: return Self.favicon(key)
                }
            }
            if data == nil, parts[0] == "favicon" {
                fetchFavicon(key, for: task, url: url)
                return
            }
            respond(task, url: url, data: data, type: "image/png")
            return
        }
        let name = parts.last.flatMap { $0.contains(".") ? $0 : nil } ?? "index.html"
        let file = Self.folder.appendingPathComponent(name)
        // Only the folder's own files.
        guard file.deletingLastPathComponent().standardizedFileURL == Self.folder.standardizedFileURL else {
            respond(task, url: url, data: nil, type: "text/plain")
            return
        }
        respond(task, url: url, data: try? Data(contentsOf: file), type: Self.types[file.pathExtension] ?? "application/octet-stream")
    }

    /// Tasks WebKit stopped (the page went, the image was dropped): nothing more may be sent to them.
    private var stopped = Set<ObjectIdentifier>()

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) { stopped.insert(ObjectIdentifier(task)) }

    /// A site Cra has no icon for yet (a search engine never visited): its own /favicon.ico, from the
    /// site itself and nowhere else, kept in the favicon cache for next time.
    private func fetchFavicon(_ host: String, for task: WKURLSchemeTask, url: URL) {
        guard !host.isEmpty, !host.contains("/"), let source = URL(string: "https://\(host)/favicon.ico") else {
            respond(task, url: url, data: nil, type: "image/png")
            return
        }
        var request = URLRequest(url: source, timeoutInterval: 6)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    var png: Data?
                    if let data, (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data), image.isValid {
                        (NSApp.delegate as? AppDelegate)?.favicons.store(image, forKey: host.lowercased())
                        png = Self.png(image, size: 32)
                    }
                    guard !self.stopped.contains(ObjectIdentifier(task)) else { return }
                    self.respond(task, url: url, data: png, type: "image/png")
                }
            }
        }.resume()
    }

    private func respond(_ task: WKURLSchemeTask, url: URL, data: Data?, type: String) {
        let status = data == nil ? 404 : 200
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": type, "Cache-Control": "no-store"])!
        task.didReceive(response)
        if let data { task.didReceive(data) }
        task.didFinish()
    }

    /// The icon Cra has for `host` as a PNG, nil while it has none.
    @MainActor private static func favicon(_ host: String) -> Data? {
        guard let favicons = (NSApp.delegate as? AppDelegate)?.favicons else { return nil }
        let h = host.lowercased()
        let bare = h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
        return png(favicons.image(forKey: h) ?? favicons.image(forKey: bare) ?? favicons.image(forKey: "www." + bare), size: 32)
    }

    @MainActor private static func png(_ image: NSImage?, size: CGFloat) -> Data? {
        guard let image else { return nil }
        var rect = NSRect(x: 0, y: 0, width: size, height: size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}

extension SettingsPageBrowser {
    /// PageEngines' hook, after EaselBrowser.register(): cra://settings gets the settings page and
    /// every other address goes to the hook before it (an easel's canvas). A page of an engine
    /// navigating to either (typed into the bar) gives the tab to it. Kept here, not in
    /// EaselBrowser, so that file still builds on its own in scripts/test-easel-canvas.sh.
    @MainActor static func register() {
        let earlier = PageEngines.nativePage
        PageEngines.nativePage = { frame, url, delegate, incognito, profilePath in
            if SettingsPage.owns(url) {
                return SettingsPageBrowser(frame: frame, url: url, delegate: delegate, incognito: incognito, profilePath: profilePath)
            }
            return earlier?(frame, url, delegate, incognito, profilePath)
        }
        PageEngines.nativeOwns = { SettingsPage.owns($0) || Easel.id(fromURL: $0) != nil }
    }

    /// The tab's icon: a gear, as the favicon cache's for the page's address.
    @MainActor static func registerIcon(in favicons: FaviconCache) {
        guard let key = FaviconKey.key(for: SettingsPage.address), favicons.image(forKey: key) == nil else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 26, weight: .medium).applying(.init(paletteColors: [.systemGray]))
        guard let symbol = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "Settings")?.withSymbolConfiguration(config) else { return }
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size, flipped: false) { r in
            let s = symbol.size
            symbol.draw(in: NSRect(x: (r.width - s.width) / 2, y: (r.height - s.height) / 2, width: s.width, height: s.height))
            return true
        }
        favicons.store(image, forKey: key, persist: false)
    }
}
