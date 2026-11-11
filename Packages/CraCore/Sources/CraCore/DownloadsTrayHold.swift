import Foundation

/// When the downloads tray over the Library button is out (11 Nov 2026). Hovering the button or the
/// tray opens it, as in Arc. A preview opened from one of its rows keeps it out behind the preview,
/// so the preview closes back into the row it grew from; once the preview closes, the tray stays
/// `grace` seconds for the pointer to come back to it before it goes.
public enum DownloadsTrayHold {
    public static let grace: TimeInterval = 3

    public static func isOpen(hovered: Bool, previewOpen: Bool, graceUntil: Date?, now: Date, hasRows: Bool) -> Bool {
        guard hasRows else { return false }
        return hovered || previewOpen || (graceUntil.map { now < $0 } ?? false)
    }
}
