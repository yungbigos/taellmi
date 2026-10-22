import CryptoKit
import Foundation

/// A chat exported from WhatsApp on an iPhone ("export chat"), read from its `_chat.txt`. Each message starts
/// with its time in brackets, written the way the phone writes dates; lines without one continue the message
/// above. WhatsApp puts U+200E before every text it adds itself (attachments, notices, "edited"), which tells
/// those apart from your words in any language.
public struct WhatsAppChat: Sendable, Equatable {
    public struct Message: Sendable, Equatable {
        public var sender: String
        public var sentAt: Date
        /// The words as written, without what WhatsApp added. Empty for a photo, voice message, document,
        /// deleted message or notice.
        public var text: String
        /// The same in every export of the chat: the time on the clock and the words. Not the sender, whose name
        /// changes when you rename yourself.
        public var fingerprint: String
    }

    public var messages: [Message]

    /// Nil when the text doesn't start with a WhatsApp message.
    public init?(text: String, calendar: Calendar) {
        var started: [(stamp: Stamp, line: Substring, lines: [Substring])] = []
        // WhatsApp ends lines with LF or CRLF; other breaks, like U+2028, are part of your words.
        for line in text.drop(while: { $0 == "\u{FEFF}" }).split(
            omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" })
        {
            if let stamp = Stamp(line) {
                started.append((stamp, line, [stamp.rest]))
            } else if !started.isEmpty {
                started[started.count - 1].lines.append(line)
            } else if line.contains(where: { !$0.isWhitespace }) {
                return nil
            }
        }
        let monthFirst = Stamp.monthFirst(started.map(\.stamp))
        var found: [(sender: String, date: Date, clock: Clock, lines: [Substring])] = []
        for (stamp, line, body) in started {
            guard let clock = stamp.clock(monthFirst: monthFirst), let date = clock.date(in: calendar),
                let (sender, firstLine) = Self.split(body[0], first: found.isEmpty)
            else {
                // A line that only looks like the start of a message (no such day, or no sender, which WhatsApp
                // on the iPhone always writes) is part of the message above.
                guard !found.isEmpty else { return nil }
                found[found.count - 1].lines += [line] + body.dropFirst()
                continue
            }
            found.append((sender, date, clock, [firstLine] + body.dropFirst()))
        }
        guard !found.isEmpty else { return nil }
        messages = found.map { sender, date, clock, lines in
            let text = Self.ownWords(lines)
            let hash = SHA256.hash(data: Data("\(clock.text)\n\(text)".utf8))
            return Message(
                sender: sender, sentAt: date, text: text,
                fingerprint: "whatsapp:" + hash.map { String(format: "%02x", $0) }.joined())
        }
    }

    /// "sam: Hallo" → ("sam", "Hallo"); "sam:" is an empty message. Without a sender, only the first
    /// message counts (an old notice); nil otherwise. Direction marks around a name, as WhatsApp writes phone
    /// numbers, are dropped.
    private static func split(_ rest: Substring, first: Bool) -> (sender: String, body: Substring)? {
        let (name, body): (Substring, Substring)
        if let colon = rest.range(of: ": ") {
            (name, body) = (rest[..<colon.lowerBound], rest[colon.upperBound...])
        } else if rest.hasSuffix(":") {
            (name, body) = (rest.dropLast(), rest[rest.endIndex...])
        } else {
            return first ? ("", rest) : nil
        }
        let visible = name.unicodeScalars.filter { $0.properties.generalCategory != .format }
        return (String(String.UnicodeScalarView(visible)).trimmingCharacters(in: .whitespaces), body)
    }

    /// The message's own lines. From the first U+200E on, a line is WhatsApp's ("Bild weggelassen", "<This
    /// message was edited>", a notice); words before it, like a photo's caption, stay. A document's line starts
    /// with its file name and "•", which isn't yours either.
    private static func ownWords(_ lines: [Substring]) -> String {
        let kept = lines.compactMap { line -> Substring? in
            guard let mark = line.firstIndex(of: "\u{200E}") else { return line }
            var words = line[..<mark]
            while words.last?.isWhitespace == true { words = words.dropLast() }
            return words.isEmpty || words.hasSuffix("•") ? nil : words
        }
        var text = kept.joined(separator: "\n")
        while text.last?.isWhitespace == true { text.removeLast() }
        return text
    }
}

/// The bracketed time at the start of a message, as written: `[23.05.25, 18:12:44]`, `[5/23/25, 6:12:44 PM]`,
/// `[23/05/2025, 18:12:44]` or `[2025-05-23, 18:12:44]`.
private struct Stamp {
    var numbers: (Int, Int, Int)
    var yearFirst: Bool
    var dots: Bool
    var hour: Int
    var minute: Int
    var second: Int
    /// For 12-hour times: true after noon.
    var afternoon: Bool?
    var rest: Substring

    init?(_ line: Substring) {
        let start = line.first == "\u{200E}" ? line.dropFirst() : line
        guard start.first == "[",
            let match = start.wholeMatch(
                of:
                    /\[(\d{1,4})([.\/-])(\d{1,2})[.\/-](\d{1,4}),? (\d{1,2})[:.](\d{2})(?:[:.](\d{2}))?(?:\s*([AaPp])\.?\s?[Mm]\.?)?\] (.*)/
                    .dotMatchesNewlines()  // the line is already cut; a U+2028 left in it is part of your words
            ),
            let first = Int(match.1), let middle = Int(match.3), let last = Int(match.4),
            let hour = Int(match.5), let minute = Int(match.6)
        else { return nil }
        numbers = (first, middle, last)
        yearFirst = match.1.count == 4
        dots = match.2 == "."
        self.hour = hour
        self.minute = minute
        second = match.7.flatMap { Int($0) } ?? 0
        afternoon = match.8.map { $0.lowercased() == "p" }
        rest = match.9
    }

    /// Whether dates like 3/4/25 put the month first. Dots always mean day first; otherwise the chat decides:
    /// a first number over 12 is a day, a second one over 12 a month, and else the number that changes more
    /// often from message to message is the day. Only a chat too short to tell goes by its clock: 12-hour times
    /// are most often American.
    static func monthFirst(_ stamps: [Stamp]) -> Bool {
        let open = stamps.filter { !$0.yearFirst && !$0.dots }
        if open.contains(where: { $0.numbers.0 > 12 }) { return false }
        if open.contains(where: { $0.numbers.1 > 12 }) { return true }
        let pairs = zip(open, open.dropFirst())
        let firstChanges = pairs.filter { $0.numbers.0 != $1.numbers.0 }.count
        let middleChanges = pairs.filter { $0.numbers.1 != $1.numbers.1 }.count
        if firstChanges != middleChanges { return middleChanges > firstChanges }
        return open.contains { $0.afternoon != nil }
    }

    func clock(monthFirst: Bool) -> Clock? {
        let (first, middle, last) = numbers
        let year = yearFirst ? first : last < 100 ? 2000 + last : last
        let (month, day) = yearFirst ? (middle, last) : monthFirst && !dots ? (first, middle) : (middle, first)
        var hour = hour
        if let afternoon {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (afternoon ? 12 : 0)
        }
        guard (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 60 else { return nil }
        return Clock(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    }
}

/// A time on the clock where the message was sent; WhatsApp writes no time zone.
private struct Clock {
    var year, month, day, hour, minute, second: Int

    var text: String { String(format: "%04d-%02d-%02dT%02d:%02d:%02d", year, month, day, hour, minute, second) }

    /// Nil for a day that doesn't exist, like 31.02.
    func date(in calendar: Calendar) -> Date? {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        guard let date = calendar.date(from: parts),
            calendar.dateComponents([.year, .month, .day], from: date)
                == DateComponents(year: year, month: month, day: day)
        else { return nil }
        return date
    }
}
