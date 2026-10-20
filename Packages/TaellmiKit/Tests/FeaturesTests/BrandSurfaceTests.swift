import Domain
import Foundation
import Testing

@testable import Features

/// The brand tokens as shipped in the Config seeds.
private func shippedTokens() throws -> BrandTokens {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../Sources/Config/Resources/Seeds/brand.json").standardizedFileURL
    return try BrandTokens(json: try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)))
}

@Suite("How see-through tällmi's windows and panels are")
struct BrandSurfaceTests {
    @Test("normally the window is a macOS material with a thin paper tint, thicker in dark mode as configured")
    func windowIsTranslucent() throws {
        let tokens = try shippedTokens()
        let light = tokens.rendering(of: .window, dark: false, reduceTransparency: false, increaseContrast: false)
        let dark = tokens.rendering(of: .window, dark: true, reduceTransparency: false, increaseContrast: false)
        #expect(light == .material(.underWindowBackground, tint: .paper, tintOpacity: 0.4))
        #expect(dark == .material(.underWindowBackground, tint: .paper, tintOpacity: 0.45))
    }

    @Test("under your thoughts the surface is nearly solid paper, never glass")
    func readingIsNearlySolid() throws {
        let tokens = try shippedTokens()
        for dark in [false, true] {
            let reading = tokens.rendering(of: .reading, dark: dark, reduceTransparency: false, increaseContrast: false)
            guard case .material(_, let tint, let opacity) = reading else {
                Issue.record("reading surface is \(reading)")
                continue
            }
            #expect(tint == .paper)
            #expect(opacity >= 0.8)
        }
    }

    @Test("tälli's bubble is Liquid Glass")
    func bubbleIsGlass() throws {
        let tokens = try shippedTokens()
        let bubble = tokens.rendering(of: .bubble, dark: false, reduceTransparency: false, increaseContrast: false)
        #expect(bubble == .glass(tint: .paper, tintOpacity: 0.2))
    }

    @Test(
        "Reduce Transparency turns every surface solid, without an outline",
        arguments: BrandSurfaceKind.allCases)
    func reduceTransparencyIsSolid(kind: BrandSurfaceKind) throws {
        let tokens = try shippedTokens()
        let rendering = tokens.rendering(of: kind, dark: false, reduceTransparency: true, increaseContrast: false)
        #expect(rendering == .solid(.paper, outline: nil))
    }

    @Test(
        "Increase Contrast turns every surface solid and draws the outline",
        arguments: BrandSurfaceKind.allCases)
    func increaseContrastIsSolidWithOutline(kind: BrandSurfaceKind) throws {
        let tokens = try shippedTokens()
        let rendering = tokens.rendering(of: kind, dark: true, reduceTransparency: false, increaseContrast: true)
        #expect(rendering == .solid(.paper, outline: BrandOutline(color: .quiet, width: 1)))
    }

    @Test("fills use their contrast opacity when Increase Contrast is on")
    func fillsGetStrongerWithContrast() throws {
        let tokens = try shippedTokens()
        #expect(tokens.fill(.selection, increaseContrast: false) == BrandFill(color: .blue, opacity: 0.16))
        #expect(tokens.fill(.selection, increaseContrast: true) == BrandFill(color: .blue, opacity: 0.32))
        #expect(tokens.fill(.field, increaseContrast: true) == BrandFill(color: .mist, opacity: 1))
    }

    @Test("every surface, fill and radius the views use is in the shipped tokens and names a known colour")
    func shippedTokensAreComplete() throws {
        let tokens = try shippedTokens()
        #expect(tokens.invalidSurfaceNames().isEmpty)
        for name in BrandFillName.allCases {
            #expect(tokens.fill[name.rawValue] != nil, "missing fill \(name.rawValue)")
        }
        for name in BrandRadius.allCases {
            #expect(tokens.shape.radiusPt[name.rawValue] != nil, "missing radius \(name.rawValue)")
        }
    }

    @Test("a surface with an unknown material or colour falls back to solid paper instead of failing")
    func unknownNamesFallBack() throws {
        var tokens = try shippedTokens()
        tokens.surface.panel.material = "frosted"
        #expect(tokens.invalidSurfaceNames() == ["panel.material: frosted"])
        let rendering = tokens.rendering(of: .panel, dark: false, reduceTransparency: false, increaseContrast: false)
        #expect(rendering == .solid(.paper, outline: nil))
    }

    @Test("view switches and scroll jumps take their timing from the motion tokens")
    func motionTimings() throws {
        let tokens = try shippedTokens()
        #expect(tokens.motion.crossfade.duration == 0.16)
        #expect(tokens.motion.crossfade.easing == "soft")
        #expect(tokens.motion.scroll.duration == 0.25)
    }
}
