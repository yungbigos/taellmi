import AppKit
import Domain
import Foundation
import SwiftUI
import Testing

@testable import Features

/// The thought editor's wiring: keys and actions reach the formatting edits, and the text comes back out.
@MainActor
@Suite("Typing and formatting in the thought editor")
struct ThoughtEditorTests {
    /// Holds the text the editor's binding writes to.
    private final class Box {
        var text = ""
        var cancelled = 0
    }

    private func makeEditor(_ text: String, selection: NSRange) throws -> (
        HighlightingTextEditor.Coordinator, ThoughtTextView, Box
    ) {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/Config/Resources/Seeds/brand.json").standardizedFileURL
        let brand = try BrandTokens(json: try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)))
        let box = Box()
        box.text = text
        let coordinator = HighlightingTextEditor.Coordinator(
            text: Binding(get: { box.text }, set: { box.text = $0 }))
        coordinator.brand = brand
        coordinator.onCancel = { box.cancelled += 1 }
        let storage = NSTextStorage(string: text)
        let layout = FormattingLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        layout.addTextContainer(container)
        let textView = ThoughtTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200), textContainer: container)
        textView.allowsUndo = true
        textView.delegate = coordinator
        coordinator.attach(textView)
        textView.setSelectedRange(selection)
        return (coordinator, textView, box)
    }

    @Test("Return in a list item starts the next one, and the thought saves it")
    func returnInList() throws {
        let (coordinator, textView, box) = try makeEditor("1. Milch", selection: NSRange(location: 8, length: 0))
        #expect(coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(box.text == "1. Milch\n2. ")
        #expect(textView.selectedRange() == NSRange(location: 12, length: 0))
    }

    @Test("Return outside a list is left to the text view")
    func plainReturn() throws {
        let (coordinator, textView, _) = try makeEditor("normal", selection: NSRange(location: 6, length: 0))
        #expect(!coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
    }

    @Test("Tab and Backspace in lists go to the formatting edits")
    func tabAndBackspace() throws {
        let (coordinator, textView, box) = try makeEditor("- a\n- b", selection: NSRange(location: 7, length: 0))
        #expect(coordinator.textView(textView, doCommandBy: #selector(NSResponder.insertTab(_:))))
        #expect(box.text == "- a\n\t- b")
        textView.setSelectedRange(NSRange(location: 7, length: 0))
        #expect(coordinator.textView(textView, doCommandBy: #selector(NSResponder.deleteBackward(_:))))
        #expect(box.text == "- a\nb")
    }

    @Test("removing an item by typing renumbers the ones below")
    func renumbersWhileTyping() throws {
        let (_, textView, box) = try makeEditor("1. a\n2. b\n3. c", selection: NSRange(location: 0, length: 0))
        textView.insertText("", replacementRange: NSRange(location: 4, length: 5))
        #expect(box.text == "1. a\n2. c")
    }

    @Test("typing never renumbers a list you didn't touch, like a date after a blank line")
    func typingLeavesOtherListsAlone() throws {
        let (_, textView, box) = try makeEditor(
            "1. Mai ist frei.\n\n3. Oktober auch.", selection: NSRange(location: 3, length: 0))
        textView.insertText("x", replacementRange: NSRange(location: 3, length: 0))
        #expect(box.text == "1. xMai ist frei.\n\n3. Oktober auch.")
    }

    @Test("a format from the bar or ⌘K wraps the selection and is saved")
    func appliesFormat() throws {
        let (coordinator, _, box) = try makeEditor("ein wichtiger Tag", selection: NSRange(location: 4, length: 9))
        coordinator.applyFormatting(.toggle(.bold))
        #expect(box.text == "ein **wichtiger** Tag")
        coordinator.applyFormatting(.toggle(.bold))
        #expect(box.text == "ein wichtiger Tag")
    }

    @Test("esc closes the composer")
    func escape() throws {
        let (coordinator, textView, box) = try makeEditor("", selection: NSRange(location: 0, length: 0))
        #expect(coordinator.textView(textView, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(box.cancelled == 1)
    }
}
