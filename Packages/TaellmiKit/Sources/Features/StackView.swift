import Domain
import SwiftUI

/// stack: your thoughts sorted by folder and concept, where flow sorts them by time. The index floats on the
/// left; the chosen group reads like flow in the middle; the open thought's details float on the right.
struct StackView: View {
    @Bindable var model: ExploreViewModel
    @Environment(\.brand) private var brand
    @Environment(\.undoManager) private var undoManager
    @AppStorage("explore.showsDetails") private var showsDetails = true
    @State private var newFolderName: String?
    @State private var renaming: (id: String, name: String)?
    /// Concepts ⌘-clicked together, to merge them at once.
    @State private var pickedConcepts: [ConceptSummary] = []
    @State private var position = ScrollPosition(idType: String.self)
    @State private var landing = ScrollLanding()

    var body: some View {
        HStack(spacing: brand.space(.l)) {
            index
                .frame(width: brand.map { CGFloat($0.space.listWidthPt.ideal) } ?? 300)
                .floatingPanel()
                .padding([.leading, .top, .bottom], brand.space(.l))
            column
            if showsDetails, let detail = model.detail {
                ThoughtDetailsView(
                    detail: detail, playbackRequest: model.playbackRequest,
                    changeDate: model.canChangeDate ? { date in Task { await model.changeDate(to: date) } } : nil
                )
                .id(detail.entry.id)
                .frame(width: brand.map { CGFloat($0.space.inspectorWidthPt.ideal) } ?? 260)
                .floatingPanel()
                .padding([.trailing, .top, .bottom], brand.space(.l))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .brandAnimation(\.crossfade, value: showsDetails)
        // A merge or rename changes the index; picks from before may point at concepts that are gone.
        .onChange(of: model.stackIndex) { pickedConcepts = [] }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(role: .destructive) {
                    Task {
                        await model.trashSelected()
                        undoManager?.registerUndo(withTarget: model) { model in Task { await model.undoTrash() } }
                        undoManager?.setActionName("delete thought")
                    }
                } label: {
                    Label("delete thought", systemImage: "trash")
                }
                .help("delete thought")
                .disabled(model.detail == nil)
                Button {
                    showsDetails.toggle()
                } label: {
                    Label("details", systemImage: "sidebar.right")
                }
                .help(showsDetails ? "hide details" : "show details")
            }
        }
    }

    // MARK: The chosen group, like flow

    private var column: some View {
        columnScroll
            .scrollPosition($position)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { landing.stop() }
            }
            .onAppear { if let id = model.scrollTarget { land(on: id) } }
            .onChange(of: model.scrollRequest) { _, request in
                if let request { land(on: request.entryID) }
            }
    }

    private func land(on id: String) {
        landing.land(on: id, position: $position, animation: brand?.animation(\.scroll) ?? .default)
    }

    private var columnScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: brand.space(.xs)) {
                    Text(heading).brandFont("display.heading")
                    Text(subheading).brandFont("text.label").brandForeground(.quiet)
                    if case .concept(let id) = model.stackGroup,
                        let concept = model.stackIndex.concepts.first(where: { $0.id == id })
                    {
                        mergedNames(concept)
                    }
                }
                .padding(.top, 24)
                ForEach(model.entries) { entry in
                    ThoughtBlockRow(model: model, entry: entry)
                        .background {
                            if model.selectedID == entry.id { BrandFillBackground(name: .selection, radius: .field) }
                        }
                        // Clicking anywhere in a thought opens its details; typing still goes into the text.
                        .simultaneousGesture(TapGesture().onEnded { model.choose(entry.id) })
                        .id(entry.id)
                }
            }
            .scrollTargetLayout()
            .frame(maxWidth: 720)
            .padding(32)
            .frame(maxWidth: .infinity)
            .endsEditingOnClick()
        }
        .overlay {
            if model.entries.isEmpty {
                ContentUnavailableView(
                    model.query.text.isEmpty ? "nothing here yet." : "nothing found.", systemImage: "folder")
            }
        }
    }

    /// The names merged into this concept, each with an × to split it off again.
    @ViewBuilder private func mergedNames(_ concept: ConceptSummary) -> some View {
        let names = model.mergedNames(into: concept)
        if !names.isEmpty {
            WrappingRow {
                Text("also").brandFont("text.label").brandForeground(.quiet)
                ForEach(names, id: \.key) { name in
                    Button {
                        Task {
                            if await model.split(name) { ConceptUndo.register(model, undoManager, "split off") }
                        }
                    } label: {
                        HStack(spacing: brand.space(.xxs)) {
                            Text(name.name)
                            Image(systemName: "xmark").imageScale(.small)
                        }
                        .brandFont("text.label")
                        .padding(.horizontal, brand.space(.s))
                        .padding(.vertical, brand.space(.xxs))
                        .brandFill(.field)
                    }
                    .buttonStyle(.plain)
                    .help("split \(name.name) off again")
                }
            }
        }
    }

    private var heading: String {
        switch model.stackGroup {
        case .loose: "loose thoughts"
        case .folder(let id): model.stackIndex.folders.first { $0.id == id }?.folder.name ?? "folder"
        case .concept(let id): model.stackIndex.concepts.first { $0.id == id }?.name ?? "concept"
        }
    }

    private var subheading: String {
        let count = ThoughtCount.words(model.entries.count)
        switch model.stackGroup {
        case .loose: return "in no folder yet · \(count)"
        case .folder: return "your folder · \(count)"
        case .concept(let id):
            let kind = model.stackIndex.concepts.first { $0.id == id }?.kind ?? ""
            return "\(model.conceptKinds.first { $0.id == kind }?.plural ?? kind) · \(count)"
        }
    }

    // MARK: The index

    private var index: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: brand.space(.xxs)) {
                sectionTitle("your folders")
                ForEach(model.stackIndex.folders) { summary in
                    if renaming?.id == summary.id {
                        nameField(
                            text: Binding(get: { renaming?.name ?? "" }, set: { renaming?.name = $0 }),
                            prompt: "folder name"
                        ) { name in
                            renaming = nil
                            Task { await model.renameFolder(summary.id, to: name) }
                        }
                    } else {
                        row(summary.folder.name, symbol: "folder", count: summary.count, group: .folder(summary.id))
                            .contextMenu {
                                Button("rename …") { renaming = (summary.id, summary.folder.name) }
                                Button("remove folder", role: .destructive) {
                                    Task { await model.deleteFolder(summary.id) }
                                }
                            }
                    }
                }
                if let name = newFolderName {
                    nameField(
                        text: Binding(get: { name }, set: { newFolderName = $0 }), prompt: "new folder"
                    ) { name in
                        newFolderName = nil
                        Task { await model.createFolder(named: name) }
                    }
                } else {
                    Button {
                        newFolderName = ""
                    } label: {
                        Label("new folder", systemImage: "plus").brandForeground(.quiet)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, brand.space(.s))
                    .padding(.vertical, brand.space(.xs))
                }
                if !model.conceptSuggestions.isEmpty {
                    sectionTitle("maybe the same")
                    ForEach(model.conceptSuggestions, id: \.first?.id) { group in suggestion(group) }
                }
                ForEach(model.conceptKinds) { kind in
                    let concepts = model.stackIndex.concepts.filter { $0.kind == kind.id }
                    if !concepts.isEmpty {
                        sectionTitle(kind.plural)
                        ForEach(concepts) { concept in conceptRow(concept, symbol: kind.symbol) }
                    }
                }
                sectionTitle("not filed")
                row("loose thoughts", symbol: "tray", count: model.stackIndex.looseCount, group: .loose)
            }
            .padding(.all, brand.space(.s))
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .brandFont("text.label")
            .brandForeground(.quiet)
            .padding(.horizontal, brand.space(.s))
            .padding(.top, brand.space(.m))
    }

    /// A concept in the index: click shows it, ⌘-click picks several to merge, right-click edits it.
    private func conceptRow(_ concept: ConceptSummary, symbol: String) -> some View {
        let picked = pickedConcepts.contains { $0.id == concept.id }
        return row(concept.name, symbol: symbol, count: concept.thoughtCount, group: .concept(concept.id)) {
            if NSEvent.modifierFlags.contains(.command) {
                if picked { pickedConcepts.removeAll { $0.id == concept.id } } else { pickedConcepts.append(concept) }
                return true
            }
            pickedConcepts = []
            return false
        }
        .background {
            if picked { BrandFillBackground(name: .selectedRow, radius: .field) }
        }
        .contextMenu { ConceptMenu(model: model, concept: concept, selection: pickedConcepts) }
    }

    /// Names that sound alike: merge them in one step, or say they are different.
    private func suggestion(_ group: [ConceptSummary]) -> some View {
        HStack(spacing: brand.space(.xs)) {
            Text(group.map(\.name).joined(separator: " · ")).lineLimit(2).brandFont("text.label")
            Spacer(minLength: brand.space(.xs))
            Button("merge …") { model.conceptEdit = .merge(group) }
                .buttonStyle(.link)
                .brandFont("text.label")
            Button {
                Task { await model.dismissSuggestion(group) }
            } label: {
                Image(systemName: "xmark").imageScale(.small)
            }
            .buttonStyle(.plain)
            .brandForeground(.quiet)
            .help("not the same")
            .accessibilityLabel("not the same")
        }
        .padding(.horizontal, brand.space(.s))
        .padding(.vertical, brand.space(.xxs))
    }

    private func row(
        _ name: String, symbol: String, count: Int, group: StackGroup, intercept: @escaping () -> Bool = { false }
    ) -> some View {
        Button {
            guard !intercept() else { return }
            Task { await model.chooseGroup(group) }
        } label: {
            HStack(spacing: brand.space(.s)) {
                Image(systemName: symbol).imageScale(.small).brandForeground(.quiet)
                Text(name).lineLimit(1)
                Spacer(minLength: brand.space(.s))
                Text("\(count)").brandFont("text.label").monospacedDigit().brandForeground(.quiet)
            }
            .padding(.horizontal, brand.space(.s))
            .padding(.vertical, brand.space(.xs))
            .selectionPill(model.stackGroup == group)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityAddTraits(model.stackGroup == group ? .isSelected : [])
    }

    private func nameField(text: Binding<String>, prompt: String, done: @escaping (String) -> Void) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .padding(.horizontal, brand.space(.s))
            .padding(.vertical, brand.space(.xs))
            .brandFill(.field)
            .onSubmit { done(text.wrappedValue) }
            .onExitCommand {
                newFolderName = nil
                renaming = nil
            }
    }
}
