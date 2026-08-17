import AppKit
import MarkdownEngine

/// Stores pasted images on disk and serves them to the Markdown engine's
/// `![[name]]` image embeds. Images live in `<appSupport>/Images/`.
final class ImageStore: @unchecked Sendable {
    private let imagesDir: URL
    private let lock = NSLock()
    private var cache: [String: NSImage] = [:]

    init(appSupport: URL) {
        imagesDir = appSupport.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    }

    /// Saves pasted image data and returns the embed name to insert as `![[name]]`.
    func savePastedImage(_ data: Data, ext: String) -> String? {
        let name = UUID().uuidString + "." + ext
        let url = imagesDir.appendingPathComponent(name)
        do {
            try data.write(to: url)
        } catch {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        cache[name] = NSImage(data: data)
        return name
    }

    func image(for name: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[name] { return cached }
        let url = imagesDir.appendingPathComponent(name)
        guard let img = NSImage(contentsOf: url) else { return nil }
        cache[name] = img
        return img
    }

    func fingerprint() -> AnyHashable {
        (try? FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil).count) ?? 0
    }
}

extension ImageStore: EmbeddedImageProvider {
    func image(for reference: EmbeddedImageRequest) -> NSImage? {
        image(for: reference.name)
    }
}
