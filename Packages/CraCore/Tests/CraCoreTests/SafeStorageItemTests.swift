import Testing
@testable import CraCore

/// Pane's own Keychain item (13 Nov 2026): "Pane Safe Storage", the secret moved over from Cra's once.
struct SafeStorageItemTests {
    @Test func theBuildNamesTheItemItsChromiumReads() {
        #expect(SafeStorageItem(bundledService: "Pane Safe Storage") == .pane)
        #expect(SafeStorageItem.pane.account == "Pane")
        #expect(SafeStorageItem(bundledService: "Cra Safe Storage") == .cra, "a CEF the script could not change")
        #expect(SafeStorageItem.cra.account == "Chromium")
        #expect(SafeStorageItem(bundledService: "Chromium Safe Storage") == nil, "stock CEF's shared item is not Pane's")
        #expect(SafeStorageItem(bundledService: nil) == nil)
        #expect(SafeStorageItem.pane.predecessors == [.cra])
        #expect(SafeStorageItem.cra.predecessors == [.pane], "a CEF back on Cra's name finds the secret in Pane's")
    }

    @Test func anEncryptedProfileTakesItsSecretFromCrasItemOnce() {
        func plan(_ items: [SafeStorageItem], mayMove: Bool = false) -> SafeStorageStep {
            SafeStorageStep.plan(item: .pane, encrypted: true, mayMoveProfile: mayMove, exists: { items.contains($0) })
        }
        #expect(plan([.cra]) == .copy(from: .cra))
        #expect(plan([.pane, .cra]) == .use, "moved already")
        #expect(plan([.pane]) == .use)
        #expect(plan([]) == .use, "no item holds its secret: Chromium makes a new one as before")
    }

    @Test func aFreshProfileNeverMakesASecondSecret() {
        func plan(_ items: [SafeStorageItem], mayMove: Bool) -> SafeStorageStep {
            SafeStorageStep.plan(item: .pane, encrypted: false, mayMoveProfile: mayMove, exists: { items.contains($0) })
        }
        #expect(plan([], mayMove: true) == .use)
        #expect(plan([.pane], mayMove: true) == .use)
        #expect(plan([.cra], mayMove: true) == .mock, "Cra's item still holds the real profile's secret")
        #expect(plan([.pane], mayMove: false) == .mock, "an ad-hoc build, or another copy has the profile")
        #expect(plan([], mayMove: false) == .mock)
    }

    @Test func onlyAnInstalledCraKeepsItsItem() {
        let home = "/Users/me"
        #expect(SafeStorageItem.appIsInstalled(at: ["/Applications/Cra.app"], home: home))
        #expect(SafeStorageItem.appIsInstalled(at: ["/Applications/Browsers/Cra.app"], home: home))
        #expect(SafeStorageItem.appIsInstalled(at: ["/Users/me/Applications/Cra.app"], home: home))
        #expect(!SafeStorageItem.appIsInstalled(at: ["/Users/me/Documents/Browser/cra/build/Cra.app"], home: home),
                "a build folder's leftover")
        #expect(!SafeStorageItem.appIsInstalled(at: [], home: home))
    }
}
