//
//  TCIControlView.swift
//  YAAM
//
//  Transceiver Control Interface (TCI) Workspace & SDR Console
//  High-speed WebSocket controls for SunSDR2, MB1, Thetis (ANAN), SDRUno.
//  VFO A/B tuning, S-Meter/Power/SWR telemetry, PTT/Tune, and Waterfall Spot Streaming.
//

import AppKit
import Combine
import SwiftUI

public struct TCIControlView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var tci = TCIClient.shared

    @State private var inputHost: String = "127.0.0.1"
    @State private var inputPort: String = "40001"
    @State private var actionStatus: String = "Ready"

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            // Connection Bar
            connectionBar

            if tci.isConnected {
                // VFO & Telemetry HUD
                vfoAndTelemetryHUD

                // Mode & Quick Controls
                operatingControls

                // Quick Band Selector
                quickBandBar
            } else {
                disconnectedPlaceholder
            }

            Spacer()
        }
        .padding(18)
        .onAppear {
            inputHost = tci.host
            inputPort = String(tci.port)
        }
    }

    // MARK: - Connection Bar

    private var connectionBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.title2)
                    .foregroundColor(tci.isConnected ? .green : .secondary)
                Text("TCI Protocol (ExpertSDR / Thetis)")
                    .font(.headline.bold())
            }

            Spacer()

            if !tci.isConnected {
                TextField("Host", text: $inputHost)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)

                TextField("Port", text: $inputPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)

                Button("Connect") {
                    let p = Int(inputPort) ?? 40001
                    tci.connect(host: inputHost, port: p)
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("Connected to ws://\(tci.host):\(tci.port) (TCI v\(tci.serverProtocol))")
                        .font(.caption.bold())
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                Button("Disconnect", role: .destructive) {
                    tci.disconnect()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - VFO & Telemetry HUD

    private var vfoAndTelemetryHUD: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 20) {
                // VFO A Primary Readout
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("VFO A")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Text(tci.currentBand)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2), in: Capsule())
                            .foregroundColor(.blue)
                        Text(tci.mode)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                            .foregroundColor(.orange)
                    }

                    Text(formattedVFO(tci.vfoAFrequencyHz))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundColor(tci.isPTTActive ? .red : (tci.isTuneActive ? .orange : .primary))
                }

                Spacer()

                // S-Meter & Power Meters
                VStack(alignment: .trailing, spacing: 6) {
                    // S-Meter Bar
                    HStack(spacing: 8) {
                        Text("S-METER")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)

                        sMeterBar(dbm: tci.sMeterDbm)
                            .frame(width: 140, height: 12)

                        Text("\(Int(tci.sMeterDbm)) dBm")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 55, alignment: .trailing)
                    }

                    // TX Power & SWR
                    if tci.isPTTActive || tci.isTuneActive {
                        HStack(spacing: 12) {
                            Text("PWR: \(String(format: "%.1f W", tci.txPowerWatts))")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundColor(.red)
                            Text("SWR: \(String(format: "%.2f", tci.txSWR))")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundColor(tci.txSWR > 2.0 ? .red : .green)
                        }
                    }
                }
            }

            Divider()

            // Action Buttons
            HStack(spacing: 12) {
                Button {
                    let snapshot = RigSnapshot(
                        frequencyHz: tci.vfoAFrequencyHz,
                        mode: tci.mode,
                        passbandHz: nil,
                        updatedAt: Date()
                    )
                    appState.applyRigSnapshotToQuickLog(snapshot)
                    actionStatus = "TCI frequency (\(tci.frequencyMHz) MHz) copied to Quick Log"
                } label: {
                    Label("Use in Quick Log", systemImage: "arrow.down.to.line.compact")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    streamSpotsToWaterfall()
                } label: {
                    Label("Stream Spots to SDR Waterfall", systemImage: "water.waves")
                }
                .buttonStyle(.bordered)

                Spacer()

                Text(actionStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Operating Controls (Mode & PTT)

    private var operatingControls: some View {
        HStack(spacing: 16) {
            // Mode Selector Grid
            HStack(spacing: 6) {
                ForEach(["CW", "USB", "LSB", "DIGIU", "FM", "AM"], id: \.self) { m in
                    Button(m) {
                        tci.setMode(m)
                    }
                    .buttonStyle(.bordered)
                    .tint(tci.mode == m ? .blue : .secondary)
                    .controlSize(.small)
                }
            }

            Spacer()

            // PTT and TUNE Buttons
            HStack(spacing: 10) {
                Button {
                    tci.setTune(!tci.isTuneActive)
                } label: {
                    Label("TUNE", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(tci.isTuneActive ? .orange : .secondary)

                Button {
                    tci.setPTT(!tci.isPTTActive)
                } label: {
                    Label(tci.isPTTActive ? "TX ON" : "PTT", systemImage: "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(tci.isPTTActive ? .red : .blue)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Quick Band Selector

    private var quickBandBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Bands:")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                let bands: [(String, UInt64, String)] = [
                    ("160M", 1840000, "CW"),
                    ("80M", 3573000, "LSB"),
                    ("40M", 7074000, "LSB"),
                    ("30M", 10136000, "USB"),
                    ("20M", 14074000, "USB"),
                    ("17M", 18100000, "USB"),
                    ("15M", 21074000, "USB"),
                    ("12M", 24915000, "USB"),
                    ("10M", 28074000, "USB"),
                    ("6M", 50313000, "USB"),
                    ("2M", 144174000, "USB")
                ]

                ForEach(bands, id: \.0) { bandName, hz, m in
                    Button(bandName) {
                        tci.setFrequency(hz: hz)
                        tci.setMode(m)
                    }
                    .buttonStyle(.bordered)
                    .tint(tci.currentBand == bandName ? .blue : .primary)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Disconnected Placeholder

    private var disconnectedPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.6))
            Text("TCI SDR Receiver Disconnected")
                .font(.headline)
            Text("Start ExpertSDR or Thetis and connect to ws://127.0.0.1:40001 to enable ultra-low latency SDR waterfall integration.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(10)
    }

    // MARK: - Helpers & S-Meter Drawing

    private func formattedVFO(_ hz: UInt64) -> String {
        let mhz = Double(hz) / 1_000_000.0
        return String(format: "%.4f MHz", mhz)
    }

    private func sMeterBar(dbm: Double) -> some View {
        GeometryReader { geo in
            let minDbm: Double = -120.0
            let maxDbm: Double = -40.0
            let ratio = max(0.0, min(1.0, (dbm - minDbm) / (maxDbm - minDbm)))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.2))
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [.green, .yellow, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * CGFloat(ratio))
            }
        }
    }

    private func streamSpotsToWaterfall() {
        let spots = BandmapEngine.shared.spots
        for spot in spots.prefix(20) {
            let hz = UInt64(spot.frequencyKHz * 1000.0)
            tci.postSpot(
                callsign: spot.callsign,
                mode: spot.mode,
                frequencyHz: hz,
                text: spot.comment
            )
        }
        actionStatus = "Streamed \(min(20, spots.count)) spots to SDR waterfall"
    }
}
