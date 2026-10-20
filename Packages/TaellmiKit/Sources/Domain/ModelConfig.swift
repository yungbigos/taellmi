import Foundation

/// A job a model can be assigned to. Roles are fixed in code; which model fills a role is config.
public enum ModelRole: String, Sendable, Codable, CaseIterable {
    case liveTranscription = "live_transcription"
    case transcription
    case title
    case tags
    case summary
    case entities
    case mood
    case cleanup
    case ask
    case embed
    case rerank
}

/// One file belonging to a model, pinned by hash.
public struct ModelFile: Sendable, Equatable, Codable {
    public var path: String
    public var sha256: String
    public var bytes: Int

    public init(path: String, sha256: String, bytes: Int) {
        self.path = path
        self.sha256 = sha256
        self.bytes = bytes
    }
}

/// Everything an engine needs to run a specific model. Built from a `model` config row.
public struct ModelConfig: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    /// Key of the engine adapter that runs this model family, e.g. `fluidaudio_parakeet`.
    public var engine: String
    public var providerID: String
    public var sourceRef: String?
    public var revision: String?
    public var files: [ModelFile]
    public var params: [String: JSONValue]
    public var capabilities: [String]
    public var estimatedMemoryMB: Int?

    public init(
        id: String, name: String, engine: String, providerID: String, sourceRef: String? = nil,
        revision: String? = nil, files: [ModelFile] = [], params: [String: JSONValue] = [:],
        capabilities: [String] = [], estimatedMemoryMB: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.engine = engine
        self.providerID = providerID
        self.sourceRef = sourceRef
        self.revision = revision
        self.files = files
        self.params = params
        self.capabilities = capabilities
        self.estimatedMemoryMB = estimatedMemoryMB
    }
}

extension ModelConfig {
    /// Which vectors can be compared with each other: the same model at the same configured size. Changing
    /// `params.dimensions` makes a new space, so every passage is embedded again.
    public var vectorSpace: String {
        "\(id)@\(params["dimensions"]?.doubleValue.map { String(Int($0)) } ?? "native")"
    }
}
