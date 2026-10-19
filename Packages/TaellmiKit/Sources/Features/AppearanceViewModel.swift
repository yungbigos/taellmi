import Foundation
import Observation
import SwiftUI

/// Reads and writes the `appearance.text_case` setting. Implemented in the composition root.
public protocol AppearanceStore: Sendable {
    func textCase() async throws -> String
    func setTextCase(_ value: String) async throws
}

/// How text is shown: normal, or all lowercase. Display only: stored Entries never change.
@Observable
public final class AppearanceViewModel {
    public private(set) var isLowercase = false
    @ObservationIgnored private let store: any AppearanceStore

    public init(store: any AppearanceStore) {
        self.store = store
    }

    public func load() async {
        isLowercase = (try? await store.textCase()) == "lowercase"
    }

    public func setLowercase(_ on: Bool) async {
        isLowercase = on
        try? await store.setTextCase(on ? "lowercase" : "normal")
    }

    /// For text that isn't a SwiftUI `Text` (window titles, menus).
    public func display(_ text: String) -> String {
        isLowercase ? text.lowercased() : text
    }

    /// Apply to a view tree with `.textCase(appearance.swiftUICase)`.
    public var swiftUICase: Text.Case? { isLowercase ? .lowercase : nil }
}
