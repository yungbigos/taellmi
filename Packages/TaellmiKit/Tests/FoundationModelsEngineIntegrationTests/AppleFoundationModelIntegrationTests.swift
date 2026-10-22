import Domain
import FoundationModels
import Testing

@testable import FoundationModelsEngine

/// Runs only where Apple Intelligence is turned on.
@Suite(
    "Apple's on-device model, for real",
    .enabled(if: SystemLanguageModel.default.availability == .available))
struct AppleFoundationModelIntegrationTests {
    @Test("a German thought yields an answer that follows the schema")
    func followsSchema() async throws {
        let model = AppleFoundationModel(temperature: 0)
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "people": .object(["type": .string("array"), "items": .object(["type": .string("string")])])
            ]),
            "required": .array([.string("people")]),
        ])
        let answer = try await model.generate(
            prompt: "Welche Personen werden genannt? Text: Heute mit Kim und Sam im Englischen Garten.",
            schema: schema)
        let people = answer.objectValue?["people"]?.arrayValue?.compactMap(\.stringValue) ?? []
        #expect(people.contains { $0.contains("Kim") })
    }
}
