import Domain
import SwiftUI

/// A floating glass capsule holding chips: the islands of the bottom bar and the view switcher at the top.
struct BarIsland<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.brand) private var brand

    var body: some View {
        HStack(spacing: brand.space(.xxs)) { content }
            .padding(.all, brand.space(.xs))
            .glassEffect(.regular, in: .capsule)
    }
}

/// A floating glass panel with a brand radius: the stack list, an open thought's details, the month rail.
struct FloatingPanel: ViewModifier {
    var radius: BrandRadius = .panel
    @Environment(\.brand) private var brand

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: brand?.radius(radius) ?? 16, style: .continuous)
        content
            .clipShape(shape)
            .glassEffect(.regular, in: shape)
    }
}

/// The pill behind a chosen word (a chip, a month, a picked concept), and the pill-shaped click area.
struct SelectionPill: ViewModifier {
    var selected: Bool

    func body(content: Content) -> some View {
        content
            .background {
                if selected { BrandFillBackground(name: .selection, radius: nil).clipShape(Capsule()) }
            }
            .contentShape(Capsule())
    }
}

extension View {
    func floatingPanel(radius: BrandRadius = .panel) -> some View { modifier(FloatingPanel(radius: radius)) }
    func selectionPill(_ selected: Bool) -> some View { modifier(SelectionPill(selected: selected)) }
}

/// A word in the bar you can choose; the chosen one carries the selection fill.
struct BarChip: View {
    let title: String
    var symbol: String?
    var selected = false
    var count: Int?
    /// Off for a chip that is only its symbol, like the formats; the title is then its accessibility label.
    var showsTitle = true
    let action: () -> Void
    @Environment(\.brand) private var brand

    var body: some View {
        Button(action: action) {
            HStack(spacing: brand.space(.xs)) {
                if let symbol { Image(systemName: symbol).imageScale(.small) }
                if showsTitle { Text(title) }
                if let count { Text("\(count)").monospacedDigit() }
            }
            .fontWeight(selected ? .semibold : .medium)
            .brandForeground(selected ? .blue : .ink)
            .padding(.horizontal, brand.space(.m))
            .frame(height: brand.space(.xxl))
            .selectionPill(selected)
        }
        .buttonStyle(.plain)
        // The selection fill marks the chosen one; a system focus ring on top looked broken.
        .focusEffectDisabled()
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A round symbol button in the bar; a toggle when it can be selected, with an optional count.
struct BarIconButton: View {
    let symbol: String
    let label: String
    var selected = false
    var badge = 0
    let action: () -> Void
    @Environment(\.brand) private var brand

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .brandForeground(selected ? .blue : .quiet)
                .frame(width: brand.space(.xxl), height: brand.space(.xxl))
                .background {
                    if selected { BrandFillBackground(name: .selection, radius: nil).clipShape(Circle()) }
                }
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .brandFont("text.label")
                            .monospacedDigit()
                            .brandForeground(.paper)
                            .padding(.horizontal, brand.space(.xxs))
                            .background(Capsule().fill(brand?.color(.quiet) ?? .secondary))
                            .offset(x: brand.space(.xxs) ?? 2, y: -(brand.space(.xxs) ?? 2))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
