import AppKit
import MarkdownEngine

/// Serves bundled SVG icons for common sites, then fetches and caches other favicons
/// via Google's favicon service. Lookup is synchronous from cache; prefetching is async
/// and posts `faviconLoaded` when a new icon arrives so the editor can restyle.
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

    /// Stable asset names are also exposed to tests so URL routing can be verified
    /// without relying on AppKit's bundle/image cache.
    enum PreparedIcon: String, CaseIterable {
        case github = "SiteGitHub"
        case githubIssue = "SiteGitHubIssue"
        case githubPullRequest = "SiteGitHubPullRequest"
        case linear = "SiteLinear"
        case huggingFace = "SiteHuggingFace"
        case gitLab = "SiteGitLab"
        case figma = "SiteFigma"
        case notion = "SiteNotion"
        case jira = "SiteJira"
        case stackOverflow = "SiteStackOverflow"
        case youtube = "SiteYouTube"
        case cvf = "SiteCVF"
        case arXiv = "SiteArXiv"
        case x = "SiteX"

        var image: NSImage? { NSImage(named: rawValue) }
    }

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
        if let prepared = Self.preparedIcon(forHost: host) {
            return prepared.image
        }
        lock.lock()
        defer { lock.unlock() }
        return cache[host.lowercased()]
    }

    /// Uses the full path for resource-specific icons, falling back to the site's logo.
    func favicon(for url: URL) -> NSImage? {
        if let prepared = Self.preparedIcon(for: url) {
            return prepared.image
        }
        guard let host = url.host else { return nil }
        return favicon(for: host)
    }

    static func preparedIcon(for url: URL) -> PreparedIcon? {
        guard let host = url.host else { return nil }
        let normalizedHost = normalize(host)
        if normalizedHost == "github.com" {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 4, Int(parts[3]) != nil {
                if parts[2] == "issues" { return .githubIssue }
                if parts[2] == "pull" { return .githubPullRequest }
            }
            return .github
        }
        return preparedIcon(forHost: normalizedHost)
    }

    private static func preparedIcon(forHost host: String) -> PreparedIcon? {
        let host = normalize(host)
        if matches(host, domain: "github.com") { return .github }
        if matches(host, domain: "linear.app") { return .linear }
        if matches(host, domain: "huggingface.co") { return .huggingFace }
        if matches(host, domain: "gitlab.com") { return .gitLab }
        if matches(host, domain: "figma.com") { return .figma }
        if matches(host, domain: "notion.so") || matches(host, domain: "notion.site") { return .notion }
        if matches(host, domain: "atlassian.net") { return .jira }
        if matches(host, domain: "stackoverflow.com") { return .stackOverflow }
        if matches(host, domain: "youtube.com") || host == "youtu.be" { return .youtube }
        if matches(host, domain: "thecvf.com") || matches(host, domain: "cv-foundation.org") {
            return .cvf
        }
        if matches(host, domain: "arxiv.org") { return .arXiv }
        if matches(host, domain: "x.com") || matches(host, domain: "twitter.com") || host == "t.co" {
            return .x
        }
        return nil
    }

    private static func normalize(_ host: String) -> String {
        let lowercased = host.lowercased()
        return lowercased.hasPrefix("www.") ? String(lowercased.dropFirst(4)) : lowercased
    }

    private static func matches(_ host: String, domain: String) -> Bool {
        host == domain || host.hasSuffix(".\(domain)")
    }

    /// Asynchronously fetches favicons for hosts that aren't cached yet.
    func prefetch(hosts: [String]) {
        for host in hosts {
            let key = host.lowercased()
            if Self.preparedIcon(forHost: key) != nil { continue }
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
