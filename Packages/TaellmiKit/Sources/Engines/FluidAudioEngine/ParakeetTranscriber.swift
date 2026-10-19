import Domain
import FluidAudio
import Foundation

/// Runs Parakeet-family models through FluidAudio (Core ML, Neural Engine).
///
/// Loads only from the local model folder, never from the network. Loading is lazy;
/// `unload()` frees the Core ML models until the next transcription.
public actor ParakeetTranscriber: Transcriber {
    public static let engineKey = "fluidaudio_parakeet"
    public static let factory: TranscriberFactory = { model, directory in
        try ParakeetTranscriber(options: ParakeetOptions(params: model.params), directory: directory)
    }

    private let options: ParakeetOptions
    private let directory: URL
    private var manager: AsrManager?

    public init(options: ParakeetOptions, directory: URL) {
        self.options = options
        self.directory = directory
    }

    public func transcribe(audioFile: URL) async throws -> RawTranscription {
        let manager = try loadedManager()
        var state = try TdtDecoderState(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(audioFile, decoderState: &state)
        let tokens = (result.tokenTimings ?? []).map {
            TimedToken(text: $0.token, start: $0.startTime, end: $0.endTime)
        }
        return RawTranscription(text: result.text, tokens: tokens, durationSeconds: result.duration)
    }

    public func unload() async {
        await manager?.cleanup()
        manager = nil
    }

    private func loadedManager() throws -> AsrManager {
        if let manager { return manager }
        let models = try AsrModels.loadLocal(
            from: directory, version: options.version, encoderPrecision: options.precision)
        let manager = AsrManager(config: .default, models: models)
        self.manager = manager
        return manager
    }
}
