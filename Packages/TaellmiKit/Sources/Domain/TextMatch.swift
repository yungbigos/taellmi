import Foundation

/// Where search words occur in a Text, the way search matches them: ignoring case, also inside compounds.
public enum TextMatch {
    /// UTF-16 ranges of every occurrence of any word, in text order; overlapping finds are merged. Words are
    /// matched in the Text's words without its Formatting, so `Ver**mieter**` is found as "vermieter"; the
    /// ranges point at the Text itself.
    public static func ranges(of words: [String], in text: String) -> [Range<Int>] {
        let view = WordsOnlyText(text)
        let string = view.words as NSString
        var found: [Range<Int>] = []
        for word in words where !word.isEmpty {
            var searchRange = NSRange(location: 0, length: string.length)
            while searchRange.length > 0 {
                let hit = string.range(of: word, options: [.caseInsensitive], range: searchRange)
                guard hit.location != NSNotFound, hit.length > 0 else { break }
                found.append(view.sourceRange(hit.location..<(hit.location + hit.length)))
                let next = hit.location + hit.length
                searchRange = NSRange(location: next, length: string.length - next)
            }
        }
        var merged: [Range<Int>] = []
        for range in found.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound < last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}

/// A short excerpt of a Text around a match, cut at word boundaries, for lists and the palette. It shows the
/// Text's words without their Formatting markup.
public struct Snippet: Sendable, Equatable {
    public let text: String
    /// Whether text was left out before or after the excerpt (show an ellipsis there).
    public let cutsStart: Bool
    public let cutsEnd: Bool
    /// Where the excerpt starts in the Text's words, in UTF-16 units.
    private let offset: Int
    private let length: Int
    private let view: WordsOnlyText

    /// - Parameter focus: the match, as a range in the Text (with its markup).
    public init(of text: String, around focus: Range<Int>?, maxLength: Int) {
        let view = WordsOnlyText(text)
        self.view = view
        let units = Array(view.words.utf16)
        let limit = max(1, maxLength)
        guard units.count > limit else {
            self.text = view.words
            cutsStart = false
            cutsEnd = false
            offset = 0
            length = units.count
            return
        }
        // A match from the index can be stale (the Text got shorter since); keep it inside the Text.
        let sourceLength = text.utf16.count
        let focus = focus.map { range in
            let lower = min(max(range.lowerBound, 0), sourceLength)
            return view.wordsRange(fromSource: lower..<min(max(range.upperBound, lower), sourceLength))
        }
        let anchor = min(max(focus?.lowerBound ?? 0, 0), units.count)
        let focusEnd = min(max(focus?.upperBound ?? anchor, anchor), units.count)
        var start = max(0, anchor - limit / 3)
        var end = min(units.count, start + limit)
        if end == units.count { start = max(0, units.count - limit) }

        func isSpace(_ index: Int) -> Bool { units[index] == 0x20 || units[index] == 0x0A || units[index] == 0x09 }
        if start > 0 {
            var boundary = start
            while boundary < min(anchor, units.count), boundary < units.count, !isSpace(boundary - 1) { boundary += 1 }
            start = boundary
        }
        if end < units.count {
            var boundary = end
            while boundary > max(start + 1, focusEnd), !isSpace(boundary) { boundary -= 1 }
            if boundary > start { end = boundary }
        }
        while start < end, isSpace(start) { start += 1 }
        while end > start, isSpace(end - 1) { end -= 1 }
        // Never split a character made of two UTF-16 units.
        if start > 0, start < units.count, UTF16.isTrailSurrogate(units[start]) { start -= 1 }
        if end < units.count, end > 0, UTF16.isTrailSurrogate(units[end]) { end += 1 }

        self.text = String(decoding: units[start..<end], as: UTF16.self)
        cutsStart = start > 0
        cutsEnd = end < units.count
        offset = start
        length = end - start
    }

    /// Ranges in the original Text, moved into the excerpt; parts outside it are dropped.
    public func ranges(_ ranges: [Range<Int>]) -> [Range<Int>] {
        ranges.map(view.wordsRange(fromSource:)).compactMap { range in
            let lower = max(range.lowerBound, offset)
            let upper = min(range.upperBound, offset + length)
            return lower < upper ? (lower - offset)..<(upper - offset) : nil
        }
    }
}
