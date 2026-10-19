import Domain
import SwiftUI

/// ⌘K: type to find a thought or a command; arrows move, return runs, esc closes.
struct CommandPaletteView: View {
    @Bindable var palette: CommandPaletteModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("search or run a command …", text: $palette.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(14)
                .focused($focused)
                .onChange(of: palette.query) { _, text in Task { await palette.update(query: text) } }
                .onKeyPress(.downArrow) {
                    palette.moveHighlight(by: 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    palette.moveHighlight(by: -1)
                    return .handled
                }
                .onKeyPress(.return) {
                    Task { await palette.chooseHighlighted() }
                    return .handled
                }
                .onKeyPress(.escape) {
                    palette.isPresented = false
                    return .handled
                }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(palette.results.enumerated()), id: \.element.id) { index, item in
                            row(item, highlighted: index == palette.highlighted)
                                .id(item.id)
                                .onTapGesture { Task { await palette.choose(item) } }
                        }
                    }
                }
                .onChange(of: palette.highlighted) { _, index in
                    if palette.results.indices.contains(index) { proxy.scrollTo(palette.results[index].id) }
                }
            }
            .frame(height: 300)
        }
        .frame(width: 520)
        .task {
            focused = true
            await palette.update(query: palette.query)
        }
    }

    private func row(_ item: PaletteItem, highlighted: Bool) -> some View {
        HStack {
            Image(systemName: icon(for: item)).foregroundStyle(.secondary).frame(width: 18)
            Text(item.title).lineLimit(1)
            Spacer()
            if let shortcut = item.shortcut {
                Text(shortcut).font(.callout.monospaced()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(highlighted ? Color.accentColor.opacity(0.18) : .clear)
        .contentShape(Rectangle())
    }

    private func icon(for item: PaletteItem) -> String {
        if case .thought = item.kind { return "text.alignleft" }
        return "command"
    }
}
