import SwiftUI

struct QSLSyncPreviewSheet: View {
    let preview: QSLSyncPreview
    var confirm: () -> Void
    var cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Review Sync All", systemImage: "arrow.triangle.2.circlepath")
                .font(.title2.bold())
            Text("Station: \(preview.stationCallsign)").font(.headline)
            Text("Upload contacts not yet sent to each available service, then download available confirmations. The same contact may be listed for multiple services.")
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(QSLProvider.allCases) { provider in
                        HStack(alignment: .top) {
                            Label(provider.title, systemImage: provider.icon).frame(width: 150, alignment: .leading)
                            if let reason = preview.notChecked[provider] {
                                Text("No upload: \(reason)").foregroundStyle(.secondary)
                            } else {
                                let count = preview.uploads[provider]?.count ?? 0
                                Text("\(count) \(count == 1 ? "upload" : "uploads")").monospacedDigit().bold()
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 200)
            Text("\(preview.uploadCount) uploads in total. Failed or blocked jobs stay stopped unless their credentials were updated. No records have been queued by this preview.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let blocker = preview.blocker {
                Label(blocker, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button("Confirm & Sync", action: confirm)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(preview.blocker != nil)
            }
        }
        .padding(24).frame(minWidth: 480, idealWidth: 550, maxWidth: 620)
    }
}
