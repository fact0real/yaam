import AppKit
import SwiftUI

/// Every received card remains visible after matching or archiving.
struct QSLReceivedCardsView: View {
    @ObservedObject var inbox: QSLInboxEngine
    var onImport: () -> Void
    var onAttach: (QSLInboundItem) -> Void
    var onReview: (QSLInboundItem) -> Void
    var onOpenCard: (URL) -> Void
    @State private var receivedSearch = ""
    @State private var pendingCardsOnly = false

    var body: some View {
        VStack(spacing: 0) {
            // Subheader
            HStack {
                Text("RECEIVED CARDS (\(inbox.receivedCards.filter { $0.mediaFileURL != nil }.count))")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Button("Archive pending") {
                    Task { await inbox.archivePendingItems() }
                }
                .controlSize(.small)
                .disabled(inbox.inboundItems.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06))

            Divider()

            HStack {
                TextField("Search callsign, sender or subject", text: $receivedSearch)
                    .textFieldStyle(.roundedBorder)
                Toggle("Pending only", isOn: $pendingCardsOnly).toggleStyle(.checkbox)
                Button("Import…") { onImport() }
            }
            .padding(10)
            if let error = inbox.archiveError {
                Text(error).font(.caption).foregroundStyle(.red).padding(8)
            }

            if inbox.receivedCards.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No Received Cards Yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Drag and drop email files (.eml) from eQSL.cc or other operators,\nor drop images (.jpg, .png) and PDFs to match them against your logbook.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                    Button("Select Files to Import...") {
                        onImport()
                    }
                    .controlSize(.small)
                    .padding(.top, 4)
                    Spacer()
                }
            } else {
                List(visibleReceivedCards) { item in
                    inboundItemRow(item: item)
                }
                .listStyle(.plain)
            }
        }
    }

    private var visibleReceivedCards: [QSLInboundItem] {
        inbox.receivedCards.filter { item in
            (!pendingCardsOnly || (item.status != .archived && item.status != .rejected)) &&
            (receivedSearch.isEmpty || [item.callsign, item.fromAddress, item.subject, item.qsoDate]
                .contains { $0.localizedCaseInsensitiveContains(receivedSearch) })
        }
    }

    private func inboundItemRow(item: QSLInboundItem) -> some View {
        HStack(spacing: 12) {
            // Source icon
            Image(systemName: item.source == .email ? "envelope.fill" : (item.source == .image ? "photo.fill" : "doc.fill"))
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 28)

            // Detected Metadata
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.callsign.isEmpty ? "UNKNOWN CALL" : item.callsign)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                    Spacer()

                    // Match Confidence Badge
                    HStack(spacing: 3) {
                        Image(systemName: item.status == .matched ? "checkmark.seal.fill" : (item.status == .conflict ? "exclamationmark.triangle.fill" : "questionmark.circle"))
                        Text(item.status == .archived || item.status == .rejected ? item.status.rawValue : "\(item.matchConfidence)% Match")
                    }
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundColor(item.status.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(item.status.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }

                Text([item.qsoDate, item.qsoTime.isEmpty ? "" : item.qsoTime + " UTC", item.band, item.mode]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                Text("Received \(item.receivedAt.formatted(date: .abbreviated, time: .shortened)) · \(item.fromAddress)")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                if item.source == .eqsl && item.mediaFileURL == nil {
                    Label("eQSL notice · card image not downloaded", systemImage: "icloud.and.arrow.down")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if item.replySentAt != nil {
                    Label("QSL reply sent", systemImage: "paperplane.fill").font(.caption2)
                }
                if !item.subject.isEmpty {
                    Text(item.subject)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            // Thumbnail if card media present
            if let mediaURL = item.mediaFileURL, let img = NSImage(contentsOf: mediaURL) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 50, height: 35)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    .onTapGesture {
                        onOpenCard(mediaURL)
                    }
            }

            // Action Buttons
            HStack(spacing: 6) {
                if item.status == .conflict {
                    Button("Review Conflict") {
                        onReview(item)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                } else if item.status == .matched {
                    Button("Confirm & Attach") {
                        onAttach(item)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                }

                if let url = item.mediaFileURL {
                    Button { onOpenCard(url) } label: { Image(systemName: "eye") }
                        .help("Open received card")
                    Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "folder") }
                        .help("Reveal original card")
                }
                if item.status != .archived && item.status != .rejected {
                    Button {
                        Task { await inbox.setStatus(.archived, for: item.id) }
                    } label: { Image(systemName: "archivebox") }
                    .help("Archive card; keep its original file")
                }
            }
        }
        .padding(.vertical, 6)
    }

}
