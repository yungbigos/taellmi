import Domain
import Foundation

/// What the floating bar at the bottom of the window holds. There is no sidebar: the bar follows the view
/// (issue #54).
nonisolated public enum ExploreBar: Sendable, Equatable {
    /// stack and flow: periods, search, spoken / typed and trash.
    case thoughts
    /// time: zoom, earlier / later / today, spoken / typed and trash.
    case time
    /// space: kinds, finding and picking concepts, spoken / typed and trash.
    case space
    /// trash: back to your thoughts, how many are in trash, empty trash.
    case trash
}

/// One month on the month rail next to flow and time.
nonisolated public struct RailMonth: Sendable, Equatable, Identifiable {
    /// The first moment of the month.
    public var start: Date
    /// Thoughts in it; months without any stay on the rail, so the rail reads as time.
    public var count: Int
    public var id: Date { start }
}

nonisolated public enum MonthRail {
    /// Every month from the newest thought's back to the oldest thought's, newest first.
    public static func months(for entries: [Entry], calendar: Calendar) -> [RailMonth] {
        guard let newest = entries.map(\.createdAt).max(), let oldest = entries.map(\.createdAt).min(),
            let first = startOfMonth(newest, calendar: calendar), let last = startOfMonth(oldest, calendar: calendar)
        else { return [] }
        var counts: [Date: Int] = [:]
        for entry in entries {
            if let month = startOfMonth(entry.createdAt, calendar: calendar) { counts[month, default: 0] += 1 }
        }
        var months: [RailMonth] = []
        var month = first
        while month >= last {
            months.append(RailMonth(start: month, count: counts[month] ?? 0))
            guard let earlier = calendar.date(byAdding: .month, value: -1, to: month) else { break }
            month = earlier
        }
        return months
    }

    static func startOfMonth(_ date: Date, calendar: Calendar) -> Date? {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))
    }
}
