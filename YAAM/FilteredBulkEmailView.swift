//
//  FilteredBulkEmailView.swift
//  YAAM
//
//  Created for YAAM Amateur Radio Logbook.
//

import SwiftUI
import AppKit

enum BulkEmailStatus: Equatable {
    case ready
    case sending
    case sent
    case failed(String)

    var label: String {
        switch self {
        case .ready: return "Ready"
        case .sending: return "Sending..."
        case .sent: return "Sent ✅"
        case .failed(let err): return "Failed: \(err)"
        }
    }

    var color: Color {
        switch self {
        case .ready: return .blue
        case .sending: return .purple
        case .sent: return .green
        case .failed: return .red
        }
    }
}

enum BulkEmailRecipientSource: String, CaseIterable {
    case filtered = "Current Filter"
    case selected = "Selected in Log"
    case allWithEmail = "All Contacts"
}

struct FilteredBulkEmailRecipient: Identifiable, Hashable {
    let id: UUID
    let callsign: String
    let name: String
    let email: String
    let state: String
    let country: String
    let grid: String
    let qsoCount: Int
    let lastBand: String
    let lastMode: String
    let lastDate: String
    let isConfirmed: Bool
    let alreadyEmailed: Bool
    let lastEmailSummary: String
    let qso: QSORecordModel?
    let allRecords: [QSORecordModel]

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: FilteredBulkEmailRecipient, rhs: FilteredBulkEmailRecipient) -> Bool {
        lhs.id == rhs.id
    }
}

enum FilteredBulkEmailRightTab: String, CaseIterable {
    case editor = "Template Editor"
    case preview = "Live Preview"
}

struct FilteredBulkEmailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    // Source selection
    @State private var selectedSource: BulkEmailRecipientSource = .filtered
    @State private var recipientsList: [FilteredBulkEmailRecipient] = []
    @State private var selectedRecipientIDs: Set<UUID> = []
    @State private var previewRecipientID: UUID? = nil
    @State private var searchText: String = ""

    // Template state & Store
    @ObservedObject private var templateStore = BulkEmailTemplateStore.shared
    @State private var selectedTemplateID: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    @State private var showSaveTemplateSheet: Bool = false
    @AppStorage("smtpUser") private var smtpUser = ""
    @AppStorage("filteredBulkEmailSubject") private var emailSubject: String = ""
    @AppStorage("filteredBulkEmailBody") private var emailBody: String = ""
    @State private var selectedRightTab: FilteredBulkEmailRightTab = .editor
    @State private var markAsQSLSent: Bool = false

    // Dispatch status
    @State private var isSending: Bool = false
    @State private var cancelRequested: Bool = false
    @State private var sendProgress: (current: Int, total: Int) = (0, 0)
    @State private var currentSendingCall: String = ""
    @State private var recipientStatusMap: [UUID: BulkEmailStatus] = [:]

    // Alerts
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showAlert: Bool = false

    // MARK: - Computed Properties

    private var resolvedMyCallsign: String {
        let active = appState.currentStationCallsign
        if !active.isEmpty && active != "DEFAULT" { return active.uppercased() }
        if let profCall = appState.activeStationProfile?.callsign, !profCall.isEmpty { return profCall.uppercased() }
        if let first = appState.qsoRecords.first(where: { !$0["STATION_CALLSIGN"].isEmpty })?["STATION_CALLSIGN"] {
            return first.uppercased()
        }
        return TransmitIdentity.callsignPreviewToken
    }

    private var resolvedMyName: String {
        if let profName = appState.activeStationProfile?.name, !profName.isEmpty { return profName }
        return ""
    }

    private var displayedRecipients: [FilteredBulkEmailRecipient] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return recipientsList
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return recipientsList.filter {
            $0.callsign.lowercased().contains(q) ||
            $0.name.lowercased().contains(q) ||
            $0.email.lowercased().contains(q) ||
            $0.state.lowercased().contains(q) ||
            $0.country.lowercased().contains(q)
        }
    }

    private var activePreviewRecipient: FilteredBulkEmailRecipient? {
        if let id = previewRecipientID, let found = recipientsList.first(where: { $0.id == id }) {
            return found
        }
        return displayedRecipients.first ?? recipientsList.first
    }

    private var selectedCount: Int {
        recipientsList.filter { selectedRecipientIDs.contains($0.id) }.count
    }

    private var unsentSelectedCount: Int {
        recipientsList.filter { selectedRecipientIDs.contains($0.id) && !$0.alreadyEmailed }.count
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            HSplitView {
                leftRecipientsPane
                    .frame(minWidth: 360, idealWidth: 420, maxWidth: 520)

                rightContentPane
                    .frame(minWidth: 460, idealWidth: 620, maxWidth: .infinity)
            }

            Divider()
            bottomStatusBar
        }
        .frame(minWidth: 880, idealWidth: 1040, maxWidth: .infinity, minHeight: 620, idealHeight: 740, maxHeight: .infinity)
        .resizablePresentation(minWidth: 880, minHeight: 620)
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .onAppear {
            if let current = currentTemplate {
                if emailSubject.isEmpty {
                    emailSubject = current.subject
                }
                if emailBody.isEmpty {
                    emailBody = current.body
                }
            }
            if appState.selectedRecordIDs.count > 1 && !appState.filterCriteria.isActive {
                selectedSource = .selected
            } else {
                selectedSource = .filtered
            }
            refreshRecipients()
        }
        .sheet(isPresented: $showSaveTemplateSheet) {
            SaveBulkEmailTemplateSheet(
                templateStore: templateStore,
                subject: emailSubject,
                bodyText: emailBody,
                linkCurrentFilter: appState.filterCriteria.isActive,
                onSaved: { newTmpl in
                    selectedTemplateID = newTmpl.id
                    emailSubject = newTmpl.subject
                    emailBody = newTmpl.body
                    alertTitle = "Template Saved"
                    alertMessage = "Template '\(newTmpl.name)' has been saved successfully."
                    showAlert = true
                }
            )
            .environmentObject(appState)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 20))
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Bulk Email Dispatcher")
                    .font(.system(size: 15, weight: .bold))

                HStack(spacing: 6) {
                    Text(sourceSubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    if appState.filterCriteria.isActive && selectedSource == .filtered {
                        Text("Active Filter Applied")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.orange.opacity(0.15)))
                    }
                }
            }

            Spacer(minLength: 16)

            Picker("Source:", selection: $selectedSource) {
                ForEach(BulkEmailRecipientSource.allCases, id: \.self) { src in
                    Text(src.rawValue).tag(src)
                }
            }
            .pickerStyle(.segmented)
            .frame(minWidth: 340, idealWidth: 380)
            .disabled(isSending)
            .onChange(of: selectedSource) { _, _ in
                refreshRecipients()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var sourceSubtitle: String {
        switch selectedSource {
        case .filtered:
            return "Targeting contacts matching current logbook filter (\(recipientsList.count) unique operators)"
        case .selected:
            return "Targeting records selected in log table (\(recipientsList.count) unique operators)"
        case .allWithEmail:
            return "Targeting all contacts with valid email addresses (\(recipientsList.count) unique operators)"
        }
    }

    // MARK: - Left Recipients Pane

    private var leftRecipientsPane: some View {
        VStack(spacing: 0) {
            // Search and Selection Controls
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search callsign, name, state, email...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                HStack(spacing: 6) {
                    Button("All (\(recipientsList.count))") {
                        selectedRecipientIDs = Set(recipientsList.map(\.id))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(isSending)

                    Button("Unsent") {
                        let unsent = recipientsList.filter { !$0.alreadyEmailed }.map(\.id)
                        selectedRecipientIDs = Set(unsent)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(isSending)

                    Button("Clear") {
                        selectedRecipientIDs.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(isSending)

                    Spacer()

                    Text("\(selectedRecipientIDs.count) of \(recipientsList.count) selected")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))

            Divider()

            // Recipients List
            if displayedRecipients.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 34))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("No matching contacts with emails found")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    if selectedSource == .filtered && !appState.filterCriteria.isActive {
                        Text("Apply a filter (e.g. United States + Confirmed) or choose 'All Contacts with Email'.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(displayedRecipients) { recipient in
                            recipientRow(recipient)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
    }

    private func recipientRow(_ recipient: FilteredBulkEmailRecipient) -> some View {
        let isSelected = selectedRecipientIDs.contains(recipient.id)
        let isPreviewSelected = activePreviewRecipient?.id == recipient.id
        let status = recipientStatusMap[recipient.id] ?? .ready

        return HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { checked in
                    if checked {
                        selectedRecipientIDs.insert(recipient.id)
                    } else {
                        selectedRecipientIDs.remove(recipient.id)
                    }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(isSending)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(recipient.callsign)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)

                    if !recipient.name.isEmpty && recipient.name != recipient.callsign {
                        Text(recipient.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    if !recipient.state.isEmpty {
                        Text(recipient.state)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(Color.blue.opacity(0.12)))
                            .foregroundColor(.blue)
                    }

                    Spacer()

                    // Status Badge
                    if status != .ready {
                        HStack(spacing: 3) {
                            if status == .sending {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 10, height: 10)
                            }
                            Text(status.label)
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(status.color.opacity(0.15)))
                        .foregroundColor(status.color)
                    } else if recipient.alreadyEmailed {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 8.5))
                            Text("Emailed")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.14)))
                        .foregroundColor(.orange)
                        .help(recipient.lastEmailSummary)
                    } else {
                        Text("Ready")
                            .font(.system(size: 9.5, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.10)))
                            .foregroundColor(.blue)
                    }
                }

                HStack(spacing: 8) {
                    Text(recipient.email)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Spacer()

                    if recipient.qsoCount > 1 {
                        Text("\(recipient.qsoCount) QSOs")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary.opacity(0.8))
                    }

                    if !recipient.lastBand.isEmpty {
                        Text(recipient.lastBand)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Button {
                previewRecipientID = recipient.id
                selectedRightTab = .preview
            } label: {
                Image(systemName: isPreviewSelected ? "eye.fill" : "eye")
                    .font(.system(size: 11))
                    .foregroundColor(isPreviewSelected ? .blue : .secondary.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isPreviewSelected ? Color.blue.opacity(0.12) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help("Preview personalized email for \(recipient.callsign)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isPreviewSelected ? Color.blue.opacity(0.09) : (isSelected ? Color.blue.opacity(0.03) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            previewRecipientID = recipient.id
        }
    }

    // MARK: - Right Content Pane

    private var rightContentPane: some View {
        VStack(spacing: 0) {
            // Mode Selector: Template Editor vs Live Preview
            HStack(spacing: 12) {
                Picker("", selection: $selectedRightTab) {
                    ForEach(FilteredBulkEmailRightTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Spacer()

                if let current = activePreviewRecipient {
                    HStack(spacing: 6) {
                        Text("Active Contact:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(current.callsign)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                        if !current.name.isEmpty {
                            Text("(\(current.name))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.blue.opacity(0.08)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))

            Divider()

            if selectedRightTab == .editor {
                templateEditorView
            } else {
                livePreviewView
            }
        }
    }

    // MARK: - Template Editor View

    private var templateEditorView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Template Selector & Actions
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.richtext.fill")
                        .foregroundColor(.blue)

                    Text("Template:")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)

                    Picker("", selection: $selectedTemplateID) {
                        let builtIns = templateStore.templates.filter { $0.isBuiltIn }
                        let customs = templateStore.templates.filter { !$0.isBuiltIn }

                        Section("Built-in Templates") {
                            ForEach(builtIns) { tmpl in
                                Text(tmpl.name).tag(tmpl.id)
                            }
                        }

                        if !customs.isEmpty {
                            Section("My Saved Templates") {
                                ForEach(customs) { tmpl in
                                    Text(tmpl.name).tag(tmpl.id)
                                }
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 200, maxWidth: 320)
                    .onChange(of: selectedTemplateID) { _, newID in
                        if let tmpl = templateStore.templates.first(where: { $0.id == newID }) {
                            emailSubject = tmpl.subject
                            emailBody = tmpl.body
                        }
                    }

                    Menu {
                        Button {
                            showSaveTemplateSheet = true
                        } label: {
                            Label("Save As New Template...", systemImage: "plus.square")
                        }

                        if let current = currentTemplate, !current.isBuiltIn {
                            Button {
                                updateCurrentTemplate()
                            } label: {
                                Label("Update '\(current.name)' with Current Text", systemImage: "arrow.triangle.2.circlepath")
                            }

                            Button(role: .destructive) {
                                confirmDeleteCurrentTemplate()
                            } label: {
                                Label("Delete '\(current.name)'", systemImage: "trash")
                            }
                        }

                        if let current = currentTemplate {
                            Button {
                                duplicateCurrentTemplate()
                            } label: {
                                Label("Duplicate as Custom Copy", systemImage: "doc.on.doc")
                            }

                            Divider()

                            Button {
                                emailSubject = current.subject
                                emailBody = current.body
                            } label: {
                                Label("Revert to Saved Content", systemImage: "arrow.counterclockwise")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 13))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24, height: 24)
                    .help("Template Actions")

                    Spacer()

                    if let current = currentTemplate, !current.isBuiltIn {
                        Button("Update") {
                            updateCurrentTemplate()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Save current subject and body directly to '\(current.name)'")
                    }

                    Button {
                        showSaveTemplateSheet = true
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save As...")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Save current subject, body, and filter criteria as a new template")
                }

                // Associated Filter Banner (if template has linked filter or hint)
                if let current = currentTemplate, (current.savedFilterCriteria != nil || !current.recommendedFilterHint.isEmpty) {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)

                        Text("Associated Filter:")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(.secondary)

                        let summary = current.savedFilterCriteria?.activeFilterSummary ?? current.recommendedFilterHint
                        Text(summary)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Spacer()

                        if let filter = current.savedFilterCriteria {
                            Button {
                                applyTemplateFilter(filter)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "bolt.fill")
                                    Text("Apply Filter")
                                }
                                .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .controlSize(.mini)
                            .help("Apply this template's filter criteria to the logbook and reload matching recipients")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.blue.opacity(0.18), lineWidth: 1))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            // Variable Insertion Chips
            VStack(alignment: .leading, spacing: 6) {
                Text("Insert Variables into Subject or Body:")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        variableChip("{NAME}", label: "Name")
                        variableChip("{CALLSIGN}", label: "Callsign")
                        variableChip("{MY_CALL}", label: "My Call")
                        variableChip("{STATE}", label: "State")
                        variableChip("{COUNTRY}", label: "Country")
                    }
                    HStack(spacing: 6) {
                        variableChip("{BAND}", label: "Band")
                        variableChip("{MODE}", label: "Mode")
                        variableChip("{DATE}", label: "QSO Date")
                        variableChip("{GRID}", label: "Grid")
                    }
                }
            }
            .padding(.horizontal, 14)

            // Subject Line
            VStack(alignment: .leading, spacing: 3) {
                Text("Subject:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)

                TextField("Email Subject", text: $emailSubject)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 14)

            // Body Editor
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Email Message Body:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Variables like {NAME} and {CALLSIGN} are automatically replaced per recipient")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.8))
                }

                TextEditor(text: $emailBody)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(4)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    private func variableChip(_ token: String, label: String) -> some View {
        Button {
            emailBody += "\n" + token
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 9))
                Text(token)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.blue.opacity(0.12)))
            .foregroundColor(.blue)
        }
        .buttonStyle(.plain)
        .help("Append \(token) to email body (\(label))")
    }

    // MARK: - Live Preview View

    private var livePreviewView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let recipient = activePreviewRecipient {
                // Email Envelope Headers
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("To:")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 45, alignment: .leading)
                                Text("\(recipient.name) <\(recipient.email)>")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.primary)
                            }

                            HStack(spacing: 6) {
                                Text("From:")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 45, alignment: .leading)
                                Text("\(resolvedMyCallsign) <\(smtpUser.isEmpty ? "configured SMTP" : smtpUser)>")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            HStack(spacing: 6) {
                                Text("Subject:")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .frame(width: 45, alignment: .leading)
                                Text(interpolateTemplate(emailSubject, for: recipient))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.blue)
                            }
                        }

                        Spacer()

                        // Recipient Navigation Controls
                        HStack(spacing: 6) {
                            Button {
                                stepPreview(forward: false)
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Previous recipient")

                            Button {
                                stepPreview(forward: true)
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Next recipient")
                        }
                    }

                    // Contact Meta Badge Strip
                    HStack(spacing: 8) {
                        badgeItem(icon: "antenna.radiowaves.left.and.right", title: "\(recipient.lastBand) / \(recipient.lastMode)")
                        if !recipient.state.isEmpty {
                            badgeItem(icon: "map", title: "State: \(recipient.state)")
                        }
                        if !recipient.country.isEmpty {
                            badgeItem(icon: "globe", title: recipient.country)
                        }
                        badgeItem(icon: "number", title: "\(recipient.qsoCount) Total QSO(s)")
                        if recipient.alreadyEmailed {
                            HStack(spacing: 3) {
                                Image(systemName: "clock")
                                Text("Emailed Previously")
                            }
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.12)))
                        }
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                Divider()

                // Rendered Email Body
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(interpolateTemplate(emailBody, for: recipient))
                            .font(.system(size: 12.5, design: .serif))
                            .lineSpacing(4)
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "eye.slash")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Select a recipient on the left to see live preview")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func badgeItem(icon: String, title: String) -> some View {
        HStack(spacing: 3.5) {
            Image(systemName: icon)
                .font(.system(size: 8.5))
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.10)))
        .foregroundColor(.secondary)
    }

    private func stepPreview(forward: Bool) {
        guard !displayedRecipients.isEmpty else { return }
        let currentID = activePreviewRecipient?.id
        let currentIndex = displayedRecipients.firstIndex(where: { $0.id == currentID }) ?? 0
        let nextIndex: Int
        if forward {
            nextIndex = (currentIndex + 1) % displayedRecipients.count
        } else {
            nextIndex = (currentIndex - 1 + displayedRecipients.count) % displayedRecipients.count
        }
        previewRecipientID = displayedRecipients[nextIndex].id
    }

    // MARK: - Bottom Status Bar

    private var bottomStatusBar: some View {
        HStack(spacing: 14) {
            if isSending {
                // Active Sending Status & Progress
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Sending \(sendProgress.current) of \(sendProgress.total):")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.primary)
                            Text(currentSendingCall)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                        }

                        ProgressView(value: Double(sendProgress.current), total: Double(max(1, sendProgress.total)))
                            .progressViewStyle(.linear)
                            .frame(minWidth: 160, idealWidth: 240, maxWidth: 340)
                    }
                }

                Spacer()

                // Prominent Stop Button
                Button(role: .destructive) {
                    cancelRequested = true
                } label: {
                    HStack(spacing: 6) {
                        if cancelRequested {
                            ProgressView()
                                .controlSize(.small)
                            Text("Stopping...")
                                .font(.system(size: 12, weight: .bold))
                        } else {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 13, weight: .bold))
                            Text("Stop Dispatch")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.regular)
                .disabled(cancelRequested)
                .fixedSize()
            } else {
                // Idle / Selection Status
                HStack(spacing: 6) {
                    Text("\(selectedCount) of \(recipientsList.count) selected")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("•")
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("\(unsentSelectedCount) unsent")
                        .font(.system(size: 11))
                        .foregroundColor(unsentSelectedCount > 0 ? .green : .secondary)

                    Toggle("Mark QSL_SENT = E", isOn: $markAsQSLSent)
                        .font(.system(size: 11))
                        .toggleStyle(.checkbox)
                        .padding(.leading, 8)
                        .help("If enabled, marks matching QSO records as QSL sent via email (QSL_SENT = Y, QSL_SENT_VIA = E)")
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button(action: startBatchSend) {
                    HStack(spacing: 5) {
                        Image(systemName: "paperplane.fill")
                        Text("Send Emails (\(selectedCount))")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(
                    selectedCount == 0 ||
                    emailSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    emailBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Template Actions & Helpers

    private var currentTemplate: SavedBulkEmailTemplate? {
        templateStore.templates.first(where: { $0.id == selectedTemplateID }) ?? templateStore.templates.first
    }

    private func applyTemplateFilter(_ filter: FilterCriteria) {
        appState.filterCriteria = filter
        selectedSource = .filtered
        refreshRecipients()
        appState.appendLog("Applied associated filter from template '\(currentTemplate?.name ?? "")': \(filter.activeFilterSummary)")
    }

    private func updateCurrentTemplate() {
        guard let current = currentTemplate, !current.isBuiltIn else { return }
        _ = templateStore.saveTemplate(
            name: current.name,
            subject: emailSubject,
            body: emailBody,
            filterHint: appState.filterCriteria.isActive ? appState.filterCriteria.activeFilterSummary : current.recommendedFilterHint,
            filterCriteria: appState.filterCriteria.isActive ? appState.filterCriteria : current.savedFilterCriteria,
            existingID: current.id
        )
        alertTitle = "Template Updated"
        alertMessage = "Template '\(current.name)' updated successfully."
        showAlert = true
    }

    private func duplicateCurrentTemplate() {
        guard let current = currentTemplate else { return }
        if let copy = templateStore.duplicateTemplate(id: current.id) {
            selectedTemplateID = copy.id
            emailSubject = copy.subject
            emailBody = copy.body
            alertTitle = "Template Duplicated"
            alertMessage = "Created custom copy '\(copy.name)'."
            showAlert = true
        }
    }

    private func confirmDeleteCurrentTemplate() {
        guard let current = currentTemplate, !current.isBuiltIn else { return }
        let alert = NSAlert()
        alert.messageText = "Delete Template"
        alert.informativeText = "Are you sure you want to permanently delete the template '\(current.name)'?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            deleteCurrentTemplate()
        }
    }

    private func deleteCurrentTemplate() {
        guard let current = currentTemplate, !current.isBuiltIn else { return }
        let name = current.name
        templateStore.deleteTemplate(id: current.id)
        if let first = templateStore.templates.first {
            selectedTemplateID = first.id
            emailSubject = first.subject
            emailBody = first.body
        }
        alertTitle = "Template Deleted"
        alertMessage = "Template '\(name)' has been deleted."
        showAlert = true
    }

    // MARK: - Template Engine

    private func interpolateTemplate(_ text: String, for recipient: FilteredBulkEmailRecipient) -> String {
        let myCall = resolvedMyCallsign
        let myName = resolvedMyName
        var result = text
        result = result.replacingOccurrences(of: "{NAME}", with: recipient.name)
        result = result.replacingOccurrences(of: "{CALLSIGN}", with: recipient.callsign)
        result = result.replacingOccurrences(of: "{MY_CALL}", with: myCall)
        result = result.replacingOccurrences(of: "{MY_NAME}", with: myName.isEmpty ? myCall : myName)
        result = result.replacingOccurrences(of: "{STATE}", with: recipient.state.isEmpty ? "your state" : recipient.state)
        result = result.replacingOccurrences(of: "{COUNTRY}", with: recipient.country.isEmpty ? "your country" : recipient.country)
        result = result.replacingOccurrences(of: "{BAND}", with: recipient.lastBand.isEmpty ? "the bands" : recipient.lastBand)
        result = result.replacingOccurrences(of: "{MODE}", with: recipient.lastMode.isEmpty ? "our mode" : recipient.lastMode)
        result = result.replacingOccurrences(of: "{DATE}", with: recipient.lastDate)
        result = result.replacingOccurrences(of: "{GRID}", with: recipient.grid)
        return result
    }

    private func formatDateDisplay(_ raw: String) -> String {
        let clean = raw.filter(\.isNumber)
        guard clean.count == 8 else { return raw }
        let y = clean.prefix(4)
        let m = clean.dropFirst(4).prefix(2)
        let d = clean.suffix(2)
        return "\(y)-\(m)-\(d)"
    }

    // MARK: - Recipients Builder

    private func refreshRecipients() {
        let rawRecords: [QSORecordModel]
        switch selectedSource {
        case .filtered:
            rawRecords = appState.filterCriteria.isActive ? appState.filteredRecords : appState.qsoRecords
        case .selected:
            rawRecords = appState.qsoRecords.filter { appState.selectedRecordIDs.contains($0.id) }
        case .allWithEmail:
            rawRecords = appState.qsoRecords
        }

        let withEmail = rawRecords.filter {
            let e = $0["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines)
            return e.contains("@") && e.contains(".")
        }

        var groupedByCall: [String: [QSORecordModel]] = [:]
        for r in withEmail {
            let call = r["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !call.isEmpty else { continue }
            groupedByCall[call, default: []].append(r)
        }

        var results: [FilteredBulkEmailRecipient] = []

        for (call, qsos) in groupedByCall {
            let sorted = qsos.sorted { ($0["QSO_DATE"] + $0["TIME_ON"]) > ($1["QSO_DATE"] + $1["TIME_ON"]) }
            let primary = sorted.first ?? qsos[0]

            let rawEmail = primary["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedName = appState.resolveFirstName(for: call, explicitName: primary["NAME"])
            let state = primary["STATE"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? primary["US_STATE"]
                : primary["STATE"]
            let country = primary["COUNTRY"].trimmingCharacters(in: .whitespacesAndNewlines)
            let grid = primary["GRIDSQUARE"].trimmingCharacters(in: .whitespacesAndNewlines)
            let band = primary["BAND"].trimmingCharacters(in: .whitespacesAndNewlines)
            let mode = primary["MODE"].trimmingCharacters(in: .whitespacesAndNewlines)
            let date = formatDateDisplay(primary["QSO_DATE"])
            let isConfirmed = qsos.contains { $0.isConfirmed }

            let history = appState.latestEmailHistory(for: call)
            let alreadyEmailed = history != nil && history?.status == "Sent"
            let summary = history != nil ? "\(appState.formattedEmailHistoryDate(history!.date)): \(history!.subject)" : ""

            results.append(FilteredBulkEmailRecipient(
                id: UUID(),
                callsign: call,
                name: resolvedName,
                email: rawEmail,
                state: state,
                country: country,
                grid: grid,
                qsoCount: qsos.count,
                lastBand: band,
                lastMode: mode,
                lastDate: date,
                isConfirmed: isConfirmed,
                alreadyEmailed: alreadyEmailed,
                lastEmailSummary: summary,
                qso: primary,
                allRecords: qsos
            ))
        }

        let sortedResults = results.sorted { $0.callsign < $1.callsign }
        recipientsList = sortedResults
        selectedRecipientIDs = Set(sortedResults.map(\.id))
        if previewRecipientID == nil || !sortedResults.contains(where: { $0.id == previewRecipientID }) {
            previewRecipientID = sortedResults.first?.id
        }
    }

    // MARK: - Batch Dispatch Engine

    private func startBatchSend() {
        let selectedRecipients = recipientsList.filter { selectedRecipientIDs.contains($0.id) }
        guard !selectedRecipients.isEmpty else { return }

        // 1. Validate SMTP
        if !appState.isSMTPConfigured {
            alertTitle = "SMTP Configuration Required"
            alertMessage = "Please enter your SMTP Username and Password in Settings > Email before sending bulk emails."
            showAlert = true
            return
        }

        // 2. Duplicate Detection
        var finalRecipients = selectedRecipients
        let alreadyEmailedList = selectedRecipients.filter { $0.alreadyEmailed }

        if !alreadyEmailedList.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Previous Email Warning"
            alert.alertStyle = .warning

            let dupCount = alreadyEmailedList.count
            let totalCount = selectedRecipients.count
            let unsentCount = totalCount - dupCount

            let previewList = alreadyEmailedList.prefix(5).map {
                "• \($0.callsign) (\($0.name)): \($0.lastEmailSummary)"
            }.joined(separator: "\n") + (dupCount > 5 ? "\n• ...and \(dupCount - 5) more" : "")

            if unsentCount > 0 {
                alert.informativeText = """
                \(dupCount) of the \(totalCount) selected recipients have ALREADY received an email from YAAM previously:

                \(previewList)

                Would you like to send only to the \(unsentCount) new recipient(s), or resend to all?
                """
                alert.addButton(withTitle: "Send Only to Unsent (\(unsentCount))")
                alert.addButton(withTitle: "Resend to All (\(totalCount))")
                alert.addButton(withTitle: "Cancel")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    finalRecipients = selectedRecipients.filter { !$0.alreadyEmailed }
                } else if response == .alertSecondButtonReturn {
                    finalRecipients = selectedRecipients
                } else {
                    return
                }
            } else {
                alert.informativeText = """
                All \(dupCount) selected recipient(s) have ALREADY received an email previously:

                \(previewList)

                Are you sure you want to resend to all \(dupCount) contacts?
                """
                alert.addButton(withTitle: "Resend to All (\(dupCount))")
                alert.addButton(withTitle: "Cancel")

                let response = alert.runModal()
                if response != .alertFirstButtonReturn {
                    return
                }
                finalRecipients = selectedRecipients
            }
        }

        guard !finalRecipients.isEmpty else { return }

        isSending = true
        cancelRequested = false
        sendProgress = (0, finalRecipients.count)

        DispatchQueue.global(qos: .userInitiated).async {
            var sentCount = 0
            var failedCount = 0
            var sentDetailsList: [(call: String, email: String, subject: String, allQSOs: [QSORecordModel])] = []
            var failedDetailsList: [(call: String, email: String, subject: String)] = []

            for (index, recipient) in finalRecipients.enumerated() {
                if self.cancelRequested { break }

                let call = recipient.callsign
                let email = recipient.email

                DispatchQueue.main.async {
                    self.sendProgress = (index + 1, finalRecipients.count)
                    self.currentSendingCall = call
                    self.recipientStatusMap[recipient.id] = .sending
                }

                let sub = self.interpolateTemplate(self.emailSubject, for: recipient)
                let body = self.interpolateTemplate(self.emailBody, for: recipient)

                let semaphore = DispatchSemaphore(value: 0)
                var successResult = false

                self.appState.sendEmail(
                    to: email,
                    subject: sub,
                    body: body,
                    attachmentData: nil,
                    attachmentName: nil,
                    replyTo: nil,
                    callsign: call,
                    playSound: false
                ) { ok, _ in
                    successResult = ok
                    semaphore.signal()
                }

                semaphore.wait()

                DispatchQueue.main.async {
                    if successResult {
                        sentCount += 1
                        self.recipientStatusMap[recipient.id] = .sent
                        sentDetailsList.append((call, email, sub, recipient.allRecords))
                    } else {
                        failedCount += 1
                        self.recipientStatusMap[recipient.id] = .failed("SMTP error")
                        failedDetailsList.append((call, email, sub))
                    }
                }

                // Polite throttle 1.0s between emails
                Thread.sleep(forTimeInterval: 1.0)
            }

            DispatchQueue.main.async {
                self.isSending = false

                // 1. Commit email history entries (fast memory-only insert without per-item disk saves)
                for item in sentDetailsList {
                    self.appState.recordEmailHistory(
                        callsign: item.call,
                        email: item.email,
                        subject: item.subject,
                        status: "Sent",
                        updateLogbookRows: false,
                        autoSave: false
                    )
                }

                for item in failedDetailsList {
                    self.appState.recordEmailHistory(
                        callsign: item.call,
                        email: item.email,
                        subject: item.subject,
                        status: "Failed",
                        updateLogbookRows: false,
                        autoSave: false
                    )
                }

                // 2. Mark QSL Sent if requested
                if self.markAsQSLSent {
                    let sentIDs = Set(sentDetailsList.flatMap { $0.allQSOs.map(\.id) })
                    if !sentIDs.isEmpty {
                        self.appState.batchMarkRecordsAsQSLSent(ids: sentIDs, via: "E", autoSave: false)
                    }
                }

                // 3. Single consolidated save
                try? self.appState.persistCurrentWorkspace(reason: "Bulk email dispatch completed")

                self.appState.playActivitySound(failedCount == 0 ? .success : .failure)
                self.alertTitle = self.cancelRequested ? "Dispatch Stopped 🛑" : "Bulk Dispatch Complete 🎉"
                self.alertMessage = "\(sentCount) email(s) successfully delivered via SMTP. \(failedCount > 0 ? "\(failedCount) failed. " : "")\(self.cancelRequested ? "Dispatch was stopped by user." : "")"
                self.showAlert = true
            }
        }
    }
}
