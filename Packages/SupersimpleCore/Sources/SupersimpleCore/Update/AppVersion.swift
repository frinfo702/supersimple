import Foundation

/// Dotted numeric version (`0.1.0`, `v0.1.0.12`). Missing or trailing zeros compare as equal
/// (`0.1.0` == `0.1.0.0`).
public struct AppVersion: Comparable, Hashable, Sendable {
    public let parts: [Int]

    public init(parts: [Int]) {
        self.parts = parts.isEmpty ? [0] : parts
    }

    /// Parses GitHub tags and `CFBundleShortVersionString` values.
    public init(parsing raw: String) {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "v" || trimmed.first == "V" {
            trimmed.removeFirst()
        }
        let parsed = trimmed.split(separator: ".", omittingEmptySubsequences: false).map { component -> Int in
            let digits = component.prefix { $0.isNumber }
            return Int(digits) ?? 0
        }
        self.init(parts: parsed)
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(normalizedParts)
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0..<count {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public var displayString: String {
        parts.map(String.init).joined(separator: ".")
    }

    private var normalizedParts: [Int] {
        var normalized = parts
        while normalized.count > 1, normalized.last == 0 {
            normalized.removeLast()
        }
        return normalized
    }
}
