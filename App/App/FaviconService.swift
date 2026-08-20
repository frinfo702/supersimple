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
    /// Bounded negative cache so a host that failed once is not re-requested on every
    /// keystroke. NSCache evicts under pressure instead of an ever-growing Set.
    private let failedCache: NSCache<NSString, NSNumber> = {
        let c = NSCache<NSString, NSNumber>()
        c.countLimit = 256
        return c
    }()
    private let session = URLSession.shared

    /// Reused across every call — the detector and regex never vary.
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let markdownLinkRegex = try? NSRegularExpression(pattern: #"\[[^\]]*\]\(([^)\s]+)\)"#)

    /// Hostnames in `body` worth prefetching: detector hits plus markdown `[text](url)`.
    static func hosts(in body: String) -> Set<String> {
        var hosts: Set<String> = []
        let ns = body as NSString
        let full = NSRange(location: 0, length: ns.length)
        linkDetector?.enumerateMatches(in: body, options: [], range: full) { match, _, _ in
            if let host = match?.url?.host { hosts.insert(host.lowercased()) }
        }
        if let re = markdownLinkRegex {
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
            let nsKey = key as NSString
            if failedCache.object(forKey: nsKey) != nil { continue }
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
            failedCache.setObject(true, forKey: key as NSString)
            return
        }
        let task = session.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            guard let data, let img = NSImage(data: data) else {
                self.lock.lock()
                self.inFlight.remove(key)
                self.lock.unlock()
                self.failedCache.setObject(true, forKey: key as NSString)
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
