//
//  DuplicateReviewView.swift
//  YAAM
//

import SwiftUI

struct DuplicateReviewView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let review = appState.duplicateReview {
                summary(review)
                Divider()
                duplicateList(review)
                Divider()
                actions(review)
            }
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 520, idealHeight: 620)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.doc.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 38, height: 38)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                Text("Review Duplicate QSOs")
                    .font(.title3.bold())
                Text("YAAM keeps the richest record and merges missing confirmation details before removal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
    }

    private func summary(_ review: DuplicateReview) -> some View {
        HStack(spacing: 20) {
            metric(value: review.groups.count, label: "Duplicate groups", icon: "square.stack.3d.up")
            metric(value: review.totalRemovalCount, label: "Extra QSO rows", icon: "minus.circle")
            metric(value: review.selectedRemovalCount, label: "Selected to remove", icon: "checkmark.circle")
            Spacer()
            Button("Select None") { appState.selectAllDuplicateGroups(false) }
            Button("Select All") { appState.selectAllDuplicateGroups(true) }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
    }

    private func metric(value: Int, label: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(value.formatted()).font(.headline.monospacedDigit())
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func duplicateList(_ review: DuplicateReview) -> some View {
        List(review.groups) { group in
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { appState.duplicateReview?.selectedGroupIDs.contains(group.id) == true },
                    set: { appState.setDuplicateGroupSelection(groupID: group.id, selected: $0) }
                ))
                .labelsHidden()

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.callsign)
                        .font(.headline.monospaced())
                    Text("\(displayDate(group.date))  \(displayTime(group.time)) UTC")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(width: 190, alignment: .leading)

                Label(group.band.isEmpty ? "Unknown band" : group.band, systemImage: "waveform.path")
                    .frame(width: 120, alignment: .leading)
                Label(group.mode.isEmpty ? "Unknown mode" : group.mode, systemImage: "dot.radiowaves.left.and.right")
                    .frame(width: 140, alignment: .leading)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(group.copyCount) copies")
                        .font(.subheadline.bold())
                    Text("Keep row #\(group.keeperRow)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 5)
        }
        .listStyle(.inset)
    }

    private func actions(_ review: DuplicateReview) -> some View {
        HStack {
            Label("A restore point will be created before any row is removed.", systemImage: "externaldrive.badge.timemachine")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { appState.cancelDuplicateReview() }
                .keyboardShortcut(.cancelAction)
            Button(role: .destructive) {
                appState.commitDuplicateCleanup()
            } label: {
                Label("Remove \(review.selectedRemovalCount) Extra QSOs", systemImage: "trash")
            }
            .disabled(review.selectedRemovalCount == 0)
            .keyboardShortcut(.defaultAction)
        }
        .padding(18)
    }

    private func displayDate(_ raw: String) -> String {
        guard raw.count == 8 else { return raw }
        return "\(raw.prefix(4))-\(raw.dropFirst(4).prefix(2))-\(raw.suffix(2))"
    }

    private func displayTime(_ raw: String) -> String {
        guard raw.count >= 4 else { return raw }
        return "\(raw.prefix(2)):\(raw.dropFirst(2).prefix(2))"
    }
}
