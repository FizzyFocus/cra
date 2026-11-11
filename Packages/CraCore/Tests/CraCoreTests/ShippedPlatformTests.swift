import CraCore
import Foundation
import Testing

/// What closed issues about privacy, profiles and performance shipped, where no older test
/// pinned it on its own.
struct ShippedPlatformTests {
    /// Settings ▸ Privacy ▸ Secure DNS (#133) lists Automatic, Off, then these providers in this
    /// order, each with the template chrome://settings/security writes for it, then Custom….
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/133"))
    func secureDNSMenuProviders() {
        #expect(SecureDNSProvider.all.map(\.name) == [
            "Google (Public DNS)", "Cloudflare (1.1.1.1)", "Quad9 (9.9.9.9)", "OpenDNS",
            "CleanBrowsing (Family Filter)", "DNS4EU (Protective)",
        ])
        #expect(SecureDNSProvider.all.allSatisfy { SecureDNSPrefs.validTemplates($0.template) == $0.template })
    }

    /// Settings ▸ Performance (#91) records only when asked for since 11 Nov 2026 (the user's
    /// call: recording all day had macOS flag Cra for significant energy), with site names kept
    /// until "Hide site names" is ticked. A file saved with the old on default reads as off, once;
    /// one switched on after that stays on.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/91"))
    func performanceRecordingIsOffUntilAskedFor() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!s.perfRecording && !s.perfHidesSiteNames)
        #expect(!AppSettings().perfRecording && !AppSettings().perfHidesSiteNames)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"perfRecording": true}"#.utf8))
        #expect(!old.perfRecording, "the old default, saved without being chosen")
        var on = AppSettings()
        on.perfRecording = true
        let back = try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(on))
        #expect(back.perfRecording, "switched on after the change: stays on")
    }

    /// The permission sheet (#137) names MIDI and the clipboard in Chrome's words, not as "a
    /// browser permission".
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/137"))
    func permissionSheetNamesMIDIAndTheClipboard() {
        let site = "https://synth.example/"
        #expect(PermissionPrompt.message(origin: site, kinds: 1 << 13) == "https://synth.example/ wants to control and reprogram your MIDI devices")
        #expect(PermissionPrompt.message(origin: site, kinds: 1 << 5) == "https://synth.example/ wants to see text and images copied to the clipboard")
    }
}
