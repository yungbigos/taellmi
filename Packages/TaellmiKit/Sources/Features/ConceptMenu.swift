import Domain
import SwiftUI

/// The right-click menu of a concept, the same in stack's index, on badges and in space: rename, merge,
/// change its kind, split merged names off again. Every change can be undone with ⌘Z.
struct ConceptMenu: View {
    @Bindable var model: ExploreViewModel
    let concept: ConceptSummary
    /// Concepts ⌘-clicked together with this one, for merging several at once.
    var selection: [ConceptSummary] = []
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Button("rename …") { model.conceptEdit = .rename(concept) }
        if selection.count > 1, selection.contains(where: { $0.id == concept.id }) {
            Button("merge \(selection.count) into one …") { model.conceptEdit = .merge(selection) }
        } else {
            Button("merge into …") { model.conceptEdit = .merge([concept]) }
        }
        Menu("change kind") {
            ForEach(model.conceptKinds.filter { $0.id != concept.kind }) { kind in
                Button(kind.plural) {
                    Task {
                        if await model.changeKind(concept, to: kind.id) {
                            ConceptUndo.register(model, undoManager, "change kind")
                        }
                    }
                }
            }
        }
        let merged = model.mergedNames(into: concept)
        if !merged.isEmpty {
            Menu("split off") {
                ForEach(merged, id: \.key) { name in
                    Button(name.name) {
                        Task {
                            if await model.split(name) { ConceptUndo.register(model, undoManager, "split off") }
                        }
                    }
                }
            }
        }
    }
}

@MainActor
enum ConceptUndo {
    static func register(_ model: ExploreViewModel, _ undoManager: UndoManager?, _ name: String) {
        undoManager?.registerUndo(withTarget: model) { model in Task { await model.undoConceptChange() } }
        undoManager?.setActionName(name)
    }
}

/// Renaming one concept, or merging several into one, with the option to spell people's names your way in
/// new recordings.
struct ConceptEditSheet: View {
    @Bindable var model: ExploreViewModel
    let edit: ConceptEdit
    @Environment(\.dismiss) private var dismiss
    @Environment(\.undoManager) private var undoManager
    @Environment(\.brand) private var brand
    @State private var name = ""
    @State private var search = ""
    @State private var target: ConceptSummary?
    @State private var spell = false

    var body: some View {
        VStack(alignment: .leading, spacing: brand.space(.m)) {
            switch edit {
            case .rename(let concept):
                Text("rename \(concept.name)").brandFont("display.title")
                TextField("name", text: $name).textFieldStyle(.roundedBorder).onSubmit(confirm)
                spellingToggle(kind: concept.kind)
            case .merge(let concepts):
                Text(concepts.count > 1 ? "merge \(concepts.count) into one" : "merge \(concepts[0].name) into …")
                    .brandFont("display.title")
                if concepts.count > 1 {
                    Text("the name that stays").brandFont("text.label").brandForeground(.quiet)
                    ForEach(concepts) { concept in choice(concept) }
                    Text("or another concept").brandFont("text.label").brandForeground(.quiet)
                }
                TextField("find a concept", text: $search).textFieldStyle(.roundedBorder)
                ScrollView {
                    VStack(alignment: .leading, spacing: brand.space(.xxs)) {
                        ForEach(candidates(excluding: concepts)) { concept in choice(concept) }
                    }
                }
                .frame(maxHeight: 220)
                spellingToggle(kind: target?.kind ?? concepts[0].kind)
            }
            HStack {
                Spacer()
                Button("cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm)
            }
        }
        .padding(.all, brand.space(.xl))
        .frame(width: 420)
        .onAppear(perform: prepare)
    }

    private func spellingToggle(kind: String) -> some View {
        Toggle("spell it this way in new recordings too", isOn: $spell)
            .help("adds the name to your spellings, so new transcripts are corrected towards it")
    }

    private func choice(_ concept: ConceptSummary) -> some View {
        Button {
            target = concept
            spell = concept.kind == "person"
        } label: {
            HStack {
                Text(concept.name)
                Spacer()
                Text("\(concept.thoughtCount)").brandForeground(.quiet).monospacedDigit()
            }
            .padding(.horizontal, brand.space(.s))
            .padding(.vertical, brand.space(.xxs))
            .selectionPill(target?.id == concept.id)
        }
        .buttonStyle(.plain)
    }

    private func candidates(excluding chosen: [ConceptSummary]) -> [ConceptSummary] {
        let words = search.lowercased()
        return model.stackIndex.concepts.filter { concept in
            !chosen.contains { $0.id == concept.id }
                && (words.isEmpty || concept.name.lowercased().contains(words))
        }
    }

    private func prepare() {
        switch edit {
        case .rename(let concept):
            name = concept.name
            spell = concept.kind == "person"
        case .merge(let concepts):
            if concepts.count > 1 { target = concepts.max { $0.thoughtCount < $1.thoughtCount } }
            spell = concepts[0].kind == "person"
        }
    }

    private var confirmTitle: String {
        if case .rename = edit { return "rename" }
        return "merge"
    }

    private var canConfirm: Bool {
        switch edit {
        case .rename: !name.trimmingCharacters(in: .whitespaces).isEmpty
        case .merge: target != nil
        }
    }

    private func confirm() {
        guard canConfirm else { return }
        let edit = edit
        let name = name
        let target = target
        let spell = spell
        dismiss()
        Task {
            switch edit {
            case .rename(let concept):
                if await model.renameConcept(concept, to: name, spell: spell) {
                    ConceptUndo.register(model, undoManager, "rename")
                }
            case .merge(let concepts):
                guard let target else { return }
                let merged = await model.mergeConcepts(
                    concepts.filter { $0.id != target.id }, into: ConceptName(kind: target.kind, name: target.name),
                    spell: spell)
                if merged { ConceptUndo.register(model, undoManager, "merge") }
            }
        }
    }
}
