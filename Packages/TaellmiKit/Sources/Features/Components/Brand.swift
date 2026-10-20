import AppKit
import Domain
import SwiftUI

extension EnvironmentValues {
    /// The brand tokens from config. Set once at the root of every window with `.brandStyle(_:)`.
    @Entry public var brand: BrandTokens?
}

/// The colour roles of the brand. Pink is only ever used for the dots.
public enum BrandColorRole: String, Sendable {
    case paper, ink, blue, mist, pink, quiet

    func swatch(in palette: BrandTokens.Palette) -> BrandTokens.Swatch {
        switch self {
        case .paper: palette.paper
        case .ink: palette.ink
        case .blue: palette.blue
        case .mist: palette.mist
        case .pink: palette.pink
        case .quiet: palette.quiet
        }
    }
}

extension BrandTokens {
    /// A colour that follows light and dark mode by itself.
    public func color(_ role: BrandColorRole) -> Color {
        Color(nsColor: nsColor(role))
    }

    /// The same colour for AppKit views (e.g. a native text view).
    public func nsColor(_ role: BrandColorRole) -> NSColor {
        let light = Self.nsColor(hex: role.swatch(in: color.light).value)
        let dark = Self.nsColor(hex: role.swatch(in: color.dark).value)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    /// A type style from the scale as a native font, for AppKit text views.
    public func nsFont(_ token: String) -> NSFont {
        guard let style = type.scale[token] else { return .systemFont(ofSize: NSFont.systemFontSize) }
        let family = style.family == "display" ? type.families.display : type.families.text
        let size = type.base.sizePt * style.size * Self.textSizeScale
        let weight = Self.nsWeight(style.weight)
        var descriptor = NSFontDescriptor(fontAttributes: [.family: family])
            .addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: weight]])
        if style.italic == true { descriptor = descriptor.withSymbolicTraits(.italic) }
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    /// How much larger the Mac's text-size setting makes body text than the default; SwiftUI fonts follow it
    /// through `relativeTo:`, native ones through this.
    public static var textSizeScale: Double {
        NSFont.preferredFont(forTextStyle: .body).pointSize / NSFont.systemFontSize
    }

    /// The line height of a type style, as a multiple of the font size, for native text views.
    public func lineHeightMultiple(_ token: String) -> Double {
        type.scale[token]?.line ?? 1
    }

    static func nsWeight(_ value: Double) -> NSFont.Weight {
        switch value {
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        default: .heavy
        }
    }

    /// A type style from the scale, relative to the macOS body size so it follows the text-size setting.
    public func font(_ token: String) -> Font {
        guard let style = type.scale[token] else { return .body }
        let family = style.family == "display" ? type.families.display : type.families.text
        var font = Font.custom(family, size: type.base.sizePt * style.size, relativeTo: textStyle(for: style))
            .weight(Self.weight(style.weight))
        if style.italic == true { font = font.italic() }
        return font
    }

    func tracking(_ token: String) -> Double {
        guard let style = type.scale[token] else { return 0 }
        return style.tracking * type.base.sizePt * style.size
    }

    private func textStyle(for style: TypeTokens.Style) -> Font.TextStyle {
        switch style.size {
        case 3...: .largeTitle
        case 1.8..<3: .title
        case 1.3..<1.8: .title2
        case 1.05..<1.3: .title3
        case 0.95..<1.05: .body
        case 0.8..<0.95: .callout
        default: .caption
        }
    }

    static func weight(_ value: Double) -> Font.Weight {
        switch value {
        case ..<350: .light
        case ..<450: .regular
        case ..<550: .medium
        case ..<650: .semibold
        case ..<750: .bold
        default: .heavy
        }
    }

    static func nsColor(hex: String) -> NSColor {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt32(digits, radix: 16) ?? 0
        return NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    static func cgColor(hex: String, opacity: Double = 1) -> Color {
        Color(nsColor: nsColor(hex: hex)).opacity(opacity)
    }
}

extension View {
    /// Puts a window's content into the brand: tokens in the environment, the blue accent, and Funnel Sans
    /// as the base type. Parts macOS draws itself stay native.
    public func brandStyle(_ tokens: BrandTokens?) -> some View {
        modifier(BrandStyle(tokens: tokens))
    }

    /// Sets a type style from the brand scale, e.g. `"display.title"` or `"text.label"`.
    public func brandFont(_ token: String) -> some View {
        modifier(BrandFont(token: token))
    }

    /// Sets a brand colour as the foreground, following light and dark mode.
    public func brandForeground(_ role: BrandColorRole) -> some View {
        modifier(BrandForeground(role: role))
    }
}

private struct BrandStyle: ViewModifier {
    var tokens: BrandTokens?

    func body(content: Content) -> some View {
        if let tokens {
            content
                .environment(\.brand, tokens)
                .tint(tokens.color(.blue))
                .font(tokens.font("text.body"))
        } else {
            content
        }
    }
}

private struct BrandFont: ViewModifier {
    var token: String
    @Environment(\.brand) private var brand

    func body(content: Content) -> some View {
        if let brand {
            content.font(brand.font(token)).tracking(brand.tracking(token)).lineSpacing(brand.lineSpacing(token))
        } else {
            content
        }
    }
}

private struct BrandForeground: ViewModifier {
    var role: BrandColorRole
    @Environment(\.brand) private var brand

    func body(content: Content) -> some View {
        if let brand { content.foregroundStyle(brand.color(role)) } else { content }
    }
}
