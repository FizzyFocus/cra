import CraCore
import Testing

/// SwiftUI's spring(response: 0.25, dampingFraction: 0.8), stepped for AppKit views.
struct SpringMotionTests {
    let spring = SpringMotion.disclosure

    @Test func matchesSwiftUIsParameters() {
        // Core Animation's mass-1 spring for the same response and damping fraction.
        #expect(abs(spring.stiffness - 631.65) < 0.01)
        #expect(abs(spring.damping - 40.21) < 0.01)
    }

    @Test func startsWhereItWasAndLands() {
        #expect(spring.offset(at: 0) == 1)
        #expect(spring.offset(at: -1) == 1)
        #expect(abs(spring.offset(at: spring.settlingDuration)) < 0.002)
        #expect(spring.settlingDuration > 0.3 && spring.settlingDuration < 0.4, "settles in about a third of a second")
    }

    @Test func mostOfTheWayInAQuarterSecondWithASmallOvershoot() {
        #expect(spring.offset(at: 0.125) < 0.3)
        let lowest = stride(from: 0.0, through: 0.5, by: 0.001).map(spring.offset(at:)).min()!
        #expect(lowest < 0 && lowest > -0.03, "under-damped: just past the target, ~1.5 %")
    }

    @Test func criticallyDampedNeverOvershoots() {
        let s = SpringMotion(response: 0.4, dampingFraction: 1)
        #expect(stride(from: 0.0, through: 1, by: 0.005).allSatisfy { s.offset(at: $0) >= 0 })
    }
}
