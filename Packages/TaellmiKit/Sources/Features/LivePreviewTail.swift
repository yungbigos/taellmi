import Foundation

/// What fits of a live transcript: its end, since that is what you are saying right now.
public enum LivePreviewTail {
    public nonisolated static func tail(of text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters, maxCharacters > 0 else { return text }
        let end = String(text.suffix(maxCharacters))
        // Start at the next whole word, unless that leaves nothing.
        if let space = end.firstIndex(where: \.isWhitespace) {
            let fromWord = end[end.index(after: space)...].trimmingCharacters(in: .whitespaces)
            if !fromWord.isEmpty { return "… " + fromWord }
        }
        return "… " + end
    }
}
