import Domain
import SwiftUI

/// The switch between stack, flow, time and space, in the same glass island as the bottom bar.
struct ViewSwitcher: View {
    let current: ExploreViewKind
    let choose: (ExploreViewKind) -> Void

    var body: some View {
        BarIsland {
            ForEach(ExploreViewKind.allCases, id: \.self) { kind in
                BarChip(title: kind.rawValue, selected: kind == current) { choose(kind) }
                    .accessibilityLabel("show \(kind.rawValue)")
            }
        }
    }
}
