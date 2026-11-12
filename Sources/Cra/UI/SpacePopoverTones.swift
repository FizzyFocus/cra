import AppKit

/// A popover over the page in the colours of the window's space (Translate, Blocked pop-ups): AppKit's
/// own NSPopover, its frosted material and arrow left as they are (no fill of its own, like the Site
/// Control Center and the bookmark card), light or dark as the space is, with the text, badge and
/// buttons in the space's dialog tones (CraCore DialogTones, as DialogTheme gives the dialogs): a light
/// space's dark ink and saturated hue, a dark space's light ink and its own dark tone.
@MainActor
struct SpacePopoverTones {
    let tones: DialogTones

    /// The tones of the space shown in `window` (Arc's navy without one, as a dialog's).
    init(window: NSWindow?) { tones = DialogTheme.resolve?(window) ?? .arc }

    var dark: Bool { tones.dark }
    /// The popover's appearance: its material light or dark with the space, not with macOS.
    var appearance: NSAppearance? { NSAppearance(named: dark ? .darkAqua : .aqua) }

    static func color(_ t: DialogTones.Tone) -> NSColor {
        NSColor(hex: t.hex).withAlphaComponent(CGFloat(t.alpha))
    }

    var title: NSColor { Self.color(tones.title) }
    var body: NSColor { Self.color(tones.body) }
    var muted: NSColor { Self.color(tones.muted) }
    /// A round badge behind a glyph (Translate's text-format badge).
    var badge: NSColor { Self.color(tones.fieldFill) }
    var divider: NSColor { Self.color(tones.fieldStroke) }
    /// The plain button (Options, Always Allow): the dialogs' secondary button.
    var secondaryFill: NSColor { Self.color(tones.secondaryFill) }
    var secondaryText: NSColor { Self.color(tones.secondaryText) }
    /// The prominent button (Translate, Open All): the dialogs' primary one, the space's own hue.
    var primaryFill: NSColor { Self.color(tones.primaryFill) }
    var primaryStroke: NSColor { Self.color(tones.primaryStroke) }
    /// White on a light space's saturated fill, the light ink on a dark space's, as DialogButton.
    var primaryText: NSColor { dark ? Self.color(tones.secondaryText) : .white }

    /// `fill` under the pointer or pressed: DialogButton's 10 % tint (white over a dark space's plain
    /// button, black otherwise), 6 % for hover.
    func fill(_ base: NSColor, prominent: Bool, hovering: Bool, pressed: Bool) -> NSColor {
        let tint: NSColor = dark && !prominent ? .white : .black
        let amount: CGFloat = pressed ? 0.1 : hovering ? 0.06 : 0
        return amount == 0 ? base : (base.blended(withFraction: amount, of: tint) ?? base)
    }
}
