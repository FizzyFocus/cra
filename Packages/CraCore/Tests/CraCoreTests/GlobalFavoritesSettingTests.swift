import CraCore
import Foundation
import Testing

/// Favorites are global (one list per profile, shown by every space) by default; files from before
/// that saved per-space favorites for everyone and switch over once.
struct GlobalFavoritesSettingTests {
    private func load(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    @Test func freshSettingsShareFavorites() throws {
        #expect(AppSettings().sharedFavorites)
        #expect(try load("{}").sharedFavorites, "a file without the key shares them")
    }

    @Test func anOlderFileThatSavedThemPerSpaceSharesThemOnce() throws {
        let old = try load(#"{"sharedFavorites": false}"#)
        #expect(old.sharedFavorites, "saved off by default before, without the mark")
        #expect(old.favoritesDefaultMigrated)
        // Saved again, the mark keeps the choice from then on.
        let saved = try load(String(decoding: JSONEncoder().encode(old), as: UTF8.self))
        #expect(saved.sharedFavorites)
    }

    @Test func aChoiceMadeAfterwardsIsKept() throws {
        var s = AppSettings()
        s.sharedFavorites = false
        let again = try load(String(decoding: JSONEncoder().encode(s), as: UTF8.self))
        #expect(!again.sharedFavorites, "turned off in Settings after the switch: stays off")
        #expect(try !load(#"{"sharedFavorites": false, "favoritesDefaultMigrated": true}"#).sharedFavorites)
    }

    @Test func syncedSettingsCarryTheMark() throws {
        var s = AppSettings()
        s.sharedFavorites = false
        let remote = try load(String(decoding: JSONEncoder().encode(s.forSync()), as: UTF8.self))
        #expect(!remote.sharedFavorites, "another Mac's choice arrives as it was made")
        #expect(AppSettings().applyingSynced(remote).favoritesDefaultMigrated)
    }
}
