import Domain
import Testing

@testable import FoundationModelsEngine

@Suite("Turning a prompt's output schema into guidance for Apple's model")
struct GenerationSchemaBuilderTests {
    @Test("objects with strings, enums, numbers and arrays of objects are supported")
    func supported() throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "summary": .object(["type": .string("string")]),
                "count": .object(["type": .string("integer")]),
                "concepts": .object([
                    "type": .string("array"), "maxItems": .number(12),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "name": .object(["type": .string("string")]),
                            "kind": .object([
                                "type": .string("string"),
                                "enum": .array([.string("person"), .string("place")]),
                            ]),
                        ]),
                        "required": .array([.string("name"), .string("kind")]),
                    ]),
                ]),
            ]),
            "required": .array([.string("concepts")]),
        ])
        _ = try GenerationSchemaBuilder.schema(from: schema)
    }

    @Test("an unknown type is refused with its location, never guessed", arguments: ["null", "date"])
    func unsupported(type: String) {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object(["when": .object(["type": .string(type)])]),
        ])
        #expect(throws: LanguageModelError.unsupportedSchema("Answer_when has type \(type)")) {
            try GenerationSchemaBuilder.schema(from: schema)
        }
    }
}
