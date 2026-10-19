import Domain
import Foundation
import Testing

@Suite("Entry Markdown file")
struct FrontMatterTests {
    private let sample = EntryDocument(
        metadata: [
            "id": .string("2026-10-19-2034-a1b2"),
            "duration_s": .number(63.25),
            "source": .string("voice"),
            "tags": .array([.string("Arbeit"), .string("Zukunftsangst")]),
            "title": .null,
        ],
        body: "## Transkript\n\nIch hatte heute ein komisches Gefühl – honestly, kind of weird.\n"
    )

    @Test("round-trips metadata and body, including umlauts and dashes")
    func roundTrip() throws {
        let text = sample.markdown()
        let parsed = try EntryDocument(markdown: text)
        #expect(parsed == sample)
    }

    @Test("writes YAML-compatible front matter with sorted keys")
    func layout() {
        let text = sample.markdown()
        #expect(text.hasPrefix("---\nduration_s: 63.25\nid: \"2026-10-19-2034-a1b2\"\n"))
        #expect(text.contains("\n---\n\n## Transkript"))
    }

    @Test("rejects a file without front matter")
    func rejectsMissingFrontMatter() {
        #expect(throws: EntryDocument.ParseError.self) {
            try EntryDocument(markdown: "Just text")
        }
    }

    @Test("a body containing --- lines survives")
    func bodyWithRules() throws {
        let doc = EntryDocument(metadata: ["id": .string("x")], body: "a\n---\nb\n")
        #expect(try EntryDocument(markdown: doc.markdown()) == doc)
    }
}
