import Domain
import SwiftUI

/// flow: every thought as one long note. Newest at the top, where it opens (issue #53); the month rail at the side
/// jumps back in time. Day dividers, each thought editable in place. A search highlights matches; ⌘G jumps
/// between them.
struct FlowView: View {
    @Bindable var model: ExploreViewModel
    @Environment(\.calendar) private var calendar
    @Environment(\.brand) private var brand
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var position = ScrollPosition(idType: String.self)
    @State private var landing = ScrollLanding()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(FlowSections.group(model.flowEntries, calendar: calendar)) { section in
                    Text(section.day, format: .dateTime.weekday(.wide).day().month(.wide).year())
                        .brandFont("display.heading")
                        .padding(.top, 24)
                    ForEach(section.entries) { entry in
                        ThoughtBlockRow(model: model, entry: entry)
                            .id(entry.id)
                    }
                }
            }
            .scrollTargetLayout()
            .frame(maxWidth: 720)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition($position)
        // Which thoughts are on screen, top first: the month rail follows.
        .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.2) { ids in model.flowVisible(ids) }
        .overlay {
            if model.flowEntries.isEmpty {
                ContentUnavailableView("no thoughts yet.", systemImage: "text.alignleft")
            }
        }
        .onAppear {
            if let id = model.scrollTarget { land(on: id) }
        }
        .onChange(of: model.scrollRequest) { _, request in
            if let request { land(on: request.entryID) }
        }
        .onChange(of: model.currentMatch) { _, id in
            if let id { land(on: id) }
        }
        // A new search lands on its first match, even when that is the same thought as before.
        .onChange(of: model.flowMatches) { _, _ in
            if let id = model.currentMatch { land(on: id) }
        }
    }
}

extension FlowView {
    fileprivate func land(on id: String) {
        landing.land(
            on: id, position: $position, animation: reduceMotion ? nil : brand?.animation(\.scroll) ?? .default)
    }
}
