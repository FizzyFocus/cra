import Foundation

/// The Boost editor's Zap (Arc 1.172.1: "Click things on the page to hide them"). While it's on, the
/// element under the pointer is outlined and a click hides it. Each click is kept at once (13 Nov
/// 2026, the owner's call: zaps were kept only when Zap was turned off, so closing the editor or
/// reloading lost them): Cra polls `takeExpression` while Zap is on and saves what it hands over to
/// the boost, then `stopExpression` hands over the rest.
///
/// A zap's selector is the picker's "this" (BoostPicker.selectorHelpers): the shortest one that
/// matches only that element, from an id or the body at any depth. The one Zap wrote before
/// stopped five levels up and still began with "body > ", so a deeper element's never matched again.
/// What a click hides is marked (`data-cra-zapped`, holding its own display), so a zap taken back
/// in the editor shows it again on that page (BoostScript's runtime); `data-cra-zap-pending` until
/// Cra has taken its selector, so a boost applied meanwhile leaves it hidden.
public enum BoostZap {
    /// Turns Zap on (once per page); run again after a navigation, it puts Zap back.
    public static let script = """
    (()=>{if(window.__craZap)return;
    \(BoostPicker.selectorHelpers)
    const hidden=[];let sent=0,over=null;
    const mark=e=>{if(over)over.style.outline=over.__craOutline||'';over=e;if(e){e.__craOutline=e.style.outline;e.style.outline='2px solid #ff3b30'}};
    const move=ev=>mark(page(ev.target)?null:ev.target);
    const click=ev=>{ev.preventDefault();ev.stopPropagation();const t=ev.target;if(page(t))return;mark(null);
    const s=thisSel(t);if(s&&!hidden.includes(s))hidden.push(s);
    if(!t.hasAttribute('data-cra-zapped'))t.setAttribute('data-cra-zapped',t.style.getPropertyValue('display')+'|'+t.style.getPropertyPriority('display'));
    t.setAttribute('data-cra-zap-pending','');t.style.setProperty('display','none','important')};
    const taken=()=>{for(const e of document.querySelectorAll('[data-cra-zap-pending]'))e.removeAttribute('data-cra-zap-pending')};
    document.addEventListener('mouseover',move,true);document.addEventListener('click',click,true);
    window.__craZap={hidden,take(){const n=hidden.slice(sent);sent=hidden.length;taken();return JSON.stringify(n)},
    stop(){document.removeEventListener('mouseover',move,true);document.removeEventListener('click',click,true);mark(null);
    const n=hidden.slice(sent);sent=hidden.length;taken();delete window.__craZap;return JSON.stringify(n)}}})()
    """

    /// The selectors zapped since the last take, as a JSON array ("[]" for none or no Zap).
    public static let takeExpression = "window.__craZap?window.__craZap.take():'[]'"
    /// Zap off, handing over what wasn't taken yet.
    public static let stopExpression = "window.__craZap?window.__craZap.stop():'[]'"

    /// The selectors in a take's answer: strings only, blanks and repeats dropped.
    public static func selectors(_ json: String) -> [String] {
        guard let list = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Any] else { return [] }
        var out: [String] = []
        for case let s as String in list where !s.trimmingCharacters(in: .whitespaces).isEmpty && !out.contains(s) { out.append(s) }
        return out
    }
}

/// What the page says about a zapped element, for the editor's zap list (13 Nov 2026, the owner's
/// call: a list of selectors didn't say which part of the page each was). BoostScript's
/// `inspect` measures it laid out as it would be if shown again, unseen.
public struct ZapFacts: Codable, Equatable, Sendable {
    public var selector: String
    /// Elements it hides on this page now (0: none here).
    public var count: Int
    public var tag: String?
    public var role: String?
    public var aria: String?
    public var id: String?
    public var classes: String?
    public var heading: String?
    public var text: String?
    public var alt: String?
    public var w: Int?
    public var h: Int?

    public init(selector: String, count: Int, tag: String? = nil, role: String? = nil, aria: String? = nil, id: String? = nil,
                classes: String? = nil, heading: String? = nil, text: String? = nil, alt: String? = nil, w: Int? = nil, h: Int? = nil) {
        self.selector = selector
        self.count = count
        self.tag = tag
        self.role = role
        self.aria = aria
        self.id = id
        self.classes = classes
        self.heading = heading
        self.text = text
        self.alt = alt
        self.w = w
        self.h = h
    }

    /// A name a person knows the element by: its accessibility label; else what its id and classes
    /// call it ("Promo Card", "Cookie Notice"), or its landmark ("Sidebar", "Navigation"); else its
    /// heading or first words, quoted; else its kind ("Image", "Block"). "×3" when it hides three.
    public var label: String {
        let base = Self.name(self)
        return count > 1 ? "\(base) ×\(count)" : base
    }

    /// "1200 × 84", or nil when it takes no room (or isn't on the page).
    public var size: String? {
        guard let w, let h, w > 0, h > 0 else { return nil }
        return "\(w) × \(h)"
    }

    /// The kind and size under the name: "aside · 300 × 250".
    public var detail: String {
        guard count > 0 else { return "Not on this page" }
        return [tag, size].compactMap { $0 }.joined(separator: " · ")
    }

    private static let adjectives: [(String, String)] = [
        ("cookie", "Cookie"), ("consent", "Cookie"), ("gdpr", "Cookie"), ("newsletter", "Newsletter"), ("subscribe", "Newsletter"),
        ("promo", "Promo"), ("promotion", "Promo"), ("sponsor", "Sponsored"), ("sponsored", "Sponsored"), ("ad", "Ad"), ("ads", "Ad"),
        ("advert", "Ad"), ("advertisement", "Ad"), ("header", "Header"), ("masthead", "Header"), ("footer", "Footer"),
        ("sidebar", "Sidebar"), ("aside", "Sidebar"), ("nav", "Nav"), ("navbar", "Nav"), ("navigation", "Nav"), ("menu", "Menu"),
        ("hero", "Hero"), ("social", "Social"), ("share", "Share"), ("comment", "Comments"), ("comments", "Comments"),
        ("related", "Related"), ("recommended", "Recommended"), ("notification", "Notification"), ("alert", "Alert"),
        ("popup", "Popup"), ("modal", "Popup"), ("overlay", "Overlay"), ("chat", "Chat"), ("toolbar", "Toolbar"),
    ]
    private static let nouns: [(String, String)] = [
        ("banner", "Banner"), ("card", "Card"), ("bar", "Bar"), ("box", "Box"), ("panel", "Panel"), ("widget", "Widget"),
        ("list", "List"), ("section", "Section"), ("button", "Button"), ("btn", "Button"), ("link", "Link"), ("links", "Links"),
        ("notice", "Notice"), ("dialog", "Dialog"), ("popup", "Popup"), ("modal", "Popup"), ("form", "Form"), ("feed", "Feed"),
        ("carousel", "Carousel"), ("slider", "Carousel"), ("block", "Block"), ("container", "Block"), ("wrapper", "Block"),
    ]
    private static let landmarks: [String: String] = [
        "header": "Header", "banner": "Header Banner", "nav": "Navigation", "navigation": "Navigation", "aside": "Sidebar",
        "complementary": "Sidebar", "footer": "Footer", "contentinfo": "Footer", "dialog": "Dialog", "alertdialog": "Dialog",
        "form": "Form", "search": "Search", "img": "Image", "picture": "Image", "svg": "Image", "video": "Video", "audio": "Audio",
        "iframe": "Embedded Frame", "button": "Button", "a": "Link", "table": "Table", "ul": "List", "ol": "List",
        "h1": "Heading", "h2": "Heading", "h3": "Heading", "p": "Paragraph", "section": "Section", "article": "Article",
        "main": "Main Content", "span": "Text", "div": "Block", "li": "List Item", "input": "Field",
    ]

    private static func name(_ f: ZapFacts) -> String {
        if let a = clean(f.aria), !a.isEmpty { return clip(a) }
        // What the page's own names call it.
        let words = ((f.id ?? "") + " " + (f.classes ?? "")).lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let adjective = words.lazy.compactMap { w in adjectives.first { $0.0 == w }?.1 }.first
        let noun = words.lazy.compactMap { w in nouns.first { $0.0 == w }?.1 }.first
        switch (adjective, noun) {
        case let (a?, n?) where a != n: return "\(a) \(n)"
        case let (a?, _): return a == "Cookie" ? "Cookie Notice" : a == "Ad" ? "Ad" : a
        case let (nil, n?) where n != "Block": return n
        default: break
        }
        let kind = (f.role.flatMap { landmarks[$0.lowercased()] }) ?? f.tag.flatMap { landmarks[$0.lowercased()] }
        if let kind, !["Block", "Text", "Paragraph", "Section", "List Item", "Heading", "Link", "Button"].contains(kind) {
            if kind == "Image", let alt = clean(f.alt), !alt.isEmpty { return "Image “\(clip(alt, 28))”" }
            return kind
        }
        if let h = clean(f.heading), !h.isEmpty { return "“\(clip(h))”" }
        if let t = clean(f.text), !t.isEmpty { return (kind.map { $0 + " " } ?? "") + "“\(clip(t, 26))”" }
        return kind ?? f.tag?.uppercased() ?? "Element"
    }

    private static func clean(_ s: String?) -> String? {
        s?.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func clip(_ s: String, _ n: Int = 32) -> String { s.count <= n ? s : String(s.prefix(n - 1)) + "…" }
}
