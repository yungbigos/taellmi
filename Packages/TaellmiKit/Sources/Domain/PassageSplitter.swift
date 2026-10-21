import Foundation

/// A contiguous stretch of an Entry's Text.
public struct TextSpan: Sendable, Equatable {
    public var text: String
    /// Position in the Text in UTF-16 code units, the unit text views use.
    public var utf16Range: Range<Int>

    public init(text: String, utf16Range: Range<Int>) {
        self.text = text
        self.utf16Range = utf16Range
    }
}

/// Splits Text into passages (Fragments) by its own structure: blank lines always separate, each list item is
/// a passage of its own, a heading starts a new one, and long paragraphs are grouped into runs of whole
/// sentences of about `targetLength` characters (ADR 0011, ADR 0014).
///
/// Passages hold the Text's words without their Formatting, which is what gets embedded; their ranges point
/// at those words in the Text, markup inside them included.
///
/// This is the simple, model-free first stage. Splitting by topic (embeddings + LLM) can replace it later.
public struct PassageSplitter: Sendable {
    public var targetLength: Int
    public var maxLength: Int

    public init(targetLength: Int, maxLength: Int) {
        self.targetLength = max(1, targetLength)
        self.maxLength = max(self.targetLength, maxLength)
    }

    public func passages(in text: String) -> [TextSpan] {
        let formatting = TextFormatting(text)
        let view = WordsOnlyText(text, formatting: formatting)
        let units = Array(view.words.utf16)
        // Where a character (emoji, letter plus accent) begins, so a hard cut never splits one.
        var boundaries = [Bool](repeating: false, count: units.count + 1)
        for index in view.words.indices { boundaries[index.utf16Offset(in: view.words)] = true }
        boundaries[units.count] = true
        return blocks(formatting).flatMap { block in
            paragraphs(units, in: view.wordsRange(fromSource: block)).flatMap { paragraph in
                group(sentences(units, in: paragraph).flatMap { cut(units, boundaries, $0) }, units)
            }
        }
        .map { TextSpan(text: String(decoding: units[$0], as: UTF16.self), utf16Range: view.sourceRange($0)) }
    }

    // MARK: - Steps, all working on UTF-16 ranges

    /// Parts of the Text that never share a passage: each list item, and a heading with what follows it.
    private func blocks(_ formatting: TextFormatting) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var open: Range<Int>?
        func close() {
            if let block = open { result.append(block) }
            open = nil
        }
        for line in formatting.lines {
            switch line.kind {
            case .listItem:
                close()
                result.append(line.content)
            case .heading:
                close()
                open = line.content
            default:
                open = (open?.lowerBound ?? line.range.lowerBound)..<line.range.upperBound
            }
        }
        close()
        return result
    }

    private func paragraphs(_ units: [UInt16], in range: Range<Int>) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = range.lowerBound
        var index = range.lowerBound
        while index < range.upperBound {
            guard units[index] == newline else {
                index += 1
                continue
            }
            // A blank line: a newline followed by only whitespace up to the next newline.
            var probe = index + 1
            while probe < range.upperBound, isSpace(units[probe]), units[probe] != newline { probe += 1 }
            if probe < range.upperBound, units[probe] == newline {
                result.append(start..<index)
                start = probe + 1
                index = probe + 1
            } else {
                index += 1
            }
        }
        result.append(start..<range.upperBound)
        return result.compactMap { trimmed($0, units) }
    }

    /// Sentence ends: `.`, `!`, `?` or `…` followed by whitespace, and single line breaks.
    private func sentences(_ units: [UInt16], in range: Range<Int>) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = range.lowerBound
        for index in range {
            let endsSentence =
                units[index] == newline
                || (terminators.contains(units[index]) && index + 1 < range.upperBound && isSpace(units[index + 1]))
            if endsSentence {
                result.append(start..<(index + 1))
                start = index + 1
            }
        }
        result.append(start..<range.upperBound)
        return result.compactMap { trimmed($0, units) }
    }

    /// Cuts a sentence that is too long at the last space before `maxLength`.
    private func cut(_ units: [UInt16], _ boundaries: [Bool], _ range: Range<Int>) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = range.lowerBound
        while range.upperBound - start > maxLength {
            let limit = start + maxLength
            var split = limit
            while split > start, !isSpace(units[split]) { split -= 1 }
            if split == start {
                // One enormous word: cut it anyway, but between two characters.
                split = limit
                while split > start + 1, !boundaries[split] { split -= 1 }
            }
            if let piece = trimmed(start..<split, units) { result.append(piece) }
            start = split
        }
        if let piece = trimmed(start..<range.upperBound, units) { result.append(piece) }
        return result
    }

    /// Joins consecutive sentences while the passage stays within `targetLength`.
    private func group(_ sentences: [Range<Int>], _ units: [UInt16]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var current: Range<Int>?
        for sentence in sentences {
            if let open = current, sentence.upperBound - open.lowerBound <= targetLength {
                current = open.lowerBound..<sentence.upperBound
            } else {
                if let open = current { result.append(open) }
                current = sentence
            }
        }
        if let open = current { result.append(open) }
        return result
    }

    private func trimmed(_ range: Range<Int>, _ units: [UInt16]) -> Range<Int>? {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, isSpace(units[lower]) { lower += 1 }
        while upper > lower, isSpace(units[upper - 1]) { upper -= 1 }
        return lower < upper ? lower..<upper : nil
    }

    private let newline: UInt16 = 0x0A
    private let terminators: Set<UInt16> = [0x2E, 0x21, 0x3F, 0x2026]

    private func isSpace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0xA0
    }
}
