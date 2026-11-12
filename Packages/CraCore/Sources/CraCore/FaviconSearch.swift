import Foundation

/// How Cra finds a page's icon: one candidate at a time until one decodes. Chromium's own list
/// holds only what the page declares (or /favicon.ico when it declares nothing), and Cra used to
/// try its first entry once. A single-page app whose `<link rel=icon>` names a file its server
/// answers with index.html (my.eskiz.uz, Nov 2026) then stayed on the globe for good.
///
/// 1. Chromium's list (OnFaviconURLChange), bitmaps before SVG, through Chromium's image download:
///    the renderer decodes it and sends no cookies, as Chromium's favicon driver does.
/// 2. The same icons again through the tab's own request context, with its cookies, decoded by
///    the app (which reads SVG): the SVGs first, then /favicon.ico at the page's origin, then the
///    bitmaps (an icon behind the site's login).
/// 3. When the page has loaded and none decoded: the icons its DOM declares (`rel~=icon`, then
///    apple-touch-icon, resolved against document.baseURI), the same two ways. A page whose list
///    never came starts here.
///
/// An attempt answered after a newer search began is dropped (`round`).
public struct FaviconSearch: Equatable, Sendable {
    public enum Fetch: String, Equatable, Hashable, Sendable {
        /// Chromium's image download in the page (CefBrowserHost::DownloadImage).
        case renderer
        /// A GET in the tab's request context (its cookies); the app decodes the bytes.
        case session
    }

    public struct Attempt: Equatable, Hashable, Sendable {
        public let url: String
        public let fetch: Fetch
        /// The search it belongs to.
        public let round: Int

        public init(url: String, fetch: Fetch, round: Int) {
            self.url = url
            self.fetch = fetch
            self.round = round
        }
    }

    /// A `<link>` the load-end probe found in the page.
    public struct PageIcon: Equatable, Decodable, Sendable {
        /// Resolved against document.baseURI.
        public let href: String
        public let rel: String

        public init(href: String, rel: String) {
            self.href = href
            self.rel = rel
        }
    }

    /// Candidates taken from one list: a page that declares hundreds doesn't cost hundreds of requests.
    public static let maxCandidates = 8

    /// The page the search is for.
    public private(set) var pageURL = ""
    /// The icon on show came from here; nil until one decodes for this site.
    public private(set) var found: String?
    /// The attempt in flight.
    public private(set) var current: Attempt?
    public private(set) var round = 0
    private var queue: [Attempt] = []
    private var tried: Set<String> = []
    /// Chromium's last list for this site.
    private var listed: [String]?
    /// What the site's loaded page declared, kept for a list Chromium sends after the load ended.
    private var pageIcons: [String] = []

    public init() {}

    /// Chromium's list changed. Starts over unless it's the list already searched for this site and
    /// that search is settled (an icon decoded, or every candidate failed). One still waiting runs
    /// again: Chromium drops a download without answering when the page replaces its frame while
    /// loading (YouTube), and the next change is what retries it.
    public mutating func iconsChanged(_ urls: [String], pageURL: String) -> Attempt? {
        let list = Self.usable(urls)
        guard !list.isEmpty else { return nil }
        if list == listed, Self.site(pageURL) == Self.site(self.pageURL), found != nil || (current == nil && queue.isEmpty) {
            self.pageURL = pageURL
            return nil
        }
        restart(pageURL: pageURL)
        listed = list
        queue = plan(list) + plan(pageIcons)
        return advance()
    }

    /// The page finished loading; `declared` is what its DOM lists. Nil when an icon decoded for
    /// this site, or while a search runs (its new candidates queue up behind it).
    public mutating func pageLoaded(declared: [PageIcon], pageURL: String) -> Attempt? {
        guard Self.isWeb(pageURL) else { return nil }
        if Self.site(pageURL) != Self.site(self.pageURL) { restart(pageURL: pageURL) }
        self.pageURL = pageURL
        guard found == nil else { return nil }
        let touch: Set<String> = ["apple-touch-icon", "apple-touch-icon-precomposed"]
        let icons = declared.filter { Self.rels($0.rel).contains("icon") }
            + declared.filter { !touch.isDisjoint(with: Self.rels($0.rel)) }
        pageIcons = Self.usable(icons.map(\.href))
        let queued = Set(queue.map(Self.key))
        queue += plan(pageIcons).filter { !queued.contains(Self.key($0)) }
        return current == nil ? advance() : nil
    }

    /// The attempt in flight came back; `decoded` when it gave an image. Returns the next attempt.
    /// Answers from an older search, or twice, change nothing.
    public mutating func finished(_ attempt: Attempt, decoded: Bool) -> Attempt? {
        guard attempt == current else { return nil }
        current = nil
        if decoded {
            found = attempt.url
            queue = []
            return nil
        }
        return advance()
    }

    /// Whether a session fetch's answer can be an icon: a success that isn't an HTML page (the
    /// index.html a single-page app sends for any path).
    public static func accepts(status: Int, mimeType: String) -> Bool {
        (200..<300).contains(status) && !mimeType.lowercased().hasPrefix("text/html")
    }

    /// The load-end probe's answer: `[{"href": …, "rel": …}]`.
    public static func pageIcons(json: String) -> [PageIcon] {
        (try? JSONDecoder().decode([PageIcon].self, from: Data(json.utf8))) ?? []
    }

    /// Whether the icon at `url` is an SVG (by its path, or a data: URL's type).
    public static func isSVG(_ url: String) -> Bool {
        let lower = url.lowercased()
        if lower.hasPrefix("data:") { return lower.hasPrefix("data:image/svg") }
        return URL(string: url)?.path.lowercased().hasSuffix(".svg") == true
    }

    /// /favicon.ico at the origin of `pageURL`, for a web page.
    public static func defaultIcon(of pageURL: String) -> String? {
        guard isWeb(pageURL), let url = URL(string: pageURL), var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        c.path = "/favicon.ico"
        c.query = nil
        c.fragment = nil
        c.user = nil
        c.password = nil
        return c.string
    }

    // MARK: -

    private mutating func restart(pageURL: String) {
        if Self.site(pageURL) != Self.site(self.pageURL) { pageIcons = [] }
        round += 1
        self.pageURL = pageURL
        found = nil
        current = nil
        queue = []
        tried = []
        listed = nil
    }

    /// Chromium's download first (bitmaps, then SVGs), then the session: the SVGs, /favicon.ico,
    /// the bitmaps on the web. A data: bitmap reads the same either way, so it gets no second try.
    private func plan(_ urls: [String]) -> [Attempt] {
        let bitmaps = urls.filter { !Self.isSVG($0) }, svgs = urls.filter(Self.isSVG)
        let session = svgs + (Self.defaultIcon(of: pageURL).map { [$0] } ?? []) + bitmaps.filter(Self.isWeb)
        return (bitmaps + svgs).map { Attempt(url: $0, fetch: .renderer, round: round) }
            + session.map { Attempt(url: $0, fetch: .session, round: round) }
    }

    private mutating func advance() -> Attempt? {
        while !queue.isEmpty {
            let next = queue.removeFirst()
            guard tried.insert(Self.key(next)).inserted else { continue }
            current = next
            return next
        }
        current = nil
        return nil
    }

    private static func key(_ a: Attempt) -> String { a.fetch.rawValue + " " + a.url }

    private static func usable(_ urls: [String]) -> [String] {
        var seen = Set<String>()
        return Array(urls.filter { u in
            let scheme = URL(string: u)?.scheme?.lowercased() ?? ""
            return ["http", "https", "data"].contains(scheme) && seen.insert(u).inserted
        }.prefix(maxCandidates))
    }

    private static func isWeb(_ url: String) -> Bool {
        ["http", "https"].contains(URL(string: url)?.scheme?.lowercased() ?? "")
    }

    /// /favicon.ico is per origin: a site is its scheme, host and port.
    private static func site(_ url: String) -> String? { defaultIcon(of: url) }

    private static func rels(_ rel: String) -> [String] { rel.lowercased().split(whereSeparator: \.isWhitespace).map(String.init) }
}
