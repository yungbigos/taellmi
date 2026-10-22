import Domain

/// The one line that tells you what an import of notes did (brand book: past tense, failures say why).
public enum NoteImportMessage {
    public static func text(for report: NoteImportReport) -> String {
        let chats = report.chats != ChatImportReport() ? ChatImportMessage.text(for: report.chats) : nil
        if report.imported.isEmpty, report.alreadyHere.isEmpty, report.failed.isEmpty {
            return chats ?? "found no notes there. choose notes exported from apple notes, or a folder of them."
        }
        let count = report.imported.count
        var sentences = ["imported \(count) \(count == 1 ? "note" : "notes")."]
        let here = report.alreadyHere.count
        if here > 0 { sentences.append("\(here) \(here == 1 ? "was" : "were") already here.") }
        if !report.failed.isEmpty {
            let reasons = report.failed.map { "\($0.file) (\(reason($0.problem)))" }.joined(separator: ", ")
            sentences.append("couldn't import \(report.failed.count): \(reasons).")
        }
        if let chats { sentences.append(chats) }
        return sentences.joined(separator: " ")
    }

    private static func reason(_ problem: NoteImportReport.Problem) -> String {
        switch problem {
        case .notANote: "not a note file"
        case .unreadable: "couldn't be read"
        case .notText: "not text"
        case .empty: "no words in it"
        }
    }
}
