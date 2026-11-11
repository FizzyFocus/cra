import AppKit
import ObjectiveC

/// Chromium's page and DevTools windows use a frame view derived from NSThemeFrame, so
/// macOS clips them to its window corner radius (about 18 pt on macOS 26, 16 pt on 27) even
/// when they are borderless. Docked inside Cra's card they must be square; the card's own
/// rounded corners (CraMetrics.contentCornerRadius) come from the content layer's mask. This
/// overrides the frame view's corner queries for windows registered here only; every other
/// window keeps the system behaviour.
@MainActor
enum ChromiumWindowCorners {
    private static let squared = NSHashTable<NSWindow>.weakObjects()
    private static var patchedClasses = Set<ObjectIdentifier>()

    static func setSquare(_ square: Bool, for window: NSWindow) {
        guard let frameView = window.contentView?.superview else { return }
        patch(type(of: frameView))
        let changed = squared.contains(window) != square
        if square { squared.add(window) } else { squared.remove(window) }
        // Also when macOS still rounds a window that is registered square (a style mask Chromium
        // put back): the mask it made then is kept until something asks for a new one.
        guard changed || (square && (effectiveRadius(window) ?? 0) > 0) else { return }
        // macOS 27 (11 Nov 2026) no longer remakes the mask on `_cornerMaskChanged` alone, so
        // the page kept its 16 pt corners: rounder than the card, and with DevTools' background
        // showing in the corners where the page meets it. `_updateWindowCornerMask` (the window)
        // and `windowCornerMaskChanged` (the frame view) ask again.
        for name in ["_cornerMaskChanged", "_updateWindowCornerMask"] {
            let sel = NSSelectorFromString(name)
            if window.responds(to: sel) { window.perform(sel) }
        }
        let frameChanged = NSSelectorFromString("windowCornerMaskChanged")
        if frameView.responds(to: frameChanged) { frameView.perform(frameChanged) }
        frameView.needsDisplay = true
        window.invalidateShadow()
    }

    /// The radius macOS clips `window` to right now (its largest corner), or nil where it doesn't
    /// say (before macOS 26). 0 for a window this squares; read by `cra://debug?windowCorners`.
    static func effectiveRadius(_ window: NSWindow) -> CGFloat? {
        let radiiSel = NSSelectorFromString("_effectiveCornerRadii")
        guard window.responds(to: radiiSel), let radii = window.perform(radiiSel)?.takeUnretainedValue() as? NSObject else { return nil }
        let maxSel = NSSelectorFromString("_maximumCornerRadius")
        guard radii.responds(to: maxSel), let imp = radii.method(for: maxSel) else { return nil }
        typealias DoubleIMP = @convention(c) (AnyObject, Selector) -> Double
        return CGFloat(unsafeBitCast(imp, to: DoubleIMP.self)(radii, maxSel))
    }

    static func isSquareWindow(_ w: NSWindow) -> Bool { squared.contains(w) }

    static func isSquare(_ view: AnyObject) -> Bool {
        guard let v = view as? NSView, let w = v.window else { return false }
        return squared.contains(w)
    }

    private static func patch(_ cls: AnyClass) {
        let id = ObjectIdentifier(cls)
        guard !patchedClasses.contains(id) else { return }
        patchedClasses.insert(id)
        overrideBool(cls, "_shouldRoundCornersForSurface", squareValue: false)
        overrideBool(cls, "topCornerRounded", squareValue: false)
        overrideBool(cls, "bottomCornerRounded", squareValue: false)
        overrideFloat(cls, "_cornerRadius", squareValue: 0)
        overrideFloat(cls, "_getCachedWindowCornerRadius", squareValue: 0)
        overrideFloat(cls, "_getCachedDefaultWindowCornerRadius", squareValue: 0)
        // Linked against a pre-26 SDK (release builds on GitHub's macos-15 runners), macOS 26
        // ignores the queries above and masks the window with a 12 pt corner image of its own,
        // which rounded the page's top corners under the toolbar. No mask means square.
        overrideObject(cls, "_cornerMask", squareValue: nil)
    }

    private typealias BoolIMP = @convention(c) (AnyObject, Selector) -> Bool
    private typealias FloatIMP = @convention(c) (AnyObject, Selector) -> CGFloat
    private typealias ObjectIMP = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?

    private static func overrideBool(_ cls: AnyClass, _ name: String, squareValue: Bool) {
        let sel = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(cls, sel), let types = method_getTypeEncoding(method) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: BoolIMP.self)
        let block: @convention(block) (AnyObject) -> Bool = { obj in
            MainActor.assumeIsolated { isSquare(obj) } ? squareValue : original(obj, sel)
        }
        let imp = imp_implementationWithBlock(block)
        // Add on the subclass when it only inherits the method, else replace its own.
        if !class_addMethod(cls, sel, imp, types) { method_setImplementation(method, imp) }
    }

    private static func overrideFloat(_ cls: AnyClass, _ name: String, squareValue: CGFloat) {
        let sel = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(cls, sel), let types = method_getTypeEncoding(method) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: FloatIMP.self)
        let block: @convention(block) (AnyObject) -> CGFloat = { obj in
            MainActor.assumeIsolated { isSquare(obj) } ? squareValue : original(obj, sel)
        }
        let imp = imp_implementationWithBlock(block)
        if !class_addMethod(cls, sel, imp, types) { method_setImplementation(method, imp) }
    }

    private static func overrideObject(_ cls: AnyClass, _ name: String, squareValue: AnyObject?) {
        let sel = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(cls, sel), let types = method_getTypeEncoding(method) else { return }
        let original = unsafeBitCast(method_getImplementation(method), to: ObjectIMP.self)
        let block: @convention(block) (AnyObject) -> Unmanaged<AnyObject>? = { obj in
            MainActor.assumeIsolated { isSquare(obj) } ? squareValue.map { Unmanaged.passUnretained($0) } : original(obj, sel)
        }
        let imp = imp_implementationWithBlock(block)
        if !class_addMethod(cls, sel, imp, types) { method_setImplementation(method, imp) }
    }
}
