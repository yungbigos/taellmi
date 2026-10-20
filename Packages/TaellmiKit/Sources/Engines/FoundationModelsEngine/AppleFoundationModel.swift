import Domain
import Foundation
import FoundationModels

/// Apple's on-device language model (Apple Intelligence), engine key `apple_foundation`. macOS owns the
/// weights and their memory, so there is nothing to download or load; each request is a fresh session, so no
/// thought leaks into the next.
public actor AppleFoundationModel: LanguageModel {
    public static let engineKey = "apple_foundation"

    public static let factory: LanguageModelFactory = { model in
        AppleFoundationModel(temperature: model.params["temperature"]?.doubleValue)
    }

    private let temperature: Double?

    public init(temperature: Double?) {
        self.temperature = temperature
    }

    public func availability() async -> LanguageModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available: .available
        case .unavailable(let reason): .unavailable(String(describing: reason))
        }
    }

    public func generate(prompt: String, schema: JSONValue) async throws -> JSONValue {
        if case .unavailable(let reason) = await availability() { throw LanguageModelError.unavailable(reason) }
        let guide = try GenerationSchemaBuilder.schema(from: schema)
        let session = LanguageModelSession(model: .default)
        do {
            let response = try await session.respond(
                to: prompt, schema: guide, options: GenerationOptions(temperature: temperature))
            return try JSONDecoder().decode(JSONValue.self, from: Data(response.content.jsonString.utf8))
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error { throw LanguageModelError.inputTooLong }
            throw error
        }
    }

    public func unload() async {}
}
