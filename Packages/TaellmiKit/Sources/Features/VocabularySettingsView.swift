import SwiftUI

/// Settings: the names tällmi should always spell your way.
public struct VocabularySettingsView: View {
    @Bindable var model: VocabularyViewModel

    public init(model: VocabularyViewModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section {
                HStack {
                    TextField("add a name, e.g. Marleen", text: $model.newTerm)
                        .onSubmit { Task { await model.addNewTerm() } }
                    Button("add") { Task { await model.addNewTerm() } }
                        .disabled(model.newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if model.terms.isEmpty {
                    Text("no names yet.").brandForeground(.quiet)
                }
                ForEach(model.terms, id: \.self) { term in
                    HStack {
                        Text(term)
                        Spacer()
                        Button {
                            Task { await model.remove(term) }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("remove \(term)")
                    }
                }
            } header: {
                Text("spellings")
            } footer: {
                Text(
                    "when a new thought sounds like one of these names, tällmi uses your spelling. each correction is noted on the thought."
                )
            }
            Section {
                Toggle(
                    "use names from my contacts",
                    isOn: Binding(
                        get: { model.usesContacts },
                        set: { on in Task { await model.setUsesContacts(on) } }))
            } footer: {
                Text("contacts are read on this mac only and never stored.")
            }
            if let message = model.message {
                Text(message).brandStatus(.problem)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(width: 460, height: 420)
        .task { await model.load() }
    }
}
