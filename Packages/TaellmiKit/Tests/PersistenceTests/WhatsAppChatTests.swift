import Foundation
import Persistence
import TestSupport
import Testing

@Suite("Reading a chat exported from WhatsApp")
struct WhatsAppChatTests {
    /// Shaped exactly like a `_chat.txt` from WhatsApp on an iPhone set to German dates: U+200E before
    /// everything WhatsApp writes itself, CRLF after a message, LF between the lines of one message.
    static let selfChat =
        "\u{200E}[14.08.25, 17:39:08] yannik: tickets.pdf • \u{200E}1 page \u{200E}document omitted\r\n"
        + "\u{200E}[19.08.25, 19:44:41] yannik: \u{200E}audio omitted\r\n"
        + "[02.09.26, 12:34:31] yannik: Zählerstand ablesen  und notieren\nZähler-ID: 1ABC0000000000\n\n"
        + "Rückruf am Freitag\r\n"
        + "[02.09.26, 15:53:38] yannik: Geschenkidee für Kim: Kletterkurs\r\n"

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date? {
        berlinCalendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))
    }

    @Test("each message keeps its sender, its time to the second, and its own words, lines and all")
    func readsMessages() throws {
        let chat = try #require(WhatsAppChat(text: Self.selfChat, calendar: berlinCalendar))

        #expect(chat.messages.map(\.sender) == ["yannik", "yannik", "yannik", "yannik"])
        #expect(
            chat.messages.map(\.sentAt) == [
                Self.date(2025, 8, 14, 17, 39, 8), Self.date(2025, 8, 19, 19, 44, 41),
                Self.date(2026, 9, 2, 12, 34, 31), Self.date(2026, 9, 2, 15, 53, 38),
            ])
        #expect(
            chat.messages[2].text
                == "Zählerstand ablesen  und notieren\nZähler-ID: 1ABC0000000000\n\nRückruf am Freitag",
            "lines without a time continue the message above them, blank lines and double spaces included")
        #expect(chat.messages[3].text == "Geschenkidee für Kim: Kletterkurs", "a colon in the words stays")
    }

    @Test(
        "what WhatsApp writes itself is left out, in any language; a caption or an edited message keeps its words",
        arguments: [
            ("tickets.pdf • \u{200E}1 page \u{200E}document omitted", ""),
            ("\u{200E}audio omitted", ""),
            ("\u{200E}Bild weggelassen", ""),
            ("\u{200E}<attached: 00000012-PHOTO-2026-09-01-09-01-00.jpg>", ""),
            ("\u{200E}This message was deleted.", ""),
            ("\u{200E}Du hast diese Nachricht gelöscht.", ""),
            ("Bauplan.pdf • \u{200E}5 Seiten \u{200E}<Anhang: 00000008-Bauplan.pdf>", ""),
            ("Lecker \u{200E}Bild weggelassen", "Lecker"),
            ("\u{200E}Nachrichten und Anrufe sind Ende-zu-Ende-verschlüsselt.", ""),
            ("Bahn verpasst, nächste um 9:40 \u{200E}<This message was edited>", "Bahn verpasst, nächste um 9:40"),
            ("Zug fällt aus \u{200E}<Diese Nachricht wurde bearbeitet.>", "Zug fällt aus"),
        ])
    func leavesOutWhatWhatsAppWrote(body: String, words: String) throws {
        let chat = try #require(
            WhatsAppChat(text: "[01.09.26, 09:00:00] yannik: \(body)\r\n", calendar: berlinCalendar))
        #expect(chat.messages.map(\.text) == [words])
    }

    @Test(
        "dates and times are read the way the phone wrote them",
        arguments: [
            "[14.08.25, 17:39:08] a: x",
            "\u{200E}[8/14/25, 5:39:08\u{202F}PM] a: x",
            "[8/14/25, 5:39:08 PM] a: x",
            "[14/08/2025, 17:39:08] a: x",
            "[2025-08-14, 17:39:08] a: x",
            "[14/8/25, 5:39:08 p.\u{00A0}m.] a: x",
        ])
    func readsDateFormats(line: String) throws {
        let chat = try #require(WhatsAppChat(text: line, calendar: berlinCalendar))
        #expect(chat.messages.map(\.sentAt) == [Self.date(2025, 8, 14, 17, 39, 8)])
    }

    @Test("midnight and noon in 12-hour times, and times without seconds")
    func readsTimes() throws {
        let chat = try #require(
            WhatsAppChat(
                text: "[8/14/25, 12:05:00 AM] a: x\n[8/14/25, 12:05:00 PM] a: y\n[14.08.25, 17:39] a: z",
                calendar: berlinCalendar))
        #expect(
            chat.messages.map(\.sentAt) == [
                Self.date(2025, 8, 14, 0, 5, 0), Self.date(2025, 8, 14, 12, 5, 0), Self.date(2025, 8, 14, 17, 39, 0),
            ])
    }

    @Test("a date like 3/4 is read in the order the rest of the chat shows")
    func resolvesDayAndMonth() throws {
        let monthFirst = try #require(
            WhatsAppChat(text: "[3/4/25, 10:00:00] a: eins\n[3/13/25, 10:00:00] a: zwei", calendar: berlinCalendar))
        #expect(monthFirst.messages.first?.sentAt == Self.date(2025, 3, 4, 10, 0, 0))

        let dayFirst = try #require(
            WhatsAppChat(text: "[3/4/25, 10:00:00] a: eins\n[13/3/25, 10:00:00] a: zwei", calendar: berlinCalendar))
        #expect(dayFirst.messages.first?.sentAt == Self.date(2025, 4, 3, 10, 0, 0))
    }

    @Test("when no number is over 12, the one that changes more often is the day, 12-hour times or not")
    func resolvesByChange() throws {
        let monthFirst = try #require(
            WhatsAppChat(
                text: "[3/4/25, 10:00:00] a: eins\n[3/5/25, 10:00:00] a: zwei\n[3/6/25, 10:00:00] a: drei",
                calendar: berlinCalendar))
        #expect(monthFirst.messages.first?.sentAt == Self.date(2025, 3, 4, 10, 0, 0))

        let dayFirst = try #require(
            WhatsAppChat(
                text: "[4/3/25, 9:00:00 AM] a: eins\n[5/3/25, 9:00:00 AM] a: zwei\n[6/3/25, 9:00:00 AM] a: drei",
                calendar: berlinCalendar))
        #expect(dayFirst.messages.first?.sentAt == Self.date(2025, 3, 4, 9, 0, 0))

        let tooShort = try #require(WhatsAppChat(text: "[3/4/25, 9:00:00 AM] a: x", calendar: berlinCalendar))
        #expect(tooShort.messages.first?.sentAt == Self.date(2025, 3, 4, 9, 0, 0), "12-hour times: month first")
    }

    @Test("a message with nothing after the sender's name is still that sender's")
    func emptyMessage() throws {
        let chat = try #require(
            WhatsAppChat(
                text: "[01.09.26, 09:00:00] yannik:\n[01.09.26, 09:01:00] yannik: Hallo", calendar: berlinCalendar))
        #expect(chat.messages.map(\.sender) == ["yannik", "yannik"])
        #expect(chat.messages.map(\.text) == ["", "Hallo"])
    }

    @Test("invisible direction marks around a sender's name are dropped")
    func cleansSenders() throws {
        let chat = try #require(
            WhatsAppChat(text: "[01.09.26, 09:00:00] \u{202A}+49 170 0000000\u{202C}: Hallo", calendar: berlinCalendar))
        #expect(chat.messages.map(\.sender) == ["+49 170 0000000"])
    }

    @Test(
        "a file that doesn't start with a WhatsApp message isn't a chat",
        arguments: ["# Einkaufsliste\n- Milch", "", "Hallo\n[01.09.26, 09:00:00] a: x", "[99.99.26, 09:00:00] a: x"])
    func notAChat(text: String) {
        #expect(WhatsAppChat(text: text, calendar: berlinCalendar) == nil)
    }

    @Test(
        "a message has the same fingerprint in every export, also after you renamed yourself; other words or times don't"
    )
    func fingerprints() throws {
        let german = try #require(
            WhatsAppChat(text: "[02.09.26, 15:53:38] yannik: Kletterkurs", calendar: berlinCalendar))
        let british = try #require(
            WhatsAppChat(text: "[02/09/2026, 15:53:38] yannik: Kletterkurs", calendar: berlinCalendar))
        let renamed = try #require(
            WhatsAppChat(text: "[02.09.26, 15:53:38] Yannik B.: Kletterkurs", calendar: berlinCalendar))
        let others = try #require(
            WhatsAppChat(
                text: "[02.09.26, 15:53:38] yannik: Boulderkurs\n[02.09.26, 15:53:39] yannik: Kletterkurs",
                calendar: berlinCalendar))

        let fingerprint = try #require(german.messages.first?.fingerprint)
        #expect(fingerprint.hasPrefix("whatsapp:"))
        #expect(british.messages.first?.fingerprint == fingerprint)
        #expect(renamed.messages.first?.fingerprint == fingerprint)
        #expect(!others.messages.map(\.fingerprint).contains(fingerprint))
        #expect(Set(others.messages.map(\.fingerprint)).count == 2)
    }

    @Test("a line that only looks like the start of a message stays part of the message above")
    func lookalikeLines() throws {
        let noSender = try #require(
            WhatsAppChat(
                text: "[01.09.26, 09:00:00] yannik: Termine\n[01.09.26, 10:00] Arzt anrufen", calendar: berlinCalendar))
        #expect(noSender.messages.map(\.text) == ["Termine\n[01.09.26, 10:00] Arzt anrufen"])

        let noSuchDay = try #require(
            WhatsAppChat(
                text: "[01.09.26, 09:00:00] yannik: eins\n[31.02.26, 09:00:00] yannik: zwei", calendar: berlinCalendar))
        #expect(noSuchDay.messages.map(\.text) == ["eins\n[31.02.26, 09:00:00] yannik: zwei"])
    }

    @Test("only line feeds and carriage returns end a line; other breaks in your words stay as they are")
    func keepsOtherBreaks() throws {
        let chat = try #require(
            WhatsAppChat(text: "[01.09.26, 09:00:00] yannik: eins\u{2028}zwei\u{0C}drei\r\n", calendar: berlinCalendar))
        #expect(chat.messages.map(\.text) == ["eins\u{2028}zwei\u{0C}drei"])
    }
}
