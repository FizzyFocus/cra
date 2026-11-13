/// Library ▸ Archived Tabs (12 Nov 2026, the owner's call): a click on an archived tab, or on its
/// Restore button, brings it back in the background. The Library stays where it is and a toast says
/// so, with Show to switch to it, as for a link opened behind the page. With Shift held the tab comes
/// back and is switched to, leaving the Library, as every click did before.
public enum ArchivedTabRestore {
    /// Whether restoring switches to the tab.
    public static func switchesToTab(shift: Bool) -> Bool { shift }

    /// The toast after a restore in the background (ShinyToast, beside "New Tab Created").
    public static let toast = "Tab Restored"
}
