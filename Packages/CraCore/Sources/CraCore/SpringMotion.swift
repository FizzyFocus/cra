import Foundation

/// SwiftUI's `.spring(response:dampingFraction:)` for views drawn in AppKit: the same mass-spring
/// (mass 1), stepped by the caller one display frame at a time. `offset(at:)` is how far from its
/// target the value still is, as a share of where it started: 1 at the start, then 0, past it a
/// little when the spring is under-damped.
public struct SpringMotion: Equatable, Sendable {
    public let response: Double
    public let dampingFraction: Double

    public init(response: Double, dampingFraction: Double) {
        self.response = response
        self.dampingFraction = dampingFraction
    }

    /// The disclosure chevrons' turn and the folders' accordion: `.spring(response: 0.25, dampingFraction: 0.8)`.
    public static let disclosure = SpringMotion(response: 0.25, dampingFraction: 0.8)
    /// A popover growing out of what opened it (the theme picker): a quick scale with a little give.
    public static let popover = SpringMotion(response: 0.32, dampingFraction: 0.72)
    /// The theme picker going away: the way it came, on a quick spring that doesn't overshoot, so
    /// it shrinks back into its arrow and is gone in about a fifth of a second.
    public static let popoverOut = SpringMotion(response: 0.2, dampingFraction: 1)

    /// Undamped angular frequency, 2π / response.
    public var omega: Double { 2 * .pi / response }
    /// Core Animation's CASpringAnimation stiffness for mass 1.
    public var stiffness: Double { omega * omega }
    /// Core Animation's CASpringAnimation damping for mass 1.
    public var damping: Double { 2 * dampingFraction * omega }

    /// The share of the distance still to go after `t` seconds.
    public func offset(at t: Double) -> Double {
        guard t > 0 else { return 1 }
        let w = omega, z = dampingFraction
        if z >= 1 { return (1 + w * t) * exp(-w * t) }
        let wd = w * (1 - z * z).squareRoot()
        return exp(-z * w * t) * (cos(wd * t) + z * w / wd * sin(wd * t))
    }

    /// When the motion is within 0.1 % of its target for good.
    public var settlingDuration: Double { log(1000) / (min(1, dampingFraction) * omega) }
}
