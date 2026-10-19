import Domain
import FluidAudioEngine
import Testing

@Suite("Parakeet engine options from config")
struct ParakeetOptionsTests {
    @Test("reads version and encoder precision from the model's params")
    func readsParams() throws {
        let options = try ParakeetOptions(params: ["version": .string("v3"), "encoder_precision": .string("int8-v2")])
        #expect(options.versionName == "v3")
        #expect(options.precisionName == "int8-v2")
    }

    @Test("missing params are an error: the model row in config must say which model it is")
    func requiresParams() {
        #expect(throws: ParakeetOptions.Error.missingParam("version")) {
            try ParakeetOptions(params: ["encoder_precision": .string("int8")])
        }
        #expect(throws: ParakeetOptions.Error.missingParam("encoder_precision")) {
            try ParakeetOptions(params: ["version": .string("v3")])
        }
    }

    @Test("rejects an unknown version with a clear error", arguments: ["v9", "whisper"])
    func rejectsUnknown(version: String) {
        #expect(throws: ParakeetOptions.Error.unknownVersion(version)) {
            try ParakeetOptions(params: ["version": .string(version), "encoder_precision": .string("int8")])
        }
    }
}
