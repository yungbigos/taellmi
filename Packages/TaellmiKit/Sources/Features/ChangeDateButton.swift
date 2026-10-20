import SwiftUI

/// Shows its label; clicking it opens a calendar to set when an imported thought was written. Saved only
/// with "save", so the thought doesn't jump around while you pick.
struct ChangeDateButton<Label: View>: View {
    let date: Date
    let save: (Date) -> Void
    @ViewBuilder let label: () -> Label
    @State private var isOpen = false
    @State private var picked = Date()

    var body: some View {
        Button {
            picked = date
            isOpen = true
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .help("change date")
        .popover(isPresented: $isOpen, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 12) {
                Text("when did you write this?").font(.headline)
                DatePicker("day", selection: $picked, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                DatePicker("time", selection: $picked, in: ...Date(), displayedComponents: .hourAndMinute)
                HStack {
                    Spacer()
                    Button("cancel") { isOpen = false }
                        .keyboardShortcut(.cancelAction)
                    Button("save") {
                        isOpen = false
                        save(picked)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
            .frame(width: 280)
        }
    }
}
