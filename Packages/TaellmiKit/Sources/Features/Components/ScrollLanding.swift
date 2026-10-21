import SwiftUI

/// Scrolls a lazy list exactly onto an item. Far items only have an estimated height until they are laid out,
/// so one jump can land beside them; jumping again while they come in lands the item at the top. Used by flow
/// and stack.
@MainActor
struct ScrollLanding {
    private var task: Task<Void, Never>?

    mutating func land(
        on id: String, position: Binding<ScrollPosition>, animation: Animation?,
        retries: [Int] = [120, 250, 450]
    ) {
        task?.cancel()
        withAnimation(animation) { position.wrappedValue.scrollTo(id: id, anchor: .top) }
        task = Task { @MainActor in
            for delay in retries {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                position.wrappedValue.scrollTo(id: id, anchor: .top)
            }
        }
    }
}
