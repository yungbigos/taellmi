import Domain
import Testing

@testable import Features

@Suite("A spoken thought still waiting for its text")
struct ThoughtWaitingTests {
    @Test(
        "says transcribing … in flow and stack, like the menu bar; a thought with words, or a typed one, doesn't",
        arguments: [
            (EntrySource.voice, "", "transcribing …"),
            (EntrySource.voice, "  \n", "transcribing …"),
            (EntrySource.voice, "Kurz notiert.", nil),
            (EntrySource.typed, "", nil),
        ] as [(EntrySource, String, String?)])
    func waitingLine(source: EntrySource, text: String, line: String?) {
        #expect(ThoughtMeta.waitingLine(source: source, text: text) == line)
    }
}
