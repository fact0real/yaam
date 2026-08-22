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
    @State private var credentialStatus = ""

    private var icomModel: Binding<IcomNetworkModel> {
        Binding(
            get: { IcomNetworkModel(rawValue: icomModelName) ?? .ic705 },
            set: { icomModelName = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sourceBand
            Divider()
            receiverBand
            Divider()
            transmitBand
            Divider()
            safetyBand
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

    private var sourceBand: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Label("Radio & Audio Path", systemImage: "cable.connector.horizontal")
                    .font(.headline)
                Picker("Path", selection: $engine.audioPath) {
                    ForEach(FT8AudioPath.allCases) { path in
                        Text(path.rawValue).tag(path)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 310)
                Spacer()
                statusPill(engine.state.title, active: engine.state.isMonitoring)
            }

            if engine.audioPath == .icomLAN {
                icomSettings
            } else {
                coreAudioSettings
            }

            HStack(spacing: 12) {
                Picker("FT8 band", selection: $engine.dialFrequencyHz) {
                    ForEach(FT8BandPreset.common) { preset in
                        Text(preset.label).tag(preset.frequencyHz)
                    }
                }
                .frame(width: 190)

                Button {
                    engine.applyDialAndMode()
                } label: {
                    Label("Set \(engine.formattedDial) MHz / USB-D", systemImage: "dial.medium")
                }
                .disabled(!radioPathConnected)

                Spacer()

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
                    Label(
                        engine.state.isMonitoring ? "Stop Monitoring" : "Start Monitoring",
                        systemImage: engine.state.isMonitoring ? "stop.fill" : "waveform.badge.mic"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(engine.state.isMonitoring ? .secondary : .blue)
                .disabled(!radioPathReadyForReceive && !engine.state.isMonitoring)
            }

            Text(engine.status)
                .font(.caption)
                .foregroundStyle(statusColor)
                .lineLimit(2)
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.28))
    }

    private var icomSettings: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 12) {
                field("Radio", width: 160) {
                    Picker("Radio", selection: icomModel) {
                        ForEach(IcomNetworkModel.allCases) { model in Text(model.rawValue).tag(model) }
                    }
                    .labelsHidden()
                }
                field("IP address / host", width: 190) {
                    TextField("192.168.1.120", text: $icomHost).textFieldStyle(.roundedBorder)
                }
                field("UDP control port", width: 110) {
                    TextField("50001", value: $icomPort, format: .number).textFieldStyle(.roundedBorder)
                }
                field("Icom network user", width: 150) {
                    TextField("Username", text: $icomUsername).textFieldStyle(.roundedBorder)
                }
                field("Password", width: 160) {
                    SecureField("Password", text: $icomPassword).textFieldStyle(.roundedBorder)
                }
                Button {
                    savePassword()
                } label: {
                    Image(systemName: "key.fill")
                }
                .help("Save the Icom network password in macOS Keychain")
                Button {
                    toggleIcomConnection()
                } label: {
                    Label(
                        radio.state.isConnected ? "Disconnect" : "Connect",
                        systemImage: radio.state.isConnected ? "xmark.circle" : "network"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(radio.state.isConnected ? .secondary : .blue)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Picker("Radio", selection: icomModel) {
                        ForEach(IcomNetworkModel.allCases) { model in Text(model.rawValue).tag(model) }
                    }
                    TextField("Radio IP address", text: $icomHost)
                    TextField("Port", value: $icomPort, format: .number).frame(width: 85)
                }
                HStack(spacing: 10) {
                    TextField("Icom network user", text: $icomUsername)
                    SecureField("Password", text: $icomPassword)
                    Button { savePassword() } label: { Image(systemName: "key.fill") }
                    Button { toggleIcomConnection() } label: {
                        Label(radio.state.isConnected ? "Disconnect" : "Connect", systemImage: "network")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .textFieldStyle(.roundedBorder)
        }
        .overlay(alignment: .bottomLeading) {
            Text(
                credentialStatus.isEmpty
                    ? "Radio: Network Control ON, CI-V Transceive ON, DATA MOD = WLAN"
                    : "\(credentialStatus) · DATA MOD = WLAN"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .offset(y: 14)
        }
    }

    private var coreAudioSettings: some View {
        HStack(alignment: .bottom, spacing: 14) {
            field("Receive audio", width: 270) {
                Picker("Receive audio", selection: $inputDeviceUID) {
                    Text("System Default Input").tag("")
                    ForEach(engine.inputDevices) { device in
                        Text("\(device.name) · \(device.transport)").tag(device.uid)
                    }
                }
                .labelsHidden()
            }
            field("Transmit audio", width: 270) {
                Picker("Transmit audio", selection: $outputDeviceUID) {
                    Text("System Default Output").tag("")
                    ForEach(engine.outputDevices) { device in
                        Text("\(device.name) · \(device.transport)").tag(device.uid)
                    }
                }
                .labelsHidden()
            }
            Button {
                engine.refreshAudioDevices()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh Core Audio devices")
            Divider().frame(height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text("RIGCTLD PTT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Label(rig.lastMessage, systemImage: rig.state.isConnected ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(rig.state.isConnected ? .green : .orange)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var receiverBand: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Live Receiver", systemImage: "waveform.path.ecg.rectangle")
                    .font(.headline)
                Spacer()
                Text("UTC slots · :00  :15  :30  :45")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button("Clear") { engine.clearDecodes() }
                    .disabled(engine.decodedRows.isEmpty)
            }

            FT8WaterfallView(rows: engine.waterfallRows)
                .frame(height: 150)
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 8) {
                        Text("200 Hz")
                        Spacer()
                        Text("FT8 AUDIO PASSBAND")
                        Spacer()
                        Text("3000 Hz")
                    }
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(8)
                }

            decodeHeader
            if engine.decodedRows.isEmpty {
                ContentUnavailableView(
                    "No FT8 Decodes Yet",
                    systemImage: "waveform",
                    description: Text("Start monitoring and allow one complete UTC slot before judging the receive path.")
                )
                .frame(maxWidth: .infinity, minHeight: 130)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(engine.decodedRows.prefix(80)) { row in
                        decodeRow(row)
                        Divider()
                    }
                }
            }
        }
        .padding(20)
    }

    private var decodeHeader: some View {
        HStack(spacing: 12) {
            Text("UTC").frame(width: 76, alignment: .leading)
            Text("EST dB").frame(width: 54, alignment: .trailing)
            Text("DT").frame(width: 50, alignment: .trailing)
            Text("AUDIO").frame(width: 64, alignment: .trailing)
            Text("MESSAGE").frame(maxWidth: .infinity, alignment: .leading)
            Text("ACTION").frame(width: 72)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
    }

    private func decodeRow(_ row: FT8DecodedRow) -> some View {
        HStack(spacing: 12) {
            Text(Self.utcTimeFormatter.string(from: row.slotStart))
                .frame(width: 76, alignment: .leading)
            Text(row.estimatedSNR.formatted(.number.precision(.fractionLength(0))))
                .frame(width: 54, alignment: .trailing)
            Text(row.timeOffset.formatted(.number.precision(.fractionLength(1))))
                .frame(width: 50, alignment: .trailing)
            Text("\(Int(row.audioFrequencyHz.rounded()))")
                .frame(width: 64, alignment: .trailing)
            Text(row.text)
                .font(.system(.body, design: .monospaced).weight(row.isDirectedToMe ? .bold : .regular))
                .foregroundStyle(row.isDirectedToMe ? Color.orange : Color.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                engine.selectForReply(row)
            } label: {
                Image(systemName: "arrowshape.turn.up.left.fill")
            }
            .buttonStyle(.borderless)
            .frame(width: 72)
            .help("Prepare the standard FT8 reply sequence")
            .disabled(row.parsed?.deCall == nil)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(engine.selectedDecodeID == row.id ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { engine.selectForReply(row) }
    }

    private var transmitBand: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Label("FT8 Transmit", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                statusPill("Phase: \(engine.sequencePhase)", active: engine.sequencePhase != "Manual")
                Spacer()
                Toggle("Arm TX", isOn: $engine.transmitArmed)
                    .toggleStyle(.switch)
                    .tint(.red)
                    .font(.headline)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 14) { transmitControls }
                VStack(alignment: .leading, spacing: 12) { transmitControls }
            }

            HStack(spacing: 10) {
                Button {
                    engine.beginCQ()
                } label: {
                    Label("Prepare CQ", systemImage: "megaphone")
                }
                Button {
                    if case .waiting = engine.state {
                        engine.cancelTransmission()
                    } else if engine.state == .transmitting {
                        engine.cancelTransmission()
                    } else {
                        engine.scheduleTransmission()
                    }
                } label: {
                    Label(transmitButtonTitle, systemImage: transmitButtonIcon)
                }
                .buttonStyle(.borderedProminent)
                .tint(isTransmissionPending ? .red : .blue)
                .disabled(!engine.transmitArmed && !isTransmissionPending)

                Toggle("Auto sequence", isOn: $engine.autoSequenceEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!engine.transmitArmed)

                Spacer()
                ProgressView(value: engine.transmitProgress)
                    .frame(width: 150)
                    .opacity(engine.state == .transmitting ? 1 : 0.35)
                Text("Next \(engine.txParity == .even ? "even" : "odd") slot in \(engine.secondsToNextTX.formatted(.number.precision(.fractionLength(1)))) s")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 190, alignment: .trailing)
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.28))
    }

    @ViewBuilder
    private var transmitControls: some View {
        field("Station", width: 120) {
            Text(engine.myCall.isEmpty ? "No callsign" : engine.myCall)
                .font(.system(.body, design: .monospaced).weight(.bold))
        }
        field("Grid", width: 80) {
            Text(engine.myGrid.isEmpty ? "----" : engine.myGrid)
                .font(.system(.body, design: .monospaced).weight(.bold))
        }
        field("TX sequence", width: 150) {
            Picker("TX sequence", selection: $engine.txParity) {
                Text("1st · :00 / :30").tag(SlotParity.even)
                Text("2nd · :15 / :45").tag(SlotParity.odd)
            }
            .labelsHidden()
        }
        field("Audio offset · \(Int(engine.txAudioFrequencyHz)) Hz", width: 230) {
            Slider(value: $engine.txAudioFrequencyHz, in: 300...2_900, step: 10)
        }
        field("Drive · \(Int(engine.txGain * 100))%", width: 180) {
            Slider(value: $engine.txGain, in: 0.02...1, step: 0.01)
        }
        field("Message", width: 330) {
            TextField("CQ EP2AES LM55", text: $engine.txText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
    }

    private var safetyBand: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "shield.checkered")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Transmit safety").font(.headline)
                Text("TX must be armed for every session. A hard 16-second watchdog releases PTT even if audio, networking, or the task stalls. Begin into a dummy load or minimum RF power, verify ALC is not active, and keep the Mac clock synchronized to UTC.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The displayed dB value is an estimate from the decoder's synchronization score; use it for relative comparison, not calibrated S-meter measurements.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    engine.runSelfTest()
                } label: {
                    Label("Run Offline Self-Test", systemImage: "checkmark.shield")
                }
                Text(engine.selfTestStatus)
                    .font(.caption2)
                    .foregroundStyle(engine.selfTestStatus.hasPrefix("Passed") ? .green : .secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 330, alignment: .trailing)
            }
        }
        .padding(20)
    }

    private var radioPathConnected: Bool {
        engine.audioPath == .icomLAN ? radio.state.isConnected : rig.state.isConnected
    }

    private var radioPathReadyForReceive: Bool {
        engine.audioPath == .icomLAN ? radio.state.isConnected : !engine.inputDevices.isEmpty
    }

    private var statusColor: Color {
        if case .failed = engine.state { return .red }
        return engine.state.isMonitoring ? .green : .secondary
    }

    private var isTransmissionPending: Bool {
        if case .waiting = engine.state { return true }
        return engine.state == .transmitting
    }

    private var transmitButtonTitle: String {
        if isTransmissionPending { return "Cancel TX" }
        return "Send at Next Slot"
    }

    private var transmitButtonIcon: String {
        isTransmissionPending ? "stop.circle.fill" : "paperplane.fill"
    }

    private func toggleIcomConnection() {
        if radio.state.isConnected {
            engine.stopMonitoring()
            radio.disconnect()
            return
        }
        savePassword()
        radio.connect(
            settings: IcomNetworkSettings(
                host: icomHost,
                controlPort: icomPort,
                username: icomUsername,
                clientName: icomClientName,
                model: icomModel.wrappedValue
            ),
            password: icomPassword
        )
    }

    private func savePassword() {
        credentialStatus = CredentialVault.set(icomPassword, for: .icomNetworkPassword)
            ? "Password saved in macOS Keychain"
            : "The password could not be saved"
    }

    private func loadIdentity() {
        engine.configureStation(
            callsign: appState.currentStationCallsign,
            grid: appState.activeStationProfile?.normalizedGrid ?? ""
        )
    }

    private func field<Content: View>(_ title: String, width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(width: width, alignment: .leading)
    }

    private func statusPill(_ text: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Circle().fill(active ? Color.green : Color.secondary).frame(width: 6, height: 6)
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1), in: Capsule())
    }
}

private struct FT8WaterfallView: View {
    let rows: [[Float]]

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: true) { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black))
            guard let columns = rows.last?.count, columns > 0, !rows.isEmpty else {
                drawGuide(in: &context, size: size)
                return
            }
            let cellWidth = size.width / CGFloat(columns)
            let cellHeight = size.height / CGFloat(rows.count)
            for (rowIndex, row) in rows.enumerated() {
                let y = CGFloat(rowIndex) * cellHeight
                for (column, value) in row.enumerated() {
                    let rect = CGRect(
                        x: CGFloat(column) * cellWidth,
                        y: y,
                        width: cellWidth + 0.5,
                        height: cellHeight + 0.5
                    )
                    context.fill(Path(rect), with: .color(waterfallColor(value)))
                }
            }
            drawGuide(in: &context, size: size)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("Live FT8 audio waterfall")
    }

    private func drawGuide(in context: inout GraphicsContext, size: CGSize) {
        for fraction in [0.25, 0.5, 0.75] {
            var path = Path()
            let x = size.width * fraction
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
        }
    }

    private func waterfallColor(_ rawValue: Float) -> Color {
        let value = Double(min(1, max(0, rawValue)))
        switch value {
        case 0..<0.2:
            return Color(red: 0.02, green: 0.05 + value * 0.25, blue: 0.12 + value * 0.7)
        case 0.2..<0.5:
            let t = (value - 0.2) / 0.3
            return Color(red: 0.02, green: 0.22 + t * 0.62, blue: 0.52 + t * 0.28)
        case 0.5..<0.78:
            let t = (value - 0.5) / 0.28
            return Color(red: 0.08 + t * 0.88, green: 0.84, blue: 0.8 - t * 0.66)
        default:
            let t = (value - 0.78) / 0.22
            return Color(red: 0.96, green: 0.84 - t * 0.68, blue: 0.14 - t * 0.08)
        }
    }
}
