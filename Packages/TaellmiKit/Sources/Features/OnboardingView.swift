import AppKit
import Domain
import SwiftUI

// The first launch, one step at a time (docs/brand.md: one loud thing per screen, calm words, tälli peeking).
struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    var talli: OnboardingTalliSizes
    var cursor: (@MainActor () -> CGPoint?)?
    var close: () -> Void
    @Environment(\.brand) private var brand

    static let size = CGSize(width: 620, height: 500)

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .padding(.horizontal, brand.space(.xxxl))
                .padding(.top, brand.space(.xxxl))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let progress = model.progress { progressMarks(progress) }
            if model.step == .hello {
                peeking(TalliView(mood: .idle, entrance: .roll, cursor: cursor), size: talli.hello)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, brand.space(.xxl))
            } else {
                peeking(TalliView(mood: talliMood, entrance: .rise, cursor: cursor), size: talli.corner)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, brand.space(.xl))
            }
        }
        // Fills the window, which has the onboarding's size; a fixed size here made the window grow by the title bar.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .brandAnimation(\.crossfade, value: model.step)
        .onChange(of: model.isFinished) { _, finished in if finished { close() } }
        // Back from System Settings or the Finder: the microphone may be allowed now, or a model added.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
    }

    private var talliMood: TalliMood {
        if model.isListening { return .listening(level: model.listeningLevel) }
        return model.step == .callTalli && model.firstThoughtID != nil ? .saved : .idle
    }

    @ViewBuilder private var content: some View {
        switch model.step {
        case .hello: hello
        case .voice: voice
        case .microphone: microphone
        case .callTalli: if model.firstThoughtID == nil { callTalli } else { firstThought }
        case .recoveryKey: recoveryKey
        case .extras: extras
        }
    }

    // MARK: Steps

    private var hello: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark(size: brand.map { $0.nsFont("display.title").pointSize } ?? 0)
            Spacer().frame(height: brand.space(.xxl))
            Text("think\nout loud.").brandFont("display.moment")
            Text("äh included.").brandFont("display.heading").padding(.top, brand.space(.l))
            Text("(äh: german for \"uh\", the sound of thinking.)").brandFont("text.whisper").brandForeground(.quiet)
            Text(
                "say it the way it comes: unfinished, german and english mixed. tällmi keeps every word on this mac and finds it again later."
            )
            .brandForeground(.quiet)
            .frame(maxWidth: 300, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, brand.space(.l))
            HStack(spacing: brand.space(.l)) {
                Button("start") { model.next() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                Button("open thoughts from another mac …") {
                    if let folder = FolderPicker.choose(
                        prompt: "open",
                        message: "pick the folder that holds your tällmi folder, for example in iCloud Drive.")
                    {
                        Task { await model.useStorage(inside: folder) }
                    }
                }
                .buttonStyle(.link)
            }
            .padding(.top, brand.space(.xl))
            if let message = model.storageMessage {
                Text(message).brandFont("text.label").brandForeground(.quiet).padding(.top, brand.space(.s))
            }
        }
    }

    private var voice: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("what tällmi needs to understand you.").brandFont("display.title")
            Text(
                "these run only on this mac, and nothing you say leaves it. getting them right here comes in a later version; the tällmi page on GitHub shows how to add them by hand. until then, spoken thoughts wait for their text."
            )
            .brandForeground(.quiet)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, brand.space(.m))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.voiceModels.enumerated()), id: \.element.id) { index, status in
                    if index > 0 { Divider().padding(.horizontal, brand.space(.l)) }
                    voiceRow(status)
                }
            }
            .brandFill(.field)
            .padding(.top, brand.space(.l))
            if let line = OnboardingModel.builtInLine(for: model.builtInRoles) {
                Text(line).brandFont("text.label").brandForeground(.quiet).padding(.top, brand.space(.m))
            }
            Spacer()
            footer {
                Button("show where they go") { model.showModelsFolder() }.buttonStyle(.link)
                Spacer()
                Button("continue") { model.next() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func voiceRow(_ status: VoiceModelStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: brand.space(.m)) {
            VStack(alignment: .leading, spacing: brand.space(.xxs)) {
                HStack(alignment: .firstTextBaseline, spacing: brand.space(.s)) {
                    if let word = Self.roleWord(status.role) { Text(word) }
                    Text(status.name).brandFont("text.label").brandForeground(.quiet).lineLimit(1)
                }
                if let purpose = Self.purpose(status.role) { Text(purpose).brandForeground(.quiet) }
            }
            Spacer(minLength: brand.space(.s))
            Text(
                status.isInstalled
                    ? "on this mac" : ByteCountFormatter.string(fromByteCount: status.bytes, countStyle: .file)
            )
            .brandFont("text.label")
            .brandForeground(.quiet)
            .monospacedDigit()
        }
        .padding(.horizontal, brand.space(.l))
        .padding(.vertical, brand.space(.m))
    }

    private var microphone: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("tälli listens only when you call it.").brandFont("display.title")
            Text("macOS asks next whether tällmi may use the microphone. every recording stays on this mac.")
                .brandForeground(.quiet)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, brand.space(.m))
            VStack(alignment: .leading, spacing: 0) {
                micRow(
                    listening: true, title: "tälli is out",
                    text: "the microphone is on, and the dots pulse with your voice.")
                Divider().padding(.horizontal, brand.space(.l))
                micRow(listening: false, title: "tälli is gone", text: "the microphone is off.")
            }
            .brandFill(.field)
            .padding(.top, brand.space(.xl))
            Spacer()
            if model.microphone == .denied {
                Text("i can't hear you. allow the microphone in system settings.")
                    .padding(.all, brand.space(.s))
                    .frame(maxWidth: 260, alignment: .leading)
                    .brandSurface(.bubble, radius: .bubble)
                    .padding(.leading, brand.space(.xxxl))
                    .padding(.bottom, brand.space(.s))
            }
            footer {
                Spacer()
                Button("type instead") { model.next() }
                if model.microphone == .denied {
                    Button("open system settings") { model.openMicrophoneSettings() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("allow the microphone") { Task { await model.allowMicrophone() } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func micRow(listening: Bool, title: String, text: String) -> some View {
        HStack(spacing: brand.space(.m)) {
            Image(nsImage: MenuBarDots.image(listening: listening, tokens: brand))
                .accessibilityHidden(true)
            Text(title).frame(width: 110, alignment: .leading)
            Text(text).brandForeground(.quiet).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, brand.space(.l))
        .padding(.vertical, brand.space(.m))
    }

    private var callTalli: some View {
        callTalliContent.shortcutConflictAlert(model.shortcut)
    }

    private var callTalliContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.isListening ? "tälli is listening." : "call tälli from anywhere.").brandFont("display.title")
            Text(
                model.isListening
                    ? "say your first thought, the way it comes. press the keys again, or \(model.finishKey), to save it."
                    : "try it now: press these keys in any app and say a first thought. anything goes, even an äh. press them again, or \(model.finishKey), to save it."
            )
            .brandForeground(.quiet)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, brand.space(.m))
            if model.keycaps.isEmpty {
                HotkeyRecorder(model: model.shortcut, title: "set a shortcut …")
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, brand.space(.xxl))
            } else {
                HStack(alignment: .top, spacing: brand.space(.m)) {
                    ForEach(Array(model.keycaps.enumerated()), id: \.offset) { _, key in keycap(key) }
                }
                .padding(.top, brand.space(.xxl))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("the shortcut: \(model.keycaps.map(Self.keyName).joined(separator: ", "))")
            }
            if model.shortcut.isRecording {
                Text("press the new keys. esc keeps the old ones.")
                    .brandFont("text.label")
                    .padding(.top, brand.space(.l))
            } else if let warning = model.shortcut.warning {
                Text(warning).brandFont("text.label").brandStatus(.warning).padding(.top, brand.space(.l))
            }
            Text("no microphone at hand? type in tälli's bubble instead.")
                .brandFont("text.label")
                .brandForeground(.quiet)
                .padding(.top, brand.space(.xl))
            Spacer()
            footer {
                if !model.keycaps.isEmpty {
                    HotkeyRecorder(model: model.shortcut, title: "change the shortcut …").buttonStyle(.link)
                }
                Spacer()
                if !model.keycaps.isEmpty {
                    Text(model.isListening ? "listening …" : "waiting for \(model.keycaps.joined()) …")
                        .brandForeground(.quiet)
                }
                Button("skip") { model.next() }
            }
        }
    }

    private func keycap(_ key: String) -> some View {
        VStack(spacing: brand.space(.s)) {
            Text(key)
                .brandFont("display.title")
                .frame(width: 72, height: 72)
                // Lit while tälli listens: the press arrived.
                .brandFill(model.isListening ? .selection : .field, radius: .panel)
            Text(Self.keyName(key)).brandFont("text.label").brandForeground(.quiet)
        }
    }

    private var firstThought: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("your first thought.").brandFont("display.title")
            HStack(alignment: .top, spacing: brand.space(.s)) {
                VStack(spacing: brand.space(.xs)) {
                    Image(systemName: ThoughtMeta.sourceSymbol(model.firstThought?.source ?? .voice))
                    if let date = model.firstThought?.createdAt {
                        Text(date, format: .dateTime.hour().minute())
                    }
                }
                .brandFont("text.label")
                .brandForeground(.quiet)
                .frame(width: 44)
                Group {
                    if let heard = model.firstThoughtPreview {
                        // The live preview, until the real text replaces it; never shown as your words.
                        Text(heard).brandForeground(.quiet)
                    } else {
                        Text(model.firstThought.map { CaptureViewModel.preview(of: $0, maxLength: .max) } ?? "saved.")
                    }
                }
                .brandFont("text.thought")
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.all, brand.space(.l))
            .brandSurface(.reading, radius: .panel)
            .padding(.top, brand.space(.xl))
            if let note = firstThoughtNote {
                Text(note)
                    .brandFont("text.whisper")
                    .brandForeground(.quiet)
                    .padding(.top, brand.space(.s))
            }
            Text(
                "it's saved on this mac, word for word, äh included. you'll find it in tällmi under today."
            )
            .brandForeground(.quiet)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, brand.space(.l))
            Spacer()
            footer {
                Spacer()
                Button("continue") { model.next() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // Says why the first thought shows no text yet, and what is shown instead.
    private var firstThoughtNote: String? {
        let waiting = model.firstThought?.source == .voice && model.firstThought?.text.isEmpty != false
        switch (model.firstThoughtPreview != nil, model.canHearYet) {
        case (true, true): return "what tälli heard. the exact text follows in a moment."
        case (true, false):
            return "what tälli heard. the exact text comes once speech recognition is set up on this mac."
        case (false, false) where waiting:
            return "its text comes once speech recognition is set up on this mac. the recording is kept until then."
        default: return nil
        }
    }

    @ViewBuilder private var recoveryKey: some View {
        if let key = model.recoveryKey {
            VStack(alignment: .leading, spacing: 0) {
                Text("your recovery key.").brandFont("display.title")
                RecoveryKeyFields(model: key) { await model.confirmRecoveryKey() }
                    .padding(.top, brand.space(.m))
                HStack(spacing: brand.space(.s)) {
                    Text("your thoughts are stored \(model.storageLocation).").brandForeground(.quiet)
                    Button("choose a folder …") {
                        if let folder = FolderPicker.choose(prompt: "store here") {
                            Task { await model.useStorage(inside: folder) }
                        }
                    }
                    .buttonStyle(.link)
                }
                .brandFont("text.label")
                .padding(.top, brand.space(.l))
                if let message = model.storageMessage {
                    Text(message).brandFont("text.label").brandForeground(.quiet).padding(.top, brand.space(.xs))
                }
            }
        }
    }

    private var extras: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("a few more things, if you like.").brandFont("display.title")
            VStack(alignment: .leading, spacing: 0) {
                extraRow(
                    title: "open tällmi at login", text: "tälli is there as soon as your mac is.",
                    isOn: Binding(
                        get: { model.opensAtLogin }, set: { on in Task { await model.setOpensAtLogin(on) } }))
                Divider().padding(.horizontal, brand.space(.l))
                extraRow(
                    title: "use contacts for spellings",
                    text: "names are written the way your contacts spell them: Kim, not Kym.",
                    isOn: Binding(
                        get: { model.usesContacts }, set: { on in Task { await model.setUsesContacts(on) } }))
                Divider().padding(.horizontal, brand.space(.l))
                VStack(alignment: .leading, spacing: brand.space(.s)) {
                    VStack(alignment: .leading, spacing: brand.space(.xxs)) {
                        Text("bring in your notes")
                        Text("each note or message becomes a thought, dated when you wrote it.")
                            .brandForeground(.quiet)
                    }
                    HStack {
                        Button("from apple notes …") {
                            let chosen = ImportFilePicker.choose(explaining: ImportFilePicker.notesExplanation)
                            Task { await model.importNotes(from: chosen) }
                        }
                        Button("from whatsapp …") {
                            let chosen = ImportFilePicker.choose(explaining: ImportFilePicker.chatExplanation)
                            Task { await model.importChats(from: chosen) }
                        }
                    }
                    .disabled(model.isImporting)
                    if let message = model.importMessage {
                        Text(message).brandFont("text.label").brandForeground(.quiet)
                    }
                }
                .padding(.horizontal, brand.space(.l))
                .padding(.vertical, brand.space(.m))
            }
            .brandFill(.field)
            .padding(.top, brand.space(.xl))
            Text("you can change all of this later in settings.")
                .brandFont("text.label")
                .brandForeground(.quiet)
                .padding(.top, brand.space(.m))
            Spacer()
            footer {
                Spacer()
                Button("open tällmi") { Task { await model.finish() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func extraRow(title: String, text: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: brand.space(.xxs)) {
                Text(title)
                Text(text).brandForeground(.quiet).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .padding(.horizontal, brand.space(.l))
        .padding(.vertical, brand.space(.m))
    }

    // MARK: Parts

    // tälli rising from the window's bottom edge: only its top part (`talli.peek`) is in the window.
    private func peeking(_ view: TalliView, size: Double) -> some View {
        view
            .frame(width: size, height: size)
            .frame(width: size, height: size * talli.peek, alignment: .top)
            .clipped()
            .accessibilityHidden(true)
    }

    // The buttons along the bottom, clear of tälli peeking in the corner, reaching out to the window's edge.
    private func footer(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: brand.space(.s)) { content() }
            .controlSize(.large)
            .padding(.leading, brand.space(.xxxl))
            .padding(.trailing, brand.space(.xl).map { -$0 })
            .frame(height: 72)
    }

    private func progressMarks(_ progress: OnboardingProgress) -> some View {
        HStack(spacing: brand.space(.xs)) {
            ForEach(0..<progress.count, id: \.self) { index in
                Capsule()
                    .frame(width: 18, height: 4)
                    .brandForeground(index < progress.index ? .quiet : index == progress.index ? .blue : .mist)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, brand.space(.l))
        .padding(.trailing, brand.space(.l))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("step \(progress.index + 1) of \(progress.count)")
    }

    // The word users see for a role; roles have no UI word of their own (brand.md §10), so others show none.
    static func roleWord(_ role: ModelRole) -> String? {
        switch role {
        case .transcription: "speech"
        case .embed: "meaning"
        default: nil
        }
    }

    static func purpose(_ role: ModelRole) -> String? {
        switch role {
        case .transcription: "turns your voice into text, german and english mixed."
        case .embed: "finds thoughts by what they mean, not only by their words."
        default: nil
        }
    }

    static func keyName(_ key: String) -> String {
        switch key {
        case "⌃": "control"
        case "⌥": "option"
        case "⇧": "shift"
        case "⌘": "command"
        default: key.lowercased()
        }
    }
}
