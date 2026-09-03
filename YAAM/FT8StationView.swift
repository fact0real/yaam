//
//  FT8StationView.swift
//  YAAM
//

import SwiftUI
import FT8808Engine

struct FT8StationView: View {
    private static let utcTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let localTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    @EnvironmentObject private var appState: AppState
    @ObservedObject var engine: FT8EngineService
    @ObservedObject var radio: IcomNetworkRadio
    @ObservedObject var rig: RigControlClient

    @AppStorage("icomNetworkHost") private var icomHost = ""
    @AppStorage("icomNetworkControlPort") private var icomPort = 50_001
    @AppStorage("icomNetworkUsername") private var icomUsername = ""
    @AppStorage("icomNetworkClientName") private var icomClientName = "YAAM"
    @AppStorage("icomNetworkModel") private var icomModelName = IcomNetworkModel.ic705.rawValue
    @AppStorage("ft8InputDeviceUID") private var inputDeviceUID = ""
    @AppStorage("ft8OutputDeviceUID") private var outputDeviceUID = ""

    @State private var icomPassword = ""
    @State private var isPasswordVisible = false
    @State private var credentialStatus = ""
    @State private var showHardwareSettings = false
    @State private var selectedTxMessageIndex = 1

    private var icomModel: Binding<IcomNetworkModel> {
        Binding(
            get: { IcomNetworkModel(rawValue: icomModelName) ?? .ic705 },
            set: { icomModelName = $0.rawValue }
        )
    }

    private var radioPathConnected: Bool {
        engine.audioPath == .icomLAN ? radio.state.isConnected : rig.state.isConnected
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Top Professional Control Ribbon
            topControlRibbon
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // 2. Radio Connection Panel (Prominently visible when disconnected or when toggled)
            if showHardwareSettings || !radioPathConnected {
                radioConnectionPanel
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                Divider()
            }

            // 3. Smart Auto-Hunter AI HUD Ribbon
            autoHunterHUD
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.04))

            stationAlertBanners

            Divider()

            // 4. SDR-Control Style RF Spectrum & Color Waterfall Display
            FT8SpectrumWaterfallView(
                engine: engine,
                onSelectRxFrequency: { freq in
                    engine.rxAudioFrequencyHz = freq
                    if engine.lockTxRxFreq {
                        engine.txAudioFrequencyHz = freq
                    }
                },
                onSelectTxFrequency: { freq in
                    engine.txAudioFrequencyHz = freq
                    if engine.lockTxRxFreq {
                        engine.rxAudioFrequencyHz = freq
                    }
                }
            )
            .frame(height: 220)
            .background(Color.black)

            Divider()

            // 5. Dual-Pane Decoded Signal Windows (Band Activity vs Rx Frequency)
            dualPaneConsole
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // 6. Bottom Status Bar
            bottomStatusBar
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        }
        .onAppear {
            loadIdentity()
            engine.refreshAudioDevices()
            if icomPassword.isEmpty {
                icomPassword = CredentialVault.valueIfAvailableWithoutPrompt(for: .icomNetworkPassword)
            }
        }
        .onChange(of: appState.activeStationProfileID) { _, _ in loadIdentity() }
        .onChange(of: engine.audioPath) { _, _ in engine.stopMonitoring() }
        .onChange(of: radio.state) { _, state in
            if !state.isConnected, engine.audioPath == .icomLAN { engine.stopMonitoring() }
        }
    }

    // MARK: - Station Alert Banners (Opportunities & Clock Drift)
    @ViewBuilder
    private var stationAlertBanners: some View {
        if let opp = engine.latestOpportunityAlert {
            HStack(spacing: 8) {
                Image(systemName: opp.isNewDXCC ? "star.circle.fill" : "mappin.and.ellipse")
                    .foregroundStyle(opp.isNewDXCC ? Color.yellow : Color.green)
                    .font(.system(size: 14, weight: .bold))
                Text(opp.isNewDXCC ? "🌟 NEW DXCC ENTITY:" : "📍 NEW GRID SQUARE:")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(opp.isNewDXCC ? Color.orange : Color.green)
                Text("\(opp.flag) \(opp.callsign) (\(opp.entityName) · \(opp.grid)) calling CQ on \(Int(opp.frequencyHz)) Hz (\(Int(opp.snrDb)) dB)")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button {
                    engine.answerOpportunity(opp)
                } label: {
                    Label("Call Now", systemImage: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(opp.isNewDXCC ? .orange : .green)
                .controlSize(.small)

                Button {
                    engine.dismissOpportunityAlert()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background((opp.isNewDXCC ? Color.orange : Color.green).opacity(0.16))
            Divider()
        }

        if let skew = engine.clockSkewAlert {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 13))
                Text(skew)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.red)
                Spacer()
                Button("Copy NTP Sync Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("sudo sntp -sS time.apple.com", forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.red.opacity(0.12))
            Divider()
        }

        if !radio.activeRemoteSettingsSummary.isEmpty && engine.audioPath == .icomLAN && radio.state.isConnected {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.blue)
                    .font(.system(size: 12))
                Text(radio.activeRemoteSettingsSummary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("Auto-reverts on disconnect")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.08))
            Divider()
        }
    }

    // MARK: - 1. Top Control Ribbon

    private var topControlRibbon: some View {
        HStack(spacing: 10) {
            // Radio Connection Setup Toggle Button
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showHardwareSettings.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(radioPathConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text(radioPathConnected ? (engine.audioPath == .icomLAN ? "Icom LAN" : "rigctld") : "Connect Radio...")
                        .font(.caption.weight(.bold))
                    Image(systemName: (showHardwareSettings || !radioPathConnected) ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .tint(radioPathConnected ? .green : .orange)
            .help("Open / Close Radio Connection settings")

            // RX Switch Button (Redesigned matching TX)
            Button {
                if engine.state.isMonitoring {
                    engine.stopMonitoring()
                } else if engine.audioPath == .icomLAN {
                    engine.startIcomMonitoring(radio: radio)
                } else {
                    engine.startCoreAudioMonitoring(
                        rig: rig,
                        inputDevice: inputDeviceUID,
                        outputDevice: outputDeviceUID
                    )
                }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(engine.state.isMonitoring ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Image(systemName: engine.state.isMonitoring ? "waveform" : "waveform.slash")
                        .font(.system(size: 11, weight: .bold))
                    Text("RX")
                        .font(.system(size: 12, weight: .heavy))
                }
                .frame(width: 60, height: 28)
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.state.isMonitoring ? Color.green : Color.secondary.opacity(0.25))
            .disabled(!radioPathConnected && !engine.state.isMonitoring)
            .help(radioPathConnected ? "Start / Stop receiving FT8 audio" : "Connect the radio first before starting receive")

            // Band Presets Picker
            Picker("Band", selection: $engine.dialFrequencyHz) {
                ForEach(FT8BandPreset.common) { preset in
                    Text(preset.band).tag(preset.frequencyHz)
                }
            }
            .frame(width: 75)
            .labelsHidden()
            .onChange(of: engine.dialFrequencyHz) { _, _ in
                engine.applyDialAndMode()
            }

            Text(engine.formattedDial)
                .font(.system(.body, design: .monospaced).weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

            // Auto-Sequence Toggle
            Toggle("Auto", isOn: $engine.autoSequenceEnabled)
                .toggleStyle(.button)
                .buttonStyle(.bordered)
                .tint(engine.autoSequenceEnabled ? Color.accentColor : Color.secondary)
                .help("Automatically progress through FT8 QSO sequence")

            // Erase Tables Button
            Button {
                engine.clearDecodes()
                engine.clearRxStream()
            } label: {
                Label("Erase", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .help("Clear both Band Activity and Rx Stream")

            Spacer()

            // TX Armed Button (Redesigned matching RX)
            Button {
                engine.transmitArmed.toggle()
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(engine.transmitArmed ? Color.red : Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Image(systemName: engine.transmitArmed ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 11, weight: .bold))
                    Text("TX")
                        .font(.system(size: 12, weight: .heavy))
                }
                .frame(width: 60, height: 28)
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.transmitArmed ? Color.red : Color.secondary.opacity(0.25))
            .help("Arm / Disarm RF Transmission")

            // Slot Parity Button (1st :00/:30 or 2nd :15/:45)
            Button {
                engine.txParity = engine.txParity.toggled
            } label: {
                Text(engine.txParity == .even ? "1st (:00)" : "2nd (:15)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 65, height: 26)
            }
            .buttonStyle(.bordered)
            .help("Toggle transmission slot between 1st (00/30s) and 2nd (15/45s)")

            // Audio Frequencies & Sync
            HStack(spacing: 4) {
                Text("RX:")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.green)
                Text("\(Int(engine.rxAudioFrequencyHz))")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .frame(width: 42)

                Button("=TX") { engine.syncRxToTx() }
                    .buttonStyle(.borderless)
                    .font(.caption2.weight(.bold))
                    .help("Set RX audio frequency equal to TX")

                Divider().frame(height: 16)

                Text("TX:")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.red)
                Text("\(Int(engine.txAudioFrequencyHz))")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .frame(width: 42)

                Button("=RX") { engine.syncTxToRx() }
                    .buttonStyle(.borderless)
                    .font(.caption2.weight(.bold))
                    .help("Set TX audio frequency equal to RX")

                Button {
                    engine.lockTxRxFreq.toggle()
                } label: {
                    Image(systemName: engine.lockTxRxFreq ? "lock.fill" : "lock.open")
                        .font(.caption)
                        .foregroundStyle(engine.lockTxRxFreq ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help("Lock RX and TX frequencies together")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))

            // DX Station & Report
            HStack(spacing: 6) {
                TextField("DX", text: $engine.dxCall)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 76)
                    .font(.system(.caption, design: .monospaced).weight(.bold))

                TextField("Rep", text: $engine.dxReport)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 46)
                    .font(.system(.caption, design: .monospaced))
            }

            // Continuous CQ Toggle Button
            Button {
                if engine.isCallingCQContinually {
                    engine.stopContinuousCQ()
                } else {
                    engine.startContinuousCQ()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: engine.isCallingCQContinually ? "repeat.circle.fill" : "megaphone")
                    Text("CQ")
                }
                .font(.caption.weight(.bold))
                .frame(width: 56, height: 26)
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isCallingCQContinually ? Color.orange : Color.accentColor)
            .help(engine.isCallingCQContinually ? "Stop Continuous CQ Loop" : "Start Continuous CQ (calls CQ indefinitely until answered)")

            // Standard Message Selector (Tx 1 .. Tx 6)
            Menu {
                ForEach(1...6, id: \.self) { idx in
                    Button("Tx \(idx): \(engine.generateStandardMessage(index: idx))") {
                        selectedTxMessageIndex = idx
                        engine.setTxMessageIndex(idx)
                    }
                }
            } label: {
                Text("Tx \(selectedTxMessageIndex)")
                    .font(.caption.weight(.semibold))
                    .frame(width: 46)
            }
            .menuStyle(.borderedButton)

            // Manual / Auto Log Button
            Button {
                if !engine.dxCall.isEmpty {
                    let currentBand = FT8BandPreset.common.first(where: { $0.frequencyHz == engine.dialFrequencyHz })?.band ?? "20m"
                    let dialMHz = Double(engine.dialFrequencyHz) / 1_000_000.0
                    appState.logFT8StationQSO(
                        call: engine.dxCall,
                        grid: engine.dxGrid,
                        sentRST: engine.dxReport,
                        rcvdRST: "-10",
                        band: currentBand,
                        freqMHz: dialMHz
                    )
                }
            } label: {
                Label("LOG", systemImage: "square.and.pencil")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.bordered)
            .disabled(engine.dxCall.isEmpty)
            .help("Log current QSO to YAAM Log Table")
        }
    }

    // MARK: - 2. Prominent Radio Connection Panel

    private var radioConnectionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("Radio & Audio Connection Setup", systemImage: "cable.connector.horizontal")
                    .font(.subheadline.weight(.bold))

                Picker("Path", selection: $engine.audioPath) {
                    ForEach(FT8AudioPath.allCases) { path in Text(path.rawValue).tag(path) }
                }
                .pickerStyle(.segmented)
                .frame(width: 270)

                Spacer()

                HStack(spacing: 8) {
                    Text("Station: \(engine.myCall.isEmpty ? "No Call" : engine.myCall)")
                        .font(.caption.monospacedDigit().weight(.bold))
                    Text("Grid: \(engine.myGrid.isEmpty ? "----" : engine.myGrid)")
                        .font(.caption.monospacedDigit().weight(.bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))

                if radioPathConnected {
                    Button {
                        withAnimation { showHardwareSettings = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Dismiss connection panel")
                }
            }

            if engine.audioPath == .icomLAN {
                icomSettings
            } else {
                coreAudioSettings
            }

            // Live Diagnostic Status & Error Banner
            if !radio.lastMessage.isEmpty {
                HStack(spacing: 8) {
                    if radio.state.isTransitioning {
                        ProgressView().controlSize(.mini)
                    } else if radio.state.isFailed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    } else if radio.state.isConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }

                    Text(radio.lastMessage)
                        .font(.caption)
                        .foregroundStyle(radio.state.isFailed ? Color.red : Color.primary)
                        .textSelection(.enabled)

                    Spacer()

                    if !credentialStatus.isEmpty {
                        Text(credentialStatus)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(credentialStatus.contains("Saved") ? Color.green : Color.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    radio.state.isFailed
                        ? Color.red.opacity(0.12)
                        : (radio.state.isConnected ? Color.green.opacity(0.10) : Color.secondary.opacity(0.08)),
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }
        }
    }

    private var icomSettings: some View {
        HStack(alignment: .bottom, spacing: 10) {
            field("Radio Model", width: 140) {
                Picker("Radio", selection: icomModel) {
                    ForEach(IcomNetworkModel.allCases) { model in Text(model.rawValue).tag(model) }
                }
                .labelsHidden()
            }
            field("IP Address / Host", width: 150) {
                TextField("192.168.1.120", text: $icomHost).textFieldStyle(.roundedBorder)
            }
            field("Port", width: 80) {
                TextField("50001", value: $icomPort, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
            }
            field("Username", width: 120) {
                TextField("Username", text: $icomUsername).textFieldStyle(.roundedBorder)
            }
            field("Password", width: 160) {
                HStack(spacing: 4) {
                    if isPasswordVisible {
                        TextField("Password", text: $icomPassword)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("Password", text: $icomPassword)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(isPasswordVisible ? "Hide password" : "Show password")

                    Button {
                        savePassword()
                    } label: {
                        Image(systemName: "key.fill")
                            .font(.caption2)
                            .foregroundStyle(credentialStatus.contains("Saved") ? Color.green : Color.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Save password in macOS Keychain")
                }
            }

            Button { toggleIcomConnection() } label: {
                Label(icomConnectionButtonTitle, systemImage: icomConnectionButtonIcon)
            }
            .buttonStyle(.borderedProminent)
            .tint(radio.state.canDisconnect ? .secondary : .blue)

            Spacer()

            statusPill(
                radio.state.isConnected ? "Connected to \(radio.radioName.isEmpty ? "Icom LAN" : radio.radioName)" : (radio.state.isTransitioning ? "Connecting..." : (radio.state.isFailed ? "Failed" : "Not Connected")),
                active: radio.state.isConnected
            )
        }
    }

    private var coreAudioSettings: some View {
        HStack(alignment: .bottom, spacing: 12) {
            field("Input Audio", width: 230) {
                Picker("Input", selection: $inputDeviceUID) {
                    Text("System Default").tag("")
                    ForEach(engine.inputDevices) { d in Text(d.name).tag(d.uid) }
                }
                .labelsHidden()
            }
            field("Output Audio", width: 230) {
                Picker("Output", selection: $outputDeviceUID) {
                    Text("System Default").tag("")
                    ForEach(engine.outputDevices) { d in Text(d.name).tag(d.uid) }
                }
                .labelsHidden()
            }
            Button { engine.refreshAudioDevices() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh Core Audio Devices")

            Spacer()

            statusPill(rig.state.isConnected ? "rigctld Connected" : "rigctld Disconnected", active: rig.state.isConnected)
        }
    }

    private var icomConnectionButtonTitle: String {
        if radio.state.isTransitioning { return "Cancel" }
        return radio.state.isConnected ? "Disconnect" : "Connect"
    }

    private var icomConnectionButtonIcon: String {
        radio.state.canDisconnect ? "xmark.circle" : "network"
    }

    private func toggleIcomConnection() {
        if radio.state.canDisconnect {
            engine.stopMonitoring()
            radio.disconnect()
            return
        }
        let cleanHost = icomHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = icomUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPass = icomPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleanPass.isEmpty {
            _ = CredentialVault.set(cleanPass, for: .icomNetworkPassword)
        }

        radio.connect(
            settings: IcomNetworkSettings(
                host: cleanHost,
                controlPort: icomPort,
                username: cleanUser,
                clientName: icomClientName,
                model: icomModel.wrappedValue
            ),
            password: cleanPass
        )
    }

    private func savePassword() {
        credentialStatus = CredentialVault.set(icomPassword, for: .icomNetworkPassword)
            ? "Saved in Keychain"
            : "Could not save"
    }

    private func statusPill(_ text: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Circle().fill(active ? Color.green : Color.orange).frame(width: 6, height: 6)
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1), in: Capsule())
    }

    // MARK: - 3. Smart Auto-Hunter HUD

    private var autoHunterHUD: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $engine.autoHunterEnabled) {
                HStack(spacing: 5) {
                    Image(systemName: "target")
                        .foregroundStyle(engine.autoHunterEnabled ? .red : .secondary)
                    Text("Auto-Hunter")
                        .font(.caption.weight(.bold))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Picker("Criteria", selection: $engine.autoHunterCriteria) {
                ForEach(SmartHunterCriteria.allCases) { c in
                    Label(c.rawValue, systemImage: c.icon).tag(c)
                }
            }
            .frame(width: 200)
            .controlSize(.small)

            HStack(spacing: 4) {
                Text("Min SNR:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Stepper("\(engine.autoHunterMinSNR) dB", value: $engine.autoHunterMinSNR, in: -26...0, step: 1)
                    .font(.caption2.monospacedDigit())
            }

            Toggle("Skip Worked B4", isOn: $engine.autoHunterSkipWorked)
                .font(.caption2)
                .controlSize(.small)

            Divider().frame(height: 16)

            Text(engine.autoHunterStatus)
                .font(.caption2)
                .foregroundStyle(engine.autoHunterEnabled ? Color.primary : Color.secondary)
                .lineLimit(1)

            Spacer()

            if engine.autoHunterEnabled {
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    Text("ACTIVE")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.12), in: Capsule())
            }
        }
    }

    // MARK: - 4. Dual-Pane Decoded Signal Windows

    private var dualPaneConsole: some View {
        HStack(spacing: 0) {
            // Left Window: Band Activity
            VStack(alignment: .leading, spacing: 0) {
                bandActivityHeader
                bandActivityList
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Right Window: Rx Frequency / Focused QSO Stream
            VStack(alignment: .leading, spacing: 0) {
                rxFrequencyStreamHeader
                rxFrequencyStreamList
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 260, maxHeight: .infinity)
    }

    // Left Pane Components
    private var bandActivityHeader: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(Color.green)
                    Text("Band Activity")
                        .font(.system(size: 11, weight: .bold))
                }
                Spacer()

                Button {
                    engine.clearBandActivity()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "trash")
                        Text("Clear")
                    }
                    .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Clear Band Activity table")

                Text("\(engine.decodedRows.count) decodes")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))

            Divider()

            HStack(spacing: 8) {
                Text("Time").frame(width: 58, alignment: .leading)
                Text("dB").frame(width: 28, alignment: .trailing)
                Text("DT").frame(width: 32, alignment: .trailing)
                Text("Freq").frame(width: 38, alignment: .trailing)
                Text("Message").frame(maxWidth: .infinity, alignment: .leading)
                Text("Cont").frame(width: 34, alignment: .center)
                Text("Country").frame(width: 110, alignment: .leading)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()
        }
    }

    private var bandActivityList: some View {
        Group {
            if engine.decodedRows.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("No Decodes in Current Slot")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Signals on \(engine.formattedDial) MHz are decoded at the end of each 15-second slot.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.12))
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(engine.decodedRows.prefix(120)) { row in
                            bandActivityRow(row)
                                .id(row.id)
                                .onTapGesture(count: 2) {
                                    engine.answerCallsign(row)
                                }
                                .contextMenu {
                                    Button("Reply to \(row.callerCall ?? "Station")") {
                                        engine.answerCallsign(row)
                                    }
                                    Button("Set RX Frequency to \(Int(row.audioFrequencyHz)) Hz") {
                                        engine.rxAudioFrequencyHz = row.audioFrequencyHz
                                    }
                                    Button("Set TX Frequency to \(Int(row.audioFrequencyHz)) Hz") {
                                        engine.txAudioFrequencyHz = row.audioFrequencyHz
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func bandActivityRow(_ row: FT8DecodedRow) -> some View {
        HStack(spacing: 8) {
            Text(Self.localTimeFormatter.string(from: row.slotStart))
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 58, alignment: .leading)

            Text("\(Int(row.estimatedSNR.rounded()))")
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 28, alignment: .trailing)

            Text(String(format: "%+.1f", row.timeOffset))
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 32, alignment: .trailing)

            Text("\(Int(row.audioFrequencyHz.rounded()))")
                .font(.system(size: 10, design: .monospaced))
                .frame(width: 38, alignment: .trailing)

            HStack(spacing: 4) {
                Text(row.text)
                    .font(.system(size: 11, design: .monospaced).weight(row.isDirectedToMe ? .bold : .medium))
                    .lineLimit(1)

                if row.isNewDXCC {
                    Text("NEW")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.purple, in: RoundedRectangle(cornerRadius: 2))
                } else if row.isNewGrid {
                    Text("GRID")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 2))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Continent Badge
            Text(row.continent)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(continentColor(row.continent))
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(continentColor(row.continent).opacity(0.14), in: RoundedRectangle(cornerRadius: 2))
                .frame(width: 34, alignment: .center)

            HStack(spacing: 4) {
                Text(row.countryFlag)
                Text(row.countryName)
                    .lineLimit(1)
            }
            .font(.system(size: 10))
            .frame(width: 110, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(rowBackground(for: row))
        .contentShape(Rectangle())
    }

    private func continentColor(_ cont: String) -> Color {
        switch cont {
        case "EU": return .blue
        case "AS": return .orange
        case "NA": return .green
        case "SA": return .cyan
        case "AF": return .yellow
        case "OC": return .purple
        case "AN": return .teal
        default: return .secondary
        }
    }

    private func rowBackground(for row: FT8DecodedRow) -> Color {
        if row.isDirectedToMe {
            return Color.red.opacity(0.32)
        } else if row.isNewDXCC {
            return Color.purple.opacity(0.28)
        } else if row.isCQ {
            return Color.green.opacity(0.26)
        } else {
            let slotInt = Int(row.slotStart.timeIntervalSince1970 / 15.0)
            return slotInt.isMultiple(of: 2) ? Color.secondary.opacity(0.04) : Color.clear
        }
    }

    // Right Pane Components
    private var rxFrequencyStreamHeader: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("Rx Frequency · Focused Stream")
                        .font(.system(size: 11, weight: .bold))
                }
                Spacer()
                Button {
                    engine.clearRxStream()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "trash")
                        Text("Erase")
                    }
                    .font(.system(size: 10))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.85))

            Divider()

            HStack(spacing: 8) {
                Text("Time").frame(width: 58, alignment: .leading)
                Text("dB").frame(width: 32, alignment: .trailing)
                Text("Freq").frame(width: 44, alignment: .trailing)
                Text("Message").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(height: 22)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()
        }
    }

    private var rxFrequencyStreamList: some View {
        Group {
            if engine.qsoStreamItems.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary.opacity(0.6))
                    Text("No Active QSO Stream")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Double-click any station in Band Activity to start answering, or click [CQ] to transmit.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.12))
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(engine.qsoStreamItems) { item in
                            switch item {
                            case .rx(let row):
                                HStack(spacing: 8) {
                                    Text(Self.localTimeFormatter.string(from: row.slotStart))
                                        .font(.system(size: 10, design: .monospaced))
                                        .frame(width: 58, alignment: .leading)
                                    Text("\(Int(row.estimatedSNR.rounded()))")
                                        .font(.system(size: 10, design: .monospaced))
                                        .frame(width: 32, alignment: .trailing)
                                    Text("\(Int(row.audioFrequencyHz.rounded()))")
                                        .font(.system(size: 10, design: .monospaced))
                                        .frame(width: 44, alignment: .trailing)
                                    Text(row.text)
                                        .font(.system(size: 11, design: .monospaced).weight(.bold))
                                        .foregroundStyle(row.isDirectedToMe ? Color.red : Color.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(row.isDirectedToMe ? Color.red.opacity(0.32) : Color.secondary.opacity(0.05))

                            case .tx(let tx):
                                HStack(spacing: 8) {
                                    Text(Self.localTimeFormatter.string(from: tx.timestamp))
                                        .font(.system(size: 10, design: .monospaced))
                                        .frame(width: 58, alignment: .leading)
                                    Text("TX")
                                        .font(.system(size: 10, design: .monospaced).weight(.heavy))
                                        .foregroundStyle(.yellow)
                                        .frame(width: 32, alignment: .trailing)
                                    Text("\(Int(tx.audioFrequencyHz.rounded()))")
                                        .font(.system(size: 10, design: .monospaced))
                                        .frame(width: 44, alignment: .trailing)
                                    Text(tx.text)
                                        .font(.system(size: 11, design: .monospaced).weight(.bold))
                                        .foregroundStyle(Color.yellow)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(Color.yellow.opacity(0.18))

                            case .status(_, let time, let text, let isMilestone):
                                HStack(spacing: 6) {
                                    Text(Self.localTimeFormatter.string(from: time))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 58, alignment: .leading)
                                    Text(text)
                                        .font(.system(size: 10, weight: isMilestone ? .bold : .regular))
                                        .foregroundStyle(isMilestone ? Color.accentColor : Color.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(isMilestone ? Color.accentColor.opacity(0.12) : Color.clear)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - 5. Bottom Status Bar

    private var bottomStatusBar: some View {
        HStack(spacing: 12) {
            // Station Identity Badge
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text(engine.myCall.isEmpty ? "EP2AES" : engine.myCall)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Text("·")
                    .foregroundStyle(.secondary)
                Text(engine.myGrid.isEmpty ? "LM55" : engine.myGrid)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.10), in: Capsule())

            Divider().frame(height: 14)

            // Live Engine Status
            HStack(spacing: 6) {
                Circle()
                    .fill(engine.state.isMonitoring ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(engine.status)
                    .font(.system(size: 11))
                    .foregroundStyle(engine.state.isMonitoring ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Transmit Watchdog Badge
            HStack(spacing: 4) {
                Image(systemName: "shield.checkered")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("Watchdog 16s")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 14)

            // Transmit progress bar
            ProgressView(value: engine.transmitProgress)
                .frame(width: 90)
                .opacity(engine.state == .transmitting ? 1 : 0.25)

            // Slot Countdown
            Text("Next: \(engine.secondsToNextTX.formatted(.number.precision(.fractionLength(1))))s")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func loadIdentity() {
        engine.configureStation(
            callsign: appState.currentStationCallsign,
            grid: appState.activeStationProfile?.normalizedGrid ?? ""
        )
    }

    private func field<Content: View>(_ title: String, width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(width: width, alignment: .leading)
    }
}

// MARK: - SDR-Control Style RF Spectrum & Color Waterfall Display

private struct FT8SpectrumWaterfallView: View {
    @ObservedObject var engine: FT8EngineService
    var onSelectRxFrequency: (Float) -> Void
    var onSelectTxFrequency: (Float) -> Void

    private let minFreq: Float = 200
    private let maxFreq: Float = 3000

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                // Top Half: RF Spectrum Graph with Peaks and Floating Callsign Tags
                spectrumCanvas(size: CGSize(width: geo.size.width, height: geo.size.height * 0.46))
                    .frame(height: geo.size.height * 0.46)

                // Frequency Calibration Ruler
                frequencyRuler(width: geo.size.width)
                    .frame(height: 18)
                    .background(Color(red: 0.08, green: 0.10, blue: 0.14))

                // Bottom Half: High-Definition Color Waterfall
                waterfallCanvas(size: CGSize(width: geo.size.width, height: geo.size.height * 0.54 - 18))
                    .frame(height: geo.size.height * 0.54 - 18)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let frac = max(0, min(1, Float(value.location.x / geo.size.width)))
                        let targetFreq = minFreq + frac * (maxFreq - minFreq)
                        if NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.option) {
                            onSelectTxFrequency(targetFreq)
                        } else {
                            onSelectRxFrequency(targetFreq)
                        }
                    }
            )
        }
    }

    // Spectrum Analyzer Canvas
    private func spectrumCanvas(size: CGSize) -> some View {
        Canvas(opaque: true, rendersAsynchronously: true) { context, cSize in
            // Dark Background
            context.fill(Path(CGRect(origin: .zero, size: cSize)), with: .color(Color(red: 0.04, green: 0.06, blue: 0.09)))

            // Horizontal dB grid lines (10 dB, 30 dB, 50 dB, 70 dB)
            for db in [10, 30, 50, 70] {
                let norm = CGFloat(db) / 80.0
                let y = cSize.height * (1.0 - norm)
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: cSize.width, y: y))
                context.stroke(p, with: .color(Color.white.opacity(0.08)), lineWidth: 0.5)

                let text = Text("\(db) dB").font(.system(size: 8, weight: .regular, design: .monospaced)).foregroundColor(.gray)
                context.draw(context.resolve(text), at: CGPoint(x: 18, y: y - 5))
            }

            // Draw RF Spectrum Curve
            let mags = engine.latestSpectrumMagnitudes
            if !mags.isEmpty {
                var curvePath = Path()
                let step = cSize.width / CGFloat(max(1, mags.count - 1))
                curvePath.move(to: CGPoint(x: 0, y: cSize.height))

                for (idx, val) in mags.enumerated() {
                    let x = CGFloat(idx) * step
                    let y = cSize.height * (1.0 - CGFloat(min(1.0, max(0.0, val * 0.95 + 0.05))))
                    curvePath.addLine(to: CGPoint(x: x, y: y))
                }

                curvePath.addLine(to: CGPoint(x: cSize.width, y: cSize.height))
                curvePath.closeSubpath()

                let gradient = Gradient(colors: [
                    Color(red: 0.1, green: 0.6, blue: 0.9).opacity(0.45),
                    Color(red: 0.05, green: 0.25, blue: 0.55).opacity(0.10)
                ])
                context.fill(curvePath, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: cSize.height)))

                // Stroke line
                var linePath = Path()
                for (idx, val) in mags.enumerated() {
                    let x = CGFloat(idx) * step
                    let y = cSize.height * (1.0 - CGFloat(min(1.0, max(0.0, val * 0.95 + 0.05))))
                    if idx == 0 { linePath.move(to: CGPoint(x: x, y: y)) } else { linePath.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(linePath, with: .color(Color(red: 0.3, green: 0.8, blue: 1.0)), lineWidth: 1.0)
            }

            // Draw RX Frequency Marker (Green)
            let rxX = xForFrequency(engine.rxAudioFrequencyHz, width: cSize.width)
            var rxPath = Path()
            rxPath.move(to: CGPoint(x: rxX, y: 0))
            rxPath.addLine(to: CGPoint(x: rxX, y: cSize.height))
            context.stroke(rxPath, with: .color(.green), lineWidth: 1.5)

            let rxText = Text("RX \(Int(engine.rxAudioFrequencyHz))").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.green)
            context.draw(context.resolve(rxText), at: CGPoint(x: rxX + 22, y: 10))

            // Draw TX Frequency Marker & FT8 50-Hz Passband Curve (Red)
            let txX = xForFrequency(engine.txAudioFrequencyHz, width: cSize.width)
            var txPath = Path()
            txPath.move(to: CGPoint(x: txX, y: 0))
            txPath.addLine(to: CGPoint(x: txX, y: cSize.height))
            context.stroke(txPath, with: .color(.red), lineWidth: 1.5)

            let txBandWidth = (50.0 / (maxFreq - minFreq)) * Float(cSize.width)
            let txRect = CGRect(x: txX - CGFloat(txBandWidth) / 2, y: 0, width: CGFloat(txBandWidth), height: cSize.height)
            context.fill(Path(txRect), with: .color(Color.red.opacity(0.18)))

            let txText = Text("TX \(Int(engine.txAudioFrequencyHz))").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.red)
            context.draw(context.resolve(txText), at: CGPoint(x: txX - 22, y: 10))

            // Draw Floating Station Callout Tags over Signal Peaks with Vertical Staggering (Collision Avoidance)
            let sortedPeaks = engine.activeSignalPeaks.prefix(20).sorted { $0.frequencyHz < $1.frequencyHz }
            var lastPx: CGFloat = -100
            var currentTier = 0
            for peak in sortedPeaks {
                let px = xForFrequency(peak.frequencyHz, width: cSize.width)
                guard px > 24 && px < cSize.width - 24 else { continue }

                // Check distance to previous tag: stagger vertically if closer than 52 points
                if abs(px - lastPx) < 52 {
                    currentTier = (currentTier + 1) % 3
                } else {
                    currentTier = 0
                }
                lastPx = px

                let pillY: CGFloat = 14 + CGFloat(currentTier) * 15

                // Vertical hairline down to signal
                var tick = Path()
                tick.move(to: CGPoint(x: px, y: pillY + 7))
                tick.addLine(to: CGPoint(x: px, y: cSize.height * 0.75))
                let tickColor: Color = peak.isDirectedToMe ? .red : (peak.isCQ ? .green : Color.white.opacity(0.4))
                context.stroke(tick, with: .color(tickColor), lineWidth: 0.8)

                // Callout Pill
                let pillRect = CGRect(x: px - 24, y: pillY, width: 48, height: 13)
                context.fill(Path(roundedRect: pillRect, cornerRadius: 3), with: .color(tickColor.opacity(0.85)))

                let tagText = Text(peak.callsign)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                context.draw(context.resolve(tagText), at: CGPoint(x: px, y: pillY + 6.5))
            }
        }
    }

    // Frequency Ruler
    private func frequencyRuler(width: CGFloat) -> some View {
        Canvas { context, size in
            let dialMHz = Double(engine.dialFrequencyHz) / 1_000_000.0
            for khz in stride(from: 500, through: 3000, by: 500) {
                let freq = Float(khz)
                let x = xForFrequency(freq, width: width)
                var mark = Path()
                mark.move(to: CGPoint(x: x, y: 0))
                mark.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(mark, with: .color(Color.white.opacity(0.2)), lineWidth: 0.5)

                let totalMHz = dialMHz + (Double(khz) / 1_000_000.0)
                let label = Text(String(format: "%.3f", totalMHz))
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(.gray)
                context.draw(context.resolve(label), at: CGPoint(x: x, y: size.height / 2))
            }
        }
    }

    // Waterfall Canvas - Ultra-low CPU bitmap rendering via CGImage (<2% CPU)
    private func waterfallCanvas(size: CGSize) -> some View {
        Canvas(opaque: true, rendersAsynchronously: true) { context, cSize in
            context.fill(Path(CGRect(origin: .zero, size: cSize)), with: .color(Color(red: 0.02, green: 0.03, blue: 0.06)))

            if let cgImage = Self.createWaterfallImage(rows: engine.waterfallRows) {
                context.draw(Image(decorative: cgImage, scale: 1.0), in: CGRect(origin: .zero, size: cSize))
            }

            // RX & TX vertical markers through waterfall
            let rxX = xForFrequency(engine.rxAudioFrequencyHz, width: cSize.width)
            var rxLine = Path()
            rxLine.move(to: CGPoint(x: rxX, y: 0))
            rxLine.addLine(to: CGPoint(x: rxX, y: cSize.height))
            context.stroke(rxLine, with: .color(Color.green.opacity(0.7)), lineWidth: 1.0)

            let txX = xForFrequency(engine.txAudioFrequencyHz, width: cSize.width)
            var txLine = Path()
            txLine.move(to: CGPoint(x: txX, y: 0))
            txLine.addLine(to: CGPoint(x: txX, y: cSize.height))
            context.stroke(txLine, with: .color(Color.red.opacity(0.7)), lineWidth: 1.0)
        }
    }

    private static func createWaterfallImage(rows: [[Float]]) -> CGImage? {
        guard !rows.isEmpty else { return nil }
        let height = rows.count
        guard let width = rows.first?.count, width > 0, height > 0 else { return nil }

        var pixels = [UInt32](repeating: 0, count: width * height)
        for r in 0..<height {
            let row = rows[r]
            let rowOffset = r * width
            let colCount = min(width, row.count)
            for c in 0..<colCount {
                pixels[rowOffset + c] = waterfallRGB32(row[c])
            }
        }

        let data = Data(bytes: &pixels, count: pixels.count * 4)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private static func waterfallRGB32(_ rawValue: Float) -> UInt32 {
        let v = min(1.0, max(0.0, rawValue))
        let r: UInt8
        let g: UInt8
        let b: UInt8
        if v < 0.15 {
            r = UInt8(v * 20)
            g = UInt8(v * 60)
            b = UInt8(40 + v * 500)
        } else if v < 0.35 {
            let t = (v - 0.15) / 0.20
            r = UInt8(10 + t * 40)
            g = UInt8(40 + t * 160)
            b = UInt8(140 + t * 115)
        } else if v < 0.60 {
            let t = (v - 0.35) / 0.25
            r = UInt8(50 + t * 180)
            g = UInt8(200 + t * 35)
            b = UInt8(255 - t * 200)
        } else if v < 0.85 {
            let t = (v - 0.60) / 0.25
            r = UInt8(230 + t * 25)
            g = UInt8(235 - t * 140)
            b = UInt8(55 - t * 40)
        } else {
            let t = (v - 0.85) / 0.15
            r = 255
            g = UInt8(95 + t * 160)
            b = UInt8(15 + t * 240)
        }
        return (0xFF << 24) | (UInt32(b) << 16) | (UInt32(g) << 8) | UInt32(r)
    }

    private func xForFrequency(_ freq: Float, width: CGFloat) -> CGFloat {
        let frac = CGFloat((freq - minFreq) / (maxFreq - minFreq))
        return max(0, min(width, frac * width))
    }
}
