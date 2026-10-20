import Domain
import SwiftUI

/// space, for now: every person, place, topic and feeling in your thoughts, by kind. Click some to filter by
/// them; the thoughts that mention all of them show at the side. The bar at the bottom narrows the kinds and
/// finds concepts by name. Later this becomes the 3D world (docs/brand.md).
struct SpaceView: View {
    @Bindable var model: ExploreViewModel
    @Environment(\.brand) private var brand

    var body: some View {
        HStack(alignment: .top, spacing: brand.space(.xxl)) {
            ScrollView {
                VStack(alignment: .leading, spacing: brand.space(.xl)) {
                    ForEach(kindsShown) { kind in
                        let concepts = model.visibleConcepts.filter { $0.kind == kind.id }
                        if !concepts.isEmpty {
                            VStack(alignment: .leading, spacing: brand.space(.s)) {
                                Label(kind.plural, systemImage: kind.symbol)
                                    .brandFont("text.label").brandForeground(.quiet)
                                WrappingRow(spacing: brand.space(.xs) ?? 4) {
                                    ForEach(concepts) { concept in conceptButton(concept) }
                                }
                            }
                        }
                    }
                }
                .padding(.all, brand.space(.xxl))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlay {
                if model.concepts.isEmpty {
                    ContentUnavailableView(
                        "no people, places or topics yet.", systemImage: "circle.hexagongrid",
                        description: Text(
                            "tälli finds them in your thoughts on this mac, with apple intelligence turned on."))
                } else if model.visibleConcepts.isEmpty {
                    ContentUnavailableView("nothing found.", systemImage: "magnifyingglass")
                }
            }
            PickedThoughtsView(model: model)
                .frame(width: brand.map { CGFloat($0.space.listWidthPt.ideal) })
        }
    }

    /// Configured kinds in order, then any kind found that config doesn't describe (shown under its id).
    private var kindsShown: [ConceptKind] {
        let known = Set(model.conceptKinds.map(\.id))
        let unknown = Set(model.concepts.map(\.kind)).subtracting(known).sorted()
        return model.conceptKinds + unknown.map { ConceptKind(id: $0, plural: $0, symbol: "circle") }
    }

    private func conceptButton(_ concept: ConceptSummary) -> some View {
        let picked = model.pickedConcepts.contains(concept.id)
        return Button {
            Task { await model.togglePick(concept.id) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: brand.space(.xs)) {
                Text(concept.name).brandFont("text.thought")
                Text("\(concept.thoughtCount)").brandFont("text.label").monospacedDigit()
                    .brandForeground(picked ? .blue : .quiet)
            }
            .brandForeground(picked ? .blue : .ink)
            .padding(.horizontal, brand.space(.s))
            .padding(.vertical, brand.space(.xxs))
            .background {
                if picked { BrandFillBackground(name: .selection, radius: .field) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Found by the model on this Mac, so marked as such (ADR 0006).
        .help(
            picked ? "stop filtering by \(concept.name)" : "found on this mac in your words. filter by \(concept.name)."
        )
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// The thoughts that mention every picked concept, newest first; one picked shows what appears with it.
private struct PickedThoughtsView: View {
    let model: ExploreViewModel
    @Environment(\.brand) private var brand

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: brand.space(.m)) {
                if model.pickedConcepts.isEmpty {
                    Text("click people, places, topics or feelings to filter by them.")
                        .brandForeground(.quiet)
                } else {
                    Text(header).brandFont("text.label").brandForeground(.quiet)
                    if model.pickedConcepts.count == 1, let detail = model.conceptDetail, !detail.appearingWith.isEmpty
                    {
                        Text("appears with").brandFont("text.label").brandForeground(.quiet)
                        WrappingRow {
                            ForEach(detail.appearingWith) { other in
                                ConceptBadge(
                                    kind: other.kind, symbol: model.conceptKinds.symbol(other.kind), name: other.name,
                                    count: other.thoughtCount
                                ) {
                                    Task { await model.togglePick(other.id) }
                                }
                            }
                        }
                    }
                    Divider()
                    ForEach(model.pickedThoughts) { entry in
                        Button {
                            Task { await model.reveal(entry.id) }
                        } label: {
                            VStack(alignment: .leading, spacing: brand.space(.xs)) {
                                Text(ThoughtMeta.short(entry.createdAt))
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
            }
            .padding(.vertical, brand.space(.xxl))
            .padding(.trailing, brand.space(.xxl))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: String {
        let names = model.pickedConcepts.compactMap { id in model.concepts.first { $0.id == id }?.name }
        return "\(ThoughtCount.words(model.pickedThoughts.count)) with \(names.joined(separator: " · "))"
    }
}
