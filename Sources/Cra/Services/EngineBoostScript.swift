import CraCEF
import Foundation

/// The Boosts' start script on the Chromium engine, which has no call for it (Pane's CEF bridge has
/// CraCEFRuntime.setBoostScript, 13 Nov 2026).
///
/// - Every new page gets it with the engine's own start scripts (setDocumentStartScript): the engine puts those in
///   as it makes a page, before its first document, which a script sent by the app later can miss.
/// - A page made before the Boosts changed keeps the script it was made with, so it also gets one of its own over
///   its DevTools protocol session, replaced on each later change: it runs after the first in every new document
///   and puts the current boost on, or takes the old one off (`__craBoostRun` replaces what an earlier run put on).
@MainActor
final class EngineBoostScript {
    static let shared = EngineBoostScript()

    /// Pane's CEF bridge installs the script itself; only the engine needs this.
    static var isNeeded: Bool { !CraCEFRuntime.responds(to: #selector(CraCEFRuntime.setBoostScript(_:world:hosts:))) }

    /// The script for the current Boosts, and how many times they changed.
    private var script = ""
    private var generation = 0

    private final class Page {
        weak var browser: CraBrowser?
        /// The Boosts the engine put in when it made the page.
        let madeWith: Int
        var identifier: String?
        var generation: Int
        init(_ browser: CraBrowser, generation: Int) {
            self.browser = browser
            madeWith = generation
            self.generation = generation
        }
    }
    private var pages: [ObjectIdentifier: Page] = [:]

    /// The Boosts changed (AppDelegate.updateBoostScript; none when Boosts are off): pages made from now on get the
    /// new script with the engine's own, and every open page made before gets it on its own.
    func update(boosts: [Boost], mainWorld: String, isolatedWorld: String, world: String) {
        let next = Self.script(boosts)
        guard next != script else { return }
        script = next
        generation += 1
        CraCEFRuntime.setDocumentStartScript(mainWorld, isolatedScript: isolatedWorld + "\n;\n" + script, world: world)
        pages = pages.filter { $0.value.browser.map { !$0.isClosed } ?? false }
        for page in pages.values { install(page) }
    }

    /// A page exists (the engine's first callback for it): it has the script the engine put in as it made it.
    func pageExists(_ browser: CraBrowser) {
        guard Self.isNeeded, type(of: browser) == CraBrowser.self, browser.isCreated, !browser.isClosed,
              !browser.isAgent else { return }
        let key = ObjectIdentifier(browser)
        if let page = pages[key], page.browser === browser { return }
        pages[key] = Page(browser, generation: generation)
    }

    /// The boost runtime (BoostScript) and a run of the boosts for this page's host. It runs on every top document
    /// of a boosted site, and on one an earlier run boosted (`__paneBoostOn`), where it takes that boost off.
    static func script(_ boosts: [Boost]) -> String {
        let table = BoostScript.entries(boosts)
        guard let json = try? JSONEncoder().encode(table), let literal = String(data: json, encoding: .utf8) else { return "" }
        return BoostScript.runtime + "\n" + #"""
        (() => {
          if (window.top !== window) return;
          const host = (location.hostname || '').toLowerCase().replace(/^www\./, '');
          const mine = \#(literal).filter((b) => host && (host === b.host || host.endsWith('.' + b.host)));
          if (!mine.length && !window.__paneBoostOn) return;
          window.__paneBoostOn = mine.length > 0;
          window.__craBoostRun(mine.map((b) => b.css).join('\n'), [...new Set(mine.flatMap((b) => b.zapped))]);
        })();
        """#
    }

    private func install(_ page: Page) {
        guard let browser = page.browser, page.generation != generation else { return }
        let wanted = generation
        page.generation = wanted
        if let old = page.identifier {
            page.identifier = nil
            browser.sendDevToolsMethod("Page.removeScriptToEvaluateOnNewDocument", params: Self.json(["identifier": old])) { _, _ in }
        }
        // Made with these Boosts: the engine's script is the current one.
        guard page.madeWith != wanted else { return }
        let params = Self.json(["source": script, "worldName": PageScript.world, "runImmediately": true])
        browser.sendDevToolsMethod("Page.addScriptToEvaluateOnNewDocument", params: params) { [weak page] result, error in
            let identifier = (result?.data(using: .utf8))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["identifier"] as? String
            DispatchQueue.main.async {
                guard let page, let browser = page.browser else { return }
                if let error { CraLog.note("boost script not installed: \(error)"); return }
                guard let identifier else { return }
                // A newer change went in meanwhile: this one comes out again.
                guard page.generation == wanted else {
                    browser.sendDevToolsMethod("Page.removeScriptToEvaluateOnNewDocument",
                                               params: Self.json(["identifier": identifier])) { _, _ in }
                    return
                }
                page.identifier = identifier
            }
        }
    }

    private static func json(_ object: [String: Any]) -> String {
        (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
