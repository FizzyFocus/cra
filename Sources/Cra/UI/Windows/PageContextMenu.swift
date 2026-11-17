import AppKit
import CraCEF

/// The page's right-click menu on the Chromium engine (CraCore PageMenu says why Pane opens its own): a right-click,
/// or a Control-click, on a page shown in a browser or Little Window still reaches the page; a moment later the page's
/// isolated world says what it hit and whether the page made a menu of its own, and a native menu of Chrome's items
/// opens at the pointer. Chrome's menu, which never appears, is turned off for the page (suppressesContextMenu).
@MainActor
final class PageContextMenuController: NSObject {
    static let shared = PageContextMenuController()

    private weak var app: AppDelegate?
    private var monitor: Any?
    private var open: Opened?

    /// The menu on screen, for its items' actions.
    private struct Opened {
        weak var browser: CraBrowser?
        weak var window: MainWindowController?
        let context: PageMenu.Context
        let pagePoint: NSPoint
    }

    /// From AppDelegate, on the Chromium engine only (CEF draws its own menu).
    func install(app: AppDelegate) {
        guard monitor == nil else { return }
        self.app = app
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
            if event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
                MainActor.assumeIsolated { self?.rightClick(event) }
            }
            return event
        }
    }

    private func rightClick(_ event: NSEvent) {
        guard let window = event.window, let app else { return }
        let at = event.locationInWindow
        func onPage(_ view: NSView) -> Bool {
            view.window === window && !view.isHiddenOrHasHiddenAncestor && view.convert(view.bounds, to: nil).contains(at)
        }
        var page: (CraBrowser, MainWindowController?, Bool)?
        if let main = app.mainWindows.first(where: { $0.window === window }) {
            for id in main.browsers.visibleTabIDs {
                if let rt = main.browsers.runtime(for: id), onPage(rt.browser.containerView) { page = (rt.browser, main, false) }
            }
        } else if let little = app.littleWindows.first(where: { $0.window === window }), let b = little.browser, onPage(b.containerView) {
            page = (b, nil, true)
        }
        // Chromium's pages only: a WebKit tab and Pane's own pages (pane://settings, easels) have their own menus.
        guard let (browser, main, little) = page, type(of: browser) == CraBrowser.self, browser.isCreated, !browser.isClosed else { return }
        browser.suppressesContextMenu = true
        let container = browser.containerView
        let local = container.convert(at, from: nil)
        let pagePoint = NSPoint(x: local.x, y: container.isFlipped ? local.y : container.bounds.height - local.y)
        // Once Chromium has dispatched the click to the page (the contextmenu event and its handlers).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak browser, weak main] in
            guard let self, let browser, !browser.isClosed else { return }
            let params = (try? JSONSerialization.data(withJSONObject: ["expression": PageMenu.snapshotScript, "returnByValue": true]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            browser.evaluate(inIsolatedWorld: PageScript.world, params: params) { [weak self, weak browser, weak main] result, _ in
                let value = (result?.data(using: .utf8)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    .flatMap { ($0["result"] as? [String: Any])?["value"] as? String }
                DispatchQueue.main.async {
                    guard let self, let browser else { return }
                    let record = value.flatMap { PageMenu.record(snapshot: $0) }
                    // The page made a menu of its own (Google Docs, a map): Chrome shows none, nor does Pane.
                    if record?.prevented == true { CraLog.note("page menu: none, the page shows its own"); return }
                    self.show(browser, main: main, little: little, record: record, event: event, pagePoint: pagePoint)
                }
            }
        }
    }

    private func show(_ browser: CraBrowser, main: MainWindowController?, little: Bool, record: PageMenu.Record?,
                      event: NSEvent, pagePoint: NSPoint) {
        guard app != nil, let view = EmbeddedPages.renderView(in: browser.containerView) ?? browser.containerView.window?.contentView else { return }
        var c = PageMenu.Context()
        if let r = record {
            c.link = r.link
            c.image = r.image
            c.selection = r.selection
            c.editable = r.editable
        }
        c.canGoBack = browser.canGoBack
        c.canGoForward = browser.canGoForward
        c.incognito = browser.isIncognito
        c.littleWindow = little
        c.canPeek = browser.delegate?.responds(to: #selector(CraBrowserDelegate.browser(_:requestsPeekWithURL:))) == true
        c.canPreviewImage = browser.delegate?.responds(to: #selector(CraBrowserDelegate.browser(_:requestsPreviewOfImageURL:at:))) == true
        c.searchName = searchEngine(for: browser).name
        c.newTabTitle = Self.menuTitle(CraCEFRuntime.chromiumString(.openLinkInNewTab) ?? LinkMenu.newTabTitle)
        let menu = NSMenu(title: "Page")
        menu.autoenablesItems = false
        // macOS adds its own text items (Writing Tools, AutoFill, Services) to a menu over a focused text field and
        // acts on the field through them: closing the menu over a field put spaces in place of its word.
        menu.allowsContextMenuPlugIns = false
        if #available(macOS 15.2, *) { menu.automaticallyInsertsWritingToolsItems = false }
        for item in PageMenu.items(c) {
            if item.isSeparator { menu.addItem(.separator()); continue }
            let row = NSMenuItem(title: item.title, action: #selector(run(_:)), keyEquivalent: "")
            row.target = self
            row.isEnabled = item.enabled
            row.representedObject = item.action?.rawValue
            menu.addItem(row)
        }
        let point = record.map { NSPoint(x: $0.x, y: $0.y) } ?? pagePoint
        open = Opened(browser: browser, window: main, context: c, pagePoint: point)
        CraLog.note("page menu: \(menu.items.filter { !$0.isSeparatorItem }.count) items for a \(c.link.isEmpty ? (c.image.isEmpty ? (c.editable ? "field" : (c.selection.isEmpty ? "page" : "selection")) : "picture") : "link")")
        // A context menu as Chrome opens one: from the right-click itself, over the page's own view. Chromium's view
        // gives up the keyboard while it is open and takes it back after: macOS otherwise acts on the text input it
        // finds in front, and closing the menu over a field put spaces in place of its selected word (17 Nov 2026).
        let window = view.window
        let previous = window?.firstResponder
        window?.makeFirstResponder(nil)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
        if let previous, let window, window.firstResponder === window || window.firstResponder == nil {
            window.makeFirstResponder(previous)
        }
    }

    @objc private func run(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let action = PageMenu.Action(rawValue: raw),
              let o = open, let browser = o.browser, !browser.isClosed else { return }
        let c = o.context
        let delegate = browser.delegate
        let background = app?.store.settings.openLinksInForeground != true
        CraLog.note("page menu runs \(action.rawValue)")
        switch action {
        case .openLinkInNewTab: delegate?.browser(browser, requestsNewTabWithURL: c.link, inBackground: background)
        case .openLinkInNewWindow: openWindow(browser, c.link, .new)
        case .openLinkInIncognito: openWindow(browser, c.link, .incognito)
        case .openLinkInLittleWindow: openWindow(browser, c.link, .little)
        case .openLinkInSplitView: delegate?.browser?(browser, requestsSplitPaneWithURL: c.link)
        case .openLinkInPeek: delegate?.browser?(browser, requestsPeekWithURL: c.link)
        case .openImageInPreview: delegate?.browser?(browser, requestsPreviewOfImageURL: c.image, at: o.pagePoint)
        case .copyLinkAddress: copy(text: c.link)
        case .openImageInNewTab: delegate?.browser(browser, requestsNewTabWithURL: c.image, inBackground: background)
        case .copyImageAddress: copy(text: c.image)
        case .copyImage: copyImage(c.image)
        case .cut: edit(browser, "cut")
        case .copy: edit(browser, "copy")
        case .paste: edit(browser, "paste")
        case .selectAll: edit(browser, "selectAll")
        case .searchSelection:
            delegate?.browser(browser, requestsNewTabWithURL: searchEngine(for: browser).searchURL(c.selection), inBackground: false)
        case .back: browser.goBack()
        case .forward: browser.goForward()
        case .reload: browser.reload()
        case .savePageAs: o.window?.savePageAs()
        case .print: browser.print()
        case .viewSource: browser.viewSource()
        case .inspect: browser.showDevToolsInspectingPoint(o.pagePoint)
        }
    }

    /// Chromium's strings mark a menu's access key with "&" ("Open Link in New &Tab"), which a Mac menu shows as is.
    static func menuTitle(_ chromium: String) -> String {
        chromium.replacingOccurrences(of: "&&", with: "\u{1}").replacingOccurrences(of: "&", with: "")
            .replacingOccurrences(of: "\u{1}", with: "&")
    }

    /// The clipboard Copy Link Address and the others write to: a test copy's own (CRA_TEST_BACKGROUND), so a
    /// scenario never touches the person's (cra://debug?pageMenuPasteboard reads it).
    static let pasteboard: NSPasteboard = ProcessInfo.processInfo.environment["CRA_TEST_BACKGROUND"] == "1"
        ? NSPasteboard(name: NSPasteboard.Name("uz.pane.test.pagemenu")) : .general

    private func openWindow(_ browser: CraBrowser, _ url: String, _ kind: CraLinkWindow) {
        if browser.delegate?.responds(to: #selector(CraBrowserDelegate.browser(_:requestsWindowWithURL:kind:))) == true {
            browser.delegate?.browser?(browser, requestsWindowWithURL: url, kind: kind)
        } else {
            browser.delegate?.browser(browser, requestsNewTabWithURL: url, inBackground: false)
        }
    }

    private func searchEngine(for browser: CraBrowser) -> ChromiumSearchEngine {
        SearchEngines.shared.defaultEngine(profilePath: browser.profilePath, legacy: app?.store.settings.searchEngine ?? .google)
    }

    private func copy(text: String) {
        let pb = Self.pasteboard
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// The picture's bytes, fetched by the app without cookies (as a page's favicon), on the pasteboard.
    private func copyImage(_ url: String) {
        guard let source = URL(string: url), ["http", "https", "data"].contains(source.scheme ?? "") else { return }
        URLSession.shared.dataTask(with: source) { data, _, _ in
            DispatchQueue.main.async {
                guard let data, let image = NSImage(data: data) else { CraLog.note("page menu: the picture didn't load"); return }
                let pb = PageContextMenuController.pasteboard
                pb.clearContents()
                pb.writeObjects([image])
            }
        }.resume()
    }

    /// Cut, Copy, Paste and Select All: Chromium's editing commands in the page's focused element (the one the
    /// right-click focused), as a key press carrying them gives them, whether or not the window is key.
    private func edit(_ browser: CraBrowser, _ command: String) {
        browser.sendDevToolsMethod("Input.dispatchKeyEvent", params: #"{"type":"rawKeyDown","commands":["\#(command)"]}"#) { _, error in
            if let error { DispatchQueue.main.async { CraLog.note("page menu: \(command) failed: \(error)") } }
        }
        browser.sendDevToolsMethod("Input.dispatchKeyEvent", params: #"{"type":"keyUp"}"#) { _, _ in }
    }
}
