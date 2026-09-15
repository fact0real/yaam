//
//  NetworkTransceiverEmulatorView.swift
//  YAAM
//
//  Created by factoreal on 9/13/26.
//

import Combine
import SwiftUI

// MARK: - Main Transceiver Emulator View
struct NetworkTransceiverEmulatorView: View {
    @ObservedObject var emulator: NetworkTransceiverEmulatorEngine
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    @State private var selectedTab: Int = 0
    @State private var newSignalCallsign: String = "EP2AES"
    @State private var newSignalGrid: String = "LL45"
    @State private var newSignalSNR: Double = -8.0
    @State private var newSignalAudioFreq: Double = 1450.0
    @State private var newSignalSlot: FT8SlotParity = .even
    @State private var currentTime: Date = Date()
    @State private var injectionFeedback: String? = nil

    private let secondTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // 1. Top Control & Power Bar
            topBar

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // 2. Hardware Front Panel LCD Display & VFO Dial
                    frontPanelHardwareDisplay

                    // 3. Middle Navigation Tab Selector
                    subTabSelector

                    // 4. Active Tab Content
                    Group {
                        switch selectedTab {
                        case 0:
                            networkAndClientsPanel
                        case 1:
                            channelSimulatorPanel
                        case 2:
                            syntheticSignalStudioPanel
                        case 3:
                            realtimeSpectrumPanel
                        case 4:
                            automatedBenchmarkingPanel
                        case 5:
                            diagnosticConsolePanel
                        default:
                            networkAndClientsPanel
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            emulator.isSpectrumVisualizerActive = (selectedTab == 3)
            if !emulator.isServerRunning {
                emulator.startServers()
            }
        }
        .onDisappear {
            emulator.isSpectrumVisualizerActive = false
        }
        .onChange(of: selectedTab) { _, newTab in
            emulator.isSpectrumVisualizerActive = (newTab == 3)
        }
        .onReceive(secondTimer) { now in
            currentTime = now
        }
    }

    // MARK: - Top Header Bar
    private var topBar: some View {
        HStack(spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Network Transceiver Emulator")
                        .font(.system(size: 14, weight: .bold))
                    Text("Icom CI-V over IP & Hamlib rigctld Physical Node Emulation")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            } icon: {
                Image(systemName: "server.rack")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(emulator.isServerRunning ? .green : .secondary)
            }

            Spacer()

            // Radio Model Selector
            Picker("Model", selection: $emulator.model) {
                ForEach(IcomNetworkModel.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
            .disabled(emulator.isServerRunning)

            // Local 1-Click Connect Button for YAAM
            if emulator.isServerRunning {
                Button {
                    connectYAAMClientToEmulator()
                } label: {
                    Label(
                        appState.icomNetworkRadio.state.isConnected ? "YAAM Linked ✅" : "Connect YAAM LAN",
                        systemImage: "link.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }

            // Power ON / OFF Button
            Button {
                if emulator.isServerRunning {
                    emulator.stopServers()
                } else {
                    emulator.startServers()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: emulator.isServerRunning ? "power.circle.fill" : "power.circle")
                        .font(.system(size: 14, weight: .bold))
                    Text(emulator.isServerRunning ? "Transceiver Online" : "Power Transceiver ON")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(emulator.isServerRunning ? .green : .blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func connectYAAMClientToEmulator() {
        let settings = IcomNetworkSettings(
            host: "127.0.0.1",
            controlPort: emulator.controlPort,
            username: emulator.username,
            clientName: "YAAM-Local",
            model: emulator.model
        )
        appState.icomNetworkRadio.connect(settings: settings, password: emulator.password)
    }

    // MARK: - Front Panel Hardware LCD Display
    private var frontPanelHardwareDisplay: some View {
        VStack(spacing: 12) {
            // Main OLED Display Chassis
            VStack(spacing: 10) {
                // Top Telemetry Header
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(emulator.isTransmitting ? Color.red : (emulator.isServerRunning ? Color.green : Color.gray))
                            .frame(width: 10, height: 10)
                            .shadow(color: emulator.isTransmitting ? Color.red.opacity(0.8) : Color.clear, radius: 4)

                        Text(emulator.isTransmitting ? "TX ACTIVE" : (emulator.isServerRunning ? "RX READY" : "STANDBY"))
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(emulator.isTransmitting ? .red : (emulator.isServerRunning ? .green : .secondary))
                    }

                    Spacer()

                    Text(emulator.model.rawValue)
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundColor(.cyan)

                    Spacer()

                    HStack(spacing: 8) {
                        Text(emulator.vfoSelected)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)

                        Text("FIL \(emulator.filterWidth == 3000 ? "1 (3.0k)" : "2 (2.4k)")")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)

                        Text("AGC \(emulator.agcSpeed)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Divider().background(Color.white.opacity(0.2))

                // Frequency Readout & Mode Badge
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AmateurBandPlan.band(forMHz: Double(emulator.frequencyHz) / 1_000_000) ?? "HF")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.3))
                            .cornerRadius(4)
                            .foregroundColor(.white)

                        Text("BAND")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    // Glowing Digital VFO Frequency Readout
                    Text(formattedFrequencyString(emulator.frequencyHz))
                        .font(.system(size: 42, weight: .black, design: .monospaced))
                        .foregroundColor(.green)
                        .shadow(color: Color.green.opacity(0.6), radius: 8)

                    Text("MHz")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.green.opacity(0.7))

                    Spacer()

                    // Mode Badge
                    VStack(spacing: 4) {
                        Text(emulator.mode)
                            .font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.yellow.opacity(0.25))
                            .cornerRadius(6)
                            .foregroundColor(.yellow)

                        Text("DATA-1")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }

                Divider().background(Color.white.opacity(0.2))

                // Analog S-Meter / Power Gauge Bar
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(emulator.isTransmitting ? "PO / SWR METER" : "SIGNAL S-METER")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)

                            Spacer()

                            if emulator.isTransmitting {
                                Text("\(String(format: "%.0f W", emulator.rfPowerWatts)) | SWR \(String(format: "%.2f", emulator.swr))")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.red)
                            } else {
                                Text("S\(Int(min(9, emulator.sMeterUnits))) \(emulator.sMeterUnits > 9 ? String(format: "+%.0f dB", (emulator.sMeterUnits - 9) * 6) : "")")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.green)
                            }
                        }

                        // Bulletproof Meter Gauge Bar (No GeometryReader, 100% NaN-immune)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.black.opacity(0.6))

                            let prog = (meterProgress.isFinite && !meterProgress.isNaN) ? max(0.001, min(1.0, meterProgress)) : 0.001
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [.green, .green, .yellow, .red],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .scaleEffect(x: CGFloat(prog), y: 1.0, anchor: .leading)
                        }
                        .frame(height: 10)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                        // Meter Tick Marks
                        HStack {
                            Text("S1").font(.system(size: 8))
                            Spacer()
                            Text("S5").font(.system(size: 8))
                            Spacer()
                            Text("S9").font(.system(size: 8))
                            Spacer()
                            Text("+20").font(.system(size: 8)).foregroundColor(.yellow)
                            Spacer()
                            Text("+60dB").font(.system(size: 8)).foregroundColor(.red)
                        }
                        .foregroundColor(.gray)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.05, green: 0.07, blue: 0.09))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
            )

            // Front Panel Quick Buttons & Tuning Controls
            HStack(spacing: 12) {
                // Band Selector Buttons
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(AmateurBandSettings.allBands.filter(\.isCore)) { band in
                            Button(band.displayName) {
                                emulator.selectBand(band)
                            }
                            .buttonStyle(.bordered)
                            .font(.system(size: 11, weight: .bold))
                            .tint(AmateurBandPlan.band(forMHz: Double(emulator.frequencyHz) / 1_000_000) == band.id ? .accentColor : .secondary)
                        }
                    }
                }

                Divider().frame(height: 24)

                // Quick Mode Selector
                Menu {
                    Button("USB-D (Digital)") { emulator.mode = "USB-D" }
                    Button("USB (Phone)") { emulator.mode = "USB" }
                    Button("LSB") { emulator.mode = "LSB" }
                    Button("CW") { emulator.mode = "CW" }
                    Button("FM") { emulator.mode = "FM" }
                    Button("AM") { emulator.mode = "AM" }
                } label: {
                    Label("Mode: \(emulator.mode)", systemImage: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                }
                .frame(width: 120)

                // Tuning Step Buttons
                HStack(spacing: 4) {
                    Button("-1k") { emulator.stepFrequency(hz: -1000) }
                    Button("+1k") { emulator.stepFrequency(hz: 1000) }
                    Button("-100") { emulator.stepFrequency(hz: -100) }
                    Button("+100") { emulator.stepFrequency(hz: 100) }
                }
                .buttonStyle(.bordered)
                .font(.system(size: 10, weight: .bold))

                // Big PTT Button
                Button {
                    emulator.togglePTT()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: emulator.isTransmitting ? "mic.fill" : "mic")
                        Text(emulator.isTransmitting ? "TX ON" : "PTT")
                            .font(.system(size: 12, weight: .black))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(emulator.isTransmitting ? .red : .orange)
            }
            .padding(.horizontal, 4)
        }
    }

    private var meterProgress: Double {
        let raw: Double
        if emulator.isTransmitting {
            raw = emulator.rfPowerWatts / 100.0
        } else {
            raw = emulator.sMeterUnits / 15.0
        }
        guard raw.isFinite && !raw.isNaN else { return 0.0 }
        return max(0.0, min(1.0, raw))
    }

    private func formattedFrequencyString(_ hz: UInt64) -> String {
        let mhz = Double(hz) / 1_000_000.0
        return String(format: "%07.4f", mhz)
    }

    // MARK: - Sub Tab Selector
    private var subTabSelector: some View {
        HStack(spacing: 6) {
            tabButton(tag: 0, title: "Network & Clients", icon: "network")
            tabButton(tag: 1, title: "Channel Simulator", icon: "waveform.path.badge.plus")
            tabButton(tag: 2, title: "Synthetic RF Studio", icon: "antenna.radiowaves.left.and.right")
            tabButton(tag: 3, title: "Live Spectrum", icon: "waveform.path.ecg")
            tabButton(tag: 4, title: "DSP Benchmark", icon: "chart.xyaxis.line")
            tabButton(tag: 5, title: "Diagnostics Log", icon: "terminal.fill")
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func tabButton(tag: Int, title: String, icon: String) -> some View {
        Button {
            selectedTab = tag
            emulator.isSpectrumVisualizerActive = (tag == 3)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11, weight: selectedTab == tag ? .bold : .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(selectedTab == tag ? Color.accentColor.opacity(0.15) : Color.clear)
            .foregroundColor(selectedTab == tag ? .accentColor : .secondary)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Panel 1: Network & Connected Clients
    private var networkAndClientsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Server Endpoints Summary Cards
            HStack(spacing: 12) {
                endpointCard(
                    title: "Icom LAN Control",
                    port: emulator.controlPort,
                    proto: "UDP",
                    status: emulator.isServerRunning ? "Listening" : "Stopped",
                    note: "Use in SDR-Control & wfview",
                    color: .green
                )
                endpointCard(
                    title: "Icom CI-V Data",
                    port: emulator.civPort,
                    proto: "UDP",
                    status: emulator.isServerRunning ? "Listening" : "Stopped",
                    note: "Auto-negotiated by Icom protocol",
                    color: .purple
                )
                endpointCard(
                    title: "Icom 48kHz Audio",
                    port: emulator.audioPort,
                    proto: "UDP",
                    status: emulator.isServerRunning ? "Streaming" : "Stopped",
                    note: "Auto-negotiated by Icom protocol",
                    color: .teal
                )
                endpointCard(
                    title: "Hamlib rigctld",
                    port: emulator.rigctldPort,
                    proto: "TCP",
                    status: "\(emulator.rigctldClientCount) Clients",
                    note: "Use in WSJT-X & JTDX",
                    color: .orange
                )
            }

            // Connected Clients Table
            VStack(alignment: .leading, spacing: 8) {
                Text("Connected Remote Software Clients")
                    .font(.system(size: 13, weight: .bold))

                if emulator.connectedClients.isEmpty && emulator.rigctldClientCount == 0 {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)
                            Text("No remote clients currently connected")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text("Point WSJT-X, wfview, or SDR-Control to 127.0.0.1")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .padding(24)
                        Spacer()
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                } else {
                    VStack(spacing: 6) {
                        ForEach(emulator.connectedClients) { client in
                            HStack {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                Text(client.clientName)
                                    .font(.system(size: 12, weight: .bold))
                                Spacer()
                                Text("\(client.remoteHost):\(client.controlPort)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("CI-V: \(client.civPort) | Audio: \(client.audioPort)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(client.packetsReceived) pkts")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }

                        if emulator.rigctldClientCount > 0 {
                            HStack {
                                Circle().fill(Color.orange).frame(width: 8, height: 8)
                                Text("Hamlib rigctld Session(s)")
                                    .font(.system(size: 12, weight: .bold))
                                Spacer()
                                Text("TCP Port \(emulator.rigctldPort)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(emulator.rigctldClientCount) Active Socket(s)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.orange)
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }
                    }
                }
            }

            // Quick Setup Guides for Third-Party Applications
            VStack(alignment: .leading, spacing: 10) {
                Text("Third-Party Application Setup Guides")
                    .font(.system(size: 13, weight: .bold))

                HStack(alignment: .top, spacing: 12) {
                    setupGuideCard(
                        title: "SDR-Control (macOS / iPad)",
                        icon: "antenna.radiowaves.left.and.right",
                        instructions: [
                            "1. Preferences > Radio > Model: \(emulator.model.rawValue)",
                            "2. Host: 127.0.0.1 (or Mac LAN IP)",
                            "3. Control Port: 50001 (UDP)",
                            "4. Username: yaam | Password: yaam",
                            "5. Connect -> CI-V, Spectrum & Audio!"
                        ]
                    )

                    setupGuideCard(
                        title: "wfview (macOS / Win / Linux)",
                        icon: "dot.radiowaves.left.and.right",
                        instructions: [
                            "1. Settings > Radio Interface",
                            "2. Radio Type: 'Icom Network Radio'",
                            "3. IP: 127.0.0.1 | Port: 50001",
                            "4. Username: yaam | Password: yaam",
                            "5. Click 'Connect' to stream CI-V & Audio"
                        ]
                    )

                    setupGuideCard(
                        title: "WSJT-X / JTDX Setup",
                        icon: "teletype",
                        instructions: [
                            "1. Preferences > Radio",
                            "2. Rig: 'Hamlib NET rigctl'",
                            "3. Network Server: 127.0.0.1:4532",
                            "4. PTT Method: 'CAT'",
                            "5. Click 'Test CAT' -> Rigctl Connected"
                        ]
                    )
                }

                // Architecture explanation banner
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Port & Network Architecture Explained")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.primary)
                        Text("• Host IP (127.0.0.1) addresses your computer. Different ports host different communication protocols.\n• SDR-Control & wfview speak the Icom Hardware LAN protocol: you only connect to UDP Port 50001. The CI-V (50002) and raw Audio (50003) channels are auto-negotiated during login!\n• WSJT-X / JTDX speak the Hamlib rigctld protocol over TCP Port 4532 (plain ASCII text commands). Binary UDP and ASCII TCP streams cannot share the same port.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineSpacing(2)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.blue.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.2), lineWidth: 1))
                .cornerRadius(8)
            }
        }
    }

    private func endpointCard(title: String, port: Int, proto: String, status: String, note: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(proto)
                    .font(.system(size: 9, weight: .black))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.2))
                    .cornerRadius(3)
                    .foregroundColor(color)
                Spacer()
                Text(status)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(emulator.isServerRunning ? .green : .secondary)
            }
            Text(title)
                .font(.system(size: 12, weight: .bold))
            Text("Port \(port)")
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundColor(.primary)
            Text(note)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func setupGuideCard(title: String, icon: String, instructions: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.accentColor)
            ForEach(instructions, id: \.self) { line in
                Text(line)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Panel 2: Channel Simulator & Physics Engine
    private var channelSimulatorPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("RF Channel Impairment & Environmental Simulation")
                .font(.system(size: 13, weight: .bold))

            // SNR Slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Signal-to-Noise Ratio (SNR):")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(String(format: "%.1f dB", emulator.rfEngine.targetSNR))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(snrColor(emulator.rfEngine.targetSNR))
                }

                Slider(value: Binding(
                    get: { emulator.rfEngine.targetSNR },
                    set: { emulator.rfEngine.targetSNR = $0 }
                ), in: -30.0...30.0, step: 0.5)

                HStack {
                    Text("-30 dB (Deep Noise Limit)").font(.system(size: 9)).foregroundColor(.secondary)
                    Spacer()
                    Text("0 dB").font(.system(size: 9)).foregroundColor(.secondary)
                    Spacer()
                    Text("+30 dB (Pristine Line)").font(.system(size: 9)).foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Ionospheric Fading & Doppler Controls
            HStack(spacing: 12) {
                // Fading Profile Picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ionospheric Multipath Fading")
                        .font(.system(size: 12, weight: .semibold))

                    Picker("Profile", selection: Binding(
                        get: { emulator.rfEngine.channelFading },
                        set: { emulator.rfEngine.channelFading = $0 }
                    )) {
                        ForEach(ChannelFadingProfile.allCases) { profile in
                            Text(profile.rawValue).tag(profile)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Doppler Shift & Drift
                VStack(alignment: .leading, spacing: 8) {
                    Text("Doppler Frequency Shift & Drift")
                        .font(.system(size: 12, weight: .semibold))

                    HStack {
                        Text("Shift:")
                            .font(.system(size: 11))
                        Slider(value: Binding(
                            get: { emulator.rfEngine.dopplerShiftHz },
                            set: { emulator.rfEngine.dopplerShiftHz = $0 }
                        ), in: -500.0...500.0, step: 5.0)
                        Text(String(format: "%+.0f Hz", emulator.rfEngine.dopplerShiftHz))
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 60)
                    }

                    HStack {
                        Text("Drift:")
                            .font(.system(size: 11))
                        Slider(value: Binding(
                            get: { emulator.rfEngine.dopplerDriftHzPerMin },
                            set: { emulator.rfEngine.dopplerDriftHzPerMin = $0 }
                        ), in: -100.0...100.0, step: 1.0)
                        Text(String(format: "%+.0f Hz/m", emulator.rfEngine.dopplerDriftHzPerMin))
                            .font(.system(size: 10, design: .monospaced))
                            .frame(width: 60)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            // QRN Atmospheric Static & Network Loss Injection
            HStack(spacing: 12) {
                // Atmospheric Static
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Atmospheric Static / QRN Impulses:")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text(String(format: "%.0f%%", emulator.rfEngine.qrnImpulseRate * 100))
                            .font(.system(size: 10, weight: .bold))
                    }
                    Slider(value: Binding(
                        get: { emulator.rfEngine.qrnImpulseRate },
                        set: { emulator.rfEngine.qrnImpulseRate = $0 }
                    ), in: 0.0...1.0)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Network Packet Loss
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Simulated UDP Packet Loss:")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text(String(format: "%.1f%%", emulator.rfEngine.simulatedPacketLossPercent))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(emulator.rfEngine.simulatedPacketLossPercent > 0 ? .red : .primary)
                    }
                    Slider(value: Binding(
                        get: { emulator.rfEngine.simulatedPacketLossPercent },
                        set: { emulator.rfEngine.simulatedPacketLossPercent = $0 }
                    ), in: 0.0...25.0)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    private func snrColor(_ snr: Double) -> Color {
        if snr >= 0 { return .green }
        if snr >= -12 { return .yellow }
        if snr >= -20 { return .orange }
        return .red
    }

    // MARK: - Panel 3: Synthetic Signal Studio
    private var syntheticSignalStudioPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Synthetic Digital Signals & Station Pileup Generator")
                        .font(.system(size: 13, weight: .bold))
                    Text("Injected waveforms are shaped with continuous-phase GFSK and streamed over UDP Audio to SDR-Control & WSJT-X.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    generatePresetPileup()
                    showFeedback("Loaded 5-station FT8 DX pileup")
                } label: {
                    Label("5-Station Pileup", systemImage: "person.3.fill")
                }
                .buttonStyle(.bordered)
                .font(.system(size: 11))

                Button("Reset Defaults") {
                    emulator.resetDefaultSignals()
                    showFeedback("Reset signals to default test set")
                }
                .buttonStyle(.bordered)
                .font(.system(size: 11))

                Button("Clear All") {
                    emulator.clearSyntheticSignals()
                    showFeedback("Cleared all synthetic signals")
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
                .font(.system(size: 11))
            }

            // Injected Feedback Toast
            if let feedback = injectionFeedback {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(feedback)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Button {
                        injectionFeedback = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.3), lineWidth: 1))
                .cornerRadius(6)
            }

            // Quick Signal Add Bar
            VStack(alignment: .leading, spacing: 6) {
                Text("Add / Inject Synthetic FT8 Station")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("Callsign", text: $newSignalCallsign)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)

                    TextField("Grid", text: $newSignalGrid)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)

                    Picker("Timing Slot", selection: $newSignalSlot) {
                        Text("Loop (Instant)").tag(FT8SlotParity.continuous)
                        Text("Even (:00 / :30)").tag(FT8SlotParity.even)
                        Text("Odd (:15 / :45)").tag(FT8SlotParity.odd)
                    }
                    .frame(width: 140)

                    HStack(spacing: 4) {
                        Text("Freq:")
                            .font(.system(size: 10))
                        TextField("Hz", value: $newSignalAudioFreq, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                    }

                    HStack(spacing: 4) {
                        Text("SNR:")
                            .font(.system(size: 10))
                        TextField("dB", value: $newSignalSNR, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                    }

                    Button {
                        injectCustomFT8()
                    } label: {
                        Label("Inject FT8 Signal", systemImage: "bolt.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .font(.system(size: 11, weight: .bold))
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            // Preset Quick Injectors
            HStack(spacing: 10) {
                Button {
                    let sig = SyntheticSignalProfile(
                        message: "CQ EP2AES LL45",
                        mode: "FT8",
                        baseAudioFrequencyHz: 1450,
                        snrDB: 0.0,
                        slotParity: .continuous
                    )
                    emulator.addSyntheticSignal(sig)
                    showFeedback("Injected instant loop: CQ EP2AES LL45 (1450 Hz)")
                } label: {
                    Label("Loop: CQ EP2AES LL45", systemImage: "repeat")
                }
                .buttonStyle(.bordered)
                .font(.system(size: 11))

                Button {
                    let sig = SyntheticSignalProfile(
                        message: "VVV DE EP2AES/B K",
                        mode: "CW",
                        baseAudioFrequencyHz: 750,
                        snrDB: 0.0,
                        slotParity: .continuous
                    )
                    emulator.addSyntheticSignal(sig)
                    showFeedback("Injected CW Morse beacon at 750 Hz")
                } label: {
                    Label("CW Beacon (750 Hz)", systemImage: "tuningfork")
                }
                .buttonStyle(.bordered)
                .font(.system(size: 11))

                Button {
                    let sig = SyntheticSignalProfile(
                        message: "CARRIER",
                        mode: "TONE",
                        baseAudioFrequencyHz: 1000,
                        snrDB: 0.0,
                        slotParity: .continuous
                    )
                    emulator.addSyntheticSignal(sig)
                    showFeedback("Injected 1000 Hz Linearity Carrier")
                } label: {
                    Label("1000 Hz Carrier", systemImage: "waveform.path")
                }
                .buttonStyle(.bordered)
                .font(.system(size: 11))

                Spacer()
            }

            // Interactive Active Signals List
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Active Synthetic Signals (\(emulator.activeSignals.count))")
                        .font(.system(size: 12, weight: .bold))

                    Spacer()

                    let onAirCount = emulator.activeSignals.filter { $0.isTransmitting(at: currentTime) }.count
                    if onAirCount > 0 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("\(onAirCount) ON AIR")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.12))
                        .cornerRadius(4)
                    }
                }

                if emulator.activeSignals.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.slash")
                            .font(.system(size: 24))
                            .foregroundColor(.secondary)
                        Text("No synthetic signals currently active.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Button("Load Default Signals") {
                            emulator.resetDefaultSignals()
                        }
                        .buttonStyle(.bordered)
                        .font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                } else {
                    VStack(spacing: 4) {
                        ForEach(emulator.activeSignals) { sig in
                            syntheticSignalRow(sig)
                        }
                    }
                }
            }
        }
    }

    private func syntheticSignalRow(_ sig: SyntheticSignalProfile) -> some View {
        let isTx = sig.isTransmitting(at: currentTime)

        return HStack(spacing: 12) {
            // Live Status Badge
            Group {
                if !sig.isEnabled {
                    Text("OFFLINE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                } else if isTx {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("ON AIR")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(4)
                } else {
                    Text("STANDBY")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(4)
                }
            }
            .frame(width: 70, alignment: .leading)

            // Mode Badge
            Text(sig.mode)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.purple.opacity(0.15))
                .foregroundColor(.purple)
                .cornerRadius(4)

            // Message
            Text(sig.message)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(width: 170, alignment: .leading)

            // Frequency
            Text("\(Int(sig.baseAudioFrequencyHz)) Hz")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 75, alignment: .trailing)

            // SNR
            Text("\(sig.snrDB >= 0 ? "+" : "")\(Int(sig.snrDB)) dB")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(snrColor(sig.snrDB))
                .frame(width: 55, alignment: .trailing)

            // Slot Parity
            Text(slotParityShort(sig.slotParity))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            Spacer()

            // Enable / Disable Toggle
            Button {
                emulator.toggleSyntheticSignal(id: sig.id)
            } label: {
                Image(systemName: sig.isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(sig.isEnabled ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(sig.isEnabled ? "Mute / Disable this signal" : "Enable this signal")

            // Delete Button
            Button {
                emulator.removeSyntheticSignal(id: sig.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("Delete signal")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }

    private func slotParityShort(_ parity: FT8SlotParity) -> String {
        switch parity {
        case .even: return "Even (:00)"
        case .odd: return "Odd (:15)"
        case .continuous: return "Loop"
        }
    }

    private func showFeedback(_ text: String) {
        injectionFeedback = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            if self.injectionFeedback == text {
                self.injectionFeedback = nil
            }
        }
    }

    private func injectCustomFT8() {
        let call = newSignalCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().replacingOccurrences(of: " ", with: "")
        let grid = newSignalGrid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().prefix(4)
        let cleanCall = call.isEmpty ? "EP2AES" : call
        let cleanGrid = grid.isEmpty ? "LL45" : String(grid)
        let msg = "CQ \(cleanCall) \(cleanGrid)"

        let sig = SyntheticSignalProfile(
            message: msg,
            mode: "FT8",
            baseAudioFrequencyHz: newSignalAudioFreq,
            snrDB: newSignalSNR,
            slotParity: newSignalSlot
        )
        emulator.addSyntheticSignal(sig)
        showFeedback("Injected FT8 Signal: \(msg) (\(Int(newSignalAudioFreq)) Hz, \(Int(newSignalSNR)) dB)")
    }

    private func generatePresetPileup() {
        let pileup: [SyntheticSignalProfile] = [
            SyntheticSignalProfile(message: "CQ EP2AES LL45", mode: "FT8", baseAudioFrequencyHz: 1250, snrDB: 4.0, slotParity: .even),
            SyntheticSignalProfile(message: "W1AW EP2AES -04", mode: "FT8", baseAudioFrequencyHz: 1540, snrDB: -6.0, slotParity: .odd),
            SyntheticSignalProfile(message: "JH1GTV EP2AES -12", mode: "FT8", baseAudioFrequencyHz: 890, snrDB: -14.0, slotParity: .odd),
            SyntheticSignalProfile(message: "CQ DX EA8AK IL18", mode: "FT8", baseAudioFrequencyHz: 1980, snrDB: -2.0, slotParity: .even),
            SyntheticSignalProfile(message: "VK3XYZ EP2AES -18", mode: "FT8", baseAudioFrequencyHz: 2280, snrDB: -19.0, slotParity: .odd)
        ]
        emulator.setSyntheticSignals(pileup)
    }

    // MARK: - Panel 4: Real-Time Spectrum Visualizer
    private var realtimeSpectrumPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live Baseband Audio Spectrum (0 – 3,000 Hz)")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text("FFT Size: 512 | Sample Rate: 48 kHz")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Real-Time Canvas Spectrum Graph
            Canvas { context, size in
                guard size.width > 10, size.height > 10 else { return }
                guard emulator.isSpectrumVisualizerActive else { return }
                let mags = emulator.liveSpectrumMagnitudes
                guard mags.count >= 2 else { return }

                var path = Path()
                let step = size.width / CGFloat(mags.count - 1)
                guard step.isFinite, step > 0 else { return }

                var firstPoint = true
                for (index, mag) in mags.enumerated() {
                    guard mag.isFinite && !mag.isNaN else { continue }
                    let normalized = max(0.0, min(1.0, CGFloat(mag + 100.0) / 100.0))
                    let y = max(0.0, min(size.height, size.height - (normalized * size.height)))
                    let x = max(0.0, min(size.width, CGFloat(index) * step))
                    guard x.isFinite, y.isFinite else { continue }

                    if firstPoint {
                        path.move(to: CGPoint(x: x, y: y))
                        firstPoint = false
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                guard !firstPoint else { return }

                // Stroke line
                context.stroke(path, with: .color(.green), lineWidth: 1.5)

                // Fill gradient under curve
                var fillPath = path
                fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
                fillPath.addLine(to: CGPoint(x: 0, y: size.height))
                fillPath.closeSubpath()

                context.fill(
                    fillPath,
                    with: .linearGradient(
                        Gradient(colors: [Color.green.opacity(0.35), Color.green.opacity(0.02)]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }
            .frame(height: 180)
            .background(Color.black)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )

            // Frequency Labels under spectrum
            HStack {
                Text("0 Hz").font(.system(size: 9, design: .monospaced))
                Spacer()
                Text("1,000 Hz").font(.system(size: 9, design: .monospaced))
                Spacer()
                Text("2,000 Hz").font(.system(size: 9, design: .monospaced))
                Spacer()
                Text("3,000 Hz").font(.system(size: 9, design: .monospaced))
            }
            .foregroundColor(.secondary)
        }
    }

    // MARK: - Panel 5: Automated Benchmarking Suite
    private var automatedBenchmarkingPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automated DSP Benchmark & SNR Sensitivity Sweep")
                        .font(.system(size: 13, weight: .bold))
                    Text("Iteratively steps SNR from +6 dB down to -24 dB to measure receiver decoding threshold")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    if emulator.tester.isTesting {
                        emulator.tester.cancel()
                    } else {
                        emulator.tester.runSNRSensitivitySweep(
                            radioModel: emulator.model.rawValue,
                            rfEngine: emulator.rfEngine
                        )
                    }
                } label: {
                    Label(
                        emulator.tester.isTesting ? "Stop Sweep" : "Run Sensitivity Sweep",
                        systemImage: emulator.tester.isTesting ? "stop.fill" : "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(emulator.tester.isTesting ? .red : .accentColor)
            }

            // Progress Bar & Status
            if emulator.tester.isTesting || emulator.tester.latestReport != nil {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: emulator.tester.progressPercent)
                    Text(emulator.tester.currentStatusMessage)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            // Benchmark Results Table
            if !emulator.tester.stepResults.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Step Results:")
                            .font(.system(size: 12, weight: .bold))

                        Spacer()

                        if let report = emulator.tester.latestReport {
                            Text("Floor: \(report.sensitivityFloorSNR != nil ? String(format: "%.1f dB", report.sensitivityFloorSNR!) : "N/A")")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.green)
                            Text("Success: \(String(format: "%.1f%%", report.overallSuccessRatePercent))")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.cyan)

                            Button("Copy Markdown Report") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(report.markdownReport, forType: .string)
                            }
                            .buttonStyle(.bordered)
                            .font(.system(size: 10))
                        }
                    }

                    ForEach(emulator.tester.stepResults) { step in
                        HStack {
                            Text("Step \(step.stepIndex)")
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 55, alignment: .leading)

                            Text(String(format: "%+.1f dB", step.snrDB))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .frame(width: 70, alignment: .leading)
                                .foregroundColor(snrColor(step.snrDB))

                            Text(step.wasDecoded ? "✅ Decoded" : "❌ No Decode")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 95, alignment: .leading)
                                .foregroundColor(step.wasDecoded ? .green : .red)

                            if let msg = step.decodedMessage {
                                Text("`\(msg)`")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Text(String(format: "%.1f ms", step.executionDurationMs))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                    }
                }
            }
        }
    }

    // MARK: - Panel 6: Diagnostic Protocol Console
    private var diagnosticConsolePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Protocol Telemetry & Packet Activity Log")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button("Clear Console") {
                    emulator.clearLogs()
                }
                .buttonStyle(.bordered)
                .font(.system(size: 10))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(emulator.activityLogs.suffix(100)) { log in
                            HStack(alignment: .top, spacing: 6) {
                                Text(log.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)

                                Text("[\(log.category.rawValue)]")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(log.category.color)

                                Text(log.message)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.primary)
                            }
                            .id(log.id)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 260)
                .background(Color.black.opacity(0.85))
                .cornerRadius(8)
                .onChange(of: emulator.activityLogs.count) { _, _ in
                    if let lastID = emulator.activityLogs.last?.id {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
    }
}
