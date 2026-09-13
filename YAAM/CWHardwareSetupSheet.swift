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
                    Text("CW Hardware Keying Setup")
                        .font(.headline.bold())
                    Text("Configure how YAAM physically transmits Morse code to your transceiver")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                // Live status badge
                let status = keyer.hardwareStatusSummary
                HStack(spacing: 5) {
                    Circle()
                        .fill(status.isConnected ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(status.title)
                            .font(.caption.bold())
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
                Label("WinKeyer", systemImage: "cable.connector.horizontal").tag(0)
                Label("Serial DTR/RTS", systemImage: "cable.connector").tag(1)
                Label("CAT Morse", systemImage: "antenna.radiowaves.left.and.right").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                switch selectedTab {
                case 0: winKeyerPanel
                case 1: serialPinPanel
                case 2: catMorsePanel
                default: EmptyView()
                }
            }
        }
        .frame(width: 620, height: 580)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            wk.refreshPorts()
            sk.refreshPorts()
            // Open to tab matching current mode
            switch keyer.transmissionMode {
            case .winkeyer: selectedTab = 0
            case .serialDTR_RTS: selectedTab = 1
            case .catMorse: selectedTab = 2
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
                    Text("When CAT Morse mode is active, YAAM uses this priority order:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Text("①").foregroundColor(.accentColor).bold()
                        Text("Hamlib rigctld (\\ send_morse command)")
                    }.font(.callout)

                    HStack(spacing: 8) {
                        Text("②").foregroundColor(.accentColor).bold()
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
