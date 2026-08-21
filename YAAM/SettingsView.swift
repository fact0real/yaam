//
//  SettingsView.swift
//  ADIF to Excel
//
//  Created by factoreal on 7/31/26.
//

import SwiftUI
import AppKit

// MARK: - macOS Preferences & Credentials Settings Sheet
struct SettingsView: View {
    private enum Tabs: Hashable {
        case stations, dataSafety, qrz, qrzRank, lotw, hamqth, smtp, externalADIF, sdrControl
    }

    @EnvironmentObject var appState: AppState
    
    @AppStorage("qrzUsername") private var qrzUsername = ""
    @State private var qrzPassword = ""
    @State private var qrzCredentialStatus = ""
    @AppStorage("qrzRankServiceUsername") private var qrzRankServiceUsername = ""
    @State private var qrzRankServicePassword = ""
    @State private var qrzRankCredentialStatus = ""
    
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
                    Text("QRZ Rank Service")
                        .font(.headline)

                    TextField("Rank service username:", text: $qrzRankServiceUsername)
                        .textFieldStyle(.roundedBorder)

                    SecureField("New password (blank keeps the saved password):", text: $qrzRankServicePassword)
                        .textFieldStyle(.roundedBorder)

                    Label("Stored in macOS Keychain", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            saveCredential(qrzRankServicePassword, as: .qrzRankPassword, status: $qrzRankCredentialStatus)
                            Task { await QRZRankService.shared.resetAuthentication() }
                        } label: {
                            Label("Save Rank Password", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(qrzRankServicePassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Remove Password", role: .destructive) {
                            removeCredential(.qrzRankPassword, value: $qrzRankServicePassword, status: $qrzRankCredentialStatus)
                            Task { await QRZRankService.shared.resetAuthentication() }
                        }

                        credentialStatus(qrzRankCredentialStatus)
                    }

                    Link(destination: URL(string: "https://qrz-rank.asis.sh/")!) {
                        Label("Open QRZ Rank account and subscription", systemImage: "arrow.up.right.square")
                    }

                    Text("Leaderboard, enrichment, and Daily Rank Backfill use QRZ Rank Panel. Guest access is limited to three lookups; add a Rank Panel account here for authenticated retrieval. YAAM enforces one shared limit of 1,440 rank requests per local day. This account is separate from QRZ.com.")
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
        status.wrappedValue = CredentialVault.set(value, for: credential) ? "Saved" : "Keychain could not save this password"
        if status.wrappedValue == "Saved" {
            switch credential {
            case .qrzPassword: qrzPassword = ""
            case .qrzRankPassword: qrzRankServicePassword = ""
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
        status.wrappedValue = removed ? "Removed" : "Keychain could not remove this password"
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
        panel.allowedFileTypes = ["p12", "pfx"]
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
