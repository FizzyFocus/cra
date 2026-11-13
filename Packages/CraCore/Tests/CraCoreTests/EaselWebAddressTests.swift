import Testing
import CraCore

/// Upstream's EaselObjectsTests.onlyWebAddressesBecomeLinks, for the part Pane has (Easel.webAddress).
struct EaselWebAddressTests {
    @Test func onlyWebAddressesBecomeLinks() {
        #expect(Easel.webAddress(" https://example.com/a?b=1 \n") == "https://example.com/a?b=1")
        #expect(Easel.webAddress("http://x.org") == "http://x.org")
        #expect(Easel.webAddress("hello world") == nil && Easel.webAddress("file:///etc/hosts") == nil)
        #expect(Easel.webAddress("javascript:alert(1)") == nil && Easel.webAddress("https://") == nil)
    }
}
