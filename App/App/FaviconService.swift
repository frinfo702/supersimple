import AppKit
import MarkdownEngine

/// Fetches and caches site favicons (via Google's favicon service) so links can
/// render a small icon inline. Lookup is synchronous from cache; prefetching is
/// async and posts `faviconLoaded` when a new icon arrives so the editor can restyle.
final class FaviconService: FaviconProvider, @unchecked Sendable {
    static let faviconLoaded = Notification.Name("supersimple.faviconLoaded")

    var didLoadNotification: Notification.Name? { Self.faviconLoaded }

    private let lock = NSLock()
    private var cache: [String: NSImage] = [:]
    private var inFlight: Set<String> = []
    private let session = URLSession.shared

    /// Hostnames in `body` worth prefetching: detector hits plus markdown `[text](url)`.
    static func hosts(in body: String) -> Set<String> {
        var hosts: Set<String> = []
        let ns = body as NSString
        let full = NSRange(location: 0, length: ns.length)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        detector?.enumerateMatches(in: body, options: [], range: full) { match, _, _ in
            if let host = match?.url?.host { hosts.insert(host.lowercased()) }
        }
        if let re = try? NSRegularExpression(pattern: #"\[[^\]]*\]\(([^)\s]+)\)"#) {
            for match in re.matches(in: body, range: full) where match.numberOfRanges >= 2 {
                var urlString = ns.substring(with: match.range(at: 1))
                if !urlString.contains("://") { urlString = "https://\(urlString)" }
                if let host = URL(string: urlString)?.host { hosts.insert(host.lowercased()) }
            }
        }
        return hosts
    }

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
        let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
        guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(encoded)&sz=32") else {
            lock.lock()
            inFlight.remove(key)
            lock.unlock()
            return
        }
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
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.faviconLoaded, object: key)
            }
        }
        task.resume()
    }
}
