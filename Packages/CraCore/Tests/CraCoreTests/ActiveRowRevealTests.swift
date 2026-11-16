import CraCore
import Testing

/// The sidebar list scrolls a row into view when it becomes active, not when its space comes back
/// (16 Nov 2026: scrolled up past the active tab, a switch to another space and back scrolled the
/// list down to it again).
struct ActiveRowRevealTests {
    /// Runs the steps a list sees, returning whether each one scrolled.
    static func run(_ steps: [(shown: Bool, active: String?, spaceOwn: String?)], first: (shown: Bool, active: String?, spaceOwn: String?))
        -> [Bool] {
        var last = ActiveRowReveal.first(shown: first.shown, active: first.active, spaceOwn: first.spaceOwn)
        return steps.map { s in
            let step = ActiveRowReveal.step(shown: s.shown, active: s.active, spaceOwn: s.spaceOwn, last: last)
            last = step.remember
            return step.reveal
        }
    }

    @Test func switchingAwayAndBackLeavesTheListWhereItWas() {
        // On space A with tab t28 open; away to B (A's list has no active row); back to A.
        let reveals = Self.run([(false, nil, "t28"), (true, "t28", "t28")], first: (true, "t28", "t28"))
        #expect(reveals == [false, false])
    }

    @Test func aSpaceShownForTheFirstTimeDoesntScroll() {
        // The list was made while its space was out of sight (a pager page), then shown.
        let reveals = Self.run([(true, "t5", "t5")], first: (false, nil, "t5"))
        #expect(reveals == [false])
    }

    @Test func aTabPickedInTheSpaceIsBroughtIntoView() {
        let reveals = Self.run([(true, "t3", "t3"), (true, "newTab", "t3"), (true, "t3", "t3")], first: (true, "t28", "t28"))
        #expect(reveals == [true, true, true])
    }

    @Test func aTabOpenedInTheSpaceFromElsewhereIsBroughtIntoView() {
        // From space B, the command bar's Switch to Tab picks t7 in A: A's own tab changes as A shows.
        let reveals = Self.run([(false, nil, "t28"), (true, "t7", "t7")], first: (true, "t28", "t28"))
        #expect(reveals == [false, true])
    }

    @Test func nothingActiveScrollsNothing() {
        let reveals = Self.run([(true, nil, nil), (true, nil, nil)], first: (true, nil, nil))
        #expect(reveals == [false, false])
    }
}
