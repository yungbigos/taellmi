import Domain
import Foundation
import Persistence
import TestSupport
import Testing

@Suite("Searching and filtering Entries")
struct EntrySearchTests {
    private func indexed(_ items: [(id: String, text: String, daysAgo: Double, source: EntrySource)]) throws
        -> EntryIndex
    {
        let index = EntryIndex(database: try makeDatabase())
        for item in items {
            try index.upsert(
                Entry(
                    id: item.id, createdAt: sampleDate.addingTimeInterval(-item.daysAgo * 86_400), durationSeconds: nil,
                    source: item.source, folder: "entries/\(item.id)", text: item.text),
                transcript: nil)
        }
        return index
    }

    private let samples: [(id: String, text: String, daysAgo: Double, source: EntrySource)] = [
        ("a", "Meine Zukunftsangst wegen dem Job ist heute kleiner.", 0, .voice),
        ("b", "Im Büro mit Marleen über das Projekt gesprochen. Honestly, gut gelaufen.", 3, .typed),
        ("c", "Straße nass, Spaziergang trotzdem schön.", 40, .voice),
    ]

    @Test(
        "finds parts of words, case-insensitively, newest first",
        arguments: [("angst", ["a"]), ("BÜRO", ["b"]), ("honest", ["b"])])
    func findsWordParts(query: String, expected: [String]) throws {
        let found = try indexed(samples).search(EntryQuery(text: query), now: sampleDate, calendar: berlinCalendar)
        #expect(found.map(\.id) == expected)
    }

    @Test("every word must match")
    func allWords() throws {
        let index = try indexed(samples)
        #expect(
            try index.search(EntryQuery(text: "büro marleen"), now: sampleDate, calendar: berlinCalendar).map(\.id) == [
                "b"
            ])
        #expect(try index.search(EntryQuery(text: "büro straße"), now: sampleDate, calendar: berlinCalendar).isEmpty)
    }

    @Test("short search words (under three letters) still work")
    func shortWords() throws {
        #expect(
            try indexed(samples).search(EntryQuery(text: "Jo"), now: sampleDate, calendar: berlinCalendar).map(\.id)
                == ["a"])
    }

    @Test("an empty search lists everything, newest first")
    func emptyQuery() throws {
        #expect(
            try indexed(samples).search(EntryQuery(), now: sampleDate, calendar: berlinCalendar).map(\.id)
                == ["a", "b", "c"])
    }

    @Test(
        "filters by time span",
        arguments: [(EntryQuery.Period.today, ["a"]), (.week, ["a", "b"]), (.year, ["a", "b", "c"])])
    func period(period: EntryQuery.Period, expected: [String]) throws {
        let found = try indexed(samples).search(EntryQuery(period: period), now: sampleDate, calendar: berlinCalendar)
        #expect(found.map(\.id) == expected)
    }

    @Test("filters by Source")
    func source() throws {
        let found = try indexed(samples).search(
            EntryQuery(sources: [.typed]), now: sampleDate, calendar: berlinCalendar)
        #expect(found.map(\.id) == ["b"])
    }

    @Test("an edited Text is found by its new words, not its old ones")
    func editedText() throws {
        let index = try indexed(samples)
        var entry = try #require(try index.entry(id: "c"))
        entry.text = "Regen und Kaffee."
        try index.upsert(entry, transcript: nil)
        #expect(
            try index.search(EntryQuery(text: "kaffee"), now: sampleDate, calendar: berlinCalendar).map(\.id) == ["c"])
        #expect(try index.search(EntryQuery(text: "spazier"), now: sampleDate, calendar: berlinCalendar).isEmpty)
    }
}
