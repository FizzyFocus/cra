import CraCore
import Foundation
import Testing

struct DockingAndTrayHoldTests {
    /// Off (the default) docking keeps Arc's near-instant slide; on, a longer settling ease.
    @Test func dockingSnapsUnlessAnimated() {
        #expect(!AppSettings().animateSidebarDocking)
        let snap = SidebarMotion.docking(animated: false)
        #expect(snap.duration == SidebarMotion.duration)
        let smooth = SidebarMotion.docking(animated: true)
        #expect(smooth.duration > 0.3 && smooth.duration < 0.6)
        // It settles: nearly there by two thirds of the way, all there at the end, never past it.
        var last = 0.0
        for i in 0...40 {
            let p = SidebarMotion.progress(at: smooth.duration * Double(i) / 40, curve: smooth.curve, duration: smooth.duration)
            #expect(p >= last - 1e-9 && p <= 1 + 1e-9)
            last = p
        }
        #expect(SidebarMotion.progress(at: smooth.duration * 2 / 3, curve: smooth.curve, duration: smooth.duration) > 0.9)
        #expect(abs(last - 1) < 1e-6)
    }

    @Test func thePageWritesTheDockingSetting() throws {
        let on = try SettingsBridge.applying("animateSidebarDocking", .bool(true), to: AppSettings())
        #expect(on.animateSidebarDocking)
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(on))
        #expect(back.animateSidebarDocking)
    }

    /// A preview opened from the tray keeps it out behind it; closed, the tray waits 3 s for the
    /// pointer before it goes (11 Nov 2026: it closed as the preview opened).
    @Test func theTrayStaysForThePreviewAndAGraceAfter() {
        let now = Date(timeIntervalSince1970: 1000)
        #expect(DownloadsTrayHold.isOpen(hovered: false, previewOpen: true, graceUntil: nil, now: now, hasRows: true))
        let until = now.addingTimeInterval(DownloadsTrayHold.grace)
        #expect(DownloadsTrayHold.isOpen(hovered: false, previewOpen: false, graceUntil: until, now: now.addingTimeInterval(2.9), hasRows: true))
        #expect(!DownloadsTrayHold.isOpen(hovered: false, previewOpen: false, graceUntil: until, now: now.addingTimeInterval(3), hasRows: true))
        #expect(DownloadsTrayHold.isOpen(hovered: true, previewOpen: false, graceUntil: nil, now: now, hasRows: true))
        #expect(!DownloadsTrayHold.isOpen(hovered: true, previewOpen: true, graceUntil: until, now: now, hasRows: false), "nothing to list")
    }

    /// A click between two rows of the open tray lands on the tray, not the tab under it; below the
    /// last row (over the Library button) clicks go through (11 Nov 2026).
    @Test func theTrayTakesClicksBetweenItsRows() throws {
        let L = DownloadsTrayLayout.self
        let a = try #require(L.clickArea(rows: 3, width: 300))
        func inside(_ x: Double, _ y: Double) -> Bool { x >= a.x && x < a.x + a.width && y >= a.y && y < a.y + a.height }
        let gapY = 2 + L.rowHeight + L.rowGap / 2
        #expect(inside(150, gapY), "between rows 1 and 2")
        #expect(inside(3, 2 + L.rowHeight / 2), "beside a row, left of its inset")
        #expect(!inside(150, 2 + L.listHeight(rows: 3) + L.bottomGap + 4), "over the Library button")
        #expect(L.clickArea(rows: 0, width: 300) == nil)
    }
}
