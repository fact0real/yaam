import SwiftUI

/// Pinned safety notices; status updates, re-keying and reconnects never acknowledge physical receive.
struct TransmitNoticesView: View {
    @ObservedObject var notices = TransmitNotices.shared

    var body: some View {
        if !notices.notices.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(notices.notices) { notice in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(notice.source.name + " · Check receive", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.red)
                            Text(notice.text)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("I checked: the radio is on receive") { notices.dismiss(notice.id) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityHint("Acknowledge this radio only after checking its physical receive state.")
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(.red).frame(width: 3) }
                    }
                }
            }
            .frame(height: min(CGFloat(notices.notices.count) * 190, 260))
        }
    }
}
