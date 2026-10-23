import Domain
import Foundation
import Testing

@testable import Features

@Suite("The wordmark's eyes")
struct WordmarkTests {
    private func shippedTokens() throws -> BrandTokens {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/Config/Resources/Seeds/brand.json").standardizedFileURL
        return try BrandTokens(json: try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)))
    }

    @Test("the two pink dots sit above the a where the logo file has them (docs/brand/logo/wordmark-light.svg)")
    func dotsMatchTheLogo() throws {
        // The logo is drawn at size 200; its a spans x 94.67…202.80 with its top at y 100.
        let a = CGRect(x: 94.67, y: 100, width: 202.80 - 94.67, height: 103.83)
        let dots = Wordmark.dots(over: a, size: 200, tokens: try shippedTokens().wordmark)
        #expect(dots.count == 2)
        #expect(abs(dots[0].center.x - 130.23) < 0.1)
        #expect(abs(dots[1].center.x - 159.23) < 0.1)
        #expect(dots.allSatisfy { abs($0.center.y - 63.4) < 0.1 && abs($0.radius - 13.6) < 0.01 })
    }
}
