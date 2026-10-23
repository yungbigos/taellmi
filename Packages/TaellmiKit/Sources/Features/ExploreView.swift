import AVFoundation
import Domain
import SwiftUI

/// The Explore window: the view you chose, with a floating bar at the bottom that holds that view's filters
/// (issue #45). There is no sidebar.
public struct ExploreView: View {
    @Bindable var model: ExploreViewModel
    /// The pointer in this window, for the tälli in the title to watch.
    let cursor: (@MainActor () -> CGPoint?)?
    @State private var palette: CommandPaletteModel
    @State private var talliPokes = 0
    @Environment(\.undoManager) private var undoManager
    @Environment(\.brand) private var brand

    public init(model: ExploreViewModel, cursor: (@MainActor () -> CGPoint?)? = nil) {
        self.model = model
        self.cursor = cursor
        _palette = State(initialValue: CommandPaletteModel(explore: model))
    }

    public var body: some View {
        content
            .brandAnimation(\.crossfade, value: model.view)
            .background { BrandSurfaceBackground(kind: .window, radius: nil).ignoresSafeArea() }
            .toolbar {
                ToolbarItem(placement: .navigation) { titleTalli }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .principal) { viewPicker }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await model.perform(.openPalette) }
                    } label: {
                        Label("search", systemImage: "magnifyingglass")
                    }
                    .help("search or run a command")
                    Button {
                        Task { await model.perform(.newThought) }
                    } label: {
                        Label("new thought", systemImage: "plus")
                    }
                    .help("new thought: speak or type")
                }
            }
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .background(CommandShortcutButtons(model: model))
            .sheet(isPresented: $model.isPaletteOpen) { CommandPaletteView(palette: palette) }
            .sheet(item: $model.conceptEdit) { edit in ConceptEditSheet(model: model, edit: edit).brandStyle(brand) }
            .onChange(of: model.noteImportRequest) {
                // After this view update (the ⌘K sheet may still be closing), so the picker doesn't block it.
                Task { @MainActor in
                    await Task.yield()
                    let chosen = ImportFilePicker.choose(explaining: ImportFilePicker.notesExplanation)
                    if !chosen.isEmpty { await model.importNotes(from: chosen) }
                }
            }
            .onChange(of: model.chatImportRequest) {
                Task { @MainActor in
                    await Task.yield()
                    let chosen = ImportFilePicker.choose(explaining: ImportFilePicker.chatExplanation)
                    if !chosen.isEmpty { await model.importChats(from: chosen) }
                }
            }
            .overlay(alignment: .top) {
                if let progress = model.importProgress {
                    Text(progress).brandForeground(.quiet).padding()
                }
            }
            .alert(
                model.importMessage ?? "",
                isPresented: Binding(
                    get: { model.importMessage != nil }, set: { if !$0 { model.importMessage = nil } })
            ) {
                Button("ok") {}
            }
            .onChange(of: model.query.text) { Task { await model.refresh() } }
            .frame(minWidth: 900, minHeight: 560)
    }

    @ViewBuilder private var content: some View {
        if model.isComposing {
            ComposerView(model: model)
        } else {
            mainView
                .safeAreaInset(edge: .bottom, spacing: 0) { ExploreBarView(model: model) }
        }
    }

    @ViewBuilder private var mainView: some View {
        if model.showsTrash {
            trashList.background { readingGround }
        } else {
            switch model.view {
            case .stack: StackView(model: model).background { readingGround }
            case .flow:
                // The rail floats over the page, at the side of the reading column.
                FlowView(model: model)
                    .background { readingGround }
                    .overlay(alignment: .trailing) { MonthRailView(model: model) }
            case .time:
                // Next to the axis, so it never covers the newest marks.
                HStack(spacing: 0) {
                    TimeView(model: model)
                    MonthRailView(model: model)
                }
                .background { readingGround }
            case .space: SpaceView(model: model).background { readingGround }
            }
        }
    }

    /// tälli in place of the window title: it watches the cursor like the floating one, and a click pokes it.
    private var titleTalli: some View {
        TalliView(mood: .idle, entrance: nil, cursor: cursor, pokes: talliPokes)
            .frame(width: brand.space(.xxl), height: brand.space(.xxl))
            .contentShape(Rectangle())
            .onTapGesture { talliPokes += 1 }
            .accessibilityLabel("tällmi")
    }

    private var viewPicker: some View {
        ViewSwitcher(current: model.view, views: model.availableViews) { view in switchTo(view) }
    }

    private func switchTo(_ view: ExploreViewKind) {
        let command: Command =
            switch view {
            case .stack: .showStack
            case .flow: .showFlow
            case .time: .showTime
            case .space: .showSpace
            }
        Task { await model.perform(command) }
    }

    /// The page under your thoughts. It runs on under the toolbar and the bar, so both float over it as glass.
    private var readingGround: some View {
        BrandSurfaceBackground(kind: .reading, radius: nil)
            .backgroundExtensionEffect()
            .ignoresSafeArea()
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
        .frame(maxWidth: brand.map { CGFloat($0.space.readingWidthPt) } ?? .infinity)
        .frame(maxWidth: .infinity)
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

/// The inspector next to an open thought. People, places, topics and connections join here once tällmi
/// finds them.
struct ThoughtDetailsView: View {
    let detail: EntryDetail
    let playbackRequest: Int
    /// Set for imported thoughts, whose date can be changed.
    var changeDate: ((Date) -> Void)?
    @Environment(\.brand) private var brand

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: brand.space(.xl)) {
                section("about") {
                    row(ThoughtMeta.sourceWord(detail.entry.source))
                    row(detail.entry.createdAt.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                    row(detail.entry.createdAt.formatted(date: .omitted, time: .shortened))
                    if let changeDate {
                        ChangeDateButton(date: detail.entry.createdAt, save: changeDate) {
                            Text("change date …").underline()
                        }
                        Text("imported notes are dated by their file. set when you wrote it.")
                            .brandFont("text.label").brandForeground(.quiet)
                    }
                    row("\(WordsOnlyText(detail.entry.text).wordCount) words")
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
