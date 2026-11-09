import SwiftUI

/// Own horizontal visibility locally: a column boundary must not recompute the
/// log toolbar, filters, or summary counts, and vertical scrolling changes no state.
struct LogTableScrollViewport<Content: View>: View {
    let columnWidths: [CGFloat]
    let pinnedWidth: CGFloat
    @ViewBuilder let content: (LogTableColumnWindow) -> Content
    @State private var horizontalOffset: CGFloat = 0

    var body: some View {
        let layout = LogTableColumnLayout(widths: columnWidths)
        GeometryReader { geometry in
            let window = layout.window(horizontalOffset: horizontalOffset,
                                       viewportWidth: geometry.size.width, pinnedWidth: pinnedWidth)
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                content(window)
            }
            .coordinateSpace(name: "logTableScrollSpace")
            .onScrollGeometryChange(for: HorizontalViewport.self) { scroll in
                HorizontalViewport(offset: scroll.contentOffset.x,
                    window: layout.window(horizontalOffset: scroll.contentOffset.x,
                                          viewportWidth: scroll.containerSize.width, pinnedWidth: pinnedWidth))
            } action: { _, newWindow in
                horizontalOffset = newWindow.offset
            }
        }
    }
}

private struct HorizontalViewport: Equatable {
    let offset: CGFloat
    let window: LogTableColumnWindow

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.window == rhs.window }
}
