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
                    TextField("Name hinzufügen, z. B. Marleen", text: $model.newTerm)
                        .onSubmit { Task { await model.addNewTerm() } }
                    Button("Hinzufügen") { Task { await model.addNewTerm() } }
                        .disabled(model.newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if model.terms.isEmpty {
                    Text("Noch keine Namen.").foregroundStyle(.secondary)
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
                        .accessibilityLabel("\(term) entfernen")
                    }
                }
            } header: {
                Text("Vokabular")
            } footer: {
                Text(
                    "Wenn ein neuer Eintrag ähnlich klingt, übernimmt tällmi deine Schreibweise. Jede Korrektur wird im Eintrag vermerkt."
                )
            }
            Section {
                Toggle(
                    "Namen aus meinen Kontakten verwenden",
                    isOn: Binding(
                        get: { model.usesContacts },
                        set: { on in Task { await model.setUsesContacts(on) } }))
            } footer: {
                Text("Die Kontakte werden nur auf diesem Mac gelesen und nirgends gespeichert.")
            }
            if let message = model.message {
                Text(message).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 420)
        .task { await model.load() }
    }
}
