//
//  SettingsView.swift
//  ADIF to Excel
//
//  Created by factoreal on 7/31/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Settings Categories & Navigation Enums
enum SettingsCategory: String, CaseIterable, Identifiable {
    case stationAndHardware = "Station & Hardware"
    case cloudAndLogbooks = "Cloud & QSL Services"
    case syncAndImports = "Log Sync & Imports"
    case safetyAndAI = "Safety & AI"

    var id: String { rawValue }
    var title: String { rawValue }

    var icon: String {
        switch self {
        case .stationAndHardware: return "antenna.radiowaves.left.and.right"
        case .cloudAndLogbooks: return "icloud.fill"
        case .syncAndImports: return "arrow.triangle.2.circlepath"
        case .safetyAndAI: return "shield.lefthalf.filled"
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    // Station & Hardware
    case stations = "stations"
    case bands = "bands"
    case tx500 = "tx500"
    case xiegu6100 = "xiegu6100"
    case tci = "tci"
    case winkeyer = "winkeyer"

    // Cloud & QSL Services
    case qrz = "qrz"
    case qrzRank = "qrzRank"
    case lotw = "lotw"
    case clubLog = "clubLog"
    case eqsl = "eqsl"
    case wavelog = "wavelog"
    case hrdlog = "hrdlog"
    case hamqth = "hamqth"
    case clubs = "clubs"

    // Log Sync & Imports
    case sdrControl = "sdrControl"
    case externalADIF = "externalADIF"
    case on4kst = "on4kst"
    case smtp = "smtp"

    // Safety & AI
    case dataSafety = "dataSafety"
    case antennaWeatherSafety = "antennaWeatherSafety"
    case assistant = "assistant"
    case audioAlerts = "audioAlerts"
    case waitAndPounce = "waitAndPounce"
    case bustedCallsigns = "bustedCallsigns"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stations: return "Station Profiles"
        case .bands: return "Amateur Bands"
        case .tx500: return "Lab599 TX-500"
        case .xiegu6100: return "Xiegu X6100"
        case .tci: return "TCI (ExpertSDR / Thetis)"
        case .winkeyer: return "WinKeyer CW"
        case .qrz: return "QRZ.com"
        case .qrzRank: return "QRZ Logbook Rank"
        case .lotw: return "LoTW (ARRL)"
        case .clubLog: return "Club Log"
        case .eqsl: return "eQSL.cc"
        case .wavelog: return "Wavelog Cloud"
        case .hrdlog: return "HRDLog.net"
        case .hamqth: return "HamQTH"
        case .clubs: return "Clubs & Rosters"
        case .sdrControl: return "SDR-Control (iCloud)"
        case .externalADIF: return "ADIF Live Sync"
        case .on4kst: return "ON4KST DX Chat"
        case .smtp: return "Email (SMTP)"
        case .dataSafety: return "Data Safety & Backups"
        case .antennaWeatherSafety: return "Antenna Weather Radar"
        case .assistant: return "AI Log Assistant"
        case .audioAlerts: return "Voice Alerts & TTS"
        case .waitAndPounce: return "Wait & Pounce (FT8/FT4)"
        case .bustedCallsigns: return "Busted Callsigns & Verification"
        }
    }

    var icon: String {
        switch self {
        case .stations: return "antenna.radiowaves.left.and.right"
        case .bands: return "waveform.path"
        case .tx500: return "bolt.horizontal.fill"
        case .xiegu6100: return "radio.fill"
        case .tci: return "point.3.filled.connected.trianglepath.dotted"
        case .winkeyer: return "cable.connector.horizontal"
        case .qrz: return "globe"
        case .qrzRank: return "trophy.fill"
        case .lotw: return "checkmark.seal.fill"
        case .clubLog: return "leaf.fill"
        case .eqsl: return "envelope.badge.shield.half.filled"
        case .wavelog: return "cloud.fill"
        case .hrdlog: return "globe.badge.chevron.backward"
        case .hamqth: return "person.text.rectangle"
        case .clubs: return "person.3.sequence.fill"
        case .sdrControl: return "ipad.and.iphone"
        case .externalADIF: return "arrow.triangle.2.circlepath.doc.on.clipboard"
        case .on4kst: return "bubble.left.and.bubble.right.fill"
        case .smtp: return "envelope"
        case .dataSafety: return "externaldrive.fill.badge.checkmark"
        case .antennaWeatherSafety: return "bolt.trianglebadge.exclamationmark.fill"
        case .assistant: return "sparkles"
        case .audioAlerts: return "speaker.wave.2.fill"
        case .waitAndPounce: return "scope"
        case .bustedCallsigns: return "shield.lefthalf.filled.badge.checkmark"
        }
    }

    var subtitle: String {
        switch self {
        case .stations: return "Manage QTH locations, grids, callsigns, and antennas"
        case .bands: return "Frequency segments, modes, power limits, and band plans"
        case .tx500: return "CAT control, audio levels, and serial communication"
        case .xiegu6100: return "WiFi telemetry, CI-V over IP, and streaming settings"
        case .tci: return "High-speed WebSocket telemetry for SunSDR2, MB1, and Thetis"
        case .winkeyer: return "K1EL CW keyer hardware configuration and paddle speed"
        case .qrz: return "XML Logbook API credentials, subscription, and 2FA"
        case .qrzRank: return "Real-time world rank telemetry and DX marathon awards"
        case .lotw: return "ARRL Logbook of the World credentials and TQSL .p12 certificates"
        case .clubLog: return "Direct uploads, Super Check Partial rosters, and OQRS"
        case .eqsl: return "Electronic QSL card exchange and automatic confirmation sync"
        case .wavelog: return "Cloud logbook API endpoints, profile keys, and live streaming"
        case .hrdlog: return "Automatic real-time QSO uploads and web logbook sync"
        case .hamqth: return "Free XML callbook lookup and online log synchronization"
        case .clubs: return "Offline membership databases: SKCC, CWops, FISTS, LICW, 30MDG, EPC"
        case .sdrControl: return "iCloud SmartSDR.smartsdrlog sync, FT8 UDP, and offline outbox"
        case .externalADIF: return "Automatic background import from WSJT-X, JTDX, GridTracker, Log4OM"
        case .on4kst: return "VHF/UHF/Microwave/160m real-time propagation chat and DX skeds"
        case .smtp: return "Outgoing mail server configuration for QSL cards and reports"
        case .dataSafety: return "Database integrity checks, automatic backups, and rollback points"
        case .antennaWeatherSafety: return "Live Open-Meteo weather alerts for lightning and gale-force winds"
        case .assistant: return "Local or cloud AI for log diagnostics, advice, and summaries"
        case .audioAlerts: return "Speech synthesis alerts for DX spots, multipliers, and warnings"
        case .waitAndPounce: return "Autonomous DX sniper, QSO completion tracking, and auto-sequence handover"
        case .bustedCallsigns: return "Multi-source SCP/LoTW verification, CW Morse dit/dah and Voice phonetic error correction"
        }
    }

    var category: SettingsCategory {
        switch self {
        case .stations, .bands, .tx500, .xiegu6100, .tci, .winkeyer:
            return .stationAndHardware
        case .qrz, .qrzRank, .lotw, .clubLog, .eqsl, .wavelog, .hrdlog, .hamqth, .clubs:
            return .cloudAndLogbooks
        case .sdrControl, .externalADIF, .on4kst, .smtp:
            return .syncAndImports
        case .dataSafety, .antennaWeatherSafety, .assistant, .audioAlerts, .waitAndPounce, .bustedCallsigns:
            return .safetyAndAI
        }
    }

    var searchKeywords: String {
        "\(title) \(subtitle) \(category.title) \(rawValue) icloud smartsdr ft8 wsjt arrl sniper pounce hunter busted callsign verification scp lotw morse voice phonetics"
    }
}

// MARK: - macOS Preferences & Credentials Settings Sheet
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @AppStorage("settingsSelectedTab") private var selectedTabRaw: String = SettingsTab.stations.rawValue
    @State private var searchText = ""

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
    @AppStorage("lotwStationLocation") private var lotwStationLocation = ""
    @State private var lotwPassword = ""
    @State private var lotwCredentialStatus = ""
    @AppStorage("lotwCertificateContainerPath") private var lotwCertificateContainerPath = ""
    @State private var lotwCertificatePassword = ""
    @State private var lotwCertificateStatus = ""
    @State private var tqslSyncStatus = ""

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
    @ObservedObject private var cloudDaemon = ZeroClickCloudUploadDaemon.shared

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

    private var currentTab: SettingsTab {
        SettingsTab(rawValue: selectedTabRaw) ?? .stations
    }

    private var selectionBinding: Binding<SettingsTab?> {
        Binding(
            get: { currentTab },
            set: { newTab in
                if let newTab {
                    selectedTabRaw = newTab.rawValue
                }
            }
        )
    }

    private var filteredTabs: [SettingsTab] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return SettingsTab.allCases
        }
        return SettingsTab.allCases.filter { tab in
            tab.searchKeywords.lowercased().contains(query)
        }
    }

    var body: some View {
        HSplitView {
            // MARK: - Left Sidebar Navigation Pane
            sidebarPane
                .frame(minWidth: 230, idealWidth: 260, maxWidth: 320)

            // MARK: - Right Detail Content Pane
            detailPane
                .frame(minWidth: 720, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(SettingsWindowConfigurator().frame(width: 0, height: 0))
        .onAppear {
            loadAllCredentialsAndPaths()
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

    // MARK: - Sidebar View
    private var sidebarPane: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("Search settings...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(7)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            // Categorized List
            List(selection: selectionBinding) {
                ForEach(SettingsCategory.allCases) { category in
                    let tabs = filteredTabs.filter { $0.category == category }
                    if !tabs.isEmpty {
                        Section(header: Text(category.title.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)) {
                            ForEach(tabs) { tab in
                                sidebarRow(for: tab)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func sidebarRow(for tab: SettingsTab) -> some View {
        HStack(spacing: 8) {
            tabIcon(for: tab)
                .frame(width: 22)
            Text(tab.title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .tag(tab)
        .onTapGesture {
            selectedTabRaw = tab.rawValue
        }
    }

    @ViewBuilder
    private func tabIcon(for tab: SettingsTab) -> some View {
        switch tab {
        case .tx500:
            Lab599LogoView(height: 11)
        case .bustedCallsigns:
            BustedCallsignIconView(size: 15, isSelected: tab == currentTab)
        default:
            Image(systemName: tab.icon)
                .foregroundColor(tab == currentTab ? Color.accentColor : Color.secondary)
        }
    }

    // MARK: - Detail View
    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                tabHeaderIcon(for: currentTab)
                    .frame(width: 36, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(currentTab.title)
                        .font(.headline)
                    Text(currentTab.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            // Tab Content
            tabContent(for: currentTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func tabHeaderIcon(for tab: SettingsTab) -> some View {
        switch tab {
        case .tx500:
            Lab599LogoView(height: 24)
        case .bustedCallsigns:
            BustedCallsignIconView(size: 26, isSelected: true)
        default:
            Image(systemName: tab.icon)
                .font(.system(size: 22))
                .foregroundColor(.accentColor)
        }
    }

    // MARK: - Tab Content Dispatcher
    @ViewBuilder
    private func tabContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .stations:
            StationProfilesSettingsView()
                .environmentObject(appState)

        case .bands:
            AmateurBandsSettingsView()

        case .tx500:
            Lab599TX500SetupView()

        case .xiegu6100:
            Xiegu6100SetupView()

        case .tci:
            tciView

        case .winkeyer:
            Form {
                WinKeyerView()
            }
            .padding()

        case .qrz:
            qrzView

        case .qrzRank:
            qrzRankView

        case .lotw:
            lotwView

        case .clubLog:
            clubLogView

        case .eqsl:
            eqslView

        case .wavelog:
            wavelogView

        case .hrdlog:
            hrdlogView

        case .hamqth:
            hamqthView

        case .clubs:
            clubsView

        case .sdrControl:
            sdrControlView

        case .externalADIF:
            externalADIFView

        case .on4kst:
            on4kstView

        case .smtp:
            SMTPSettingsView(embeddedInSettings: true)

        case .dataSafety:
            DataSafetySettingsView()
                .environmentObject(appState)

        case .antennaWeatherSafety:
            AntennaWeatherSafetySettingsView()

        case .assistant:
            assistantView

        case .audioAlerts:
            ScrollView {
                AudioAlertSettingsView()
                    .padding()
            }

        case .waitAndPounce:
            waitAndPounceSettingsView

        case .bustedCallsigns:
            BustedCallsignDatabaseManagerView()
        }
    }

    // MARK: - Wait & Pounce Settings Form
    private var waitAndPounceSettingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header & Info
                HStack(spacing: 12) {
                    Image(systemName: "scope")
                        .font(.system(size: 28))
                        .foregroundColor(.red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Autonomous Wait & Pounce (W&P) Engine")
                            .font(.title3)
                            .bold()
                        Text("Track DX stations in ongoing QSOs, detect RR73/73 completion, and snipe on the next slot boundary.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 4)

                Divider()

                // Master Toggle & Hunter Mode
                GroupBox(label: Label("Hunting Strategy & Target Selection", systemImage: "target")) {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Enable Wait & Pounce Engine", isOn: Binding(
                            get: { WaitAndPounceEngine.shared.isEnabled },
                            set: { WaitAndPounceEngine.shared.isEnabled = $0 }
                        ))
                        .fontWeight(.semibold)

                        Picker("Target Acquisition Mode", selection: Binding(
                            get: { WaitAndPounceEngine.shared.huntMode },
                            set: { WaitAndPounceEngine.shared.huntMode = $0 }
                        )) {
                            ForEach(TargetHuntMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode.iconName).tag(mode)
                            }
                        }

                        Picker("Transmit Frequency Strategy", selection: Binding(
                            get: { WaitAndPounceEngine.shared.frequencyMode },
                            set: { WaitAndPounceEngine.shared.frequencyMode = $0 }
                        )) {
                            ForEach(PounceFrequencyMode.allCases) { fq in
                                Text(fq.rawValue).tag(fq)
                            }
                        }

                        if WaitAndPounceEngine.shared.frequencyMode == .autoClearSplit {
                            HStack {
                                Text("Preferred Split Audio Offset:")
                                    .foregroundColor(.secondary)
                                TextField("Hz", value: Binding(
                                    get: { WaitAndPounceEngine.shared.splitAudioOffsetHz },
                                    set: { WaitAndPounceEngine.shared.splitAudioOffsetHz = $0 }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                Text("Hz (Avoids Simplex QRM pileups)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(8)
                }

                // Safety & Guardrails
                GroupBox(label: Label("Amateur Radio Safety & Retry Limits", systemImage: "shield.lefthalf.filled")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Maximum Calling Retries:")
                            Spacer()
                            Text("\(WaitAndPounceEngine.shared.maxAttempts) attempts")
                                .bold()
                            Stepper("", value: Binding(
                                get: { WaitAndPounceEngine.shared.maxAttempts },
                                set: { WaitAndPounceEngine.shared.maxAttempts = $0 }
                            ), in: 1...5)
                            .labelsHidden()
                        }
                        Text("Enforces amateur radio etiquette. If the target station does not respond within this limit, transmission is automatically disarmed to avoid frequency congestion.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        Toggle("Voice Announcements for W&P Events", isOn: Binding(
                            get: { WaitAndPounceEngine.shared.voiceAnnouncementsEnabled },
                            set: { WaitAndPounceEngine.shared.voiceAnnouncementsEnabled = $0 }
                        ))
                        Text("Announces target acquisition, armed state, and QSO engagement using macOS Speech Synthesis.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                // Watchlist Manager
                GroupBox(label: Label("Manual Watchlist & ATNO Hunter", systemImage: "list.star")) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Enter comma-separated callsigns to track whenever they appear on the band:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("e.g. 3Y0J, VK0AW, DP0GVN, FT4YM", text: Binding(
                            get: { WaitAndPounceEngine.shared.watchlistText },
                            set: { WaitAndPounceEngine.shared.watchlistText = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    }
                    .padding(8)
                }

                Spacer()
            }
            .padding(20)
        }
    }

    // MARK: - QRZ.com Settings Form
    private var qrzView: some View {
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

                VStack(alignment: .leading, spacing: 10) {
                    Text("Bulk Email & Contact Enrichment")
                        .font(.subheadline.weight(.semibold))

                    Text("Enrich all contacts across your Master Log with email addresses and names from QRZ.com / HAMQTH in a controlled batch process.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        if !appState.isBulkQRZEnriching {
                            appState.bulkQRZCompleted = false
                        }
                        appState.showBulkQRZEnrichmentSheet = true
                    } label: {
                        Label("Enrich All Contacts (QRZ)...", systemImage: "sparkles.rectangle.stack")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(appState.qsoRecords.isEmpty || appState.isEnriching)
                }

                Divider()

                Label("The QRZ Logbook API key is stored per station under the Stations tab. The account password remains shared for QRZ login and Awards.", systemImage: "key.horizontal.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }

    // MARK: - QRZ Rank Form
    private var qrzRankView: some View {
        Form {
            VStack(alignment: .leading, spacing: 16) {
                Text("QRZ Rank API")
                    .font(.headline)

                SecureField("Personal API token (blank keeps the saved token):", text: $qrzRankAPIToken)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    if !CredentialVault.value(for: .qrzRankAPIToken).isEmpty {
                        Label("API token saved in Keychain", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("No API token saved yet", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

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
    }

    // MARK: - Club Log Form
    private var clubLogView: some View {
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
    }

    // MARK: - LoTW Form
    private var lotwView: some View {
        Form {
            VStack(alignment: .leading, spacing: 16) {
                Text("Logbook of The World (LoTW)")
                    .font(.headline)

                TextField("Username:", text: $lotwUsername)
                    .textFieldStyle(.roundedBorder)

                SecureField("New password (blank keeps the saved password):", text: $lotwPassword)
                    .textFieldStyle(.roundedBorder)

                TextField("Default Station Location (e.g. EP2AES-Home):", text: $lotwStationLocation)
                    .textFieldStyle(.roundedBorder)

                Text("Station Location name defined in TQSL for this callsign (also synced with active Station Profile).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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

                HStack(spacing: 12) {
                    Button {
                        let outcome = TQSLService.synchronizeTQSLStorage()
                        tqslSyncStatus = outcome.message
                    } label: {
                        Label("Sync TQSL Data (~/.tqsl)", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)

                    if !tqslSyncStatus.isEmpty {
                        Text(tqslSyncStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
    }

    // MARK: - eQSL Form
    private var eqslView: some View {
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
    }

    // MARK: - Wavelog Form
    private var wavelogView: some View {
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

                    if let wavelogError = wavelogEngine.lastError {
                        Text(wavelogError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Club Memberships Form
    private var clubsView: some View {
        Form {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.title2)
                        .foregroundColor(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Amateur Radio Club Roster Databases")
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
    }

    // MARK: - TCI SDR Settings Form
    private var tciView: some View {
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
    }

    // MARK: - ON4KST DX Chat Form
    private var on4kstView: some View {
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
    }

    // MARK: - HRDLog.net Form
    private var hrdlogView: some View {
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
    }

    // MARK: - HAMQTH Form
    private var hamqthView: some View {
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
    }

    // MARK: - AI Log Assistant Form
    private var assistantView: some View {
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
    }

    // MARK: - External ADIF Sync Form
    private var externalADIFView: some View {
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
    }

    // MARK: - SDR-Control iCloud Log Form
    private var sdrControlView: some View {
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

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Zero-Click Cloud Outbox", systemImage: "icloud.and.arrow.up.fill")
                            .font(.subheadline.bold())
                        Spacer()
                        HStack(spacing: 5) {
                            Circle()
                                .fill(cloudDaemon.isNetworkConnected ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(cloudDaemon.isNetworkConnected ? "Network Online" : "Network Offline")
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        if cloudDaemon.pendingQueueCount > 0 {
                            Label("\(cloudDaemon.pendingQueueCount) QSO(s) awaiting cloud upload", systemImage: "tray.full.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Label("Outbox queue is empty", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }

                        Spacer()

                        if cloudDaemon.pendingQueueCount > 0 {
                            Button("Upload Outbox Now") {
                                cloudDaemon.flushNow()
                            }
                            .disabled(!cloudDaemon.isNetworkConnected || cloudDaemon.isFlushingQueue)
                        }
                    }

                    Text("New contacts upload to enabled services that are configured. Network failures wait in the outbox; uploads logged while Touch ID is locked are checked after unlock. Older requests and rejected uploads remain available for manual retry.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }

    // MARK: - Credential & Path Helpers
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

    private func loadAllCredentialsAndPaths() {
        clubLogPassword = CredentialVault.value(for: .clubLogPassword)
        clubLogAPIKey = CredentialVault.value(for: .clubLogAPIKey)
        eqslPassword = CredentialVault.value(for: .eqslPassword)
        wavelogAPIKey = CredentialVault.value(for: .wavelogAPIKey)
        refreshSDRControlPath()
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

// MARK: - Settings Window Toolbar & Frame Configurator
private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window)
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.toolbar?.sizeMode = .small

        let targetWidth: CGFloat = 1280
        let targetHeight: CGFloat = 740
        window.contentMinSize = NSSize(width: 1080, height: 620)

        if window.frame.width < targetWidth || window.frame.height < targetHeight {
            var newFrame = window.frame
            let widthDiff = max(0, targetWidth - newFrame.width)
            let heightDiff = max(0, targetHeight - newFrame.height)
            newFrame.origin.x = max(0, newFrame.origin.x - widthDiff / 2)
            newFrame.origin.y = max(0, newFrame.origin.y - heightDiff / 2)
            newFrame.size.width = max(newFrame.size.width, targetWidth)
            newFrame.size.height = max(newFrame.size.height, targetHeight)
            window.setFrame(newFrame, display: true, animate: false)
        }
    }
}

// MARK: - Antenna & Station Weather Safety Settings
struct AntennaWeatherSafetySettingsView: View {
    @ObservedObject private var engine = StationWeatherSafetyEngine.shared
    @AppStorage("weatherRadarEnabled") private var weatherRadarEnabled = true
    @AppStorage("weatherAudioAlertsEnabled") private var weatherAudioAlertsEnabled = true
    @AppStorage("weatherHighWindThreshold") private var weatherHighWindThreshold: Double = 50.0

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Station Weather & Antenna Safety Radar")
                            .font(.headline)
                        Text("Monitors live atmospheric telemetry to prevent lightning strikes, coaxial cable ESD arcing, and wind load damage to Yagi antennas and masts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Master Toggle
                Toggle("Enable Live Atmospheric Radar", isOn: $weatherRadarEnabled)
                    .font(.body.weight(.medium))

                if weatherRadarEnabled {
                    // Audio warning toggle
                    Toggle("Voice Alert on Severe Weather / Lightning Threats", isOn: $weatherAudioAlertsEnabled)
                        .font(.body)

                    // Wind threshold slider
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("High Wind Alert Threshold:")
                            Spacer()
                            Text("\(Int(weatherHighWindThreshold)) km/h")
                                .font(.body.monospacedDigit().bold())
                        }
                        Slider(value: $weatherHighWindThreshold, in: 25...120, step: 5)
                        Text("Triggers warning when wind gusts threaten directional HF Yagi beams or vertical antennas.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Live Status Card
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Active Station QTH:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(engine.resolvedGrid.isEmpty ? "No Grid Set" : engine.resolvedGrid)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Threat Level:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(engine.threatLevel.color)
                                    .frame(width: 8, height: 8)
                                Text(engine.threatLevel.rawValue)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(engine.threatLevel.color)
                            }
                        }

                        Spacer()

                        Button {
                            Task {
                                await engine.refresh()
                            }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .controlSize(.small)
                        .disabled(engine.isFetching)
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                }

                // Audio Test Button
                HStack {
                    Button {
                        engine.speak(message: "Warning. Severe lightning or thunderstorm hazard detected at your station locator. Disconnect antenna coaxial cables immediately.")
                    } label: {
                        Label("Test Voice Warning Announcement", systemImage: "speaker.wave.2.fill")
                    }
                    .controlSize(.small)

                    Spacer()

                    Text("Weather telemetry powered by Open-Meteo REST API (No API key needed)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
}
