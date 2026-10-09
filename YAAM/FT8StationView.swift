//
//  FT8StationView.swift
//  YAAM
//

import SwiftUI
import FT8Codec
import FT8808Engine

private struct FT8RibbonButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var accent: Color = .secondary
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: 34)
            .padding(.horizontal, 9)
            .foregroundStyle(prominent && isEnabled ? Color.white : (isEnabled ? Color.primary : Color.secondary))
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(prominent && isEnabled ? accent : Color(nsColor: .controlBackgroundColor))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(accent.opacity(prominent && isEnabled ? 0 : 0.14), lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct FT8RibbonMenuLabel: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 12, weight: .semibold))
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 9)
        .frame(height: 34)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.secondary.opacity(0.14)))
    }
}

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
    @ObservedObject var tx500: Lab599TX500Driver = Lab599TX500Driver.shared
    @ObservedObject var icomUSB: IcomUSBRadioDriver = IcomUSBRadioDriver.shared
    @ObservedObject var fx4cr: FX4CRDriver = FX4CRDriver.shared
    @ObservedObject var xiegu: Xiegu6100Driver = Xiegu6100Driver.shared

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
    @State private var showChecksheetPopover = false
    @State private var showCabrilloExportSheet = false
    @State private var showWSJTXBridgeSheet = false
    @State private var upperContentHeight: CGFloat = 320
    @State private var showTxDrivePopover = false
    @StateObject private var bandClubLogSpots = ClubLogSpotsService()

    private var icomModel: Binding<IcomNetworkModel> {
        Binding(
            get: { IcomNetworkModel(rawValue: icomModelName) ?? .ic705 },
            set: { icomModelName = $0.rawValue }
        )
    }

    private var radioPathConnected: Bool {
        switch engine.audioPath {
        case .icomLAN: return radio.state.isConnected
        case .coreAudio: return rig.state.isConnected
        case .lab599TX500: return tx500.isConnected
        case .icomUSB: return icomUSB.isConnected
        case .fx4cr: return fx4cr.isConnected
        case .xiegu6100: return xiegu.isConnected
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 1_050
            let spectrumHeight = min(compact ? 170 : 220, max(110, geometry.size.height * 0.23))
            let upperLimit = max(100, geometry.size.height - spectrumHeight - 210 - 38)

            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: true) {
                    upperStationControls
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { upperContentHeight = $0 }
                }
                .frame(height: min(upperContentHeight, upperLimit))

                Divider()

                FT8SpectrumWaterfallView(
                    engine: engine,
                    onSelectRxFrequency: { freq in
                        engine.rxAudioFrequencyHz = freq
                        if engine.lockTxRxFreq { engine.txAudioFrequencyHz = freq }
                    },
                    onSelectTxFrequency: { freq in
                        engine.txAudioFrequencyHz = freq
                        if engine.lockTxRxFreq { engine.rxAudioFrequencyHz = freq }
                    }
                )
                .frame(height: spectrumHeight)
                .background(Color.black)

                Divider()

                dualPaneConsole(compact: compact)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                bottomStatusBar
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            }
        }
        .onAppear {
            loadIdentity()
            engine.refreshAudioDevices()
            if icomPassword.isEmpty {
                icomPassword = CredentialVault.valueIfAvailableWithoutPrompt(for: .icomNetworkPassword)
            }
        }
        .task {
            // Reuse configured Club Log authentication and keep the fetch rate
            // bounded while this screen is visible. DX Cluster is event-driven.
            while !Task.isCancelled {
                let configured = !(UserDefaults.standard.string(forKey: "clubLogEmail") ?? "").isEmpty
                    || !ClubLogSessionStore.savedCookieHeader().isEmpty
                if configured && !bandClubLogSpots.isLoading {
                    await bandClubLogSpots.fetchPersonalSpots(credentials: appState.qslServiceCredentials(for: [.clubLog]))
                }
                do { try await Task.sleep(for: .seconds(300)) } catch { return }
            }
        }
        .onChange(of: appState.activeStationProfileID) { _, _ in loadIdentity() }
        .onChange(of: engine.audioPath) { _, _ in engine.stopMonitoring() }
        .onChange(of: radio.state) { _, state in
            if !state.isConnected, engine.audioPath == .icomLAN { engine.stopMonitoring() }
        }
        .onChange(of: tx500.isConnected) { _, connected in
            if !connected, engine.audioPath == .lab599TX500 { engine.stopMonitoring() }
        }
        .onChange(of: icomUSB.isConnected) { _, connected in
            if !connected, engine.audioPath == .icomUSB { engine.stopMonitoring() }
        }
        .onChange(of: fx4cr.isConnected) { _, connected in
            if !connected, engine.audioPath == .fx4cr { engine.stopMonitoring() }
        }
        .onChange(of: xiegu.isConnected) { _, connected in
            if !connected, engine.audioPath == .xiegu6100 { engine.stopMonitoring() }
        }
        .sheet(isPresented: $showCabrilloExportSheet) {
            DigitalContestCabrilloExportView(
                engine: engine.contestEngine,
                defaultCall: appState.currentStationCallsign,
                defaultGrid: appState.activeStationProfile?.normalizedGrid ?? engine.myGrid
            )
        }
        .sheet(isPresented: $showWSJTXBridgeSheet) {
            VStack(spacing: 0) {
                HStack {
                    Label("WSJT-X / JTDX 2-Way Live Stream & Command Console", systemImage: "dot.radiowaves.left.and.right")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Button("Done") { showWSJTXBridgeSheet = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(16)
                Divider()
                WSJTXLiveStreamView(wsjtx: appState.wsjtxListener)
            }
            .frame(minWidth: 880, idealWidth: 980, minHeight: 560, idealHeight: 660)
        }
    }

    private var upperStationControls: some View {
        VStack(spacing: 0) {
            topControlRibbon
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))
            Divider()

            if showHardwareSettings || !radioPathConnected {
                radioConnectionPanel
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                Divider()
            }

            if engine.isContestMode {
                ScrollView(.horizontal, showsIndicators: true) {
                    contestCommandHUD
                        .fixedSize(horizontal: true, vertical: false)
                }
                Divider()
                ScrollView(.horizontal, showsIndicators: true) {
                    contestQueueHUD
                        .frame(minWidth: 760)
                }
                Divider()
            }

            autoHunterHUD
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.04))

            stationAlertBanners
            Divider()

            if radioPathConnected {
                radioMetersHUD
                Divider()
            }
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

                Button {
                    radio.reapplyDigitalSettings()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                        Text("Re-apply to Radio")
                    }
                    .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Re-sends CI-V DATA MOD=LAN/WLAN and USB-D configuration to the radio")

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
        VStack(alignment: .leading, spacing: 7) {
            Label("RECEIVE & TUNE", systemImage: "waveform.path")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            WrappingControlsLayout(spacing: 8) {
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
                    let labelText: String = {
                        if !radioPathConnected { return "Connect Radio..." }
                        switch engine.audioPath {
                        case .icomLAN: return "Icom LAN"
                        case .coreAudio: return "rigctld"
                        case .lab599TX500: return "TX-500"
                        case .icomUSB: return "Icom USB"
                        case .fx4cr: return "FX-4CR"
                        case .xiegu6100: return "X6100"
                        }
                    }()
                    Text(labelText)
                        .font(.caption.weight(.bold))
                    Image(systemName: (showHardwareSettings || !radioPathConnected) ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
            }
            .buttonStyle(FT8RibbonButtonStyle(accent: radioPathConnected ? .green : .orange))
            .help("Open / Close Radio Connection settings")

            // RX Switch Button (Redesigned matching TX)
            Button {
                if engine.state.isMonitoring {
                    engine.stopMonitoring()
                } else if engine.audioPath == .icomLAN {
                    engine.startIcomMonitoring(radio: radio)
                } else if engine.audioPath == .lab599TX500 {
                    engine.startTX500Monitoring(
                        inputDevice: inputDeviceUID,
                        outputDevice: outputDeviceUID
                    )
                } else if engine.audioPath == .icomUSB {
                    engine.startIcomUSBMonitoring(
                        inputDevice: inputDeviceUID,
                        outputDevice: outputDeviceUID
                    )
                } else if engine.audioPath == .fx4cr {
                    engine.startFX4CRMonitoring(
                        inputDevice: inputDeviceUID,
                        outputDevice: outputDeviceUID
                    )
                } else if engine.audioPath == .xiegu6100 {
                    engine.startXiegu6100Monitoring(
                        inputDevice: inputDeviceUID,
                        outputDevice: outputDeviceUID
                    )
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
            .buttonStyle(FT8RibbonButtonStyle(accent: engine.state.isMonitoring ? .green : .gray, prominent: true))
            .disabled(!radioPathConnected && !engine.state.isMonitoring)
            .help(radioPathConnected ? "Start / Stop receiving FT8/FT4 audio" : "Connect the radio first before starting receive")

            // Operating Protocol Pill: FT8 (15s) vs FT4 (7.5s)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    engine.toggleOperatingProtocol()
                }
            } label: {
                HStack(spacing: 4) {
                    if engine.operatingProtocol == .ft4 {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(Color.yellow)
                    }
                    Text(engine.operatingProtocol == .ft4 ? "FT4 (7.5s)" : "FT8 (15s)")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                }
                .padding(.horizontal, 7)
                .frame(height: 28)
            }
            .buttonStyle(FT8RibbonButtonStyle(accent: engine.operatingProtocol == .ft4 ? .yellow : .secondary))
            .help("Toggle between FT8 (15-second cycles) and high-rate FT4 (7.5-second cycles)")

            Menu {
                Button("Standard · one pass") { engine.expandedDecodeEnabled = false }
                Button("Expanded · three timing alignments") { engine.expandedDecodeEnabled = true }
                Text("Expanded keeps the standard results and searches two additional alignments. Uses more CPU during decoding.")
            } label: {
                FT8RibbonMenuLabel(text: engine.expandedDecodeEnabled ? "Decode: Expanded" : "Decode: Standard")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            // Band Presets Picker
            Menu {
                if engine.operatingProtocol == .ft4 {
                    ForEach(FT4BandPreset.common) { preset in
                        Button(preset.band) { engine.dialFrequencyHz = preset.frequencyHz }
                    }
                } else {
                    ForEach(FT8BandPreset.common) { preset in
                        Button(preset.band) { engine.dialFrequencyHz = preset.frequencyHz }
                    }
                }
            } label: {
                FT8RibbonMenuLabel(text: engine.currentBandName)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .onChange(of: engine.dialFrequencyHz) { _, _ in
                engine.applyDialAndMode()
            }

            Text(engine.formattedDial)
                .font(.system(.body, design: .monospaced).weight(.bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .frame(height: 34)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

            // Contest Mode Toggle Button
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    engine.toggleContestMode()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(engine.isContestMode ? Color.yellow : Color.secondary)
                    Text("CONTEST")
                        .font(.system(size: 11, weight: .heavy))
                }
                .padding(.horizontal, 7)
                .frame(height: 28)
            }
            .buttonStyle(FT8RibbonButtonStyle(accent: engine.isContestMode ? .yellow : .secondary))
            .help("Toggle Digital Contest Mode (CQ WW Digi / ARRL Digi rules, multipliers, and live rate)")

            // Auto-Sequence Toggle
            Toggle("Auto", isOn: $engine.autoSequenceEnabled)
                .toggleStyle(.button)
                .buttonStyle(FT8RibbonButtonStyle(accent: .accentColor, prominent: engine.autoSequenceEnabled))
                .help("Automatically progress through QSO sequence")

            // Erase Tables Button
            Button {
                engine.clearDecodes()
                engine.clearRxStream()
            } label: {
                Label("Erase", systemImage: "trash")
                    .frame(height: 28)
            }
            .buttonStyle(FT8RibbonButtonStyle())
            .help("Clear both Band Activity and Rx Stream")

            // WSJT-X 2-Way Bridge Button
            Button {
                showWSJTXBridgeSheet.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                    Text("WSJT-X")
                        .font(.system(size: 11, weight: .bold))
                    if appState.wsjtxListener.state.isListening {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 6)
                .frame(height: 28)
            }
            .buttonStyle(FT8RibbonButtonStyle(accent: appState.wsjtxListener.state.isListening ? .green : .secondary))
            .help("Open 2-Way WSJT-X / JTDX Live Stream & 1-Click Reply Console")

            }

            Divider()

            Label("TRANSMIT & LOG", systemImage: "antenna.radiowaves.left.and.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            WrappingControlsLayout(spacing: 8) {

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
            .buttonStyle(FT8RibbonButtonStyle(accent: engine.transmitArmed ? .red : .gray, prominent: true))
            .help("Arm / Disarm RF Transmission")

            // Slot Parity Button (1st :00/:30 or 2nd :15/:45)
            Button {
                engine.txParity = engine.txParity.toggled
            } label: {
                Text(engine.txParity == .even ? "1st (:00)" : "2nd (:15)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 65, height: 26)
            }
            .buttonStyle(FT8RibbonButtonStyle())
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
            .frame(height: 34)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))

            // DX Station & Report
            HStack(spacing: 6) {
                TextField("DX", text: $engine.dxCall)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .frame(width: 92)
                    .frame(height: 34)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.secondary.opacity(0.2)))
                    .font(.system(.caption, design: .monospaced).weight(.bold))

                TextField("Rep", text: $engine.dxReport)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .frame(width: 62)
                    .frame(height: 34)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.secondary.opacity(0.2)))
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
                .frame(width: 60, height: 28)
            }
            .buttonStyle(FT8RibbonButtonStyle(accent: engine.isCallingCQContinually ? .orange : .accentColor, prominent: true))
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
                FT8RibbonMenuLabel(text: "Tx \(selectedTxMessageIndex)")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            // Manual / Auto Log Button
            Button {
                if !engine.dxCall.isEmpty {
                    let currentBand = engine.currentBandName
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
                    .frame(height: 28)
            }
            .buttonStyle(FT8RibbonButtonStyle())
            .disabled(engine.dxCall.isEmpty)
            .help("Log current QSO to YAAM Log Table")

            if let quietHz = engine.suggestedTxAudioHz {
                Button {
                    engine.txAudioFrequencyHz = Float(quietHz)
                } label: {
                    Label("Quiet TX · \(quietHz) Hz", systemImage: "waveform.path")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(FT8RibbonButtonStyle(accent: .cyan))
                .disabled(engine.transmitArmed || engine.isTransmitScheduled)
                .help("Suggested from recent received waterfall energy and decoded signals. Disarm TX to apply. Local reception cannot guarantee a clear frequency at the other station.")
            }
            }
        }
    }

    // MARK: - 2. Prominent Radio Connection Panel

    private func iconForAudioPath(_ path: FT8AudioPath) -> String {
        switch path {
        case .icomLAN: return "network"
        case .icomUSB: return "cable.connector"
        case .coreAudio: return "waveform.path"
        case .fx4cr: return "antenna.radiowaves.left.and.right"
        case .lab599TX500: return "radio.fill"
        case .xiegu6100: return "slider.horizontal.3"
        }
    }

    private var radioConnectionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Keep identity and connection state visible as the window narrows.
            WrappingControlsLayout(spacing: 8) {
                Label("Radio & Audio Connection Setup", systemImage: "cable.connector.horizontal")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)

                Text("Transceiver Interface & Telemetry")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    // Connection Status Indicator Pill
                    HStack(spacing: 4) {
                        Circle()
                            .fill(radioPathConnected ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(radioPathConnected ? "Connected" : "Not Connected")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(radioPathConnected ? Color.green : Color.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        (radioPathConnected ? Color.green : Color.orange).opacity(0.12),
                        in: Capsule()
                    )

                    if radioPathConnected {
                        Button {
                            withAnimation { showHardwareSettings = false }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Dismiss connection panel")
                    }
                }

                Text("Station: \(engine.myCall.isEmpty ? "No Call" : engine.myCall) · Grid: \(engine.myGrid.isEmpty ? "----" : engine.myGrid)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            }

            // Row 2: Transceiver Path Selector (Responsive Capsules, Zero Overlap)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(FT8AudioPath.allCases) { path in
                        let isSelected = engine.audioPath == path
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                engine.audioPath = path
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: iconForAudioPath(path))
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                Text(path.rawValue)
                                    .font(.system(size: 11.5, weight: isSelected ? .bold : .medium))
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .foregroundColor(isSelected ? .white : .primary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected ? Color.clear : Color.primary.opacity(0.12), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Configure \(path.rawValue)")
                    }
                }
                .padding(.vertical, 2)
            }
            .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.6)

            if engine.audioPath == .icomLAN {
                icomSettings
            } else if engine.audioPath == .icomUSB {
                icomUSBSettings
            } else if engine.audioPath == .lab599TX500 {
                tx500Settings
            } else if engine.audioPath == .fx4cr {
                fx4crSettings
            } else if engine.audioPath == .xiegu6100 {
                xiegu6100Settings
            } else {
                coreAudioSettings
            }

            if (engine.audioPath == .icomLAN && icomModel.wrappedValue == .ic7300MK2)
                || (engine.audioPath == .icomUSB && icomUSB.model == .ic7300MK2) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("IC-7300MK2 receive check", systemImage: "checklist")
                        .font(.caption.weight(.bold))
                    Text("Connect the radio, confirm its dial frequency and mode, then start RX and check decoded signals. Arm TX only when the receive path is verified.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
            }

            // Live Diagnostic Status & Error Banner
            let bannerMessage: String = {
                switch engine.audioPath {
                case .icomLAN: return radio.lastMessage
                case .icomUSB: return icomUSB.lastMessage
                case .coreAudio: return rig.lastMessage
                case .lab599TX500: return tx500.lastMessage
                case .fx4cr: return fx4cr.lastMessage
                case .xiegu6100: return xiegu.lastMessage
                }
            }()
            let bannerConnected: Bool = radioPathConnected
            let bannerFailed: Bool = {
                switch engine.audioPath {
                case .icomLAN: return radio.state.isFailed
                case .icomUSB: return icomUSB.lastMessage.contains("Failed")
                case .coreAudio: return rig.state.title.contains("failed")
                case .lab599TX500: return tx500.lastMessage.contains("Failed")
                case .fx4cr: return fx4cr.lastMessage.contains("Failed")
                case .xiegu6100: return xiegu.lastMessage.contains("Failed")
                }
            }()
            let bannerTransitioning: Bool = {
                switch engine.audioPath {
                case .icomLAN: return radio.state.isTransitioning
                case .icomUSB: return icomUSB.isConnecting
                case .coreAudio: return rig.state.title == "Connecting"
                case .lab599TX500: return tx500.isConnecting
                case .fx4cr: return fx4cr.isConnecting
                case .xiegu6100: return xiegu.isConnecting
                }
            }()

            if !bannerMessage.isEmpty {
                HStack(spacing: 8) {
                    if bannerTransitioning {
                        ProgressView().controlSize(.mini)
                    } else if bannerFailed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    } else if bannerConnected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }

                    Text(bannerMessage)
                        .font(.caption)
                        .foregroundStyle(bannerFailed ? Color.red : Color.primary)
                        .textSelection(.enabled)

                    Spacer()

                    if engine.audioPath == .icomLAN && !credentialStatus.isEmpty {
                        Text(credentialStatus)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(credentialStatus.contains("Saved") ? Color.green : Color.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    bannerFailed
                        ? Color.red.opacity(0.12)
                        : (bannerConnected ? Color.green.opacity(0.10) : Color.secondary.opacity(0.08)),
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }
        }
    }

    private var tx500Settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            WrappingControlsLayout(spacing: 12) {
                field("USB Serial CAT (AD-514/AD-502)", width: 220) {
                    Picker("Serial Port", selection: Binding(get: { tx500.selectedPort }, set: { tx500.selectedPort = $0 })) {
                        if tx500.availablePorts.isEmpty {
                            Text("No serial ports found").tag("")
                        }
                        ForEach(tx500.availablePorts, id: \.self) { p in
                            Text(p.components(separatedBy: "/").last ?? p).tag(p)
                        }
                    }
                    .labelsHidden()
                }

                Button { tx500.refreshPorts() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh serial ports")

                field("Input Audio (AD-508 / Codec)", width: 190) {
                    Picker("Input", selection: $inputDeviceUID) {
                        Text("System Default").tag("")
                        ForEach(engine.inputDevices) { d in Text(d.name).tag(d.uid) }
                    }
                    .labelsHidden()
                }

                field("Output Audio (AD-508 / Codec)", width: 190) {
                    Picker("Output", selection: $outputDeviceUID) {
                        Text("System Default").tag("")
                        ForEach(engine.outputDevices) { d in Text(d.name).tag(d.uid) }
                    }
                    .labelsHidden()
                }

                Button { engine.refreshAudioDevices(); tx500.scanAudioDevices() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Core Audio Devices")

                Button {
                    tx500.toggleConnection()
                } label: {
                    Label(tx500.isConnected ? "Disconnect" : "Connect", systemImage: tx500.isConnected ? "xmark.circle" : "bolt.horizontal.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(tx500.isConnected ? .secondary : .blue)

                statusPill(tx500.isConnected ? "TX-500 Connected" : (tx500.isConnecting ? "Connecting..." : "TX-500 Offline"), active: tx500.isConnected)
            }

            // Checklist & Firmware Bug #1 Notice
            WrappingControlsLayout(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.green)
                        .font(.caption2)
                    Text("Pre-Flight: Menu 34: TS2000 • Menu 35: 9600 • Menu 09: 30 • Mode: DIG • Audio: 48kHz 16-bit")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Toggle("Preserve DIG Mode", isOn: Binding(get: { tx500.preserveDIGMode }, set: { tx500.preserveDIGMode = $0 }))
                    .font(.caption2)
                    .help("Suppresses CAT mode override to prevent Firmware Bug #1 (TX mode switching to USB with 0W output)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var fx4crSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            WrappingControlsLayout(spacing: 12) {
                field("Transport Link", width: 140) {
                    Picker("Transport", selection: Binding(get: { fx4cr.connectionType }, set: { fx4cr.connectionType = $0 })) {
                        ForEach(FX4CRConnectionType.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .labelsHidden()
                }

                field(fx4cr.connectionType == .bluetooth ? "Bluetooth Serial Port" : "USB Serial Port", width: 200) {
                    Picker("Serial Port", selection: Binding(get: { fx4cr.selectedPort }, set: { fx4cr.selectedPort = $0 })) {
                        if fx4cr.availablePorts.isEmpty {
                            Text("No matching ports").tag("")
                        }
                        ForEach(fx4cr.availablePorts, id: \.self) { p in
                            Text(p.components(separatedBy: "/").last ?? p).tag(p)
                        }
                    }
                    .labelsHidden()
                }

                Button { fx4cr.refreshPorts() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh serial ports")

                field("Input Audio (CM108AH / BT)", width: 180) {
                    Picker("Input", selection: $inputDeviceUID) {
                        Text("System Default").tag("")
                        ForEach(engine.inputDevices) { d in Text(d.name).tag(d.uid) }
                    }
                    .labelsHidden()
                }

                field("Output Audio (CM108AH / BT)", width: 180) {
                    Picker("Output", selection: $outputDeviceUID) {
                        Text("System Default").tag("")
                        ForEach(engine.outputDevices) { d in Text(d.name).tag(d.uid) }
                    }
                    .labelsHidden()
                }

                Button { engine.refreshAudioDevices(); fx4cr.scanAudioDevices() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Core Audio Devices")

                Button {
                    fx4cr.toggleConnection()
                } label: {
                    Label(fx4cr.isConnected ? "Disconnect" : "Connect", systemImage: fx4cr.isConnected ? "xmark.circle" : "cable.connector")
                }
                .buttonStyle(.borderedProminent)
                .tint(fx4cr.isConnected ? .secondary : .blue)

                statusPill(fx4cr.isConnected ? "FX-4CR Linked" : (fx4cr.isConnecting ? "Connecting..." : "FX-4CR Offline"), active: fx4cr.isConnected)
            }
        }
    }

    private var xiegu6100Settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            WrappingControlsLayout(spacing: 12) {
                field("Serial Port (DEV Port)", width: 220) {
                    Picker("Serial Port", selection: Binding(get: { xiegu.selectedPort }, set: { xiegu.selectedPort = $0 })) {
                        if xiegu.availablePorts.isEmpty {
                            Text("No matching ports").tag("")
                        }
                        ForEach(xiegu.availablePorts, id: \.self) { p in
                            Text(p.components(separatedBy: "/").last ?? p).tag(p)
                        }
                    }
                    .labelsHidden()
                }

                Button { xiegu.refreshPorts() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh serial ports")

                field("CI-V Baud", width: 110) {
                    Picker("Baud Rate", selection: Binding(get: { xiegu.baudRate }, set: { xiegu.baudRate = $0 })) {
                        Text("9600").tag(9600)
                        Text("19200").tag(19200)
                        Text("38400").tag(38400)
                        Text("57600").tag(57600)
                        Text("115200").tag(115200)
                    }
                    .labelsHidden()
                }

                field("Input Audio (USB CODEC)", width: 180) {
                    Picker("Input", selection: $inputDeviceUID) {
                        Text("System Default").tag("")
                        ForEach(engine.inputDevices) { d in Text(d.name).tag(d.uid) }
                    }
                    .labelsHidden()
                }

                field("Output Audio (USB CODEC)", width: 180) {
                    Picker("Output", selection: $outputDeviceUID) {
                        Text("System Default").tag("")
                        ForEach(engine.outputDevices) { d in Text(d.name).tag(d.uid) }
                    }
                    .labelsHidden()
                }

                Button { engine.refreshAudioDevices(); xiegu.scanAudioDevices() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Core Audio Devices")

                Button {
                    xiegu.toggleConnection()
                } label: {
                    Label(xiegu.isConnected ? "Disconnect" : "Connect", systemImage: xiegu.isConnected ? "xmark.circle" : "cable.connector")
                }
                .buttonStyle(.borderedProminent)
                .tint(xiegu.isConnected ? .secondary : .blue)

                statusPill(xiegu.isConnected ? "X6100 Linked" : (xiegu.isConnecting ? "Connecting..." : "X6100 Offline"), active: xiegu.isConnected)
            }
        }
    }

    private var icomUSBSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            WrappingControlsLayout(spacing: 12) {
                field("Radio Model", width: 140) {
                    Picker("Model", selection: Binding(get: { icomUSB.model }, set: { icomUSB.model = $0 })) {
                        ForEach(IcomUSBModel.allCases) { m in
                            Label(m.rawValue, systemImage: m.iconName).tag(m)
                        }
                    }
                    .labelsHidden()
                }

                field("USB Serial Port (CP210x / CDC)", width: 200) {
                    Picker("Serial Port", selection: Binding(get: { icomUSB.selectedPort }, set: { icomUSB.selectedPort = $0 })) {
                        if icomUSB.availablePorts.isEmpty {
                            Text("No serial ports found").tag("")
                        }
                        ForEach(icomUSB.availablePorts, id: \.self) { p in
                            Text(p.components(separatedBy: "/").last ?? p).tag(p)
                        }
                    }
                    .labelsHidden()
                }

                Button { icomUSB.refreshPorts() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh serial ports")

                field("Baud Rate", width: 100) {
                    Picker("Baud", selection: Binding(get: { icomUSB.baudRate }, set: { icomUSB.baudRate = $0 })) {
                        Text("115200").tag(115200)
                        Text("19200").tag(19200)
                        Text("9600").tag(9600)
                        Text("4800").tag(4800)
                    }
                    .labelsHidden()
                }

                field("Input Audio (USB CODEC)", width: 180) {
                    Picker("Input", selection: $inputDeviceUID) {
                        if let matched = icomUSB.detectedAudioInputName {
                            Text("Auto: \(matched)").tag(icomUSB.detectedAudioInputUID ?? "")
                        } else {
                            Text("System Default").tag("")
                        }
                        ForEach(engine.inputDevices) { d in Text(d.name).tag(d.uid) }
                    }
                    .labelsHidden()
                }

                field("Output Audio (USB CODEC)", width: 180) {
                    Picker("Output", selection: $outputDeviceUID) {
                        if let matched = icomUSB.detectedAudioOutputName {
                            Text("Auto: \(matched)").tag(icomUSB.detectedAudioOutputUID ?? "")
                        } else {
                            Text("System Default").tag("")
                        }
                        ForEach(engine.outputDevices) { d in Text(d.name).tag(d.uid) }
                    }
                    .labelsHidden()
                }

                Button { engine.refreshAudioDevices(); icomUSB.scanAudioDevices() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Core Audio Devices")

                Button {
                    if icomUSB.isConnected {
                        icomUSB.disconnect()
                    } else {
                        icomUSB.connect()
                    }
                } label: {
                    Label(icomUSB.isConnected ? "Disconnect" : "Connect", systemImage: icomUSB.isConnected ? "xmark.circle" : "cable.connector")
                }
                .buttonStyle(.borderedProminent)
                .tint(icomUSB.isConnected ? .secondary : .blue)

                statusPill(icomUSB.isConnected ? "\(icomUSB.model.rawValue) Linked" : (icomUSB.isConnecting ? "Connecting..." : "Icom Offline"), active: icomUSB.isConnected)
            }

            // Pre-flight settings info and Audio Codec status
            WrappingControlsLayout(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.blue)
                        .font(.caption2)
                    Text("Pre-Flight: Icom Menu -> Connectors -> DATA MOD: USB • CI-V Baud: \(icomUSB.baudRate) • Mode: USB-D")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text("CI-V Addr: 0x\(icomUSB.customCivAddressHex)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    if icomUSB.isAudioCodecDetected {
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("USB Audio CODEC Ready")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.green)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange).frame(width: 6, height: 6)
                            Text("Verify USB Audio in Settings")
                                .font(.caption2)
                                .foregroundStyle(Color.orange)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var icomSettings: some View {
        WrappingControlsLayout(spacing: 10) {
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

            statusPill(
                radio.state.isConnected ? "Connected to \(radio.radioName.isEmpty ? "Icom LAN" : radio.radioName)" : (radio.state.isTransitioning ? "Connecting..." : (radio.state.isFailed ? "Failed" : "Not Connected")),
                active: radio.state.isConnected
            )
        }
    }

    private var coreAudioSettings: some View {
        WrappingControlsLayout(spacing: 12) {
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

    // MARK: - 2.5 Gold Standard Contest Command Ribbon & Live Multipliers HUD

    private var contestCommandHUD: some View {
        HStack(spacing: 12) {
            // Contest Selector & Mode Pill
            Menu {
                ForEach(DigitalContestType.allCases) { contest in
                    Button {
                        engine.contestEngine.configureContest(type: contest, myCall: engine.myCall, myGrid: engine.myGrid)
                    } label: {
                        HStack {
                            Text(contest.rawValue)
                            if engine.contestEngine.contestType == contest {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button("Reset Contest Session...", role: .destructive) {
                    engine.contestEngine.resetContestSession()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(Color.yellow)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(engine.contestEngine.contestType.shortCode)
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.primary)
                        Text(engine.contestEngine.contestType.exchangeDescription)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Divider()
                .frame(height: 28)

            // Claimed Score Card
            VStack(alignment: .leading, spacing: 1) {
                Text("CLAIMED SCORE")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(engine.contestEngine.claimedScore.formatted())
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.yellow)
            }
            .padding(.horizontal, 6)

            Divider()
                .frame(height: 28)

            // QSOs & Points & Mults
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("QSOS")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(engine.contestEngine.totalQSOs)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("POINTS")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(engine.contestEngine.totalPoints)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("MULTS")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("\(engine.contestEngine.totalMultipliers)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.orange)
                        Text("(\(engine.contestEngine.totalGridMultipliers)G·\(engine.contestEngine.totalDXCCMultipliers)D)")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
                .frame(height: 28)

            // Live Rate Meter (QSOs/hr)
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("10m RATE")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                        Text("\(engine.contestEngine.rate10Min) /hr")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Color.green)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("60m RATE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(engine.contestEngine.rate60Min) /hr")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("PEAK")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(engine.contestEngine.peakRate) /hr")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Cabrillo 3.0 Export Button
            Button {
                showCabrilloExportSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export Cabrillo 3.0")
                }
                .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            // Checksheet Popover Button
            Button {
                showChecksheetPopover.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tablecells.badge.sparkles")
                    Text("Contest Matrix")
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showChecksheetPopover) {
                DigitalContestBandMatrixView(engine: engine.contestEngine) {
                    showChecksheetPopover = false
                    showCabrilloExportSheet = true
                }
                .frame(width: 760, height: 500)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.12, blue: 0.05).opacity(0.8),
                    Color(nsColor: .controlBackgroundColor).opacity(0.8)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    // MARK: - 2.6 Smart Auto-Runner & Multi-Caller Queue HUD

    private var contestQueueHUD: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "tray.full.fill")
                        .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.15))
                        .font(.system(size: 11))
                    Text("Auto-Runner Queue")
                        .font(.system(size: 11, weight: .bold))
                    Text("(\(engine.contestEngine.queuedCallers.count))")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(engine.contestEngine.queuedCallers.isEmpty ? .secondary : Color.yellow)
                }

                Divider()
                    .frame(height: 16)

                Toggle(isOn: Binding(
                    get: { engine.contestEngine.autoEngageNext },
                    set: { engine.contestEngine.autoEngageNext = $0 }
                )) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.horizontal.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(engine.contestEngine.autoEngageNext ? Color.green : Color.secondary)
                        Text("Zero-Idle Auto-Engage")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)

                Toggle(isOn: Binding(
                    get: { engine.contestEngine.autoQueueIncomingCallers },
                    set: { engine.contestEngine.autoQueueIncomingCallers = $0 }
                )) {
                    HStack(spacing: 4) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(engine.contestEngine.autoQueueIncomingCallers ? Color.cyan : Color.secondary)
                        Text("Auto-Queue Pile-up")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)

                Spacer()

                if !engine.contestEngine.queuedCallers.isEmpty {
                    if let top = engine.contestEngine.queuedCallers.first {
                        Button {
                            if let caller = engine.contestEngine.popNextCaller() {
                                engine.engageQueuedCaller(caller)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8))
                                Text("Engage #1 (\(top.callsign))")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.orange)
                        .controlSize(.mini)
                    }

                    Button {
                        engine.contestEngine.clearQueue()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "trash")
                                .font(.system(size: 8))
                            Text("Clear")
                                .font(.system(size: 9))
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }

            if engine.contestEngine.queuedCallers.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("Pile-up queue is empty. Callers answering CQ during an active QSO will be ranked and queued automatically.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 2)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(engine.contestEngine.queuedCallers.enumerated()), id: \.element.id) { index, caller in
                            queueCard(caller: caller, rank: index + 1)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color(red: 0.12, green: 0.10, blue: 0.05).opacity(0.6))
    }

    private func queueCard(caller: ContestQueuedCaller, rank: Int) -> some View {
        HStack(spacing: 8) {
            // Rank Badge
            Text("#\(rank)")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(rank == 1 ? Color.yellow : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(caller.callsign)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)

                    if caller.contestStatus.isMultiplier {
                        Text(caller.contestStatus.badgeLabel)
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(red: 1.0, green: 0.72, blue: 0.15), in: RoundedRectangle(cornerRadius: 3))
                    } else if caller.contestStatus.isDupe {
                        Text("DUPE")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 2))
                    } else if caller.contestStatus.points > 0 {
                        Text("+\(caller.contestStatus.points) PTS")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color(red: 0.15, green: 0.75, blue: 0.38), in: RoundedRectangle(cornerRadius: 2))
                    }
                }

                HStack(spacing: 6) {
                    if !caller.countryFlag.isEmpty {
                        Text(caller.countryFlag)
                            .font(.system(size: 9))
                    }
                    if let grid = caller.grid {
                        Text(grid)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text(String(format: "%+02d dB", caller.snr))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(caller.snr >= -10 ? Color.green : Color.secondary)
                    Text("\(caller.audioFrequencyHz) Hz")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 3) {
                Button {
                    engine.engageQueuedCaller(caller)
                    engine.contestEngine.removeQueuedCaller(id: caller.id)
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("Engage this caller now")

                if rank > 1 {
                    Button {
                        engine.contestEngine.promoteQueuedCallerToTop(id: caller.id)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 8))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("Promote to top of queue")
                }

                Button {
                    engine.contestEngine.removeQueuedCaller(id: caller.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
                .foregroundStyle(.secondary)
                .help("Remove from queue")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rank == 1 ? Color.yellow.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(rank == 1 ? Color.yellow.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - 3. Smart Auto-Hunter HUD

    private var autoHunterHUD: some View {
        WrappingControlsLayout(spacing: 12) {
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

            Stepper(value: $engine.autoHunterMinSNR, in: -26...0, step: 1) {
                Text("Min SNR: \(engine.autoHunterMinSNR) dB")
                    .font(.caption2.monospacedDigit())
                    .fixedSize(horizontal: true, vertical: false)
            }
            .fixedSize(horizontal: true, vertical: false)

            Toggle("Skip Worked B4", isOn: $engine.autoHunterSkipWorked)
                .font(.caption2)
                .controlSize(.small)

            Text(engine.autoHunterStatus)
                .font(.caption2)
                .foregroundStyle(engine.autoHunterEnabled ? Color.primary : Color.secondary)
                .lineLimit(1)

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

    @ViewBuilder
    private func dualPaneConsole(compact: Bool) -> some View {
        if compact {
            VStack(spacing: 0) {
                bandActivityPane
                Divider()
                rxFrequencyPane
            }
            .frame(minHeight: 200, maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                bandActivityPane
                Divider()
                rxFrequencyPane
            }
            .frame(minHeight: 200, maxHeight: .infinity)
        }
    }

    private var bandActivityPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            bandActivityHeader
            bandActivityList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rxFrequencyPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            rxFrequencyStreamHeader
            rxFrequencyStreamList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                Menu {
                    let activeBand = engine.currentBandName.lowercased()
                    let recentCluster = appState.dxClusterClient.spots
                        .filter { $0.band.lowercased() == activeBand && (0...900).contains(Date().timeIntervalSince($0.lastSeenAt)) }
                        .sorted { $0.lastSeenAt > $1.lastSeenAt }
                    if recentCluster.isEmpty {
                        Text("No DX Cluster reports in the last 15 min")
                    } else {
                        Section("DX Cluster · last 15 min") {
                            ForEach(Array(recentCluster.prefix(8))) { spot in
                                Button("\(spot.flagEmoji) \(spot.callsign) · \(spot.mode) · \(String(format: "%.3f", spot.frequencyKHz / 1000)) MHz") {
                                    engine.dxCall = spot.callsign
                                }
                            }
                        }
                    }
                    Divider()
                    Button(bandClubLogSpots.isLoading ? "Refreshing Club Log…" : "Refresh Club Log personal spots") {
                        Task { await bandClubLogSpots.fetchPersonalSpots(credentials: appState.qslServiceCredentials(for: [.clubLog])) }
                    }
                    .disabled(bandClubLogSpots.isLoading)
                    let clubSpots = bandClubLogSpots.spots.filter {
                        guard $0.band.lowercased() == activeBand, let reported = $0.reportedAt else { return false }
                        return (0...900).contains(Date().timeIntervalSince(reported))
                    }.sorted { ($0.reportedAt ?? .distantPast) > ($1.reportedAt ?? .distantPast) }
                    if !clubSpots.isEmpty {
                        Section("Club Log · last 15 min · UTC") {
                            ForEach(Array(clubSpots.prefix(8))) { spot in
                                Button("\(spot.callsign) · \(spot.mode) · \(spot.frequency) MHz · \(spot.timeStr)") {
                                    engine.dxCall = spot.callsign
                                }
                            }
                        }
                    } else if bandClubLogSpots.lastRefreshed != nil {
                        Text("No recent Club Log reports on this band")
                    }
                    if let error = bandClubLogSpots.errorMessage, !error.isEmpty {
                        Text(error)
                    }
                } label: {
                    Label("On band", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 10, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: true, vertical: false)
                .help("Recent DX Cluster spots and Club Log personal spots on this band. Selecting a spot prepares its call only; it does not transmit.")

                Menu {
                    ForEach(1...3, id: \.self) { count in
                        Button("Keep \(count) previous cycle\(count == 1 ? "" : "s")") {
                            engine.setPreviousCycleCount(count)
                        }
                    }
                } label: {
                    Label("\(engine.previousCycleCount) prior", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: true, vertical: false)
                .help("Keep the latest decoded cycle and 1–3 previous cycles")

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
                if let latest = engine.cycleDecodeCounts.first {
                    Menu {
                        Text("Last 24 received cycles · local time")
                        ForEach(Array(engine.cycleDecodeCounts.enumerated()), id: \.offset) { _, cycle in
                            Text("\(Self.localTimeFormatter.string(from: cycle.slot)) · \(cycle.count) decodes")
                        }
                    } label: {
                        Text("Cycle \(latest.count) · Best \(engine.cycleDecodeCounts.map(\.count).max() ?? 0)")
                    }
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.cyan)
                        .menuStyle(.borderlessButton)
                        .fixedSize(horizontal: true, vertical: false)
                        .help("Latest cycle count and best count in the last 24 cycles")
                }
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
                Text("Country / State").frame(width: 130, alignment: .leading)
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
                        let visibleRows = engine.decodedRows
                        ForEach(Array(visibleRows.enumerated()), id: \.element.id) { index, row in
                            let slotIndex = Int((row.slotStart.timeIntervalSince1970 / engine.slotDuration).rounded(.down))
                            let precedingSlotIndex = index > 0
                                ? Int((visibleRows[index - 1].slotStart.timeIntervalSince1970 / engine.slotDuration).rounded(.down))
                                : nil
                            if precedingSlotIndex != slotIndex {
                                cycleDivider(for: row, slotIndex: slotIndex)
                            }
                            bandActivityRow(row)
                                .onTapGesture(count: 2) { engine.answerCallsign(row) }
                                .contextMenu {
                                    Button("Reply to \(row.callerCall ?? "Station")") { engine.answerCallsign(row) }
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

    private func cycleDivider(for row: FT8DecodedRow, slotIndex: Int) -> some View {
        let latest = engine.latestCompletedSlotStart.map {
            Int(($0.timeIntervalSince1970 / engine.slotDuration).rounded(.down))
        } ?? slotIndex
        let age = max(0, latest - slotIndex)
        let title = age == 0 ? "Latest cycle" : "\(age) cycle\(age == 1 ? "" : "s") ago"
        return HStack(spacing: 8) {
            Text("\(title) · \(Self.localTimeFormatter.string(from: row.slotStart))")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.cyan)
                .fixedSize(horizontal: true, vertical: false)
            Rectangle()
                .fill(LinearGradient(colors: [.cyan.opacity(0.8), .cyan.opacity(0.04)], startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
        }
        .padding(.horizontal, 10)
        .frame(height: 20)
        .background(Color.cyan.opacity(0.07))
        .accessibilityLabel("\(title), \(Self.localTimeFormatter.string(from: row.slotStart))")
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
                    .foregroundStyle(row.contestStatus.isDupe ? Color.secondary.opacity(0.6) : (row.isDirectedToMe ? Color.red : Color.primary))
                    .lineLimit(1)

                if engine.isContestMode {
                    if row.contestStatus.isMultiplier {
                        Text(row.contestStatus.badgeLabel)
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Color(red: 1.0, green: 0.72, blue: 0.15), in: RoundedRectangle(cornerRadius: 3))
                    } else if row.contestStatus.isDupe {
                        Text("DUPE")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 2))
                    } else if row.contestStatus.points > 0 {
                        Text("+\(row.contestStatus.points) PTS")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color(red: 0.15, green: 0.75, blue: 0.38), in: RoundedRectangle(cornerRadius: 2))
                    }
                } else {
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
                Text(row.loggedSubdivision.map { "\($0) · \(row.countryName)" } ?? row.countryName)
                    .lineLimit(1)
            }
            .font(.system(size: 10))
            .frame(width: 130, alignment: .leading)
            .help(row.loggedSubdivision.map { "\(row.countryName) · \($0) (state/province from your logbook)" } ?? row.countryName)
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
        } else if engine.isContestMode {
            if row.contestStatus.isMultiplier {
                return Color.orange.opacity(0.24)
            } else if row.contestStatus.isDupe {
                return Color.secondary.opacity(0.04)
            } else if row.isCQ || row.contestStatus.points > 0 {
                return Color.green.opacity(0.18)
            } else {
                let slotInt = Int(row.slotStart.timeIntervalSince1970 / engine.slotDuration)
                return slotInt.isMultiple(of: 2) ? Color.secondary.opacity(0.04) : Color.clear
            }
        } else if row.isNewDXCC {
            return Color.purple.opacity(0.28)
        } else if row.isCQ {
            return Color.green.opacity(0.26)
        } else {
            let slotInt = Int(row.slotStart.timeIntervalSince1970 / engine.slotDuration)
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
                        ForEach(Array(engine.qsoStreamItems.reversed())) { item in
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
                                    HStack(spacing: 4) {
                                        Text(row.text)
                                            .font(.system(size: 11, design: .monospaced).weight(.bold))
                                            .foregroundStyle(row.isDirectedToMe ? Color.red : Color.primary)

                                        if engine.isContestMode && row.contestStatus.isMultiplier {
                                            Text(row.contestStatus.badgeLabel)
                                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                                .foregroundStyle(.black)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color(red: 1.0, green: 0.72, blue: 0.15), in: RoundedRectangle(cornerRadius: 3))
                                        }
                                    }
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

            // Transmit Watchdog Badge (matches protocol slot duration: 15s for FT8, 7.5s for FT4)
            HStack(spacing: 4) {
                Image(systemName: "shield.checkered")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("Watchdog \(Int(engine.slotDuration.rounded()))s")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 14)

            // Slot & Transmit Progress
            if engine.state == .transmitting {
                HStack(spacing: 6) {
                    ProgressView(value: Double(engine.transmitProgress))
                        .frame(width: 80)
                        .tint(.red)
                    Text("TX: \((Double(engine.transmitProgress) * engine.slotDuration).formatted(.number.precision(.fractionLength(1))))s")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.red)
                        .frame(width: 75, alignment: .trailing)
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView(value: engine.slotProgress)
                        .frame(width: 80)
                        .tint(.accentColor)
                    Text("Slot: \(engine.slotRemainingSeconds.formatted(.number.precision(.fractionLength(1))))s")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(width: 75, alignment: .trailing)
                }
            }

            if engine.transmitArmed {
                Text("TX in: \(engine.secondsToNextTX.formatted(.number.precision(.fractionLength(1))))s")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(3)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Live Radio Transceiver Meters HUD (RF Power, SWR, ALC, S-Meter)
    private var radioMetersHUD: some View {
        WrappingControlsLayout(spacing: 16) {
            // Radio Model & PTT status badge
            HStack(spacing: 6) {
                Circle()
                    .fill(engine.state == .transmitting ? Color.red : Color.green)
                    .frame(width: 8, height: 8)
                Text(engine.state == .transmitting ? "TX ACTIVE" : "RX LISTENING")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(engine.state == .transmitting ? Color.red : Color.green)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((engine.state == .transmitting ? Color.red : Color.green).opacity(0.12))
            .cornerRadius(4)

            // RF Power Meter (Po)
            HStack(spacing: 6) {
                Text("PWR")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                meterBar(
                    value: engine.state == .transmitting ? min(1.0, max(0.0, engine.livePowerWatts / 100.0)) : 0.0,
                    tint: Color.cyan,
                    width: 65
                )
                Text("\(Int(engine.state == .transmitting ? engine.livePowerWatts : 0)) W")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(engine.state == .transmitting ? Color.cyan : Color.secondary)
                    .frame(width: 42, alignment: .trailing)
            }

            // SWR Meter
            HStack(spacing: 6) {
                Text("SWR")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                let swrVal = engine.state == .transmitting ? engine.liveSWR : 1.0
                let swrColor: Color = swrVal <= 1.5 ? .green : (swrVal <= 2.0 ? .orange : .red)
                meterBar(
                    value: min(1.0, max(0.0, (swrVal - 1.0) / 2.0)),
                    tint: swrColor,
                    width: 65
                )
                Text(String(format: "%.1f", swrVal))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(swrColor)
                    .frame(width: 28, alignment: .trailing)
            }

            // ALC Meter
            HStack(spacing: 6) {
                Text("ALC")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                let alcVal = engine.state == .transmitting ? engine.liveALC : 0.0
                let alcColor: Color = alcVal <= 50 ? .green : (alcVal <= 80 ? .orange : .red)
                meterBar(
                    value: min(1.0, max(0.0, alcVal / 100.0)),
                    tint: alcColor,
                    width: 65
                )
                Text("\(Int(alcVal))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(alcColor)
                    .frame(width: 34, alignment: .trailing)
            }

            Button("TX audio \(Int(engine.txGain * 100))%") {
                showTxDrivePopover.toggle()
            }
            .font(.system(size: 10, weight: .semibold))
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .popover(isPresented: $showTxDrivePopover) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Transmit audio drive")
                        .font(.headline)
                    Text("Lower this if the measured ALC is high. Changes apply to the next transmission.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { Double(engine.txGain) },
                        set: { engine.txGain = Float($0) }
                    ), in: 0.02...1.0)
                    Text("\(Int(engine.txGain * 100))% drive · ALC now \(Int(engine.liveALC))%")
                        .font(.caption.monospacedDigit())
                    Divider()
                    Toggle("Stop TX if SWR exceeds 2.5", isOn: $engine.stopTxOnHighSWR)
                        .font(.caption)
                    Text("Uses two consecutive loaded meter readings and disarms TX. Available with Icom LAN, Icom USB and Xiegu telemetry.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(width: 320)
            }

            // S-Meter / RX Signal Level
            HStack(spacing: 6) {
                Text("SIG")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                let sVal = engine.state == .transmitting ? 0.0 : engine.liveSMeter
                meterBar(
                    value: min(1.0, max(0.0, sVal / 9.0)),
                    tint: Color.green,
                    width: 65
                )
                Text(sVal >= 9.0 ? "S9+" : "S\(Int(min(9, sVal)))")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.green)
                    .frame(width: 28, alignment: .trailing)
            }

        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.25))
    }

    private func meterBar(value: Double, tint: Color, width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white.opacity(0.08))
                .frame(width: width, height: 6)
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: max(0, min(width, width * CGFloat(value))), height: 6)
        }
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

struct FT8SpectrumWaterfallView: View {
    @ObservedObject var engine: FT8EngineService
    @State private var cachedWaterfallImage: CGImage?
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
        .onAppear { cachedWaterfallImage = Self.createWaterfallImage(rows: engine.waterfallRows) }
        .onChange(of: engine.waterfallRevision) { _, _ in
            cachedWaterfallImage = Self.createWaterfallImage(rows: engine.waterfallRows)
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

            // Translucent Active Digital Filter Passband Box (SDR-Control style)
            let pbLeft = xForFrequency(minFreq + 50, width: cSize.width)
            let pbRight = xForFrequency(maxFreq - 50, width: cSize.width)
            let pbRect = CGRect(x: pbLeft, y: 0, width: max(0, pbRight - pbLeft), height: cSize.height)
            context.fill(Path(pbRect), with: .color(Color(red: 0.04, green: 0.18, blue: 0.38).opacity(0.20)))
            context.stroke(Path(pbRect), with: .color(Color(red: 0.1, green: 0.5, blue: 0.9).opacity(0.35)), lineWidth: 1.0)

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
                    Color(red: 1.0, green: 0.45, blue: 0.10).opacity(0.70), // Warm orange/red peak
                    Color(red: 0.95, green: 0.80, blue: 0.15).opacity(0.55), // Golden yellow
                    Color(red: 0.15, green: 0.85, blue: 0.40).opacity(0.40), // Emerald green mid
                    Color(red: 0.05, green: 0.35, blue: 0.70).opacity(0.20), // Cyan/blue
                    Color(red: 0.02, green: 0.08, blue: 0.20).opacity(0.05)  // Navy base
                ])
                context.fill(curvePath, with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: cSize.height)))

                // Glowing Stroke line
                var linePath = Path()
                for (idx, val) in mags.enumerated() {
                    let x = CGFloat(idx) * step
                    let y = cSize.height * (1.0 - CGFloat(min(1.0, max(0.0, val * 0.95 + 0.05))))
                    if idx == 0 { linePath.move(to: CGPoint(x: x, y: y)) } else { linePath.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(linePath, with: .color(Color(red: 0.25, green: 0.95, blue: 0.55)), lineWidth: 1.2)
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

    // Reuse the bitmap until the next spectrum row arrives. The slot clock and
    // radio meters may refresh without rebuilding every historical pixel.
    private func waterfallCanvas(size: CGSize) -> some View {
        Canvas(opaque: true, rendersAsynchronously: true) { context, cSize in
            context.fill(Path(CGRect(origin: .zero, size: cSize)), with: .color(Color(red: 0.02, green: 0.03, blue: 0.06)))

            if let cgImage = cachedWaterfallImage {
                context.draw(Image(decorative: cgImage, scale: 1.0), in: CGRect(origin: .zero, size: cSize))
            }

            let rowCount = max(1, engine.waterfallRows.count)
            for boundary in engine.waterfallCycleBoundaries where boundary < rowCount {
                let y = CGFloat(boundary + 1) * cSize.height / CGFloat(rowCount)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: cSize.width, y: y))
                context.stroke(line, with: .color(Color.cyan.opacity(0.24)), lineWidth: 5)
                context.stroke(
                    line,
                    with: .linearGradient(
                        Gradient(colors: [.cyan, .white, .cyan.opacity(0.65)]),
                        startPoint: CGPoint(x: 0, y: y),
                        endPoint: CGPoint(x: cSize.width, y: y)
                    ),
                    lineWidth: 1.5
                )
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
            // Invert row index so newest row (rows.last) appears at r = 0 (top line directly under frequency ruler)
            let row = rows[height - 1 - r]
            let rowOffset = r * width
            let colCount = min(width, row.count)
            for c in 0..<colCount {
                let index = Int(min(255, max(0, row[c] * 255)))
                pixels[rowOffset + c] = waterfallPalette[index]
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

    private static let waterfallPalette = (0...255).map { waterfallRGB32(Float($0) / 255) }

    private static func waterfallRGB32(_ rawValue: Float) -> UInt32 {
        let v = min(1.0, max(0.0, rawValue))
        let r: UInt8
        let g: UInt8
        let b: UInt8

        if v < 0.10 {
            // Inky space black to deep midnight navy (noise floor)
            let t = v / 0.10
            r = UInt8(1 * t)
            g = UInt8(2 * t)
            b = UInt8(10 * t)
        } else if v < 0.25 {
            // Faint noise: Deep navy to rich cobalt blue
            let t = (v - 0.10) / 0.15
            r = UInt8(1 + t * 5)
            g = UInt8(2 + t * 35)
            b = UInt8(10 + t * 135)
        } else if v < 0.45 {
            // Weak FT8 signal tones: Cobalt blue to electric glowing cyan
            let t = (v - 0.25) / 0.20
            r = UInt8(6 + t * 14)
            g = UInt8(37 + t * 185)
            b = UInt8(145 + t * 110)
        } else if v < 0.65 {
            // Solid FT8 tones: Electric cyan to brilliant neon emerald green
            let t = (v - 0.45) / 0.20
            r = UInt8(20 + t * 65)
            g = UInt8(222 + t * 33)
            b = UInt8(255 - t * 215)
        } else if v < 0.85 {
            // Strong signals: Neon green to bright sun yellow and amber
            let t = (v - 0.65) / 0.20
            r = UInt8(85 + t * 170)
            g = UInt8(255 - t * 45)
            b = UInt8(40 - t * 30)
        } else {
            // S9+ local signals: Flaming orange to white-hot peak
            let t = (v - 0.85) / 0.15
            r = 255
            let gVal = 210 * (1.0 - t * 0.4)
            g = UInt8(max(0, min(255, gVal)))
            b = UInt8(10 + t * 235)
        }

        return (0xFF << 24) | (UInt32(b) << 16) | (UInt32(g) << 8) | UInt32(r)
    }

    private func xForFrequency(_ freq: Float, width: CGFloat) -> CGFloat {
        let frac = CGFloat((freq - minFreq) / (maxFreq - minFreq))
        return max(0, min(width, frac * width))
    }
}

// MARK: - Contest Checksheet & Multiplier Sheet Popover

struct ContestChecksheetPopoverView: View {
    @ObservedObject var engine: DigitalContestEngine
    var onOpenCabrilloExport: (() -> Void)? = nil

    var body: some View {
        DigitalContestBandMatrixView(engine: engine, onOpenCabrilloExport: onOpenCabrilloExport)
    }
}
