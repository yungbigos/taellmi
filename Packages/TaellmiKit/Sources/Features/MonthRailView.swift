import Domain
import SwiftUI

/// The month rail at the side of flow and time (issue #53): every month, newest at the top, with a dot per
/// thought. In flow a month scrolls to it; in time it shows that month.
struct MonthRailView: View {
    @Bindable var model: ExploreViewModel
    @Environment(\.brand) private var brand
    @Environment(\.calendar) private var calendar

    var body: some View {
        let months = model.railMonths
        if !months.isEmpty {
            ViewThatFits(in: .vertical) {
                list(months)
                ScrollView { list(months) }.scrollIndicators(.never)
            }
            .padding(.vertical, brand.space(.s))
            .padding(.horizontal, brand.space(.xs))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: brand?.radius(.bubble) ?? 14, style: .continuous))
            .fixedSize(horizontal: true, vertical: false)
            .padding(.trailing, brand.space(.l))
            .padding(.vertical, brand.space(.xl))
        }
    }

    private func list(_ months: [RailMonth]) -> some View {
        VStack(alignment: .leading, spacing: brand.space(.xxs)) {
            ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                let year = calendar.component(.year, from: month.start)
                if index == 0 || calendar.component(.year, from: months[index - 1].start) != year {
                    Text(String(year))
                        .brandFont("text.label")
                        .brandForeground(.quiet)
                        .padding(.horizontal, brand.space(.s))
                        .padding(.top, index == 0 ? 0 : brand.space(.xs))
                }
                row(month)
            }
        }
    }

    private func row(_ month: RailMonth) -> some View {
        let current = model.currentRailMonth == month.start
        return Button {
            Task { await model.jump(to: month) }
        } label: {
            HStack(spacing: brand.space(.s)) {
                Text(month.start.formatted(.dateTime.month(.abbreviated)).lowercased())
                    .brandFont("text.label")
                    .brandForeground(current ? .blue : (month.count == 0 ? .quiet : .ink))
                Spacer(minLength: 0)
                HStack(spacing: brand.space(.xxs)) {
                    ForEach(0..<min(month.count, brand?.space.railMaxDots ?? 0), id: \.self) { _ in
                        BrandFillBackground(name: .markSpoken, radius: nil)
                            .clipShape(Circle())
                            .frame(width: brand.space(.xs), height: brand.space(.xs))
                    }
                }
            }
            .frame(minWidth: brand.space(.xxxl))
            .padding(.horizontal, brand.space(.s))
            .padding(.vertical, brand.space(.xxs))
            .background {
                if current { BrandFillBackground(name: .selection, radius: nil).clipShape(Capsule()) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.view == .flow && month.count == 0)
        .accessibilityLabel(
            "\(month.start.formatted(.dateTime.month(.wide).year())), \(ThoughtCount.words(month.count))")
    }
}
