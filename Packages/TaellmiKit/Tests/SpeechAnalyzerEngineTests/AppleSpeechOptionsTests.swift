import Domain
import SpeechAnalyzerEngine
import Testing

@Suite("Apple live transcription options from config")
struct AppleSpeechOptionsTests {
    @Test("reads the locale from the model's params")
    func readsLocale() throws {
        #expect(try AppleSpeechOptions(params: ["locale": .string("de-DE")]).localeIdentifier == "de-DE")
    }

    @Test("a missing locale is an error: the config row must say which language")
    func requiresLocale() {
        #expect(throws: AppleSpeechOptions.Error.missingParam("locale")) {
            try AppleSpeechOptions(params: [:])
        }
    }
}
