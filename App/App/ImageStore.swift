import AppKit
import MarkdownEngine

/// Stores pasted images on disk and serves them to the Markdown engine's
/// `![[name]]` image embeds. Images live in `<appSupport>/Images/`.
/// HTTP(S) / `file:` destinations for `![](url)` are fetched asynchronously
/// and cached in memory; a notification restyles the editor when they land.
final class ImageStore: @unchecked Sendable {
    static let remoteImageLoaded = Notification.Name("supersimple.remoteImageLoaded")

    var didLoadNotification: Notification.Name? { Self.remoteImageLoaded }

    private let imagesDir: URL
    private let lock = NSLock()
    private var cache: [String: NSImage] = [:]
    private var remoteCache: [String: NSImage] = [:]
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []
    private var generation = 0
    private let session = URLSession.shared

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
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: imagesDir, includingPropertiesForKeys: nil
            ).count) ?? 0
        lock.lock()
        let gen = generation
        let remote = remoteCache.count
        lock.unlock()
        return "\(files)|\(remote)|\(gen)"
    }

    static func remoteURL(from name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "http" || scheme == "https" || scheme == "file" { return url }
        return nil
    }

    private func remoteImage(for url: URL) -> NSImage? {
        let key = url.absoluteString
        lock.lock()
        if let cached = remoteCache[key] {
            lock.unlock()
            return cached
        }
        if failed.contains(key) || inFlight.contains(key) {
            lock.unlock()
            return nil
        }
        inFlight.insert(key)
        lock.unlock()
        fetch(url: url, key: key)
        return nil
    }

    private func fetch(url: URL, key: String) {
        if url.isFileURL {
            let image = NSImage(contentsOf: url)
            lock.lock()
            inFlight.remove(key)
            if let image {
                remoteCache[key] = image
                generation += 1
            } else {
                failed.insert(key)
            }
            lock.unlock()
            if image != nil {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.remoteImageLoaded, object: key)
                }
            }
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Supersimple/1.0 (macOS notes app; image embed)", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            let ok: Bool
            if let http = response as? HTTPURLResponse {
                ok = (200..<300).contains(http.statusCode)
            } else {
                ok = data != nil
            }
            let image = ok ? data.flatMap(NSImage.init(data:)) : nil
            self.lock.lock()
            self.inFlight.remove(key)
            if let image {
                self.remoteCache[key] = image
                self.generation += 1
            } else {
                self.failed.insert(key)
            }
            self.lock.unlock()
            if image != nil {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.remoteImageLoaded, object: key)
                }
            }
        }
        task.resume()
    }
}

extension ImageStore: EmbeddedImageProvider {
    func image(for reference: EmbeddedImageRequest) -> NSImage? {
        if let url = Self.remoteURL(from: reference.name) {
            return remoteImage(for: url)
        }
        return image(for: reference.name)
    }
}
