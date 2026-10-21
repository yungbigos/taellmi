import CoreGraphics

/// Heights a growing editor has already measured, by text, width and look. Measuring lays the whole text out,
/// and SwiftUI asks again and again while a long flow scrolls; answering from here keeps scrolling smooth.
struct MeasuredHeights {
    private struct Key: Hashable {
        var text: String
        var width: CGFloat
        var style: Int
    }

    private var heights: [Key: CGFloat] = [:]
    private var order: [Key] = []
    private let limit: Int

    init(limit: Int = 4) {
        self.limit = limit
    }

    var count: Int { heights.count }

    mutating func height(text: String, width: CGFloat, style: Int, measure: () -> CGFloat) -> CGFloat {
        let key = Key(text: text, width: width, style: style)
        if let known = heights[key] { return known }
        let height = measure()
        heights[key] = height
        order.append(key)
        if order.count > limit { heights[order.removeFirst()] = nil }
        return height
    }
}
