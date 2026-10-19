import AVFoundation
import Domain
import SwiftUI

/// The Explore window: filters, the list of Entries with search, and the open Entry.
public struct ExploreView: View {
    @Bindable var model: ExploreViewModel
    @Environment(\.undoManager) private var undoManager

    public init(model: ExploreViewModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            if model.showsTrash { trashList } else { entryList }
        } detail: {
            if let detail = model.detail {
                EntryDetailView(model: model, detail: detail)
            } else {
                ContentUnavailableView("Kein Eintrag gewählt", systemImage: "text.alignleft")
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .task {
            model.startObserving()
            await model.refresh()
        }
    }

    private var sidebar: some View {
        List {
            Section("Zeitraum") {
                ForEach(EntryQuery.Period.allCases, id: \.self) { period in
                    sidebarRow(
                        Self.label(for: period), icon: "calendar",
                        selected: !model.showsTrash && model.query.period == period
                    ) {
                        model.showsTrash = false
                        model.query.period = period
                    }
                }
            }
            Section("Quelle") {
                sidebarRow("Alle", icon: "tray.full", selected: model.query.sources == nil) {
                    model.query.sources = nil
                }
                sidebarRow("Gesprochen", icon: "waveform", selected: model.query.sources == [.voice]) {
                    model.query.sources = [.voice]
                }
                sidebarRow("Getippt", icon: "keyboard", selected: model.query.sources == [.typed]) {
                    model.query.sources = [.typed]
                }
            }
            Section {
                sidebarRow("Papierkorb", icon: "trash", selected: model.showsTrash) { model.showsTrash = true }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 170, ideal: 190)
    }

    private func sidebarRow(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Task {
                await model.select(nil)
                await model.refresh()
            }
        } label: {
            Label(title, systemImage: icon).fontWeight(selected ? .semibold : .regular)
        }
        .buttonStyle(.plain)
    }

    private var entryList: some View {
        List(
            model.entries,
            selection: Binding(get: { model.detail?.entry.id }, set: { id in Task { await model.select(id) } })
        ) { entry in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Image(systemName: entry.source == .typed ? "keyboard" : "waveform").foregroundStyle(.secondary)
                    Text(entry.createdAt, format: .dateTime.weekday().day().month().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(entry.text.isEmpty ? "Wird transkribiert …" : entry.text)
                    .lineLimit(2)
                    .foregroundStyle(entry.text.isEmpty ? .secondary : .primary)
            }
            .padding(.vertical, 2)
            .tag(entry.id)
        }
        .searchable(text: $model.query.text, prompt: "Suchen")
        .onChange(of: model.query.text) { Task { await model.refresh() } }
        .overlay {
            if model.entries.isEmpty {
                ContentUnavailableView(
                    model.query.text.isEmpty ? "Noch keine Einträge" : "Nichts gefunden", systemImage: "magnifyingglass"
                )
            }
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: 320)
    }

    private var trashList: some View {
        List(model.trashedEntries) { item in
            HStack {
                VStack(alignment: .leading) {
                    Text(item.entry.createdAt, format: .dateTime.day().month().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                    Text(item.entry.text).lineLimit(2)
                }
                Spacer()
                Button("Wiederherstellen") { Task { await model.restore(item) } }
                Button("Löschen", role: .destructive) { Task { await model.deleteForever(item) } }
                    .help("Legt den Eintrag in den Papierkorb von macOS.")
            }
        }
        .overlay {
            if model.trashedEntries.isEmpty { ContentUnavailableView("Papierkorb ist leer", systemImage: "trash") }
        }
    }

    static func label(for period: EntryQuery.Period) -> String {
        switch period {
        case .all: "Alle"
        case .today: "Heute"
        case .week: "Letzte 7 Tage"
        case .month: "Letzte 30 Tage"
        case .year: "Letztes Jahr"
        }
    }
}

/// The open Entry: its Text (editable, saved automatically) and, if still kept, its Recording.
struct EntryDetailView: View {
    @Bindable var model: ExploreViewModel
    let detail: EntryDetail
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(detail.entry.createdAt, format: .dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    Task {
                        await model.trashSelected()
                        undoManager?.registerUndo(withTarget: model) { model in
                            Task { await model.undoTrash() }
                        }
                        undoManager?.setActionName("Eintrag löschen")
                    }
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
            TextEditor(text: $model.editorText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            if !detail.corrections.isEmpty {
                Text("Vokabular: " + detail.corrections.map { "\($0.from) → \($0.to)" }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if detail.entry.source == .voice {
                RecordingSection(detail: detail)
            }
        }
        .padding()
        .onDisappear { Task { await model.saveIfNeeded() } }
    }
}

/// Player plus the Transcript as sentences that jump to their moment in the audio.
struct RecordingSection: View {
    let detail: EntryDetail
    @State private var player: AVPlayer?
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup("Aufnahme", isExpanded: $isExpanded) {
            if let url = detail.recordingURL {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button {
                            togglePlayback(url: url)
                        } label: {
                            Label("Abspielen / Pause", systemImage: "playpause.fill")
                        }
                        if let duration = detail.entry.durationSeconds {
                            Text(Duration.seconds(duration), format: .time(pattern: .minuteSecond))
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(detail.segments.enumerated()), id: \.offset) { _, segment in
                                Button {
                                    jump(to: segment, url: url)
                                } label: {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(
                                            Duration.milliseconds(segment.startMs),
                                            format: .time(pattern: .minuteSecond)
                                        )
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                        Text(segment.text).multilineTextAlignment(.leading)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }
            } else {
                Text("Aufnahme gelöscht").foregroundStyle(.secondary)
            }
        }
        .onChange(of: detail.entry.id) {
            player?.pause()
            player = nil
        }
    }

    private func preparedPlayer(url: URL) -> AVPlayer {
        if let player { return player }
        let fresh = AVPlayer(url: url)
        player = fresh
        return fresh
    }

    private func togglePlayback(url: URL) {
        let player = preparedPlayer(url: url)
        if player.timeControlStatus == .playing { player.pause() } else { player.play() }
    }

    private func jump(to segment: TranscriptSegment, url: URL) {
        let player = preparedPlayer(url: url)
        player.seek(to: CMTime(value: CMTimeValue(segment.startMs), timescale: 1000))
        player.play()
    }
}
