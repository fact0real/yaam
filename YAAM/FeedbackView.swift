//
//  FeedbackView.swift
//  YAAM
//
//  Created for YAAM Community & User Feedback System.
//

import AppKit
import SwiftUI

// MARK: - Feedback Models
enum FeedbackCategory: String, CaseIterable, Identifiable, Codable {
    case featureRequest = "Feature Request"
    case bugReport = "Bug / Shortcoming"
    case dxData = "DX & News Data"
    case general = "General Suggestion"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .featureRequest: return "💡 Feature Request"
        case .bugReport: return "🪲 Bug / Issue"
        case .dxData: return "📡 DX & News Data"
        case .general: return "💬 General Suggestion"
        }
    }

    var shortTitle: String {
        switch self {
        case .featureRequest: return "Feature"
        case .bugReport: return "Bug"
        case .dxData: return "DX Data"
        case .general: return "Suggestion"
        }
    }

    var icon: String {
        switch self {
        case .featureRequest: return "sparkles"
        case .bugReport: return "ant.fill"
        case .dxData: return "dot.radiowaves.left.and.right"
        case .general: return "bubble.left.and.bubble.right.fill"
        }
    }

    var color: Color {
        switch self {
        case .featureRequest: return .purple
        case .bugReport: return .red
        case .dxData: return .blue
        case .general: return .green
        }
    }
}

enum FeedbackPriority: String, CaseIterable, Identifiable, Codable {
    case normal = "Normal"
    case high = "High"
    case urgent = "Urgent"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .normal: return "flag"
        case .high: return "flag.fill"
        case .urgent: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .normal: return .secondary
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

struct SavedFeedbackItem: Codable, Identifiable {
    let id: UUID
    let date: Date
    let category: FeedbackCategory
    let priority: FeedbackPriority
    let title: String
    let description: String
    let callsign: String
    let email: String

    var displayDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Feedback View
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var selectedCategory: FeedbackCategory = .featureRequest
    @State private var selectedPriority: FeedbackPriority = .normal
    @State private var title: String = ""
    @State private var descriptionText: String = ""
    @State private var callsignText: String = ""
    @AppStorage("feedbackUserEmail") private var userEmail: String = ""
    @State private var includeDiagnostics: Bool = true
    @State private var selectedTab: Int = 0 // 0: Form, 1: History
    @State private var savedHistory: [SavedFeedbackItem] = []
    @State private var showCopiedAlert: Bool = false
    @State private var showSubmittedAlert: Bool = false
    @State private var submissionMethodMessage: String = ""
    @State private var isSendingEmail: Bool = false
    @State private var showSMTPSettingsSheet: Bool = false
    @State private var emailErrorLog: String = ""
    @State private var showEmailErrorAlert: Bool = false
    @State private var showNoSMTPAlert: Bool = false

    private let feedbackRecipientEmail = "ep2aes@asis.sh"
    private let feedbackRepoURL = "https://github.com/fact0real/yaam"
    private static let historyStorageKey = "yaamSavedFeedbackHistory_v1"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar

            Divider()

            // Sub Navigation: New Feedback vs History
            Picker("View", selection: $selectedTab) {
                Label("New Feedback", systemImage: "square.and.pencil").tag(0)
                Label("History (\(savedHistory.count))", systemImage: "clock.arrow.circlepath").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            Divider()

            if selectedTab == 0 {
                feedbackForm
            } else {
                feedbackHistoryView
            }
        }
        .frame(minWidth: 680, idealWidth: 780, maxWidth: 900, minHeight: 600, idealHeight: 720, maxHeight: 850)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadSavedHistory()
            if callsignText.isEmpty {
                callsignText = appState.activeStationProfile?.normalizedCallsign ?? appState.currentStationCallsign
            }
            if userEmail.isEmpty && !appState.configuredSMTPEmail.isEmpty {
                userEmail = appState.configuredSMTPEmail
            }
        }
        .alert("Feedback Copied to Clipboard", isPresented: $showCopiedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your formatted feedback and system diagnostics were copied to the clipboard. You can now paste and send it anywhere!")
        }
        .alert("Feedback Sent", isPresented: $showSubmittedAlert) {
            Button("Done", role: .cancel) {
                dismiss()
            }
        } message: {
            Text(submissionMethodMessage)
        }
        .alert("SMTP Delivery Failed", isPresented: $showEmailErrorAlert) {
            Button("Open Default Mail Client") {
                openDefaultMailClient()
            }
            Button("Copy Markdown") {
                copyFormattedReport()
            }
            Button("Dismiss", role: .cancel) { }
        } message: {
            Text("The email could not be sent through your SMTP server:\n\n\(emailErrorLog)\n\nYou can open your default mail client or copy the markdown feedback.")
        }
        .alert("SMTP Not Configured", isPresented: $showNoSMTPAlert) {
            Button("Configure SMTP...") {
                showSMTPSettingsSheet = true
            }
            Button("Open Default Mail App") {
                openDefaultMailClient()
            }
            Button("Copy Markdown") {
                copyFormattedReport()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have not configured an SMTP email server in YAAM Settings yet.\n\nTo send directly from YAAM, configure your SMTP server (e.g. Gmail / Outlook / Custom SMTP) in Settings. Otherwise, YAAM can open your default macOS Mail client or copy the report.")
        }
        .sheet(isPresented: $showSMTPSettingsSheet) {
            SMTPSettingsView(embeddedInSettings: false)
                .onDisappear {
                    if userEmail.isEmpty && !appState.configuredSMTPEmail.isEmpty {
                        userEmail = appState.configuredSMTPEmail
                    }
                }
        }
    }

    // MARK: - Header
    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: "bubble.left.and.exclamationmark.bubble.right.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("YAAM Feedback & Suggestions")
                    .font(.headline)
                Text("Share feature requests, report shortcomings/bugs, or submit DX news feedback anytime.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .controlSize(.regular)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Form View
    private var feedbackForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Category Selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category")
                        .font(.subheadline.bold())

                    HStack(spacing: 8) {
                        ForEach(FeedbackCategory.allCases) { cat in
                            Button {
                                selectedCategory = cat
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: cat.icon)
                                    Text(cat.shortTitle)
                                }
                                .font(.system(size: 12, weight: selectedCategory == cat ? .semibold : .regular))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    selectedCategory == cat ? cat.color.opacity(0.18) : Color(NSColor.controlBackgroundColor),
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(selectedCategory == cat ? cat.color : Color.secondary.opacity(0.3), lineWidth: selectedCategory == cat ? 1.5 : 0.8)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 2. Priority & Callsign Row
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Priority")
                            .font(.subheadline.bold())

                        Picker("", selection: $selectedPriority) {
                            ForEach(FeedbackPriority.allCases) { pri in
                                Label(pri.rawValue, systemImage: pri.icon)
                                    .foregroundColor(pri.color)
                                    .tag(pri)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 250)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your Callsign")
                            .font(.subheadline.bold())

                        TextField("Callsign (e.g. EP2AES)", text: $callsignText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your Email (Optional)")
                            .font(.subheadline.bold())

                        TextField("operator@example.com", text: $userEmail)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                // 3. Title / Subject
                VStack(alignment: .leading, spacing: 5) {
                    Text("Title / Summary")
                        .font(.subheadline.bold())

                    TextField("Brief summary of your request or issue...", text: $title)
                        .textFieldStyle(.roundedBorder)
                }

                // 4. Description TextEditor
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Details")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("Please specify desired behavior, steps to reproduce, or suggestions.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $descriptionText)
                            .font(.system(size: 13))
                            .frame(minHeight: 140)
                            .padding(4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                            )

                        if descriptionText.isEmpty {
                            Text("Describe your proposal, shortcoming, or bug in detail...")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary.opacity(0.6))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }
                    }
                }

                // 5. System Diagnostics Box (collapsible / toggleable)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Include system & station diagnostics (helps solve issues faster)", isOn: $includeDiagnostics)
                        .font(.subheadline)

                    if includeDiagnostics {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Diagnostics Snapshot (No credentials or passwords included):")
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)

                            Text(diagnosticSummary)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(12)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                // 5.5 Email / SMTP Server Status Indicator
                HStack(spacing: 6) {
                    if appState.isSMTPConfigured {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 13))
                        Text("SMTP Server Ready: Direct delivery via **\(appState.configuredSMTPEmail)**")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 13))
                        Text("No SMTP server configured in Settings.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Configure SMTP...") {
                            showSMTPSettingsSheet = true
                        }
                        .font(.caption.bold())
                        .buttonStyle(.link)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)

                // 6. Action Buttons Bar
                HStack(spacing: 12) {
                    // Send via Email / SMTP
                    Button {
                        sendViaEmail()
                    } label: {
                        HStack(spacing: 6) {
                            if isSendingEmail {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Sending SMTP...")
                            } else {
                                Label(appState.isSMTPConfigured ? "Send via SMTP" : "Send via Email",
                                      systemImage: appState.isSMTPConfigured ? "paperplane.fill" : "envelope.fill")
                            }
                        }
                        .frame(minWidth: 140)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSendingEmail)

                    // Submit to GitHub Issues
                    Button {
                        submitViaGitHub()
                    } label: {
                        Label("Open GitHub Issue", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    // Copy formatted markdown to clipboard
                    Button {
                        copyFormattedReport()
                    } label: {
                        Label("Copy Markdown", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Spacer()

                    // Reset form
                    Button("Clear") {
                        title = ""
                        descriptionText = ""
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
    }

    // MARK: - History View
    private var feedbackHistoryView: some View {
        Group {
            if savedHistory.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No feedback submitted yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("When you submit feedback or copy reports, they will be archived here for your reference.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(savedHistory) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label(item.category.rawValue, systemImage: item.category.icon)
                                    .font(.caption.bold())
                                    .foregroundColor(item.category.color)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(item.category.color.opacity(0.12), in: Capsule())

                                Label(item.priority.rawValue, systemImage: item.priority.icon)
                                    .font(.caption)
                                    .foregroundColor(item.priority.color)

                                Spacer()

                                Text(item.displayDate)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Text(item.title)
                                .font(.subheadline.bold())

                            if !item.description.isEmpty {
                                Text(item.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }

                            HStack {
                                if !item.callsign.isEmpty {
                                    Text("Operator: \(item.callsign)")
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(item.description, forType: .string)
                                    showCopiedAlert = true
                                }
                                .buttonStyle(.borderless)
                                .font(.caption2)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .onDelete(perform: deleteHistoryItems)
                }
            }
        }
    }

    // MARK: - Helpers & Diagnostics
    private var diagnosticSummary: String {
        let appVer = appState.currentVersion
        let osVer = ProcessInfo.processInfo.operatingSystemVersionString
        let qsoCount = appState.qsoRecords.count
        let activeCall = appState.activeStationProfile?.normalizedCallsign ?? "None"
        let activeGrid = appState.activeStationProfile?.grid ?? "None"
        let clusterConnected = appState.dxClusterClient.state.isConnected ? "Connected" : "Disconnected"
        let rigConnected = appState.rigControlClient.state.isConnected ? "Connected" : "Disconnected"

        return """
        • YAAM Version: \(appVer) | macOS: \(osVer)
        • Active Profile: \(activeCall) (\(activeGrid)) | Total Logs: \(qsoCount) QSOs
        • DX Cluster: \(clusterConnected) | Radio Rig: \(rigConnected)
        • DXpeditions Cached: \(appState.dxpeditionEntries.count) | DX News Articles: \(appState.dxNewsArticles.count)
        """
    }

    private func formatMarkdownReport() -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDesc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let opCall = callsignText.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        # [\(selectedCategory.rawValue)] \(cleanTitle)

        **Category**: \(selectedCategory.rawValue)
        **Priority**: \(selectedPriority.rawValue)
        **Operator Callsign**: \(opCall.isEmpty ? "Not specified" : opCall)
        **Contact Email**: \(userEmail.isEmpty ? "Not provided" : userEmail)
        **Date (UTC)**: \(ISO8601DateFormatter().string(from: Date()))

        ## Description
        \(cleanDesc.isEmpty ? "No detailed description provided." : cleanDesc)

        \(includeDiagnostics ? "\n## System Diagnostics\n```text\n\(diagnosticSummary)\n```" : "")
        """
    }

    private func saveToHistory() {
        let item = SavedFeedbackItem(
            id: UUID(),
            date: Date(),
            category: selectedCategory,
            priority: selectedPriority,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
            callsign: callsignText.trimmingCharacters(in: .whitespacesAndNewlines),
            email: userEmail
        )
        savedHistory.insert(item, at: 0)
        if savedHistory.count > 50 { savedHistory = Array(savedHistory.prefix(50)) }
        if let data = try? JSONEncoder().encode(savedHistory) {
            UserDefaults.standard.set(data, forKey: Self.historyStorageKey)
        }
    }

    private func loadSavedHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyStorageKey),
              let items = try? JSONDecoder().decode([SavedFeedbackItem].self, from: data)
        else { return }
        savedHistory = items
    }

    private func deleteHistoryItems(at offsets: IndexSet) {
        savedHistory.remove(atOffsets: offsets)
        if let data = try? JSONEncoder().encode(savedHistory) {
            UserDefaults.standard.set(data, forKey: Self.historyStorageKey)
        }
    }

    // MARK: - Submission Implementations
    private func sendViaEmail() {
        if appState.isSMTPConfigured {
            sendDirectViaSMTP()
        } else {
            showNoSMTPAlert = true
        }
    }

    private func sendDirectViaSMTP() {
        guard !isSendingEmail else { return }
        isSendingEmail = true

        let report = formatMarkdownReport()
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = "[YAAM Feedback] [\(selectedCategory.shortTitle)] \(cleanTitle)"
        let replyAddress = userEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        let opCall = callsignText.trimmingCharacters(in: .whitespacesAndNewlines)

        appState.sendEmail(
            to: feedbackRecipientEmail,
            subject: subject,
            body: report,
            attachmentData: nil,
            attachmentName: nil,
            replyTo: replyAddress.isEmpty ? nil : replyAddress,
            callsign: opCall.isEmpty ? "FEEDBACK" : opCall,
            playSound: true
        ) { success, log in
            DispatchQueue.main.async {
                self.isSendingEmail = false
                if success {
                    self.saveToHistory()
                    let sender = self.appState.configuredSMTPEmail
                    self.submissionMethodMessage = "Your feedback was successfully delivered directly to the developer (\(self.feedbackRecipientEmail)) via your configured SMTP account (\(sender)). Thank you for supporting YAAM!"
                    self.showSubmittedAlert = true
                } else {
                    self.emailErrorLog = log
                    self.showEmailErrorAlert = true
                }
            }
        }
    }

    private func openDefaultMailClient() {
        saveToHistory()
        let report = formatMarkdownReport()
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = "[YAAM Feedback] [\(selectedCategory.shortTitle)] \(cleanTitle)"

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackRecipientEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: report)
        ]

        if let mailtoURL = components.url {
            NSWorkspace.shared.open(mailtoURL)
            submissionMethodMessage = "Your default macOS mail app has been opened with your pre-formatted feedback. Please click 'Send' in your mail app to transmit your feedback to \(feedbackRecipientEmail)."
            showSubmittedAlert = true
        } else {
            copyFormattedReport()
        }
    }

    private func submitViaGitHub() {
        saveToHistory()
        let report = formatMarkdownReport()
        let cleanTitle = "[\(selectedCategory.shortTitle)] \(title)"

        var urlComponents = URLComponents(string: "\(feedbackRepoURL)/issues/new")
        urlComponents?.queryItems = [
            URLQueryItem(name: "title", value: cleanTitle),
            URLQueryItem(name: "body", value: report)
        ]

        if let url = urlComponents?.url {
            NSWorkspace.shared.open(url)
            submissionMethodMessage = "GitHub has been opened in your browser to submit an issue. Thank you for contributing to YAAM!"
            showSubmittedAlert = true
        }
    }

    private func copyFormattedReport() {
        let report = formatMarkdownReport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        showCopiedAlert = true
    }
}
