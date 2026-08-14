//
//  SettingsView.swift
//  ADIF to Excel
//
//  Created by factoreal on 7/31/26.
//

import SwiftUI

// MARK: - macOS Preferences & Credentials Settings Sheet
struct SettingsView: View {
    private enum Tabs: Hashable {
        case general, qrz, lotw, hamqth, smtp, externalADIF, sdrControl
    }

    @EnvironmentObject var appState: AppState
    
    @AppStorage("operatorCallsign") private var operatorCallsign = ""
    @AppStorage("stationGrid") private var stationGrid = ""
    @AppStorage("radioModel") private var radioModel = ""
    @AppStorage("radioPowerWatts") private var radioPowerWatts = 100
    @AppStorage("antennaDescription") private var antennaDescription = ""
    @AppStorage("antennaHeightMeters") private var antennaHeightMeters = 10
    
    @AppStorage("qrzUsername") private var qrzUsername = ""
    @AppStorage("qrzPassword") private var qrzPassword = ""
    @AppStorage("qrzApiKey") private var qrzApiKey = ""
    
    @AppStorage("lotwUsername") private var lotwUsername = ""
    @AppStorage("lotwPassword") private var lotwPassword = ""
    @AppStorage("hamqthUsername") private var hamqthUsername = ""
    @AppStorage("hamqthPassword") private var hamqthPassword = ""
    @AppStorage("externalADIFLogPath") private var externalADIFLogPath = ""
    @AppStorage("externalADIFAutoSyncEnabled") private var externalADIFAutoSyncEnabled = false
    @AppStorage("externalADIFSyncIntervalMinutes") private var externalADIFSyncIntervalMinutes = 15.0
    @AppStorage("sdrControlLogbookPath") private var sdrControlLogbookPath = ""
    @AppStorage("sdrControlPeriodicSyncEnabled") private var sdrControlPeriodicSyncEnabled = false
    @AppStorage("sdrControlPeriodicSyncIntervalMinutes") private var sdrControlPeriodicSyncIntervalMinutes = 15.0

    var body: some View {
        TabView {
            // MARK: - General Settings Tab
            Form {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Station Details")
                        .font(.headline)
                    TextField("My Callsign:", text: $operatorCallsign)
                        .textFieldStyle(.roundedBorder)

                    TextField("Grid Locator:", text: $stationGrid)
                        .textFieldStyle(.roundedBorder)

                    Divider()

                    Text("Radio & Antenna")
                        .font(.headline)

                    TextField("Radio model:", text: $radioModel)
                        .textFieldStyle(.roundedBorder)

                    Stepper("Power: \(radioPowerWatts) W", value: $radioPowerWatts, in: 1...1500, step: 5)

                    TextField("Antenna:", text: $antennaDescription)
                        .textFieldStyle(.roundedBorder)

                    Stepper("Antenna height: \(antennaHeightMeters) m", value: $antennaHeightMeters, in: 1...80, step: 1)
                    
                    Text("These values improve DX Advisor recommendations and will be used by future VOACAP-style prediction logic.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            .tag(Tabs.general)
            
            // MARK: - QRZ.com Settings Tab
            Form {
                VStack(alignment: .leading, spacing: 16) {
                    Text("QRZ.com Integration")
                        .font(.headline)
                    
                    TextField("Username:", text: $qrzUsername)
                        .textFieldStyle(.roundedBorder)
                    
                    SecureField("Password:", text: $qrzPassword)
                        .textFieldStyle(.roundedBorder)
                    
                    Divider()
                    
                    TextField("XML API Key:", text: $qrzApiKey)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("The API Key is used to fetch QRZ Logbook confirmations via the QRZ Logbook API. LoTW confirmations still use the LoTW tab credentials.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .tabItem {
                Label("QRZ.com", systemImage: "q.circle.fill")
            }
            .tag(Tabs.qrz)
            
            // MARK: - LoTW Settings Tab
            Form {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Logbook of The World (LoTW)")
                        .font(.headline)
                    
                    TextField("Username:", text: $lotwUsername)
                        .textFieldStyle(.roundedBorder)
                    
                    SecureField("Password:", text: $lotwPassword)
                        .textFieldStyle(.roundedBorder)
                    
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

                    SecureField("Password:", text: $hamqthPassword)
                        .textFieldStyle(.roundedBorder)

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

    private var resolvedExternalADIFPath: String {
        if !externalADIFLogPath.isEmpty {
            return externalADIFLogPath
        }

        return UserDefaults.standard.string(forKey: "sdrControlLogPath") ?? ""
    }

    private var resolvedSDRControlLogbookPath: String {
        sdrControlLogbookPath
    }

    private func refreshSDRControlPath() {
        sdrControlLogbookPath = UserDefaults.standard.string(forKey: "sdrControlLogbookPath") ?? ""
    }
}
