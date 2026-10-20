import Domain
import Synchronization

/// Builds each configured language model once and hands it out. Apple's model is managed by macOS, so there
/// is no loading to coordinate with the one-heavy-model rule.
final class LanguageModels: LanguageModelProvider {
    private let factories: [String: LanguageModelFactory]
    private let built = Mutex<[String: any LanguageModel]>([:])

    init(factories: [String: LanguageModelFactory]) {
        self.factories = factories
    }

    var registeredEngines: Set<String> { Set(factories.keys) }

    func languageModel(_ model: ModelConfig) async throws -> any LanguageModel {
        if let existing = built.withLock({ $0[model.id] }) { return existing }
        guard let factory = factories[model.engine] else {
            throw LanguageModelError.unavailable("no engine \(model.engine)")
        }
        let made = try factory(model)
        return built.withLock { cache in
            if let existing = cache[model.id] { return existing }
            cache[model.id] = made
            return made
        }
    }
}
