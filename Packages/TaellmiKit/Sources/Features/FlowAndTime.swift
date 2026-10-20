import Domain
import Foundation

/// Which Explore view is showing.
nonisolated public enum ExploreViewKind: String, Sendable, CaseIterable {
    case stack, flow, time
    /// For now a list of all concepts; later the 3D world of your thoughts (docs/brand.md).
    case space
}

/// One day in the flow, with its thoughts in reading order.
nonisolated public struct FlowSection: Sendable, Equatable, Identifiable {
    public var day: Date
    public var entries: [Entry]
    public var id: Date { day }
}

nonisolated public enum FlowSections {
    /// Newest day first; within a day, newest thought first (issue #53).
    public static func group(_ entries: [Entry], calendar: Calendar) -> [FlowSection] {
        let sorted = entries.sorted { $0.createdAt > $1.createdAt }
        var sections: [FlowSection] = []
        for entry in sorted {
            let day = calendar.startOfDay(for: entry.createdAt)
            if sections.last?.day == day {
                sections[sections.count - 1].entries.append(entry)
            } else {
                sections.append(FlowSection(day: day, entries: [entry]))
            }
        }
        return sections
    }
}

/// How much time the time view shows at once.
nonisolated public enum TimelineZoom: String, Sendable, CaseIterable, Comparable {
    case day, week, month, year

    var days: Int {
        switch self {
        case .day: 1
        case .week: 7
        // 31, so any calendar month fits when you jump to it from the month rail.
        case .month: 31
        case .year: 365
        }
    }

    public static func < (lhs: TimelineZoom, rhs: TimelineZoom) -> Bool {
        (allCases.firstIndex(of: lhs) ?? 0) < (allCases.firstIndex(of: rhs) ?? 0)
    }
}

/// The span the time view shows: it ends with the anchor's day.
nonisolated public struct TimelineRange: Sendable, Equatable {
    public private(set) var zoom: TimelineZoom
    public private(set) var anchor: Date
    private let calendar: Calendar

    public init(zoom: TimelineZoom, anchor: Date, calendar: Calendar = .current) {
        self.zoom = zoom
        self.anchor = anchor
        self.calendar = calendar
    }

    public var end: Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: anchor)) ?? anchor
    }

    public var start: Date {
        calendar.date(byAdding: .day, value: -zoom.days, to: end) ?? anchor
    }

    /// Shows the span that ends with this day, at the same zoom (e.g. today).
    public mutating func jump(to date: Date) { anchor = date }

    /// Shows a whole calendar month: the span ends where the next month begins.
    public mutating func show(monthStarting start: Date) {
        zoom = .month
        let next = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        anchor = calendar.date(byAdding: .day, value: -1, to: next) ?? start
    }

    public mutating func moveEarlier() { shift(by: -zoom.days) }
    public mutating func moveLater() { shift(by: zoom.days) }

    public mutating func zoomIn() {
        if let index = TimelineZoom.allCases.firstIndex(of: zoom), index > 0 { zoom = TimelineZoom.allCases[index - 1] }
    }

    public mutating func zoomOut() {
        if let index = TimelineZoom.allCases.firstIndex(of: zoom), index < TimelineZoom.allCases.count - 1 {
            zoom = TimelineZoom.allCases[index + 1]
        }
    }

    private mutating func shift(by days: Int) {
        anchor = calendar.date(byAdding: .day, value: days, to: anchor) ?? anchor
    }

    public static func == (lhs: TimelineRange, rhs: TimelineRange) -> Bool {
        lhs.zoom == rhs.zoom && lhs.anchor == rhs.anchor
    }
}

/// One thought on the time axis.
nonisolated public struct TimelineMark: Sendable, Equatable, Identifiable {
    public var id: String
    /// Position in the span, 0 (start) … 1 (end).
    public var x: Double
    /// Relative size, 0…1, from the length of the thought.
    public var size: Double
    public var isSpoken: Bool
    public var preview: String
}

nonisolated public enum TimelineLayout {
    /// Marks for the thoughts inside the range. Size grows with length on a log scale, so long and
    /// short thoughts stay comparable: spoken by recording seconds, typed by word count.
    public static func marks(for entries: [Entry], in range: TimelineRange) -> [TimelineMark] {
        let span = range.end.timeIntervalSince(range.start)
        guard span > 0 else { return [] }
        return entries.compactMap { entry in
            guard entry.createdAt >= range.start, entry.createdAt < range.end else { return nil }
            let isSpoken = entry.source == .voice
            let size: Double
            if isSpoken, let seconds = entry.durationSeconds {
                size = min(1, log1p(seconds) / log1p(600))
            } else {
                let words = entry.text.split(whereSeparator: \.isWhitespace).count
                size = min(1, log1p(Double(words)) / log1p(300))
            }
            let preview = entry.text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
            return TimelineMark(
                id: entry.id, x: entry.createdAt.timeIntervalSince(range.start) / span, size: max(size, 0.15),
                isSpoken: isSpoken, preview: String(preview.prefix(120)))
        }
    }
}
