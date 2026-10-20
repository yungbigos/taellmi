import Domain
import FoundationModels

/// Turns a prompt's JSON Schema (from config) into a schema Apple's model is guided by. Supports what the
/// prompts need: objects, arrays, strings (with `enum`), numbers, integers and booleans.
enum GenerationSchemaBuilder {
    static func schema(from json: JSONValue) throws -> GenerationSchema {
        try GenerationSchema(root: dynamic(json, name: "Answer"), dependencies: [])
    }

    private static func dynamic(_ json: JSONValue, name: String) throws -> DynamicGenerationSchema {
        guard case .object(let node) = json else {
            throw LanguageModelError.unsupportedSchema("\(name) is not an object")
        }
        let description = node["description"]?.stringValue
        switch node["type"]?.stringValue {
        case "object":
            guard case .object(let properties)? = node["properties"] else {
                throw LanguageModelError.unsupportedSchema("\(name) has no properties")
            }
            let required = Set(node["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
            return DynamicGenerationSchema(
                name: name, description: description,
                properties: try properties.keys.sorted().map { key in
                    DynamicGenerationSchema.Property(
                        name: key, description: properties[key]?.objectValue?["description"]?.stringValue,
                        schema: try dynamic(properties[key] ?? .null, name: name + "_" + key),
                        isOptional: !required.contains(key))
                })
        case "array":
            return DynamicGenerationSchema(
                arrayOf: try dynamic(node["items"] ?? .null, name: name + "_item"),
                maximumElements: node["maxItems"]?.doubleValue.map(Int.init))
        case "string":
            if let choices = node["enum"]?.arrayValue?.compactMap(\.stringValue), !choices.isEmpty {
                return DynamicGenerationSchema(name: name, description: description, anyOf: choices)
            }
            return DynamicGenerationSchema(type: String.self)
        case "number": return DynamicGenerationSchema(type: Double.self)
        case "integer": return DynamicGenerationSchema(type: Int.self)
        case "boolean": return DynamicGenerationSchema(type: Bool.self)
        case let other: throw LanguageModelError.unsupportedSchema("\(name) has type \(other ?? "none")")
        }
    }
}
