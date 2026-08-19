import AppKit
import Testing
@testable import MarkdownEngine

@Suite("Markdown image links")
struct MarkdownImageLinkTests {

    @Test("imageDestination strips titles and angle brackets")
    func destinationParsing() {
        #expect(MarkdownStyler.imageDestination(from: "https://example.com/a.png") == "https://example.com/a.png")
        #expect(MarkdownStyler.imageDestination(from: "  https://example.com/a.png \"title\" ") == "https://example.com/a.png")
        #expect(MarkdownStyler.imageDestination(from: "<https://example.com/a.png>") == "https://example.com/a.png")
    }

    @Test("Empty alt plants the image on the opening bang")
    func emptyAltAnchorIsBang() {
        let text = "![](https://example.com/a.png)"
        let tokens = MarkdownTokenizer.parseTokensViaAST(in: text)
        let image = tokens.first { $0.kind == .imageLink }
        #expect(image != nil)
        #expect(image?.contentRange.length == 0)
        let loc = MarkdownStyler.collapsedImageAnchorLocation(
            token: image!,
            rawContent: text,
            textLength: (text as NSString).length
        )
        #expect(loc == 0)
    }

    @Test("Empty-alt URL image renders when the provider returns an image")
    func emptyAltRendersFromProvider() {
        let image = NSImage(size: NSSize(width: 12, height: 8))
        var config = MarkdownEditorConfiguration.default
        config.services.images = StubImageProvider(image: image)
        let text = "![](https://example.com/a.png)"
        let attrs = MarkdownStyler.styleAttributes(
            text: text,
            fontName: "Helvetica",
            fontSize: 16,
            caretLocation: -1,
            activeTokenIndices: [],
            configuration: config
        )
        let planted = attrs.contains { $0.attributes[.latexImage] != nil }
        #expect(planted)
    }
}

private struct StubImageProvider: EmbeddedImageProvider {
    let image: NSImage
    func image(for reference: EmbeddedImageRequest) -> NSImage? { image }
    func fingerprint() -> AnyHashable { 1 }
}
