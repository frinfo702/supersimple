import AppKit
import Testing

@testable import MarkdownEngine

@Suite(
    "Markdown scrolling benchmarks",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["RUN_SCROLL_BENCHMARKS"] != nil)
)
@MainActor
struct MarkdownScrollingBenchmarkTests {
    @Test("Mixed-rendering note scroll throughput")
    func mixedRenderingScrollThroughput() throws {
        let benchmark = try ScrollRenderingBenchmark(paragraphCount: 1_200)
        #expect(benchmark.fragments.count >= 1_100)

        // Warm TextKit, Core Text, and symbol/image caches before recording.
        _ = benchmark.render(frames: 12, viewportFragmentCount: 28)

        let framesPerRound = 180
        let roundMilliseconds = (0..<5).map { _ in
            let started = DispatchTime.now().uptimeNanoseconds
            let checksum = benchmark.render(frames: framesPerRound, viewportFragmentCount: 28)
            #expect(checksum > 0)
            return Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        }

        let sorted = roundMilliseconds.sorted()
        let medianMilliseconds = sorted[sorted.count / 2]
        let millisecondsPerFrame = medianMilliseconds / Double(framesPerRound)
        let framesPerSecond = 1_000 / millisecondsPerFrame
        let samples = roundMilliseconds.map { String(format: "%.2f", $0) }.joined(separator: ",")

        print(
            "SCROLL_BENCHMARK "
                + "paragraphs=1200 fragments=\(benchmark.fragments.count) "
                + "frames=\(framesPerRound) viewport_fragments=28 "
                + "median_ms=\(String(format: "%.2f", medianMilliseconds)) "
                + "ms_per_frame=\(String(format: "%.3f", millisecondsPerFrame)) "
                + "fps=\(String(format: "%.1f", framesPerSecond)) "
                + "round_ms=[\(samples)]"
        )

        #expect(millisecondsPerFrame.isFinite)
    }
}

@MainActor
private final class ScrollRenderingBenchmark {
    let fragments: [MarkdownTextLayoutFragment]

    private let textView: NativeTextView
    private let layoutDelegate: MarkdownLayoutManagerDelegate
    private let context: CGContext

    init(paragraphCount: Int) throws {
        let width: CGFloat = 760
        textView = NativeTextView(frame: NSRect(x: 0, y: 0, width: width, height: 720))
        textView.baseFont = NSFont.systemFont(ofSize: 16)
        textView.font = textView.baseFont

        guard let textContainer = textView.textContainer,
              let layoutManager = textView.textLayoutManager,
              let textStorage = textView.textStorage else {
            throw BenchmarkSetupError.missingTextKitStack
        }
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 0
        textContainer.size = NSSize(width: width, height: .greatestFiniteMagnitude)

        layoutDelegate = MarkdownLayoutManagerDelegate()
        layoutManager.delegate = layoutDelegate
        (layoutManager.textContentManager as? NSTextContentStorage)?.delegate = layoutDelegate

        textStorage.setAttributedString(Self.makeDocument(paragraphCount: paragraphCount))
        layoutManager.ensureLayout(for: layoutManager.documentRange)

        var laidOutFragments: [MarkdownTextLayoutFragment] = []
        layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            if let markdownFragment = fragment as? MarkdownTextLayoutFragment {
                laidOutFragments.append(markdownFragment)
            }
            return true
        }
        fragments = laidOutFragments

        guard let bitmapContext = CGContext(
            data: nil,
            width: Int(width),
            height: 720,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw BenchmarkSetupError.missingBitmapContext
        }
        context = bitmapContext
    }

    func render(frames: Int, viewportFragmentCount: Int) -> CGFloat {
        guard fragments.count > viewportFragmentCount else { return 0 }

        var checksum: CGFloat = 0
        for frame in 0..<frames {
            let start = (frame * 7) % (fragments.count - viewportFragmentCount)
            let visibleFragments = fragments[start..<(start + viewportFragmentCount)]
            let viewportTop = visibleFragments.first?.layoutFragmentFrame.minY ?? 0

            context.saveGState()
            context.setFillColor(NSColor.textBackgroundColor.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 760, height: 720))
            context.clip(to: CGRect(x: 0, y: 0, width: 760, height: 720))

            for fragment in visibleFragments {
                let frame = fragment.layoutFragmentFrame
                let drawPoint = CGPoint(x: frame.minX, y: frame.minY - viewportTop)
                checksum += fragment.renderingSurfaceBounds.width
                fragment.draw(at: drawPoint, in: context)
            }
            context.restoreGState()
        }
        return checksum
    }

    private static func makeDocument(paragraphCount: Int) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = NSFont.systemFont(ofSize: 16)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = 22
        paragraphStyle.paragraphSpacing = 6
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ]
        let latexImage = makeLatexPlaceholder()

        for index in 0..<paragraphCount {
            let line: String
            let customAttributes: [(NSAttributedString.Key, Any, NSRange)]

            switch index % 9 {
            case 0:
                line = "A plain paragraph with enough text to represent a normal note line.\n"
                customAttributes = []
            case 1:
                line = "let renderedValue = expensiveOperation(item: \(index))\n"
                customAttributes = [
                    (.markdownCodeBlockBackground, NSColor.windowBackgroundColor, NSRange(location: 0, length: line.utf16.count - 1))
                ]
            case 2:
                line = "Highlighted prose appears inside an attributed line-box fill.\n"
                customAttributes = [
                    (.markdownBlockBackground, NSColor.systemYellow.withAlphaComponent(0.22), NSRange(location: 0, length: 17))
                ]
            case 3:
                line = "Inline formula x squared remains cached while the document scrolls.\n"
                customAttributes = [
                    (.latexImage, latexImage, NSRange(location: 15, length: 9)),
                    (.latexBounds, NSValue(rect: CGRect(x: 0, y: -3, width: 42, height: 18)), NSRange(location: 15, length: 9))
                ]
            case 4:
                line = "---\n"
                customAttributes = [
                    (.thematicBreak, true, NSRange(location: 0, length: 3))
                ]
            case 5:
                line = "> A quoted paragraph carries a painted gutter bar.\n"
                customAttributes = [
                    (.blockquoteLevel, 1, NSRange(location: 0, length: line.utf16.count - 1))
                ]
            case 6:
                line = "- A bullet marker is replaced by a painted disc.\n"
                customAttributes = [
                    (.bulletMarker, true, NSRange(location: 0, length: 1))
                ]
            case 7:
                line = "8. An ordered marker is painted over its source.\n"
                customAttributes = [
                    (.orderedMarker, "8.", NSRange(location: 0, length: 2))
                ]
            default:
                line = "- [ ] A task marker is replaced by a symbol image.\n"
                customAttributes = [
                    (.taskCheckbox, false, NSRange(location: 0, length: 5))
                ]
            }

            let paragraphStart = result.length
            result.append(NSAttributedString(string: line, attributes: baseAttributes))
            for (key, value, localRange) in customAttributes {
                result.addAttribute(
                    key,
                    value: value,
                    range: NSRange(location: paragraphStart + localRange.location, length: localRange.length)
                )
            }
        }
        return result
    }

    private static func makeLatexPlaceholder() -> NSImage {
        let image = NSImage(size: NSSize(width: 42, height: 18))
        image.lockFocus()
        NSColor.labelColor.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 2, y: 4))
        path.line(to: NSPoint(x: 16, y: 14))
        path.line(to: NSPoint(x: 28, y: 4))
        path.lineWidth = 1.5
        path.stroke()
        image.unlockFocus()
        return image
    }
}

private enum BenchmarkSetupError: Error {
    case missingTextKitStack
    case missingBitmapContext
}
