import Foundation

@main struct LogTableColumnWindowRegression {
    static func main() {
        var checks = 0
        func verify(_ widths: [CGFloat], _ offset: CGFloat, _ viewport: CGFloat, _ pinned: CGFloat) {
            let layout = LogTableColumnLayout(widths: widths)
            let window = layout.window(horizontalOffset: offset, viewportWidth: viewport, pinnedWidth: pinned)
            precondition(window.range.lowerBound >= 0 && window.range.upperBound <= widths.count)
            let leading = widths.prefix(window.range.lowerBound).reduce(0, +)
            let trailing = widths.suffix(widths.count - window.range.upperBound).reduce(0, +)
            precondition(abs(window.leadingWidth - leading) < 0.001)
            precondition(abs(window.trailingWidth - trailing) < 0.001)
            precondition(abs(leading + widths[window.range].reduce(0, +) + trailing - layout.totalWidth) < 0.001)
            var x: CGFloat = 0
            let left = max(0, offset)
            let right = left + max(0, viewport - pinned)
            for (index, width) in widths.enumerated() {
                if x + width > left && x < right { precondition(window.range.contains(index), "Visible column omitted") }
                x += width
            }
            checks += 1
        }
        for widths: [CGFloat] in [[], [100], [20, 500, 36, 180, 76, 1000], Array(repeating: 100, count: 200)] {
            for viewport: CGFloat in [0, 200, 760, 1280, 30000] {
                for offset: CGFloat in [-100, 0, 19, 20, 99, 100, 499, 900, 19000, 99999] {
                    for pinned: CGFloat in [0, 48, 540, 1000] { verify(widths, offset, viewport, pinned) }
                }
            }
        }
        // Fractional resizes, hidden columns, and a narrow window with pinned columns covering it.
        for seed in 0..<1000 {
            let widths = (0..<40).map { CGFloat(30 + (($0 * 73 + seed * 17) % 280)) + 0.5 }
            verify(widths, CGFloat(seed * 7), CGFloat(760 + seed % 640), 540)
            verify(Array(widths.dropFirst(seed % 20)), CGFloat(seed * 7), 300, 540)
        }
        let many = LogTableColumnLayout(widths: Array(repeating: 100, count: 200))
        precondition(many.window(horizontalOffset: 0, viewportWidth: 1000, pinnedWidth: 540).range.count <= 7)
        precondition(many.window(horizontalOffset: 15000, viewportWidth: 1000, pinnedWidth: 540).range.count <= 8)
        print("LogTableColumnWindowRegression passed: \(checks) geometry/coverage checks; offscreen cells bounded")
    }
}
