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
        #expect(light == .material(.underWindowBackground, tint: .paper, tintOpacity: 0.2))
        #expect(dark == .material(.underWindowBackground, tint: .paper, tintOpacity: 0.25))
    }

    /// Owner's decision 2026-10-20: the desktop shows through under your thoughts too, but with enough paper
    /// that text stays readable, and never the glass-shape effect behind text.
    @Test("under your thoughts the desktop shows through, with enough paper for reading, never glass")
    func readingIsSeeThrough() throws {
        let tokens = try shippedTokens()
        for dark in [false, true] {
            let reading = tokens.rendering(of: .reading, dark: dark, reduceTransparency: false, increaseContrast: false)
            guard case .material(_, let tint, let opacity) = reading else {
                Issue.record("reading surface is \(reading)")
                continue
            }
            #expect(tint == .paper)
            #expect(opacity >= 0.1 && opacity <= 0.5)
        }
    }

    @Test("tälli's bubble is Liquid Glass")
    func bubbleIsGlass() throws {
        let tokens = try shippedTokens()
        let bubble = tokens.rendering(of: .bubble, dark: false, reduceTransparency: false, increaseContrast: false)
        // Clear glass, so what's behind tälli's bubble stays visible (owner, 2026-10-20).
        #expect(bubble == .glass(tint: .paper, tintOpacity: 0.1, clear: true))
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

@Suite("Brand values for native text views")
struct BrandNativeTests {
    @Test("a type token gives a native font of the scale's size")
    func nativeFont() throws {
        let tokens = try shippedTokens()
        let style = try #require(tokens.type.scale["text.thought"])
        let expected = tokens.type.base.sizePt * style.size * BrandTokens.textSizeScale
        #expect(abs(tokens.nsFont("text.thought").pointSize - expected) < 0.01)
    }

    @Test("a type token gives its line height for native text views")
    func nativeLineHeight() throws {
        let tokens = try shippedTokens()
        let style = try #require(tokens.type.scale["text.thought"])
        #expect(tokens.lineHeightMultiple("text.thought") == style.line)
    }

    @Test("a fill gives a native colour with the token's opacity, stronger with Increase Contrast")
    func nativeFill() throws {
        let tokens = try shippedTokens()
        let quiet = try #require(tokens.nsFill(.related, increaseContrast: false))
        let strong = try #require(tokens.nsFill(.related, increaseContrast: true))
        #expect(abs(quiet.alphaComponent - 0.12) < 0.001)
        #expect(strong.alphaComponent > quiet.alphaComponent)
    }
}

@Suite("The see-through window")
struct WindowMaterialTests {
    @Test("the window looks the same whether or not it is in front, so clicking into it never changes its colour")
    func staysActive() {
        #expect(VisualEffectBackground.state == .active)
    }
}
