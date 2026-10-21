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
            .background {
                if selected { BrandFillBackground(name: .selection, radius: nil).clipShape(Capsule()) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // The selection fill marks the chosen one; a system focus ring on top looked broken.
        .focusEffectDisabled()
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
