import Domain
import SwiftUI

/// flow: every thought as one long note. Oldest at the top, newest at the bottom (it opens there),
/// day dividers, each thought editable in place. A search highlights matches; ⌘G jumps between them.
struct FlowView: View {
    @Bindable var model: ExploreViewModel
    @Environment(\.calendar) private var calendar
    @Environment(\.brand) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(FlowSections.group(model.flowEntries, calendar: calendar)) { section in
                        Text(section.day, format: .dateTime.weekday(.wide).day().month(.wide).year())
                            .brandFont("display.heading")
                            .padding(.top, 24)
                        ForEach(section.entries) { entry in
                            FlowBlock(
                                entry: entry, isCurrentMatch: model.currentMatch == entry.id,
                                isRelated: model.isRelated(entry.id),
                                highlights: { text in model.highlights(in: text, entryID: entry.id) },
                                meaning: model.meanings[entry.id], kinds: model.conceptKinds,
                                openConcept: { id in Task { await model.openConcept(id) } },
                                reveal: { id in Task { await model.reveal(id) } },
                                saveSummary: { text in Task { await model.saveSummary(text, for: entry.id) } }
                            ) { text in
                                await model.saveFlowText(id: entry.id, text: text)
                            }
                            .id(entry.id)
                            .task { await model.loadMeaning(for: entry.id) }
                            .onDisappear { model.forgetMeaning(for: entry.id) }
                        }
                    }
                    Color.clear.frame(height: 1).id("flow-end")
                }
                .frame(maxWidth: 720)
                .padding(32)
                .frame(maxWidth: .infinity)
            }
            .overlay {
                if model.flowEntries.isEmpty {
                    ContentUnavailableView("no thoughts yet.", systemImage: "text.alignleft")
                }
            }
            .onAppear {
                if let id = model.scrollTarget {
                    proxy.scrollTo(id, anchor: .center)
                } else {
                    proxy.scrollTo("flow-end", anchor: .bottom)
                }
            }
            .onChange(of: model.scrollRequest) { _, request in
                if let request { proxy.scrollTo(request.entryID, anchor: .center) }
            }
            .onChange(of: model.currentMatch) { _, id in
                if let id {
                    withAnimation(reduceMotion ? nil : brand?.animation(\.scroll) ?? .default) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }
}

/// One thought in the flow, editable in place; saved shortly after you stop typing. While a search is active,
/// its words are highlighted in place and a related thought carries a small label.
private struct FlowBlock: View {
    let entry: Entry
    let isCurrentMatch: Bool
    let isRelated: Bool
    let highlights: (String) -> [TextHighlight]
    let meaning: ThoughtMeaning?
    let kinds: [ConceptKind]
    let openConcept: (String) -> Void
    let reveal: (String) -> Void
    let saveSummary: (String?) -> Void
    let save: (String) async -> Void
    @State private var text = ""
    /// The text last handed to save; a newer text from the Archive is only taken while nothing newer is typed.
    @State private var lastSaved = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 4) {
                Image(systemName: entry.source == .typed ? "keyboard" : "waveform")
                Text(entry.createdAt, format: .dateTime.hour().minute())
            }
            .brandFont("text.label")
            .brandForeground(.quiet)
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                if isRelated { RelatedLabel() }
                HighlightingTextEditor(text: $text, highlights: highlights(text), grows: true)
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
                        saveSummary: saveSummary)
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
