import Domain
import SwiftUI

/// One thought as flow and stack show it, editable in place; saved shortly after you stop typing. While a search is active,
/// its words are highlighted in place and a related thought carries a small label.
struct ThoughtBlock: View {
    let entry: Entry
    let isCurrentMatch: Bool
    let isRelated: Bool
    let highlights: (String) -> [TextHighlight]
    let meaning: ThoughtMeaning?
    let kinds: [ConceptKind]
    let openConcept: (String) -> Void
    let reveal: (String) -> Void
    let saveSummary: (String?) -> Void
    /// Set for imported thoughts: clicking the time changes their date.
    let changeDate: ((Date) -> Void)?
    let formatting: FormattingFocus
    let shortcuts: [Command: Hotkey]
    var menuItems: [EditorMenuItem] = []
    var badgeMenu: ((ThoughtConcept) -> AnyView)?
    let save: (String) async -> Void
    @State private var text = ""
    /// The text last handed to save; a newer text from the Archive is only taken while nothing newer is typed.
    @State private var lastSaved = ""
    @State private var saveTask: Task<Void, Never>?
    /// Read mode by default; the editor only while you work in this thought.
    @State private var isEditing = false

    private var when: some View {
        VStack(spacing: 4) {
            Image(systemName: ThoughtMeta.sourceSymbol(entry.source))
            Text(entry.createdAt, format: .dateTime.hour().minute())
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let changeDate {
                    ChangeDateButton(date: entry.createdAt, save: changeDate) { when }
                } else {
                    when
                }
            }
            .brandFont("text.label")
            .brandForeground(.quiet)
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                if isRelated { RelatedLabel() }
                Group {
                    if isEditing {
                        HighlightingTextEditor(
                            text: $text, highlights: highlights(text), grows: true, formatting: formatting,
                            shortcuts: shortcuts, focusOnAppear: true, onCancel: { EditingFocus.end() },
                            menuItems: menuItems, onEndEditing: { isEditing = false }
                        )
                    } else {
                        ReadingTextView(text: text, highlights: highlights(text)) { isEditing = true }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("edit this thought")
                    }
                }
                .onChange(of: text) { _, newText in
                    guard newText != entry.text else { return }
                    saveTask?.cancel()
                    saveTask = Task {
                        try? await Task.sleep(for: .milliseconds(800))
                        guard !Task.isCancelled else { return }
                        lastSaved = newText
                        await save(newText)
                    }
                }
                if let meaning {
                    ThoughtMeaningView(
                        meaning: meaning, kinds: kinds, openConcept: openConcept, reveal: reveal,
                        saveSummary: saveSummary, badgeMenu: badgeMenu)
                }
            }
        }
        .padding(10)
        .background {
            if isCurrentMatch { BrandFillBackground(name: .match, radius: .field) }
        }
        .onAppear {
            text = entry.text
            lastSaved = entry.text
        }
        .onChange(of: entry.text) { _, newText in
            // Coming back from our own save while you kept typing: keep what you typed.
            guard newText != text, text == lastSaved else { return }
            text = newText
            lastSaved = newText
        }
    }
}
