//
//  ImportReviewView.swift
//  YAAM
//

import SwiftUI

struct ImportReviewView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedKind: ImportReviewKind?

    private var review: PendingImportReview? { appState.pendingImportReview }

    private var visibleItems: [ImportReviewItem] {
        guard let review else { return [] }
        guard let selectedKind else { return review.items }
        return review.items.filter { $0.kind == selectedKind }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let review {
                summary(review)
                Divider()
                reviewToolbar(review)
                Divider()
                itemList
                Divider()
                footer(review)
            } else {
                ContentUnavailableView(
                    "No Import Pending",
                    systemImage: "tray",
                    description: Text("Choose an ADIF or SmartSDR log from the File menu to begin.")
                )
            }
        }
        .frame(
            minWidth: 900,
            idealWidth: 1040,
            maxWidth: .infinity,
            minHeight: 600,
            idealHeight: 720,
            maxHeight: .infinity
        )
        .resizablePresentation(minWidth: 900, minHeight: 600)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: review?.sourceFormat.systemImage ?? "doc.badge.magnifyingglass")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 42, height: 42)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(review.map { "Review \($0.sourceFormat.title) Import" } ?? "Review Import")
                    .font(.title2.weight(.semibold))
                Text(review?.sourceName ?? "Log import")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Label(appState.activeStationProfile?.displayTitle ?? "No station", systemImage: "antenna.radiowaves.left.and.right")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(18)
    }

    private func summary(_ review: PendingImportReview) -> some View {
        HStack(spacing: 0) {
            importMetric(kind: .newQSO, count: review.count(for: .newQSO), color: .blue)
            Divider().frame(height: 42)
            importMetric(kind: .confirmationUpdate, count: review.count(for: .confirmationUpdate), color: .green)
            Divider().frame(height: 42)
            importMetric(kind: .duplicate, count: review.count(for: .duplicate), color: .secondary)
            Divider().frame(height: 42)
            importMetric(kind: .potentialConflict, count: review.count(for: .potentialConflict), color: .orange)
            Divider().frame(height: 42)
            importMetric(kind: .invalid, count: review.count(for: .invalid), color: .red)
        }
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private func importMetric(kind: ImportReviewKind, count: Int, color: Color) -> some View {
        Button {
            selectedKind = selectedKind == kind ? nil : kind
        } label: {
            HStack(spacing: 9) {
                Image(systemName: kind.systemImage)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(count.formatted())
                        .font(.headline.monospacedDigit())
                    Text(kind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selectedKind == kind ? color.opacity(0.10) : .clear)
        .help("Show only \(kind.title.lowercased()) records")
    }

    private func reviewToolbar(_ review: PendingImportReview) -> some View {
        HStack(spacing: 10) {
            if let selectedKind {
                Label(selectedKind.title, systemImage: selectedKind.systemImage)
                    .font(.callout.weight(.medium))
                Button {
                    self.selectedKind = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear filter")
            } else {
                Text("All \(review.items.count) records")
                    .font(.callout.weight(.medium))
            }

            Spacer()

            if let selectableKind = selectedKind,
               selectableKind != .duplicate,
               selectableKind != .invalid {
                Button {
                    appState.selectImportReviewItems(kind: selectableKind, selected: true)
                } label: {
                    Label("Select All", systemImage: "checkmark.circle")
                }
                Button {
                    appState.selectImportReviewItems(kind: selectableKind, selected: false)
                } label: {
                    Label("Select None", systemImage: "circle")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var itemList: some View {
        List(visibleItems) { item in
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { item.isSelected },
                    set: { appState.setImportReviewSelection(itemID: item.id, selected: $0) }
                ))
                .labelsHidden()
                .disabled(item.kind == .duplicate || item.kind == .invalid)

                Image(systemName: item.kind.systemImage)
                    .foregroundStyle(color(for: item.kind))
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(item.callsign.isEmpty ? "Missing callsign" : item.callsign)
                            .font(.body.weight(.semibold).monospaced())
                        Text(item.date)
                            .font(.callout.monospacedDigit())
                        Text(item.time)
                            .font(.callout.monospacedDigit())
                        Text(item.band)
                            .font(.callout.weight(.medium))
                        Text(item.mode)
                            .font(.callout.weight(.medium))
                    }
                    Text(item.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
                Text(item.kind.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(for: item.kind))
            }
            .padding(.vertical, 5)
        }
        .listStyle(.inset)
    }

    private func footer(_ review: PendingImportReview) -> some View {
        HStack(spacing: 12) {
            Label("A restore point is created before any selected record changes the Master Log.", systemImage: "clock.arrow.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
            Button("Cancel", role: .cancel) {
                appState.cancelPendingImport()
            }
            Button {
                appState.commitPendingImport()
            } label: {
                Label("Import \(review.selectedCount)", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(review.selectedCount == 0)
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func color(for kind: ImportReviewKind) -> Color {
        switch kind {
        case .newQSO: return .blue
        case .confirmationUpdate: return .green
        case .duplicate: return .secondary
        case .potentialConflict: return .orange
        case .invalid: return .red
        }
    }
}
