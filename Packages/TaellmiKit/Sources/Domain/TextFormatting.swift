import Foundation

/// The Formatting of a Text, read from its Markdown (ADR 0014). The Text itself is never changed; this only
/// says where the formatted words and their markup are, as UTF-16 offsets, the unit text views use.
///
/// It reads the part of Markdown a journal needs, line by line: lists, headings, quotes and code blocks, and
/// inside a line bold, italic, strike-through, underline, links and images. Anything else stays plain text,
/// so a misreading can only make words look wrong, never change them.
public struct TextFormatting: Sendable, Equatable {
    /// One line of the Text and what kind of line it is.
    public struct Line: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case plain
            case heading(level: Int)
            case listItem(ListStyle, level: Int)
            case quote
            /// A line of a fenced code block, or a fence: shown as its plain text.
            case code
        }

        public var kind: Kind
        /// The whole line, without its line break.
        public var range: Range<Int>
        /// Indentation plus the line's marker (`- `, `1. `, `- [ ] `, `# `, `> `). Empty for plain lines.
        public var marker: Range<Int>
        /// What follows the marker.
        public var content: Range<Int>
        /// A list item's leading tabs or spaces, the start of its marker; empty for other lines.
        public var indentation: Range<Int> = 0..<0
    }

    public enum ListStyle: Sendable, Equatable {
        case bullet
        case numbered(Int)
        case checklist(checked: Bool)
    }

    /// Formatted words within a line, with the markup before and after them.
    public struct Span: Sendable, Equatable {
        public enum Style: Sendable, Equatable {
            case bold
            case italic
            case strikethrough
            case underline
            case link(url: String)
            case image(source: String)
        }

        public var style: Style
        public var opening: Range<Int>
        public var content: Range<Int>
        public var closing: Range<Int>

        public var full: Range<Int> { opening.lowerBound..<closing.upperBound }
    }

    public var lines: [Line]
    /// In order of where they start; nested spans follow the span they sit in.
    public var spans: [Span]

    public init(_ text: String) {
        let units = Array(text.utf16)
        var lines: [Line] = []
        var spans: [Span] = []
        var reader = BlockReader()
        var start = 0
        for index in 0...units.count where index == units.count || units[index] == Self.newline {
            let line = reader.read(units, start..<index)
            lines.append(line)
            if line.kind != .code {
                spans += InlineReader(units: units, range: line.content).spans()
            }
            start = index + 1
        }
        self.lines = lines
        self.spans = spans.sorted { $0.full.lowerBound < $1.full.lowerBound }
    }

    /// The line a position is on (a position right after a line's end belongs to that line).
    public func line(at offset: Int) -> Line? {
        lines.first { $0.range.lowerBound <= offset && offset <= $0.range.upperBound }
    }

    static let newline: UInt16 = 0x0A
}

// MARK: - Hidden markup

/// What the editor hides while you edit (ADR 0014): markup disappears except around the formatted words the
/// cursor is in or next to. Bullets and boxes are drawn in place of their hidden markers.
public struct MarkupVisibility: Sendable, Equatable {
    /// Markup to hide, as ranges in the Text.
    public var hidden: [Range<Int>]
    /// Line starts of bullet items whose `- ` is hidden, so a • is drawn instead.
    public var bullets: [Int]
    /// Line starts of checklist items whose `- [ ] ` is hidden, so a box is drawn instead.
    public var boxes: [Int]
    /// Positions of hidden images, where `image not imported` is drawn.
    public var placeholders: [Int]
}

extension TextFormatting {
    /// - Parameter selection: where the cursor or selection is, or nil when the Text isn't being edited.
    public func visibility(selection: Range<Int>?) -> MarkupVisibility {
        var result = MarkupVisibility(hidden: [], bullets: [], boxes: [], placeholders: [])
        func touches(_ range: Range<Int>) -> Bool {
            guard let selection else { return false }
            return selection.lowerBound <= range.upperBound && range.lowerBound <= selection.upperBound
        }
        for line in lines where !line.marker.isEmpty {
            switch line.kind {
            case .plain, .code:
                continue
            case .listItem(.numbered, _):
                // Numbers show as typed; the level is drawn as an indent instead of the tabs.
                if !line.indentation.isEmpty { result.hidden.append(line.indentation) }
            case .listItem(let style, _):
                guard !touches(line.marker.lowerBound..<line.content.lowerBound) else {
                    if !line.indentation.isEmpty { result.hidden.append(line.indentation) }
                    continue
                }
                result.hidden.append(line.marker)
                if case .checklist = style {
                    result.boxes.append(line.range.lowerBound)
                } else {
                    result.bullets.append(line.range.lowerBound)
                }
            case .heading, .quote:
                if !touches(line.range) { result.hidden.append(line.marker) }
            }
        }
        for span in spans where !touches(span.full) {
            if case .image = span.style {
                result.placeholders.append(span.full.lowerBound)
                result.hidden.append((span.full.lowerBound + 1)..<span.full.upperBound)
            } else {
                result.hidden.append(span.opening)
                result.hidden.append(span.closing)
            }
        }
        return result
    }
}

// MARK: - Lines

/// Reads one line at a time, remembering what it needs across lines: an open code block and the
/// indentation of the list items above, which decides their level.
private struct BlockReader {
    private var inCode = false
    private var listIndents: [Int] = []
    private var previousWasListItem = false

    mutating func read(_ units: [UInt16], _ range: Range<Int>) -> TextFormatting.Line {
        var position = range.lowerBound
        var columns = 0
        while position < range.upperBound, units[position] == space || units[position] == tab {
            columns = units[position] == tab ? (columns / 4 + 1) * 4 : columns + 1
            position += 1
        }
        let rest = position..<range.upperBound

        if starts(units, rest, with: "```") || starts(units, rest, with: "~~~") {
            inCode.toggle()
            return finish(.code, range, marker: range.lowerBound..<range.lowerBound, isListItem: false)
        }
        if inCode { return finish(.code, range, marker: range.lowerBound..<range.lowerBound, isListItem: false) }

        if columns < 4, let (level, end) = heading(units, rest) {
            return finish(.heading(level: level), range, marker: range.lowerBound..<end, isListItem: false)
        }
        if columns < 4, position < range.upperBound, units[position] == greaterThan {
            var end = position + 1
            if end < range.upperBound, units[end] == space { end += 1 }
            return finish(.quote, range, marker: range.lowerBound..<end, isListItem: false)
        }
        if let (style, end) = listMarker(units, rest) {
            let level = level(forIndent: columns)
            var line = finish(.listItem(style, level: level), range, marker: range.lowerBound..<end, isListItem: true)
            line.indentation = range.lowerBound..<position
            return line
        }
        // A blank line between items keeps the list going.
        if rest.isEmpty {
            return TextFormatting.Line(
                kind: .plain, range: range, marker: range.lowerBound..<range.lowerBound, content: range)
        }
        if columns == 0 { listIndents = [] }
        return finish(.plain, range, marker: range.lowerBound..<range.lowerBound, isListItem: false)
    }

    private mutating func finish(
        _ kind: TextFormatting.Line.Kind, _ range: Range<Int>, marker: Range<Int>, isListItem: Bool
    ) -> TextFormatting.Line {
        if !isListItem, kind != .plain { listIndents = [] }
        previousWasListItem = isListItem
        return TextFormatting.Line(
            kind: kind, range: range, marker: marker, content: marker.upperBound..<range.upperBound)
    }

    /// Deeper indentation than the item above makes a sub-item; the same or less returns to that level.
    private mutating func level(forIndent columns: Int) -> Int {
        while let last = listIndents.last, columns < last { listIndents.removeLast() }
        if listIndents.last.map({ columns > $0 }) ?? true { listIndents.append(columns) }
        return listIndents.count - 1
    }

    private func heading(_ units: [UInt16], _ rest: Range<Int>) -> (Int, Int)? {
        var position = rest.lowerBound
        while position < rest.upperBound, units[position] == hash { position += 1 }
        let level = position - rest.lowerBound
        guard (1...6).contains(level) else { return nil }
        if position == rest.upperBound { return (level, position) }
        guard units[position] == space || units[position] == tab else { return nil }
        while position < rest.upperBound, units[position] == space || units[position] == tab { position += 1 }
        return (level, position)
    }

    private func listMarker(_ units: [UInt16], _ rest: Range<Int>) -> (TextFormatting.ListStyle, Int)? {
        guard let first = rest.first.map({ units[$0] }) else { return nil }
        var position = rest.lowerBound
        var style: TextFormatting.ListStyle
        if first == dash || first == star || first == plus {
            position += 1
            style = .bullet
        } else if isDigit(first) {
            var value = 0
            while position < rest.upperBound, isDigit(units[position]), position - rest.lowerBound < 9 {
                value = value * 10 + Int(units[position] - zero)
                position += 1
            }
            guard position < rest.upperBound, units[position] == dot || units[position] == closingParen else {
                return nil
            }
            // "3. Oktober" at the start of a line is a date, not a list: a list starts at one.
            guard value == 1 || previousWasListItem else { return nil }
            position += 1
            style = .numbered(value)
        } else {
            return nil
        }
        guard position < rest.upperBound, units[position] == space || units[position] == tab else { return nil }
        position += 1
        if case .bullet = style, position + 3 <= rest.upperBound, units[position] == openBracket,
            units[position + 2] == closeBracket,
            position + 3 == rest.upperBound || units[position + 3] == space
        {
            let mark = units[position + 1]
            if mark == space || mark == lowerX || mark == upperX {
                style = .checklist(checked: mark != space)
                position = min(position + 4, rest.upperBound)
            }
        }
        return (style, position)
    }

    private func starts(_ units: [UInt16], _ range: Range<Int>, with prefix: String) -> Bool {
        let prefix = Array(prefix.utf16)
        guard range.count >= prefix.count else { return false }
        return Array(units[range.lowerBound..<(range.lowerBound + prefix.count)]) == prefix
    }

    private func isDigit(_ unit: UInt16) -> Bool { unit >= zero && unit <= zero + 9 }

    private let space: UInt16 = 0x20
    private let tab: UInt16 = 0x09
    private let hash: UInt16 = 0x23
    private let greaterThan: UInt16 = 0x3E
    private let dash: UInt16 = 0x2D
    private let star: UInt16 = 0x2A
    private let plus: UInt16 = 0x2B
    private let dot: UInt16 = 0x2E
    private let closingParen: UInt16 = 0x29
    private let openBracket: UInt16 = 0x5B
    private let closeBracket: UInt16 = 0x5D
    private let lowerX: UInt16 = 0x78
    private let upperX: UInt16 = 0x58
    private let zero: UInt16 = 0x30
}

// MARK: - Inside a line

/// Bold, italic, strike-through, underline, links and images within one line, following Markdown's rules for
/// where a marker may open or close: `**` must touch a word, `_` never works inside a word, `5 * 3` stays
/// arithmetic, and code in backticks is left alone.
private struct InlineReader {
    let units: [UInt16]
    let range: Range<Int>

    /// A run of the same marker character that may still open or close a span.
    private struct Delimiter {
        var character: UInt16
        var start: Int
        var count: Int
        let originalCount: Int
        let canOpen: Bool
        let canClose: Bool
    }

    func spans() -> [TextFormatting.Span] {
        var result: [TextFormatting.Span] = []
        var opaque: [Range<Int>] = []
        var tags: [(isClosing: Bool, range: Range<Int>)] = []
        var delimiters: [Delimiter] = []

        var position = range.lowerBound
        while position < range.upperBound {
            let unit = units[position]
            if unit == backslash, position + 1 < range.upperBound, isASCIIPunctuation(units[position + 1]) {
                position += 2
            } else if unit == backtick, let end = codeSpanEnd(from: position) {
                opaque.append(position..<end)
                position = end
            } else if let link = link(at: position) {
                result.append(link)
                opaque.append(link.opening)
                opaque.append(link.closing)
                position = link.opening.upperBound
            } else if unit == lessThan, let (isClosing, end) = underlineTag(at: position) {
                tags.append((isClosing, position..<end))
                position = end
            } else if unit == star || unit == underscore || unit == tilde || unit == plus {
                var end = position
                while end < range.upperBound, units[end] == unit { end += 1 }
                if let delimiter = delimiter(unit, position..<end) { delimiters.append(delimiter) }
                position = end
            } else {
                position += 1
            }
        }
        // Delimiters inside a link's address are not markup.
        delimiters.removeAll { delimiter in opaque.contains { $0.contains(delimiter.start) } }
        result += emphasis(delimiters)
        result += underlines(tags.filter { tag in !opaque.contains { $0.contains(tag.range.lowerBound) } })
        return result
    }

    // MARK: Emphasis, strike-through, ++underline++

    private func delimiter(_ character: UInt16, _ run: Range<Int>) -> Delimiter? {
        // `~` works once or twice, `++` exactly twice; longer runs are plain text.
        if character == tilde, run.count > 2 { return nil }
        if character == plus, run.count != 2 { return nil }
        let before = run.lowerBound > range.lowerBound ? units[run.lowerBound - 1] : nil
        let after = run.upperBound < range.upperBound ? units[run.upperBound] : nil
        let leftFlanking =
            after.map {
                !isSpace($0) && (!isPunctuation($0) || before.map { isSpace($0) || isPunctuation($0) } ?? true)
            }
            ?? false
        let rightFlanking =
            before.map {
                !isSpace($0) && (!isPunctuation($0) || after.map { isSpace($0) || isPunctuation($0) } ?? true)
            }
            ?? false
        var canOpen = leftFlanking
        var canClose = rightFlanking
        if character == underscore {
            canOpen = leftFlanking && (!rightFlanking || before.map(isPunctuation) ?? false)
            canClose = rightFlanking && (!leftFlanking || after.map(isPunctuation) ?? false)
        }
        guard canOpen || canClose else { return nil }
        return Delimiter(
            character: character, start: run.lowerBound, count: run.count, originalCount: run.count,
            canOpen: canOpen, canClose: canClose)
    }

    /// Markdown's "process emphasis", reduced to what is read here: each closer pairs with the nearest
    /// opener of the same character; two on each side make bold, one makes italic.
    private func emphasis(_ delimiters: [Delimiter]) -> [TextFormatting.Span] {
        var spans: [TextFormatting.Span] = []
        var openers: [Delimiter] = []
        for var closer in delimiters {
            while closer.canClose, closer.count > 0,
                let index = openers.lastIndex(where: { matches($0, closer) })
            {
                var opener = openers[index]
                let used: Int
                let style: TextFormatting.Span.Style
                switch closer.character {
                case tilde:
                    used = opener.count
                    style = .strikethrough
                case plus:
                    used = 2
                    style = .underline
                default:
                    used = opener.count >= 2 && closer.count >= 2 ? 2 : 1
                    style = used == 2 ? .bold : .italic
                }
                let opening = (opener.start + opener.count - used)..<(opener.start + opener.count)
                let closing = closer.start..<(closer.start + used)
                spans.append(
                    TextFormatting.Span(
                        style: style, opening: opening, content: opening.upperBound..<closing.lowerBound,
                        closing: closing))
                opener.count -= used
                closer.start += used
                closer.count -= used
                openers.removeSubrange((index + 1)...)
                if opener.count == 0 { openers.remove(at: index) } else { openers[index] = opener }
            }
            if closer.canOpen, closer.count > 0 { openers.append(closer) }
        }
        return spans
    }

    private func matches(_ opener: Delimiter, _ closer: Delimiter) -> Bool {
        guard opener.character == closer.character, opener.canOpen, opener.count > 0 else { return false }
        if closer.character == tilde { return opener.count == closer.count }
        return true
    }

    // MARK: <u>…</u>

    private func underlineTag(at position: Int) -> (Bool, Int)? {
        for (tag, isClosing) in [("<u>", false), ("</u>", true)] {
            let tag = Array(tag.utf16)
            guard position + tag.count <= range.upperBound else { continue }
            let found = units[position..<(position + tag.count)].map(lowercased)
            if found == tag { return (isClosing, position + tag.count) }
        }
        return nil
    }

    private func underlines(_ tags: [(isClosing: Bool, range: Range<Int>)]) -> [TextFormatting.Span] {
        var open: [Range<Int>] = []
        var spans: [TextFormatting.Span] = []
        for tag in tags {
            if !tag.isClosing {
                open.append(tag.range)
            } else if let opening = open.popLast() {
                spans.append(
                    TextFormatting.Span(
                        style: .underline, opening: opening, content: opening.upperBound..<tag.range.lowerBound,
                        closing: tag.range))
            }
        }
        return spans
    }

    // MARK: Links, images, code

    /// `[words](address)` or `![words](address)`, on one line, without nesting.
    private func link(at position: Int) -> TextFormatting.Span? {
        var start = position
        var isImage = false
        if units[position] == exclamation, position + 1 < range.upperBound, units[position + 1] == openBracket {
            isImage = true
            start = position + 1
        }
        guard units[start] == openBracket else { return nil }
        var close = start + 1
        while close < range.upperBound, units[close] != closeBracket, units[close] != openBracket { close += 1 }
        guard close + 1 < range.upperBound, units[close] == closeBracket, units[close + 1] == openParen else {
            return nil
        }
        var end = close + 2
        while end < range.upperBound, units[end] != closeParen, !isSpace(units[end]) { end += 1 }
        guard end < range.upperBound, units[end] == closeParen else { return nil }
        let address = String(decoding: units[(close + 2)..<end], as: UTF16.self)
        guard !address.isEmpty else { return nil }
        let span = TextFormatting.Span(
            style: isImage ? .image(source: address) : .link(url: address), opening: position..<(start + 1),
            content: (start + 1)..<close, closing: close..<(end + 1))
        return span
    }

    private func codeSpanEnd(from position: Int) -> Int? {
        var runEnd = position
        while runEnd < range.upperBound, units[runEnd] == backtick { runEnd += 1 }
        let length = runEnd - position
        var probe = runEnd
        while probe < range.upperBound {
            guard units[probe] == backtick else {
                probe += 1
                continue
            }
            var closeEnd = probe
            while closeEnd < range.upperBound, units[closeEnd] == backtick { closeEnd += 1 }
            if closeEnd - probe == length { return closeEnd }
            probe = closeEnd
        }
        return nil
    }

    // MARK: Characters

    private func isSpace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0xA0
    }

    private func isPunctuation(_ unit: UInt16) -> Bool {
        if isASCIIPunctuation(unit) { return true }
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar)
    }

    private func isASCIIPunctuation(_ unit: UInt16) -> Bool {
        (0x21...0x2F).contains(unit) || (0x3A...0x40).contains(unit) || (0x5B...0x60).contains(unit)
            || (0x7B...0x7E).contains(unit)
    }

    private func lowercased(_ unit: UInt16) -> UInt16 { (0x41...0x5A).contains(unit) ? unit + 0x20 : unit }

    private let backslash: UInt16 = 0x5C
    private let backtick: UInt16 = 0x60
    private let star: UInt16 = 0x2A
    private let underscore: UInt16 = 0x5F
    private let tilde: UInt16 = 0x7E
    private let plus: UInt16 = 0x2B
    private let lessThan: UInt16 = 0x3C
    private let exclamation: UInt16 = 0x21
    private let openBracket: UInt16 = 0x5B
    private let closeBracket: UInt16 = 0x5D
    private let openParen: UInt16 = 0x28
    private let closeParen: UInt16 = 0x29
}

// MARK: - Words only

/// The words of a Text without its Formatting markup: what search, passages and meaning read (ADR 0014).
/// Positions map both ways, so a match found in the words is highlighted on the same words in the Text.
public struct WordsOnlyText: Sendable, Equatable {
    public let words: String
    /// For each UTF-16 unit of `words`, where it is in the Text; one more entry for the end.
    private let sourceOffsets: [Int]

    public init(_ text: String, formatting: TextFormatting? = nil) {
        let units = Array(text.utf16)
        let formatting = formatting ?? TextFormatting(text)
        var hidden = [Bool](repeating: false, count: units.count)
        func hide(_ range: Range<Int>) {
            for index in range where index < hidden.count { hidden[index] = true }
        }
        for line in formatting.lines { hide(line.marker) }
        for span in formatting.spans {
            hide(span.opening)
            hide(span.closing)
        }
        var kept: [UInt16] = []
        var offsets: [Int] = []
        kept.reserveCapacity(units.count)
        offsets.reserveCapacity(units.count + 1)
        for (index, unit) in units.enumerated() where !hidden[index] {
            kept.append(unit)
            offsets.append(index)
        }
        offsets.append(units.count)
        words = String(decoding: kept, as: UTF16.self)
        sourceOffsets = offsets
    }

    /// How many words the Text has; markers like `-` or `1.` don't count.
    public var wordCount: Int { words.split(whereSeparator: \.isWhitespace).count }

    /// The range in the Text that a range in the words came from, markup inside it included.
    public func sourceRange(_ range: Range<Int>) -> Range<Int> {
        let last = sourceOffsets.count - 1
        let lower = sourceOffsets[min(max(range.lowerBound, 0), last)]
        // `last` is the end of the Text, not a character, so the end of a range maps from the one before it.
        guard range.upperBound > range.lowerBound, last > 0 else { return lower..<lower }
        let upper = sourceOffsets[min(max(range.upperBound - 1, 0), last - 1)] + 1
        return lower..<max(lower, upper)
    }

    /// The part of the words that a range in the Text covers.
    public func wordsRange(fromSource range: Range<Int>) -> Range<Int> {
        let lower = firstIndex(atOrAfter: range.lowerBound)
        let upper = firstIndex(atOrAfter: range.upperBound)
        return lower..<max(lower, upper)
    }

    /// The first unit of the words that comes from at or after a position in the Text.
    private func firstIndex(atOrAfter offset: Int) -> Int {
        var low = 0
        var high = sourceOffsets.count - 1
        while low < high {
            let middle = (low + high) / 2
            if sourceOffsets[middle] < offset { low = middle + 1 } else { high = middle }
        }
        return low
    }
}
