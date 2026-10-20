import Domain
import SwiftUI

/// The floating bar at the bottom of the window, as three glass islands that follow the view (issue #54):
/// what to look at, (in space) finding concepts, and spoken / typed with trash. Trash has a bar of its own.
struct ExploreBarView: View {
    @Bindable var model: ExploreViewModel
    @State private var confirmsEmptyTrash = false
    @Environment(\.brand) private var brand

    var body: some View {
        GlassEffectContainer(spacing: brand.space(.s) ?? 8) {
            HStack(spacing: brand.space(.s)) {
                switch model.bar {
                case .thoughts:
                    // Search is the button at the top right, which opens ⌘K.
                    island { periods }
                    island { sourceAndTrash }
                case .time:
                    island { zooms }
                    island { timeNavigation }
                    island { sourceAndTrash }
                case .space:
                    island { kinds }
                    island { conceptField }
                    island { sourceAndTrash }
                case .trash:
                    island {
                        BarChip(title: "back to thoughts", symbol: "chevron.left") {
                            Task { await model.leaveTrash() }
                        }
                    }
                    island {
                        Text(trashLine).brandForeground(.quiet).padding(.horizontal, brand.space(.m))
                            .frame(height: brand.space(.xxl))
                    }
                    island {
                        BarChip(title: "empty trash", symbol: "trash") { confirmsEmptyTrash = true }
                            .disabled(model.trashCount == 0)
                    }
                }
            }
        }
        .padding(.horizontal, brand.space(.l))
        .padding(.bottom, brand.space(.l))
        .brandAnimation(\.crossfade, value: model.bar)
        .confirmationDialog(
            "delete every thought in trash for good?", isPresented: $confirmsEmptyTrash, titleVisibility: .visible
        ) {
            Button("delete for good", role: .destructive) { Task { await model.emptyTrash() } }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("they move on to the macOS Trash.")
        }
    }

    private func island(@ViewBuilder _ content: () -> some View) -> some View {
        BarIsland { content() }
    }

    private var trashLine: String {
        model.trashCount == 0 ? "trash is empty." : ThoughtCount.words(model.trashCount) + " in trash"
    }

    // MARK: stack and flow

    private var periods: some View {
        ForEach(EntryQuery.Period.allCases, id: \.self) { period in
            BarChip(title: ExploreView.label(for: period), selected: model.query.period == period) {
                Task { await model.choose(period: period) }
            }
        }
    }

    // MARK: time

    private var zooms: some View {
        ForEach(TimelineZoom.allCases, id: \.self) { zoom in
            BarChip(title: zoom.rawValue, selected: model.timeRange.zoom == zoom) {
                while model.timeRange.zoom < zoom { model.timeRange.zoomOut() }
                while model.timeRange.zoom > zoom { model.timeRange.zoomIn() }
            }
        }
    }

    private var timeNavigation: some View {
        Group {
            BarIconButton(symbol: "chevron.left", label: "show earlier") {
                Task { await model.perform(.showEarlier) }
            }
            BarChip(title: "today") { model.showToday() }
            BarIconButton(symbol: "chevron.right", label: "show later") {
                Task { await model.perform(.showLater) }
            }
        }
    }

    // MARK: space

    private var kinds: some View {
        Group {
            BarChip(title: "all", selected: model.conceptKindFilter == nil) { model.conceptKindFilter = nil }
            ForEach(model.conceptKinds) { kind in
                BarChip(
                    title: kind.plural, selected: model.conceptKindFilter == kind.id,
                    count: pickedCount(of: kind.id)
                ) {
                    model.conceptKindFilter = kind.id
                }
            }
        }
    }

    private func pickedCount(of kind: String) -> Int? {
        let count = model.concepts.filter { $0.kind == kind && model.pickedConcepts.contains($0.id) }.count
        return count == 0 ? nil : count
    }

    /// Picked concepts as tags you can take away, then a field that finds concepts by name.
    private var conceptField: some View {
        HStack(spacing: brand.space(.xs)) {
            Image(systemName: "magnifyingglass").brandForeground(.quiet)
            ForEach(model.pickedConcepts, id: \.self) { id in
                let name = model.concepts.first { $0.id == id }?.name ?? id
                Button {
                    Task { await model.togglePick(id) }
                } label: {
                    HStack(spacing: brand.space(.xxs)) {
                        Text(name)
                        Image(systemName: "xmark").imageScale(.small)
                    }
                    .fontWeight(.semibold)
                    .brandForeground(.blue)
                    .padding(.horizontal, brand.space(.s))
                    .padding(.vertical, brand.space(.xxs))
                    .background { BrandFillBackground(name: .selection, radius: nil).clipShape(Capsule()) }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("remove \(name)")
            }
            TextField(
                model.pickedConcepts.isEmpty ? "find " + model.conceptKinds.map(\.plural).joined(separator: ", ") : "",
                text: $model.conceptSearch
            )
            .textFieldStyle(.plain)
            .onExitCommand { model.conceptSearch = "" }
            if !model.pickedConcepts.isEmpty {
                BarIconButton(symbol: "xmark.circle.fill", label: "remove all") { model.clearPicks() }
            }
        }
        .padding(.horizontal, brand.space(.m))
        .frame(minWidth: brand.map { CGFloat($0.space.barSearchWidthPt) })
        .frame(height: brand.space(.xxl))
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: every view

    private var sourceAndTrash: some View {
        Group {
            BarIconButton(symbol: "waveform", label: "only spoken", selected: model.onlySource == .voice) {
                Task { await model.toggle(source: .voice) }
            }
            BarIconButton(symbol: "keyboard", label: "only typed", selected: model.onlySource == .typed) {
                Task { await model.toggle(source: .typed) }
            }
            BarIconButton(
                symbol: ThoughtMeta.sourceSymbol(.appleNotes), label: "only from apple notes",
                selected: model.onlySource == .appleNotes
            ) {
                Task { await model.toggle(source: .appleNotes) }
            }
            BarIconButton(
                symbol: "trash",
                label: model.trashCount == 0 ? "trash" : "trash, " + ThoughtCount.words(model.trashCount),
                badge: model.trashCount
            ) {
                Task { await model.perform(.showTrash) }
            }
        }
    }
}

/// "1 thought", "3 thoughts".
enum ThoughtCount {
    static func words(_ count: Int) -> String { count == 1 ? "1 thought" : "\(count) thoughts" }
}

/// A round symbol button in the bar; a toggle when it can be selected, with an optional count.
private struct BarIconButton: View {
    let symbol: String
    let label: String
    var selected = false
    var badge = 0
    let action: () -> Void
    @Environment(\.brand) private var brand

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .brandForeground(selected ? .blue : .quiet)
                .frame(width: brand.space(.xxl), height: brand.space(.xxl))
                .background {
                    if selected { BrandFillBackground(name: .selection, radius: nil).clipShape(Circle()) }
                }
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .brandFont("text.label")
                            .monospacedDigit()
                            .brandForeground(.paper)
                            .padding(.horizontal, brand.space(.xxs))
                            .background(Capsule().fill(brand?.color(.quiet) ?? .secondary))
                            .offset(x: brand.space(.xxs) ?? 2, y: -(brand.space(.xxs) ?? 2))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
