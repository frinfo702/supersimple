import AppKit

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

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])

// Accent color (warm terracotta) used for the brand mark.
let accent = NSColor(calibratedRed: 0.78, green: 0.455, blue: 0.353, alpha: 1.0)
let background = NSColor(calibratedRed: 0.055, green: 0.055, blue: 0.060, alpha: 1.0)

func render(size px: Int) -> NSImage {
    let canvas = NSImage(size: NSSize(width: px, height: px), flipped: false) { rect in
        // Background rounded square (macOS icon masks corners itself, draw full-bleed).
        background.setFill()
        rect.fill()

        // Accent "N + ink" mark: a clean squared page glyph with a folded corner.
        let scale = CGFloat(px) / 1024.0
        let pageRect = NSRect(x: 328 * scale, y: 252 * scale, width: 368 * scale, height: 480 * scale)
        accent.setFill()
        NSBezierPath(roundedRect: pageRect, xRadius: 30 * scale, yRadius: 30 * scale).fill()

        // Paper highlight line suggesting note text.
        NSColor.black.withAlphaComponent(0.25).setFill()
        let line1 = NSRect(x: 400 * scale, y: 600 * scale, width: 224 * scale, height: 26 * scale)
        let line2 = NSRect(x: 400 * scale, y: 520 * scale, width: 224 * scale, height: 26 * scale)
        NSBezierPath(roundedRect: line1, xRadius: 12 * scale, yRadius: 12 * scale).fill()
        NSBezierPath(roundedRect: line2, xRadius: 12 * scale, yRadius: 12 * scale).fill()

        return true
    }
    return canvas
}

let fileMgr = FileManager.default
try? fileMgr.createDirectory(at: outDir, withIntermediateDirectories: true)

for entry in sizes {
    let image = render(size: entry.px)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("failed to render \(entry.name)")
        continue
    }
    let url = outDir.appendingPathComponent(entry.name)
    do { try png.write(to: url) } catch { print("write failed \(entry.name): \(error)") }
    print("wrote \(entry.name)")
}