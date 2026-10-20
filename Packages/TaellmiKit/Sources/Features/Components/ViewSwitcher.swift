import Domain
import SwiftUI

/// The switch between stack, flow, time and space: plain words, the active one with a thin blue outline
/// (brand token `active`), no frame around the others.
struct ViewSwitcher: View {
    let current: ExploreViewKind
    let choose: (ExploreViewKind) -> Void
    @Environment(\.brand) private var brand

    var body: some View {
        HStack(spacing: brand.space(.xs)) {
            ForEach(ExploreViewKind.allCases, id: \.self) { kind in
                let isActive = kind == current
                Button {
                    choose(kind)
                } label: {
                    Text(kind.rawValue)
                        .brandForeground(isActive ? .ink : .quiet)
                        .padding(.horizontal, brand.space(.m))
                        .padding(.vertical, brand.space(.xs))
                        .overlay {
                            if isActive, let active = brand?.surface.active {
                                Capsule().strokeBorder(
                                    brand?.color(BrandColorRole(rawValue: active.color) ?? .blue) ?? .accentColor,
                                    lineWidth: active.widthPt)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                // No system focus ring: the blue outline already marks the active view.
                .focusEffectDisabled()
                .accessibilityAddTraits(isActive ? .isSelected : [])
                .accessibilityLabel("show \(kind.rawValue)")
            }
        }
    }
}
