//
//  HellschreiberView.swift
//  YAAM
//
//  Vintage Facsimile Ticker-Tape Workstation for Hellschreiber (Feld Hell)
//  Features authentic dual-line moving ribbon, aged paper & phosphor themes,
//  real-time slant/speed calibration, type-ahead TX, and 1-click YAAM logging.
//

import AppKit
import SwiftUI

public enum HellTapeTheme: String, CaseIterable, Identifiable, Sendable {
    case agedPaper = "Vintage Paper"
    case phosphorGreen = "Phosphor CRT"
    case darkNeon = "Dark Neon"

    public var id: String { rawValue }

    public var paperColor: Color {
        switch self {
        case .agedPaper: return Color(red: 0.94, green: 0.91, blue: 0.82)
        case .phosphorGreen: return Color(red: 0.02, green: 0.06, blue: 0.02)
        case .darkNeon: return Color(red: 0.05, green: 0.06, blue: 0.08)
        }
    }

    public var inkColor: Color {
        switch self {
        case .agedPaper: return Color(red: 0.15, green: 0.10, blue: 0.08)
        case .phosphorGreen: return Color(red: 0.2, green: 1.0, blue: 0.3)
        case .darkNeon: return Color(red: 0.2, green: 0.85, blue: 1.0)
        }
    }
}

public struct HellschreiberView: View {
    @ObservedObject var engine: HellschreiberEngine
    @AppStorage("hellTapeTheme") private var tapeThemeRaw = HellTapeTheme.agedPaper.rawValue

    private var theme: HellTapeTheme {
        HellTapeTheme(rawValue: tapeThemeRaw) ?? .agedPaper
    }

    public init(engine: HellschreiberEngine) {
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

            // 2. Vintage Moving Paper Ticker Tape (Dual-Line Trace)
            tickerTapePanel
                .frame(minHeight: 220)
                .background(theme.paperColor)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 6)

            // 3. Fine-Calibration Ribbon (Slant, Contrast, Squelch)
            calibrationRibbon
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)

            // 4. Type-Ahead TX & Macro Controls
            txControlBay
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
                    Text(engine.isListening ? "STOP HELL" : "START HELL")
                        .font(.caption.bold())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(engine.isListening ? .red : .green)

            // Tone Frequency Control
            HStack(spacing: 4) {
                Text("TONE:")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                Text("\(Int(engine.centerFrequencyHz)) Hz")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .frame(width: 52)
            }

            // VU Meter
            ProgressView(value: Double(engine.audioInputLevel), total: 1.0)
                .frame(width: 60)
                .tint(.green)

            Divider().frame(height: 20)

            // Tape Theme Selector
            Menu {
                ForEach(HellTapeTheme.allCases) { t in
                    Button(t.rawValue) {
                        tapeThemeRaw = t.rawValue
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "paintpalette.fill")
                    Text(theme.rawValue)
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)

            Spacer()

            // Simulation Button
            Button {
                engine.toggleSimulation()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: engine.isSimulationActive ? "bolt.fill" : "bolt")
                        .foregroundColor(engine.isSimulationActive ? .yellow : .secondary)
                    Text(engine.isSimulationActive ? "SIM ON" : "Practice Tape")
                        .font(.caption2.bold())
                }
            }
            .buttonStyle(.bordered)
            .tint(engine.isSimulationActive ? .yellow : .secondary)

            // Clear Button
            Button {
                engine.clearTape()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - 2. Vintage Moving Paper Ticker Tape Canvas

    private var tickerTapePanel: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Paper Texture / Background
                theme.paperColor

                // Dual-Line Column Canvas
                Canvas { context, size in
                    drawDualTraceTape(context: context, size: size, theme: theme)
                }

                // Ribbon Perforations / Guidelines
                VStack {
                    Divider().opacity(0.15)
                    Spacer()
                    // Center separator guide line between top and bottom duplicate text traces
                    Rectangle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 1)
                    Spacer()
                    Divider().opacity(0.15)
                }

                // Vintage Tape Header Badge
                HStack {
                    Text("HELLSCHREIBER TAPE RECORDER · 245 PIXELS/SEC · DUAL-LINE")
                        .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                        .foregroundColor(theme.inkColor.opacity(0.4))
                        .padding(6)
                    Spacer()
                }
            }
        }
    }

    private func drawDualTraceTape(context: GraphicsContext, size: CGSize, theme: HellTapeTheme) {
        let cols = engine.columns
        guard !cols.isEmpty else { return }

        // We render from right to left as a moving tape
        let colWidth: CGFloat = 2.4
        let pixelHeight: CGFloat = size.height / 32.0 // 14 pixels top line + 4 gap + 14 pixels bottom line

        let totalColsVisible = Int(size.width / colWidth)
        let startIndex = max(0, cols.count - totalColsVisible)
        let visibleCols = cols[startIndex..<cols.count]

        for (i, col) in visibleCols.enumerated() {
            let x = size.width - CGFloat(visibleCols.count - i) * colWidth

            for (row, val) in col.pixels.enumerated() {
                guard val > 0.05 else { continue }
                let alpha = Double(min(1.0, val))

                // Trace 1: Upper duplicate line
                let y1 = CGFloat(row + 1) * pixelHeight
                let rect1 = CGRect(x: x, y: y1, width: colWidth + 0.3, height: pixelHeight + 0.3)
                context.fill(Path(rect1), with: .color(theme.inkColor.opacity(alpha)))

                // Trace 2: Lower duplicate line (classic Hellschreiber anti-skew redundancy)
                let y2 = CGFloat(row + 17) * pixelHeight
                let rect2 = CGRect(x: x, y: y2, width: colWidth + 0.3, height: pixelHeight + 0.3)
                context.fill(Path(rect2), with: .color(theme.inkColor.opacity(alpha)))
            }
        }
    }

    // MARK: - 3. Fine-Calibration Ribbon

    private var calibrationRibbon: some View {
        HStack(spacing: 16) {
            // Slant Adjustment
            HStack(spacing: 6) {
                Text("SLANT / SPEED:")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                Button {
                    engine.setSlant(engine.slantCorrectionPct - 0.2)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.caption2)
                }
                .buttonStyle(.plain)

                Slider(value: Binding(
                    get: { engine.slantCorrectionPct },
                    set: { engine.setSlant($0) }
                ), in: -5.0...5.0)
                .frame(width: 90)

                Button {
                    engine.setSlant(engine.slantCorrectionPct + 0.2)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                }
                .buttonStyle(.plain)

                Text(String(format: "%+0.1f%%", engine.slantCorrectionPct))
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .frame(width: 44)
            }

            Divider().frame(height: 16)

            // Contrast
            HStack(spacing: 6) {
                Text("CONTRAST:")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                Slider(value: $engine.tapeContrast, in: 0.5...3.0)
                    .frame(width: 70)
            }

            Divider().frame(height: 16)

            // Squelch
            HStack(spacing: 6) {
                Text("SQUELCH:")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)

                Slider(value: $engine.squelchLevel, in: 0.01...0.25)
                    .frame(width: 70)
            }

            Spacer()

            Button("Reset Slant") {
                engine.setSlant(0.0)
            }
            .font(.system(size: 9))
            .buttonStyle(.bordered)
        }
    }

    // MARK: - 4. TX Controls & 1-Click Logging

    private var txControlBay: some View {
        VStack(spacing: 6) {
            // Quick Macros
            HStack(spacing: 6) {
                macroBtn("CQ", text: "CQ CQ DE \(engine.myCallsign) \(engine.myCallsign) K ")
                macroBtn("Exch", text: "\(engine.targetCallsign.isEmpty ? "DX" : engine.targetCallsign) 599 001 BK ")
                macroBtn("73", text: "73 GL DE \(engine.myCallsign) SK ")
                macroBtn("MyCall", text: "\(engine.myCallsign) ")

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
            }

            if !engine.txRefusal.isEmpty {
                Text(engine.txRefusal)
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            // TX Buffer Input
            HStack(spacing: 8) {
                TextField("Type message and press Enter to transmit in Feld Hell...", text: $engine.txBufferText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5, design: .monospaced))
                    .onSubmit {
                        engine.startTransmission()
                    }

                Button {
                    if engine.isTransmitting {
                        engine.stopTransmission()
                    } else {
                        engine.startTransmission()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: engine.isTransmitting ? "stop.fill" : "paperplane.fill")
                        Text(engine.isTransmitting ? "ABORT" : "SEND")
                            .font(.caption.bold())
                    }
                    .frame(width: 80)
                }
                .buttonStyle(.borderedProminent)
                .tint(engine.isTransmitting ? .red : .orange)
            }
        }
    }

    private func macroBtn(_ label: String, text: @autoclosure @escaping () -> String) -> some View {
        Button(label) {
            engine.queueTextForTransmission(text())
        }
        .buttonStyle(.bordered)
        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
    }
}
