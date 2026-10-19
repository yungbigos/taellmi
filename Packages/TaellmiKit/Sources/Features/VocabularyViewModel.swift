import Foundation
import Observation

/// What the Vocabulary settings screen needs. Implemented in the composition root.
public protocol VocabularySettings: Sendable {
    func terms() async throws -> [String]
    func add(_ term: String) async throws
    func remove(_ term: String) async throws
    func usesContacts() async throws -> Bool
    /// Turns the contacts opt-in on or off; returns the resulting state (off if macOS denied access).
    func setUsesContacts(_ on: Bool) async throws -> Bool
}

@Observable
public final class VocabularyViewModel {
    public private(set) var terms: [String] = []
    public private(set) var usesContacts = false
    public private(set) var message: String?
    public var newTerm = ""

    @ObservationIgnored private let settings: any VocabularySettings

    public init(settings: any VocabularySettings) {
        self.settings = settings
    }

    public func load() async {
        do {
            terms = try await settings.terms()
            usesContacts = try await settings.usesContacts()
        } catch {
            message = "Vokabular konnte nicht geladen werden."
        }
    }

    public func addNewTerm() async {
        let term = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        do {
            try await settings.add(term)
            newTerm = ""
            terms = try await settings.terms()
        } catch {
            message = "„\(term)“ konnte nicht gespeichert werden."
        }
    }

    public func remove(_ term: String) async {
        do {
            try await settings.remove(term)
            terms = try await settings.terms()
        } catch {
            message = "„\(term)“ konnte nicht entfernt werden."
        }
    }

    public func setUsesContacts(_ on: Bool) async {
        message = nil
        do {
            usesContacts = try await settings.setUsesContacts(on)
            if on, !usesContacts {
                message = "Kein Zugriff auf Kontakte. Erlaube ihn in den Systemeinstellungen unter Datenschutz."
            }
        } catch {
            message = "Einstellung konnte nicht gespeichert werden."
        }
    }
}
