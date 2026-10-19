import SwiftUI

/// Counter-scroll only in the compositor. Feeding a rounded offset into @State
/// invalidates every row and the log toolbar during each horizontal gesture.
struct PinnedLogColumns: ViewModifier {
    func body(content: Content) -> some View {
        content.visualEffect { effect, geometry in
            effect.offset(x: max(0, -geometry.frame(in: .named("logTableScrollSpace")).minX))
        }
    }
}
