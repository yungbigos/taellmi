import Config
import Domain
import Foundation
import Testing

@testable import AppComposition

@Suite("The brand survives an old or edited brand row")
struct BrandFallbackTests {
    @Test("a stored version 1 brand row, without surfaces, falls back to the shipped tokens instead of no brand")
    func oldRowFallsBackToShipped() throws {
        let shipped = try #require(AppEnvironment.seededBrand)
        guard case .object(var fields) = try JSONValue(encoding: shipped) else { throw CocoaError(.coderReadCorrupt) }
        fields["surface"] = nil
        fields["fill"] = nil
        fields["shape"] = nil
        #expect(AppEnvironment.brand(stored: .object(fields)) == shipped)
    }

    @Test("a stored row that decodes is used as it is")
    func validRowIsUsed() throws {
        var shipped = try #require(AppEnvironment.seededBrand)
        shipped.surface.window.tintOpacity.light = 0.6
        #expect(AppEnvironment.brand(stored: try JSONValue(encoding: shipped))?.surface.window.tintOpacity.light == 0.6)
    }
}

extension JSONValue {
    fileprivate init(encoding tokens: BrandTokens) throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self = try JSONDecoder().decode(JSONValue.self, from: encoder.encode(tokens))
    }
}
