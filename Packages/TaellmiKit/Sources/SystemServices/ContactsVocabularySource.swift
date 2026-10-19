import Contacts
import Domain

public enum ContactsAccessError: Error, Equatable {
    case denied
}

/// First names, last names and nicknames from the user's macOS Contacts. Read locally, never stored.
public struct ContactsVocabularySource: VocabularySource {
    public init() {}

    /// Asks for Contacts access (shows the system prompt the first time).
    public static func requestAccess() async -> Bool {
        (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
    }

    public func terms() async throws -> [VocabularyTerm] {
        guard CNContactStore.authorizationStatus(for: .contacts) == .authorized else {
            throw ContactsAccessError.denied
        }
        return try await Task.detached(priority: .utility) {
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey] as [CNKeyDescriptor]
            var names = Set<String>()
            try CNContactStore().enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
                for name in [contact.givenName, contact.familyName, contact.nickname] where !name.isEmpty {
                    names.insert(name)
                }
            }
            return names.sorted().map(VocabularyTerm.init(text:))
        }.value
    }
}
