import AVFoundation
import Domain
import SwiftUI

/// The Explore window: filters, the list of Entries with search, and the open Entry.
public struct ExploreView: View {
    @Bindable var model: ExploreViewModel
    @State private var palette: CommandPaletteModel
    @State private var searchFocused = false
    @Environment(\.undoManager) private var undoManager

    public init(model: ExploreViewModel) {
        self.model = model
        _palette = State(initialValue: CommandPaletteModel(explore: model))
    }

    public var body: some View {
        Group {
            if model.isComposing {
                ComposerView(model: model)
            } else {
                splitView
            }
        }
    }

    private var splitView: some View {
        NavigationSplitView {
            sidebar
        } content: {
            if model.showsTrash { trashList } else { entryList }
        } detail: {
            if let detail = model.detail {
                EntryDetailView(model: model, detail: detail)
            } else {
                ContentUnavailableView("no thought selected", systemImage: "text.alignleft")
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(CommandShortcutButtons(model: model))
        .sheet(isPresented: $model.isPaletteOpen) {
            CommandPaletteView(palette: palette)
        }
        .onChange(of: model.searchFocusRequest) { searchFocused = true }
        .task {
            model.startObserving()
            await model.refresh()
        }
    }

    private var sidebar: some View {
        List {
            Section("time") {
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
            Section("source") {
                sidebarRow("all", icon: "tray.full", selected: model.query.sources == nil) {
                    model.query.sources = nil
                }
                sidebarRow("spoken", icon: "waveform", selected: model.query.sources == [.voice]) {
                    model.query.sources = [.voice]
                }
                sidebarRow("typed", icon: "keyboard", selected: model.query.sources == [.typed]) {
                    model.query.sources = [.typed]
                }
            }
            Section {
                sidebarRow("trash", icon: "trash", selected: model.showsTrash) { model.showsTrash = true }
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
                Text(entry.text.isEmpty ? "transcribing …" : entry.text)
                    .lineLimit(2)
                    .foregroundStyle(entry.text.isEmpty ? .secondary : .primary)
            }
            .padding(.vertical, 2)
            .tag(entry.id)
        }
        .searchable(text: $model.query.text, isPresented: $searchFocused, prompt: "search")
        .onChange(of: model.query.text) { Task { await model.refresh() } }
        .overlay {
            if model.entries.isEmpty {
                ContentUnavailableView(
                    model.query.text.isEmpty ? "no thoughts yet." : "nothing found.", systemImage: "magnifyingglass"
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
                Button("restore") { Task { await model.restore(item) } }
                Button("delete for good", role: .destructive) { Task { await model.deleteForever(item) } }
                    .help("moves the thought to the macOS Trash.")
            }
        }
        .overlay {
            if model.trashedEntries.isEmpty { ContentUnavailableView("trash is empty.", systemImage: "trash") }
        }
    }

    static func label(for period: EntryQuery.Period) -> String {
        switch period {
        case .all: "all"
        case .today: "today"
        case .week: "last 7 days"
        case .month: "last 30 days"
        case .year: "last year"
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
                        undoManager?.setActionName("delete thought")
                    }
                } label: {
                    Label("delete thought", systemImage: "trash")
                }
            }
            TextEditor(text: $model.editorText)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            if !detail.corrections.isEmpty {
                Text("spellings: " + detail.corrections.map { "\($0.from) → \($0.to)" }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if detail.entry.source == .voice {
                RecordingSection(detail: detail, playbackRequest: model.playbackRequest)
            }
        }
        .padding()
        .onDisappear { Task { await model.saveIfNeeded() } }
    }
}

/// Player plus the Transcript as sentences that jump to their moment in the audio.
struct RecordingSection: View {
    let detail: EntryDetail
    /// Changes when the "play or pause recording" command runs.
    let playbackRequest: Int
    @State private var player: AVPlayer?
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup("recording", isExpanded: $isExpanded) {
            if let url = detail.recordingURL {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Button {
                            togglePlayback(url: url)
                        } label: {
                            Label("play / pause", systemImage: "playpause.fill")
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
                Text("recording deleted.").foregroundStyle(.secondary)
            }
        }
        .onChange(of: detail.entry.id) {
            player?.pause()
            player = nil
        }
        .onChange(of: playbackRequest) {
            guard let url = detail.recordingURL else { return }
            isExpanded = true
            togglePlayback(url: url)
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
