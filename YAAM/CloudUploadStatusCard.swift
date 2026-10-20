import SwiftUI

struct CloudUploadStatusCard: View {
    let notice: CloudUploadNotice
    let message: String
    let pendingCount: Int
    let canRetry: Bool
    let retry: () -> Void
    let dismiss: () -> Void
    private var tint: Color {
        switch notice { case .accepted: return .green; case .waiting: return .orange; case .needsAttention: return .red }
    }
    private var title: String {
        switch notice { case .accepted: return "Contact accepted by services"; case .waiting: return "Upload waiting"; case .needsAttention: return "Upload needs your attention" }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: notice.symbol).font(.title3).foregroundStyle(tint)
                    .frame(width: 34, height: 34).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(action: dismiss) { Image(systemName: "xmark").font(.caption.weight(.semibold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Dismiss upload status")
            }
            if pendingCount > 0 {
                HStack {
                    Label("\(pendingCount) contact(s) in outbox", systemImage: "tray").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button("Retry pending", systemImage: "arrow.clockwise", action: retry)
                        .controlSize(.small).disabled(!canRetry)
                        .help("Retry pending destinations. Accepted services stay complete.")
                }
            }
        }.padding(14).frame(maxWidth: 620, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.4), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}
