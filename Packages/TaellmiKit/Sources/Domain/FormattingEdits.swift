import Foundation

/// A format you can switch on and off from the floating bar, a shortcut or ⌘K (ADR 0014).
public enum Format: String, Sendable, CaseIterable, Hashable {
    case bold
    case italic
    case underline
    case strikethrough
    case bulletList
    case numberedList
}

/// One change to a Text: replace `range` with `replacement`, then select `selection` (in the changed Text).
public struct TextEdit: Sendable, Equatable {
    public var range: Range<Int>
    public var replacement: String
    public var selection: Range<Int>

    public init(range: Range<Int>, replacement: String, selection: Range<Int>) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    public func applied(to text: String) -> String {
        var units = Array(text.utf16)
        units.replaceSubrange(range, with: Array(replacement.utf16))
        return String(decoding: units, as: UTF16.self)
    }
}

/// What the formatting actions do to a Text's Markdown (ADR 0014). They are pure: the editor only applies
/// the edit, so every action is one undoable change and is tested without a text view.
public enum FormattingEdits {
    // MARK: Switching a format

    /// Bold, italic, underline or strike-through around the selection (or the word at the cursor), or a list
    /// on every line the selection touches. If the format is already on there, it is taken off.
    public static func toggle(_ format: Format, in text: String, selection: Range<Int>) -> TextEdit? {
        let document = Document(text)
        switch format {
        case .bulletList: return document.toggleList(numbered: false, selection: selection)
        case .numberedList: return document.toggleList(numbered: true, selection: selection)
        default: return document.toggleInline(Markup(format), selection: selection)
        }
    }

    /// Which formats are on for the selection, for the floating bar.
    public static func activeFormats(in text: String, selection: Range<Int>) -> Set<Format> {
        let document = Document(text)
        var active: Set<Format> = []
        for format in [Format.bold, .italic, .underline, .strikethrough]
        where document.span(Markup(format).style, containing: selection) != nil {
            active.insert(format)
        }
        let lines = document.lines(touching: selection).filter { !document.isBlank($0) }
        if !lines.isEmpty {
            if lines.allSatisfy({ document.isItem($0, numbered: false) }) { active.insert(.bulletList) }
            if lines.allSatisfy({ document.isItem($0, numbered: true) }) { active.insert(.numberedList) }
        }
        return active
    }

    // MARK: Typing in lists

    /// Return in a list item: the next item, with the next number. On an empty item the list ends (a sub-item
    /// moves up a level instead). Nil outside lists, where Return is an ordinary line break.
    public static func newline(in text: String, selection: Range<Int>) -> TextEdit? {
        let document = Document(text)
        guard selection.isEmpty, let line = document.formatting.line(at: selection.lowerBound),
            case .listItem(let style, let level) = line.kind, selection.lowerBound >= line.content.lowerBound
        else { return nil }
        var ops = Ops()
        if document.isEmptyContent(line) {
            if level > 0, let indent = document.outdentRange(line) {
                ops.replace(indent, with: "")
            } else {
                ops.replace(line.marker, with: "")
            }
            return document.finish(ops, selection: selection, cursorBias: .before)
        }
        let indent = document.string(line.range.lowerBound..<document.indentEnd(line))
        let bullet = document.bulletCharacter(line)
        let next: String
        switch style {
        case .bullet: next = "\(bullet) "
        case .numbered(let number): next = "\(number + 1)\(document.numberDelimiter(line)) "
        case .checklist: next = "\(bullet) [ ] "
        }
        ops.replace(selection, with: "\n" + indent + next)
        return document.finish(ops, selection: selection, cursorBias: .after)
    }

    /// Backspace right after a line's marker (a bullet, number, box, `#` or `>`) removes the marker; the words
    /// stay. Nil anywhere else, where Backspace is ordinary.
    public static func deleteBackward(in text: String, selection: Range<Int>) -> TextEdit? {
        let document = Document(text)
        guard selection.isEmpty, let line = document.formatting.line(at: selection.lowerBound),
            !line.marker.isEmpty, selection.lowerBound == line.content.lowerBound
        else { return nil }
        switch line.kind {
        case .listItem, .heading, .quote: break
        case .plain, .code: return nil
        }
        var ops = Ops()
        ops.replace(line.marker, with: "")
        return document.finish(ops, selection: selection, cursorBias: .before)
    }

    /// Tab (and ⌘]) on list items: one level deeper. Nil when the selection touches no list item.
    public static func indent(in text: String, selection: Range<Int>) -> TextEdit? {
        let document = Document(text)
        var ops = Ops()
        for line in document.lines(touching: selection) where document.isAnyItem(line) {
            ops.replace(line.range.lowerBound..<line.range.lowerBound, with: "\t")
        }
        guard !ops.isEmpty else { return nil }
        return document.finish(ops, selection: selection, cursorBias: .after)
    }

    /// ⇧Tab (and ⌘[) on list items: one level up. Nil when nothing can move up.
    public static func outdent(in text: String, selection: Range<Int>) -> TextEdit? {
        let document = Document(text)
        var ops = Ops()
        for line in document.lines(touching: selection) where document.isAnyItem(line) {
            if let indent = document.outdentRange(line) { ops.replace(indent, with: "") }
        }
        guard !ops.isEmpty else { return nil }
        return document.finish(ops, selection: selection, cursorBias: .before)
    }

    // MARK: Numbers and boxes

    /// The numbered lists that `range` touches (all of them when nil), counting up on each level, or nil if
    /// the numbers are already right. A list here is a run of items without a blank line or a sentence
    /// between them, so a list you didn't touch is never rewritten. The selection is carried through.
    public static func renumbered(_ text: String, around range: Range<Int>? = nil, selection: Range<Int> = 0..<0)
        -> TextEdit?
    {
        let document = Document(text)
        let ops = document.renumberOps(around: range)
        guard !ops.isEmpty else { return nil }
        return document.edit(ops, selection: selection, cursorBias: .before)
    }

    /// Ticks or unticks the box of the checklist item on the line at `offset`. Nil if that line has no box.
    public static func toggleCheckbox(in text: String, lineAt offset: Int, selection: Range<Int> = 0..<0)
        -> TextEdit?
    {
        let document = Document(text)
        guard let line = document.formatting.line(at: offset),
            case .listItem(.checklist(let checked), _) = line.kind,
            let open = (line.marker.lowerBound..<line.marker.upperBound).first(where: {
                document.units[$0] == 0x5B
            })
        else { return nil }
        var ops = Ops()
        ops.replace((open + 1)..<(open + 2), with: checked ? " " : "x")
        return document.edit(ops, selection: selection, cursorBias: .before)
    }
}

// MARK: - Markup written by the app

/// The markup the app writes for an inline format (ADR 0014: `<u>` for underline, which Obsidian shows).
private struct Markup {
    let style: TextFormatting.Span.Style
    let open: String
    let close: String

    init(_ format: Format) {
        switch format {
        case .italic: (style, open, close) = (.italic, "*", "*")
        case .underline: (style, open, close) = (.underline, "<u>", "</u>")
        case .strikethrough: (style, open, close) = (.strikethrough, "~~", "~~")
        default: (style, open, close) = (.bold, "**", "**")
        }
    }
}

// MARK: - Edits as a set of replacements

/// Several non-overlapping replacements in one Text, with positions carried through them.
private struct Ops {
    enum Bias { case before, after }

    private(set) var items: [(range: Range<Int>, units: [UInt16])] = []

    var isEmpty: Bool { items.isEmpty }

    mutating func replace(_ range: Range<Int>, with text: String) {
        items.append((range, Array(text.utf16)))
    }

    /// In text order. At the same position an insertion comes before a replacement that starts there.
    private var sorted: [(range: Range<Int>, units: [UInt16])] {
        items.enumerated().sorted {
            let left = ($0.element.range.lowerBound, $0.element.range.isEmpty ? 0 : 1, $0.offset)
            let right = ($1.element.range.lowerBound, $1.element.range.isEmpty ? 0 : 1, $1.offset)
            return left < right
        }.map(\.element)
    }

    /// The part of the changed Text the replacements wrote.
    var changedRange: Range<Int>? {
        guard let lower = items.map(\.range.lowerBound).min(), let upper = items.map(\.range.upperBound).max() else {
            return nil
        }
        let start = map(lower, bias: .before)
        return start..<max(start, map(upper, bias: .after))
    }

    func apply(to units: [UInt16]) -> [UInt16] {
        var result: [UInt16] = []
        var position = 0
        for item in sorted {
            result += units[position..<item.range.lowerBound]
            result += item.units
            position = item.range.upperBound
        }
        result += units[position...]
        return result
    }

    /// Where a position ends up. At an insertion point, `bias` says whether it lands before or after it.
    func map(_ offset: Int, bias: Bias) -> Int {
        var delta = 0
        for item in sorted {
            let range = item.range
            if range.lowerBound > offset { break }
            if range.isEmpty {
                if range.lowerBound < offset || bias == .after { delta += item.units.count }
            } else if range.upperBound <= offset {
                delta += item.units.count - range.count
            } else {
                // Inside replaced text: move to its start, or its end.
                return range.lowerBound + delta + (bias == .after ? item.units.count : 0)
            }
        }
        return offset + delta
    }
}

// MARK: - A Text being edited

private struct Document {
    let text: String
    let units: [UInt16]
    let formatting: TextFormatting

    init(_ text: String) {
        self.text = text
        units = Array(text.utf16)
        formatting = TextFormatting(text)
    }

    func string(_ range: Range<Int>) -> String { String(decoding: units[range], as: UTF16.self) }

    // MARK: Inline formats

    func span(_ style: TextFormatting.Span.Style, containing selection: Range<Int>) -> TextFormatting.Span? {
        formatting.spans.last { span in
            span.style == style
                && ((span.content.lowerBound <= selection.lowerBound && selection.upperBound <= span.content.upperBound)
                    || span.full == selection)
        }
    }

    func toggleInline(_ markup: Markup, selection: Range<Int>) -> TextEdit? {
        var ops = Ops()
        if let span = span(markup.style, containing: selection) {
            ops.replace(span.opening, with: "")
            ops.replace(span.closing, with: "")
            let lower = ops.map(selection.lowerBound, bias: .before)
            let upper = ops.map(selection.upperBound, bias: .before)
            return edit(ops, selection: lower..<max(lower, upper))
        }
        if selection.isEmpty {
            let word = word(at: selection.lowerBound)
            guard !word.isEmpty else {
                // Between words: empty markup to type into.
                ops.replace(selection, with: markup.open + markup.close)
                let cursor = selection.lowerBound + markup.open.utf16.count
                return edit(ops, selection: cursor..<cursor)
            }
            ops.replace(word.lowerBound..<word.lowerBound, with: markup.open)
            ops.replace(word.upperBound..<word.upperBound, with: markup.close)
            let cursor = ops.map(selection.lowerBound, bias: selection.lowerBound == word.upperBound ? .before : .after)
            return edit(ops, selection: cursor..<cursor)
        }
        var segments: [Range<Int>] = []
        for line in lines(touching: selection) {
            let lower = max(selection.lowerBound, line.content.lowerBound)
            let upper = min(selection.upperBound, line.content.upperBound)
            if let segment = trimmed(lower..<max(lower, upper)) { segments.append(segment) }
        }
        guard let first = segments.first, let last = segments.last else { return nil }
        for segment in segments {
            for span in formatting.spans
            where span.style == markup.style && segment.contains(span.full.lowerBound)
                && span.full.upperBound <= segment.upperBound
            {
                ops.replace(span.opening, with: "")
                ops.replace(span.closing, with: "")
            }
            ops.replace(segment.lowerBound..<segment.lowerBound, with: markup.open)
            ops.replace(segment.upperBound..<segment.upperBound, with: markup.close)
        }
        let lower = ops.map(first.lowerBound, bias: .after)
        let upper = ops.map(last.upperBound, bias: .before)
        return edit(ops, selection: lower..<max(lower, upper))
    }

    /// The word around a position: letters, digits and marks; empty between words.
    func word(at offset: Int) -> Range<Int> {
        let bounds = formatting.line(at: offset)?.content ?? 0..<units.count
        var lower = offset
        var upper = offset
        while lower > bounds.lowerBound, isWordUnit(units[lower - 1]) { lower -= 1 }
        while upper < bounds.upperBound, isWordUnit(units[upper]) { upper += 1 }
        return lower..<upper
    }

    private func isWordUnit(_ unit: UInt16) -> Bool {
        if UTF16.isLeadSurrogate(unit) || UTF16.isTrailSurrogate(unit) { return true }
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.alphanumerics.contains(scalar) || unit == 0x2D
            || unit == 0x27
    }

    private func trimmed(_ range: Range<Int>) -> Range<Int>? {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, isSpace(units[lower]) { lower += 1 }
        while upper > lower, isSpace(units[upper - 1]) { upper -= 1 }
        return lower < upper ? lower..<upper : nil
    }

    private func isSpace(_ unit: UInt16) -> Bool { unit == 0x20 || unit == 0x09 || unit == 0xA0 }

    // MARK: Lines and lists

    /// The lines a selection touches; a selection ending at the very start of a line leaves that line out.
    func lines(touching selection: Range<Int>) -> [TextFormatting.Line] {
        formatting.lines.filter { line in
            if selection.isEmpty {
                return line.range.lowerBound <= selection.lowerBound && selection.lowerBound <= line.range.upperBound
            }
            return line.range.lowerBound < selection.upperBound && selection.lowerBound <= line.range.upperBound
        }
    }

    func isBlank(_ line: TextFormatting.Line) -> Bool {
        line.kind == .plain && units[line.range].allSatisfy(isSpace)
    }

    func isEmptyContent(_ line: TextFormatting.Line) -> Bool { units[line.content].allSatisfy(isSpace) }

    func isItem(_ line: TextFormatting.Line, numbered: Bool) -> Bool {
        switch line.kind {
        case .listItem(.numbered, _): return numbered
        case .listItem(.bullet, _): return !numbered
        default: return false
        }
    }

    func isAnyItem(_ line: TextFormatting.Line) -> Bool {
        if case .listItem = line.kind { return true }
        return false
    }

    func level(_ line: TextFormatting.Line) -> Int? {
        if case .listItem(_, let level) = line.kind { return level }
        return nil
    }

    func indentEnd(_ line: TextFormatting.Line) -> Int {
        var position = line.range.lowerBound
        while position < line.content.lowerBound, units[position] == 0x20 || units[position] == 0x09 { position += 1 }
        return position
    }

    /// One level of leading indentation: a tab, or up to four spaces.
    func outdentRange(_ line: TextFormatting.Line) -> Range<Int>? {
        let start = line.range.lowerBound
        guard start < units.count else { return nil }
        if units[start] == 0x09 { return start..<(start + 1) }
        var end = start
        while end < indentEnd(line), end - start < 4, units[end] == 0x20 { end += 1 }
        return end > start ? start..<end : nil
    }

    func bulletCharacter(_ line: TextFormatting.Line) -> String {
        let position = indentEnd(line)
        if position < units.count, [0x2A, 0x2B].contains(units[position]) {
            return string(position..<(position + 1))
        }
        return "-"
    }

    func numberDelimiter(_ line: TextFormatting.Line) -> String {
        var position = indentEnd(line)
        while position < line.content.lowerBound, (0x30...0x39).contains(units[position]) { position += 1 }
        return position < units.count && units[position] == 0x29 ? ")" : "."
    }

    func toggleList(numbered: Bool, selection: Range<Int>) -> TextEdit? {
        let touched = lines(touching: selection)
        let lines = touched.count > 1 ? touched.filter { !isBlank($0) } : touched
        guard !lines.isEmpty else { return nil }
        var ops = Ops()
        if lines.allSatisfy({ isItem($0, numbered: numbered) }) {
            for line in lines { ops.replace(line.marker, with: "") }
            return finish(ops, selection: selection, cursorBias: .before)
        }
        var number = startingNumber(before: lines[0])
        for line in lines {
            let indent = isAnyItem(line) ? string(line.range.lowerBound..<indentEnd(line)) : ""
            ops.replace(line.marker, with: indent + (numbered ? "\(number). " : "- "))
            number += 1
        }
        return finish(ops, selection: selection, cursorBias: .after)
    }

    /// The number a new item under the line above would get.
    private func startingNumber(before line: TextFormatting.Line) -> Int {
        guard let index = formatting.lines.firstIndex(of: line), index > 0,
            case .listItem(.numbered(let number), let level) = formatting.lines[index - 1].kind,
            level == (self.level(line) ?? 0)
        else { return 1 }
        return number + 1
    }

    /// Numbers that differ from counting up, per list and level. A list keeps its first number (one, unless
    /// it continues a list above a blank line); a sub-list starts at one.
    func renumberOps(around range: Range<Int>?) -> Ops {
        var ops = Ops()
        for block in listBlocks() {
            if let range, let first = block.first, let last = block.last,
                !(range.lowerBound <= last.range.upperBound && first.range.lowerBound <= range.upperBound)
            {
                continue
            }
            var counters: [Int: Int] = [:]
            for line in block {
                guard case .listItem(let style, let level) = line.kind else { continue }
                counters = counters.filter { $0.key <= level }
                guard case .numbered(let number) = style else {
                    counters[level] = nil
                    continue
                }
                let expected = counters[level].map { $0 + 1 } ?? (level == 0 && line == block.first ? number : 1)
                counters[level] = expected
                if number != expected {
                    let start = indentEnd(line)
                    var end = start
                    while end < line.content.lowerBound, (0x30...0x39).contains(units[end]) { end += 1 }
                    ops.replace(start..<end, with: String(expected))
                }
            }
        }
        return ops
    }

    /// Runs of list items with nothing between them.
    private func listBlocks() -> [[TextFormatting.Line]] {
        var blocks: [[TextFormatting.Line]] = []
        var current: [TextFormatting.Line] = []
        for line in formatting.lines {
            if isAnyItem(line) {
                current.append(line)
            } else if !current.isEmpty {
                blocks.append(current)
                current = []
            }
        }
        if !current.isEmpty { blocks.append(current) }
        return blocks
    }

    // MARK: Making the edit

    /// Applies the replacements and then renumbers the lists, as one edit.
    func finish(_ ops: Ops, selection: Range<Int>, cursorBias: Ops.Bias) -> TextEdit {
        let lower = ops.map(selection.lowerBound, bias: cursorBias)
        let upper = selection.isEmpty ? lower : ops.map(selection.upperBound, bias: .before)
        let changed = String(decoding: ops.apply(to: units), as: UTF16.self)
        let moved = lower..<max(lower, upper)
        guard let renumber = FormattingEdits.renumbered(changed, around: ops.changedRange, selection: moved) else {
            return edit(ops, selection: moved)
        }
        return Self.diff(text, renumber.applied(to: changed), selection: renumber.selection)
    }

    func edit(_ ops: Ops, selection: Range<Int>, cursorBias: Ops.Bias) -> TextEdit {
        let lower = ops.map(selection.lowerBound, bias: cursorBias)
        let upper = selection.isEmpty ? lower : ops.map(selection.upperBound, bias: .before)
        return edit(ops, selection: lower..<max(lower, upper))
    }

    /// One edit covering all replacements; `selection` is already in the changed Text.
    func edit(_ ops: Ops, selection: Range<Int>) -> TextEdit {
        Self.diff(text, String(decoding: ops.apply(to: units), as: UTF16.self), selection: selection)
    }

    /// The smallest single replacement that turns `old` into `new`.
    static func diff(_ old: String, _ new: String, selection: Range<Int>) -> TextEdit {
        let a = Array(old.utf16)
        let b = Array(new.utf16)
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix, a[a.count - 1 - suffix] == b[b.count - 1 - suffix] {
            suffix += 1
        }
        return TextEdit(
            range: prefix..<(a.count - suffix),
            replacement: String(decoding: b[prefix..<(b.count - suffix)], as: UTF16.self), selection: selection)
    }
}
