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

    var body: some View {
        ScrollViewReader { proxy in
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
                .frame(maxWidth: 720)
                .padding(32)
                .frame(maxWidth: .infinity)
            }
            .overlay {
                if model.flowEntries.isEmpty {
                    ContentUnavailableView("no thoughts yet.", systemImage: "text.alignleft")
                }
            }
            .onAppear {
                if let id = model.scrollTarget { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: model.scrollRequest) { _, request in
                if let request { proxy.scrollTo(request.entryID, anchor: .center) }
            }
            .onChange(of: model.currentMatch) { _, id in
                if let id { scroll(to: id, with: proxy) }
            }
            // A new search lands on its first match, even when that is the same thought as before.
            .onChange(of: model.flowMatches) { _, _ in
                if let id = model.currentMatch { scroll(to: id, with: proxy) }
            }
        }
    }
}

extension FlowView {
    /// Thoughts far away only have an estimated height until they are drawn, so the first jump can land
    /// short; a second jump once they are laid out puts the match where it belongs.
    fileprivate func scroll(to id: String, with proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : brand?.animation(\.scroll) ?? .default) {
            proxy.scrollTo(id, anchor: .center)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            proxy.scrollTo(id, anchor: .center)
        }
    }
}
