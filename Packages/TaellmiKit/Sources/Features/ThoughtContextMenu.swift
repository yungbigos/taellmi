import AppKit
import Domain
import SwiftUI

/// The same actions for the right-click menu inside a thought's text.
enum ThoughtActions {
    static func menuItems(model: ExploreViewModel, entry: Entry, undoManager: UndoManager?) -> [EditorMenuItem] {
        var items: [EditorMenuItem] = []
        if model.view != .flow {
            items.append(EditorMenuItem(title: "show in flow") { Task { await model.reveal(entry.id) } })
        }
        let folders = model.stackIndex.folders.map { summary in
            EditorMenuItem(title: summary.folder.name) { Task { await model.file(entry.id, in: summary.folder.id) } }
        }
        let loose = EditorMenuItem(title: "no folder") { Task { await model.file(entry.id, in: nil) } }
        items.append(EditorMenuItem(title: "move to folder", children: folders + [loose]))
        items.append(
            EditorMenuItem(title: "delete thought", isDestructive: true) {
                Task {
                    await model.trash(entry.id)
                    undoManager?.registerUndo(withTarget: model) { model in Task { await model.undoTrash() } }
                    undoManager?.setActionName("delete thought")
                }
            })
        return items
    }
}

/// The right-click menu of a thought, the same in flow and stack: copy, show it in the other view, file it,
/// delete it (undo brings it back).
struct ThoughtContextMenu: View {
    @Bindable var model: ExploreViewModel
    let entry: Entry
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        Button("copy text") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.text, forType: .string)
        }
        if model.view != .flow {
            Button("show in flow") { Task { await model.reveal(entry.id) } }
        }
        Menu("move to folder") {
            ForEach(model.stackIndex.folders) { summary in
                Button(summary.folder.name) { Task { await model.file(entry.id, in: summary.folder.id) } }
            }
            if !model.stackIndex.folders.isEmpty { Divider() }
            Button("no folder") { Task { await model.file(entry.id, in: nil) } }
        }
        Divider()
        Button("delete thought", role: .destructive) {
            Task {
                await model.trash(entry.id)
                undoManager?.registerUndo(withTarget: model) { model in Task { await model.undoTrash() } }
                undoManager?.setActionName("delete thought")
            }
        }
    }
}
