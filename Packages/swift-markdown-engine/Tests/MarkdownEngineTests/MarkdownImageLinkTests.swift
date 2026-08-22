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

    @Test("Link favicon providers receive the complete URL")
    func faviconReceivesCompleteURL() {
        var config = MarkdownEditorConfiguration.default
        config.services.favicons = PathFaviconProvider()
        let attrs = MarkdownStyler.styleAttributes(
            text: "[Issue](https://github.com/acme/app/issues/42)",
            fontName: "Helvetica",
            fontSize: 16,
            caretLocation: -1,
            activeTokenIndices: [],
            configuration: config
        )

        #expect(attrs.contains { $0.attributes[.latexImage] != nil })
    }

    @Test("Link favicons scale with body and heading line height")
    func faviconScalesWithLineHeight() throws {
        let link = "[Issue](https://github.com/acme/app/issues/42)"
        let smallBody = try #require(faviconBounds(text: link, fontSize: 12))
        let largeBody = try #require(faviconBounds(text: link, fontSize: 24))
        let heading = try #require(faviconBounds(text: "# \(link)", fontSize: 16))
        let bareHeading = try #require(
            faviconBounds(
                text: "# Issue https://github.com/acme/app/issues/42",
                fontSize: 16
            )
        )

        #expect(largeBody.height > smallBody.height)
        #expect(heading.height > smallBody.height)
        #expect(bareHeading.height == heading.height)
        #expect(heading.width == heading.height)
    }

    @Test("Link favicons follow configured paragraph line-height spacing")
    func faviconFollowsExtraLineHeight() throws {
        let link = "[Issue](https://github.com/acme/app/issues/42)"
        let standard = try #require(faviconBounds(text: link, fontSize: 16))
        let spacious = try #require(
            faviconBounds(text: link, fontSize: 16, lineHeightExtraSpacing: 14)
        )

        #expect(spacious.height > standard.height)
    }

    private func faviconBounds(
        text: String,
        fontSize: CGFloat,
        lineHeightExtraSpacing: CGFloat = ParagraphStyle.default.lineHeightExtraSpacing
    ) -> CGRect? {
        var config = MarkdownEditorConfiguration.default
        config.paragraph.lineHeightExtraSpacing = lineHeightExtraSpacing
        config.services.favicons = PathFaviconProvider()
        let attrs = MarkdownStyler.styleAttributes(
            text: text,
            fontName: "Helvetica",
            fontSize: fontSize,
            caretLocation: -1,
            activeTokenIndices: [],
            configuration: config
        )
        return attrs.compactMap { styled in
            (styled.attributes[.latexBounds] as? NSValue)?.rectValue
        }.first
    }
}

private struct StubImageProvider: EmbeddedImageProvider {
    let image: NSImage
    func image(for reference: EmbeddedImageRequest) -> NSImage? { image }
    func fingerprint() -> AnyHashable { 1 }
}

private struct PathFaviconProvider: FaviconProvider {
    func favicon(for host: String) -> NSImage? { nil }

    func favicon(for url: URL) -> NSImage? {
        guard url.path == "/acme/app/issues/42" else { return nil }
        return NSImage(size: NSSize(width: 12, height: 12))
    }
}
