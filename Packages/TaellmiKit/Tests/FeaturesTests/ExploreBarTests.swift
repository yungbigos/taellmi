import Domain
import Features
import Foundation
import TestSupport
import Testing

private func thought(_ id: String, _ text: String, at date: Date, source: EntrySource = .voice) -> Entry {
    Entry(id: id, createdAt: date, durationSeconds: nil, source: source, folder: "entries/\(id)", text: text)
}

private func day(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar = .current) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

@Suite("The floating bar at the bottom of the window")
struct ExploreBarTests {
    func makeModel() -> (ExploreViewModel, FakeLibrary) {
        let library = FakeLibrary(entries: [
            thought("spoken", "Heute gelaufen.", at: Date().addingTimeInterval(-60)),
            thought("typed", "Liste für den Umzug.", at: Date().addingTimeInterval(-20 * 86_400), source: .typed),
        ])
        return (ExploreViewModel(library: library, autosaveDelay: .zero), library)
    }

    @Test("each view brings its own bar: periods in stack and flow, zoom in time, kinds in space, trash its own")
    func barPerView() async {
        let (model, _) = makeModel()
        let expected: [(Command, ExploreBar)] = [
            (.showStack, .thoughts), (.showFlow, .thoughts), (.showTime, .time), (.showSpace, .space),
        ]
        for (command, bar) in expected {
            await model.perform(command)
            #expect(model.bar == bar)
        }
        await model.perform(.showTrash)
        #expect(model.bar == .trash)
        await model.leaveTrash()
        #expect(!model.showsTrash)
        #expect(model.bar == .space)
    }

    @Test("the month rail is there in flow and time only")
    func railPerView() async {
        let (model, _) = makeModel()
        var shown: [ExploreViewKind: Bool] = [:]
        for (command, view) in [(Command.showStack, ExploreViewKind.stack), (.showFlow, .flow), (.showTime, .time)]
            + [(.showSpace, .space)]
        {
            await model.perform(command)
            shown[view] = model.showsMonthRail
        }
        #expect(shown == [.stack: false, .flow: true, .time: true, .space: false])
        await model.perform(.showFlow)
        await model.perform(.showTrash)
        #expect(!model.showsMonthRail)
    }

    @Test("choosing a period narrows the thoughts")
    func period() async {
        let (model, _) = makeModel()
        await model.refresh()
        await model.choose(period: .week)
        #expect(model.query.period == .week)
        #expect(model.entries.map(\.id) == ["spoken"])
        await model.choose(period: .all)
        #expect(model.entries.map(\.id) == ["spoken", "typed"])
    }

    @Test("spoken and typed are toggles: on shows only that source, again shows everything")
    func sourceToggles() async {
        let (model, _) = makeModel()
        await model.refresh()
        await model.toggle(source: .typed)
        #expect(model.onlySource == .typed)
        #expect(model.entries.map(\.id) == ["typed"])
        await model.toggle(source: .voice)
        #expect(model.onlySource == .voice)
        #expect(model.entries.map(\.id) == ["spoken"])
        await model.toggle(source: .voice)
        #expect(model.onlySource == nil)
        #expect(model.entries.map(\.id) == ["spoken", "typed"])
    }

    @Test("the bar knows how many thoughts are in trash before trash is opened")
    func trashCount() async {
        let (model, _) = makeModel()
        await model.refresh()
        #expect(model.trashCount == 0)
        await model.select("typed")
        await model.trashSelected()
        #expect(model.trashCount == 1)
        #expect(!model.showsTrash)
    }

    @Test("emptying trash deletes every thought in it for good")
    func emptyTrash() async throws {
        let (model, library) = makeModel()
        await model.refresh()
        await model.select("typed")
        await model.trashSelected()
        await model.select("spoken")
        await model.trashSelected()
        await model.perform(.showTrash)
        await model.emptyTrash()
        #expect(model.trashedEntries.isEmpty)
        #expect(model.trashCount == 0)
        #expect(try await library.trashed().isEmpty)
    }
}

extension ExploreBarTests {
    @Test("a trash that can't be read leaves the thoughts showing; only the count waits")
    func trashFailureIsSeparate() async {
        let (model, library) = makeModel()
        await library.failTrashListing()
        await model.refresh()
        #expect(model.entries.map(\.id) == ["spoken", "typed"])
        #expect(model.errorMessage == nil)
    }

    @Test(
        "search opens ⌘K from every view; the bar has no search field of its own", arguments: ExploreViewKind.allCases)
    func searchOpensPalette(view: ExploreViewKind) async {
        let (model, _) = makeModel()
        model.view = view
        await model.perform(.searchThoughts)
        #expect(model.isPaletteOpen)
        #expect(model.view == view)
    }
}

@Suite("The month rail")
struct MonthRailTests {
    @Test("only months that have thoughts, newest first, with how many thoughts each (owner, 2026-10-21)")
    func months() {
        let entries = [
            thought("a", "x", at: day(2026, 10, 20, calendar: berlinCalendar)),
            thought("b", "x", at: day(2026, 10, 2, calendar: berlinCalendar)),
            thought("c", "x", at: day(2026, 8, 14, calendar: berlinCalendar)),
        ]
        let months = MonthRail.months(for: entries, calendar: berlinCalendar)
        #expect(
            months.map(\.start)
                == [10, 8].map { day(2026, $0, 1, calendar: berlinCalendar) }.map {
                    berlinCalendar.startOfDay(for: $0)
                })
        #expect(months.map(\.count) == [2, 1])
        #expect(MonthRail.months(for: [], calendar: berlinCalendar).isEmpty)
    }

    @Test("in flow, choosing a month scrolls to its newest thought")
    func flowJump() async {
        let library = FakeLibrary(entries: [
            thought("oct", "x", at: day(2026, 10, 20)), thought("sep-late", "x", at: day(2026, 9, 28)),
            thought("sep-early", "x", at: day(2026, 9, 3)),
        ])
        let model = ExploreViewModel(library: library, autosaveDelay: .zero, startView: .flow)
        await model.open(selecting: nil)
        let september = model.railMonths.first { Calendar.current.component(.month, from: $0.start) == 9 }
        #expect(september != nil)
        if let september { await model.jump(to: september) }
        #expect(model.scrollTarget == "sep-late")
    }

    @Test("in flow, the rail marks the month of the topmost thought on screen as you scroll")
    func followsScrolling() async {
        let library = FakeLibrary(entries: [
            thought("oct", "x", at: day(2026, 10, 20)), thought("sep", "x", at: day(2026, 9, 28)),
        ])
        let model = ExploreViewModel(library: library, autosaveDelay: .zero, startView: .flow)
        await model.open(selecting: nil)
        model.flowVisible(["sep"])
        #expect(model.currentRailMonth.map { Calendar.current.component(.month, from: $0) } == 9)
        model.flowVisible(["oct", "sep"])
        #expect(model.currentRailMonth.map { Calendar.current.component(.month, from: $0) } == 10)
    }

    @Test("in time, choosing a month shows that whole month and marks it on the rail")
    func timeJump() async {
        let library = FakeLibrary(entries: [
            thought("a", "x", at: day(2026, 10, 20)), thought("b", "x", at: day(2026, 3, 31)),
        ])
        let model = ExploreViewModel(library: library, autosaveDelay: .zero, startView: .time)
        await model.open(selecting: nil)
        let march = model.railMonths.first { Calendar.current.component(.month, from: $0.start) == 3 }
        #expect(march != nil)
        guard let march else { return }
        await model.jump(to: march)
        #expect(model.timeRange.zoom == .month)
        #expect(model.timeRange.start <= march.start)
        #expect(model.timeRange.end == Calendar.current.date(byAdding: .month, value: 1, to: march.start))
        #expect(model.currentRailMonth == march.start)
    }

    @Test("today brings time back to now and keeps the zoom")
    func today() async {
        let model = ExploreViewModel(library: FakeLibrary(entries: []), autosaveDelay: .zero, startView: .time)
        await model.perform(.zoomOutTime)
        await model.perform(.showEarlier)
        await model.perform(.showEarlier)
        let zoom = model.timeRange.zoom
        model.showToday()
        #expect(model.timeRange.zoom == zoom)
        #expect(Calendar.current.isDateInToday(model.timeRange.end.addingTimeInterval(-1)))
    }
}

@Suite("Picking people, places, topics and feelings in space")
struct ConceptPickingTests {
    private let anna = ConceptSummary(id: "concept:person:anna", kind: "person", name: "Anna", thoughtCount: 2)
    private let zurich = ConceptSummary(id: "concept:place:zurich", kind: "place", name: "Zürich", thoughtCount: 2)
    private let work = ConceptSummary(id: "concept:topic:work", kind: "topic", name: "Arbeit", thoughtCount: 1)

    private let a: Entry
    private let b: Entry
    private let c: Entry
    private let library: FakeLibrary
    private var annaDetail: ConceptDetail { ConceptDetail(concept: anna, thoughts: [a, b], appearingWith: [zurich]) }

    init() {
        let now = Date()
        a = thought("a", "Mit Anna in Zürich.", at: now)
        b = thought("b", "Anna ruft an.", at: now.addingTimeInterval(-3_600), source: .typed)
        c = thought("c", "Zürich, Büro.", at: now.addingTimeInterval(-7_200))
        library = FakeLibrary(entries: [a, b, c])
    }

    private func setUp() async -> ExploreViewModel {
        await library.setConcepts(
            [anna, zurich, work],
            details: [
                annaDetail,
                ConceptDetail(concept: zurich, thoughts: [a, c], appearingWith: [anna, work]),
                ConceptDetail(concept: work, thoughts: [c], appearingWith: [zurich]),
            ])
        let model = ExploreViewModel(library: library, autosaveDelay: .zero, startView: .space)
        await model.open(selecting: nil)
        return model
    }

    @Test("picking several shows the thoughts that mention all of them, newest first")
    func intersect() async {
        let model = await setUp()
        await model.togglePick(anna.id)
        #expect(model.pickedConcepts == [anna.id])
        #expect(model.pickedThoughts.map(\.id) == ["a", "b"])
        await model.togglePick(zurich.id)
        #expect(model.pickedThoughts.map(\.id) == ["a"])
    }

    @Test("picking one again takes it away; clearing takes all away")
    func unpick() async {
        let model = await setUp()
        await model.togglePick(anna.id)
        await model.togglePick(zurich.id)
        await model.togglePick(anna.id)
        #expect(model.pickedConcepts == [zurich.id])
        #expect(model.pickedThoughts.map(\.id) == ["a", "c"])
        model.clearPicks()
        #expect(model.pickedConcepts.isEmpty)
        #expect(model.pickedThoughts.isEmpty)
    }

    @Test("the source toggles narrow the picked thoughts too")
    func source() async {
        let model = await setUp()
        await model.togglePick(anna.id)
        await model.toggle(source: .typed)
        #expect(model.pickedThoughts.map(\.id) == ["b"])
    }

    @Test("a kind narrows the concepts shown, and the search finds them by name")
    func narrow() async {
        let model = await setUp()
        #expect(model.visibleConcepts.map(\.id) == [anna.id, zurich.id, work.id])
        model.conceptKindFilter = "place"
        #expect(model.visibleConcepts.map(\.id) == [zurich.id])
        model.conceptKindFilter = nil
        model.conceptSearch = "an"
        #expect(model.visibleConcepts.map(\.id) == [anna.id])
    }

    @Test("picking the same concept twice in a row keeps it once")
    func doublePick() async {
        let model = await setUp()
        async let first: Void = model.togglePick(anna.id)
        async let second: Void = model.togglePick(anna.id)
        _ = await (first, second)
        #expect(model.pickedConcepts.count <= 1)
    }

    @Test("a picked concept that is gone after a change is no longer picked")
    func vanishedPick() async {
        let model = await setUp()
        await model.togglePick(work.id)
        await model.togglePick(anna.id)
        await library.setConcepts([anna, zurich], details: [annaDetail])
        await model.refresh()
        #expect(model.pickedConcepts == [anna.id])
        #expect(model.pickedThoughts.map(\.id) == ["a", "b"])
    }

    @Test("opening a concept from a thought picks just that one")
    func openPicksOne() async {
        let model = await setUp()
        await model.togglePick(anna.id)
        await model.perform(.showFlow)
        await model.openConcept(work.id)
        #expect(model.view == .space)
        #expect(model.pickedConcepts == [work.id])
        #expect(model.pickedThoughts.map(\.id) == ["c"])
    }
}
