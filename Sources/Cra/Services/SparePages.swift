import AppKit
import ObjectiveC
import CraCEF

/// One Chromium page per profile made ahead, which the next tab that needs a page takes (SparePage
/// in CraCore): the ~34 ms CEF spends making a page's window then falls between clicks, not on one.
/// Shared by every window's BrowserManager. A spare has no delegate and no tab; its window stays
/// hidden and extensions don't see it (Cra.setSpare) until a tab takes it.
@MainActor
final class SparePages {
    static let shared = SparePages()

    /// CRA_SPARE_PAGES=0 turns spares off (for measuring and for a CEF without Cra.setSpare).
    static let isEnabled = ProcessInfo.processInfo.environment["CRA_SPARE_PAGES"] != "0"

    private var spares: [String: CraBrowser] = [:]
    private var pending: [String: ScheduledWork] = [:]

    /// A spare for `profilePath` that Chromium has finished making, or nil. It is no longer kept.
    func take(profilePath: String?) -> CraBrowser? {
        let key = SparePage.key(profilePath: profilePath)
        guard Self.isEnabled, let b = spares[key] else { return nil }
        guard b.isCreated, !b.isClosed else { return nil }
        spares[key] = nil
        return b
    }

    /// Makes `profilePath`'s next spare `SparePage.refillDelay` from now, unless it has one.
    func refill(profilePath: String?, frame: NSRect, clock: Scheduler) {
        let key = SparePage.key(profilePath: profilePath)
        guard Self.isEnabled, CraCEFRuntime.chromeHosting(), spares[key] == nil, pending[key] == nil else { return }
        pending[key] = clock.after(SparePage.refillDelay) { [weak self] in
            guard let self else { return }
            self.pending[key] = nil
            if let old = self.spares[key], !old.isClosed { return }
            Self.refuseKeyWhileMaking()
            Self.makingSpare = true
            self.spares[key] = CraBrowser(spareWithFrame: frame, profilePath: profilePath)
            Self.makingSpare = false
        }
    }

    /// CEF shows a page's window as it makes it, and Chromium makes the window it shows key
    /// (kShowAndActivateWindow). A spare's window goes out of sight at once, but the window that had
    /// the keyboard had lost it: the URL field's dropdown and the ⌘T bar closed, a toolbar address
    /// edit ended (Pane, 13 Nov 2026; command-bar-dropdown failed whenever a spare was made while the
    /// dropdown was open). While a spare is made, Chromium's windows can't become key.
    private static var makingSpare = false
    private static var keyPatched = false
    private typealias KeyIMP = @convention(c) (NSWindow, Selector) -> Bool

    private static func refuseKeyWhileMaking() {
        guard !keyPatched, let cls = NSClassFromString("NativeWidgetMacNSWindow") else { return }
        keyPatched = true
        let sel = #selector(getter: NSWindow.canBecomeKey)
        guard let method = class_getInstanceMethod(cls, sel), let types = method_getTypeEncoding(method) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: KeyIMP.self)
        let block: @convention(block) (NSWindow) -> Bool = { window in
            MainActor.assumeIsolated { makingSpare } ? false : original(window, sel)
        }
        let imp = imp_implementationWithBlock(block)
        // Chromium's class answers canBecomeKey itself; only if it didn't would this add an override
        // there rather than change NSWindow's.
        if !class_addMethod(cls, sel, imp, types) { method_setImplementation(method, imp) }
    }

    /// Every spare and every pending refill goes (tests start from none).
    func dropAll() {
        for w in pending.values { w.cancel() }
        pending = [:]
        for b in spares.values { b.close() }
        spares = [:]
    }

    /// A profile was deleted: its spare goes too.
    func drop(profilePath: String?) {
        let key = SparePage.key(profilePath: profilePath)
        pending.removeValue(forKey: key)?.cancel()
        spares.removeValue(forKey: key)?.close()
    }
}
