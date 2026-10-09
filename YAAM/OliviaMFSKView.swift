//
//  OliviaMFSKView.swift
//  YAAM
//
//  Multi-Tone Orthogonal Workstation for Olivia MFSK & Contestia Modes
//  Features live multi-tone LED matrix activity indicator, Walsh-Hadamard confidence gauge,
//  sub-noise decoding down to -14 dB SNR, and type-ahead conversational terminal.
//

import AppKit
import SwiftUI

public struct OliviaMFSKView: View {
    @ObservedObject var engine: OliviaMFSKEngine

    public init(engine: OliviaMFSKEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(spacing: 8) {
            // 1. Top Control Bar
            topControlBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(10)

            // 2. Multi-Tone LED Activity Matrix & Spectral Ruler
            toneMatrixBay
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(red: 0.03, green: 0.04, blue: 0.06))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                )

            // 3. Conversational RX/TX Terminals
            terminalsBay
                .frame(minHeight: 180)

            // 4. TX Controls & 1-Click Logging
            txControlBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                .cornerRadius(10)
        }
        .padding(10)
        .onReceive(NotificationCenter.default.publisher(for: TransmitIdentity.identityChanged)) { _ in
            // A refusal shown for the previous profile no longer applies.
            engine.txRefusal = ""
        }
    }

    // MARK: - 1. Top Control Bar

    private var topControlBar: some View {
        HStack(spacing: 12) {
            // Master Start / Stop
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
                    Text(engine.isListening ? "STOP OLIVIA" : "START OLIVIA")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isListening ? .red : .teal)

            // Configuration Picker
            Picker("Format:", selection: $engine.config) {
                ForEach(OliviaConfiguration.allCases) { c in
                    Text(c.rawValue).tag(c)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 170)

            Divider().frame(height: 20)

            // Center Pitch
            HStack(spacing: 4) {
                Text("PITCH:")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                Text("\(Int(engine.centerFrequencyHz)) Hz")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .frame(width: 52)
            }

            // Confidence Level Badge
            HStack(spacing: 4) {
                Text("FEC LOCK:")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                Text(String(format: "%0.1f%%", engine.confidenceLevel))
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .foregroundColor(engine.confidenceLevel > 70.0 ? .green : .secondary)
            }

            Spacer()

            // Simulation Button
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

            // Clear Button
            Button {
                engine.clearTerminals()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - 2. Multi-Tone LED Activity Matrix

    private var toneMatrixBay: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("MFSK WALSH-HADAMARD TONE MATRIX (\(engine.config.toneCount) TONES · \(Int(engine.config.bandwidthHz)) Hz BW)", systemImage: "music.note.list")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)

                Spacer()

                Text("TONE SPACING: \(String(format: "%0.2f", engine.config.toneSpacingHz)) Hz")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Glowing Tone Bars Row
            HStack(spacing: 4) {
                ForEach(0..<engine.config.toneCount, id: \.self) { t in
                    let act = t < engine.toneActivity.count ? Double(engine.toneActivity[t]) : 0.0
                    let isDom = t == engine.dominantTone && act > 0.4

                    VStack(spacing: 3) {
                        ZStack(alignment: .bottom) {
                            // Dark Channel Track
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(white: 0.12))
                                .frame(height: 54)

                            // Active Lit Bar
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: isDom ? [Color.green, Color.cyan] : [Color.blue.opacity(0.6), Color.purple.opacity(0.8)],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(height: max(4, 54.0 * CGFloat(act)))
                                .shadow(color: isDom ? Color.cyan.opacity(0.7) : Color.clear, radius: 4)
                        }

                        // Tone Number Label
                        Text("\(t)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(isDom ? .cyan : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - 3. Conversational Terminals

    private var terminalsBay: some View {
        HStack(spacing: 12) {
            // RX Terminal
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("RX DECODED TEXT (DOWN TO -14 dB SNR)", systemImage: "text.bubble")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.green)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)

                ScrollViewReader { proxy in
                    ScrollView {
                        Text(engine.rxText.isEmpty ? "Waiting for MFSK signal on \(Int(engine.centerFrequencyHz)) Hz..." : engine.rxText)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(engine.rxText.isEmpty ? .secondary.opacity(0.7) : .green)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .id("OLIVIA_RX_BOTTOM")
                    }
                    .onChange(of: engine.rxText) { _, _ in
                        proxy.scrollTo("OLIVIA_RX_BOTTOM", anchor: .bottom)
                    }
                }
                .background(Color(red: 0.04, green: 0.05, blue: 0.06))
                .cornerRadius(6)
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            .cornerRadius(10)

            // TX Buffer
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("TX BUFFER", systemImage: "paperplane")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.teal)
                    Spacer()
                    if engine.isTransmitting {
                        Text("TRANSMITTING")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)

                TextEditor(text: $engine.txBufferText)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundColor(.white)
                    .background(Color(red: 0.06, green: 0.05, blue: 0.07))
                    .cornerRadius(6)
                    .padding(.horizontal, 6)
            }
            .frame(width: 320)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            .cornerRadius(10)
        }
    }

    // MARK: - 4. TX Controls & 1-Click Logging

    private var txControlBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !engine.txRefusal.isEmpty {
                Text(engine.txRefusal)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            txControlButtons
        }
    }

    private var txControlButtons: some View {
        HStack(spacing: 8) {
            // Quick Macros
            Button("CQ") { engine.queueTextForTransmission("CQ CQ DE \(engine.myCallsign) \(engine.myCallsign) K ") }.buttonStyle(.bordered).font(.caption2)
            Button("Exch") { engine.queueTextForTransmission("\(engine.targetCallsign.isEmpty ? "DX" : engine.targetCallsign) 599 001 BK ") }.buttonStyle(.bordered).font(.caption2)
            Button("73") { engine.queueTextForTransmission("73 GL DE \(engine.myCallsign) SK ") }.buttonStyle(.bordered).font(.caption2)

            Spacer()

            // Target Callsign Field & 1-Click Log
            HStack(spacing: 4) {
                Text("CALL:")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                TextField("CALL", text: $engine.targetCallsign)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)

                Button("LOG QSO") {
                    engine.logCurrentQSO()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(engine.targetCallsign.isEmpty)
            }

            Divider().frame(height: 20)

            Button {
                if engine.isTransmitting {
                    engine.stopTransmission()
                } else {
                    engine.startTransmission()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: engine.isTransmitting ? "stop.fill" : "paperplane.fill")
                    Text(engine.isTransmitting ? "ABORT" : "TRANSMIT")
                        .font(.caption.bold())
                }
                .frame(width: 85)
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isTransmitting ? .red : .teal)
        }
    }
}
