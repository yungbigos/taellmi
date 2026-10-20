import Domain
import Foundation
import Testing

@testable import Features

private func shippedTokens() throws -> BrandTokens {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../Sources/Config/Resources/Seeds/brand.json").standardizedFileURL
    return try BrandTokens(json: try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)))
}

@Suite("Spacing and line height come from the brand tokens")
struct BrandLayoutTests {
    @Test("every spacing step the views use is in the shipped tokens, on a 4 pt grid from s up")
    func spacingScale() throws {
        let tokens = try shippedTokens()
        for step in BrandSpace.allCases {
            let value = try #require(tokens.space.scale[step.rawValue], "missing space \(step.rawValue)")
            #expect(tokens.space(step) == value)
        }
        #expect(tokens.space(.l) == 16)
        #expect(tokens.space.readingWidthPt == 680)
    }

    @Test("a thought's line height adds the room above the font's natural 1.2 as line spacing")
    func lineSpacing() throws {
        let tokens = try shippedTokens()
        let thought = try #require(tokens.type.scale["text.thought"])
        let expected = (thought.line - 1.2) * thought.size * tokens.type.base.sizePt
        #expect(abs(tokens.lineSpacing("text.thought") - expected) < 0.001)
        #expect(tokens.lineSpacing("display.moment") == 0)
        #expect(tokens.lineSpacing("no.such.token") == 0)
    }

    @Test("the open thought's details read as one quiet line: day, time, how it came in, length")
    func metaLine() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let date = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 15, minute: 28)))
        let line = ThoughtMeta.line(
            createdAt: date, source: .voice, durationSeconds: 35, locale: Locale(identifier: "en_GB"),
            calendar: calendar)
        #expect(line == "tue, 20 oct 2026 · 15:28 · spoken · 0:35")
        let typed = ThoughtMeta.line(
            createdAt: date, source: .typed, durationSeconds: nil, locale: Locale(identifier: "en_GB"),
            calendar: calendar)
        #expect(typed == "tue, 20 oct 2026 · 15:28 · typed")
        let imported = ThoughtMeta.line(
            createdAt: date, source: .appleNotes, durationSeconds: nil, locale: Locale(identifier: "en_GB"),
            calendar: calendar)
        #expect(imported == "tue, 20 oct 2026 · 15:28 · from apple notes")
    }

    @Test("a row in the list ends in a short date: the time today, day and month this year, else the year too")
    func shortDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let locale = Locale(identifier: "en_GB")
        func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9) throws -> Date {
            try #require(calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: 5)))
        }
        let now = try date(2026, 10, 20, 18)
        let today = ThoughtMeta.short(try date(2026, 10, 20), now: now, locale: locale, calendar: calendar)
        #expect(today == "9:05")
        #expect(ThoughtMeta.short(try date(2026, 10, 19), now: now, locale: locale, calendar: calendar) == "19 oct")
        #expect(
            ThoughtMeta.short(try date(2025, 3, 2), now: now, locale: locale, calendar: calendar) == "2 mar 2025")
    }
}
