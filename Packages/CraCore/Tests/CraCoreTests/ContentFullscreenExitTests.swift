import Foundation
import Testing
@testable import CraCore

@Suite struct ContentFullscreenExitTests {
    private let video = UUID(), other = UUID()

    @Test func anotherTabTakesTheWindow() {
        #expect(ContentFullscreenExit.shouldExit(fullscreenTab: video, shownTabs: [other], commandBarOpening: false))
        #expect(ContentFullscreenExit.shouldExit(fullscreenTab: video, shownTabs: [], commandBarOpening: false), "a new tab not shown yet")
    }

    @Test func theCommandBarOpensOverIt() {
        #expect(ContentFullscreenExit.shouldExit(fullscreenTab: video, shownTabs: [video], commandBarOpening: true))
    }

    @Test func itStaysWhileItIsTheOneShown() {
        #expect(!ContentFullscreenExit.shouldExit(fullscreenTab: video, shownTabs: [video], commandBarOpening: false))
        #expect(!ContentFullscreenExit.shouldExit(fullscreenTab: nil, shownTabs: [other], commandBarOpening: true))
    }
}
