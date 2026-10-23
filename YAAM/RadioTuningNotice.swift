import SwiftUI

/// Retained QSY errors are separate from periodic provider refresh status.
struct RadioTuningNotice: View {
    let message: String
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Dismiss", action: dismiss).buttonStyle(.bordered)
        }
        .foregroundStyle(.orange)
        .padding(12)
        .background(Color.orange.opacity(0.08))
    }
}
