import AppKit
import Foundation

/// Generates selectable app-icon imagesets: copies the original mark as Default,
/// copies Ghost from `icon_ghost.png`, and draws a family of colored squircles.

let sizes: [(suffix: String, px: Int)] = [
    ("icon.png", 256),
    ("icon@2x.png", 512),
]

struct IconSpec {
    var folder: String
    var top: (CGFloat, CGFloat, CGFloat)
    var bottom: (CGFloat, CGFloat, CGFloat)
    var mark: (CGFloat, CGFloat, CGFloat)
    var accent: (CGFloat, CGFloat, CGFloat)
}

let generated: [IconSpec] = [
    IconSpec(
        folder: "AppIconPaper",
        top: (0.96, 0.94, 0.90), bottom: (0.90, 0.87, 0.80),
        mark: (0.16, 0.15, 0.13), accent: (0.82, 0.48, 0.38)),
    IconSpec(
        folder: "AppIconInk",
        top: (0.10, 0.16, 0.28), bottom: (0.06, 0.10, 0.18),
        mark: (0.96, 0.95, 0.92), accent: (0.84, 0.68, 0.38)),
    IconSpec(
        folder: "AppIconEmber",
        top: (0.78, 0.38, 0.28), bottom: (0.58, 0.24, 0.18),
        mark: (0.99, 0.96, 0.93), accent: (0.20, 0.12, 0.10)),
    IconSpec(
        folder: "AppIconMoss",
        top: (0.22, 0.34, 0.26), bottom: (0.14, 0.22, 0.17),
        mark: (0.95, 0.94, 0.88), accent: (0.78, 0.86, 0.52)),
    IconSpec(
        folder: "AppIconViolet",
        top: (0.30, 0.22, 0.48), bottom: (0.18, 0.12, 0.32),
        mark: (0.97, 0.96, 1.00), accent: (0.92, 0.55, 0.98)),
    IconSpec(
        folder: "AppIconFrost",
        top: (0.78, 0.84, 0.90), bottom: (0.62, 0.70, 0.80),
        mark: (0.14, 0.18, 0.26), accent: (0.25, 0.45, 0.78)),
    IconSpec(
        folder: "AppIconNoir",
        top: (0.12, 0.12, 0.12), bottom: (0.05, 0.05, 0.05),
        mark: (0.96, 0.96, 0.96), accent: (0.22, 0.42, 0.95)),
]

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repoRoot = scriptDir.deletingLastPathComponent()
let catalog = repoRoot.appendingPathComponent("App/Resources/Assets.xcassets")
let sourceURL = scriptDir.appendingPathComponent("icon_source.png")

func writeImagesetContents(_ url: URL) throws {
    let json = """
        {
          "images" : [
            { "filename" : "icon.png", "idiom" : "mac", "scale" : "1x" },
            { "filename" : "icon@2x.png", "idiom" : "mac", "scale" : "2x" }
          ],
          "info" : { "author" : "xcode", "version" : 1 }
        }
        """
    try json.data(using: .utf8)!.write(to: url.appendingPathComponent("Contents.json"))
}

func pngData(from image: CGImage) -> Data? {
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

func makeContext(px: Int) -> (CGContext, UnsafeMutablePointer<UInt8>)? {
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let bytesPerRow = px * 4
    guard let data = malloc(bytesPerRow * px)?.assumingMemoryBound(to: UInt8.self) else { return nil }
    memset(data, 0, bytesPerRow * px)
    guard
        let ctx = CGContext(
            data: data, width: px, height: px, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else {
        free(data)
        return nil
    }
    ctx.interpolationQuality = .high
    return (ctx, data)
}

func imageFromContext(_ ctx: CGContext, data: UnsafeMutablePointer<UInt8>) -> Data? {
    defer { free(data) }
    guard let image = ctx.makeImage() else { return nil }
    return pngData(from: image)
}

func scaledSquirclePNG(
    from source: CGImage, px: Int, plateInset: CGFloat = 0.06, artInset: CGFloat = 0
) -> Data? {
    guard let (ctx, data) = makeContext(px: px) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let canvas = CGRect(x: 0, y: 0, width: px, height: px)
    let plate = canvas.insetBy(dx: CGFloat(px) * plateInset, dy: CGFloat(px) * plateInset)
    squirclePath(in: plate).addClip()
    NSColor.black.setFill()
    NSBezierPath(rect: plate).fill()
    // Shrink uniformly and sit on the plate bottom so cropped hems (Ghost)
    // still meet the squircle instead of floating on a black pad.
    let scale = 1 - 2 * artInset
    let art = CGRect(
        x: plate.midX - plate.width * scale / 2,
        y: plate.minY,
        width: plate.width * scale,
        height: plate.height * scale
    )
    ctx.draw(source, in: art)
    NSGraphicsContext.restoreGraphicsState()
    return imageFromContext(ctx, data: data)
}

/// `icon_source.png` paints a squircle on an opaque black square. Punch the
/// connected black padding to alpha so Settings / Dock see rounded corners.
func scaledKnockoutPNG(from source: CGImage, px: Int) -> Data? {
    guard let (ctx, data) = makeContext(px: px) else { return nil }
    ctx.draw(source, in: CGRect(x: 0, y: 0, width: px, height: px))
    let count = px * px
    var visited = [UInt8](repeating: 0, count: count)
    var queue = [Int]()
    queue.reserveCapacity(count / 4)

    func luma(_ i: Int) -> Int {
        let o = i * 4
        return Int(data[o]) + Int(data[o + 1]) + Int(data[o + 2])
    }
    func enqueue(_ x: Int, _ y: Int) {
        guard x >= 0, y >= 0, x < px, y < px else { return }
        let i = y * px + x
        if visited[i] != 0 { return }
        visited[i] = 1
        if luma(i) <= 14 { queue.append(i) }
    }

    enqueue(0, 0)
    enqueue(px - 1, 0)
    enqueue(0, px - 1)
    enqueue(px - 1, px - 1)
    var q = 0
    while q < queue.count {
        let i = queue[q]
        q += 1
        let x = i % px
        let y = i / px
        enqueue(x - 1, y)
        enqueue(x + 1, y)
        enqueue(x, y - 1)
        enqueue(x, y + 1)
    }
    for i in queue {
        let o = i * 4
        data[o] = 0
        data[o + 1] = 0
        data[o + 2] = 0
        data[o + 3] = 0
    }
    return imageFromContext(ctx, data: data)
}

enum SourceIconMode {
    case squircle(plateInset: CGFloat, artInset: CGFloat)
    case knockoutBlack
}

func writeSourcedIcon(folder: String, source: URL, mode: SourceIconMode) throws {
    guard let image = NSImage(contentsOf: source),
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        fputs("failed to load source icon: \(source.path)\n", stderr)
        exit(1)
    }
    let dir = catalog.appendingPathComponent("\(folder).imageset")
    try fileMgr.createDirectory(at: dir, withIntermediateDirectories: true)
    try writeImagesetContents(dir)
    for entry in sizes {
        let png: Data?
        switch mode {
        case .squircle(let plateInset, let artInset):
            png = scaledSquirclePNG(from: cg, px: entry.px, plateInset: plateInset, artInset: artInset)
        case .knockoutBlack: png = scaledKnockoutPNG(from: cg, px: entry.px)
        }
        guard let png else {
            fputs("failed to scale \(folder) \(entry.suffix)\n", stderr)
            continue
        }
        try png.write(to: dir.appendingPathComponent(entry.suffix))
        print("wrote \(folder)/\(entry.suffix)")
    }
}

func squirclePath(in rect: CGRect) -> NSBezierPath {
    // macOS icon corner radius ≈ 22.4% of the side.
    let r = rect.width * 0.223
    return NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
}

func color(_ rgb: (CGFloat, CGFloat, CGFloat), alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: alpha)
}

func drawIcon(spec: IconSpec, px: Int) -> CGImage? {
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard
        let ctx = CGContext(
            data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    let canvas = CGRect(x: 0, y: 0, width: px, height: px)
    let inset = CGFloat(px) * 0.06
    let rect = canvas.insetBy(dx: inset, dy: inset)
    let clip = squirclePath(in: rect)
    clip.addClip()

    let gradient = NSGradient(colors: [color(spec.top), color(spec.bottom)])
    gradient?.draw(in: rect, angle: 270)

    // Soft sheen from the top edge, fading out before the midline.
    let highlight = NSGradient(
        colors: [
            NSColor(calibratedWhite: 1, alpha: 0.0),
            NSColor(calibratedWhite: 1, alpha: 0.18),
        ])
    let hiRect = CGRect(
        x: rect.minX,
        y: rect.midY + rect.height * 0.08,
        width: rect.width,
        height: rect.height / 2 - rect.height * 0.08
    )
    highlight?.draw(in: hiRect, angle: 90)

    // Drop shadow for the mark.
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -CGFloat(px) * 0.018),
        blur: CGFloat(px) * 0.035,
        color: NSColor(calibratedWhite: 0, alpha: 0.35).cgColor
    )
    drawS(in: rect, mark: spec.mark, accent: spec.accent)
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()
}

func drawS(
    in rect: CGRect, mark: (CGFloat, CGFloat, CGFloat), accent: (CGFloat, CGFloat, CGFloat)
) {
    let s = NSBezierPath()
    let inset = rect.insetBy(dx: rect.width * 0.27, dy: rect.height * 0.24)
    s.move(to: CGPoint(x: inset.maxX - inset.width * 0.06, y: inset.minY + inset.height * 0.20))
    s.curve(
        to: CGPoint(x: inset.midX, y: inset.midY),
        controlPoint1: CGPoint(x: inset.maxX + inset.width * 0.18, y: inset.minY + inset.height * 0.48),
        controlPoint2: CGPoint(x: inset.maxX - inset.width * 0.02, y: inset.midY - inset.height * 0.04)
    )
    s.curve(
        to: CGPoint(x: inset.minX + inset.width * 0.06, y: inset.maxY - inset.height * 0.20),
        controlPoint1: CGPoint(x: inset.minX + inset.width * 0.02, y: inset.midY + inset.height * 0.04),
        controlPoint2: CGPoint(x: inset.minX - inset.width * 0.18, y: inset.maxY - inset.height * 0.48)
    )
    s.lineWidth = rect.width * 0.155
    s.lineCapStyle = .round
    s.lineJoinStyle = .round
    color(mark).setStroke()
    s.stroke()

    // Accent fold at the S waist.
    let fold = NSBezierPath(
        roundedRect: CGRect(
            x: inset.midX - rect.width * 0.055,
            y: inset.midY - rect.height * 0.035,
            width: rect.width * 0.11,
            height: rect.height * 0.07
        ),
        xRadius: rect.width * 0.02,
        yRadius: rect.width * 0.02
    )
    color(accent).setFill()
    fold.fill()
}

let fileMgr = FileManager.default
try fileMgr.createDirectory(at: catalog, withIntermediateDirectories: true)

let catalogContents = """
    {
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """
try catalogContents.data(using: .utf8)!.write(to: catalog.appendingPathComponent("Contents.json"))

try writeSourcedIcon(folder: "AppIconDefault", source: sourceURL, mode: .knockoutBlack)
try writeSourcedIcon(
    folder: "AppIconGhost",
    source: scriptDir.appendingPathComponent("icon_ghost.png"),
    mode: .squircle(plateInset: 0.06, artInset: 0.16)
)

for spec in generated {
    let dir = catalog.appendingPathComponent("\(spec.folder).imageset")
    try fileMgr.createDirectory(at: dir, withIntermediateDirectories: true)
    try writeImagesetContents(dir)
    for entry in sizes {
        guard let image = drawIcon(spec: spec, px: entry.px), let png = pngData(from: image) else {
            fputs("failed to draw \(spec.folder) \(entry.suffix)\n", stderr)
            continue
        }
        try png.write(to: dir.appendingPathComponent(entry.suffix))
        print("wrote \(spec.folder)/\(entry.suffix)")
    }
}
