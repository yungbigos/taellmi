import Domain
import SwiftUI

/// space, for now: every person, place, topic and feeling in your thoughts. Choosing one shows the thoughts
/// that mention it and what appears with it. Later this becomes the 3D world (docs/brand.md).
struct SpaceView: View {
    @Bindable var model: ExploreViewModel
    let ground: AnyView
    @Environment(\.brand) private var brand

    var body: some View {
        NavigationSplitView {
            conceptList
        } detail: {
            Group {
                if let detail = model.conceptDetail {
                    ConceptDetailView(detail: detail, model: model)
                } else {
                    ContentUnavailableView(
                        model.concepts.isEmpty ? "no people, places or topics yet." : "choose one on the left.",
                        systemImage: "circle.hexagongrid",
                        description: Text(
                            model.concepts.isEmpty
                                ? "tälli finds them in your thoughts on this mac, with apple intelligence turned on."
                                : ""))
                }
            }
            .background { ground }
        }
        .frame(minWidth: 900, minHeight: 560)
    }

    /// Configured kinds in order, then any kind found that config doesn't describe (shown under its id).
    private var kindsShown: [ConceptKind] {
        let known = Set(model.conceptKinds.map(\.id))
        let unknown = Set(model.concepts.map(\.kind)).subtracting(known).sorted()
        return model.conceptKinds + unknown.map { ConceptKind(id: $0, plural: $0, symbol: "circle") }
    }

    private var conceptList: some View {
        List {
            ForEach(kindsShown) { kind in
                let concepts = model.concepts.filter { $0.kind == kind.id }
                if !concepts.isEmpty {
                    Section(kind.plural) {
                        ForEach(concepts) { concept in
                            Button {
                                Task { await model.openConcept(concept.id) }
                            } label: {
                                HStack {
                                    Label(concept.name, systemImage: kind.symbol)
                                    Spacer()
                                    Text("\(concept.thoughtCount)").brandForeground(.quiet)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(
                                model.conceptDetail?.concept.id == concept.id
                                    ? BrandFillBackground(name: .selection, radius: .field) : nil)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .navigationSplitViewColumnWidth(
            min: brand?.space.sidebarWidthPt.min ?? 170, ideal: (brand?.space.sidebarWidthPt.ideal ?? 190) + 40)
    }
}

/// One concept: its name, what appears with it, and every thought that mentions it, newest first.
private struct ConceptDetailView: View {
    let detail: ConceptDetail
    let model: ExploreViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label(detail.concept.name, systemImage: model.conceptKinds.symbol(detail.concept.kind))
                    .brandFont("display.heading")
                Text(detail.concept.thoughtCount == 1 ? "in 1 thought" : "in \(detail.concept.thoughtCount) thoughts")
                    .brandForeground(.quiet)
                if !detail.appearingWith.isEmpty {
                    Text("appears with").brandFont("text.label").brandForeground(.quiet)
                    WrappingRow {
                        ForEach(detail.appearingWith) { other in
                            ConceptBadge(
                                kind: other.kind, symbol: model.conceptKinds.symbol(other.kind), name: other.name,
                                count: other.thoughtCount
                            ) {
                                Task { await model.openConcept(other.id) }
                            }
                        }
                    }
                }
                Divider()
                ForEach(detail.thoughts) { entry in
                    Button {
                        Task { await model.reveal(entry.id) }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.createdAt, format: .dateTime.weekday().day().month().year().hour().minute())
                                .brandFont("text.label").brandForeground(.quiet)
                            Text(CaptureViewModel.preview(of: entry, maxLength: 280))
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("show this thought in flow")
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }
}
