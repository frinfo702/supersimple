import AppKit
import Foundation
import MarkdownEngine

/// Stores pasted images on disk and serves them to the Markdown engine's
/// `![[name]]` image embeds. Images live in `<appSupport>/Images/`.
/// HTTP(S) / `file:` destinations for `![](url)` are fetched asynchronously
/// and cached in memory; a notification restyles the editor when they land.
final class ImageStore: @unchecked Sendable {
    static let remoteImageLoaded = Notification.Name("supersimple.remoteImageLoaded")

    var didLoadNotification: Notification.Name? { Self.remoteImageLoaded }

    private let imagesDir: URL
    /// Guards the bookkeeping sets/counters. Image caches use `NSCache` (thread-safe,
    /// bounded) so the hot paths never hold the lock during decode.
    private let lock = NSLock()
    /// Local pasted-image memory cache, cost = raw byte size.
    private let cache: NSCache<NSString, NSImage>
    /// Remote `![](url)` images already decoded, cost = raw byte size.
    private let remoteCache: NSCache<NSString, NSImage>
    /// Negative cache so a failed host is not re-fetched on every keystroke; bounded by
    /// NSCache's own eviction instead of an ever-growing Set.
    private let failedCache: NSCache<NSString, NSNumber>
    private var inFlight: Set<String> = []
    /// Bumped whenever the visible image set changes (a paste landed or a remote image
    /// arrived). The engine keys restyle decisions off this, so it must NOT change on
    /// a pure lazy cache fill — that would cause a restyle storm while typing.
    private var contentGeneration = 0
    /// Fallback byte cap for remote images (deter over-large downloads / decoder bombs).
    private static let maxRemoteBytes = 20 * 1024 * 1024
    private let session = URLSession.shared

    init(appSupport: URL) {
        imagesDir = appSupport.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        cache = NSCache()
        cache.totalCostLimit = 64 * 1024 * 1024
        remoteCache = NSCache()
        remoteCache.totalCostLimit = 128 * 1024 * 1024
        failedCache = NSCache()
        failedCache.countLimit = 256
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
        let image = NSImage(data: data)
        lock.lock()
        contentGeneration &+= 1
        lock.unlock()
        if let image {
            cache.setObject(image, forKey: name as NSString, cost: data.count)
        }
        return name
    }

    func image(for name: String) -> NSImage? {
        let key = name as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let url = imagesDir.appendingPathComponent(name)
        guard let img = NSImage(contentsOf: url) else { return nil }
        // A lazy fill does NOT bump contentGeneration (typing must not restyle the doc).
        cache.setObject(img, forKey: key, cost: estimatedCost(of: img))
        return img
    }

    /// Opaque value that changes only when the visible image set changes (paste/remote),
    /// so the editor re-measures on meaningful changes but stays stable while typing.
    func fingerprint() -> AnyHashable {
        lock.lock()
        let gen = contentGeneration
        lock.unlock()
        return gen
    }

    static func remoteURL(from name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "http" || scheme == "https" || scheme == "file" { return url }
        return nil
    }

    private func remoteImage(for url: URL) -> NSImage? {
        let key = url.absoluteString
        let nsKey = key as NSString
        if let cached = remoteCache.object(forKey: nsKey) { return cached }
        if failedCache.object(forKey: nsKey) != nil { return nil }
        lock.lock()
        let alreadyInflight = inFlight.contains(key)
        if !alreadyInflight { inFlight.insert(key) }
        lock.unlock()
        if !alreadyInflight { fetch(url: url, key: key) }
        return nil
    }

    private func fetch(url: URL, key: String) {
        let nsKey = key as NSString
        if url.isFileURL {
            let image = NSImage(contentsOf: url)
            lock.lock()
            inFlight.remove(key)
            lock.unlock()
            if let image {
                remoteCache.setObject(image, forKey: nsKey, cost: estimatedCost(of: image))
                bumpGenerationAndNotify(key: key)
            } else {
                failedCache.setObject(true, forKey: nsKey)
            }
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Supersimple/1.0 (macOS notes app; image embed)", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self else { return }
            var image: NSImage?
            if let data, data.count <= Self.maxRemoteBytes {
                let ok: Bool
                if let http = response as? HTTPURLResponse {
                    ok = (200..<300).contains(http.statusCode)
                } else {
                    ok = true
                }
                if ok { image = NSImage(data: data) }
            }
            self.lock.lock()
            self.inFlight.remove(key)
            self.lock.unlock()
            if let image {
                self.remoteCache.setObject(image, forKey: nsKey, cost: data?.count ?? 0)
                self.bumpGenerationAndNotify(key: key)
            } else {
                self.failedCache.setObject(true, forKey: nsKey)
            }
        }
        task.resume()
    }

    private func bumpGenerationAndNotify(key: String) {
        lock.lock()
        contentGeneration &+= 1
        lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.remoteImageLoaded, object: key)
        }
    }

    private func estimatedCost(of image: NSImage) -> Int {
        guard let rep = image.representations.first else { return 1024 * 1024 }
        let width = rep.pixelsWide, height = rep.pixelsHigh
        guard width > 0, height > 0 else { return 1024 * 1024 }
        return min(max(width * height * 4, 4096), 64 * 1024 * 1024)
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
