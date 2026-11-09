import Foundation

/// Exact column positions keep header/row alignment and the full scroll extent
/// while avoiding construction of cells hidden behind pinned columns or offscreen.
nonisolated struct LogTableColumnWindow: Equatable {
    let range: Range<Int>
    let leadingWidth: CGFloat
    let trailingWidth: CGFloat
}

nonisolated struct LogTableColumnLayout {
    private let edges: [CGFloat]

    init(widths: [CGFloat]) {
        var edges: [CGFloat] = [0]
        edges.reserveCapacity(widths.count + 1)
        for width in widths {
            edges.append(edges.last! + max(0, width))
        }
        self.edges = edges
    }

    var totalWidth: CGFloat { edges.last! }

    func window(horizontalOffset: CGFloat, viewportWidth: CGFloat, pinnedWidth: CGFloat) -> LogTableColumnWindow {
        let count = edges.count - 1
        let left = min(totalWidth, max(0, horizontalOffset))
        let right = min(totalWidth, left + max(0, viewportWidth - pinnedWidth))
        // Include one neighbouring column on either side for continuous gestures.
        let first = max(0, upperBound(left) - 2)
        let end = min(count, upperBound(right) + 1)
        return LogTableColumnWindow(range: first..<max(first, end),
                                    leadingWidth: edges[first], trailingWidth: totalWidth - edges[max(first, end)])
    }

    private func upperBound(_ value: CGFloat) -> Int {
        var low = 0
        var high = edges.count
        while low < high {
            let middle = low + (high - low) / 2
            if edges[middle] <= value { low = middle + 1 } else { high = middle }
        }
        return low
    }
}
