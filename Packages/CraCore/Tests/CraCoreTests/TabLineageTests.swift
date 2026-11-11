import Foundation
import Testing
@testable import CraCore

@Suite struct TabLineageTests {
    private let p = UUID(), a = UUID(), b = UUID(), c = UUID(), x = UUID(), y = UUID()

    @Test func theFirstLinkGoesRightBelowItsTab() {
        #expect(TabLineage.insertionIndex(after: p, in: [x, p, y], lineage: [:]) == 2)
    }

    /// Each next link lines up under the last one from the same tab, not on top of them.
    @Test func linksLineUpInTheOrderTheyOpened() {
        #expect(TabLineage.insertionIndex(after: p, in: [x, p, a, y], lineage: [a: p]) == 3)
        #expect(TabLineage.insertionIndex(after: p, in: [x, p, a, b, y], lineage: [a: p, b: p]) == 4)
    }

    /// A link opened from a child stays inside its parent's run, which goes on after it.
    @Test func grandchildrenStayInTheRun() {
        #expect(TabLineage.insertionIndex(after: p, in: [p, a, c, y], lineage: [a: p, c: a]) == 3)
        #expect(TabLineage.insertionIndex(after: a, in: [p, a, c, y], lineage: [a: p, c: a]) == 3)
    }

    /// A tab dragged away left the line (no entry): the run stops before it.
    @Test func aMovedTabBreaksTheRun() {
        #expect(TabLineage.insertionIndex(after: p, in: [p, a, b], lineage: [b: p]) == 1)
        #expect(TabLineage.insertionIndex(after: p, in: [x], lineage: [:]) == nil)
    }
}
