import CraCore
import Foundation
import Testing

struct WebImagePreviewTests {
    @Test func aShiftClickPreviewsAnImageButNotALink() {
        #expect(WebImagePreview.shiftClickPreviews(shiftOnly: true, isImage: true, insideLink: false))
        #expect(!WebImagePreview.shiftClickPreviews(shiftOnly: true, isImage: true, insideLink: true), "Peek keeps linked images")
        #expect(!WebImagePreview.shiftClickPreviews(shiftOnly: false, isImage: true, insideLink: false))
        #expect(!WebImagePreview.shiftClickPreviews(shiftOnly: true, isImage: false, insideLink: false))
    }

    @Test func dataURLsDecode() throws {
        let png = try #require(WebImagePreview.decodeDataURL("data:image/png;base64,iVBORw0KGgo="))
        #expect(png.mimeType == "image/png")
        #expect(png.data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        let svg = try #require(WebImagePreview.decodeDataURL("data:image/svg+xml,%3Csvg%2F%3E"))
        #expect(String(decoding: svg.data, as: UTF8.self) == "<svg/>")
        #expect(WebImagePreview.decodeDataURL("https://example.com/a.png") == nil)
    }

    @Test func theFileIsNamedAfterTheImage() {
        #expect(WebImagePreview.fileName(url: "https://cdn.example.com/photos/Cat%20Photo.JPG?w=200", mimeType: "image/jpeg") == "Cat Photo.JPG")
        #expect(WebImagePreview.fileName(url: "https://example.com/render/12345", mimeType: "image/webp") == "12345.webp")
        #expect(WebImagePreview.fileName(url: "data:image/png;base64,xyz", mimeType: "image/png") == "Image.png")
        #expect(WebImagePreview.fileName(url: "https://example.com/", mimeType: nil) == "Image.png")
    }
}
