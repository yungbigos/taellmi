import Features
import Testing

@Suite("The end of what you're saying, in tälli's bubble")
struct LivePreviewTailTests {
    @Test("short text is shown as it is")
    func short() {
        #expect(LivePreviewTail.tail(of: "Hallo tälli.", maxCharacters: 40) == "Hallo tälli.")
    }

    @Test("long text shows its end, starting at a whole word, with … in front")
    func long() {
        let text = "Heute war ich lange an der Isar und danach noch kurz bei Kim im Englischen Garten"
        let tail = LivePreviewTail.tail(of: text, maxCharacters: 30)
        #expect(tail == "… bei Kim im Englischen Garten")
        #expect(tail.count <= 32)
    }

    @Test("one very long word is cut rather than shown empty")
    func longWord() {
        #expect(LivePreviewTail.tail(of: "Donaudampfschifffahrtsgesellschaft", maxCharacters: 10) == "… sellschaft")
    }
}
