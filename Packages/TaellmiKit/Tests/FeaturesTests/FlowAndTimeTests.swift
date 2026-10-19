import Domain
import Features
import Foundation
import TestSupport
import Testing

private func thought(_ id: String, _ text: String, daysAgo: Double, source: EntrySource = .voice, seconds: Double? = 30)
    -> Entry
{
    Entry(
        id: id, createdAt: sampleDate.addingTimeInterval(-daysAgo * 86_400), durationSeconds: seconds, source: source,
        folder: "entries/\(id)", text: text)
}

@Suite("Switching views")
struct ViewSwitchingTests {
    @Test("commands switch between stack, flow and time")
    func switches() async {
        let model = ExploreViewModel(library: FakeLibrary(entries: []), autosaveDelay: .zero)
        await model.perform(.showFlow)
        #expect(model.view == .flow)
        await model.perform(.showTime)
        #expect(model.view == .time)
        await model.perform(.showStack)
        #expect(model.view == .stack)
    }
}

@Suite("flow: every thought as one long note")
struct FlowTests {
    @Test("oldest at the top, newest at the bottom, grouped by day")
    func sections() {
        let sections = FlowSections.group(
            [thought("new", "c", daysAgo: 0), thought("mid", "b", daysAgo: 0.01), thought("old", "a", daysAgo: 2)],
            calendar: berlinCalendar)
        #expect(sections.map { $0.entries.map(\.id) } == [["old"], ["mid", "new"]])
        #expect(
            sections.first.map {
                berlinCalendar.isDate($0.day, inSameDayAs: sampleDate.addingTimeInterval(-2 * 86_400))
            } == true)
    }

    @Test("editing a thought in the flow saves it")
    func inlineEdit() async {
        let library = FakeLibrary(entries: [thought("a", "Alt.", daysAgo: 1)])
        let model = ExploreViewModel(library: library, autosaveDelay: .zero)
        await model.refresh()
        await model.saveFlowText(id: "a", text: "Neu geschrieben.")
        #expect(await library.savedTexts["a"] == "Neu geschrieben.")
    }

    @Test("with a search, matches are listed in reading order and next/previous jump between them, wrapping")
    func matches() async {
        let library = FakeLibrary(entries: [
            thought("a", "Marleen angerufen.", daysAgo: 3), thought("b", "Kaffee.", daysAgo: 2),
            thought("c", "Mit Marleen gelaufen.", daysAgo: 1),
        ])
        let model = ExploreViewModel(library: library, autosaveDelay: .zero)
        model.view = .flow
        model.query.text = "marleen"
        await model.refresh()
        #expect(model.flowMatches == ["a", "c"])
        #expect(model.currentMatch == "a")
        await model.perform(.nextMatch)
        #expect(model.currentMatch == "c")
        await model.perform(.nextMatch)
        #expect(model.currentMatch == "a")
        await model.perform(.previousMatch)
        #expect(model.currentMatch == "c")
    }
}

@Suite("time: a zoomable time axis")
struct TimelineTests {
    @Test(
        "each zoom level shows a span ending with the anchor's day",
        arguments: [(TimelineZoom.day, 1.0), (.week, 7.0), (.month, 30.0), (.year, 365.0)])
    func spans(zoom: TimelineZoom, days: Double) {
        let range = TimelineRange(zoom: zoom, anchor: sampleDate, calendar: berlinCalendar)
        #expect(
            range.end == berlinCalendar.date(byAdding: .day, value: 1, to: berlinCalendar.startOfDay(for: sampleDate)))
        #expect(abs(range.end.timeIntervalSince(range.start) - days * 86_400) < 3_700, "within a DST hour")
    }

    @Test("earlier and later move by one span; zoom steps through day, week, month, year")
    func navigate() {
        var range = TimelineRange(zoom: .week, anchor: sampleDate, calendar: berlinCalendar)
        let start = range.start
        range.moveEarlier()
        #expect(abs(range.end.timeIntervalSince(start)) < 3_700)
        range.moveLater()
        #expect(abs(range.start.timeIntervalSince(start)) < 3_700)
        range.zoomOut()
        #expect(range.zoom == .month)
        range.zoomIn()
        range.zoomIn()
        range.zoomIn()
        #expect(range.zoom == .day)
    }

    @Test("marks sit at their time within the span, sized by length, shaped by Source")
    func marks() {
        let range = TimelineRange(zoom: .week, anchor: sampleDate, calendar: berlinCalendar)
        let marks = TimelineLayout.marks(
            for: [
                thought("long", "x", daysAgo: 1, seconds: 600), thought("short", "x", daysAgo: 2, seconds: 5),
                thought("typed", String(repeating: "wort ", count: 40), daysAgo: 3, source: .typed, seconds: nil),
                thought("outside", "x", daysAgo: 30),
            ], in: range)
        #expect(marks.map(\.id).sorted() == ["long", "short", "typed"])
        let long = marks.first { $0.id == "long" }!
        let short = marks.first { $0.id == "short" }!
        #expect(long.x > short.x)
        #expect((0...1).contains(long.x))
        #expect(long.size > short.size)
        #expect(marks.first { $0.id == "typed" }?.isSpoken == false)
        #expect(long.isSpoken)
    }
}
