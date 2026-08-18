import Foundation

/// Recency buckets for the library list. Search results are not grouped.
enum NoteRecencyGroup: Int, CaseIterable, Identifiable {
    case today
    case yesterday
    case previous7Days
    case older

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .previous7Days: "Previous 7 Days"
        case .older: "Older"
        }
    }

    static func group(for date: Date, now: Date = Date()) -> NoteRecencyGroup {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return .yesterday
        }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: now), date >= weekAgo {
            return .previous7Days
        }
        return .older
    }
}
