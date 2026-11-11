import CraCore
import Testing

/// 11 Nov 2026: Settings ▸ Shortcuts' groups, the downloads list's grid, and the default colour of a
/// space with none of its own.
struct ShortcutGroupsAndTintTests {
    @Test func shortcutGroups() {
        #expect(ShortcutGroups.group(id: "settings", section: "app") == "Cra")
        #expect(ShortcutGroups.group(id: "newTab", section: "file") == "File")
        #expect(ShortcutGroups.group(id: "goBack", section: "archive") == "Navigation", "back is navigation, not Archive")
        #expect(ShortcutGroups.group(id: "nextTab", section: "tabs") == "Navigation")
        #expect(ShortcutGroups.group(id: "devTools", section: "view") == "Developer")
        #expect(ShortcutGroups.group(id: "addSplitView", section: "view") == "Split View")
        #expect(ShortcutGroups.group(id: "pinTab", section: "tabs") == "Tabs")
        #expect(ShortcutGroups.group(id: "whatever", section: "none") == "Other")
        for g in ["Navigation", "Developer", "Split View", "Cra", "Other"] { #expect(ShortcutGroups.order.contains(g)) }
    }

    /// Arc's rows (11 Nov 2026): the hover pill's padding the same on every side of the picture.
    @Test func trayRowsShareOneGrid() {
        let L = DownloadsTrayLayout.self
        #expect(L.iconFrame.size == 40, "Arc's 40 pt picture")
        #expect(L.iconFrame.x == L.iconFrame.y && L.iconFrame.x == 6, "6 pt round the picture on every side, not thick sides and a squashed top")
        #expect(L.iconFrame.y * 2 + L.iconFrame.size == L.rowHeight)
        #expect(L.textX == 58, "the name and the age start 12 pt after the picture, on every row")
        #expect(L.ageY - L.nameY == L.nameHeight + L.lineGap)
        #expect(L.nameY + L.nameHeight + L.lineGap + L.ageHeight + L.nameY == L.rowHeight, "the two lines centred")
        #expect(L.rowPitch == 56, "Arc's rows are 56 pt apart")
        #expect(L.listHeight(rows: 3) == 3 * 52 + 2 * 4)
        #expect(L.listHeight(rows: 0) == 0)
        let r1 = L.row(1, width: 300)
        #expect(r1.y == 56 && r1.x == 8 && r1.width == 284, "the pill 8 pt in from both sides")
        #expect(L.bottomGap <= 4, "the last row sits right above the dock: no dead gap to cross")
        #expect(L.fillsSquare(cornerAlphas: [1, 1, 1, 1]))
        #expect(!L.fillsSquare(cornerAlphas: [0, 1, 1, 1]), "an icon's see-through corner: drawn whole, not cropped")
    }

    @Test func unthemedSpacesTakeTheDefaultTint() throws {
        let plain = SpaceColorPresets.newSpaceTheme()
        #expect(plain.colors.isEmpty, "a new space still has nothing on its pad (#170)")
        let painted = plain.paintingUnthemed(with: SpaceColorPresets.defaultTint)
        #expect(painted.colors.first == "#DCF3FC", "Arc's pastel sky blue, not the grey that read as white")
        #expect(painted.opacity == plain.opacity, "see-through as the space is")
        #expect(!painted.isDark)
        let themed = SpaceColorPresets.pastelTheme(index: 0)
        #expect(themed.paintingUnthemed(with: "#FF0000") == themed, "a space with colours keeps them")
        #expect(AppSettings().defaultSpaceTint == "#DCF3FC")
        #expect(SpaceColorPresets.validTint("#e8f4f9") == "#E8F4F9")
        #expect(SpaceColorPresets.validTint("blue") == nil)
        let s = try SettingsBridge.applying("defaultSpaceTint", .string("#e8f4f9"), to: AppSettings())
        #expect(s.defaultSpaceTint == "#E8F4F9")
        #expect(throws: SettingsBridge.Failure.invalid("defaultSpaceTint")) {
            try SettingsBridge.applying("defaultSpaceTint", .string("#12"), to: AppSettings())
        }
    }
}
