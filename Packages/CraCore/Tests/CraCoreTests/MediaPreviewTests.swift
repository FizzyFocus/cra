import CoreGraphics
import CraCore
import Foundation
import Testing

/// Arc's preview for a pick in Library ▸ Media, measured on Victor's Arc (8 Nov 2026).
struct MediaPreviewTests {
    @Test func thePanelSitsWhereArcsDid() {
        let p = MediaPreview.panel(in: CGRect(x: 0, y: 0, width: 1728, height: 1084))
        #expect(p == CGRect(x: 199, y: 133, width: 1330, height: 818))
    }

    @Test func thePictureFitsUnderTheHeader() {
        let panel = CGRect(x: 199, y: 133, width: 1330, height: 818)
        // Arc's square picture: 739 pt tall under the 46 pt header, centred across.
        let r = MediaPreview.media(CGSize(width: 1024, height: 1024), in: panel)
        #expect(r.height == 742.0)
        #expect(r.width == r.height)
        #expect(abs(r.midX - panel.midX) <= 0.5)
        #expect(r.minY == 148.0)
        // A wide one fills the width instead.
        let wide = MediaPreview.media(CGSize(width: 4000, height: 1000), in: panel)
        #expect(wide.width == 1300.0)
    }

    @Test func arrowsStopAtTheEnds() {
        #expect(MediaPreview.step(0, by: -1, count: 3) == nil)
        #expect(MediaPreview.step(0, by: 1, count: 3) == 1)
        #expect(MediaPreview.step(2, by: 1, count: 3) == nil)
    }

    @Test func theHeadersAge() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(MediaPreview.age(now.addingTimeInterval(-86_400), now: now) == "1 day ago")
        #expect(MediaPreview.age(now.addingTimeInterval(-10), now: now) == "Just now")
    }

    @Test func downloadsPreviewByKindAndTheRestOpenInTheirApp() {
        #expect(MediaPreview.kind(of: "/d/step1 (1).png") == .image)
        #expect(MediaPreview.kind(of: "/d/Clip.GIF") == .image)
        #expect(MediaPreview.kind(of: "/d/logo.svg") == .image)
        #expect(MediaPreview.kind(of: "/d/Screen Recording.mp4") == .video)
        #expect(MediaPreview.kind(of: "/d/talk.webm") == .webVideo)
        for doc in ["a.pdf", "notes.txt", "table.csv", "report.docx", "sheet.xlsx", "deck.pptx", "song.mp3"] {
            #expect(MediaPreview.kind(of: "/d/" + doc) == .document, "\(doc)")
        }
        for other in ["archive.zip", "installer.dmg", "setup.pkg", "tree_01.3mf", "noextension"] {
            #expect(MediaPreview.kind(of: "/d/" + other) == nil, "\(other)")
        }
    }

    @Test func theArrowsStepThroughWhatTheListPreviews() {
        let list = ["/d/a.png", "/d/b.zip", "/d/c.pdf", "/d/d.dmg", "/d/e.mp4"]
        let b = MediaPreview.browse(list, picked: "/d/c.pdf")
        #expect(b?.paths == ["/d/a.png", "/d/c.pdf", "/d/e.mp4"])
        #expect(b?.index == 1)
        // A pick it can't show opens in its app instead.
        #expect(MediaPreview.browse(list, picked: "/d/b.zip") == nil)
        // A pick missing from the list is shown on its own.
        #expect(MediaPreview.browse(list, picked: "/d/z.png")?.paths == ["/d/z.png"])
    }

    @Test func theHandOffButtonNamesTheApp() {
        #expect(MediaPreview.openTitle(appName: "Preview") == "Open in Preview")
        #expect(MediaPreview.openTitle(appName: "QuickTime Player.app") == "Open in QuickTime Player")
        #expect(MediaPreview.openTitle(appName: nil) == "Open")
    }

    @Test func aDocumentFillsTheBody() {
        let panel = CGRect(x: 199, y: 133, width: 1330, height: 818)
        #expect(MediaPreview.body(in: panel) == CGRect(x: 214, y: 148, width: 1300, height: 742))
    }

    /// The panel grows out of the clicked thumbnail and shrinks back into it: its picture lands
    /// centred inside the thumbnail's rect, fitted (11 Nov 2026).
    @Test func thePictureLandsInsideTheItemItGrewFrom() throws {
        let panel = CGRect(x: 199, y: 133, width: 1330, height: 818)
        let thumb = CGRect(x: 30, y: 40, width: 40, height: 40)
        // Whichever point the layer is anchored at (AppKit's corner, or the centre), the same item.
        for anchor in [panel.origin, CGPoint(x: panel.midX, y: panel.midY)] {
            for media in [MediaPreview.media(CGSize(width: 1600, height: 900), in: panel), MediaPreview.body(in: panel)] {
                let o = try #require(MediaPreview.origin(media: media, about: anchor, origin: thumb))
                let landed = CGRect(x: anchor.x + (media.minX - anchor.x) * o.scale + o.shift.x,
                                    y: anchor.y + (media.minY - anchor.y) * o.scale + o.shift.y,
                                    width: media.width * o.scale, height: media.height * o.scale)
                #expect(abs(landed.midX - thumb.midX) < 0.01 && abs(landed.midY - thumb.midY) < 0.01)
                #expect(landed.width <= thumb.width + 0.01 && landed.height <= thumb.height + 0.01)
                #expect(abs(landed.width - thumb.width) < 0.01 || abs(landed.height - thumb.height) < 0.01, "fitted, touching two sides")
            }
        }
        #expect(MediaPreview.origin(media: .zero, about: panel.origin, origin: thumb) == nil)
    }

    /// With nothing to go back into, the panel shrinks a touch about its own centre, wherever its
    /// layer is anchored.
    @Test func shrinkingInPlaceKeepsTheCentre() {
        let panel = CGRect(x: 199, y: 133, width: 1330, height: 818)
        let c = CGPoint(x: panel.midX, y: panel.midY), a = panel.origin
        let t = MediaPreview.shift(keeping: c, about: a, scale: 0.96)
        #expect(abs(a.x + (c.x - a.x) * 0.96 + t.x - c.x) < 0.001 && abs(a.y + (c.y - a.y) * 0.96 + t.y - c.y) < 0.001)
    }
}
