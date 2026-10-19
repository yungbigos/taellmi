import Foundation

/// What the Explore list shows: a search text plus filters.
public struct EntryQuery: Sendable, Equatable {
    public enum Period: String, Sendable, CaseIterable {
        case all, today, week, month, year
    }

    public var text: String
    public var period: Period
    /// nil means every Source.
    public var sources: Set<EntrySource>?

    public init(text: String = "", period: Period = .all, sources: Set<EntrySource>? = nil) {
        self.text = text
        self.period = period
        self.sources = sources
    }

    /// The earliest creation date the period allows, or nil for all time.
    public func earliestDate(now: Date, calendar: Calendar) -> Date? {
        switch period {
        case .all: nil
        case .today: calendar.startOfDay(for: now)
        case .week: now.addingTimeInterval(-7 * 86_400)
        case .month: now.addingTimeInterval(-30 * 86_400)
        case .year: now.addingTimeInterval(-365 * 86_400)
        }
    }

    /// Search words, lowercased.
    public var words: [String] {
        text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
