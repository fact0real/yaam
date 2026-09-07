//
//  TodayConfirmedQSLDispatchView.swift
//  YAAM
//
//  Created for YAAM Amateur Radio Logbook.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

enum DispatchItemStatus: Equatable {
    case ready
    case renderingPDF
    case sendingSMTP
    case sent
    case failed(String)
    case queuedBureau

    var label: String {
        switch self {
        case .ready: return "Ready"
        case .renderingPDF: return "Rendering PDF..."
        case .sendingSMTP: return "Sending SMTP..."
        case .sent: return "Sent ✅"
        case .failed(let err): return "Failed: \(err)"
        case .queuedBureau: return "Bureau Queued"
        }
    }

    var color: Color {
        switch self {
        case .ready: return .secondary
        case .renderingPDF: return .blue
        case .sendingSMTP: return .purple
        case .sent: return .green
        case .failed: return .red
        case .queuedBureau: return .orange
        }
    }
}

enum QSLDispatchPreviewTab: String, CaseIterable {
    case card = "QSL Card"
    case email = "Email Message"
}

struct TodayConfirmedQSLDispatchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @State private var localRecords: [QSORecordModel] = []
    @State private var selectedRecordIDs: Set<UUID> = []
    @State private var previewRecord: QSORecordModel? = nil
    @State private var previewImage: NSImage? = nil
    @State private var isRenderingPreview: Bool = false
    @State private var selectedPreviewTab: QSLDispatchPreviewTab = .card

    // Async Operations
    @State private var isEnrichingEmails: Bool = false
    @State private var enrichProgress: (current: Int, total: Int) = (0, 0)
    @State private var isDispatching: Bool = false
    @State private var cancelRequested: Bool = false
    @State private var dispatchProgress: (current: Int, total: Int) = (0, 0)
    @State private var currentDispatchCall: String = ""
    @State private var dispatchStatusMap: [UUID: DispatchItemStatus] = [:]

    // Inline Email Editing
    @State private var editingRecordID: UUID? = nil
    @State private var editingEmailText: String = ""

    // Alerts & Notifications
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false

    // Template customizer
    @State private var showTemplateEditor: Bool = false
    @AppStorage("qslCardDeliveryEmailSubject") private var emailSubject = "QSL Card for our QSO - {CALLSIGN} de {MY_CALL}"
    @AppStorage("qslCardDeliveryEmailBody") private var emailBody = """
Hello {NAME},

It was a genuine pleasure to meet you on the air. I have attached my QSL card for our confirmed contact.{QSO_DETAILS}

Thank you for the QSO. This card was prepared with YAAM.

Warm 73,
{MY_CALL}
"""

    private var todayRecords: [QSORecordModel] {
        localRecords.isEmpty ? appState.todayConfirmedRecords : localRecords
    }

    private var readyWithEmailCount: Int {
        todayRecords.filter { !$0["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var missingEmailCount: Int {
        todayRecords.filter { $0["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var alreadySentCount: Int {
        todayRecords.filter { appState.isQSLSent(record: $0) }.count
    }

    private var readyUnsentCount: Int {
        todayRecords.filter { rec in
            !rec["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !appState.isQSLSent(record: rec)
        }.count
    }

    private var selectedCount: Int {
        selectedRecordIDs.count
    }

    private var selectedReadyToSendCount: Int {
        todayRecords.filter { selectedRecordIDs.contains($0.id) && !$0["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var selectedAlreadySentCount: Int {
        todayRecords.filter { selectedRecordIDs.contains($0.id) && appState.isQSLSent(record: $0) }.count
    }

    private var sendButtonTitle: String {
        if selectedReadyToSendCount == 0 {
            return "Send QSL Cards"
        }
        let unsent = selectedReadyToSendCount - selectedAlreadySentCount
        if selectedAlreadySentCount > 0 && unsent > 0 {
            return "Send \(selectedReadyToSendCount) QSLs (\(selectedAlreadySentCount) Resend)"
        } else if selectedAlreadySentCount > 0 && unsent == 0 {
            return "Resend \(selectedReadyToSendCount) QSL Cards"
        } else {
            return "Send \(selectedReadyToSendCount) QSL Cards"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            HSplitView {
                // Left: Contact list
                contactsListPane
                    .frame(minWidth: 580, idealWidth: 680)

                // Right: Live preview pane
                previewPane
                    .frame(minWidth: 400, idealWidth: 460)
            }

            Divider()
            bottomStatusBar
        }
        .frame(minWidth: 1060, idealWidth: 1180, maxWidth: .infinity, minHeight: 680, idealHeight: 750, maxHeight: .infinity)
        .onAppear {
            initializeSelection()
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [Color.green.opacity(0.85), Color.teal.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: Color.green.opacity(0.25), radius: 4, x: 0, y: 2)

                    Image(systemName: "postcard.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Today's Confirmed QSL Dispatcher")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)

                        Text("(\(todayRecords.count) QSOs)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                    }

                    Text("Generate high-resolution 2-page personalized QSL card PDFs and dispatch via email to today's confirmed contacts.")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Station profile info pill
                stationPill

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Close Dispatcher")
            }

            // Metrics & Quick Filter bar
            HStack(spacing: 12) {
                metricChip(
                    icon: "checkmark.seal.fill",
                    color: .green,
                    title: "Confirmed Today",
                    value: "\(todayRecords.count)"
                )

                metricChip(
                    icon: "envelope.badge.fill",
                    color: .blue,
                    title: "Ready with Email",
                    value: "\(readyWithEmailCount)"
                )

                metricChip(
                    icon: "exclamationmark.triangle.fill",
                    color: missingEmailCount > 0 ? .orange : .secondary,
                    title: "Missing Email",
                    value: "\(missingEmailCount)"
                )

                metricChip(
                    icon: "clock.arrow.circlepath",
                    color: .purple,
                    title: "Already Sent",
                    value: "\(alreadySentCount)"
                )

                Spacer()

                // Action to enrich missing emails
                if missingEmailCount > 0 {
                    Button {
                        enrichMissingEmails()
                    } label: {
                        HStack(spacing: 6) {
                            if isEnrichingEmails {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Enriching \(enrichProgress.current)/\(enrichProgress.total)...")
                                    .font(.system(size: 11, weight: .semibold))
                            } else {
                                Image(systemName: "sparkle.magnifyingglass")
                                    .font(.system(size: 11))
                                Text("Enrich Missing Emails from QRZ (\(missingEmailCount))")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.14)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.35), lineWidth: 1))
                        .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .disabled(isEnrichingEmails || isDispatching)
                    .help("Query QRZ.com for all contacts missing an email address")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var stationPill: some View {
        let station = appState.qslCardStationInfoFromDefaults()
        return HStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 11))
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 1) {
                Text(station.callsign.isEmpty ? "EP2AES" : station.callsign)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)

                Text("\(station.grid.isEmpty ? "LM55" : station.grid) · \(station.powerWatts)W")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.blue.opacity(0.2), lineWidth: 1))
    }

    private func metricChip(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)

            Text(title + ":")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)

            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color(NSColor.controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.18), lineWidth: 1))
    }

    // MARK: - Contacts List Pane
    private var contactsListPane: some View {
        VStack(spacing: 0) {
            // Dedicated Sub-Toolbar for Selection Controls
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                    Text("Selected: \(selectedCount) of \(todayRecords.count) QSOs")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    if readyUnsentCount > 0 {
                        Button("Select Unsent (\(readyUnsentCount))") {
                            selectedRecordIDs = Set(todayRecords.filter {
                                !$0["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !appState.isQSLSent(record: $0)
                            }.map(\.id))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button("Select All Ready (\(readyWithEmailCount))") {
                        selectedRecordIDs = Set(todayRecords.filter { !$0["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.id))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Deselect All") {
                        selectedRecordIDs.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.7))

            Divider()

            // Table Header
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: {
                        let targetRecords = readyUnsentCount > 0
                            ? todayRecords.filter { !$0["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !appState.isQSLSent(record: $0) }
                            : todayRecords.filter { !$0["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        return !targetRecords.isEmpty && targetRecords.allSatisfy { selectedRecordIDs.contains($0.id) }
                    },
                    set: { checked in
                        let targetRecords = readyUnsentCount > 0
                            ? todayRecords.filter { !$0["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !appState.isQSLSent(record: $0) }
                            : todayRecords.filter { !$0["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        if checked {
                            selectedRecordIDs.formUnion(targetRecords.map(\.id))
                        } else {
                            selectedRecordIDs.subtract(targetRecords.map(\.id))
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .frame(width: 24)

                Text("Callsign & Country")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 150, alignment: .leading)

                Text("Band / Mode")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 85, alignment: .leading)

                Text("Time (UTC)")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 75, alignment: .leading)

                Text("Delivery Status")
                    .font(.system(size: 11, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Preview")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 36, alignment: .center)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .foregroundColor(.secondary)

            Divider()

            // List of Rows
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(todayRecords) { record in
                        contactRow(for: record)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func contactRow(for record: QSORecordModel) -> some View {
        let isSelected = selectedRecordIDs.contains(record.id)
        let isPreviewSelected = previewRecord?.id == record.id
        let call = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let email = record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines)
        let hasEmail = !email.isEmpty
        let status = dispatchStatusMap[record.id] ?? defaultStatus(for: record)
        let country = record["COUNTRY"].trimmingCharacters(in: .whitespacesAndNewlines)
        let flag = DXCCDatabase.resolve(callsign: call, country: country).flagEmoji

        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { checked in
                    if checked {
                        selectedRecordIDs.insert(record.id)
                    } else {
                        selectedRecordIDs.remove(record.id)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .frame(width: 24)

            // Callsign & Country + Flag
            VStack(alignment: .leading, spacing: 2) {
                Text(call)
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    if !flag.isEmpty {
                        Text(flag)
                            .font(.system(size: 11))
                    }
                    if !country.isEmpty {
                        Text(country)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .frame(width: 150, alignment: .leading)

            // Band & Mode badges
            HStack(spacing: 4) {
                Text(record["BAND"])
                    .font(.system(size: 9.5, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.blue.opacity(0.14)))
                    .foregroundColor(.blue)

                Text(record["MODE"])
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.purple.opacity(0.14)))
                    .foregroundColor(.purple)
            }
            .frame(width: 85, alignment: .leading)

            // Time UTC: clean and simple, no frequency decimals or RST clutter
            Text("\(formatTimeDisplay(record["TIME_ON"])) UTC")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 75, alignment: .leading)

            // Delivery Status (Clean Capsule Badges)
            HStack(spacing: 6) {
                let isAlreadySent = status == .sent || appState.isQSLSent(record: record)
                if isAlreadySent {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9.5))
                        Text("Sent")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.14)))
                    .foregroundColor(.green)
                    .help(appState.sentEmailSummary(for: record).isEmpty ? "QSL card already emailed to this contact" : appState.sentEmailSummary(for: record))

                    if isSelected {
                        Text("Resend")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.orange.opacity(0.15)))
                            .help("This contact was already emailed. Sending will send a duplicate email.")
                    }
                } else if hasEmail {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 9))
                        Text("Ready")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.blue.opacity(0.12)))
                    .foregroundColor(.blue)
                    .help(email)
                } else {
                    HStack(spacing: 5) {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8.5))
                            Text("No Email")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(Color.orange.opacity(0.14)))
                        .foregroundColor(.orange)

                        Button {
                            fetchEmailForSingleRecord(record)
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 8.5))
                                Text("QRZ")
                                    .font(.system(size: 9, weight: .bold))
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("Lookup email for \(call) on QRZ")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Preview Action Button
            Button {
                selectRecordForPreview(record)
            } label: {
                Image(systemName: isPreviewSelected ? "eye.fill" : "eye")
                    .font(.system(size: 12))
                    .foregroundColor(isPreviewSelected ? .blue : .secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .frame(width: 36, alignment: .center)
            .help("Preview personalized QSL card for \(call)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isPreviewSelected ? Color.blue.opacity(0.08) : (isSelected ? Color.blue.opacity(0.03) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectRecordForPreview(record)
        }
    }

    private func statusBadge(for status: DispatchItemStatus) -> some View {
        HStack(spacing: 3) {
            switch status {
            case .ready:
                Text("Ready")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.secondary)
            case .renderingPDF:
                ProgressView()
                    .controlSize(.mini)
                Text("Rendering")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.blue)
            case .sendingSMTP:
                ProgressView()
                    .controlSize(.mini)
                Text("Sending...")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.purple)
            case .sent:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                Text("Sent")
                    .font(.system(size: 9.5, weight: .bold))
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
                Text("Error")
                    .font(.system(size: 9.5, weight: .bold))
            case .queuedBureau:
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 9))
                Text("Bureau")
                    .font(.system(size: 9.5, weight: .bold))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(status.color.opacity(0.12)))
        .foregroundColor(status.color)
    }

    private func defaultStatus(for record: QSORecordModel) -> DispatchItemStatus {
        if appState.isQSLSent(record: record) {
            return .sent
        }
        if record["QSL_SENT"].uppercased() == "Q" {
            return .queuedBureau
        }
        return .ready
    }

    // MARK: - Preview Pane
    private var previewPane: some View {
        VStack(spacing: 0) {
            // Preview Header & Tab Picker
            HStack {
                if let record = previewRecord {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record["CALL"].uppercased())
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)

                        Text("\(record["BAND"]) · \(record["MODE"]) · \(formatTimeDisplay(record["TIME_ON"])) UTC")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Select a QSO to Preview")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Picker("", selection: $selectedPreviewTab) {
                    ForEach(QSLDispatchPreviewTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Preview Content
            if let record = previewRecord {
                if selectedPreviewTab == .card {
                    cardPreviewContent(for: record)
                } else {
                    emailPreviewContent(for: record)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 38))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Click on any contact row to inspect its personalized QSL card.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private func cardPreviewContent(for record: QSORecordModel) -> some View {
        VStack(spacing: 10) {
            ZStack {
                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .cornerRadius(6)
                        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                } else if isRenderingPreview {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Rendering personalized card...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("No preview generated.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(12)

            // Card details badge & Single Export
            HStack(spacing: 12) {
                Label("2-Page HQ PDF (Artwork + Confirmation)", systemImage: "doc.richtext")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    exportSinglePDF(for: record)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 10))
                        Text("Save PDF")
                            .font(.system(size: 10.5))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    private func emailPreviewContent(for record: QSORecordModel) -> some View {
        let call = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let email = record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines)
        let greetingName = appState.resolveFirstName(for: call, explicitName: record["NAME"])
        let myCall = appState.qslCardStationInfoFromDefaults().callsign
        let resolvedDetails = buildQSOFormattedDetails(record: record)

        let renderedSubject = emailSubject
            .replacingOccurrences(of: "{CALLSIGN}", with: call)
            .replacingOccurrences(of: "{NAME}", with: greetingName)
            .replacingOccurrences(of: "{MY_CALL}", with: myCall)

        let renderedBody = emailBody
            .replacingOccurrences(of: "{CALLSIGN}", with: call)
            .replacingOccurrences(of: "{NAME}", with: greetingName)
            .replacingOccurrences(of: "{MY_CALL}", with: myCall)
            .replacingOccurrences(of: "{QSO_DETAILS}", with: resolvedDetails)

        return VStack(alignment: .leading, spacing: 10) {
            // Recipient To: Field
            HStack(spacing: 8) {
                Text("To:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)

                if editingRecordID == record.id {
                    TextField("operator@email.com", text: $editingEmailText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .onSubmit {
                            saveEditedEmail(for: record)
                        }

                    Button("Save") {
                        saveEditedEmail(for: record)
                    }
                    .controlSize(.small)

                    Button("Cancel") {
                        editingRecordID = nil
                    }
                    .controlSize(.small)
                } else if !email.isEmpty {
                    Text(email)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)

                    Button {
                        editingRecordID = record.id
                        editingEmailText = email
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Edit email address")
                } else {
                    Text("No email address")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)

                    Button("Lookup QRZ") {
                        fetchEmailForSingleRecord(record)
                    }
                    .controlSize(.small)

                    Button("Enter Email") {
                        editingRecordID = record.id
                        editingEmailText = ""
                    }
                    .controlSize(.small)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            Divider()

            HStack(spacing: 8) {
                Text("Subject:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)
                Text(renderedSubject)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)

            Divider()

            ScrollView {
                Text(renderedBody)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }

            Divider()

            HStack {
                Image(systemName: "paperclip")
                    .foregroundColor(.blue)
                Text("\(myCall)_QSL_\(call).pdf")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.blue)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Bottom Status & Dispatch Bar
    private var bottomStatusBar: some View {
        HStack(spacing: 14) {
            // Live Dispatch Progress Bar
            if isDispatching {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dispatching \(dispatchProgress.current) of \(dispatchProgress.total): \(currentDispatchCall)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.primary)

                        ProgressView(value: Double(dispatchProgress.current), total: Double(max(1, dispatchProgress.total)))
                            .progressViewStyle(.linear)
                            .frame(width: 220)
                    }

                    Button("Stop") {
                        cancelRequested = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 6) {
                    Text("\(selectedCount) of \(todayRecords.count) selected")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.primary)

                    Text("•")
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("\(selectedReadyToSendCount) ready to email")
                        .font(.system(size: 11))
                        .foregroundColor(selectedReadyToSendCount > 0 ? .green : .secondary)
                }
            }

            Spacer()

            // Export to Folder
            Button {
                exportAllSelectedToFolder()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder.badge.plus")
                    Text("Export All PDFs...")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isDispatching || selectedCount == 0)
            .help("Render and save high-resolution QSL card PDFs for all selected contacts into a folder")

            // Queue for Bureau
            Button {
                queueSelectedForBureau()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down")
                    Text("Queue Bureau")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isDispatching || selectedCount == 0)
            .help("Mark selected QSOs as queued for Bureau dispatch (QSL_SENT = 'Q')")

            // Already sent warning indicator
            if selectedAlreadySentCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text("\(selectedAlreadySentCount) already sent")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.12)))
                .help("\(selectedAlreadySentCount) of the selected contacts have already been sent a QSL card email. You will be prompted before sending duplicates.")
            }

            // Main Dispatch Button
            Button {
                startBatchDispatch()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 11))
                    Text(sendButtonTitle)
                        .font(.system(size: 12, weight: .bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(selectedAlreadySentCount > 0 && selectedReadyToSendCount == selectedAlreadySentCount ? .orange : .green)
            .disabled(isDispatching || selectedReadyToSendCount == 0)
            .help("Generate and send personalized QSL card PDFs via SMTP to all selected contacts with an email address")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Actions & Business Logic
    private func initializeSelection() {
        localRecords = appState.todayConfirmedRecords
        // Only select contacts that have an email AND have NOT yet been sent a QSL
        let unsentWithEmail = localRecords.filter { rec in
            let hasEmail = !rec["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasEmail && !appState.isQSLSent(record: rec)
        }
        selectedRecordIDs = Set(unsentWithEmail.map(\.id))

        // Set first record as preview: prefer the first unsent record if available
        if let first = unsentWithEmail.first ?? localRecords.first {
            selectRecordForPreview(first)
        }
    }

    private func selectRecordForPreview(_ record: QSORecordModel) {
        previewRecord = record
        let station = appState.qslCardStationInfoFromDefaults()
        // QSLCardRenderer.render executes instantaneously on the main thread
        let img = QSLCardRenderer.render(record: record, station: station)
        self.previewImage = img
        self.isRenderingPreview = false
    }

    private func formatTimeDisplay(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines).filter(\.isNumber)
        if clean.count >= 4 {
            let h = clean.prefix(2)
            let m = clean.dropFirst(2).prefix(2)
            return "\(h):\(m)"
        }
        return raw
    }

    private func saveEditedEmail(for record: QSORecordModel) {
        let clean = editingEmailText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = appState.qsoRecords.firstIndex(where: { $0.id == record.id }) {
            appState.qsoRecords[idx].fields["EMAIL"] = clean
            appState.autoSaveActiveWorkspace()
        }
        if let lIdx = localRecords.firstIndex(where: { $0.id == record.id }) {
            localRecords[lIdx].fields["EMAIL"] = clean
            if !clean.isEmpty {
                selectedRecordIDs.insert(record.id)
            }
        }
        editingRecordID = nil
    }

    private func fetchEmailForSingleRecord(_ record: QSORecordModel) {
        let call = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !call.isEmpty else { return }

        Task {
            if let email = await appState.fetchAndStoreQRZEmail(for: call) {
                await MainActor.run {
                    if let lIdx = self.localRecords.firstIndex(where: { $0.id == record.id }) {
                        self.localRecords[lIdx].fields["EMAIL"] = email
                        if !self.appState.isQSLSent(record: record) {
                            self.selectedRecordIDs.insert(record.id)
                        }
                    }
                }
            }
        }
    }

    private func enrichMissingEmails() {
        isEnrichingEmails = true
        let missing = todayRecords.filter { $0["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        enrichProgress = (0, missing.count)

        Task {
            let count = await appState.enrichMissingEmailsForTodayConfirmed(records: localRecords) { cur, tot in
                DispatchQueue.main.async {
                    self.enrichProgress = (cur, tot)
                }
            }

            DispatchQueue.main.async {
                self.isEnrichingEmails = false
                self.localRecords = self.appState.todayConfirmedRecords
                // Automatically check contacts that now have emails AND are not already sent
                let withEmailUnsent = self.localRecords.filter {
                    !$0["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !self.appState.isQSLSent(record: $0)
                }
                self.selectedRecordIDs.formUnion(withEmailUnsent.map(\.id))
                self.alertTitle = "Email Enrichment Complete"
                self.alertMessage = "Found and updated \(count) email address(es) from QRZ/HamQTH."
                self.showAlert = true
            }
        }
    }

    private func startBatchDispatch() {
        let recordsToDispatch = todayRecords.filter {
            selectedRecordIDs.contains($0.id) &&
            !$0["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        guard !recordsToDispatch.isEmpty else { return }

        // Validate SMTP
        let user = UserDefaults.standard.string(forKey: "smtpUser") ?? ""
        let pass = CredentialVault.value(for: .smtpPassword)
        if user.isEmpty || pass.isEmpty {
            alertTitle = "SMTP Configuration Required"
            alertMessage = "Please enter your SMTP Username and Password in Settings > SMTP before sending QSL cards."
            showAlert = true
            return
        }

        // Duplicate Email Verification
        var finalRecordsToSend = recordsToDispatch
        let alreadySentList = recordsToDispatch.filter { appState.isQSLSent(record: $0) }

        if !alreadySentList.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Duplicate Email Warning"
            alert.alertStyle = .warning

            let dupCount = alreadySentList.count
            let totalCount = recordsToDispatch.count
            let unsentCount = totalCount - dupCount

            let callsignList = alreadySentList.prefix(6).map { rec in
                let call = rec["CALL"].uppercased()
                let summary = appState.sentEmailSummary(for: rec)
                return "• \(call): \(summary.isEmpty ? "Already Sent" : summary)"
            }.joined(separator: "\n") + (dupCount > 6 ? "\n• ...and \(dupCount - 6) more" : "")

            if unsentCount > 0 {
                alert.informativeText = """
                \(dupCount) of the \(totalCount) selected contacts have ALREADY received a QSL card email:

                \(callsignList)

                To prevent sending duplicate emails, you can choose to send only to the \(unsentCount) new contact(s), or resend to all.
                """
                alert.addButton(withTitle: "Send Only New Contacts (\(unsentCount))")
                alert.addButton(withTitle: "Resend to All (\(totalCount))")
                alert.addButton(withTitle: "Cancel")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    finalRecordsToSend = recordsToDispatch.filter { !appState.isQSLSent(record: $0) }
                } else if response == .alertSecondButtonReturn {
                    finalRecordsToSend = recordsToDispatch
                } else {
                    return
                }
            } else {
                alert.informativeText = """
                All \(dupCount) selected contact(s) have ALREADY received a QSL card email:

                \(callsignList)

                Are you sure you want to resend duplicate QSL card emails to all \(dupCount) contact(s)?
                """
                alert.addButton(withTitle: "Resend Duplicate Emails (\(dupCount))")
                alert.addButton(withTitle: "Cancel")

                let response = alert.runModal()
                if response != .alertFirstButtonReturn {
                    return
                }
                finalRecordsToSend = recordsToDispatch
            }
        }

        guard !finalRecordsToSend.isEmpty else { return }

        isDispatching = true
        cancelRequested = false
        dispatchProgress = (0, finalRecordsToSend.count)

        let station = appState.qslCardStationInfoFromDefaults()

        DispatchQueue.global(qos: .userInitiated).async {
            var sentCount = 0
            var failedCount = 0

            for (index, record) in finalRecordsToSend.enumerated() {
                if self.cancelRequested { break }

                let call = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let recipientEmail = record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines)

                DispatchQueue.main.async {
                    self.dispatchProgress = (index + 1, finalRecordsToSend.count)
                    self.currentDispatchCall = call
                    self.dispatchStatusMap[record.id] = .renderingPDF
                }

                // 1. Render PDF
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("pdf")

                var pdfData: Data? = nil
                do {
                    try QSLCardRenderer.exportPDF(record: record, station: station, to: tempURL)
                    pdfData = try Data(contentsOf: tempURL)
                    try? FileManager.default.removeItem(at: tempURL)
                } catch {
                    try? FileManager.default.removeItem(at: tempURL)
                    DispatchQueue.main.async {
                        self.dispatchStatusMap[record.id] = .failed(error.localizedDescription)
                    }
                    failedCount += 1
                    continue
                }

                guard let attachmentData = pdfData else {
                    DispatchQueue.main.async {
                        self.dispatchStatusMap[record.id] = .failed("Could not read rendered PDF")
                    }
                    failedCount += 1
                    continue
                }

                DispatchQueue.main.async {
                    self.dispatchStatusMap[record.id] = .sendingSMTP
                }

                // 2. Build email body & subject
                let greetingName = self.appState.resolveFirstName(for: call, explicitName: record["NAME"])
                let resolvedDetails = self.buildQSOFormattedDetails(record: record)
                let sub = self.emailSubject
                    .replacingOccurrences(of: "{CALLSIGN}", with: call)
                    .replacingOccurrences(of: "{NAME}", with: greetingName)
                    .replacingOccurrences(of: "{MY_CALL}", with: station.callsign)

                let body = self.emailBody
                    .replacingOccurrences(of: "{CALLSIGN}", with: call)
                    .replacingOccurrences(of: "{NAME}", with: greetingName)
                    .replacingOccurrences(of: "{MY_CALL}", with: station.callsign)
                    .replacingOccurrences(of: "{QSO_DETAILS}", with: resolvedDetails)

                let attachmentName = "\(QSLCardRenderer.cleanFileComponent(station.callsign))_QSL_\(QSLCardRenderer.cleanFileComponent(call)).pdf"

                // 3. Send via SMTP
                let semaphore = DispatchSemaphore(value: 0)
                var successResult = false

                self.appState.sendEmail(
                    to: recipientEmail,
                    subject: sub,
                    body: body,
                    attachmentData: attachmentData,
                    attachmentName: attachmentName,
                    playSound: false
                ) { ok, _ in
                    successResult = ok
                    semaphore.signal()
                }

                semaphore.wait()

                DispatchQueue.main.async {
                    if successResult {
                        sentCount += 1
                        self.dispatchStatusMap[record.id] = .sent
                        self.appState.markRecordAsQSLSent(id: record.id, via: "E", autoSave: false)
                        self.appState.recordEmailHistory(callsign: call, email: recipientEmail, subject: sub, status: "Sent")
                        if let lIdx = self.localRecords.firstIndex(where: { $0.id == record.id }) {
                            self.localRecords[lIdx].fields["QSL_SENT"] = "Y"
                            self.localRecords[lIdx].fields["QSLSDATE"] = AppState.adifDateFormatter.string(from: Date())
                            self.localRecords[lIdx].fields["QSL_SENT_VIA"] = "E"
                            self.localRecords[lIdx].fields["APP_YAAM_EMAIL_SENT_DATE"] = AppState.adifDateFormatter.string(from: Date())
                        }
                    } else {
                        failedCount += 1
                        self.dispatchStatusMap[record.id] = .failed("SMTP delivery failed")
                        self.appState.recordEmailHistory(callsign: call, email: recipientEmail, subject: sub, status: "Failed")
                    }
                }

                // Polite throttle between emails to respect SMTP servers
                Thread.sleep(forTimeInterval: 1.0)
            }

            DispatchQueue.main.async {
                self.isDispatching = false
                // Single autoSave and notification at the end of the batch!
                self.appState.autoSaveActiveWorkspace()
                self.appState.objectWillChange.send()

                self.appState.playActivitySound(failedCount == 0 ? .success : .failure)
                self.alertTitle = "Dispatch Complete 🎉"
                self.alertMessage = "\(sentCount) QSL card email(s) successfully delivered via SMTP. \(failedCount > 0 ? "\(failedCount) failed." : "")"
            }
        }
    }

    private func exportAllSelectedToFolder() {
        let selectedRecords = todayRecords.filter { selectedRecordIDs.contains($0.id) }
        guard !selectedRecords.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export QSL PDFs"
        panel.message = "Select a folder to save \(selectedRecords.count) QSL card PDF(s):"

        guard panel.runModal() == .OK, let folderURL = panel.url else { return }

        do {
            let exported = try appState.exportTodayConfirmedQSLPDFs(records: selectedRecords, to: folderURL)
            alertTitle = "Export Complete 📁"
            alertMessage = "Successfully exported \(exported.count) QSL card PDF(s) to:\n\(folderURL.path)"
            showAlert = true
            NSWorkspace.shared.open(folderURL)
        } catch {
            alertTitle = "Export Failed"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func exportSinglePDF(for record: QSORecordModel) {
        let panel = NSSavePanel()
        let station = appState.qslCardStationInfoFromDefaults()
        let cleanCall = QSLCardRenderer.cleanFileComponent(record["CALL"])
        panel.nameFieldStringValue = "\(station.callsign)_QSL_\(cleanCall).pdf"
        panel.allowedContentTypes = [.pdf]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try QSLCardRenderer.exportPDF(record: record, station: station, to: url)
            alertTitle = "Saved Successfully"
            alertMessage = "QSL Card PDF saved to \(url.lastPathComponent)."
            showAlert = true
        } catch {
            alertTitle = "Save Failed"
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func queueSelectedForBureau() {
        let ids = selectedRecordIDs
        guard !ids.isEmpty else { return }

        appState.queueRecordsForBureau(ids: ids)
        for id in ids {
            dispatchStatusMap[id] = .queuedBureau
        }

        alertTitle = "Queued for Bureau"
        alertMessage = "\(ids.count) QSO(s) marked for Bureau dispatch (QSL_SENT = 'Q')."
        showAlert = true
    }

    private func buildQSOFormattedDetails(record: QSORecordModel) -> String {
        var items: [String] = []
        let rawDate = record["QSO_DATE"].trimmingCharacters(in: .whitespacesAndNewlines)
        if rawDate.count == 8 {
            let y = rawDate.prefix(4)
            let m = rawDate.dropFirst(4).prefix(2)
            let d = rawDate.suffix(2)
            items.append("- Date: \(y)-\(m)-\(d)")
        }

        let time = formatTimeDisplay(record["TIME_ON"])
        if !time.isEmpty { items.append("- Time: \(time) UTC") }

        let band = record["BAND"].trimmingCharacters(in: .whitespacesAndNewlines)
        if !band.isEmpty { items.append("- Band: \(band)") }

        let mode = record["MODE"].trimmingCharacters(in: .whitespacesAndNewlines)
        if !mode.isEmpty { items.append("- Mode: \(mode)") }

        let freq = record["FREQ"].trimmingCharacters(in: .whitespacesAndNewlines)
        if !freq.isEmpty { items.append("- Freq: \(freq) MHz") }

        let rstSent = record["RST_SENT"].trimmingCharacters(in: .whitespacesAndNewlines)
        let rstRcvd = record["RST_RCVD"].trimmingCharacters(in: .whitespacesAndNewlines)
        let rst = [rstSent, rstRcvd].filter { !$0.isEmpty }.joined(separator: "/")
        if !rst.isEmpty { items.append("- RST (Sent/Rcvd): \(rst)") }

        return items.isEmpty ? "" : "\n\nQSO Details:\n" + items.joined(separator: "\n")
    }
}
