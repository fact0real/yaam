//
//  WinKeyerView.swift
//  YAAM
//
//  K1EL WinKeyer Hardware Control Panel & Diagnostics
//  Configure USB Serial port, Baud Rate, Iambic Mode, WPM, Sidetone Hz, Weighting,
//  and test live Morse keying with real-time character echo highlighting.
//

import AppKit
import SwiftUI

public struct WinKeyerView: View {
    @ObservedObject private var wk = WinKeyerDriver.shared
    @State private var testInput: String = "CQ CQ DE EP2AES K"

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            // Hardware Serial Connection Card
            serialConnectionCard

            if wk.isConnected {
                // Keyer Hardware Settings
                hardwareSettingsCard

                // Interactive Test Transmitter
                testTransmitterCard
            } else {
                disconnectedPlaceholder
            }

            Spacer()
        }
        .padding(18)
        .onAppear {
            wk.refreshPorts()
        }
    }

    // MARK: - Serial Connection Card

    private var serialConnectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "cable.connector.horizontal")
                    .font(.title2)
                    .foregroundColor(wk.isConnected ? .green : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("K1EL WinKeyer Hardware (USB Serial)")
                        .font(.headline.bold())
                    Text("Direct micro-controller Morse timing over USB UART chip")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if wk.isConnected {
                    HStack(spacing: 6) {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text(wk.wkVersion)
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12), in: Capsule())

                    Button("Disconnect", role: .destructive) {
                        wk.disconnect()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !wk.isConnected {
                Divider()

                HStack(spacing: 12) {
                    Picker("Serial Port:", selection: $wk.selectedPort) {
                        if wk.availableSerialPorts.isEmpty {
                            Text("No serial ports found").tag("")
                        } else {
                            ForEach(wk.availableSerialPorts, id: \.self) { port in
                                Text(port).tag(port)
                            }
                        }
                    }
                    .frame(maxWidth: 320)

                    Button {
                        wk.refreshPorts()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh serial ports")

                    Picker("Baud:", selection: $wk.baudRate) {
                        Text("1200 (WK2)").tag(1200)
                        Text("9600 (WK3)").tag(9600)
                    }
                    .frame(width: 130)

                    Button("Connect") {
                        wk.connect()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(wk.selectedPort.isEmpty)
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Hardware Settings Card

    private var hardwareSettingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("WinKeyer Internal Registers")
                .font(.subheadline.bold())

            HStack(spacing: 20) {
                // Keyer Mode
                Picker("Keyer Mode:", selection: $wk.mode) {
                    ForEach(WinKeyerMode.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }
                .onChange(of: wk.mode) { _, newMode in
                    wk.setMode(newMode)
                }
                .frame(width: 220)

                // Speed WPM
                HStack(spacing: 8) {
                    Text("Speed:")
                        .font(.caption.bold())
                    Slider(value: Binding(
                        get: { Double(wk.wpm) },
                        set: { wk.setSpeed(Int($0)) }
                    ), in: 10...50, step: 1)
                    .frame(width: 120)

                    Text("\(wk.wpm) WPM")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .frame(width: 60)
                }

                // Sidetone Pitch
                Picker("Sidetone:", selection: $wk.sidetoneHz) {
                    Text("500 Hz").tag(500)
                    Text("600 Hz").tag(600)
                    Text("700 Hz").tag(700)
                    Text("800 Hz").tag(800)
                }
                .onChange(of: wk.sidetoneHz) { _, newHz in
                    wk.setSidetone(newHz)
                }
                .frame(width: 140)
            }

            HStack(spacing: 24) {
                Toggle("Swap Paddles (Left/Right)", isOn: $wk.paddleSwap)
                    .onChange(of: wk.paddleSwap) { _, _ in
                        wk.setMode(wk.mode)
                    }

                Toggle("Auto-Space (Letter Spacing)", isOn: $wk.autoSpace)
                    .onChange(of: wk.autoSpace) { _, _ in
                        wk.setMode(wk.mode)
                    }

                HStack(spacing: 6) {
                    Text("Weighting:")
                        .font(.caption)
                    Slider(value: Binding(
                        get: { Double(wk.weight) },
                        set: { wk.setWeight(Int($0)) }
                    ), in: 30...70, step: 1)
                    .frame(width: 100)
                    Text("\(wk.weight)%")
                        .font(.caption.monospacedDigit())
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Test Transmitter Card

    private var testTransmitterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Interactive Keyer Test")
                .font(.subheadline.bold())

            HStack(spacing: 10) {
                TextField("Enter Morse message to send...", text: $testInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        wk.sendMorseText(testInput)
                    }

                Button {
                    wk.sendMorseText(testInput)
                } label: {
                    Label("Send Morse", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(testInput.trimmingCharacters(in: .whitespaces).isEmpty)

                Button(role: .destructive) {
                    wk.abort()
                } label: {
                    Label("ABORT (ESC)", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }

            // Real-time Echo HUD
            HStack(spacing: 12) {
                if wk.isTransmitting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Transmitting via WinKeyer Hardware...")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                    }
                }

                Spacer()

                if !wk.lastEchoedChar.isEmpty {
                    HStack(spacing: 4) {
                        Text("Hardware Echo:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(wk.lastEchoedChar)
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Disconnected Placeholder

    private var disconnectedPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "cable.connector.horizontal")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.6))
            Text("No WinKeyer Device Connected")
                .font(.headline)
            Text("Plug in your K1EL WKUSB, microHAM CW Keyer, or Arduino Winkeyer emulator to `/dev/cu.usbserial` and click Connect.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
    }
}
