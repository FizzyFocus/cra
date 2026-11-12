/// Settings ▸ Shortcuts' groups (11 Nov 2026): the menus' sections, with what moves around the
/// browser (back, forward, the next tab or space) under Navigation, the page tools under Developer
/// and split view's commands under Split View, wherever their menu puts them.
public enum ShortcutGroups {
    /// The groups in the order the page shows them.
    public static let order = ["Pane", "File", "Edit", "View", "Navigation", "Tabs", "Split View", "Spaces", "Archive",
                               "Window", "Developer", "Help", "Other"]

    static let navigation: Set<String> = ["goBack", "goForward", "reload", "stop", "nextTab", "previousTab", "recentTab",
                                          "recentTabBackward", "revealTab", "nextSpace", "previousSpace", "nextSplitPane",
                                          "previousSplitPane"]
    static let developer: Set<String> = ["devTools", "inspectElement", "jsConsole", "viewSource", "toggleDeveloperMode",
                                         "clearCache", "clearCookies", "hardReload", "taskManager", "allowAppleEventsJavaScript"]
    static let split: Set<String> = ["addSplitView", "closeSplitPane", "flipSplitOrientation", "separateFromSplit", "expandSplitPane"]
    static let sections = ["app": "Pane", "file": "File", "edit": "Edit", "view": "View", "tabs": "Tabs", "spaces": "Spaces",
                           "archive": "Archive", "window": "Window", "help": "Help"]

    /// The group of the action `id`, from its menu section (MenuSection's raw value).
    public static func group(id: String, section: String) -> String {
        if navigation.contains(id) { return "Navigation" }
        if developer.contains(id) { return "Developer" }
        if split.contains(id) { return "Split View" }
        return sections[section] ?? "Other"
    }
}

/// The downloads list over the bottom of the sidebar (DownloadsTrayView), laid out as Arc's
/// (11 Nov 2026): rows 56 pt apart, each a 52 pt rounded hover pill 8 pt in from the list's sides
/// (10 pt corners), the picture a 40 pt square with the same 6 pt round it on every side, the name
/// and the age over each other 12 pt after it, centred in the row the same way whatever the
/// picture is. y runs down.
public enum DownloadsTrayLayout {
    public static let rowHeight: Double = 52
    public static let rowGap: Double = 4
    public static var rowPitch: Double { rowHeight + rowGap }
    /// The rows' inset from the list's sides.
    public static let rowInset: Double = 8
    public static let corner: Double = 10
    public static let icon: Double = 40
    /// The picture's inset from the pill's left edge: the pill's own top and bottom padding.
    public static var iconLeading: Double { (rowHeight - icon) / 2 }
    public static let textGap: Double = 12
    /// Between the last row and the bottom of the list's area: the rows sit just above the dock.
    public static let bottomGap: Double = 2

    /// Opening: each row glides up this far into place on a spring, bottom row first, `stagger` apart;
    /// closing it settles back down the same way, faster, as it fades.
    public static let glide: Double = 10
    public static let stagger: Double = 0.025
    /// The opening spring (mass 1): a quick glide that settles without a visible bounce.
    public static let springStiffness: Double = 320
    public static let springDamping: Double = 26
    public static let closeDuration: Double = 0.16
    public static let nameHeight: Double = 17
    public static let ageHeight: Double = 15
    /// Between the name's box and the age's.
    public static let lineGap: Double = 1

    /// The list's height with `rows` rows (none: no list).
    public static func listHeight(rows: Int) -> Double { rows == 0 ? 0 : Double(rows) * rowPitch - rowGap }

    /// Where the open list takes clicks, in its own coordinates (y down from its top, rows from
    /// `top`): the rows and the gaps between and beside them, one surface, so a click between two
    /// rows does nothing instead of reaching the tab under it (11 Nov 2026). Below the last row
    /// the list's view reaches over the Library button: that strip lets clicks through.
    public static func clickArea(rows: Int, width: Double, top: Double = 2) -> (x: Double, y: Double, width: Double, height: Double)? {
        guard rows > 0, width > 0 else { return nil }
        return (0, 0, width, top + listHeight(rows: rows) + bottomGap)
    }

    /// Row `i` from the top of a list `width` wide.
    public static func row(_ i: Int, width: Double) -> (x: Double, y: Double, width: Double, height: Double) {
        (rowInset, Double(i) * rowPitch, max(0, width - 2 * rowInset), rowHeight)
    }

    /// Inside a row: the icon's square, and where the name and the age start and how high they sit.
    public static var iconFrame: (x: Double, y: Double, size: Double) { (iconLeading, (rowHeight - icon) / 2, icon) }
    public static var textX: Double { iconLeading + icon + textGap }
    public static var nameY: Double { (rowHeight - (nameHeight + lineGap + ageHeight)) / 2 }
    public static var ageY: Double { nameY + nameHeight + lineGap }

    /// A file's picture is drawn whole inside the square when it is an icon (see-through corners,
    /// like a Word or ZIP icon), and fills the square with rounded corners when it is a preview.
    /// `cornerAlphas`: the picture's four corner pixels' alpha, 0…1.
    public static func fillsSquare(cornerAlphas: [Double]) -> Bool {
        !cornerAlphas.isEmpty && cornerAlphas.allSatisfy { $0 > 0.5 }
    }
}
