/// The sidebar's width while a Library drawer is open: Media, Downloads, Easels, Boosts and
/// Archived Tabs. They widen the sidebar to about 400 pt (less in a narrow window, never more than
/// 45 % of it) on the Library's own animation, and leaving gives the width back. The Spaces page
/// keeps its own rule (it widens to fit every space's card), and a tab sidebar already wider than
/// the drawer keeps its width: opening one never narrows the sidebar.
public enum LibraryDrawerWidth {
    public static let target: Double = 400
    public static let windowShare: Double = 0.45

    /// `sidebar`: the tab sidebar's width; `window`: the window's.
    public static func width(sidebar: Double, window: Double) -> Double {
        max(sidebar, min(target, window * windowShare)).rounded()
    }
}
