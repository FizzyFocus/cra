import Foundation

/// Bookmarks brought in from elsewhere, as a tree: Netscape's `bookmarks.html` (what every browser
/// exports) and Chromium's own `Bookmarks` file (a profile's bookmark manager, where Chrome's
/// importer puts what it brings in). `BookmarkLibrary.merge` adds them to bookmarks.json.
public indirect enum ImportedBookmark: Equatable, Sendable {
    case folder(title: String, children: [ImportedBookmark], id: String?)
    case bookmark(title: String, url: String, added: Date?, id: String?)

    /// Bookmarks, folders: everything under this node, itself included.
    public var counts: (bookmarks: Int, folders: Int) {
        switch self {
        case .bookmark: return (1, 0)
        case .folder(_, let children, _):
            return children.reduce((0, 1)) { sum, c in let n = c.counts; return (sum.0 + n.bookmarks, sum.1 + n.folders) }
        }
    }
}

// MARK: Netscape bookmarks.html

public enum NetscapeBookmarks {
    /// The file's tree: `<DT><H3>Folder</H3><DL>…</DL>` is a folder, `<DT><A HREF="…">Title</A>` a
    /// bookmark; the page's own `<H1>Bookmarks</H1>` heading is not a folder. Lenient as browsers
    /// write it (no closing `<DT>`, `<p>` anywhere, any case).
    public static func parse(_ html: String) -> [ImportedBookmark] {
        var stack: [(title: String, children: [ImportedBookmark])] = [("", [])]
        // A folder's heading waits for its <DL> to open.
        var pendingFolder: String?
        var i = html.startIndex
        while let lt = html[i...].firstIndex(of: "<") {
            guard let gt = html[lt...].firstIndex(of: ">") else { break }
            let tag = html[html.index(after: lt)..<gt]
            let name = tag.prefix { !$0.isWhitespace && $0 != ">" }.lowercased()
            i = html.index(after: gt)
            switch name {
            case "h3":
                let (text, end) = innerText(of: "h3", in: html, from: i)
                pendingFolder = decode(text).trimmingCharacters(in: .whitespacesAndNewlines)
                i = end
            case "dl":
                stack.append((pendingFolder ?? "", []))
                pendingFolder = nil
            case "/dl":
                guard stack.count > 1 else { continue }
                let done = stack.removeLast()
                // The outermost list is the page's own: its items go to the top.
                if stack.count == 1, done.title.isEmpty {
                    stack[0].children += done.children
                } else {
                    stack[stack.count - 1].children.append(.folder(title: done.title.isEmpty ? "Folder" : done.title,
                                                                   children: done.children, id: nil))
                }
            case "a":
                let attrs = attributes(String(tag))
                let (text, end) = innerText(of: "a", in: html, from: i)
                i = end
                guard let href = attrs["href"].map(decode), !href.isEmpty, !href.lowercased().hasPrefix("javascript:"),
                      !href.lowercased().hasPrefix("place:") else { continue }
                let title = decode(text).trimmingCharacters(in: .whitespacesAndNewlines)
                let added = attrs["add_date"].flatMap(TimeInterval.init).map { Date(timeIntervalSince1970: $0) }
                stack[stack.count - 1].children.append(.bookmark(title: title.isEmpty ? href : title, url: href, added: added, id: nil))
            default:
                continue
            }
        }
        // A file that never closed its lists keeps what it had.
        while stack.count > 1 {
            let done = stack.removeLast()
            if stack.count == 1, done.title.isEmpty { stack[0].children += done.children }
            else { stack[stack.count - 1].children.append(.folder(title: done.title, children: done.children, id: nil)) }
        }
        return stack[0].children
    }

    /// The text up to the element's closing tag, and where the scan goes on.
    private static func innerText(of name: String, in html: String, from i: String.Index) -> (String, String.Index) {
        guard let close = html.range(of: "</\(name)", options: .caseInsensitive, range: i..<html.endIndex) else {
            return ("", i)
        }
        let after = html[close.upperBound...].firstIndex(of: ">").map { html.index(after: $0) } ?? close.upperBound
        // Tags inside the title (rare) are dropped.
        let raw = String(html[i..<close.lowerBound])
        return (raw.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression), after)
    }

    /// `HREF="…" ADD_DATE="…"` and the like, lower-cased names, quotes optional.
    static func attributes(_ tag: String) -> [String: String] {
        var out: [String: String] = [:]
        let pattern = #"([A-Za-z_:-]+)\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return out }
        let ns = tag as NSString
        for m in re.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: m.range(at: 1)).lowercased()
            for g in 3...5 where m.range(at: g).location != NSNotFound {
                out[key] = ns.substring(with: m.range(at: g))
                break
            }
        }
        return out
    }

    /// HTML's entities: the named five and numeric ones.
    static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var rest = Substring(s)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            guard let semi = after.prefix(10).firstIndex(of: ";") else { out += "&"; rest = after; continue }
            let entity = String(after[..<semi])
            let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}"]
            if let v = named[entity.lowercased()] {
                out += v
            } else if entity.hasPrefix("#"), let code = entity.lowercased().hasPrefix("#x")
                        ? UInt32(entity.dropFirst(2), radix: 16) : UInt32(entity.dropFirst()), let u = Unicode.Scalar(code) {
                out.unicodeScalars.append(u)
            } else {
                out += "&" + entity + ";"
            }
            rest = after[after.index(after: semi)...]
        }
        return out + rest
    }
}

// MARK: Chromium's Bookmarks file

public enum ChromiumBookmarks {
    /// A profile's `Bookmarks` JSON: the bookmark bar's contents at the top, Other and Mobile
    /// bookmarks as folders of their own when they hold anything. Each node keeps its GUID, so a
    /// later read brings in only what is new (`BookmarkLibrary.importedIDs`).
    public static func parse(_ data: Data) -> [ImportedBookmark] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let roots = root["roots"] as? [String: Any] else { return [] }
        var out: [ImportedBookmark] = []
        if let bar = roots["bookmark_bar"] as? [String: Any] { out += children(of: bar) }
        for (key, title) in [("other", "Other Bookmarks"), ("synced", "Mobile Bookmarks")] {
            guard let node = roots[key] as? [String: Any] else { continue }
            let kids = children(of: node)
            if !kids.isEmpty { out.append(.folder(title: title, children: kids, id: node["guid"] as? String)) }
        }
        return out
    }

    private static func children(of node: [String: Any]) -> [ImportedBookmark] {
        (node["children"] as? [[String: Any]] ?? []).compactMap(item)
    }

    private static func item(_ n: [String: Any]) -> ImportedBookmark? {
        let id = n["guid"] as? String
        let name = (n["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch n["type"] as? String {
        case "url":
            guard let url = n["url"] as? String, !url.isEmpty else { return nil }
            return .bookmark(title: name.isEmpty ? url : name, url: url, added: date(n["date_added"]), id: id)
        case "folder":
            return .folder(title: name.isEmpty ? "Folder" : name, children: children(of: n), id: id)
        default:
            return nil
        }
    }

    /// Chromium's times: microseconds since 1 January 1601, as a string.
    static func date(_ v: Any?) -> Date? {
        guard let s = v as? String, let us = Double(s), us > 0 else { return nil }
        return Date(timeIntervalSince1970: us / 1_000_000 - 11_644_473_600)
    }
}

// MARK: Merging

extension BookmarkLibrary {
    /// What a merge brought in.
    public struct MergeResult: Equatable, Sendable {
        public var bookmarks = 0
        public var folders = 0
        public init(bookmarks: Int = 0, folders: Int = 0) { (self.bookmarks, self.folders) = (bookmarks, folders) }
    }

    /// Adds `items` under `parent` (nil: the top of the tree). A folder joins the one of the same
    /// name already there; an address already bookmarked anywhere is not added twice. Items with an
    /// id already brought in once (`importedIDs`) are skipped, so what was deleted here stays gone
    /// when the same file is read again.
    @discardableResult
    public mutating func merge(_ items: [ImportedBookmark], into parent: UUID? = nil, now: Date) -> MergeResult {
        var result = MergeResult()
        for item in items {
            switch item {
            case .folder(let title, let children, let id):
                let known = id.map { importedIDs.contains($0) } ?? false
                // Read before and nothing new in it: left as it is here (deleted, renamed, moved).
                if known, !hasNew(children) { continue }
                let had = folders.count
                let f = addFolder(title: title, parentId: parent, now: now)
                if folders.count > had { result.folders += 1 }
                if let id, !known { importedIDs.insert(id) }
                let sub = merge(children, into: f.id, now: now)
                result.bookmarks += sub.bookmarks
                result.folders += sub.folders
            case .bookmark(let title, let url, let added, let id):
                if let id, importedIDs.contains(id) { continue }
                if let id { importedIDs.insert(id) }
                guard !isBookmarked(url) else { continue }
                add(url: url, title: title, folderId: parent, now: added ?? now)
                result.bookmarks += 1
            }
        }
        return result
    }

    /// Something under these nodes not brought in before (or with no id to tell).
    private func hasNew(_ items: [ImportedBookmark]) -> Bool {
        items.contains { item in
            switch item {
            case .bookmark(_, _, _, let id): return id.map { !importedIDs.contains($0) } ?? true
            case .folder(_, let children, let id): return id.map { !importedIDs.contains($0) } ?? true || hasNew(children)
            }
        }
    }
}
