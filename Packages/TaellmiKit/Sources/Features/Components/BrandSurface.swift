import AppKit
import Domain
import SwiftUI

/// The kinds of surface tällmi draws. Each one is configured in the brand tokens (`surface`).
public enum BrandSurfaceKind: String, CaseIterable, Sendable {
    /// The tällmi window: sidebar, lists, toolbar.
    case window
    /// Under your thoughts: nearly solid, never glass.
    case reading
    /// Menu bar panel, ⌘K, settings, recovery key, unlock.
    case panel
    /// tälli's bubble.
    case bubble
}

/// A macOS material, by the name used in the brand tokens.
public enum BrandMaterial: String, Sendable {
    case sidebar, menu, popover, sheet
    case hudWindow = "hud_window"
    case windowBackground = "window_background"
    case underWindowBackground = "under_window_background"

    var visualEffect: NSVisualEffectView.Material {
        switch self {
        case .sidebar: .sidebar
        case .menu: .menu
        case .popover: .popover
        case .sheet: .sheet
        case .hudWindow: .hudWindow
        case .windowBackground: .windowBackground
        case .underWindowBackground: .underWindowBackground
        }
    }
}

public struct BrandOutline: Sendable, Equatable {
    public var color: BrandColorRole
    public var width: Double
}

/// What a surface turns into, once the Mac's accessibility settings are taken into account.
public enum SurfaceRendering: Sendable, Equatable {
    case material(BrandMaterial, tint: BrandColorRole, tintOpacity: Double)
    /// Liquid Glass; `clear` is the very see-through variant (things behind stay visible).
    case glass(tint: BrandColorRole, tintOpacity: Double, clear: Bool)
    case solid(BrandColorRole, outline: BrandOutline?)
}

/// Named quiet fills from the brand tokens (`fill`).
public enum BrandFillName: String, CaseIterable, Sendable {
    case field, selection, match, axis, related, concept
    case selectedRow = "selected_row"
    case matchCurrent = "match.current"
    case markSpoken = "mark.spoken"
    case markTyped = "mark.typed"
}

public struct BrandFill: Sendable, Equatable {
    public var color: BrandColorRole
    public var opacity: Double
}

/// Named corner radii from the brand tokens (`shape.radius_pt`).
public enum BrandRadius: String, CaseIterable, Sendable {
    case field, panel, bubble, mark
}

extension BrandTokens {
    private static let glass = "glass"
    private static let glassClear = "glass_clear"

    /// How a surface is drawn. Reduce Transparency and Increase Contrast always get a solid colour, so text
    /// keeps its contrast whatever is behind the window; a broken token also falls back to solid.
    public func rendering(
        of kind: BrandSurfaceKind, dark: Bool, reduceTransparency: Bool, increaseContrast: Bool
    ) -> SurfaceRendering {
        let token = surface(kind)
        let fallback = BrandColorRole(rawValue: token.fallback) ?? .paper
        if increaseContrast {
            return .solid(fallback, outline: outline)
        }
        guard !reduceTransparency, let tint = BrandColorRole(rawValue: token.tint) else {
            return .solid(fallback, outline: nil)
        }
        let opacity = dark ? token.tintOpacity.dark : token.tintOpacity.light
        if token.material == Self.glass { return .glass(tint: tint, tintOpacity: opacity, clear: false) }
        if token.material == Self.glassClear { return .glass(tint: tint, tintOpacity: opacity, clear: true) }
        guard let material = BrandMaterial(rawValue: token.material) else { return .solid(fallback, outline: nil) }
        return .material(material, tint: tint, tintOpacity: opacity)
    }

    /// A named fill; Increase Contrast makes it stronger.
    public func fill(_ name: BrandFillName, increaseContrast: Bool) -> BrandFill? {
        guard let token = fill[name.rawValue], let role = BrandColorRole(rawValue: token.color) else { return nil }
        return BrandFill(color: role, opacity: increaseContrast ? token.contrastOpacity : token.opacity)
    }

    /// A named fill as a native colour, for AppKit views.
    public func nsFill(_ name: BrandFillName, increaseContrast: Bool) -> NSColor? {
        guard let fill = fill(name, increaseContrast: increaseContrast) else { return nil }
        return nsColor(fill.color).withAlphaComponent(fill.opacity)
    }

    /// A named corner radius in points.
    public func radius(_ name: BrandRadius) -> Double {
        shape.radiusPt[name.rawValue] ?? 0
    }

    /// Surface entries whose material or colour name tällmi doesn't know, as `"kind.field: value"`.
    public func invalidSurfaceNames() -> [String] {
        var invalid: [String] = []
        for kind in BrandSurfaceKind.allCases {
            let token = surface(kind)
            if ![Self.glass, Self.glassClear].contains(token.material), BrandMaterial(rawValue: token.material) == nil {
                invalid.append("\(kind.rawValue).material: \(token.material)")
            }
            for (field, value) in [("tint", token.tint), ("fallback", token.fallback)]
            where BrandColorRole(rawValue: value) == nil {
                invalid.append("\(kind.rawValue).\(field): \(value)")
            }
        }
        if BrandColorRole(rawValue: surface.outline.color) == nil {
            invalid.append("outline.color: \(surface.outline.color)")
        }
        return invalid
    }

    /// A transition's curve and duration as a SwiftUI animation.
    func animation(_ transition: Motion.Crossfade) -> Animation {
        guard let points = easing[transition.easing]?.bezier, points.count == 4 else {
            return .easeInOut(duration: transition.duration)
        }
        return .timingCurve(points[0], points[1], points[2], points[3], duration: transition.duration)
    }

    private var outline: BrandOutline {
        BrandOutline(color: BrandColorRole(rawValue: surface.outline.color) ?? .quiet, width: surface.outline.widthPt)
    }

    private func surface(_ kind: BrandSurfaceKind) -> Surface {
        switch kind {
        case .window: surface.window
        case .reading: surface.reading
        case .panel: surface.panel
        case .bubble: surface.bubble
        }
    }
}

extension View {
    /// Draws a brand surface behind the view: a see-through macOS material with a thin tint, Liquid Glass
    /// for tälli's bubble, or a solid colour when Reduce Transparency or Increase Contrast is on.
    public func brandSurface(_ kind: BrandSurfaceKind, radius: BrandRadius? = nil) -> some View {
        background { BrandSurfaceBackground(kind: kind, radius: radius) }
    }

    /// Lays a named quiet fill behind the view, e.g. the ground of the live transcript.
    public func brandFill(_ name: BrandFillName, radius: BrandRadius? = .field) -> some View {
        background { BrandFillBackground(name: name, radius: radius) }
    }

    /// Animates changes of `value` with a brand transition (`crossfade` or `scroll`).
    func brandAnimation(
        _ transition: KeyPath<BrandTokens.Motion, BrandTokens.Motion.Crossfade>, value: some Equatable
    ) -> some View {
        modifier(BrandAnimation(transition: transition, value: value))
    }

    /// Text that reports a problem or a warning. Follows macOS: red and orange are system colours, not brand.
    func brandStatus(_ status: BrandStatus) -> some View {
        foregroundStyle(status == .problem ? Color.red : Color.orange)
    }
}

enum BrandStatus { case problem, warning }

extension BrandTokens {
    /// A brand transition, for `withAnimation` calls.
    func animation(_ transition: KeyPath<Motion, Motion.Crossfade>) -> Animation {
        animation(motion[keyPath: transition])
    }
}

struct BrandSurfaceBackground: View {
    var kind: BrandSurfaceKind
    var radius: BrandRadius?
    @Environment(\.brand) private var brand
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius.map { brand?.radius($0) ?? 0 } ?? 0, style: .continuous)
        if let brand {
            switch brand.rendering(
                of: kind, dark: colorScheme == .dark, reduceTransparency: reduceTransparency,
                increaseContrast: contrast == .increased)
            {
            case .material(let material, let tint, let opacity):
                ZStack {
                    VisualEffectBackground(material: material.visualEffect)
                    brand.color(tint).opacity(opacity)
                }
                .clipShape(shape)
            case .glass(let tint, let opacity, let clear):
                Color.clear.glassEffect(
                    (clear ? Glass.clear : Glass.regular).tint(brand.color(tint).opacity(opacity)), in: shape)
            case .solid(let role, let outline):
                // The outline marks floating shapes (bubble, fields); window-sized surfaces end at the window edge.
                shape.fill(brand.color(role))
                    .overlay {
                        if let outline, radius != nil {
                            shape.strokeBorder(brand.color(outline.color), lineWidth: outline.width)
                        }
                    }
            }
        } else if kind == .bubble {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.background)
        }
    }
}

struct BrandFillBackground: View {
    var name: BrandFillName
    var radius: BrandRadius?
    @Environment(\.brand) private var brand
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius.map { brand?.radius($0) ?? 0 } ?? 0, style: .continuous)
        if let brand, let fill = brand.fill(name, increaseContrast: contrast == .increased) {
            shape.fill(brand.color(fill.color).opacity(fill.opacity))
        } else {
            shape.fill(.quaternary)
        }
    }
}

private struct BrandAnimation<Value: Equatable>: ViewModifier {
    var transition: KeyPath<BrandTokens.Motion, BrandTokens.Motion.Crossfade>
    var value: Value
    @Environment(\.brand) private var brand

    func body(content: Content) -> some View {
        content.animation(brand?.animation(transition) ?? .default, value: value)
    }
}

/// The macOS material behind the window, so the desktop shows through.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    /// Always active: following the window's active state made the colour change when you clicked into it.
    static let state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = Self.state
        view.material = material
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
