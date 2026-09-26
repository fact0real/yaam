//
//  Lab599TX500SetupView.swift
//  YAAM
//
//  Comprehensive Lab599 Discovery TX-500 USB-C Station Setup & Diagnostics Workbench
//  Supports dual-channel configuration (CAT & Audio), real-time telemetry testing,
//  and hardware checklist guidance directly derived from engineering best practices.
//

import AppKit
import SwiftUI

public struct Lab599TX500SetupView: View {
    @ObservedObject var tx500 = Lab599TX500Driver.shared
    @ObservedObject var rigEngine = RigControlEngine.shared
    @ObservedObject var cwKeyer = CWKeyerService.shared

    @State private var testFrequencyStr: String = "14.074000"
    @State private var testCWMessage: String = "TEST DE EP2AES"
    @State private var isTestingPTT: Bool = false
    @State private var isTestingCW: Bool = false

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                headerBanner

                // Section 1: Channel Architecture Overview
                dualChannelStatusGrid

                // Section 2: Channel 1 — Serial CAT Control Setup
                catControlCard

                // Section 3: Channel 2 — Analog Audio (REM/DATA) Setup
                audioInterfaceCard

                // Section 4: Interactive Hardware Verification & Diagnostics
                hardwareDiagnosticsCard

                // Section 5: Firmware Bug #1 Mitigation & Pre-Flight Checklist
                checklistAndBugReferenceCard
            }
            .padding(24)
        }
        .frame(minWidth: 700, minHeight: 650)
        .onAppear {
            tx500.refreshPorts()
            tx500.scanAudioDevices()
        }
    }

    // MARK: - Header Banner
    private var headerBanner: some View {
        HStack(spacing: 14) {
            Lab599LogoView(height: 28)
                .frame(width: 76)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Lab599 Discovery TX-500")
                        .font(.title2.bold())
                    Text("USB-C Transceiver Architecture")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundColor(.accentColor)
                }
                Text("Native hardware CAT control, FT8/FT4 digital modem routing, and Kenwood KY Morse keying on macOS")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Live Connection Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(tx500.isConnected ? Color.green : (tx500.isConnecting ? Color.yellow : Color.secondary.opacity(0.4)))
                    .frame(width: 8, height: 8)
                Text(tx500.isConnected ? "CAT CONNECTED" : (tx500.isConnecting ? "CONNECTING..." : "OFFLINE"))
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(tx500.isConnected ? .green : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tx500.isConnected ? Color.green.opacity(0.12) : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(tx500.isConnected ? Color.green.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1))
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Dual Channel Status Grid
    private var dualChannelStatusGrid: some View {
        HStack(spacing: 14) {
            // CAT Channel Summary
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "cable.connector")
                        .foregroundColor(.accentColor)
                    Text("Channel 1: Serial CAT (GX12 4-Pin)")
                        .font(.caption.bold())
                    Spacer()
                    Text("AD-514 / AD-502")
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Port").font(.caption2).foregroundColor(.secondary)
                        Text(tx500.selectedPort.components(separatedBy: "/").last ?? "None")
                            .font(.system(.caption, design: .monospaced).bold())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Parameters").font(.caption2).foregroundColor(.secondary)
                        Text("\(tx500.baudRate) 8N\(tx500.stopBits)")
                            .font(.system(.caption, design: .monospaced).bold())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Protocol").font(.caption2).foregroundColor(.secondary)
                        Text("Menu 34: TS2000")
                            .font(.system(.caption, design: .monospaced).bold())
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
            .cornerRadius(8)

            // Audio Channel Summary
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "waveform")
                        .foregroundColor(.green)
                    Text("Channel 2: Analog Audio (REM/DATA 7-Pin)")
                        .font(.caption.bold())
                    Spacer()
                    Text("AD-508 / AD-509")
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Codec Status").font(.caption2).foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            Circle().fill(tx500.isAudioDeviceDetected ? Color.green : Color.orange).frame(width: 6, height: 6)
                            Text(tx500.isAudioDeviceDetected ? "USB Audio Detected" : "Default Audio")
                                .font(.caption2.bold())
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sample Rate").font(.caption2).foregroundColor(.secondary)
                        Text("48000 Hz 16-bit")
                            .font(.system(.caption, design: .monospaced).bold())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio Gain").font(.caption2).foregroundColor(.secondary)
                        Text("Menu 09: 30")
                            .font(.system(.caption, design: .monospaced).bold())
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
            .cornerRadius(8)
        }
    }

    // MARK: - CAT Control Card
    private var catControlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Channel 1: USB Serial CAT Setup (AD-514 / AD-502)", icon: "cable.connector")

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Serial Port").font(.caption.bold())
                    Picker("Port", selection: $tx500.selectedPort) {
                        if tx500.availablePorts.isEmpty {
                            Text("No serial ports found").tag("")
                        }
                        ForEach(tx500.availablePorts, id: \.self) { p in
                            Text(p).tag(p)
                        }
                    }
                    .frame(maxWidth: 280)
                }

                Button { tx500.refreshPorts() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Refresh available serial ports")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Baud Rate").font(.caption.bold())
                    Picker("Baud", selection: $tx500.baudRate) {
                        Text("9600 (Menu 35 Default)").tag(9600)
                        Text("19200").tag(19200)
                        Text("38400").tag(38400)
                    }
                    .frame(width: 170)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Stop Bits").font(.caption.bold())
                    Picker("Stop", selection: $tx500.stopBits) {
                        Text("2 Stop Bits (8N2 - Verified)").tag(2)
                        Text("1 Stop Bit (8N1)").tag(1)
                    }
                    .frame(width: 160)
                }
            }

            HStack(spacing: 16) {
                Toggle("Auto-Connect on YAAM Launch", isOn: $tx500.autoConnect)
                    .font(.caption)

                Toggle("Preserve DIG Mode (Menu 34=TS2000)", isOn: $tx500.preserveDIGMode)
                    .font(.caption.bold())
                    .help("MANDATORY: Prevents Firmware Bug #1 by suppressing automated CAT mode strings that knock the TX-500 out of DIG mode into USB voice mode.")

                Spacer()

                if tx500.isConnected {
                    Button("Disconnect TX-500", role: .destructive) { tx500.disconnect() }
                        .buttonStyle(.bordered)
                } else {
                    Button {
                        tx500.connect()
                    } label: {
                        Label("Connect TX-500", systemImage: "bolt.horizontal.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(tx500.selectedPort.isEmpty)
                }
            }

            if !tx500.lastMessage.isEmpty {
                Text(tx500.lastMessage)
                    .font(.caption.monospaced())
                    .foregroundColor(tx500.isConnected ? .green : .secondary)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Audio Interface Card
    private var audioInterfaceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Channel 2: Analog Baseband Audio (AD-508 / AD-509)", icon: "waveform")

            Text("The TX-500 contains no internal USB soundcard. Transmit and receive audio travel through the locking GX12 REM/DATA port. On modern Apple Silicon Macs, the AD-508 USB-C cable or AD-509 provides full-duplex 48 kHz 16-bit digital audio.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detected Audio Hardware").font(.caption.bold())
                    HStack(spacing: 6) {
                        Circle().fill(tx500.isAudioDeviceDetected ? Color.green : Color.orange).frame(width: 8, height: 8)
                        Text(tx500.detectedAudioDeviceName ?? "Standard CoreAudio Devices")
                            .font(.callout.weight(.medium))
                    }
                }

                Spacer()

                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Audio MIDI Setup.app"))
                } label: {
                    Label("Open Audio MIDI Setup", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .help("Configure 48000.0 Hz 16-bit format in macOS Audio MIDI Setup")
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Hardware Diagnostics Card
    private var hardwareDiagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("Live Telemetry & Hardware Diagnostics", icon: "gauge.with.needle")

            // Real-Time Meter Strip
            HStack(spacing: 16) {
                // Dial Frequency
                metricBox(title: "VFO Frequency", value: tx500.formattedFrequency, sub: tx500.currentBand, color: .cyan)

                // Operating Mode
                metricBox(title: "Operating Mode", value: tx500.mode, sub: tx500.preserveDIGMode ? "Locked to DIG" : "Auto", color: .purple)

                // S-Meter
                metricBox(title: "S-Meter", value: tx500.sMeterDescription, sub: "Scale 0-15", color: tx500.sMeterValue > 9 ? .red : .green)

                // RF Power
                metricBox(title: "Output Power", value: "\(tx500.powerWatts) W", sub: "QRP HF/6m", color: .orange)
            }

            Divider()

            // Interactive Verification Action Strip
            Text("Interactive Hardware Self-Tests:")
                .font(.caption.bold())
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                // 1. Query Status
                Button {
                    tx500.queryRadioStatus()
                } label: {
                    Label("Query Status (FA/MD/SM/PC)", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .disabled(!tx500.isConnected)

                // 2. Test 1-Second PTT
                Button {
                    testPTTPulse()
                } label: {
                    Label(isTestingPTT ? "Transmitting..." : "Test 1s PTT Pulse", systemImage: "bolt.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!tx500.isConnected || isTestingPTT)

                // 3. Test CW Morse
                Button {
                    testCWSend()
                } label: {
                    Label(isTestingCW ? "Sending CW..." : "Test Morse (KY)", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(.bordered)
                .disabled(!tx500.isConnected || isTestingCW)

                Spacer()

                // Set as Active Universal Rig Driver
                Button {
                    rigEngine.driverType = .tx500
                    rigEngine.connect()
                } label: {
                    Label("Set TX-500 as Global CAT Driver", systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Pre-Flight Checklist & Firmware Bug Reference
    private var checklistAndBugReferenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Pre-Session Operational Checklist & Bug Mitigation", icon: "checklist")

            VStack(alignment: .leading, spacing: 8) {
                checklistItem(title: "Radio Menu 34 (CAT Protocol)", detail: "Must be set to TS2000 (Kenwood TS-2000 emulation command set).")
                checklistItem(title: "Radio Menu 35 (CAT Rate)", detail: "Set to 9600 (factory default). Matches YAAM baud rate setting.")
                checklistItem(title: "Radio Menu 09 (Gain>DIG)", detail: "Baseline at 30 (range 20–40). Adjust until MIC meter reaches 3/4 scale on TX.")
                checklistItem(title: "Front Panel Mode: DIG", detail: "Press front-panel MODE until screen indicates DIG. This isolates microphone and connects REM/DATA.")
                checklistItem(title: "macOS Audio MIDI Setup", detail: "Set USB Audio Device to 48000.0 Hz, 2ch 16-bit Integer with ~70% output volume.")
                checklistItem(title: "Firmware Bug #1 Prevention", detail: "YAAM omits CAT mode switch commands on transmit, preventing the TX-500 from dropping from DIG to USB voice mode.")
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
            .cornerRadius(8)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Helper Views & Actions

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .font(.headline)
            Text(title)
                .font(.headline.bold())
        }
    }

    private func metricBox(title: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2.bold()).foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                .foregroundColor(color)
            Text(sub).font(.caption2).foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
    }

    private func checklistItem(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.caption)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.bold())
                Text(detail).font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private func testPTTPulse() {
        guard tx500.isConnected else { return }
        isTestingPTT = true
        tx500.setPTT(true, maximumDuration: 1.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.tx500.setPTT(false)
            self.isTestingPTT = false
        }
    }

    private func testCWSend() {
        guard tx500.isConnected else { return }
        isTestingCW = true
        tx500.sendMorse(testCWMessage, wpm: cwKeyer.wpm)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            self.isTestingCW = false
        }
    }
}
