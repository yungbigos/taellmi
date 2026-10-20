import Domain
import Foundation
import SwiftUI

/// Spacing steps from the brand tokens (`space.scale`), on a 4 pt grid.
public enum BrandSpace: String, CaseIterable, Sendable {
    case xxs, xs, s, m, l, xl, xxl, xxxl
}

extension BrandTokens {
    /// A spacing step in points.
    public func space(_ step: BrandSpace) -> Double {
        space.scale[step.rawValue] ?? 0
    }

    /// The extra line spacing a type style needs to reach its line height (`line` × size). Fonts already set
    /// lines about 1.2 × their size apart, so only the room above that is added.
    func lineSpacing(_ token: String) -> Double {
        guard let style = type.scale[token] else { return 0 }
        return max(0, style.line - Self.naturalLineHeight) * style.size * type.base.sizePt
    }

    private static let naturalLineHeight = 1.2
}

extension Optional where Wrapped == BrandTokens {
    /// A spacing step, or nil (the macOS default) when there are no tokens.
    func space(_ step: BrandSpace) -> CGFloat? {
        map { CGFloat($0.space(step)) }
    }
}

/// The one quiet line above an open thought: day, time, how it came in, and how long it is.
enum ThoughtMeta {
    static func line(
        createdAt: Date, source: EntrySource, durationSeconds: Double?, locale: Locale = .current,
        calendar: Calendar = .current
    ) -> String {
        var day = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar)
        day.timeZone = calendar.timeZone
        var time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar)
        time.timeZone = calendar.timeZone
        var parts = [
            createdAt.formatted(day.weekday(.abbreviated)), createdAt.formatted(time), sourceWord(source),
        ]
        if let durationSeconds {
            parts.append(Duration.seconds(durationSeconds).formatted(.time(pattern: .minuteSecond)))
        }
        return parts.joined(separator: " · ").lowercased(with: locale)
    }

    /// The date at the end of a one-line row: the time today, day and month this year, else with the year.
    static func short(
        _ date: Date, now: Date = .now, locale: Locale = .current, calendar: Calendar = .current
    ) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar)
        style.timeZone = calendar.timeZone
        let text: String
        if calendar.isDate(date, inSameDayAs: now) {
            var time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar)
            time.timeZone = calendar.timeZone
            text = date.formatted(time)
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            text = date.formatted(style.day().month(.abbreviated))
        } else {
            text = date.formatted(style.day().month(.abbreviated).year())
        }
        return text.lowercased(with: locale)
    }

    static func sourceWord(_ source: EntrySource) -> String {
        switch source {
        case .typed: "typed"
        case .voice: "spoken"
        default: "from " + source.rawValue.replacingOccurrences(of: "_", with: " ")
        }
    }

    /// The symbol that stands for how a thought came in.
    static func sourceSymbol(_ source: EntrySource) -> String {
        switch source {
        case .typed: "keyboard"
        case .voice: "waveform"
        default: "note.text"
        }
    }
}
