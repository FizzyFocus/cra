import Foundation
import Testing
@testable import CraCore

/// The profile pill (13 Nov 2026): only with more than one profile; the sidebar's only with its setting on.
struct ProfileBadgeTests {
    @Test func showsOnlyWithMoreThanOneProfile() {
        #expect(!ProfileBadge.shows(profiles: 1, in: .library, setting: true))
        #expect(!ProfileBadge.shows(profiles: 1, in: .sidebar, setting: true))
        #expect(ProfileBadge.shows(profiles: 2, in: .library, setting: false), "the Library always names it")
        #expect(ProfileBadge.shows(profiles: 2, in: .sidebar, setting: true))
        #expect(!ProfileBadge.shows(profiles: 3, in: .sidebar, setting: false), "Settings ▸ Show profile indicator in sidebar, off")
        #expect(!ProfileBadge.shows(profiles: 3, in: .library, setting: true, incognito: true))
        #expect(!ProfileBadge.shows(profiles: 3, in: .sidebar, setting: true, blank: true))
    }

    @Test func theNameGivesWayBeforeThePill() throws {
        let full = try #require(ProfileBadge.width(name: 30, hasIcon: true, room: 200))
        #expect(full.showsName && full.width == 6 * 2 + 12 + 4 + 30)
        let capped = try #require(ProfileBadge.width(name: 300, hasIcon: false, room: 400))
        #expect(capped.width == 104, "a long name is cut at the pill's widest")
        let squeezed = try #require(ProfileBadge.width(name: 80, hasIcon: true, room: 60))
        #expect(squeezed.showsName && squeezed.width == 60)
        let compact = try #require(ProfileBadge.width(name: 80, hasIcon: true, room: 30))
        #expect(!compact.showsName && compact.width == 24)
        #expect(ProfileBadge.width(name: 80, hasIcon: true, room: 10) == nil)
    }

    @Test func aLookIsCleanedAndOldFilesStillLoad() throws {
        #expect(ProfileLook.cleaned(icon: " 💼 ", color: "blue") == ProfileLook(icon: "💼", color: "blue"))
        #expect(ProfileLook.cleaned(icon: "🇺🇿x", color: "chartreuse") == ProfileLook(icon: "🇺🇿", color: nil))
        #expect(ProfileLook.cleaned(icon: "  ", color: nil).isEmpty)
        // A profile saved before looks, and one with a colour from a newer build.
        let old = try JSONDecoder().decode(BrowserProfile.self, from: Data(#"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Work"}"#.utf8))
        #expect(old.icon == nil && old.look.isEmpty)
        let newer = try JSONDecoder().decode(BrowserProfile.self, from: Data(#"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Work","color":"teal"}"#.utf8))
        #expect(newer.look.accent == nil)
        // Nothing new is written for a profile with no look.
        let json = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        #expect(!json.contains("icon") && !json.contains("color"))
        #expect(ProfileAccent.blue.hex == "#007AFF")
    }
}
