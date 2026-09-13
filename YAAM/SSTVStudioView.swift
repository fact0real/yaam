//
//  SSTVStudioView.swift
//  YAAM
//
//  Slow Scan Television (SSTV) Studio & Cathode Ray Scanline Monitor
//  Features live line-by-line electron beam sweeping, Robot 36 / Martin M1 / Scottie S1 decoding,
//  picture gallery, test-card transmission, and 1-click YAAM logging.
//

import AppKit
import SwiftUI

public struct SSTVStudioView: View {
    @ObservedObject var engine: SSTVEngine

    public init(engine: SSTVEngine) {
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

            // 2. Main Workstation: CRT Monitor + Gallery & Controls
            HStack(spacing: 12) {
                // Left: Cathode Ray Scanline Monitor
                crtMonitorPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Right: Transmitter Studio & Image Gallery
                sidebarStudioPanel
                    .frame(width: 280)
            }
            .frame(minHeight: 280)

            // 3. Bottom Target Bar & 1-Click Logging
            bottomTargetBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.06))
                .cornerRadius(10)
        }
        .padding(10)
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
                    Text(engine.isListening ? "STOP SSTV" : "START SSTV")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isListening ? .red : .orange)

            // Mode Selector
            Picker("Mode:", selection: $engine.operatingMode) {
                ForEach(SSTVMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200)

            Divider().frame(height: 20)

            // FM Subcarrier Frequency
            HStack(spacing: 4) {
                Text("SUBCARRIER:")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                Text("\(Int(engine.detectedFrequencyHz)) Hz")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(engine.syncPulseDetected ? .yellow : .cyan)
                    .frame(width: 54)
            }

            // Sync Pulse Indicator
            Circle()
                .fill(engine.syncPulseDetected ? Color.yellow : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)
                .help("1200 Hz Horizontal Sync Pulse Detected")

            Spacer()

            // Simulation Button
            Button {
                engine.toggleSimulation()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: engine.isSimulationActive ? "bolt.fill" : "bolt")
                        .foregroundColor(engine.isSimulationActive ? .yellow : .secondary)
                    Text(engine.isSimulationActive ? "RECEIVING..." : "Practice Image")
                        .font(.caption2.bold())
                }
            }
            .buttonStyle(.bordered)
            .tint(engine.isSimulationActive ? .yellow : .secondary)

            // Clear Button
            Button {
                engine.clearCanvas()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - 2. Cathode Ray Scanline Monitor Panel

    private var crtMonitorPanel: some View {
        ZStack {
            // Bezel Outer Shadow & Frame
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(white: 0.22), lineWidth: 1.5)
                )

            // Screen Area
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // Decoded Image Canvas
                    if let img = engine.liveImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(8)
                    } else {
                        Rectangle()
                            .fill(Color.black)
                            .cornerRadius(8)
                    }

                    // Sweeping Electron Beam Scanline
                    if engine.scanProgress > 0.0 && engine.scanProgress < 1.0 {
                        let scanY = geo.size.height * CGFloat(engine.scanProgress)
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.green.opacity(0.0), Color.green, Color.white],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 2.5)
                            .shadow(color: .green, radius: 5)
                            .position(x: geo.size.width * 0.5, y: scanY)
                    }

                    // Scanline / Reticle Line Overlay
                    VStack {
                        Spacer()
                        HStack {
                            Text("LINE: \(engine.currentScanline) / \(engine.operatingMode.height) · \(String(format: "%0.1f%%", engine.scanProgress * 100.0))")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                                .padding(6)
                                .background(Color.black.opacity(0.75))
                                .cornerRadius(4)
                            Spacer()
                        }
                        .padding(8)
                    }
                }
            }
            .padding(10)
        }
    }

    // MARK: - 3. Sidebar Studio & Gallery Panel

    private var sidebarStudioPanel: some View {
        VStack(spacing: 8) {
            // TX Picture Studio Card
            VStack(alignment: .leading, spacing: 6) {
                Label("TX PICTURE STUDIO", systemImage: "camera.fill")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)

                Divider()

                Text("Send SMPTE color test card with station callsign watermark.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Button {
                    if engine.isTransmitting {
                        engine.stopTransmission()
                    } else {
                        engine.transmitTestCard()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: engine.isTransmitting ? "stop.fill" : "antenna.radiowaves.left.and.right")
                        Text(engine.isTransmitting ? "ABORT TX" : "SEND TEST PATTERN")
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(engine.isTransmitting ? .red : .orange)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            .cornerRadius(10)

            // Received Images Gallery
            VStack(alignment: .leading, spacing: 6) {
                Label("RECEIVED GALLERY (\(engine.gallery.count))", systemImage: "photo.stack")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)

                Divider()

                if engine.gallery.isEmpty {
                    Text("No saved images yet.\n(Tip: click 'Practice Image' to simulate reception)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(engine.gallery) { item in
                                if let thumb = item.makeNSImage() {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Image(nsImage: thumb)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .cornerRadius(6)

                                        HStack {
                                            Text(item.callsign.isEmpty ? "DX" : item.callsign)
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            Spacer()
                                            Text(item.mode.components(separatedBy: " ").first ?? "")
                                                .font(.system(size: 8.5, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(6)
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(8)
                                }
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
            .cornerRadius(10)
        }
    }

    // MARK: - 4. Bottom Target Bar & 1-Click Logging

    private var bottomTargetBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text("CALL:")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                TextField("CALL", text: $engine.targetCallsign)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
            }

            Spacer()

            Button {
                engine.logCurrentQSO()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                    Text("LOG SSTV QSO")
                        .font(.caption.bold())
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(engine.targetCallsign.isEmpty)
        }
    }
}
