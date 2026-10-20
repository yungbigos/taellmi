import Domain
import SwiftUI

/// time: a zoomable time axis. Each thought is a mark: size = length, round = spoken, square = typed.
/// Hover shows its start; click opens it.
struct TimeView: View {
    @Bindable var model: ExploreViewModel
    @State private var hovered: TimelineMark?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    Task { await model.perform(.showEarlier) }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("show earlier")
                Text(rangeLabel).brandFont("display.title").monospacedDigit()
                Button {
                    Task { await model.perform(.showLater) }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("show later")
                Spacer()
                Picker(
                    "zoom",
                    selection: Binding(
                        get: { model.timeRange.zoom },
                        set: { zoom in
                            while model.timeRange.zoom < zoom { model.timeRange.zoomOut() }
                            while model.timeRange.zoom > zoom { model.timeRange.zoomIn() }
                        })
                ) {
                    ForEach(TimelineZoom.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            }
            .buttonStyle(.borderless)
            GeometryReader { geometry in
                let marks = TimelineLayout.marks(for: model.entries, in: model.timeRange)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(.quaternary).frame(height: 1)
                        .offset(y: geometry.size.height / 2)
                    ForEach(marks) { mark in
                        markView(mark)
                            .position(
                                x: 20 + mark.x * (geometry.size.width - 40),
                                y: geometry.size.height / 2 + Self.lane(for: mark.id) * geometry.size.height * 0.3)
                    }
                    if marks.isEmpty {
                        Text("no thoughts in this time.").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            Text(hovered?.preview ?? " ")
                .lineLimit(2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
    }

    private func markView(_ mark: TimelineMark) -> some View {
        let side = 10 + mark.size * 26
        return Group {
            if mark.isSpoken {
                Circle().fill(.tint.opacity(0.75))
            } else {
                RoundedRectangle(cornerRadius: 3).fill(.tint.opacity(0.45))
            }
        }
        .frame(width: side, height: side)
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
