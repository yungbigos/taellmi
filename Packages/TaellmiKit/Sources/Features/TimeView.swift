import Domain
import SwiftUI

/// time: a zoomable time axis. Each thought is a mark: size = length, round = spoken, square = typed.
/// Hover shows its start; click opens it. Zoom and moving through time are in the bar at the bottom.
struct TimeView: View {
    @Bindable var model: ExploreViewModel
    @State private var hovered: TimelineMark?
    @Environment(\.brand) private var brand

    private var chosenPreview: String? {
        model.detail.map { CaptureViewModel.preview(of: $0.entry) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Zoom, earlier, later and today live in the bar at the bottom.
            Text(rangeLabel).brandFont("display.title").monospacedDigit()
            GeometryReader { geometry in
                let marks = TimelineLayout.marks(for: model.entries, in: model.timeRange)
                ZStack(alignment: .topLeading) {
                    BrandFillBackground(name: .axis, radius: nil).frame(height: 1)
                        .offset(y: geometry.size.height / 2)
                    ForEach(marks) { mark in
                        markView(mark)
                            .position(
                                x: 20 + mark.x * (geometry.size.width - 40),
                                y: geometry.size.height / 2 + Self.lane(for: mark.id) * geometry.size.height * 0.3)
                    }
                    if marks.isEmpty {
                        Text("no thoughts in this time.").brandForeground(.quiet)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            Text(hovered?.preview ?? chosenPreview ?? " ")
                .lineLimit(2)
                .brandForeground(.quiet)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
    }

    private func markView(_ mark: TimelineMark) -> some View {
        let side = 10 + mark.size * 26
        return Group {
            if mark.isSpoken {
                BrandFillBackground(name: .markSpoken, radius: nil).clipShape(Circle())
            } else {
                BrandFillBackground(name: .markTyped, radius: .mark)
            }
        }
        .frame(width: side, height: side)
        .overlay {
            // The thought you went to (e.g. from ⌘K) is ringed.
            if mark.id == model.selectedID {
                Circle().strokeBorder(brand?.color(.blue) ?? .accentColor, lineWidth: 2).padding(-5)
            }
        }
        .onHover { inside in hovered = inside ? mark : (hovered == mark ? nil : hovered) }
        .onTapGesture {
            Task {
                await model.perform(.showStack)
                await model.select(mark.id)
            }
        }
        .accessibilityLabel(mark.preview)
    }

    private var rangeLabel: String {
        let format = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        return
            "\(model.timeRange.start.formatted(format)) – \(model.timeRange.end.addingTimeInterval(-1).formatted(format))"
    }

    /// A stable vertical offset (-1…1) per thought, so marks close in time don't sit on top of each other.
    private static func lane(for id: String) -> CGFloat {
        let hash = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return CGFloat(hash % 200) / 100 - 1
    }
}
