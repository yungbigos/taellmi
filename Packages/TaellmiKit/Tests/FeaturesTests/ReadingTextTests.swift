import AppKit
import Domain
import Foundation
import Testing

@testable import Features

private func shippedTokens() throws -> BrandTokens {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../Sources/Config/Resources/Seeds/brand.json").standardizedFileURL
    return try BrandTokens(json: try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)))
}

@Suite("A thought in read mode looks like the editor, without the editor")
struct ReadingTextTests {
    private func read(_ text: String, highlights: [TextHighlight] = []) throws -> NSAttributedString {
        ReadingText.make(text: text, highlights: highlights, brand: try shippedTokens(), token: "text.thought")
    }

    @Test("markup is hidden: bold stays bold without its stars, a list shows bullets")
    func markup() throws {
        let shown = try read("Heute **wichtig**:\n- Heizung\n- Vermieter")
        #expect(shown.string == "Heute wichtig:\n•\tHeizung\n•\tVermieter")
        let bold = shown.attribute(.font, at: 7, effectiveRange: nil) as? NSFont
        #expect(bold?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test("a checklist shows open and ticked boxes")
    func checklist() throws {
        #expect(try read("- [ ] Milch\n- [x] Brot").string == "☐\tMilch\n☑\tBrot")
    }

    @Test("search marks and concept underlines land on the same words after the markup is gone")
    func highlights() throws {
        let text = "Die **Heizung** gluckert."
        let heizung = (text as NSString).range(of: "Heizung")
        let shown = try read(
            text,
            highlights: [
                TextHighlight(range: heizung.location..<(heizung.location + heizung.length), kind: .concept("topic"))
            ])
        let at = (shown.string as NSString).range(of: "Heizung").location
        #expect(shown.attribute(.underlineStyle, at: at, effectiveRange: nil) != nil)
        #expect(shown.attribute(.underlineStyle, at: 0, effectiveRange: nil) == nil)
    }

    @Test("plain text stays exactly as it is")
    func plain() throws {
        #expect(try read("Mit Malin an der Isar.").string == "Mit Malin an der Isar.")
    }
}

@Suite("Line spacing that keeps the cursor the size of the text")
struct LineSpacingTests {
    @Test("the brand's line height is added as space between lines, not as taller lines")
    func spacingBetweenLines() throws {
        let brand = try shippedTokens()
        let shown = ReadingText.make(text: "Eins\nZwei", highlights: [], brand: brand, token: "text.thought")
        let paragraph = try #require(shown.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(paragraph.lineHeightMultiple == 0 || paragraph.lineHeightMultiple == 1)
        if brand.lineHeightMultiple("text.thought") > 1 { #expect(paragraph.lineSpacing > 0) }
    }
}
