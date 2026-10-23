import Foundation

/// The Kölner Phonetik: a sound code for German words. Words that sound alike get the same code
/// ("Kym" and "Kim" → "46").
public enum KoelnerPhonetik {
    public static func code(_ word: String) -> String {
        let letters = Array(
            word.uppercased()
                .replacingOccurrences(of: "Ä", with: "A").replacingOccurrences(of: "Ö", with: "O")
                .replacingOccurrences(of: "Ü", with: "U").replacingOccurrences(of: "ß", with: "S")
                .filter { $0.isLetter && $0.isASCII })
        var raw: [Character] = []
        for (index, letter) in letters.enumerated() {
            let previous = index > 0 ? letters[index - 1] : nil
            let next = index + 1 < letters.count ? letters[index + 1] : nil
            raw.append(contentsOf: digits(for: letter, previous: previous, next: next, isFirst: index == 0))
        }
        var collapsed: [Character] = []
        for digit in raw where digit != collapsed.last { collapsed.append(digit) }
        return String(collapsed.enumerated().filter { $0.offset == 0 || $0.element != "0" }.map(\.element))
    }

    private static func digits(for letter: Character, previous: Character?, next: Character?, isFirst: Bool) -> String {
        switch letter {
        case "A", "E", "I", "J", "O", "U", "Y": return "0"
        case "H": return ""
        case "B": return "1"
        case "P": return next == "H" ? "3" : "1"
        case "D", "T": return next.map { "CSZ".contains($0) } == true ? "8" : "2"
        case "F", "V", "W": return "3"
        case "G", "K", "Q": return "4"
        case "C":
            if isFirst { return next.map { "AHKLOQRUX".contains($0) } == true ? "4" : "8" }
            let hardNext = next.map { "AHKOQUX".contains($0) } == true
            let softPrevious = previous.map { "SZ".contains($0) } == true
            return hardNext && !softPrevious ? "4" : "8"
        case "X": return previous.map { "CKQ".contains($0) } == true ? "8" : "48"
        case "L": return "5"
        case "M", "N": return "6"
        case "R": return "7"
        case "S", "Z": return "8"
        default: return ""
        }
    }
}
