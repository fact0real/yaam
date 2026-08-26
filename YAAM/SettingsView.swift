//
//  SettingsView.swift
//  ADIF to Excel
//
//  Created by factoreal on 7/31/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - macOS Preferences & Credentials Settings Sheet
struct SettingsView: View {
    private enum Tabs: Hashable {
        case stations, dataSafety, qrz, qrzRank, clubLog, lotw, hamqth, smtp, externalADIF, sdrControl, assistant
    }

    @EnvironmentObject var appState: AppState
    
    @AppStorage("qrzUsername") private var qrzUsername = ""
    @State private var qrzPassword = ""
    @State private var qrzCredentialStatus = ""
    @State private var qrzRankAPIToken = ""
    @State private var qrzRankCredentialStatus = ""

    @AppStorage("clubLogEmail") private var clubLogEmail = ""
    @AppStorage("clubLogCallsign") private var clubLogCallsign = ""
    @State private var clubLogPassword = ""
    @State private var clubLogAPIKey = ""
    @State private var clubLogCredentialStatus = ""
    @State private var showSettingsClubLogLoginSheet = false
    
    @AppStorage("lotwUsername") private var lotwUsername = ""
    @State private var lotwPassword = ""
    @State private var lotwCredentialStatus = ""
    @AppStorage("lotwCertificateContainerPath") private var lotwCertificateContainerPath = ""
    @State private var lotwCertificatePassword = ""
    @State private var lotwCertificateStatus = ""
    @AppStorage("hamqthUsername") private var hamqthUsername = ""
    @State private var hamqthPassword = ""
    @State private var hamqthCredentialStatus = ""
    @AppStorage("externalADIFLogPath") private var externalADIFLogPath = ""
    @AppStorage("externalADIFAutoSyncEnabled") private var externalADIFAutoSyncEnabled = false
    @AppStorage("externalADIFSyncIntervalMinutes") private var externalADIFSyncIntervalMinutes = 15.0
    @AppStorage("sdrControlLogbookPath") private var sdrControlLogbookPath = ""
    @AppStorage("sdrControlPeriodicSyncEnabled") private var sdrControlPeriodicSyncEnabled = false
    @AppStorage("sdrControlPeriodicSyncIntervalMinutes") private var sdrControlPeriodicSyncIntervalMinutes = 15.0
    @AppStorage("logAssistantEndpoint") private var logAssistantEndpoint = "https://api.openai.com/v1/chat/completions"
    @AppStorage("logAssistantModel") private var logAssistantModel = "gpt-5-mini"
    @State private var logAssistantAPIKey = ""
    @State private var logAssistantCredentialStatus = ""

    var body: some View {
        TabView {
            StationProfilesSettingsView()
                .environmentObject(appState)
            .tabItem {
                Label("Stations", systemImage: "antenna.radiowaves.left.and.right")
            }
            .tag(Tabs.stations)

            DataSafetySettingsView()
                .environmentObject(appState)
                .tabItem {
                    Label("Data Safety", systemImage: "externaldrive.fill.badge.checkmark")
                }
                .tag(Tabs.dataSafety)

            // MARK: - QRZ.com Settings Tab
            Form {
                VStack(alignment: .leading, spacing: 16) {
                    Text("QRZ.com Integration")
                        .font(.headline)

                    TextField("Username:", text: $qrzUsername)
                        .textFieldStyle(.roundedBorder)

                    SecureField("New password (blank keeps the saved password):", text: $qrzPassword)
                        .textFieldStyle(.roundedBorder)

                    Label("Stored in macOS Keychain", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            saveCredential(qrzPassword, as: .qrzPassword, status: $qrzCredentialStatus)
                        } label: {
                            Label("Save QRZ Password", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(qrzPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Remove Password", role: .destructive) {
                            removeCredential(.qrzPassword, value: $qrzPassword, status: $qrzCredentialStatus)
                        }

                        credentialStatus(qrzCredentialStatus)
                    }
                    
                    Label("The QRZ Logbook API key is stored per station under the Stations tab. The account password remains shared for QRZ login and Awards.", systemImage: "key.horizontal.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .tabItem {
                Label("QRZ.com", systemImage: "q.circle.fill")
            }
            .tag(Tabs.qrz)

            Form {
                VStack(alignment: .leading, spacing: 16) {
                    Text("QRZ Rank API")
                        .font(.headline)

                    SecureField("Personal API token (blank keeps the saved token):", text: $qrzRankAPIToken)
                        .textFieldStyle(.roundedBorder)

                    Label("Stored in macOS Keychain and sent only as an Authorization header", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            let token = QRZRankAPIContract.normalizedToken(qrzRankAPIToken)
                            saveCredential(token, as: .qrzRankAPIToken, status: $qrzRankCredentialStatus)
                        } label: {
                            Label("Save API Token", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(QRZRankAPIContract.normalizedToken(qrzRankAPIToken).isEmpty)

                        Button("Remove Token", role: .destructive) {
                            removeCredential(.qrzRankAPIToken, value: $qrzRankAPIToken, status: $qrzRankCredentialStatus)
                        }

                        credentialStatus(qrzRankCredentialStatus)
                    }

                    Link(destination: URL(string: "https://qrz-rank.asis.sh/")!) {
                        Label("Open QRZ Rank panel to generate a token", systemImage: "arrow.up.right.square")
                    }

                    Text("Leaderboard, enrichment, and Daily Rank Backfill use your personal Bearer token. YAAM never puts this token in a URL or log. Before a batch, YAAM reads the allowance assigned to your account by the server and follows its reported remaining count or unlimited status. This token is separate from your QRZ.com credentials.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
            }
            .tabItem {
                Label("Rank Service", systemImage: "chart.line.uptrend.xyaxis")
            }
            .tag(Tabs.qrzRank)

            // MARK: - Club Log Settings Tab
            Form {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Club Log Integration")
                        .font(.headline)

                    TextField("Email Address:", text: $clubLogEmail)
                        .textFieldStyle(.roundedBorder)

                    TextField("Callsign:", text: $clubLogCallsign)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Application Password (blank keeps saved password):", text: $clubLogPassword)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Club Log API Key (optional):", text: $clubLogAPIKey)
                        .textFieldStyle(.roundedBorder)

                    Label("Stored securely in macOS Keychain", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            if !clubLogPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                saveCredential(clubLogPassword, as: .clubLogPassword, status: $clubLogCredentialStatus)
                            }
                            if !clubLogAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                saveCredential(clubLogAPIKey, as: .clubLogAPIKey, status: $clubLogCredentialStatus)
                            }
                            if clubLogPassword.isEmpty && clubLogAPIKey.isEmpty {
                                clubLogCredentialStatus = "Saved"
                            }
                        } label: {
                            Label("Save Credentials", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Remove Password/Key", role: .destructive) {
                            removeCredential(.clubLogPassword, value: $clubLogPassword, status: $clubLogCredentialStatus)
                            removeCredential(.clubLogAPIKey, value: $clubLogAPIKey, status: $clubLogCredentialStatus)
                        }

                        credentialStatus(clubLogCredentialStatus)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("2-Factor Authentication (2FA / MFA)")
                            .font(.subheadline.weight(.semibold))

                        if ClubLogSessionStore.hasSavedSession() {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Active Club Log Session Authenticated")
                                        .font(.caption.bold())
                                        .foregroundColor(.green)
                                    Text("Your 2FA session is active and saved in Keychain.")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Sign Out", role: .destructive) {
                                    ClubLogSessionStore.clear()
                                    clubLogCredentialStatus = "Signed out"
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            }
                            .padding(8)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        } else {
                            Text("If your Club Log account uses 2-Factor Authentication (2FA/MFA) or if you do not have an API key, click below to log in.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button {
                            if !clubLogPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                saveCredential(clubLogPassword, as: .clubLogPassword, status: $clubLogCredentialStatus)
                            }
                            if !clubLogAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                saveCredential(clubLogAPIKey, as: .clubLogAPIKey, status: $clubLogCredentialStatus)
                            }
                            showSettingsClubLogLoginSheet = true
                        } label: {
                            Label(
                                ClubLogSessionStore.hasSavedSession() ? "Verify / Re-authenticate 2FA" : "Log In & Verify 2FA",
                                systemImage: ClubLogSessionStore.hasSavedSession() ? "arrow.clockwise.circle" : "lock.shield.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ClubLogSessionStore.hasSavedSession() ? .green : .blue)
                    }
                }
                .padding()
            }
            .tabItem {
                Label("Club Log", systemImage: "person.3.fill")
            }
            .tag(Tabs.clubLog)
            .onAppear {
                clubLogPassword = CredentialVault.value(for: .clubLogPassword)
                clubLogAPIKey = CredentialVault.value(for: .clubLogAPIKey)
            }
            
            // MARK: - LoTW Settings Tab
            Form {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Logbook of The World (LoTW)")
                        .font(.headline)
                    
                    TextField("Username:", text: $lotwUsername)
                        .textFieldStyle(.roundedBorder)
                    
                    SecureField("New password (blank keeps the saved password):", text: $lotwPassword)
                        .textFieldStyle(.roundedBorder)

                    Label("Stored in macOS Keychain", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            saveCredential(lotwPassword, as: .lotwPassword, status: $lotwCredentialStatus)
                        } label: {
                            Label("Save LoTW Password", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(lotwPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Remove Password", role: .destructive) {
                            removeCredential(.lotwPassword, value: $lotwPassword, status: $lotwCredentialStatus)
                        }

                        credentialStatus(lotwCredentialStatus)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("LoTW Certificate Container (.p12)", systemImage: "doc.badge.gearshape")
                            .font(.subheadline.weight(.semibold))
                        Text(lotwCertificateContainerPath.isEmpty ? "No certificate container selected" : lotwCertificateContainerPath)
                            .font(.caption.monospaced())
                            .lineLimit(2)
                            .truncationMode(.middle)
                        HStack {
                            Button("Choose .p12...") {
                                chooseLoTWCertificateContainer()
                            }
                            Button("Remove Certificate", role: .destructive) {
                                UserDefaults.standard.removeObject(forKey: "lotwCertificateContainerBookmark")
                                lotwCertificateContainerPath = ""
                            }
                            .disabled(lotwCertificateContainerPath.isEmpty)
                        }
                        SecureField("Certificate password (optional, saved in Keychain)", text: $lotwCertificatePassword)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Save Certificate Password") {
                                saveCredential(lotwCertificatePassword, as: .lotwCertificatePassword, status: $lotwCertificateStatus)
                            }
                            .disabled(lotwCertificatePassword.isEmpty)
                            Button("Remove Certificate Password", role: .destructive) {
                                removeCredential(.lotwCertificatePassword, value: $lotwCertificatePassword, status: $lotwCertificateStatus)
                            }
                            credentialStatus(lotwCertificateStatus)
                        }
                        Text("YAAM keeps a security-scoped reference to the .p12 file. TQSL must import the certificate before it can sign and upload new QSOs; the file itself is never copied into the logbook.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Text("Credentials are used to securely download your latest TQSL verification records directly from ARRL servers.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .tabItem {
                Label("LoTW", systemImage: "globe.americas.fill")
            }
            .tag(Tabs.lotw)

            // MARK: - HAMQTH Settings Tab
            Form {
                VStack(alignment: .leading, spacing: 16) {
                    Text("HAMQTH Integration")
                        .font(.headline)

                    TextField("Username:", text: $hamqthUsername)
                        .textFieldStyle(.roundedBorder)

                    SecureField("New password (blank keeps the saved password):", text: $hamqthPassword)
                        .textFieldStyle(.roundedBorder)

                    Label("Stored in macOS Keychain", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            saveCredential(hamqthPassword, as: .hamqthPassword, status: $hamqthCredentialStatus)
                        } label: {
                            Label("Save HAMQTH Password", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(hamqthPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Remove Password", role: .destructive) {
                            removeCredential(.hamqthPassword, value: $hamqthPassword, status: $hamqthCredentialStatus)
                        }

                        credentialStatus(hamqthCredentialStatus)
                    }

                    Text("Credentials will be used for HAMQTH callsign lookups in DX Advisor and contact enrichment.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .tabItem {
                Label("HAMQTH", systemImage: "person.text.rectangle")
            }
            .tag(Tabs.hamqth)

            SMTPSettingsView(embeddedInSettings: true)
                .tabItem {
                    Label("Email", systemImage: "envelope")
                }
                .tag(Tabs.smtp)

            Form {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Log Assistant")
                        .font(.headline)
                    Text("The assistant can explain the active log and propose safe actions. It never sends mail, deletes QSOs, or syncs a cloud service without your confirmation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("OpenAI-compatible endpoint", text: $logAssistantEndpoint)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model", text: $logAssistantModel)
                        .textFieldStyle(.roundedBorder)
                    SecureField("API key (blank keeps the saved key)", text: $logAssistantAPIKey)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Save Assistant Key") {
                            saveCredential(logAssistantAPIKey, as: .logAssistantAPIKey, status: $logAssistantCredentialStatus)
                        }
                        .disabled(logAssistantAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Remove Key", role: .destructive) {
                            removeCredential(.logAssistantAPIKey, value: $logAssistantAPIKey, status: $logAssistantCredentialStatus)
                        }
                        credentialStatus(logAssistantCredentialStatus)
                    }
                    Label("Use an account you control. The key stays in macOS Keychain and is only used when you explicitly ask the assistant to analyse a prompt.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .tabItem {
                Label("Assistant", systemImage: "bubble.left.and.text.bubble.right")
            }
            .tag(Tabs.assistant)

            // MARK: - External ADIF Sync Tab
            Form {
                VStack(alignment: .leading, spacing: 16) {
                    Text("External ADIF Sync")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("ADIF Log File:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Text(resolvedExternalADIFPath.isEmpty ? "No external ADIF log selected" : resolvedExternalADIFPath)
                                .font(.caption)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("Choose...") {
                                appState.selectExternalADIFLogFile()
                            }
                        }
                    }

                    Toggle("Sync automatically", isOn: $externalADIFAutoSyncEnabled)
                        .onChange(of: externalADIFAutoSyncEnabled) { _, _ in
                            appState.configureExternalADIFAutoSync()
                        }

                    HStack {
                        Text("Interval:")
                        Stepper(
                            "\(Int(externalADIFSyncIntervalMinutes)) minutes",
                            value: $externalADIFSyncIntervalMinutes,
                            in: 1...120,
                            step: 1
                        )
                        .onChange(of: externalADIFSyncIntervalMinutes) { _, _ in
                            appState.configureExternalADIFAutoSync()
                        }
                    }

                    Button("Sync Now") {
                        appState.syncExternalADIFLogIfNeeded()
                    }
                    .disabled(resolvedExternalADIFPath.isEmpty)

                    Text("Select a live .adi/.adif file from any logger or digital-mode app such as WSJT-X, JTDX, GridTracker, Log4OM, N1MM, or SDR-Control exports. YAAM will periodically merge new QSOs into the Master Log.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .tabItem {
                Label("External ADIF", systemImage: "arrow.triangle.2.circlepath.doc.on.clipboard")
            }
            .tag(Tabs.externalADIF)

            Form {
                VStack(alignment: .leading, spacing: 16) {
                    Text("SDR-Control iCloud Log")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("SmartSDR.smartsdrlog:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Text(resolvedSDRControlLogbookPath.isEmpty ? "No SmartSDR.smartsdrlog permission saved" : resolvedSDRControlLogbookPath)
                                .font(.caption)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("Choose...") {
                                appState.chooseSDRControlLogbookFile()
                                refreshSDRControlPath()
                            }
                        }
                    }

                    Toggle("Import periodically", isOn: $sdrControlPeriodicSyncEnabled)
                        .onChange(of: sdrControlPeriodicSyncEnabled) { _, _ in
                            appState.configureSDRControlPeriodicSync()
                        }

                    HStack {
                        Text("Interval:")
                        Stepper(
                            "\(Int(sdrControlPeriodicSyncIntervalMinutes)) minutes",
                            value: $sdrControlPeriodicSyncIntervalMinutes,
                            in: 1...120,
                            step: 1
                        )
                        .onChange(of: sdrControlPeriodicSyncIntervalMinutes) { _, _ in
                            appState.configureSDRControlPeriodicSync()
                        }
                    }

                    Button("Sync Now") {
                        appState.syncSDRControlLogbookIfNeeded()
                        refreshSDRControlPath()
                    }

                    Text("Reads SDR-Control's SmartSDR.smartsdrlog binary plist directly from iCloud, filters deleted contacts, converts date/time to ADIF format, and merges new QSOs into the Master Log. macOS may ask you to choose the file once so YAAM can save permission.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .tabItem {
                Label("SDR-Control", systemImage: "antenna.radiowaves.left.and.right")
            }
            .tag(Tabs.sdrControl)
        }
        .padding(10)
        .onAppear {
            refreshSDRControlPath()
        }
        .sheet(isPresented: $showSettingsClubLogLoginSheet) {
            ClubLogLoginView()
                .environmentObject(appState)
        }
    }

    @ViewBuilder
    private func credentialStatus(_ status: String) -> some View {
        if !status.isEmpty {
            let succeeded = ["Saved", "Removed"].contains(status)
            Label(status, systemImage: succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(succeeded ? .green : .orange)
        }
    }

    private func saveCredential(
        _ value: String,
        as credential: SecureCredential,
        status: Binding<String>
    ) {
        status.wrappedValue = CredentialVault.set(value, for: credential) ? "Saved" : "Keychain could not save this credential"
        if status.wrappedValue == "Saved" {
            switch credential {
            case .qrzPassword: qrzPassword = ""
            case .qrzRankAPIToken: qrzRankAPIToken = ""
            case .lotwPassword: lotwPassword = ""
            case .lotwCertificatePassword: lotwCertificatePassword = ""
            case .hamqthPassword: hamqthPassword = ""
            default: break
            }
        }
        appState.refreshSyncServiceConfiguration()
    }

    private func removeCredential(
        _ credential: SecureCredential,
        value: Binding<String>,
        status: Binding<String>
    ) {
        let removed = CredentialVault.delete(credential)
        if removed { value.wrappedValue = "" }
        status.wrappedValue = removed ? "Removed" : "Keychain could not remove this credential"
        appState.refreshSyncServiceConfiguration()
    }

    private var resolvedExternalADIFPath: String {
        if !externalADIFLogPath.isEmpty {
            return externalADIFLogPath
        }

        return UserDefaults.standard.string(forKey: "sdrControlLogPath") ?? ""
    }

    private func chooseLoTWCertificateContainer() {
        let panel = NSOpenPanel()
        panel.title = "Select LoTW Certificate Container"
        panel.message = "Choose the .p12 certificate container exported from TQSL."
        panel.prompt = "Choose Certificate"
        panel.allowedContentTypes = ["p12", "pfx"].compactMap { UTType(filenameExtension: $0) }
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: "lotwCertificateContainerBookmark")
            lotwCertificateContainerPath = url.path
            lotwCertificateStatus = "Saved"
        } catch {
            lotwCertificateStatus = "Could not save file permission"
        }
    }

    private var resolvedSDRControlLogbookPath: String {
        sdrControlLogbookPath
    }

    private func refreshSDRControlPath() {
        sdrControlLogbookPath = UserDefaults.standard.string(forKey: "sdrControlLogbookPath") ?? ""
    }
}
