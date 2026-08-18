import AppKit
import Foundation

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let sourceURL =
    CommandLine.arguments.count > 2
    ? URL(fileURLWithPath: CommandLine.arguments[2])
    : scriptDir.appendingPathComponent("icon_source.png")
let outDir =
    CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : scriptDir.deletingLastPathComponent()
        .appendingPathComponent("App/Resources/Assets.xcassets/AppIcon.appiconset")

guard let source = NSImage(contentsOf: sourceURL),
    let cgSource = source.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    fputs("failed to load source icon: \(sourceURL.path)\n", stderr)
    exit(1)
}

func pngData(from image: CGImage, px: Int) -> Data? {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard
        let ctx = CGContext(
            data: nil,
            width: px,
            height: px,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
    guard let scaled = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
}

let fileMgr = FileManager.default
try? fileMgr.createDirectory(at: outDir, withIntermediateDirectories: true)

for entry in sizes {
    guard let png = pngData(from: cgSource, px: entry.px) else {
        fputs("failed to render \(entry.name)\n", stderr)
        continue
    }
    let url = outDir.appendingPathComponent(entry.name)
    do {
        try png.write(to: url)
        print("wrote \(entry.name)")
    } catch {
        fputs("write failed \(entry.name): \(error)\n", stderr)
    }
}
