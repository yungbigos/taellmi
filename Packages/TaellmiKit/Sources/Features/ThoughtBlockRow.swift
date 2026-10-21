import Domain
import SwiftUI

/// A thought block wired to the Explore model: saving, meaning, concepts, dates. Used by flow and stack alike,
/// so a thought looks and behaves the same in both.
struct ThoughtBlockRow: View {
    @Bindable var model: ExploreViewModel
    let entry: Entry
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        ThoughtBlock(
            entry: entry, isCurrentMatch: model.currentMatch == entry.id,
            isRelated: model.isRelated(entry.id),
            highlights: { text in model.highlights(in: text, entryID: entry.id) },
            meaning: model.meanings[entry.id], kinds: model.conceptKinds,
            openConcept: { id in Task { await model.openConcept(id) } },
            reveal: { id in Task { await model.reveal(id) } },
            saveSummary: { text in Task { await model.saveSummary(text, for: entry.id) } },
            changeDate: entry.source.isImported
                ? { date in Task { await model.changeDate(of: entry.id, to: date) } } : nil,
            formatting: model.formatting, shortcuts: model.shortcuts,
            menuItems: ThoughtActions.menuItems(model: model, entry: entry, undoManager: undoManager),
            badgeMenu: { concept in
                AnyView(
                    ConceptMenu(
                        model: model,
                        concept: ConceptSummary(id: concept.id, kind: concept.kind, name: concept.name, thoughtCount: 0)
                    ))
            }
        ) { text in
            await model.saveFlowText(id: entry.id, text: text)
        }
        .contextMenu { ThoughtContextMenu(model: model, entry: entry) }
        .task { await model.loadMeaning(for: entry.id) }
        .onDisappear { model.forgetMeaning(for: entry.id) }
    }
}
