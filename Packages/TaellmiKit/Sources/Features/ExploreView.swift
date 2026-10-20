import AVFoundation
import Domain
import SwiftUI

/// The Explore window: filters, the list of Entries with search, and the open Entry.
public struct ExploreView: View {
    @Bindable var model: ExploreViewModel
    @State private var palette: CommandPaletteModel
    @State private var searchFocused = false
    @Environment(\.undoManager) private var undoManager
    @Environment(\.brand) private var brand

    public init(model: ExploreViewModel) {
        self.model = model
        _palette = State(initialValue: CommandPaletteModel(explore: model))
    }

    public var body: some View {
        content
            .brandAnimation(\.crossfade, value: model.view)
            .background { BrandSurfaceBackground(kind: .window, radius: nil).ignoresSafeArea() }
            .toolbar { ToolbarItem(placement: .principal) { viewPicker } }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .background(CommandShortcutButtons(model: model))
            .sheet(isPresented: $model.isPaletteOpen) { CommandPaletteView(palette: palette) }
            .onChange(of: model.searchFocusRequest) { searchFocused = true }
    }

    @ViewBuilder private var content: some View {
        if model.isComposing {
            ComposerView(model: model)
        } else if model.view == .stack || model.showsTrash {
            splitView
        } else {
            wideView
        }
    }

    /// flow and time use the whole width next to the sidebar.
    private var wideView: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            Group {
                if model.view == .flow { FlowView(model: model) } else { TimeView(model: model) }
            }
            .background { readingGround }
        }
        .searchable(text: $model.query.text, isPresented: $searchFocused, prompt: "search")
        .onChange(of: model.query.text) { Task { await model.refresh() } }
        .frame(minWidth: 900, minHeight: 560)
    }

    private var viewPicker: some View {
        Picker("view", selection: Binding(get: { model.view }, set: { view in switchTo(view) })) {
            Text("stack").tag(ExploreViewKind.stack)
            Text("flow").tag(ExploreViewKind.flow)
            Text("time").tag(ExploreViewKind.time)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func switchTo(_ view: ExploreViewKind) {
        let command: Command =
            switch view {
            case .stack: .showStack
            case .flow: .showFlow
            case .time: .showTime
            }
        Task { await model.perform(command) }
    }

    private var splitView: some View {
        NavigationSplitView {
            sidebar
        } content: {
            if model.showsTrash { trashList } else { entryList }
        } detail: {
            Group {
                if let detail = model.detail {
                    // One editor per thought, so undo history never crosses from one thought to another.
                    EntryDetailView(model: model, detail: detail).id(detail.entry.id)
                } else {
                    ContentUnavailableView("no thought selected", systemImage: "text.alignleft")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { readingGround }
        }
        .frame(minWidth: 900, minHeight: 560)
        .task {
            model.startObserving()
            await model.refresh()
        }
    }

    /// The page under your thoughts. It runs on under the toolbar and the sidebar, so both float over it as glass.
    private var readingGround: some View {
        BrandSurfaceBackground(kind: .reading, radius: nil)
            .backgroundExtensionEffect()
            .ignoresSafeArea()
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
        .scrollContentBackground(.hidden)
        .navigationSplitViewColumnWidth(
            min: brand?.space.sidebarWidthPt.min ?? 170, ideal: brand?.space.sidebarWidthPt.ideal ?? 190)
    }

    private func sidebarRow(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Task {
                await model.select(nil)
                await model.refresh()
            }
        } label: {
            Label(title, systemImage: icon)
                .fontWeight(selected ? .medium : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            Group {
                if selected {
                    BrandFillBackground(name: .selection, radius: .field).padding(.horizontal, brand.space(.s))
                }
            })
    }

    private var entryList: some View {
        List(
            model.entries,
            selection: Binding(get: { model.detail?.entry.id }, set: { id in Task { await model.select(id) } })
        ) { entry in
            // One line per thought: what it says, and when. Everything else is in the open thought's details.
            // While searching, the line shows the part around the match with the words marked instead.
            HStack(alignment: .firstTextBaseline, spacing: brand.space(.s)) {
                if let snippet = model.snippets[entry.id] {
                    HighlightedText(text: snippet.text, ranges: snippet.ranges)
                        .lineLimit(1)
                        .brandForeground(.ink)
                } else {
                    Text(entry.text.isEmpty ? "transcribing …" : CaptureViewModel.preview(of: entry))
                        .lineLimit(1)
                        .brandForeground(entry.text.isEmpty ? .quiet : .ink)
                }
                Spacer(minLength: brand.space(.s))
                if model.isRelated(entry.id) { RelatedLabel() }
                Text(ThoughtMeta.short(entry.createdAt))
                    .brandFont("text.label").monospacedDigit().brandForeground(.quiet)
            }
            .padding(.vertical, brand.space(.xs))
            .listRowSeparator(.hidden)
            .tag(entry.id)
        }
        .scrollContentBackground(.hidden)
        .searchable(text: $model.query.text, isPresented: $searchFocused, prompt: "search")
        .onChange(of: model.query.text) { Task { await model.refresh() } }
        .overlay {
            if model.entries.isEmpty {
                ContentUnavailableView(
                    model.query.text.isEmpty ? "no thoughts yet." : "nothing found.", systemImage: "magnifyingglass"
                )
            }
        }
        .navigationSplitViewColumnWidth(
            min: brand?.space.listWidthPt.min ?? 240, ideal: brand?.space.listWidthPt.ideal ?? 300)
    }

    private var trashList: some View {
        List(model.trashedEntries) { item in
            HStack(alignment: .firstTextBaseline, spacing: brand.space(.s)) {
                Text(item.entry.text).lineLimit(1)
                Spacer(minLength: brand.space(.s))
                Text(ThoughtMeta.short(item.entry.createdAt))
                    .brandFont("text.label").monospacedDigit().brandForeground(.quiet)
                Button("restore") { Task { await model.restore(item) } }
                Button("delete for good", role: .destructive) { Task { await model.deleteForever(item) } }
                    .help("moves the thought to the macOS Trash.")
            }
            .padding(.vertical, brand.space(.xs))
            .listRowSeparator(.hidden)
        }
        .scrollContentBackground(.hidden)
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

/// The open Entry: only your text, in a calm reading column, under one quiet line of when and how. Its details
/// (recording, transcript, spellings) live in the inspector on the right.
struct EntryDetailView: View {
    @Bindable var model: ExploreViewModel
    let detail: EntryDetail
    @Environment(\.undoManager) private var undoManager
    @Environment(\.brand) private var brand
    @AppStorage("explore.showsDetails") private var showsDetails = true

    var body: some View {
        VStack(alignment: .leading, spacing: brand.space(.l)) {
            Text(
                ThoughtMeta.line(
                    createdAt: detail.entry.createdAt, source: detail.entry.source,
                    durationSeconds: detail.entry.durationSeconds)
            )
            .brandFont("text.label")
            .brandForeground(.quiet)
            HighlightingTextEditor(
                text: $model.editorText,
                highlights: model.highlights(in: model.editorText, entryID: detail.entry.id),
                scrollKey: detail.entry.id + "|" + model.query.text
            )
        }
        .frame(maxWidth: brand.map { CGFloat($0.space.readingWidthPt) } ?? .infinity, alignment: .leading)
        .padding(.horizontal, brand.space(.xxxl))
        .padding(.top, brand.space(.xl))
        .padding(.bottom, brand.space(.l))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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
                .help("delete thought")
                Button {
                    showsDetails.toggle()
                } label: {
                    Label("details", systemImage: "sidebar.right")
                }
                .help(showsDetails ? "hide details" : "show details")
            }
        }
        .inspector(isPresented: $showsDetails) {
            ThoughtDetailsView(detail: detail, playbackRequest: model.playbackRequest)
                .inspectorColumnWidth(
                    min: brand?.space.inspectorWidthPt.min ?? 220, ideal: brand?.space.inspectorWidthPt.ideal ?? 260,
                    max: brand?.space.inspectorWidthPt.max ?? 340)
        }
        .onDisappear { Task { await model.saveIfNeeded() } }
    }
}

/// The inspector next to an open thought. People, places, topics and connections join here once tällmi
/// finds them.
struct ThoughtDetailsView: View {
    let detail: EntryDetail
    let playbackRequest: Int
    @Environment(\.brand) private var brand

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: brand.space(.xl)) {
                section("about") {
                    row(ThoughtMeta.sourceWord(detail.entry.source))
                    row(detail.entry.createdAt.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                    row(detail.entry.createdAt.formatted(date: .omitted, time: .shortened))
                    row("\(detail.entry.text.split(whereSeparator: \.isWhitespace).count) words")
                }
                if !detail.corrections.isEmpty {
                    section("spellings") {
                        ForEach(Array(detail.corrections.enumerated()), id: \.offset) { _, correction in
                            row("\(correction.from) → \(correction.to)")
                        }
                    }
                }
                if detail.entry.source == .voice {
                    section("recording") {
                        RecordingSection(detail: detail, playbackRequest: playbackRequest)
                    }
                }
            }
            .padding(.all, brand.space(.l))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: brand.space(.s)) {
            Text(title).brandFont("text.label").brandForeground(.quiet)
            content()
        }
    }

    private func row(_ text: String) -> some View {
        Text(text.lowercased())
    }
}

/// Player plus the Transcript as sentences that jump to their moment in the audio.
struct RecordingSection: View {
    let detail: EntryDetail
    /// Changes when the "play or pause recording" command runs.
    let playbackRequest: Int
    @State private var player: AVPlayer?
    @Environment(\.brand) private var brand

    var body: some View {
        Group {
            if let url = detail.recordingURL {
                VStack(alignment: .leading, spacing: brand.space(.m)) {
                    HStack(spacing: brand.space(.s)) {
                        Button {
                            togglePlayback(url: url)
                        } label: {
                            Label("play / pause", systemImage: "playpause.fill")
                        }
                        if let duration = detail.entry.durationSeconds {
                            Text(Duration.seconds(duration), format: .time(pattern: .minuteSecond))
                                .monospacedDigit().brandForeground(.quiet)
                        }
                    }
                    VStack(alignment: .leading, spacing: brand.space(.s)) {
                        ForEach(Array(detail.segments.enumerated()), id: \.offset) { _, segment in
                            Button {
                                jump(to: segment, url: url)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: brand.space(.s)) {
                                    Text(
                                        Duration.milliseconds(segment.startMs),
                                        format: .time(pattern: .minuteSecond)
                                    )
                                    .brandFont("text.label").monospacedDigit().brandForeground(.quiet)
                                    Text(segment.text).multilineTextAlignment(.leading)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text("recording deleted.").brandForeground(.quiet)
            }
        }
        .onChange(of: detail.entry.id) {
            player?.pause()
            player = nil
        }
        .onChange(of: playbackRequest) {
            guard let url = detail.recordingURL else { return }
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
