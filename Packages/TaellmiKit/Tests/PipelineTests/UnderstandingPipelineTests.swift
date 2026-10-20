import Config
import Domain
import Foundation
import Persistence
import Pipeline
import TestSupport
import Testing

@Suite("Concepts and summaries in the pipeline")
struct UnderstandingPipelineTests {
    typealias Harness = PipelineRunnerTests.Harness

    private let longText = Array(
        repeating: "Heute habe ich lange mit Marleen über die Heizung in der Wohnung in Giesing gesprochen.", count: 4
    ).joined(separator: " ")

    private func addTypedEntry(_ harness: Harness, text: String) throws -> Entry {
        let entry = try harness.files.createTypedEntry(text: text, createdAt: sampleDate)
        try harness.index.upsert(entry, transcript: nil)
        return entry
    }

    @Test("a long thought gets its concepts, linked to its words, and a one-sentence summary")
    func long() async throws {
        let model = FakeLanguageModel(
            concepts: [("Marleen", "person", "Marleen"), ("Heizung", "topic", "Heizung")],
            summary: "Mit Marleen über die Heizung in Giesing gesprochen.")
        let harness = try Harness(languageModel: model)
        let entry = try addTypedEntry(harness, text: longText)

        await harness.runUntilSettled()

        let read = try #require(try harness.understandings.understanding(entryID: entry.id))
        #expect(read.summary == "Mit Marleen über die Heizung in Giesing gesprochen.")
        #expect(read.concepts.map(\.name) == ["Marleen", "Heizung"])
        #expect(read.concepts.first?.utf16Ranges.count == 4)
        #expect(await model.prompts.first?.contains(longText) == true)
    }

    @Test("a summary with words the thought doesn't contain is not shown, the concepts are")
    func ungroundedSummary() async throws {
        let model = FakeLanguageModel(
            concepts: [("Marleen", "person", "Marleen")], summary: "Streit mit Marleen wegen der Miete.")
        let harness = try Harness(languageModel: model)
        let entry = try addTypedEntry(harness, text: longText)

        await harness.runUntilSettled()

        let read = try #require(try harness.understandings.understanding(entryID: entry.id))
        #expect(read.summary == nil)
        #expect(read.concepts.map(\.name) == ["Marleen"])
    }

    @Test("a short thought gets concepts but no summary")
    func short() async throws {
        let model = FakeLanguageModel(concepts: [("Marleen", "person", "Marleen")])
        let harness = try Harness(languageModel: model)
        let entry = try addTypedEntry(harness, text: "Kurz mit Marleen telefoniert.")

        await harness.runUntilSettled()

        let read = try #require(try harness.understandings.understanding(entryID: entry.id))
        #expect(read.summary == nil)
        #expect(read.concepts.map(\.name) == ["Marleen"])
        #expect(await model.prompts.count == 1)
    }

    @Test("a concept the model names but the thought doesn't contain is never stored")
    func noInvention() async throws {
        let model = FakeLanguageModel(concepts: [("einsam", "emotion", "einsam")])
        let harness = try Harness(languageModel: model)
        let entry = try addTypedEntry(harness, text: "Die Heizung gluckert wieder.")

        await harness.runUntilSettled()

        #expect(try harness.understandings.understanding(entryID: entry.id)?.concepts.isEmpty == true)
    }

    @Test("without Apple Intelligence nothing is made; once it is on, existing thoughts are understood")
    func waitsForAvailability() async throws {
        let model = FakeLanguageModel(concepts: [("Marleen", "person", "Marleen")], isAvailable: false)
        let harness = try Harness(languageModel: model)
        let entry = try addTypedEntry(harness, text: "Kurz mit Marleen telefoniert.")

        await harness.runUntilSettled()
        #expect(try harness.understandings.understanding(entryID: entry.id) == nil)

        await model.setAvailable(true)
        await harness.runUntilSettled()
        #expect(try harness.understandings.understanding(entryID: entry.id)?.concepts.count == 1)
    }

    @Test("editing a thought understands it again")
    func edited() async throws {
        let model = FakeLanguageModel(concepts: [("Marleen", "person", "Marleen"), ("Jonas", "person", "Jonas")])
        let harness = try Harness(languageModel: model)
        var entry = try addTypedEntry(harness, text: "Kurz mit Marleen telefoniert.")
        await harness.runUntilSettled()

        entry.text = "Kurz mit Jonas telefoniert."
        try harness.index.upsert(entry, transcript: nil)
        await harness.runUntilSettled()

        #expect(try harness.understandings.understanding(entryID: entry.id)?.concepts.map(\.name) == ["Jonas"])
    }
}

@Suite("When the model declines a summary")
struct DeclinedSummaryTests {
    typealias Harness = PipelineRunnerTests.Harness

    @Test("the concepts are still kept")
    func keepsConcepts() async throws {
        let model = FakeLanguageModel(concepts: [("Marleen", "person", "Marleen")])
        await model.declineSummaries()
        let harness = try Harness(languageModel: model)
        let text = Array(repeating: "Heute ein langer Gedanke über Marleen und vieles mehr.", count: 6).joined(
            separator: " ")
        let entry = try harness.files.createTypedEntry(text: text, createdAt: sampleDate)
        try harness.index.upsert(entry, transcript: nil)

        await harness.runUntilSettled()

        let read = try #require(try harness.understandings.understanding(entryID: entry.id))
        #expect(read.summary == nil)
        #expect(read.concepts.map(\.name) == ["Marleen"])
    }
}
