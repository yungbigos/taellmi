import Domain
import SwiftUI

extension [ConceptKind] {
    func symbol(_ kind: String) -> String { first { $0.id == kind }?.symbol ?? "circle" }
    func rank(_ kind: String) -> Int { firstIndex { $0.id == kind } ?? count }
}

/// One concept as a small badge; clicking it opens the concept in space.
struct ConceptBadge: View {
    let kind: String
    let symbol: String
    let name: String
    var count: Int?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 4) {
                Image(systemName: symbol).imageScale(.small)
                Text(name)
                if let count { Text("\(count)").brandForeground(.quiet) }
            }
            .brandFont("text.label")
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .brandFill(.field)
        }
        .buttonStyle(.plain)
        // Found by the model on this Mac, so marked as such (ADR 0006).
        .help("found on this mac in your words. show everything about \(name).")
        .accessibilityLabel("\(name), \(kind), found on this mac")
    }
}

/// Lays children out in rows, wrapping to the next line when a row is full.
struct WrappingRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            let gap = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}

/// Under a thought: its summary (marked as generated, or yours), its concepts and related thoughts.
struct ThoughtMeaningView: View {
    let meaning: ThoughtMeaning
    let kinds: [ConceptKind]
    let openConcept: (String) -> Void
    let reveal: (String) -> Void
    let saveSummary: (String?) -> Void
    @State private var isEditing = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if meaning.summary != nil || isEditing { summary }
            if !meaning.concepts.isEmpty {
                WrappingRow {
                    ForEach(meaning.concepts.sorted { kinds.rank($0.kind) < kinds.rank($1.kind) }) { concept in
                        ConceptBadge(kind: concept.kind, symbol: kinds.symbol(concept.kind), name: concept.name) {
                            openConcept(concept.id)
                        }
                    }
                }
            }
            if !meaning.related.isEmpty {
                WrappingRow {
                    RelatedLabel()
                    ForEach(meaning.related) { entry in
                        Button(CaptureViewModel.preview(of: entry, maxLength: 40)) { reveal(entry.id) }
                            .buttonStyle(.link)
                            .brandFont("text.label")
                    }
                }
            }
        }
    }

    @ViewBuilder private var summary: some View {
        if isEditing {
            TextField("summary", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .brandFont("text.label")
                .padding(6)
                .brandFill(.field)
                .onSubmit {
                    isEditing = false
                    saveSummary(draft)
                }
                .onExitCommand { isEditing = false }
        } else if let text = meaning.summary {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: meaning.summaryIsEdited ? "pencil" : "sparkle")
                    .imageScale(.small)
                    .help(meaning.summaryIsEdited ? "your summary" : "summary made on this mac. click to change it.")
                Text(text).italic()
            }
            .brandFont("text.label")
            .brandForeground(.quiet)
            .onTapGesture {
                draft = text
                isEditing = true
            }
            .accessibilityLabel(meaning.summaryIsEdited ? "your summary: \(text)" : "generated summary: \(text)")
        }
    }
}
