//
//  DigitalModemStationView.swift
//  YAAM
//
//  Premier Digital Modem Workstation for RTTY & PSK31
//  Combines CRT Lissajous Crossed-Ellipses Scope, Audio Waterfall with Click-to-Tune,
//  Color-Coded Token Stream, Type-Ahead TX Buffer, F1-F8 Macros, and 1-Click YAAM Logging.
//

import AppKit
import SwiftUI

public struct DigitalModemStationView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var engine: DigitalModemEngine

    @State private var isCustomPitchPresented = false
    @State private var pitchInputText = "1500"
    @State private var showMacroEditor = false

    public init(engine: DigitalModemEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(spacing: 8) {
            // 1. Top Operating Control Ribbon
            topControlRibbon
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(10)

            // 2. Visualizer Bay: Crossed-Ellipses Scope + Audio Waterfall
            HStack(spacing: 12) {
                // CRT Crossed-Ellipses Oscilloscope (Fixed square aspect)
                RTTYCrossedEllipsesScopeView(engine: engine)
                    .frame(width: 220, height: 210)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(10)

                // High-Res Audio Waterfall with Click-to-Tune
                DigitalAudioWaterfallView(engine: engine)
                    .frame(height: 210)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(10)
            }

            // 3. Dual-Pane Terminal Bay (RX Log Stream + TX Type-Ahead Buffer)
            HStack(spacing: 12) {
                // Left / Upper: RX Received Text Terminal
                rxTerminalPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                    .cornerRadius(10)

                // Right / Lower: TX Type-Ahead Buffer & Transmit Controls
                txTerminalPanel
                    .frame(width: 320)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                    .cornerRadius(10)
            }
            .frame(minHeight: 180)

            // 4. Contest & Ragchew Macro Ribbon (F1 - F8)
            macroRibbon
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            // 5. Active Target DX Intelligence & 1-Click QSO Logger
            targetLogBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.06))
                .cornerRadius(10)
        }
        .padding(10)
        .onAppear {
            syncStationInfo()
        }
    }

    private func syncStationInfo() {
        if engine.myCallsign.isEmpty {
            engine.myCallsign = appState.currentStationCallsign
        }
        if engine.myGrid.isEmpty, let grid = appState.activeStationProfile?.grid {
            engine.myGrid = grid
        }
    }

    // MARK: - 1. Top Operating Control Ribbon

    private var topControlRibbon: some View {
        HStack(spacing: 12) {
            // Master Modem Power Button
            Button {
                if engine.isListening {
                    engine.stopListening()
                } else {
                    engine.startListening()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: engine.isListening ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title3)
                    Text(engine.isListening ? "STOP MODEM" : "START MODEM")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isListening ? .red : .green)

            // Mode Selector Picker
            Picker("Mode:", selection: $engine.operatingMode) {
                ForEach(DigitalOperatingMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 170)

            Divider().frame(height: 20)

            // Pitch & Center Frequency Controls
            HStack(spacing: 4) {
                Text("PITCH:")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)

                Button {
                    engine.adjustCenterFrequency(by: -25.0)
                } label: {
                    Image(systemName: "minus.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Text("\(Int(engine.centerFrequencyHz)) Hz")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .frame(width: 54)

                Button {
                    engine.adjustCenterFrequency(by: 25.0)
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Menu {
                    Button("1275 Hz (Low Tones)") { engine.setCenterFrequency(1275.0) }
                    Button("1500 Hz (Standard)") { engine.setCenterFrequency(1500.0) }
                    Button("2125 Hz (High Standard)") { engine.setCenterFrequency(2125.0) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 20)

            // Toggles (AFC, REV, UOS)
            HStack(spacing: 8) {
                Toggle("AFC", isOn: $engine.afcEnabled)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .help("Automatic Frequency Control tracks frequency drift.")

                if engine.operatingMode.isRTTY {
                    Toggle("REV", isOn: $engine.reversePolarity)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .help("Reverse Mark/Space polarity (useful for LSB/USB swaps).")

                    Toggle("UOS", isOn: $engine.unshiftOnSpace)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .help("Unshift-On-Space automatically resets Baudot state to letters after space.")
                }
            }

            Divider().frame(height: 20)

            // Squelch Slider
            HStack(spacing: 4) {
                Image(systemName: "speaker.wave.1")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Slider(value: $engine.squelchThreshold, in: 0.01...0.30)
                    .frame(width: 60)
                    .help("Squelch threshold level")
            }

            Spacer()

            // Simulation / Practice Mode Button
            Button {
                engine.toggleSimulation()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: engine.isSimulationActive ? "bolt.fill" : "bolt")
                        .foregroundColor(engine.isSimulationActive ? .yellow : .secondary)
                    Text(engine.isSimulationActive ? "SIM ON" : "Practice Feed")
                        .font(.caption2.bold())
                }
            }
            .buttonStyle(.bordered)
            .tint(engine.isSimulationActive ? .yellow : .secondary)
            .help("Toggle on-air practice signals with QSB fading and test exchanges.")

            // Clear Button
            Button {
                engine.clearTerminals()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("Clear RX and TX text buffers.")
        }
    }

    // MARK: - 3. Dual-Pane Terminal Bay

    private var rxTerminalPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("RX DECODE STREAM", systemImage: "text.bubble.fill")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)

                Spacer()

                // Audio Metrics Badge
                HStack(spacing: 8) {
                    Text("SNR: \(String(format: "%0.1f", engine.signalToNoiseRatioDb)) dB")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(engine.signalToNoiseRatioDb > 8.0 ? .green : .secondary)

                    if engine.operatingMode.isRTTY {
                        Text("SHIFT: \(engine.baudotState == .letters ? "LTRS" : "FIGS")")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            Divider()

            // Terminal Scrollable View with Clickable Tokens
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        // Raw text stream display
                        Text(engine.rxText.isEmpty ? "Waiting for digital signal on \(Int(engine.centerFrequencyHz)) Hz...\n(Tip: click 'Practice Feed' to test without a radio)" : engine.rxText)
                            .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                            .foregroundColor(engine.rxText.isEmpty ? .secondary.opacity(0.7) : .green)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("RX_BOTTOM")

                        // Clickable Decoded Callsigns Ribbon
                        if !engine.decodedTokens.isEmpty {
                            Divider().padding(.vertical, 4)
                            HStack(spacing: 6) {
                                Text("FOUND CALLS:")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(engine.decodedTokens.filter { $0.isCallsign }.suffix(12)) { tok in
                                            Button {
                                                engine.selectTargetCallsign(tok.text)
                                            } label: {
                                                HStack(spacing: 3) {
                                                    Image(systemName: "person.crop.circle")
                                                        .font(.system(size: 8))
                                                    Text(tok.text)
                                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                }
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.yellow.opacity(0.18))
                                                .foregroundColor(.yellow)
                                                .cornerRadius(4)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
                .onChange(of: engine.rxText) { _, _ in
                    proxy.scrollTo("RX_BOTTOM", anchor: .bottom)
                }
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.06))
            .cornerRadius(6)
            .padding([.horizontal, .bottom], 8)
        }
    }

    private var txTerminalPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("TX TYPE-AHEAD BUFFER", systemImage: "paperplane.fill")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)

                Spacer()

                if engine.isTransmitting {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                        Text("TRANSMITTING")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            Divider()

            // Type-Ahead Text Input Field
            TextEditor(text: $engine.txBufferText)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(.white)
                .background(Color(red: 0.08, green: 0.06, blue: 0.04))
                .cornerRadius(6)
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity)

            // Transmit Progress Bar
            if engine.isTransmitting {
                ProgressView(value: engine.txProgress, total: 1.0)
                    .tint(.orange)
                    .padding(.horizontal, 8)
            }

            // Bottom TX Control Buttons
            HStack(spacing: 8) {
                Button {
                    if engine.isTransmitting {
                        engine.stopTransmission()
                    } else {
                        engine.startTransmission()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: engine.isTransmitting ? "stop.fill" : "paperplane.fill")
                        Text(engine.isTransmitting ? "ABORT TX" : "TRANSMIT")
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(engine.isTransmitting ? .red : .orange)

                Button("Clear TX") {
                    engine.txBufferText = ""
                    engine.txRemainingText = ""
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    // MARK: - 4. Macro Ribbon (F1 - F8)

    private var macroRibbon: some View {
        HStack(spacing: 6) {
            ForEach(engine.macros) { macro in
                Button {
                    engine.triggerMacro(macro)
                } label: {
                    VStack(spacing: 1) {
                        Text("F\(macro.id)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                        Text(macro.name)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .help("Trigger: \(engine.expandMacroTemplate(macro.template).replacingOccurrences(of: "\r\n", with: " "))")
            }
        }
    }

    // MARK: - 5. Active Target DX Intelligence & 1-Click QSO Logger

    private var targetLogBar: some View {
        HStack(spacing: 12) {
            // Target Callsign Field
            HStack(spacing: 6) {
                Text("CALL:")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                TextField("DX CALL", text: $engine.targetCallsign)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .frame(width: 100)
                    .onChange(of: engine.targetCallsign) { _, newCall in
                        engine.selectTargetCallsign(newCall)
                    }
            }

            // DXCC & Flag Badge
            if !engine.targetCallsign.isEmpty {
                HStack(spacing: 6) {
                    Text(engine.targetCountryFlag)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(engine.targetCountryName.isEmpty ? "International" : engine.targetCountryName)
                            .font(.caption.bold())
                        Text("Continent: \(engine.targetContinent.isEmpty ? "??" : engine.targetContinent)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // RST Sent & Received
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text("SENT:")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    TextField("599", text: $engine.targetReportSent)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 44)
                }

                HStack(spacing: 4) {
                    Text("RCVD:")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    TextField("599", text: $engine.targetReportReceived)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 44)
                }

                HStack(spacing: 4) {
                    Text("SER:")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    Text(String(format: "%03d", engine.targetSerial))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .frame(width: 32)
                }
            }

            // Big 1-Click Log QSO Button
            Button {
                engine.logCurrentQSO()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                    Text("LOG QSO")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(engine.targetCallsign.isEmpty)
        }
    }
}
