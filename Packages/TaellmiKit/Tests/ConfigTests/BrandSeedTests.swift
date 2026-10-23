import Config
import CryptoKit
import Domain
import Foundation
import Testing

@Suite("Brand tokens ship as config")
struct BrandSeedTests {
    private func brandSetting() throws -> SeedBundle.Setting {
        try #require(try SeedBundle.bundled().settings.first { $0.key == SettingKeys.brandTokens })
    }

    @Test("the brand tokens are a seeded setting and decode into colours, tälli's look and motion")
    func decodes() throws {
        let tokens = try BrandTokens(json: try brandSetting().value)
        #expect(tokens.color.light.pink.value == "#F0397C")
        #expect(tokens.color.dark.blue.value == "#7398FF")
        #expect(tokens.talli.body.fill.stops.count == 6)
        #expect(tokens.motion.appearCursor.duration == 0.85)
        #expect(tokens.type.scale["text.thought"]?.family == "text")
    }

    @Test("the shipped tokens are exactly the ones decided in docs/brand/tokens.json")
    func matchesTheBrandBook() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../docs/brand/tokens.json").standardizedFileURL
        let documented = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: repo))
        #expect(try brandSetting().value == documented)
    }

    /// The seeder only updates a row whose seed version went up, so a changed token without a bump
    /// would never reach a Mac that already has tällmi. Bump `version` in both files, then update this pin.
    @Test("changing the tokens comes with a version bump, so existing installs pick it up")
    func changesBumpTheVersion() throws {
        let setting = try brandSetting()
        guard case .object(var fields) = setting.value else { throw CocoaError(.coderReadCorrupt) }
        fields["version"] = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let digest = SHA256.hash(data: try encoder.encode(JSONValue.object(fields)))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        let pinned: [Int: String] = [
            1: "c561ef1150f6432f190a94c004dcc95cfe505818750a1af934e2c0dbf75dcde5",
            2: "19dd482f2cb68801e55bbeb920a9876ad0cd489697b094da4870777eed0176f6",
            3: "8cc46fcf050a0b4d572ff92e0d2b88835c08376342d3cec84b13fb62cb65484e",
            4: "be657bdb66b9040c58372f6ff088cdab661e72b3b8522f1d20660442165c6d9a",
            5: "aa664b8797df804caf84eaaed12b7dff3fe1271e22cabb8ba5b017319af3f290",
            6: "dc456ff9afdcea7189f58096712b4d37dac781dc68d87696c3a103458a6dd5e3",
            7: "53297c01d8d123285feeee611bd030cd5249536f47876af561b5ff347f2d5259",
            8: "25a9703bd728d46a0917b29b940dfc709ad9ea65a7ca98f150340dbc809ffc05",
            9: "a458edf1a91a3a97c47772f6147ed6a25f07860044ef44402871222442f099fe",
            10: "1bf8683a8f7cfca54459bcd09158bf95708a357aeb5626227f537f1fa31944e9",
            11: "16b1b979ce51737771984ad21d96087a62254b4821734e43e0d11fe6c8bf8647",
            12: "ff1836595e58d408854c5d24e79e15506a554bb8f5201990720ca4400a0568c7",
            13: "1737e3c5fdb36f63c68ebc8de8a7fe3b52ef78128cb2d5b9b3c9ba9c45045a5b",
            14: "bfec15e42c0e5e4f3da0adb2e80a37461dd44627c9f7b602db72f832971628e3",
        ]
        #expect(
            pinned[setting.seedVersion] == hash,
            "tokens changed: bump version to \(setting.seedVersion + 1), pin \(hash)")
    }
}
