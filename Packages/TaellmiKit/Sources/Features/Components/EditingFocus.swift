import AppKit
import SwiftUI

/// Ends editing a thought: the editor gives up the keyboard and the thought returns to read mode.
@MainActor
enum EditingFocus {
    static func end() {
        NSApplication.shared.keyWindow?.makeFirstResponder(nil)
    }
}

extension View {
    /// A click on empty space here ends editing (flow and stack's background).
    func endsEditingOnClick() -> some View {
        background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { EditingFocus.end() }
        }
    }
}
