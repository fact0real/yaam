//
//  CWHardwareSetupSheet.swift
//  YAAM
//
//  Unified CW Hardware Keying Configuration Panel
//  Supports K1EL WinKeyer (WK2/WK3), Serial DTR/RTS Pin Keying, and CAT Morse.
//

import SwiftUI

public struct CWHardwareSetupSheet: View {
    @ObservedObject private var wk = WinKeyerDriver.shared
    @ObservedObject private var sk = SerialKeyerDriver.shared
    @ObservedObject private var rigCtl = RigControlClient.shared
    @ObservedObject private var flRig = FLRigClient.shared
    @ObservedObject private var keyer = CWKeyerService.shared
    @ObservedObject private var tx500 = Lab599TX500Driver.shared
    @ObservedObject private var icom = IcomUSBRadioDriver.shared
    @ObservedObject private var fx4cr = FX4CRDriver.shared
    @ObservedObject private var xiegu = Xiegu6100Driver.shared

    @State private var selectedTab: Int = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "cable.connector.horizontal")
                    .font(.title2)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CW Keyer Hardware Setup")
                        .font(.headline)
                    Text("Configure hardware transceivers, WinKeyer, Serial DTR/RTS, or CAT Morse keying")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Current Active Mode Status Pill
                let status = keyer.hardwareStatusSummary
                HStack(spacing: 6) {
                    Circle()
                        .fill(status.isConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(status.title)
                            .font(.caption.bold())
                            .foregroundColor(status.isConnected ? .primary : .orange)
                        Text(status.detail)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(status.isConnected ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(status.isConnected ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // Mode tabs
            Picker("", selection: $selectedTab) {
                Label("Icom USB", systemImage: "radio.fill").tag(0)
                Label("Xiegu X6100", systemImage: "radio.fill").tag(1)
                Label("FX-4CR", systemImage: "antenna.radiowaves.left.and.right").tag(2)
                Label("Lab599 TX-500", systemImage: "bolt.horizontal.fill").tag(3)
                Label("WinKeyer", systemImage: "cable.connector.horizontal").tag(4)
                Label("Serial DTR/RTS", systemImage: "cable.connector").tag(5)
                Label("CAT Morse", systemImage: "waveform").tag(6)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                switch selectedTab {
                case 0: icomUSBPanel
                case 1: xiegu6100Panel
                case 2: fx4crPanel
                case 3: tx500Panel
                case 4: winKeyerPanel
                case 5: serialPinPanel
                case 6: catMorsePanel
                default: EmptyView()
                }
            }
        }
        .frame(width: 680, height: 580)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            icom.refreshPorts()
            xiegu.refreshPorts()
            fx4cr.refreshPorts()
            tx500.refreshPorts()
            wk.refreshPorts()
            sk.refreshPorts()
            // Open to tab matching current mode
            switch keyer.transmissionMode {
            case .icomUSB: selectedTab = 0
            case .xiegu6100: selectedTab = 1
            case .fx4cr: selectedTab = 2
            case .lab599TX500: selectedTab = 3
            case .winkeyer: selectedTab = 4
            case .serialDTR_RTS: selectedTab = 5
            case .catMorse:
                if xiegu.isConnected {
                    selectedTab = 1
                } else if fx4cr.isConnected {
                    selectedTab = 2
                } else if tx500.isConnected {
                    selectedTab = 3
                } else if icom.isConnected {
                    selectedTab = 0
                } else {
                    selectedTab = 6
                }
            default: break
            }
        }
    }

    // MARK: - WinKeyer Tab

    private var winKeyerPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Port Connection
            settingsGroup("USB Serial Connection") {
                HStack(spacing: 10) {
                    Picker("Serial Port", selection: $wk.selectedPort) {
                        if wk.availableSerialPorts.isEmpty {
                            Text("No serial ports found").tag("")
                        }
                        ForEach(wk.availableSerialPorts, id: \.self) { port in
                            Text(port.components(separatedBy: "/").last ?? port).tag(port)
                        }
                    }
                    .frame(maxWidth: 240)

                    Button { wk.refreshPorts() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh serial ports")

                    Spacer()

                    if wk.isConnected {
                        Button("Disconnect", role: .destructive) { wk.disconnect() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Connect") { wk.connect() }
                            .buttonStyle(.borderedProminent)
                            .disabled(wk.selectedPort.isEmpty)
                    }
                }

                if wk.isConnected {
                    HStack(spacing: 8) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text(wk.wkVersion)
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    }
                }
            }

            if wk.isConnected {
                // Keyer Mode
                settingsGroup("Keyer Mode") {
                    HStack(spacing: 10) {
                        Picker("Paddle Mode", selection: $wk.mode) {
                            ForEach(WinKeyerMode.allCases) { m in
                                Text(m.title).tag(m)
                            }
                        }
                        .frame(maxWidth: 220)
                        .onChange(of: wk.mode) { _, _ in wk.setMode(wk.mode) }

                        Toggle("Swap Paddles", isOn: $wk.paddleSwap)
                            .onChange(of: wk.paddleSwap) { _, _ in wk.setMode(wk.mode) }

                        Toggle("Auto-Space", isOn: $wk.autoSpace)
                            .onChange(of: wk.autoSpace) { _, _ in wk.setMode(wk.mode) }
                    }
                }

                // Timing Parameters
                settingsGroup("Timing & Delays") {
                    VStack(spacing: 10) {
                        sliderRow(
                            label: "PTT Lead-In",
                            value: Binding(get: { Double(wk.pttLeadInMs) }, set: { wk.pttLeadInMs = Int($0) }),
                            range: 0...500,
                            unit: "ms",
                            help: "Time to assert PTT before first key element (protects linear amplifier relay)"
                        ) { wk.setPTTDelays(leadInMs: wk.pttLeadInMs, tailMs: wk.pttTailMs) }

                        sliderRow(
                            label: "PTT Tail",
                            value: Binding(get: { Double(wk.pttTailMs) }, set: { wk.pttTailMs = Int($0) }),
                            range: 0...500,
                            unit: "ms",
                            help: "Time to hold PTT after last element (allows final RF burst to settle)"
                        ) { wk.setPTTDelays(leadInMs: wk.pttLeadInMs, tailMs: wk.pttTailMs) }

                        sliderRow(
                            label: "Keying Compensation",
                            value: Binding(get: { Double(wk.keyingCompensationMs) }, set: { wk.keyingCompensationMs = Int($0) }),
                            range: 0...31,
                            unit: "ms",
                            help: "Compensates for slow T/R relay switch time (adds to all marks)"
                        ) { wk.setKeyingCompensation(wk.keyingCompensationMs) }

                        sliderRow(
                            label: "Sidetone Pitch",
                            value: Binding(get: { Double(wk.sidetoneHz) }, set: { wk.sidetoneHz = Int($0) }),
                            range: 400...1000,
                            unit: "Hz",
                            help: "Hardware sidetone frequency generated by WinKeyer chip"
                        ) { wk.setSidetone(wk.sidetoneHz) }

                        sliderRow(
                            label: "Dit/Dah Weighting",
                            value: Binding(get: { Double(wk.ditDahRatio) }, set: { wk.ditDahRatio = Int($0) }),
                            range: 20...80,
                            unit: "%",
                            help: "50 = standard 1:3 ratio. Higher values lengthen marks relative to spaces."
                        ) { wk.setDitDahRatio(wk.ditDahRatio) }
                    }
                }

                // Test Transmitter
                settingsGroup("Hardware Test") {
                    HStack(spacing: 12) {
                        Button {
                            wk.testKeyPulse()
                        } label: {
                            Label("Send Test Dit (E)", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            keyer.transmissionMode = .winkeyer
                        } label: {
                            Label("Use WinKeyer as Active Mode", systemImage: "checkmark.seal.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(20)
    }

    // MARK: - Serial DTR/RTS Tab

    private var serialPinPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup("USB Serial Connection") {
                HStack(spacing: 10) {
                    Picker("Serial Port", selection: $sk.selectedPort) {
                        if sk.availablePorts.isEmpty {
                            Text("No serial ports found").tag("")
                        }
                        ForEach(sk.availablePorts, id: \.self) { port in
                            Text(port.components(separatedBy: "/").last ?? port).tag(port)
                        }
                    }
                    .frame(maxWidth: 240)

                    Button { sk.refreshPorts() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    if sk.isConnected {
                        Button("Disconnect", role: .destructive) { sk.disconnect() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Connect") { sk.connect() }
                            .buttonStyle(.borderedProminent)
                            .disabled(sk.selectedPort.isEmpty)
                    }
                }
                if sk.isConnected {
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text(sk.statusMessage)
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    }
                }
            }

            settingsGroup("Pin Assignments") {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CW Key Pin").font(.caption.bold())
                        Picker("CW Pin", selection: $sk.cwPin) {
                            ForEach(SerialControlPin.allCases) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                        .frame(width: 160)
                        .labelsHidden()
                        Text("Assert this pin for mark (key-down)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("PTT Pin").font(.caption.bold())
                        Picker("PTT Pin", selection: $sk.pttPin) {
                            ForEach(SerialControlPin.allCases) { p in
                                Text(p.rawValue).tag(p)
                            }
                        }
                        .frame(width: 160)
                        .labelsHidden()
                        Text("Asserted during transmission")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Polarity").font(.caption.bold())
                        Toggle("Invert Lines (Active-Low)", isOn: $sk.isInverted)
                        Text("For optoisolated/open-collector interfaces")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            settingsGroup("PTT Timing Delays") {
                VStack(spacing: 10) {
                    sliderRow(
                        label: "PTT Lead-In",
                        value: Binding(get: { Double(sk.pttLeadInMs) }, set: { sk.pttLeadInMs = Int($0) }),
                        range: 0...500,
                        unit: "ms",
                        help: "Time PTT is asserted before first dit/dah"
                    ) {}

                    sliderRow(
                        label: "PTT Tail",
                        value: Binding(get: { Double(sk.pttTailMs) }, set: { sk.pttTailMs = Int($0) }),
                        range: 0...500,
                        unit: "ms",
                        help: "Time PTT is held after last dit/dah"
                    ) {}
                }
            }

            if sk.isConnected {
                settingsGroup("Hardware Test") {
                    HStack(spacing: 12) {
                        Button {
                            sk.testKeyPulse()
                        } label: {
                            Label("Send Test Pulse (70ms key-down)", systemImage: "bolt.fill")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            keyer.transmissionMode = .serialDTR_RTS
                        } label: {
                            Label("Use DTR/RTS as Active Mode", systemImage: "checkmark.seal.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(20)
    }

    // MARK: - CAT Morse Tab

    private var catMorsePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup("FX-4CR CAT Morse (Kenwood KY Chunking & KS Speed)") {
                HStack(spacing: 8) {
                    Circle()
                        .fill(fx4cr.isConnected ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(fx4cr.isConnected ? "FX-4CR Connected via \(fx4cr.connectionType.rawValue) — TS-590S KY/KS available" : "FX-4CR Offline")
                        .font(.callout)
                }

                if fx4cr.isConnected {
                    Text("YAAM transmits Morse code directly to the FX-4CR's internal keyer over Kenwood TS-590S CAT. Text is automatically chunked into 24-character blocks with auto-pacing, and keyer speed is synchronized via `KS<wpm>;`.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Connect your FX-4CR via USB-C or Bluetooth in the FX-4CR tab or Rig Control toolbar to enable direct CAT Morse.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            settingsGroup("Hamlib rigctld (\\send_morse)") {
                let rigState = RigControlClient.shared.state
                HStack(spacing: 8) {
                    Circle()
                        .fill(rigState.isConnected ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(rigState.isConnected ? "Hamlib rigctld Connected — \\send_morse available" : "Hamlib rigctld Offline")
                        .font(.callout)
                }

                if rigState.isConnected {
                    Text("YAAM will send Morse text directly to your transceiver's internal keyer using `b <text>` and control keyer speed with `L KEYSPD <wpm>`.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Connect your transceiver via Rig Control (Operator Desk → Rig Control tab) to enable Hamlib CAT Morse.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            settingsGroup("FLRig XML-RPC (rig.send_morse)") {
                HStack(spacing: 8) {
                    Circle()
                        .fill(FLRigClient.shared.isConnected ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(FLRigClient.shared.isConnected ? "FLRig Connected — rig.send_morse available" : "FLRig Offline")
                        .font(.callout)
                }

                if FLRigClient.shared.isConnected {
                    Text("YAAM will send Morse text directly via FLRig's XML-RPC `rig.send_morse` command. The transceiver's internal CW keyer handles the timing.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            settingsGroup("Priority & Activation") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("When CAT Morse mode is active, YAAM transmits using this priority order:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Text("①").foregroundColor(.accentColor).bold()
                        Text("FX-4CR Direct CAT Morse (Kenwood KY chunked buffer)")
                    }.font(.callout)

                    HStack(spacing: 8) {
                        Text("②").foregroundColor(.accentColor).bold()
                        Text("Icom USB CI-V (Command 17 Direct Keyer)")
                    }.font(.callout)

                    HStack(spacing: 8) {
                        Text("③").foregroundColor(.accentColor).bold()
                        Text("Hamlib rigctld (\\ send_morse command)")
                    }.font(.callout)

                    HStack(spacing: 8) {
                        Text("④").foregroundColor(.accentColor).bold()
                        Text("FLRig XML-RPC (rig.send_morse method)")
                    }.font(.callout)

                    Button {
                        keyer.transmissionMode = .catMorse
                    } label: {
                        Label("Use CAT Morse as Active Mode", systemImage: "checkmark.seal.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
            }
        }
        .padding(20)
    }

    // MARK: - Lab599 TX-500 Tab

    private var tx500Panel: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup("USB Serial Connection (AD-514/AD-502)") {
                HStack(spacing: 10) {
                    Picker("Serial Port", selection: Binding(get: { tx500.selectedPort }, set: { tx500.selectedPort = $0 })) {
                        if tx500.availablePorts.isEmpty {
                            Text("No serial ports found").tag("")
                        }
                        ForEach(tx500.availablePorts, id: \.self) { port in
                            Text(port.components(separatedBy: "/").last ?? port).tag(port)
                        }
                    }
                    .frame(maxWidth: 240)

                    Button { tx500.refreshPorts() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh serial ports")

                    Spacer()

                    if tx500.isConnected {
                        Button("Disconnect", role: .destructive) { tx500.disconnect() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Connect") { tx500.connect() }
                            .buttonStyle(.borderedProminent)
                            .disabled(tx500.selectedPort.isEmpty)
                    }
                }

                if tx500.isConnected {
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text(tx500.lastMessage)
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    }
                }
            }

            settingsGroup("Kenwood CAT Morse (KY Buffer & KS Speed)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("In CAT Morse mode, YAAM transmits text directly to the TX-500's internal keyer using Kenwood `KY <text>;` commands and sets internal keyer speed with `KS<wpm>;`.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Text("Current Speed:")
                            .font(.caption.bold())
                        Text("\(keyer.wpm) WPM")
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundColor(.accentColor)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("Radio Setup: Menu 34 = TS2000 • Menu 35 = 9600 • Front-panel Mode = CW")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if tx500.isConnected {
                settingsGroup("Hardware CW Transmission Test") {
                    HStack(spacing: 12) {
                        Button {
                            tx500.sendMorse("E", wpm: keyer.wpm)
                        } label: {
                            Label("Send Test Dit (E)", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            tx500.sendMorse("TEST DE \(keyer.macros.first?.template.contains("CQ") == true ? "EP2AES" : "YAAM")", wpm: keyer.wpm)
                        } label: {
                            Label("Send Test Text", systemImage: "paperplane.fill")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            keyer.transmissionMode = .lab599TX500
                        } label: {
                            Label("Use TX-500 as Active CW Mode", systemImage: "checkmark.seal.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(20)
    }

    // MARK: - Xiegu X6100 Tab

    private var xiegu6100Panel: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup("Xiegu X6100 USB-C Serial Connection (DEV Port)") {
                HStack(spacing: 10) {
                    Picker("Serial Port", selection: Binding(get: { xiegu.selectedPort }, set: { xiegu.selectedPort = $0 })) {
                        if xiegu.availablePorts.isEmpty {
                            Text("No serial ports found").tag("")
                        }
                        ForEach(xiegu.availablePorts, id: \.self) { port in
                            Text(port.components(separatedBy: "/").last ?? port).tag(port)
                        }
                    }
                    .frame(maxWidth: 240)

                    Button { xiegu.refreshPorts() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh serial ports")

                    Spacer()

                    if xiegu.isConnected {
                        Button("Disconnect", role: .destructive) { xiegu.disconnect() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Connect") { xiegu.connect() }
                            .buttonStyle(.borderedProminent)
                            .disabled(xiegu.selectedPort.isEmpty)
                    }
                }

                if xiegu.isConnected {
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text(xiegu.lastMessage)
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    }
                }
            }

            settingsGroup("Keying & Hardware Pin Options") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Key Transceiver via CI-V CAT Command 17 (Direct ASCII Morse Buffer)", isOn: .constant(true))
                        .disabled(true)
                        .font(.caption)

                    Toggle("Hardware DTR CW Keying (DEV port DTR line keys transmitter)", isOn: Binding(get: { xiegu.enableHardwareDTRCW }, set: { xiegu.enableHardwareDTRCW = $0 }))
                        .font(.caption)

                    Toggle("Hardware RTS PTT (DEV port RTS line asserts TX)", isOn: Binding(get: { xiegu.enableHardwareRTSPTT }, set: { xiegu.enableHardwareRTSPTT = $0 }))
                        .font(.caption)
                }
            }

            settingsGroup("CI-V Protocol Details & Keyer Settings") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("In Xiegu X6100 mode, YAAM transmits text directly to the radio's internal keyer using CI-V Command 0x17 and sets keyer speed using Command 0x14 0x0C.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Text("Keyer Speed:")
                            .font(.caption.bold())
                        Text("\(keyer.wpm) WPM")
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundColor(.accentColor)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("Radio Setup: CI-V Baud: \(xiegu.baudRate) • CI-V Address: 0x\(xiegu.civAddressHex) • Front-panel Mode: CW")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if xiegu.isConnected {
                settingsGroup("Hardware CW Transmission Test") {
                    HStack(spacing: 12) {
                        Button {
                            xiegu.setKeyerSpeed(keyer.wpm)
                            xiegu.sendMorse("E")
                        } label: {
                            Label("Send Test Dit (E)", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            xiegu.setKeyerSpeed(keyer.wpm)
                            xiegu.sendMorse("TEST YAAM DE X6100")
                        } label: {
                            Label("Send Test Text", systemImage: "paperplane.fill")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            keyer.transmissionMode = .xiegu6100
                        } label: {
                            Label("Use Xiegu X6100 as Active CW Mode", systemImage: "checkmark.seal.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(20)
    }

    // MARK: - FX-4CR Tab

    private var fx4crPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup("FX-4CR Transport Link & Serial Port") {
                HStack(spacing: 12) {
                    Picker("Transport", selection: Binding(get: { fx4cr.connectionType }, set: { fx4cr.connectionType = $0 })) {
                        ForEach(FX4CRConnectionType.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .frame(width: 170)

                    Picker("Port", selection: Binding(get: { fx4cr.selectedPort }, set: { fx4cr.selectedPort = $0 })) {
                        if fx4cr.availablePorts.isEmpty {
                            Text("No matching ports").tag("")
                        }
                        ForEach(fx4cr.availablePorts, id: \.self) { port in
                            Text(port.components(separatedBy: "/").last ?? port).tag(port)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Button { fx4cr.refreshPorts() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh serial ports")

                    if fx4cr.isConnected {
                        Button("Disconnect", role: .destructive) { fx4cr.disconnect() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Connect") { fx4cr.connect() }
                            .buttonStyle(.borderedProminent)
                            .disabled(fx4cr.selectedPort.isEmpty)
                    }
                }

                if fx4cr.isConnected {
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("FX-4CR Connected via \(fx4cr.connectionType.rawValue) • \(fx4cr.formattedFrequency) \(fx4cr.mode)")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    }
                }
            }

            settingsGroup("Kenwood CAT Morse (KY Chunking & KS Speed)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("YAAM sends Morse code text directly to the FX-4CR's internal keyer over Kenwood TS-590S CAT. Text is automatically chunked into 24-character blocks (`KY <chunk>;`) with auto-pacing, and keyer speed is synchronized via `KS<wpm>;`.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Text("Current Speed:")
                            .font(.caption.bold())
                        Text("\(keyer.wpm) WPM")
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundColor(.accentColor)

                        Spacer()

                        Text("Baud: 115200 8N1")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text(fx4cr.transport == .usb
                             ? "USB: Radio Menu 'Bluetooth = 0 (Off)' & use USB-A adapter. Set mode to CW."
                             : "Bluetooth: Radio Menu 'Bluetooth = 1 (On)' & pair in macOS System Settings. Set mode to CW.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if fx4cr.isConnected {
                settingsGroup("Hardware CW Transmission Test") {
                    HStack(spacing: 12) {
                        Button {
                            fx4cr.sendMorse("E", wpm: keyer.wpm)
                        } label: {
                            Label("Send Test Dit (E)", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            fx4cr.sendMorse("TEST DE \(keyer.macros.first?.template.contains("CQ") == true ? "EP2AES" : "YAAM")", wpm: keyer.wpm)
                        } label: {
                            Label("Send Test Text", systemImage: "paperplane.fill")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            keyer.transmissionMode = .fx4cr
                        } label: {
                            Label("Use FX-4CR as Active Mode", systemImage: "checkmark.seal.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(20)
    }

    // MARK: - Icom USB Tab

    private var icomUSBPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup("Icom Transceiver USB Connection") {
                HStack(spacing: 10) {
                    Picker("Model", selection: Binding(get: { icom.model }, set: { icom.model = $0 })) {
                        ForEach(IcomUSBModel.allCases) { m in
                            Label(m.rawValue, systemImage: m.iconName).tag(m)
                        }
                    }
                    .frame(maxWidth: 150)

                    Picker("Serial Port", selection: Binding(get: { icom.selectedPort }, set: { icom.selectedPort = $0 })) {
                        if icom.availablePorts.isEmpty {
                            Text("No serial ports found").tag("")
                        }
                        ForEach(icom.availablePorts, id: \.self) { port in
                            Text(port.components(separatedBy: "/").last ?? port).tag(port)
                        }
                    }
                    .frame(maxWidth: 200)

                    Button { icom.refreshPorts() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh serial ports")

                    Spacer()

                    if icom.isConnected {
                        Button("Disconnect", role: .destructive) { icom.disconnect() }
                            .buttonStyle(.bordered)
                    } else {
                        Button("Connect") { icom.connect() }
                            .buttonStyle(.borderedProminent)
                            .disabled(icom.selectedPort.isEmpty)
                    }
                }

                if icom.isConnected {
                    HStack(spacing: 8) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("\(icom.model.rawValue) Connected @ \(icom.baudRate) bps • CI-V Addr: 0x\(icom.customCivAddressHex)")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    }
                }
            }

            settingsGroup("Keying & Hardware Pin Options") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Key Transceiver via CI-V CAT Command 17 (Direct ASCII Morse Buffer)", isOn: .constant(true))
                        .disabled(true)
                        .font(.caption)

                    Toggle("Hardware DTR CW Keying (Menu -> Connectors -> USB Keying: DTR)", isOn: Binding(get: { icom.enableHardwareDTRCW }, set: { icom.enableHardwareDTRCW = $0 }))
                        .font(.caption)

                    Toggle("Hardware RTS PTT (Menu -> Connectors -> USB SEND: RTS)", isOn: Binding(get: { icom.enableHardwareRTSPTT }, set: { icom.enableHardwareRTSPTT = $0 }))
                        .font(.caption)
                }
            }

            settingsGroup("Icom CI-V Protocol Details & Keyer Settings") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("In Icom USB mode, YAAM transmits text directly to the radio's internal keyer using CI-V Command 0x17 and sets keyer speed using Command 0x14 0x0C.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        Text("Keyer Speed:")
                            .font(.caption.bold())
                        Text("\(keyer.wpm) WPM")
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundColor(.accentColor)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("Radio Setup: Menu -> Connectors -> CI-V Baud: \(icom.baudRate) • CI-V Address: \(icom.customCivAddressHex)h • Front-panel Mode: CW")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if icom.isConnected {
                settingsGroup("Hardware CW Transmission Test") {
                    HStack(spacing: 12) {
                        Button {
                            icom.setKeyerSpeed(keyer.wpm)
                            icom.sendMorse("E")
                        } label: {
                            Label("Send Test Dit (E)", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            icom.setKeyerSpeed(keyer.wpm)
                            icom.sendMorse("TEST YAAM DE ICOM")
                        } label: {
                            Label("Send Test Text", systemImage: "paperplane.fill")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            keyer.transmissionMode = .icomUSB
                        } label: {
                            Label("Set Icom USB as Active CW Mode", systemImage: "checkmark.seal.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(20)
    }

    // MARK: - Helpers

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .tracking(1)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
    }

    private func sliderRow(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        unit: String,
        help: String,
        onChanged: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption.bold())
                .frame(width: 150, alignment: .trailing)
                .help(help)

            Slider(value: value, in: range, step: 1)
                .onChange(of: value.wrappedValue) { _, _ in onChanged() }

            Text("\(Int(value.wrappedValue)) \(unit)")
                .font(.system(.caption, design: .monospaced).bold())
                .frame(width: 56, alignment: .leading)
        }
    }
}
