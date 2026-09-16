//
//  Xiegu6100SetupView.swift
//  YAAM
//
//  Comprehensive Xiegu X6100 USB-C Station Setup & Diagnostics Workbench
//  Supports dual-channel configuration (CAT & Audio), real-time telemetry testing,
//  and hardware checklist guidance directly derived from engineering best practices.
//

import AppKit
import SwiftUI

public struct Xiegu6100SetupView: View {
    @ObservedObject var xiegu = Xiegu6100Driver.shared
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

                // Section 3: Channel 2 — USB-C Audio CODEC Setup
                audioInterfaceCard

                // Section 4: Interactive Hardware Verification & Diagnostics
                hardwareDiagnosticsCard

                // Section 5: Transceiver Checklist & Operating Guidance
                checklistAndReferenceCard
            }
            .padding(24)
        }
        .frame(minWidth: 700, minHeight: 650)
        .onAppear {
            xiegu.refreshPorts()
            xiegu.scanAudioDevices()
        }
    }

    // MARK: - Header Banner
    private var headerBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "radio.fill")
                .font(.system(size: 32))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Xiegu X6100")
                        .font(.title2.bold())
                    Text("USB-C Transceiver Architecture")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundColor(.accentColor)
                }
                Text("Native hardware CAT control, FT8/FT4 digital modem routing, and CI-V / Pin Morse keying on macOS")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Live Connection Pill
            HStack(spacing: 6) {
                Circle()
                    .fill(xiegu.isConnected ? Color.green : (xiegu.isConnecting ? Color.yellow : Color.secondary.opacity(0.4)))
                    .frame(width: 8, height: 8)
                Text(xiegu.isConnected ? "CAT CONNECTED" : (xiegu.isConnecting ? "CONNECTING..." : "OFFLINE"))
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(xiegu.isConnected ? .green : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(xiegu.isConnected ? Color.green.opacity(0.12) : Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(xiegu.isConnected ? Color.green.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1))
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
                    Text("Channel 1: Serial CAT (USB-C DEV)")
                        .font(.caption.bold())
                    Spacer()
                    Text("CI-V Address: 0x\(xiegu.civAddressHex)")
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Port").font(.caption2).foregroundColor(.secondary)
                        Text(xiegu.selectedPort.components(separatedBy: "/").last ?? "None")
                            .font(.system(.caption, design: .monospaced).bold())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Parameters").font(.caption2).foregroundColor(.secondary)
                        Text("\(xiegu.baudRate) 8N1")
                            .font(.system(.caption, design: .monospaced).bold())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Emulation").font(.caption2).foregroundColor(.secondary)
                        Text("Icom IC-705")
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
                    Text("Channel 2: USB Audio CODEC")
                        .font(.caption.bold())
                    Spacer()
                    Text("48.0 kHz 16-Bit")
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Device").font(.caption2).foregroundColor(.secondary)
                        Text(xiegu.detectedAudioDeviceName ?? (xiegu.isAudioDeviceDetected ? "USB Audio" : "Not Found"))
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundColor(xiegu.isAudioDeviceDetected ? .green : .secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Digital Mode").font(.caption2).foregroundColor(.secondary)
                        Text("USB-D / DATA")
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
            HStack {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(.accentColor)
                Text("Channel 1: USB-C Serial CAT & CI-V Protocol")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    // Port selection
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Serial Port (DEV Port)")
                            .font(.caption.bold())
                        Picker("", selection: $xiegu.selectedPort) {
                            if xiegu.availablePorts.isEmpty {
                                Text("No serial ports detected").tag("")
                            }
                            ForEach(xiegu.availablePorts, id: \.self) { p in
                                Text(p.components(separatedBy: "/").last ?? p).tag(p)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 220)
                    }

                    Button {
                        xiegu.refreshPorts()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .help("Rescan serial ports")

                    // Baud Rate
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Baud Rate")
                            .font(.caption.bold())
                        Picker("", selection: $xiegu.baudRate) {
                            Text("9600").tag(9600)
                            Text("19200 (Default)").tag(19200)
                            Text("38400").tag(38400)
                            Text("57600").tag(57600)
                            Text("115200").tag(115200)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }

                    // CI-V Address
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CI-V Address (Hex)")
                            .font(.caption.bold())
                        HStack(spacing: 4) {
                            Text("0x").font(.caption.monospaced()).foregroundColor(.secondary)
                            TextField("A4", text: $xiegu.civAddressHex)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 50)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }

                    Spacer()

                    // Connect / Disconnect button
                    Button {
                        xiegu.toggleConnection()
                    } label: {
                        Label(xiegu.isConnected ? "Disconnect" : "Connect", systemImage: xiegu.isConnected ? "xmark.circle" : "cable.connector")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(xiegu.isConnected ? .secondary : .blue)
                    .disabled(xiegu.selectedPort.isEmpty)
                }

                Divider()

                // Hardware Pin Options
                HStack(spacing: 24) {
                    Toggle("Hardware RTS PTT (DEV port RTS line asserts TX)", isOn: $xiegu.enableHardwareRTSPTT)
                        .font(.caption)

                    Toggle("Hardware DTR CW Keying (Direct pin keying)", isOn: $xiegu.enableHardwareDTRCW)
                        .font(.caption)

                    Toggle("Auto-Connect on Startup", isOn: $xiegu.autoConnect)
                        .font(.caption)
                }

                if !xiegu.lastMessage.isEmpty {
                    Text(xiegu.lastMessage)
                        .font(.caption2.monospaced())
                        .foregroundColor(xiegu.isConnected ? .green : .secondary)
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Audio Interface Card
    private var audioInterfaceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.circle")
                    .foregroundColor(.green)
                Text("Channel 2: USB-C Bidirectional Audio CODEC")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(xiegu.isAudioDeviceDetected ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(xiegu.detectedAudioDeviceName ?? "USB Audio CODEC Not Detected")
                            .font(.callout.bold())
                            .foregroundColor(xiegu.isAudioDeviceDetected ? .primary : .orange)

                        Text("Xiegu X6100 features a built-in USB Audio Class (UAC) sound card over the USB-C DEV port. Standard 48.0 kHz 16-bit PCM for FT8, FT4, RTTY, PSK31, and CW audio decoding.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        xiegu.scanAudioDevices()
                    } label: {
                        Label("Scan Audio", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Hardware Diagnostics & Tests
    private var hardwareDiagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "stethoscope")
                    .foregroundColor(.purple)
                Text("Interactive Hardware Verification & Diagnostics")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 14) {
                // Live Transceiver Status
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VFO Frequency")
                            .font(.caption2).foregroundColor(.secondary)
                        Text(xiegu.formattedFrequency)
                            .font(.system(.title3, design: .monospaced).bold())
                            .foregroundColor(.cyan)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Operating Mode")
                            .font(.caption2).foregroundColor(.secondary)
                        Text(xiegu.mode)
                            .font(.system(.title3, design: .monospaced).bold())
                            .foregroundColor(.green)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("S-Meter")
                            .font(.caption2).foregroundColor(.secondary)
                        Text(xiegu.sMeterDescription)
                            .font(.system(.title3, design: .monospaced).bold())
                            .foregroundColor(.yellow)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("RF Power")
                            .font(.caption2).foregroundColor(.secondary)
                        Text("\(xiegu.powerWatts) W")
                            .font(.system(.title3, design: .monospaced).bold())
                            .foregroundColor(.orange)
                    }

                    Spacer()

                    // Quick Mode Buttons
                    HStack(spacing: 6) {
                        Button("USB-D") { xiegu.setMode("USB-D") }
                            .buttonStyle(.bordered)
                            .disabled(!xiegu.isConnected)
                        Button("CW") { xiegu.setMode("CW") }
                            .buttonStyle(.bordered)
                            .disabled(!xiegu.isConnected)
                        Button("USB") { xiegu.setMode("USB") }
                            .buttonStyle(.bordered)
                            .disabled(!xiegu.isConnected)
                    }
                }

                Divider()

                // Test Actions
                HStack(spacing: 14) {
                    // PTT Test
                    Button {
                        isTestingPTT = true
                        xiegu.setPTT(true, maximumDuration: 1.0)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            xiegu.setPTT(false)
                            isTestingPTT = false
                        }
                    } label: {
                        Label(isTestingPTT ? "Keying Transceiver (1s)..." : "1-Second PTT Test", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!xiegu.isConnected || isTestingPTT)

                    // CW Test
                    Button {
                        isTestingCW = true
                        xiegu.sendMorse("TEST YAAM DE X6100")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            isTestingCW = false
                        }
                    } label: {
                        Label(isTestingCW ? "Sending CW..." : "Send Test Morse (CI-V 0x17)", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!xiegu.isConnected || isTestingCW)

                    // Synchronize RigControlEngine
                    Button {
                        rigEngine.driverType = .xiegu6100
                        rigEngine.connect()
                    } label: {
                        Label("Use as Primary CAT Rig", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!xiegu.isConnected)
                }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    // MARK: - Pre-Flight Checklist & Guidance
    private var checklistAndReferenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(.blue)
                Text("Xiegu X6100 Pre-Flight Checklist & Setup Tips")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 8) {
                checklistRow(number: "1", title: "Physical Cable Connection", detail: "Connect your USB-C cable to the 'DEV' port on the left side of the X6100. Do NOT use the 'HOST' port.")
                checklistRow(number: "2", title: "Radio Menu Configuration", detail: "Ensure CI-V Address is set to 0xA4 (Menu default) and CI-V Baud Rate is set to 19200 bps.")
                checklistRow(number: "3", title: "Digital Mode Operation", detail: "Set Mode to USB-DIG on the radio. In YAAM FT8 Station View, select 'Xiegu X6100 (USB-C)' as the audio/radio path.")
                checklistRow(number: "4", title: "CW / Morse Code Operation", detail: "In YAAM CW Keyer, choose 'Xiegu X6100 (USB-C CAT & Pin)'. Both CI-V 0x17 text buffer keying and DTR/RTS hardware line keying are supported.")
                checklistRow(number: "5", title: "Power Supply Note", detail: "On internal battery, maximum RF power is 5 Watts. Connect an external 13.8V DC supply for full 10 Watts QRP output.")
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    private func checklistRow(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.15), in: Circle())
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.bold())
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
