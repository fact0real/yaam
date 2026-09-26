//
//  BulkQRZEnrichmentView.swift
//  YAAM
//

import SwiftUI

struct BulkQRZEnrichmentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var onlyMissingEmail = true
    @State private var allowHAMQTH = true
    @State private var forceRecheck = true

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.indigo)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Bulk QRZ Email & Contact Enrichment")
                        .font(.headline)
                    Text("Batch retrieve email addresses and operator names for contacts across your entire logbook.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Close") {
                    if appState.isBulkQRZEnriching {
                        appState.stopBulkQRZEnrichment()
                    }
                    appState.bulkQRZCompleted = false
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(spacing: 18) {
                    // Metrics Grid
                    HStack(spacing: 12) {
                        metricCard(
                            title: "Total QSOs",
                            value: "\(appState.qsoRecords.count)",
                            icon: "book.closed.fill",
                            color: .blue
                        )
                        metricCard(
                            title: "Unique Calls",
                            value: "\(appState.uniqueCallsignCount)",
                            icon: "person.2.fill",
                            color: .indigo
                        )
                        metricCard(
                            title: "With Email",
                            value: "\(appState.callsignsWithEmailCount)",
                            icon: "envelope.fill",
                            color: .green
                        )
                        metricCard(
                            title: "Missing Email",
                            value: "\(appState.callsignsMissingEmailCount)",
                            icon: "envelope.badge.fill",
                            color: .orange
                        )
                    }

                    if appState.isBulkQRZEnriching {
                        // Live Progress Section
                        progressCard
                    } else if appState.bulkQRZCompleted {
                        // Completion Summary
                        completionCard
                    } else {
                        // Pre-flight Configuration Section
                        configurationCard
                    }
                }
                .padding(18)
            }

            Divider()

            // Footer Bar
            HStack {
                if !appState.isBulkQRZEnriching && !appState.bulkQRZCompleted {
                    Label("Requests are paced at ~350ms to protect your QRZ account.", systemImage: "shield.lefthalf.filled")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if appState.isBulkQRZEnriching {
                    Button(role: .destructive) {
                        appState.stopBulkQRZEnrichment()
                    } label: {
                        Label("Stop Enrichment", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else if appState.bulkQRZCompleted {
                    Button("Enrich More / Settings") {
                        appState.bulkQRZCompleted = false
                    }
                    .buttonStyle(.bordered)

                    Button("Done") {
                        appState.bulkQRZCompleted = false
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                } else {
                    Button("Cancel") {
                        appState.bulkQRZCompleted = false
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        appState.startBulkQRZEnrichment(
                            onlyMissingEmail: onlyMissingEmail,
                            allowHAMQTH: allowHAMQTH,
                            forceRecheck: forceRecheck
                        )
                    } label: {
                        Label("Start Enrichment", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(appState.qsoRecords.isEmpty || targetCandidateCount == 0)
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 580, idealWidth: 640, minHeight: 460, idealHeight: 520)
        .resizablePresentation(minWidth: 580, minHeight: 460)
        .onAppear {
            if !appState.isBulkQRZEnriching {
                appState.bulkQRZCompleted = false
            }
        }
        .onDisappear {
            if !appState.isBulkQRZEnriching {
                appState.bulkQRZCompleted = false
            }
        }
    }

    private var targetCandidateCount: Int {
        appState.bulkQRZCandidateCount(onlyMissingEmail: onlyMissingEmail, forceRecheck: forceRecheck)
    }

    // MARK: - Metric Card
    private func metricCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.subheadline)
                Spacer()
            }
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Configuration Card
    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Enrichment Options & Scope")
                .font(.subheadline.bold())

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $onlyMissingEmail) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Only lookup callsigns currently missing an email address")
                            .font(.body)
                        Text("Skips stations that already have a valid email, saving bandwidth and network requests.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: $forceRecheck) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include callsigns checked previously in backfill")
                            .font(.body)
                        Text("Re-evaluates stations that were previously marked as checked but still have no email saved.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Toggle(isOn: $allowHAMQTH) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Query HAMQTH as secondary fallback")
                            .font(.body)
                        Text("If QRZ.com does not publish an email for the callsign, queries HAMQTH if credentials are configured.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(8)

            // Authentication Banner
            if QRZSessionStore.hasSavedSession() {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("QRZ Authenticated Session Active")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                        Text("Logged in via WebKit Session. YAAM has access to member-only contact emails.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No Active QRZ Session Cookies Detected")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                        Text("QRZ hides email addresses from non-logged in users. Log in first for best results.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("QRZ Login...") {
                        appState.showQRZLoginSheet = true
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }

            // Estimate Summary
            let targetCount = targetCandidateCount
            let estimatedSeconds = Double(targetCount) * 0.35
            let minutes = Int(estimatedSeconds / 60)
            let seconds = Int(estimatedSeconds.truncatingRemainder(dividingBy: 60))
            let estimateStr = minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"

            if targetCount == 0 {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No Callsigns Match Selection")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                        Text("All \(appState.callsignsMissingEmailCount) stations missing email were marked checked by previous automatic backfills. Enable \"Include callsigns checked previously in backfill\" to re-evaluate them.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            } else {
                HStack {
                    Image(systemName: "clock.badge.checkmark")
                        .foregroundColor(.secondary)
                    Text("Target: **\(targetCount)** callsigns to evaluate. Estimated time: **~\(estimateStr)**.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Live Progress Card
    private var progressCard: some View {
        VStack(spacing: 16) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Enriching Contacts from QRZ...")
                    .font(.headline)
                Spacer()
                Text("Callsign: ")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(appState.bulkQRZCurrentCallsign.isEmpty ? "-" : appState.bulkQRZCurrentCallsign)
                    .font(.title3.bold().monospaced())
                    .foregroundColor(.indigo)
            }

            let current = appState.bulkQRZProgress.current
            let total = max(1, appState.bulkQRZProgress.total)
            let progressRatio = Double(current) / Double(total)
            let percentage = Int(progressRatio * 100)

            ProgressView(value: progressRatio)
                .progressViewStyle(.linear)
                .tint(.indigo)

            HStack {
                Text("\(current) of \(total) callsigns (\(percentage)%)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Spacer()
            }

            Divider()

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(.green)
                    Text("+\(appState.bulkQRZStats.emailsFound) Emails Found")
                        .font(.subheadline.bold())
                        .foregroundColor(.green)
                }

                HStack(spacing: 6) {
                    Image(systemName: "person.text.rectangle")
                        .foregroundColor(.blue)
                    Text("+\(appState.bulkQRZStats.namesFound) Names Found")
                        .font(.subheadline.bold())
                        .foregroundColor(.blue)
                }

                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.secondary)
                    Text("\(appState.bulkQRZStats.notFound) Not Listed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Completion Summary Card
    private var completionCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("Bulk Enrichment Complete! 🎉")
                .font(.title3.bold())

            Text("Successfully processed \(appState.bulkQRZProgress.total) callsigns across your logbook.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("\(appState.bulkQRZStats.emailsFound)")
                        .font(.title2.bold())
                        .foregroundColor(.green)
                    Text("Emails Added")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider().frame(height: 36)

                VStack(spacing: 4) {
                    Text("\(appState.bulkQRZStats.namesFound)")
                        .font(.title2.bold())
                        .foregroundColor(.blue)
                    Text("Names Added")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider().frame(height: 36)

                VStack(spacing: 4) {
                    Text("\(appState.bulkQRZStats.notFound)")
                        .font(.title2.bold())
                        .foregroundColor(.secondary)
                    Text("No Email Found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)

            Text("All updated email addresses and names have been automatically saved to your Master Log.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}
