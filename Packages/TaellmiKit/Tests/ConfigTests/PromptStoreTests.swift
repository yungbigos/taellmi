import Config
import Domain
import Persistence
import TestSupport
import Testing

@Suite("Prompts from config")
struct PromptStoreTests {
    @Test("the seeded concept and summary prompts are found by role, with their answer shape")
    func seeded() throws {
        let store = PromptStore(database: try makeSeededDatabase())
        let concepts = try store.current(role: .entities)
        #expect(concepts.ref == "concepts@2")
        #expect(concepts.outputSchema?.objectValue?["required"] == .array([.string("concepts")]))
        #expect(try store.current(role: .summary).ref == "summary@2")
    }

    @Test("placeholders are filled; text without placeholders stays as it is")
    func render() {
        let prompt = PromptTemplate(id: "p", version: 1, template: "Text:\n{{text}}", outputSchema: nil)
        #expect(prompt.render(["text": "Die Heizung {{gluckert}}."]) == "Text:\nDie Heizung {{gluckert}}.")
    }

    @Test("a role without a prompt is reported, not silently empty")
    func missing() throws {
        let store = PromptStore(database: try makeSeededDatabase())
        #expect(throws: PromptError.missing(role: "mood")) { try store.current(role: .mood) }
    }
}
