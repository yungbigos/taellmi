import Domain

/// The one line that tells you what an import of WhatsApp chats did (brand book: past tense, failures say why).
public enum ChatImportMessage {
    public static func text(for report: ChatImportReport) -> String {
        if report.imported.isEmpty, report.alreadyHere == 0, report.withoutWords == 0, report.failed.isEmpty {
            return "found no whatsapp chat there. export the chat, unzip it, and choose its _chat.txt or its folder."
        }
        let count = report.imported.count
        var sentences = ["imported \(count) \(count == 1 ? "message" : "messages")."]
        let here = report.alreadyHere
        if here > 0 { sentences.append("\(here) \(here == 1 ? "was" : "were") already here.") }
        if report.withoutWords > 0 {
            sentences.append("left out \(report.withoutWords) without words, like photos and voice messages.")
        }
        if !report.failed.isEmpty {
            let reasons = report.failed.map { "\($0.file) (\(reason($0.problem)))" }.joined(separator: ", ")
            sentences.append("couldn't import \(report.failed.count): \(reasons).")
        }
        return sentences.joined(separator: " ")
    }

    private static func reason(_ problem: ChatImportReport.Problem) -> String {
        switch problem {
        case .notAChat: "not a whatsapp chat"
        case .unreadable: "couldn't be read"
        case .notText: "not text"
        case .withOthers: "a chat with others; only chats with yourself for now"
        case .zipped: "unzip it first"
        case .unsaved: "not every message was saved; import it again"
        }
    }
}
