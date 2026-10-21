import Domain
import Testing

/// Texts in these tests mark the selection with « » and an empty selection (the cursor) with |.
private func parse(_ marked: String) -> (text: String, selection: Range<Int>) {
    var text = ""
    var start: Int?
    var end: Int?
    for character in marked {
        switch character {
        case "«": start = text.utf16.count
        case "»": end = text.utf16.count
        case "|":
            start = text.utf16.count
            end = start
        default: text.append(character)
        }
    }
    let lower = start ?? 0
    return (text, lower..<(end ?? lower))
}

private func mark(_ text: String, _ selection: Range<Int>) -> String {
    var units = Array(text.utf16)
    if selection.isEmpty {
        units.insert(contentsOf: "|".utf16, at: selection.lowerBound)
    } else {
        units.insert(contentsOf: "»".utf16, at: selection.upperBound)
        units.insert(contentsOf: "«".utf16, at: selection.lowerBound)
    }
    return String(decoding: units, as: UTF16.self)
}

/// Runs a formatting action on a marked text and gives the marked result; nil when the action does nothing.
private func run(_ marked: String, _ action: (String, Range<Int>) -> TextEdit?) -> String? {
    let (text, selection) = parse(marked)
    guard let edit = action(text, selection) else { return nil }
    return mark(edit.applied(to: text), edit.selection)
}

@Suite("Bold, italic, underline and strike-through from the bar and shortcuts")
struct InlineFormattingEditTests {
    private func toggle(_ format: Format, _ marked: String) -> String? {
        run(marked) { FormattingEdits.toggle(format, in: $0, selection: $1) }
    }

    @Test(
        "a selection is wrapped in the format's markup and stays selected",
        arguments: [
            (Format.bold, "ein «wichtiger» Tag", "ein **«wichtiger»** Tag"),
            (.italic, "ein «leiser» Tag", "ein *«leiser»* Tag"),
            (.strikethrough, "ein «falscher» Tag", "ein ~~«falscher»~~ Tag"),
            (.underline, "an «Oma» denken", "an <u>«Oma»</u> denken"),
        ])
    func wraps(format: Format, before: String, after: String) {
        #expect(toggle(format, before) == after)
    }

    @Test(
        "the same format again takes the markup away, whichever way it was written",
        arguments: [
            (Format.bold, "ein **«wichtiger»** Tag", "ein «wichtiger» Tag"),
            (.bold, "ein __«wichtiger»__ Tag", "ein «wichtiger» Tag"),
            (.italic, "ein _«leiser»_ Tag", "ein «leiser» Tag"),
            (.underline, "an ++«Oma»++ denken", "an «Oma» denken"),
            (.underline, "an <u>«Oma»</u> denken", "an «Oma» denken"),
        ])
    func unwraps(format: Format, before: String, after: String) {
        #expect(toggle(format, before) == after)
    }

    @Test("spaces at the ends of a selection stay outside the markup")
    func trimsSpaces() {
        #expect(toggle(.bold, "ein« wichtiger »Tag") == "ein **«wichtiger»** Tag")
    }

    @Test("with only a cursor, the word it is in gets the format, or loses it")
    func wordAtCursor() {
        #expect(toggle(.bold, "ein wich|tiger Tag") == "ein **wich|tiger** Tag")
        #expect(toggle(.bold, "ein wichtiger| Tag") == "ein **wichtiger|** Tag")
        #expect(toggle(.bold, "ein |wichtiger Tag") == "ein **|wichtiger** Tag")
        #expect(toggle(.bold, "ein **wich|tiger** Tag") == "ein wich|tiger Tag")
    }

    @Test("with the cursor between words, empty markup is put in to type into")
    func emptyMarkup() {
        #expect(toggle(.italic, "ein | Tag") == "ein *|* Tag")
    }

    @Test("bold that was already inside the selection is merged into one")
    func merges() {
        #expect(toggle(.bold, "«ein **sehr** guter» Tag") == "**«ein sehr guter»** Tag")
    }

    @Test("a selection that starts or ends at the same format merges it, whichever format")
    func mergesAtTheEdges() {
        #expect(toggle(.bold, "«**a** b»") == "**«a b»**")
        #expect(toggle(.italic, "«*a* b»") == "*«a b»*")
        #expect(toggle(.strikethrough, "«a ~~b~~»") == "~~«a b»~~")
        #expect(toggle(.underline, "> «<u>a</u> b»") == "> <u>«a b»</u>")
    }

    @Test("formats add up: italic on bold words")
    func addsUp() {
        #expect(toggle(.italic, "**«laut»**") == "***«laut»***")
    }

    @Test("over several lines, each line's words are wrapped, list markers stay in front")
    func severalLines() {
        #expect(toggle(.bold, "«eins\nzwei»") == "**«eins**\n**zwei»**")
        #expect(toggle(.bold, "- «Milch\n- Brot»") == "- **«Milch**\n- **Brot»**")
    }
}

@Suite("Bullet and numbered lists from the bar and shortcuts")
struct ListFormattingEditTests {
    private func toggle(_ format: Format, _ marked: String) -> String? {
        run(marked) { FormattingEdits.toggle(format, in: $0, selection: $1) }
    }

    @Test("a line becomes a list item and back")
    func onAndOff() {
        #expect(toggle(.bulletList, "Mil|ch") == "- Mil|ch")
        #expect(toggle(.bulletList, "- Mil|ch") == "Mil|ch")
        #expect(toggle(.numberedList, "Steu|er") == "1. Steu|er")
    }

    @Test("every line the selection touches becomes an item, numbered in order")
    func severalLines() {
        #expect(toggle(.numberedList, "«Milch\nBrot»") == "1. «Milch\n2. Brot»")
        #expect(toggle(.bulletList, "«Milch\n\nBrot»") == "- «Milch\n\n- Brot»")
    }

    @Test("another kind of line changes kind: bullets to numbers, a heading to a bullet")
    func changesKind() {
        #expect(toggle(.numberedList, "- Mil|ch\n- Brot") == "1. Mil|ch\n- Brot")
        #expect(toggle(.bulletList, "# Tit|el") == "- Tit|el")
    }

    @Test("a new numbered item under a numbered list continues its numbers")
    func continues() {
        #expect(toggle(.numberedList, "1. Milch\nBro|t") == "1. Milch\n2. Bro|t")
    }
}

@Suite("Typing in lists: Return, Backspace, Tab")
struct ListTypingEditTests {
    private func newline(_ marked: String) -> String? {
        run(marked) { FormattingEdits.newline(in: $0, selection: $1) }
    }

    private func deleteBackward(_ marked: String) -> String? {
        run(marked) { FormattingEdits.deleteBackward(in: $0, selection: $1) }
    }

    @Test(
        "Return in an item starts the next one",
        arguments: [
            ("- Milch|", "- Milch\n- |"),
            ("1. Milch|", "1. Milch\n2. |"),
            ("- [x] Brot|", "- [x] Brot\n- [ ] |"),
            ("- Mi|lch", "- Mi\n- |lch"),
            ("\t- tief|", "\t- tief\n\t- |"),
        ])
    func nextItem(before: String, after: String) {
        #expect(newline(before) == after)
    }

    @Test("the numbers after a new item move up by one")
    func renumbersBelow() {
        #expect(newline("1. a|\n2. b") == "1. a\n2. |\n3. b")
    }

    @Test("Return on an empty item ends the list; on an empty sub-item it moves up a level")
    func endsList() {
        #expect(newline("- Milch\n- |") == "- Milch\n|")
        #expect(newline("- a\n\t- |") == "- a\n- |")
    }

    @Test("outside a list, Return is just a line break", arguments: ["normal|", "# Titel|", "> zitat|"])
    func plainReturn(text: String) {
        #expect(newline(text) == nil)
    }

    @Test(
        "Backspace at the start of a formatted line removes its marker, the words stay",
        arguments: [
            ("- |Milch", "|Milch"),
            ("1. |Steuer", "|Steuer"),
            ("- [ ] |Brot", "|Brot"),
            ("# |Titel", "|Titel"),
            ("> |zitat", "|zitat"),
        ])
    func removesMarker(before: String, after: String) {
        #expect(deleteBackward(before) == after)
    }

    @Test("Backspace anywhere else is ordinary", arguments: ["- Mi|lch", "normal|", "- «Milch»"])
    func ordinaryBackspace(text: String) {
        #expect(deleteBackward(text) == nil)
    }

    @Test("Tab moves an item one level down, ⇧Tab back up; numbers follow")
    func levels() {
        #expect(run("- a\n- b|") { FormattingEdits.indent(in: $0, selection: $1) } == "- a\n\t- b|")
        #expect(run("- a\n\t- b|") { FormattingEdits.outdent(in: $0, selection: $1) } == "- a\n- b|")
        #expect(
            run("1. a\n2. b|\n3. c") { FormattingEdits.indent(in: $0, selection: $1) } == "1. a\n\t1. b|\n2. c")
    }

    @Test("Tab outside a list is left to the editor")
    func tabOutsideLists() {
        #expect(run("normal|") { FormattingEdits.indent(in: $0, selection: $1) } == nil)
        #expect(run("normal|") { FormattingEdits.outdent(in: $0, selection: $1) } == nil)
    }
}

@Suite("Numbers renumber themselves; checkboxes tick")
struct RenumberingAndCheckboxTests {
    @Test("numbers in a list count up from one, on every level")
    func renumbers() {
        let edit = FormattingEdits.renumbered("1. a\n1. b\n5. c")
        #expect(edit?.applied(to: "1. a\n1. b\n5. c") == "1. a\n2. b\n3. c")
        let nested = "1. a\n\t1. x\n\t5. y\n7. b"
        #expect(FormattingEdits.renumbered(nested)?.applied(to: nested) == "1. a\n\t1. x\n\t2. y\n2. b")
    }

    @Test("only the list that was edited is renumbered; a list after a blank line or a sentence is left as it is")
    func onlyTheEditedList() {
        #expect(FormattingEdits.renumbered("1. Mai ist frei.\n\n3. Oktober auch.", around: 0..<3) == nil)
        let text = "1. a\n1. b\nText\n1. x\n5. y"
        #expect(FormattingEdits.renumbered(text, around: 0..<3)?.applied(to: text) == "1. a\n2. b\nText\n1. x\n5. y")
        #expect(FormattingEdits.renumbered(text, around: 12..<14) == nil)
    }

    @Test("numbers that are already right are left alone")
    func alreadyRight() {
        #expect(FormattingEdits.renumbered("1. a\n2. b\n\nText") == nil)
    }

    @Test("clicking a box ticks it, clicking again unticks it")
    func checkbox() {
        let text = "- [ ] Brot\n- [x] Milch"
        #expect(FormattingEdits.toggleCheckbox(in: text, lineAt: 3)?.applied(to: text) == "- [x] Brot\n- [x] Milch")
        #expect(FormattingEdits.toggleCheckbox(in: text, lineAt: 14)?.applied(to: text) == "- [ ] Brot\n- [ ] Milch")
        #expect(FormattingEdits.toggleCheckbox(in: "Brot", lineAt: 1) == nil)
    }
}

@Suite("Which formats are on, for the bar")
struct ActiveFormatsTests {
    private func active(_ marked: String) -> Set<Format> {
        let (text, selection) = parse(marked)
        return FormattingEdits.activeFormats(in: text, selection: selection)
    }

    @Test("a format is on when the whole selection is inside it")
    func inline() {
        #expect(active("ein **wich|tiger** Tag") == [.bold])
        #expect(active("**«a»** b") == [.bold])
        #expect(active("«**a** b»").isEmpty)
        #expect(active("***«laut»***") == [.bold, .italic])
    }

    @Test("a list is on when every line the selection touches is that kind of item")
    func lists() {
        #expect(active("- «a\n- b»") == [.bulletList])
        #expect(active("1. «a\nb»").isEmpty)
    }
}
