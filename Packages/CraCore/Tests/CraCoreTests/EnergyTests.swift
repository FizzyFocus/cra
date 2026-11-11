import CraCore
import Foundation
import Testing

/// "Using Significant Energy" (11 Nov 2026): what keeps waking Cra while nothing happens.
struct EnergyTests {
    @Test func floatingSidebarSamplesOnlyWhenItCanMatter() {
        let P = FloatingSidebarPoll.self
        #expect(P.interval(appActive: true, sidebarDocked: true, shown: false, pointerStillFor: 0) == nil,
                "docked: 30 wake-ups a second for nothing before")
        #expect(P.interval(appActive: false, sidebarDocked: false, shown: false, pointerStillFor: 0) == nil, "in the background")
        #expect(P.interval(appActive: true, sidebarDocked: false, shown: false, pointerStillFor: 0) == P.fast, "hidden: the edge is watched")
        #expect(P.interval(appActive: true, sidebarDocked: true, shown: true, pointerStillFor: 0) == P.fast, "floating out (full screen)")
        #expect(P.interval(appActive: true, sidebarDocked: false, shown: false, pointerStillFor: 3) == P.resting, "a resting pointer: 4 Hz")
        #expect(P.resting >= 0.25 && P.fast <= 1.0 / 30)
    }

    @Test func performanceRecordingIsOffUntilAskedFor() throws {
        #expect(!AppSettings().perfRecording, "off by default: no 5 s samples, no 2 Hz watchdog")
        let empty = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!empty.perfRecording)
        #expect(PerfSessionRules.recording(setting: false, environment: ["CRA_PERF": "1"]), "scenarios still record")
        #expect(!PerfSessionRules.recording(setting: true, environment: ["CRA_PERF": "0"]))
        #expect(PerfSessionRules.recording(setting: true, environment: [:]), "switched on in Settings ▸ Performance")
    }
}
