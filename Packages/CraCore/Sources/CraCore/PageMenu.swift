import Foundation

/// A page's right-click menu, as Pane builds it on the Chromium engine (17 Nov 2026). The engine's own (Chrome's,
/// with Arc's changes in the engine's bridge) never appears in Pane's windows: Chrome reaches its menu code, but no
/// menu opens. Pane opens a native menu of Chrome's items instead, from what the page's isolated world recorded of
/// the right-click (`recorderScript`): a page that handles its own right-click (preventDefault) gets none.
public enum PageMenu {
    /// What was right-clicked, from `recorderScript`, and what the page can do.
    public struct Context: Equatable, Sendable {
        public var link = ""
        public var image = ""
        public var selection = ""
        public var editable = false
        public var canGoBack = false
        public var canGoForward = false
        public var incognito = false
        /// The page is in a Little Window: no Little Window or Split View from it.
        public var littleWindow = false
        /// The page's window can Peek a link and preview a picture (Pane's items, ⇧-click's).
        public var canPeek = false
        public var canPreviewImage = false
        /// The search engine's name, for "Search <name> for “…”".
        public var searchName = "Google"
        /// The link item's title (LinkMenu: Chromium's "Open Link in New Tab").
        public var newTabTitle = LinkMenu.newTabTitle
        public init() {}
    }

    public enum Action: String, Sendable, CaseIterable {
        case openLinkInNewTab, openLinkInNewWindow, openLinkInIncognito, openLinkInSplitView, openLinkInLittleWindow, openLinkInPeek
        case copyLinkAddress, openImageInNewTab, openImageInPreview, copyImage, copyImageAddress
        case cut, copy, paste, selectAll, searchSelection
        case back, forward, reload, savePageAs, print, viewSource, inspect
    }

    /// One row: an action with its title, or a separator (no action).
    public struct Item: Equatable, Sendable {
        public let action: Action?
        public let title: String
        public let enabled: Bool
        static let separator = Item(action: nil, title: "", enabled: false)
        public var isSeparator: Bool { action == nil }
    }

    /// Chrome's rows for what was clicked (a link, an image, a selection, a field, else the page), then Inspect.
    public static func items(_ c: Context) -> [Item] {
        var groups: [[Item]] = []
        func item(_ a: Action, _ title: String, _ enabled: Bool = true) -> Item { Item(action: a, title: title, enabled: enabled) }
        if !c.link.isEmpty {
            var open = [item(.openLinkInNewTab, c.newTabTitle), item(.openLinkInNewWindow, "Open Link in New Window")]
            if !c.littleWindow {
                open.append(item(.openLinkInSplitView, "Open Link in Split View"))
                if !c.incognito { open.append(item(.openLinkInLittleWindow, "Open Link in Little Window")) }
            }
            if c.canPeek && !c.incognito { open.append(item(.openLinkInPeek, "Open Link in Peek")) }
            if !c.incognito { open.append(item(.openLinkInIncognito, "Open Link in Incognito Window")) }
            groups.append(open)
            groups.append([item(.copyLinkAddress, "Copy Link Address")])
        }
        if !c.image.isEmpty {
            var picture = [item(.openImageInNewTab, "Open Image in New Tab")]
            if c.canPreviewImage { picture.append(item(.openImageInPreview, "Open Image in Preview")) }
            groups.append(picture + [item(.copyImage, "Copy Image"), item(.copyImageAddress, "Copy Image Address")])
        }
        if c.editable {
            groups.append([item(.cut, "Cut", !c.selection.isEmpty), item(.copy, "Copy", !c.selection.isEmpty),
                           item(.paste, "Paste"), item(.selectAll, "Select All")])
        } else if !c.selection.isEmpty {
            groups.append([item(.copy, "Copy"), item(.searchSelection, "Search \(c.searchName) for “\(searchSnippet(c.selection))”")])
        }
        if c.link.isEmpty && c.image.isEmpty && c.selection.isEmpty && !c.editable {
            groups.append([item(.back, "Back", c.canGoBack), item(.forward, "Forward", c.canGoForward), item(.reload, "Reload")])
            groups.append([item(.savePageAs, "Save As…"), item(.print, "Print…")])
            groups.append([item(.viewSource, "View Page Source")])
        }
        groups.append([item(.inspect, "Inspect")])
        return Array(groups.map { $0 }.joined(separator: [Item.separator]))
    }

    /// The selection as Chrome quotes it in its search row: one line, at most 32 characters.
    public static func searchSnippet(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return line.count <= 32 ? line : String(line.prefix(31)) + "…"
    }

    /// What `recorderScript` kept of the page's last right-click.
    public struct Record: Equatable, Sendable, Decodable {
        public var link: String
        public var image: String
        public var selection: String
        public var editable: Bool
        public var x: Double
        public var y: Double
        public var prevented: Bool
        public var settled: Bool
        public var at: Double
    }

    /// The page's last right-click, from `snapshotScript`'s answer: nil when there is none from the last `within`
    /// milliseconds (the click landed in another site's frame, which the main frame's script doesn't see).
    public static func record(snapshot json: String, within: Double = 1500) -> Record? {
        struct Snapshot: Decodable { let rec: Record?; let now: Double }
        guard let data = json.data(using: .utf8), let s = try? JSONDecoder().decode(Snapshot.self, from: data),
              let rec = s.rec, s.now - rec.at <= within, s.now >= rec.at else { return nil }
        return rec
    }

    /// Run in the page's isolated world once Chromium has dispatched the right-click: the record and the page's clock.
    /// The selection is read again: Chromium selects the right-clicked word (a Mac's way) after the event.
    public static let snapshotScript = #"""
    (() => {
      const rec = window.__paneMenu || null;
      if (rec) {
        const a = document.activeElement;
        const inField = a && typeof a.selectionStart === 'number' && a.selectionStart !== a.selectionEnd;
        const now = inField ? String(a.value).slice(a.selectionStart, a.selectionEnd) : String(getSelection ? getSelection() : '');
        if (now) rec.selection = now.slice(0, 2000);
      }
      return JSON.stringify({rec, now: performance.now()});
    })()
    """#

    /// In each document's isolated world from its start (with the engine's start scripts): the target of the page's
    /// last right-click (its link, image, selection, whether it's a field) and, once its dispatch is over, whether the
    /// page took it for a menu of its own (defaultPrevented).
    public static let recorderScript = #"""
    (() => {
      if (window.__paneMenuRecorder) return;
      window.__paneMenuRecorder = true;
      addEventListener('contextmenu', (e) => {
        const path = e.composedPath ? e.composedPath() : [e.target];
        const els = path.filter((n) => n && n.nodeType === 1);
        const link = els.find((n) => n.matches && n.matches('a[href],area[href]'));
        const img = els.find((n) => n.tagName === 'IMG');
        const el = els[0];
        const field = el && el.matches && el.matches('textarea,select,input:not([type=button]):not([type=submit]):not([type=reset]):not([type=checkbox]):not([type=radio]):not([type=image]):not([type=file])');
        const rec = {
          link: link ? String(link.href) : '',
          image: img ? String(img.currentSrc || img.src || '') : '',
          selection: String((field && typeof el.selectionStart === 'number' ? String(el.value).slice(el.selectionStart, el.selectionEnd) : '')
            || (getSelection ? getSelection() : '')).slice(0, 2000),
          editable: !!(el && (el.isContentEditable || field)),
          x: e.clientX, y: e.clientY, prevented: false, settled: false, at: performance.now()
        };
        window.__paneMenu = rec;
        setTimeout(() => { rec.prevented = e.defaultPrevented; rec.settled = true; }, 0);
      }, true);
    })();
    """#
}
