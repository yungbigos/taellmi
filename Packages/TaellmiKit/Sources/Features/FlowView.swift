import Domain
import SwiftUI

/// flow: every thought as one long note. Oldest at the top, newest at the bottom (it opens there),
/// day dividers, each thought editable in place. A search highlights matches; ⌘G jumps between them.
struct FlowView: View {
    @Bindable var model: ExploreViewModel
    @Environment(\.calendar) private var calendar

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
                                entry: entry, isMatch: model.flowMatches.contains(entry.id),
                                isCurrentMatch: model.currentMatch == entry.id
                            ) { text in
                                await model.saveFlowText(id: entry.id, text: text)
                            }
                            .id(entry.id)
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
            .onAppear { proxy.scrollTo("flow-end", anchor: .bottom) }
            .onChange(of: model.currentMatch) { _, id in
                if let id { withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }
}

/// One thought in the flow, editable in place; saved shortly after you stop typing.
private struct FlowBlock: View {
    let entry: Entry
    let isMatch: Bool
    let isCurrentMatch: Bool
    let save: (String) async -> Void
    @State private var text = ""
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 4) {
                Image(systemName: entry.source == .typed ? "keyboard" : "waveform")
                Text(entry.createdAt, format: .dateTime.hour().minute())
            }
            .brandFont("text.label")
            .foregroundStyle(.tertiary)
            .frame(width: 44)
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .brandFont("text.thought")
                .lineSpacing(4)
                .onChange(of: text) { _, newText in
                    guard newText != entry.text else { return }
                    saveTask?.cancel()
                    saveTask = Task {
                        try? await Task.sleep(for: .milliseconds(800))
                        guard !Task.isCancelled else { return }
                        await save(newText)
                    }
                }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isMatch ? AnyShapeStyle(.tint.opacity(isCurrentMatch ? 0.22 : 0.08)) : AnyShapeStyle(.clear))
        )
        .onAppear { text = entry.text }
        .onChange(of: entry.text) { _, newText in if newText != text { text = newText } }
    }
}
