import Foundation
import Testing
@testable import CraCore

/// Icon Color's colours for pinned and bookmark folders (FolderColor).
struct FolderColorTests {
    @Test func everyChoiceIsAColourWithItsOwnName() {
        #expect(Set(FolderColor.catalogue.map(\.name)).count == FolderColor.catalogue.count)
        #expect(Set(FolderColor.catalogue.map { $0.hex.lowercased() }).count == FolderColor.catalogue.count)
        for c in FolderColor.catalogue {
            #expect(FolderColor.tones(c.hex, dark: false) != nil, "\(c.name)")
            #expect(FolderColor.name(of: c.hex.lowercased()) == c.name)
        }
        #expect(FolderColor.name(of: "#123456") == nil && FolderColor.name(of: nil) == nil)
        #expect(FolderColor.tones("not a colour", dark: false) == nil)
    }

    /// The front is the colour itself, so a red folder is red on any theme; the outline is darker
    /// than it on a light sidebar and lighter on a dark one, so the glyph keeps its edge.
    @Test func theFrontIsTheColourAndTheOutlineStandsOff() throws {
        func lum(_ c: RGB) -> Double { 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
        for c in FolderColor.catalogue {
            let light = try #require(FolderColor.tones(c.hex, dark: false))
            let dark = try #require(FolderColor.tones(c.hex, dark: true))
            let rgb = try #require(HexColor.components(c.hex))
            #expect(light.front == RGB(rgb.r, rgb.g, rgb.b) && dark.front == light.front, "\(c.name)")
            #expect(lum(light.outline) < lum(light.front), "\(c.name) light")
            #expect(lum(dark.outline) > lum(dark.front), "\(c.name) dark")
            #expect(lum(light.back) < lum(light.front), "\(c.name): the back panel is a shade behind the front")
        }
    }

    /// A pinned folder's colour is a key of its own, so a Cra that predates it still reads the
    /// file; a bookmark folder's likewise.
    @Test func coloursAreSavedBesideTheOldKeys() throws {
        let enc = JSONEncoder(), dec = JSONDecoder()
        var item = SidebarItem(id: UUID(), parentID: nil, title: "Work", children: [], isUnread: false,
                               createdAt: Date(timeIntervalSince1970: 0), data: .folder)
        #expect(!String(decoding: try enc.encode(item), as: UTF8.self).contains("folderColor"), "no colour, no key")
        item.folderColor = "#F0625D"
        let back = try dec.decode(SidebarItem.self, from: try enc.encode(item))
        #expect(back.folderColor == "#F0625D" && back.folderIcon == nil)

        var lib = BookmarkLibrary()
        let f = lib.addFolder(title: "Reading", now: Date(timeIntervalSince1970: 0))
        lib.setColor(f.id, "#4F8FEA")
        let read = try dec.decode(BookmarkLibrary.self, from: try enc.encode(lib))
        #expect(read.folder(f.id)?.color == "#4F8FEA")
        lib.setColor(f.id, nil)
        #expect(!String(decoding: try enc.encode(lib), as: UTF8.self).contains("color"))
        let old = #"{"version":1,"folders":[{"id":"\#(f.id.uuidString)","title":"Old","createdAt":0}],"bookmarks":[]}"#
        #expect(try dec.decode(BookmarkLibrary.self, from: Data(old.utf8)).folders.first?.color == nil)
    }
}
