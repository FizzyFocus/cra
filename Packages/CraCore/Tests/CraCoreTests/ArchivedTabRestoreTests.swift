import Testing
@testable import CraCore

/// A click restores an archived tab in the background; Shift-click switches to it (12 Nov 2026).
struct ArchivedTabRestoreTests {
    @Test func aClickRestoresInTheBackgroundAndShiftSwitches() {
        #expect(!ArchivedTabRestore.switchesToTab(shift: false))
        #expect(ArchivedTabRestore.switchesToTab(shift: true))
        #expect(ArchivedTabRestore.toast == "Tab Restored")
    }
}
