import CraCore
import Foundation
import Testing

/// Arc's Tidy Tabs with the Mac's own model: what the sidebar makes of the model's answer.
struct TidyTabsTests {
    /// The owner's rule (12 Nov 2026): Tidy is on the divider whenever Today holds more than 10 tabs,
    /// with fewer while Shift is held; and (14 Nov) outright only with two loose tabs to group.
    @Test func shownAboveTenTodayTabsOrWithShift() {
        func v(_ today: Int, loose: Int, offered: Int? = nil, groups: Int = 0, after: Bool = false) -> TidyTabs.Visibility {
            TidyTabs.visibility(todayTabs: today, looseTabs: loose, offeredTabs: offered ?? loose, offeredGroups: groups, leftoversOnly: after)
        }
        #expect(v(11, loose: 3) == .shown)
        #expect(v(10, loose: 10) == .withShift, "ten is not more than ten")
        #expect(v(2, loose: 2) == .withShift)
        // Grouped tabs count towards the ten; outright only with two loose tabs to group.
        #expect(v(14, loose: 2) == .shown)
        #expect(v(14, loose: 1) == .hidden, "one loose tab and no section to put it in: nothing a run could do")
        #expect(v(1, loose: 1) == .hidden, "one tab alone: not even with Shift")
        #expect(TidyTabs.shows(.shown, shiftHeld: false) && TidyTabs.shows(.shown, shiftHeld: true))
        #expect(!TidyTabs.shows(.withShift, shiftHeld: false) && TidyTabs.shows(.withShift, shiftHeld: true))
        #expect(!TidyTabs.shows(.hidden, shiftHeld: true))
    }

    /// Pane, 14 Nov 2026: right after a run Tidy is off the divider (Shift brings it), however many tabs
    /// the run left loose; and with every tab in Tidy's sections, Shift still brings it to tidy them again.
    @Test func aRunTakesTidyOffTheDividerAndShiftStillReachesIt() {
        // Fourteen Today tabs, twelve loose after a run that grouped two: Shift only, until a new tab comes.
        #expect(TidyTabs.visibility(todayTabs: 14, looseTabs: 12, offeredTabs: 14, offeredGroups: 1, leftoversOnly: true) == .withShift)
        #expect(TidyTabs.visibility(todayTabs: 15, looseTabs: 13, offeredTabs: 15, offeredGroups: 1, leftoversOnly: false) == .shown)
        // Every tab in Tidy's (Full) sections: nothing loose, all of them offered again.
        #expect(TidyTabs.visibility(todayTabs: 6, looseTabs: 0, offeredTabs: 6, offeredGroups: 3, leftoversOnly: true) == .withShift)
        // One loose tab and a section it could join.
        #expect(TidyTabs.visibility(todayTabs: 5, looseTabs: 1, offeredTabs: 1, offeredGroups: 1, leftoversOnly: false) == .withShift)
        // Every tab in sections made by hand (Add Only): none offered, nothing a run could do.
        #expect(TidyTabs.visibility(todayTabs: 6, looseTabs: 0, offeredTabs: 0, offeredGroups: 2, leftoversOnly: false) == .hidden)

        #expect(!TidyTabs.onlyLeftovers(["a", "b"], leftAfterRun: nil), "no run yet")
        #expect(TidyTabs.onlyLeftovers(["a"], leftAfterRun: ["a", "b"]), "one closed since: still the run's")
        #expect(!TidyTabs.onlyLeftovers(["a", "c"], leftAfterRun: ["a", "b"]), "a new loose tab")
        #expect(TidyTabs.onlyLeftovers([String](), leftAfterRun: []), "the run left nothing loose")
    }

    /// A collapsed group lists only what holds the open tab, as a closed folder does.
    @Test func aCollapsedGroupKeepsItsOpenTabInSight() {
        let kids = ["a", "split", "c"]
        #expect(TabGroups.listed(children: kids, collapsed: false, holdsOpenTab: { _ in false }) == kids)
        #expect(TabGroups.listed(children: kids, collapsed: true, holdsOpenTab: { _ in false }).isEmpty)
        #expect(TabGroups.listed(children: kids, collapsed: true, holdsOpenTab: { $0 == "split" }) == ["split"])
    }

    /// A section made by hand goes where its first pick is: in a loose tab's place, after a section holding it.
    @Test func aNewSectionGoesWhereItsFirstPickIs() {
        let today = ["t1", "S1", "t2", "t3"]
        let inS1: Set<String> = ["s1a", "s1b"]
        let top = { (p: String) -> String? in inS1.contains(p) ? "S1" : (today.contains(p) ? p : nil) }
        #expect(TabGroups.newSectionIndex(picked: ["t2", "t3"], today: today, topLevel: top) == 2)
        #expect(TabGroups.newSectionIndex(picked: ["s1b", "t3"], today: today, topLevel: top) == 2, "after the section holding the first pick")
        #expect(TabGroups.newSectionIndex(picked: ["pinned"], today: today, topLevel: top) == nil)
        #expect(TabGroups.noun == "Section")
    }

    /// Move Up / Move Down swap a group with the next group that way; loose tabs keep their places.
    @Test func groupsMovePastTheNextGroupOnly() {
        let today = ["t1", "G1", "t2", "G2", "G3"]
        let isGroup = { (id: String) in id.hasPrefix("G") }
        #expect(TabGroups.moving("G2", .up, in: today, isGroup: isGroup) == ["t1", "G2", "t2", "G1", "G3"])
        #expect(TabGroups.moving("G2", .down, in: today, isGroup: isGroup) == ["t1", "G1", "t2", "G3", "G2"])
        #expect(TabGroups.moving("G1", .up, in: today, isGroup: isGroup) == nil)
        #expect(TabGroups.moving("G3", .down, in: today, isGroup: isGroup) == nil)
        #expect(TabGroups.moving("t1", .down, in: today, isGroup: isGroup) == nil, "a loose tab isn't a group")
    }

    @Test func promptListsTabsWithIdsAndExistingGroups() {
        let p = TidyTabs.prompt(tabs: [.init(title: "Mars - Wikipedia", host: "en.wikipedia.org"),
                                       .init(title: "", host: "example.com"),
                                       .init(title: "Line one\nline two", host: "")],
                                existingGroups: ["Bread"])
        #expect(p == """
        Here are my tabs, as 'id: title (site)':
        0: Mars - Wikipedia (en.wikipedia.org)
        1: example.com (example.com)
        2: Line one line two

        I already have these groups; reuse a name exactly to add tabs to it: "Bread".
        """)
    }

    @Test func promptCutsLongTitlesAndTabLists() {
        let tabs = Array(repeating: TidyTabs.Tab(title: String(repeating: "x", count: 200), host: "h"), count: 100)
        let lines = TidyTabs.prompt(tabs: tabs, existingGroups: []).split(separator: "\n")
        #expect(lines.count == TidyTabs.maximumTabs + 1)
        #expect(lines[1] == "0: " + String(repeating: "x", count: 79) + "… (h)")
    }

    @Test func planDropsBadIdsDuplicatesAndOneTabGroups() {
        let plan = TidyTabs.plan([.init(name: "Planets", tabs: [6, 0, 3, 99, -1]),
                                  .init(name: "Bread", tabs: [1, 4, 7, 0]),
                                  .init(name: "Email", tabs: [8]),
                                  .init(name: "  ", tabs: [2, 5])],
                                 tabCount: 9, existingGroups: [])
        #expect(plan.newGroups == [.init(name: "Planets", tabs: [0, 3, 6]), .init(name: "Bread", tabs: [1, 4, 7])])
        #expect(plan.joins.isEmpty)
    }

    @Test func planMergesSameNamesAndJoinsExistingGroups() {
        let plan = TidyTabs.plan([.init(name: "Python", tabs: [4]),
                                  .init(name: "bread.", tabs: [0]),
                                  .init(name: "python", tabs: [2]),
                                  .init(name: "Travel", tabs: [3, 1])],
                                 tabCount: 5, existingGroups: ["Planets", "Bread"])
        #expect(plan.joins == [1: [0]])
        // New groups follow their first tab's place.
        #expect(plan.newGroups == [.init(name: "Travel", tabs: [1, 3]), .init(name: "Python", tabs: [2, 4])])
    }

    @Test func planCapsNames() {
        let plan = TidyTabs.plan([.init(name: String(repeating: "n", count: 50), tabs: [0, 1])], tabCount: 2, existingGroups: [])
        #expect(plan.newGroups.first?.name.count == 32)
        #expect(TidyTabs.plan([], tabCount: 3, existingGroups: []).isEmpty)
    }

    @Test func orderKeepsLooseTabsAboveTheGroups() {
        let today = ["t1", "G", "t2", "t3", "t4"]
        let order = TidyTabs.order(today: today, isGroup: { $0.hasPrefix("G") || $0.hasPrefix("N") },
                                   grouped: ["t2", "t4"], newGroups: ["N1", "N2"])
        #expect(order == ["t1", "t3", "G", "N1", "N2"])
    }
}

/// A tab group is a folder with a mark, so a Cra from before groups still reads the file.
struct TabGroupItemTests {
    @Test func groupRoundTripsAndPlainFoldersWriteNoMark() throws {
        let group = SidebarItem.tabGroup("Planets", parent: nil)
        #expect(group.isFolder && group.isTabGroup && group.title == "Planets")
        let data = try JSONEncoder().encode(group)
        #expect(try JSONDecoder().decode(SidebarItem.self, from: data) == group)
        let folder = try JSONEncoder().encode(SidebarItem.folder("F", parent: nil))
        #expect(!String(decoding: folder, as: UTF8.self).contains("tabGroup"))
        #expect(try !JSONDecoder().decode(SidebarItem.self, from: folder).isTabGroup)
    }
}
