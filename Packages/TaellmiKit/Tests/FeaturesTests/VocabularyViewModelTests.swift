import Features
import Testing

@Suite("Editing the Vocabulary in Settings")
struct VocabularyViewModelTests {
    actor FakeSettings: VocabularySettings {
        var words: [String] = ["Marleen"]
        var contacts = false
        var contactsAccessGranted: Bool

        init(contactsAccessGranted: Bool = true) {
            self.contactsAccessGranted = contactsAccessGranted
        }

        func terms() async throws -> [String] { words }
        func add(_ term: String) async throws { words = (words + [term]).sorted() }
        func remove(_ term: String) async throws { words.removeAll { $0 == term } }
        func usesContacts() async throws -> Bool { contacts }
        func setUsesContacts(_ on: Bool) async throws -> Bool {
            contacts = on && contactsAccessGranted
            return contacts
        }
    }

    @Test("loads the current list and the contacts choice")
    func loads() async {
        let model = VocabularyViewModel(settings: FakeSettings())
        await model.load()
        #expect(model.terms == ["Marleen"])
        #expect(model.usesContacts == false)
    }

    @Test("adding a name clears the input and shows the new list; blank input is ignored")
    func adds() async {
        let model = VocabularyViewModel(settings: FakeSettings())
        await model.load()
        model.newTerm = "  "
        await model.addNewTerm()
        #expect(model.terms == ["Marleen"])
        model.newTerm = "Jannik"
        await model.addNewTerm()
        #expect(model.terms == ["Jannik", "Marleen"])
        #expect(model.newTerm.isEmpty)
    }

    @Test("removing a name updates the list")
    func removes() async {
        let model = VocabularyViewModel(settings: FakeSettings())
        await model.load()
        await model.remove("Marleen")
        #expect(model.terms.isEmpty)
    }

    @Test("turning on contacts without macOS permission stays off and explains why")
    func contactsDenied() async {
        let model = VocabularyViewModel(settings: FakeSettings(contactsAccessGranted: false))
        await model.load()
        await model.setUsesContacts(true)
        #expect(model.usesContacts == false)
        #expect(model.message?.contains("Kontakte") == true)
    }
}
