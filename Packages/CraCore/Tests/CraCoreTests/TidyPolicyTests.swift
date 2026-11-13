import Foundation
import Testing
@testable import CraCore

/// Sections' Tidy Tabs Behavior (13 Nov 2026): Full, Add Only, Locked.
struct TidyPolicyTests {
    typealias Section = TidyRun.Section<String>

    // Loose tabs l1 l2 l3; Full section F (f1 f2 f3), Add Only section A (a1), Locked section L (k1 k2).
    let loose = ["l1", "l2", "l3"]
    let sections = [Section(id: "F", policy: .full, tabs: ["f1", "f2", "f3"]),
                    Section(id: "A", policy: .addOnly, tabs: ["a1"]),
                    Section(id: "L", policy: .locked, tabs: ["k1", "k2"])]

    func run(_ proposals: [TidyTabs.Proposal], names: [String: String] = ["F": "Work", "A": "Reading"]) -> TidyRun.Outcome<String> {
        let offer = TidyRun.offer(loose: loose, sections: sections)
        let plan = TidyTabs.plan(proposals, tabCount: offer.tabs.count, existingGroups: offer.groups.map { names[$0] ?? $0 })
        return TidyRun.outcome(plan, tabs: offer.tabs, groups: offer.groups, sections: sections, loose: Set(loose))
    }

    @Test func theModelSeesLooseTabsFullSectionsAndNoLockedOne() {
        let offer = TidyRun.offer(loose: loose, sections: sections)
        #expect(offer.tabs == ["l1", "l2", "l3", "f1", "f2", "f3"], "a Locked or Add Only section's tabs aren't offered")
        #expect(offer.groups == ["F", "A"], "nor is a Locked section's name")
    }

    @Test func addOnlyTakesLooseTabsAndNothingElse() {
        // tabs: 0 l1, 1 l2, 2 l3, 3 f1, 4 f2, 5 f3. "Reading" is A.
        let out = run([TidyTabs.Proposal(name: "Reading", tabs: [0, 3])])
        #expect(out.sections["A"] == ["a1", "l1"], "the loose tab joins; F's tab doesn't")
        #expect(out.sections["F"] == nil && out.removed.isEmpty, "F keeps f1")
        #expect(out.renamed.isEmpty && out.created.isEmpty)
    }

    @Test func fullIsRegroupedRenamedAndRemoved() {
        // A new group of f1, f2 and l1: F's own tabs make up most of it, so F takes the name.
        let renamed = run([TidyTabs.Proposal(name: "Docs", tabs: [3, 4, 0])])
        #expect(renamed.renamed == ["F": "Docs"])
        #expect(renamed.sections["F"] == ["f1", "f2", "f3", "l1"], "f3, left out, stays; l1 comes in")
        #expect(renamed.created.isEmpty)
        // F's tabs split over two new groups: the one holding two of its three takes F's place.
        let split = run([TidyTabs.Proposal(name: "One", tabs: [3, 0, 1]), TidyTabs.Proposal(name: "Two", tabs: [4, 5, 2])])
        #expect(split.renamed.count == 1, "one of them takes F's place: two of F's three tabs are in it")
        #expect(split.removed.isEmpty)
        // F's tabs joined into... nothing else Full; moved to a new section where F is a minority.
        let moved = run([TidyTabs.Proposal(name: "News", tabs: [0, 1, 2, 3])])
        #expect(moved.created.map(\.name) == ["News"] && moved.created.first?.tabs == ["l1", "l2", "l3", "f1"])
        #expect(moved.sections["F"] == ["f2", "f3"], "f1 leaves F for the new section")
    }

    @Test func aFullSectionEmptiedGoes() {
        let sections = [Section(id: "F", policy: .full, tabs: ["f1"]), Section(id: "G", policy: .full, tabs: ["g1", "g2"])]
        let offer = TidyRun.offer(loose: ["l1"], sections: sections)
        // tabs: 0 l1, 1 f1, 2 g1, 3 g2; "Games" is G: f1 and l1 join it.
        let plan = TidyTabs.plan([TidyTabs.Proposal(name: "Games", tabs: [1, 0])], tabCount: offer.tabs.count, existingGroups: ["Fun", "Games"])
        let out = TidyRun.outcome(plan, tabs: offer.tabs, groups: offer.groups, sections: sections, loose: ["l1"])
        #expect(out.removed == ["F"])
        #expect(out.sections["G"] == ["g1", "g2", "l1", "f1"])
    }

    @Test func lockedIsNeverTouched() {
        let out = run([TidyTabs.Proposal(name: "Everything", tabs: [0, 1, 2, 3, 4, 5])])
        #expect(out.sections["L"] == nil && !out.removed.contains("L") && out.renamed["L"] == nil)
    }

    @Test func thePolicyIsSavedOnlyWhenSetAndReadsUnknownAsFull() throws {
        var g = SidebarItem.tabGroup("Mine", parent: nil)
        #expect(g.sectionTidyPolicy == .full)
        let plain = String(decoding: try JSONEncoder().encode(g), as: UTF8.self)
        #expect(!plain.contains("tidyPolicy"))
        g.tidyPolicy = .addOnly
        let back = try JSONDecoder().decode(SidebarItem.self, from: try JSONEncoder().encode(g))
        #expect(back.tidyPolicy == .addOnly)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(g)) as? [String: Any])
        json["tidyPolicy"] = "someday"
        let newer = try JSONDecoder().decode(SidebarItem.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(newer.tidyPolicy == nil && newer.sectionTidyPolicy == .full)
    }
}
