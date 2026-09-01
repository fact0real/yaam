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
        case stations, dataSafety, qrz, qrzRank, clubLog, lotw, eqsl, wavelog, clubs, tci, winkeyer, on4kst, hrdlog, hamqth, smtp, externalADIF, sdrControl, assistant
    }

    @EnvironmentObject var appState: AppState
    
    @AppStorage("qrzUsername") private var qrzUsername = ""
    @State private var qrzPassword = ""
    @State private var qrzCredentialStatus = ""
    @State private var qrzRankAPIToken = ""
    @State private var qrzRankCredentialStatus = ""
    @State private var showSettingsQRZLoginSheet = false

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

    @AppStorage("eqslUsername") private var eqslUsername = ""
    @State private var eqslPassword = ""
    @State private var eqslCredentialStatus = ""

    @AppStorage("wavelogServerURL") private var wavelogServerURL = ""
    @AppStorage("wavelogStationProfileID") private var wavelogStationProfileID = "1"
    @AppStorage("wavelogAutoPushEnabled") private var wavelogAutoPushEnabled = true
    @AppStorage("wavelogLiveRadioBroadcastEnabled") private var wavelogLiveRadioBroadcastEnabled = false
    @State private var wavelogAPIKey = ""
    @State private var wavelogCredentialStatus = ""
    @ObservedObject private var wavelogEngine = WavelogSyncEngine.shared

    @AppStorage("hamqthUsername") private var hamqthUsername = ""
    @State private var hamqthPassword = ""
    @State private var hamqthCredentialStatus = ""
    @AppStorage("hamqthAutoUploadEnabled") private var hamqthAutoUploadEnabled = false

    @AppStorage("hrdlogCallsign") private var hrdlogCallsign = ""
    @State private var hrdlogCode = ""
    @State private var hrdlogCredentialStatus = ""
    @AppStorage("hrdlogAutoUploadEnabled") private var hrdlogAutoUploadEnabled = false
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
            Group {
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

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("2-Factor Authentication (2FA / MFA)")
                            .font(.subheadline.weight(.semibold))

                        if QRZSessionStore.hasSavedSession() {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Active QRZ Session Authenticated")
                                        .font(.caption.bold())
                                        .foregroundColor(.green)
                                    Text("Your 2FA / Web session is active and saved in Keychain.")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Sign Out", role: .destructive) {
                                    QRZSessionStore.clear()
                                    qrzCredentialStatus = "Signed out"
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            }
                            .padding(8)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                        } else {
                            Text("If your QRZ.com account uses 2-Factor Authentication (2FA / MFA) or if you want to sign in directly through the secure WebKit browser, click below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button {
                            if !qrzPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                saveCredential(qrzPassword, as: .qrzPassword, status: $qrzCredentialStatus)
                            }
                            showSettingsQRZLoginSheet = true
                        } label: {
                            Label(
                                QRZSessionStore.hasSavedSession() ? "Verify / Re-authenticate 2FA" : "Log In & Verify 2FA",
                                systemImage: QRZSessionStore.hasSavedSession() ? "arrow.clockwise.circle" : "lock.shield.fill"
                            )
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }
                    
                    Divider()

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

            // MARK: - eQSL.cc Settings Tab
            Form {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "photo.badge.checkmark.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("eQSL.cc Integration & Graphic Card Downloader")
                                .font(.headline)
                            Text("Download electronic QSL status and high-resolution graphical QSL cards")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    TextField("Username / Callsign:", text: $eqslUsername)
                        .textFieldStyle(.roundedBorder)

                    SecureField("New password (blank keeps the saved password):", text: $eqslPassword)
                        .textFieldStyle(.roundedBorder)

                    Label("Stored in macOS Keychain", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            saveCredential(eqslPassword, as: .eqslPassword, status: $eqslCredentialStatus)
                        } label: {
                            Label("Save eQSL Password", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(eqslPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Remove Password", role: .destructive) {
                            removeCredential(.eqslPassword, value: $eqslPassword, status: $eqslCredentialStatus)
                        }

                        credentialStatus(eqslCredentialStatus)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cached QSL Cards Storage")
                            .font(.subheadline.weight(.semibold))

                        Text("Graphic QSL cards downloaded from eQSL are stored locally on your Mac for instant offline viewing.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Button("Open eQSL Cards Folder in Finder") {
                                NSWorkspace.shared.open(EQSLService.shared.cardsDirectoryURL)
                            }
                            .buttonStyle(.bordered)

                            Spacer()
                        }
                    }
                }
                .padding()
            }
            .tabItem {
                Label("eQSL.cc", systemImage: "photo.badge.checkmark.fill")
            }
            .tag(Tabs.eqsl)
            .onAppear {
                eqslPassword = CredentialVault.value(for: .eqslPassword)
            }

            // MARK: - Wavelog / Cloudlog Settings Tab
            Form {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "cloud.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Wavelog & Cloudlog Server Integration")
                                .font(.headline)
                            Text("Connect to your personal or club web logbook server via REST API")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    TextField("Server Base URL (e.g. https://log.myqth.com):", text: $wavelogServerURL)
                        .textFieldStyle(.roundedBorder)

                    SecureField("API Key (saved securely in Keychain):", text: $wavelogAPIKey)
                        .textFieldStyle(.roundedBorder)

                    Label("Stored in macOS Hardware Keychain", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            saveCredential(wavelogAPIKey, as: .wavelogAPIKey, status: $wavelogCredentialStatus)
                            Task {
                                await wavelogEngine.discoverStationProfiles()
                            }
                        } label: {
                            Label("Save Key & Discover Profiles", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(wavelogAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || wavelogServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Remove Key", role: .destructive) {
                            removeCredential(.wavelogAPIKey, value: $wavelogAPIKey, status: $wavelogCredentialStatus)
                        }

                        credentialStatus(wavelogCredentialStatus)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sync Preferences")
                            .font(.subheadline.weight(.semibold))

                        if !wavelogEngine.availableStationProfiles.isEmpty {
                            Picker("Remote Station Profile:", selection: $wavelogStationProfileID) {
                                ForEach(wavelogEngine.availableStationProfiles) { p in
                                    Text("\(p.stationProfileName) (\(p.stationCallsign) - \(p.stationGridsquare))").tag(p.stationID)
                                }
                            }
                        }

                        Toggle("Real-Time Auto-Push QSOs to Server on Save", isOn: $wavelogAutoPushEnabled)
                            .onChange(of: wavelogAutoPushEnabled) { _, val in
                                wavelogEngine.isAutoPushEnabled = val
                            }

                        Toggle("Live Radio Frequency Telemetry Broadcast", isOn: $wavelogLiveRadioBroadcastEnabled)
                            .onChange(of: wavelogLiveRadioBroadcastEnabled) { _, val in
                                wavelogEngine.isLiveRadioBroadcastEnabled = val
                            }

                        HStack {
                            Button {
                                Task {
                                    await wavelogEngine.performFullSync(appState: appState)
                                }
                            } label: {
                                Label("Perform Two-Way Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.bordered)
                            .disabled(wavelogEngine.isSyncing)

                            if wavelogEngine.isSyncing {
                                ProgressView().controlSize(.small)
                            }
                        }

                        Text(wavelogEngine.lastStatusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .tabItem {
                Label("Wavelog", systemImage: "cloud.fill")
            }
            .tag(Tabs.wavelog)
            .onAppear {
                wavelogAPIKey = CredentialVault.value(for: .wavelogAPIKey)
            }
        }

        Group {
            // MARK: - Club Memberships Settings Tab
            Form {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "person.3.sequence.fill")
                            .font(.title2)
                            .foregroundColor(.purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("International Club Memberships")
                                .font(.headline)
                            Text("Manage offline databases for SKCC, CWops, FISTS, LICW, 30MDG, and EPC")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Indexed Members: \(ClubMembershipEngine.shared.totalMembersIndexed.formatted())")
                            .font(.subheadline.bold())

                        Text("Club membership numbers are automatically detected when typing a callsign in Quick Log, and can be inserted into the contest exchange or comment field in 1 click.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Button {
                                Task {
                                    await ClubMembershipEngine.shared.updateAllRosters()
                                }
                            } label: {
                                Label("Update Rosters from Servers Now", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(ClubMembershipEngine.shared.isUpdatingRosters)

                            Button("Open Rosters Folder") {
                                NSWorkspace.shared.open(ClubMembershipEngine.shared.clubDataDirectoryURL)
                            }
                            .buttonStyle(.bordered)
                        }

                        Text(ClubMembershipEngine.shared.statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .tabItem {
                Label("Clubs", systemImage: "person.3.sequence.fill")
            }
            .tag(Tabs.clubs)

            // MARK: - TCI SDR Settings Tab
            Form {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Transceiver Control Interface (TCI)")
                        .font(.headline)

                    Text("High-speed WebSocket telemetry protocol for ExpertSDR2/3 (SunSDR2 / MB1), Thetis (ANAN), SDRUno, and SDR-Console.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        TextField("Host / IP:", text: Binding(
                            get: { TCIClient.shared.host },
                            set: { TCIClient.shared.host = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        TextField("Port:", value: Binding(
                            get: { TCIClient.shared.port },
                            set: { TCIClient.shared.port = $0 }
                        ), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    }

                    HStack {
                        if TCIClient.shared.isConnected {
                            Button("Disconnect from SDR", role: .destructive) {
                                TCIClient.shared.disconnect()
                            }
                            .buttonStyle(.bordered)

                            HStack(spacing: 6) {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                Text("Connected (TCI v\(TCIClient.shared.serverProtocol))")
                                    .font(.caption.bold())
                                    .foregroundColor(.green)
                            }
                        } else {
                            Button {
                                TCIClient.shared.connect()
                            } label: {
                                Label("Connect to TCI Server", systemImage: "antenna.radiowaves.left.and.right")
                            }
                            .buttonStyle(.borderedProminent)

                            Text(TCIClient.shared.statusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            .tabItem {
                Label("TCI (SDR)", systemImage: "antenna.radiowaves.left.and.right")
            }
            .tag(Tabs.tci)

            // MARK: - WinKeyer Hardware Settings Tab
            Form {
                WinKeyerView()
            }
            .tabItem {
                Label("WinKeyer", systemImage: "cable.connector.horizontal")
            }
            .tag(Tabs.winkeyer)

            // MARK: - ON4KST Chat Settings Tab
            Form {
                VStack(alignment: .leading, spacing: 16) {
                    Text("ON4KST Real-Time Propagation & Chat Network")
                        .font(.headline)

                    Text("Global chat rooms for VHF (50/70MHz), UHF (144/432MHz), Microwaves (1.2G-76G), and 160m Low-Band DX skeds.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        TextField("Server Host:", text: Binding(
                            get: { ON4KSTClient.shared.serverHost },
                            set: { ON4KSTClient.shared.serverHost = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)

                        Picker("Default Room:", selection: Binding(
                            get: { ON4KSTClient.shared.selectedRoom },
                            set: { ON4KSTClient.shared.selectedRoom = $0 }
                        )) {
                            ForEach(ON4KSTRoom.allCases) { r in
                                Text(r.title).tag(r)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        if ON4KSTClient.shared.isConnected {
                            Button("Disconnect", role: .destructive) {
                                ON4KSTClient.shared.disconnect()
                            }
                            .buttonStyle(.bordered)

                            HStack(spacing: 6) {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                Text("Connected to \(ON4KSTClient.shared.selectedRoom.title)")
                                    .font(.caption.bold())
                                    .foregroundColor(.green)
                            }
                        } else {
                            Button {
                                let call = appState.activeStationProfile?.callsign ?? "EP2AES"
                                ON4KSTClient.shared.connect(callsign: call)
                            } label: {
                                Label("Connect to ON4KST", systemImage: "bubble.left.and.bubble.right.fill")
                            }
                            .buttonStyle(.borderedProminent)

                            Text(ON4KSTClient.shared.statusMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
            }
            .tabItem {
                Label("ON4KST", systemImage: "bubble.left.and.bubble.right.fill")
            }
            .tag(Tabs.on4kst)

            // MARK: - HRDLog.net Settings Tab
            Form {
                VStack(alignment: .leading, spacing: 16) {
                    Text("HRDLog.net Online Logbook")
                        .font(.headline)

                    Text("Automatic real-time QSO uploads and batch synchronization with HRDLog.net.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Callsign:", text: $hrdlogCallsign)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Upload Code (from HRDLog Profile):", text: $hrdlogCode)
                        .textFieldStyle(.roundedBorder)

                    Label("Stored securely in macOS Keychain", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            saveCredential(hrdlogCode, as: .hrdlogCode, status: $hrdlogCredentialStatus)
                        } label: {
                            Label("Save HRDLog Code", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(hrdlogCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Remove Code", role: .destructive) {
                            removeCredential(.hrdlogCode, value: $hrdlogCode, status: $hrdlogCredentialStatus)
                        }

                        credentialStatus(hrdlogCredentialStatus)
                    }

                    Divider()

                    Toggle("Auto-Upload QSOs on Save (Quick Log & Contest)", isOn: $hrdlogAutoUploadEnabled)

                    HStack {
                        Button {
                            Task {
                                _ = await HRDLogClient.shared.uploadBatch(records: appState.qsoRecords)
                            }
                        } label: {
                            Label("Upload All \(appState.qsoRecords.count) QSOs Now", systemImage: "arrow.up.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(HRDLogClient.shared.isUploading || appState.qsoRecords.isEmpty)

                        if HRDLogClient.shared.isUploading {
                            ProgressView().controlSize(.small)
                        }

                        Text(HRDLogClient.shared.lastUploadStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .tabItem {
                Label("HRDLog", systemImage: "globe.badge.chevron.backward")
            }
            .tag(Tabs.hrdlog)

            // MARK: - HAMQTH Settings Tab
            Form {
                VStack(alignment: .leading, spacing: 16) {
                    Text("HAMQTH Integration & Online Log")
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

                    Divider()

                    Toggle("Auto-Upload QSOs to HamQTH Online Logbook", isOn: $hamqthAutoUploadEnabled)

                    HStack {
                        Button {
                            Task {
                                _ = await HamQTHUploadClient.shared.uploadBatch(records: appState.qsoRecords)
                            }
                        } label: {
                            Label("Upload Log to HamQTH Now", systemImage: "arrow.up.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(HamQTHUploadClient.shared.isUploading || appState.qsoRecords.isEmpty)

                        if HamQTHUploadClient.shared.isUploading {
                            ProgressView().controlSize(.small)
                        }

                        Text(HamQTHUploadClient.shared.lastUploadStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
        }
        .padding(10)
        .onAppear {
            refreshSDRControlPath()
        }
        .sheet(isPresented: $showSettingsClubLogLoginSheet) {
            ClubLogLoginView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $showSettingsQRZLoginSheet) {
            QRZLoginView()
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
