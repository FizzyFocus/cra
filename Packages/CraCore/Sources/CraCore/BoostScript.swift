import Foundation

/// How a boost reaches its pages (13 Nov 2026, the owner's call: a zapped element came back on
/// reload). Every page browser runs `documentStart(_:)` in Cra's isolated world before the page's
/// own scripts. It carries each enabled boost and puts the page's on at once, before anything
/// paints. A commit and every edit in the editor run `apply(css:zapped:)` in the same world. Both go
/// through one small runtime (`window.__craBoostRun`):
/// - the boost's stylesheet is adopted by the document; a page that sets `adoptedStyleSheets`
///   itself (as some frameworks do) gets it back with the next change to its DOM;
/// - each zapped selector is a rule of its own (Boost.stylesheet), so one the page's CSS can't
///   parse doesn't undo the others;
/// - what a zap matches is hidden inline as well, when the document is parsed and as elements
///   come (a MutationObserver), and gets its own display back once no zap matches it, as does what
///   the editor's Zap hid on the page (BoostZap's `data-cra-zapped`).
public enum BoostScript {
    /// The isolated world's runtime. Defined once per document; later runs reuse it.
    public static let runtime = #"""
    (() => {
      if (window.__craBoostRun) return;
      let sheet = null, zaps = [], observer = null;
      const hidden = new Set(), was = new WeakMap();
      const adopt = () => {
        if (!sheet) return;
        try {
          const list = document.adoptedStyleSheets;
          if (!list.includes(sheet)) document.adoptedStyleSheets = [...list, sheet];
        } catch (e) {}
      };
      const hide = (el) => {
        const st = el.style;
        if (!st || (st.getPropertyValue('display') === 'none' && st.getPropertyPriority('display') === 'important')) return;
        if (!was.has(el)) {
          was.set(el, [st.getPropertyValue('display'), st.getPropertyPriority('display')]);
          hidden.add(new WeakRef(el));
        }
        st.setProperty('display', 'none', 'important');
      };
      const sweep = (root) => {
        for (const s of zaps) {
          try {
            if (root.nodeType === 1 && root.matches(s)) hide(root);
            for (const el of root.querySelectorAll(s)) hide(el);
          } catch (e) {}
        }
      };
      const matches = (el) => zaps.some((s) => { try { return el.matches(s); } catch (e) { return false; } });
      const restore = () => {
        for (const ref of [...hidden]) {
          const el = ref.deref();
          if (el && matches(el)) continue;
          hidden.delete(ref);
          if (!el) continue;
          const [v, p] = was.get(el) || ['', ''];
          if (v) el.style.setProperty('display', v, p); else el.style.removeProperty('display');
          was.delete(el);
        }
        // What the editor's Zap hid on this page (BoostZap), once its zap is taken back.
        for (const el of document.querySelectorAll('[data-cra-zapped]:not([data-cra-zap-pending])')) {
          if (matches(el)) continue;
          const [v, p] = (el.getAttribute('data-cra-zapped') || '|').split('|');
          el.removeAttribute('data-cra-zapped');
          if (v) el.style.setProperty('display', v, p || ''); else el.style.removeProperty('display');
        }
      };
      const ready = () => { adopt(); sweep(document); };
      window.__craBoostRun = (css, list) => {
        if (!sheet) sheet = new CSSStyleSheet();
        try { sheet.replaceSync(css || ''); } catch (e) {}
        zaps = (list || []).filter((s) => typeof s === 'string' && s.trim());
        adopt();
        restore();
        if (zaps.length) {
          sweep(document);
          if (!observer) {
            observer = new MutationObserver((records) => {
              adopt();
              for (const r of records) for (const n of r.addedNodes) if (n.nodeType === 1) sweep(n);
            });
            observer.observe(document, { childList: true, subtree: true });
          }
        } else if (observer) {
          observer.disconnect();
          observer = null;
        }
        if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ready, { once: true });
      };
      // The editor's zap list (13 Nov 2026): what each zap hides, measured laid out as it would be
      // shown again, unseen (all in one task, so nothing paints), and a ghost of one in its place.
      const natural = (els, fn) => {
        const keys = ['display', 'visibility'];
        const saved = els.map((el) => [el, keys.map((k) => [k, el.style.getPropertyValue(k), el.style.getPropertyPriority(k)])]);
        const off = !!sheet && !sheet.disabled;
        if (off) sheet.disabled = true;
        for (const [el] of saved) { el.style.removeProperty('display'); el.style.setProperty('visibility', 'hidden', 'important'); }
        try { return fn(); } finally {
          for (const [el, props] of saved) for (const [k, v, p] of props) { if (v) el.style.setProperty(k, v, p); else el.style.removeProperty(k); }
          if (off) sheet.disabled = false;
        }
      };
      const all = (s) => { try { return [...document.querySelectorAll(s)]; } catch (e) { return []; } };
      const clip = (s) => (s || '').replace(/\s+/g, ' ').trim().slice(0, 80);
      window.__craBoostInspect = (list) => {
        const found = list.map((s) => [s, all(s)]);
        return JSON.stringify(natural(found.flatMap(([, els]) => els.slice(0, 1)), () => found.map(([s, els]) => {
          const el = els[0];
          if (!el) return { selector: s, count: 0 };
          const r = el.getBoundingClientRect(), h = el.querySelector('h1,h2,h3,h4,h5,h6');
          return { selector: s, count: els.length, tag: el.tagName.toLowerCase(), role: el.getAttribute('role') || '',
                   aria: clip(el.getAttribute('aria-label')), id: el.id || '', classes: [...el.classList].slice(0, 8).join(' '),
                   heading: clip(h && h.textContent), text: clip(el.textContent), alt: clip(el.getAttribute('alt') || el.getAttribute('title')),
                   w: Math.round(r.width), h: Math.round(r.height) };
        })));
      };
      let ghosts = [], badge = null;
      window.__craBoostGhost = (s) => {
        for (const [el, props] of ghosts) for (const [k, v, p] of props) { if (v) el.style.setProperty(k, v, p); else el.style.removeProperty(k); }
        ghosts = [];
        if (badge) { badge.remove(); badge = null; }
        if (!s) return 0;
        const els = all(s).slice(0, 50);
        if (!els.length) return 0;
        const shows = natural(els, () => els.map((el) => getComputedStyle(el).display));
        const keys = ['display', 'opacity', 'outline', 'outline-offset'];
        els.forEach((el, i) => {
          ghosts.push([el, keys.map((k) => [k, el.style.getPropertyValue(k), el.style.getPropertyPriority(k)])]);
          el.style.setProperty('display', shows[i] === 'none' ? 'block' : shows[i], 'important');
          el.style.setProperty('opacity', '0.45', 'important');
          el.style.setProperty('outline', '2px dashed #ff6a3d', 'important');
          el.style.setProperty('outline-offset', '2px', 'important');
        });
        els[0].scrollIntoView({ block: 'nearest', inline: 'nearest' });
        const r = els[0].getBoundingClientRect();
        badge = document.createElement('div');
        badge.textContent = '↺ Restore';
        badge.style.cssText = 'position:absolute;z-index:2147483647;pointer-events:none;font:600 11px -apple-system,system-ui,sans-serif;'
          + 'color:#fff;background:#ff6a3d;border-radius:6px;padding:2px 7px;box-shadow:0 1px 3px rgba(0,0,0,.25);white-space:nowrap';
        badge.style.left = Math.max(0, r.left + scrollX) + 'px';
        badge.style.top = Math.max(0, r.top + scrollY - 22) + 'px';
        (document.body || document.documentElement).append(badge);
        return els.length;
      };
      window.__craBoostState = () => ({
        adopted: !!sheet && document.adoptedStyleSheets.includes(sheet),
        zaps: zaps.length,
        hidden: [...hidden].filter((r) => r.deref()).length,
      });
    })();
    """#

    /// What a page of a boosted site needs: the stylesheet of every boost on it and their zaps.
    public struct Entry: Codable, Equatable {
        public var host: String
        public var css: String
        public var zapped: [String]

        public init(host: String, css: String, zapped: [String]) {
            self.host = host
            self.css = css
            self.zapped = zapped
        }
    }

    /// The table `documentStart` carries: each enabled boost's host, stylesheet and zaps.
    public static func entries(_ boosts: [Boost]) -> [Entry] {
        boosts.filter(\.enabled).map { Entry(host: $0.host, css: $0.stylesheet, zapped: $0.zapped) }
    }

    /// The script every page runs at its start: the runtime, then the page's boosts (the page's
    /// host, or a subdomain of a boost's), in the top frame only, as a commit applies them. Empty
    /// with no enabled boost (or Boosts off), so no page runs anything.
    public static func documentStart(_ boosts: [Boost]) -> String {
        let table = entries(boosts)
        guard !table.isEmpty, let json = try? JSONEncoder().encode(table), let literal = String(data: json, encoding: .utf8) else { return "" }
        return runtime + "\n" + #"""
        (() => {
          if (window.top !== window) return;
          const host = (location.hostname || '').toLowerCase().replace(/^www\./, '');
          if (!host) return;
          const mine = \#(literal).filter((b) => host === b.host || host.endsWith('.' + b.host));
          if (!mine.length) return;
          window.__craBoostRun(mine.map((b) => b.css).join('\n'), [...new Set(mine.flatMap((b) => b.zapped))]);
        })();
        """#
    }

    /// The facts of each zap on the page, as a JSON array of ZapFacts (in the isolated world).
    public static func inspect(_ zapped: [String]) -> String {
        let args = (try? JSONSerialization.data(withJSONObject: [zapped], options: [])).flatMap { String(data: $0, encoding: .utf8) } ?? "[[]]"
        return runtime + "\n" + "window.__craBoostInspect(...\(args));"
    }

    /// The ghost of what `selector` hides, in its place on the page; nil takes it away.
    public static func ghost(_ selector: String?) -> String {
        let args = (try? JSONSerialization.data(withJSONObject: [selector.map { $0 as Any } ?? NSNull()], options: [])).flatMap { String(data: $0, encoding: .utf8) } ?? "[null]"
        return runtime + "\n" + "window.__craBoostGhost(...\(args));"
    }

    /// The expression a commit or an edit evaluates in the isolated world: the runtime (in case the
    /// document began before the start script was in), then this boost's stylesheet and zaps. An
    /// emptied boost (or none) clears what an earlier one put on.
    public static func apply(css: String, zapped: [String]) -> String {
        let args = (try? JSONSerialization.data(withJSONObject: [css, zapped], options: [])).flatMap { String(data: $0, encoding: .utf8) } ?? #"["",[]]"#
        return runtime + "\n" + "window.__craBoostRun(...\(args));"
    }
}
