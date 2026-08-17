import AppKit
import MarkdownEngine

/// Fetches and caches site favicons (via Google's favicon service) so links can
/// render a small icon inline. Lookup is synchronous from cache; prefetching is
/// async and posts `faviconLoaded` when a new icon arrives so the app can restyle.
final class FaviconService: FaviconProvider, @unchecked Sendable {
    static let faviconLoaded = Notification.Name("supersimple.faviconLoaded")

    private let lock = NSLock()
    private var cache: [String: NSImage] = [:]
    private var inFlight: Set<String> = []
    private let session = URLSession.shared

    /// Synchronous cached lookup (used by the engine during styling).
    func favicon(for host: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache[host.lowercased()]
    }

    /// Asynchronously fetches favicons for hosts that aren't cached yet.
    func prefetch(hosts: [String]) {
        for host in hosts {
            let key = host.lowercased()
            lock.lock()
            let known = cache[key] != nil || inFlight.contains(key)
            if !known { inFlight.insert(key) }
            lock.unlock()
            if !known { fetch(key: key) }
        }
    }

    private func fetch(key: String) {
        guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(key)&sz=32") else { return }
        let task = session.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let img = NSImage(data: data) else {
                self?.lock.lock()
                self?.inFlight.remove(key)
                self?.lock.unlock()
                return
            }
            self.lock.lock()
            self.cache[key] = img
            self.inFlight.remove(key)
            self.lock.unlock()
            NotificationCenter.default.post(name: Self.faviconLoaded, object: key)
        }
        task.resume()
    }
}
