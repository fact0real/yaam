//
//  DigitalAudioWaterfallView.swift
//  YAAM
//
//  Real-Time Audio Spectrum Waterfall & Click-To-Tune Display for Digital Modes
//  Spans 300 Hz to 3200 Hz with dual Mark/Space tuning cursors, shift bracket,
//  AFC lock indicator corridor, and click-to-tune functionality.
//

import AppKit
import SwiftUI

public struct DigitalAudioWaterfallView: View {
    @ObservedObject var engine: DigitalModemEngine

    // Waterfall historical buffer (60 rows)
    @State private var waterfallHistory: [[Float]] = []
    private let minFrequency: Double = 300.0
    private let maxFrequency: Double = 3200.0

    public init(engine: DigitalModemEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(spacing: 4) {
            // Header Bar
            HStack {
                Label("AUDIO WATERFALL & SPECTRUM (300 - 3200 Hz)", systemImage: "waveform.path")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)

                Spacer()

                Text("CLICK WATERFALL TO TUNE")
                    .font(.system(size: 9.0, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.horizontal, 4)

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // 1. Background Waterfall Canvas
                    Canvas { context, size in
                        drawWaterfall(context: context, size: size)
                        drawSpectrumLine(context: context, size: size)
                        drawFrequencyScale(context: context, size: size)
                    }
                    .background(Color.black)
                    .cornerRadius(8)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                handleTuneTap(location: value.location, width: geo.size.width)
                            }
                    )

                    // 2. Interactive Tuning Overlay Cursors
                    tuningCursorsOverlay(size: geo.size)
                }
            }
            .frame(minHeight: 140)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(white: 0.2), lineWidth: 1)
            )
        }
        .onReceive(engine.$waterfallSpectrum) { newRow in
            guard engine.isListening || engine.isSimulationActive else { return }
            waterfallHistory.insert(newRow, at: 0)
            if waterfallHistory.count > 65 {
                waterfallHistory.removeLast()
            }
        }
    }

    // MARK: - Click to Tune

    private func handleTuneTap(location: CGPoint, width: CGFloat) {
        guard width > 0 else { return }
        let clampedX = max(0, min(width, location.x))
        let fraction = Double(clampedX / width)
        let targetFreq = minFrequency + fraction * (maxFrequency - minFrequency)
        engine.setCenterFrequency(targetFreq)
    }

    // MARK: - Waterfall Canvas Drawing

    private func drawWaterfall(context: GraphicsContext, size: CGSize) {
        guard !waterfallHistory.isEmpty, size.width > 0, size.height > 0 else { return }
        let rowCount = waterfallHistory.count
        let rowHeight = size.height / CGFloat(rowCount)

        for (r, row) in waterfallHistory.enumerated() {
            let binCount = row.count
            guard binCount > 0 else { continue }
            let binWidth = size.width / CGFloat(binCount)
            let y = CGFloat(r) * rowHeight

            for (b, val) in row.enumerated() {
                guard val.isFinite else { continue }
                let x = CGFloat(b) * binWidth
                let rect = CGRect(x: x, y: y, width: binWidth + 0.5, height: rowHeight + 0.5)
                context.fill(Path(rect), with: .color(colorForPower(val)))
            }
        }
    }

    private func drawSpectrumLine(context: GraphicsContext, size: CGSize) {
        let currentSpectrum = engine.waterfallSpectrum
        guard !currentSpectrum.isEmpty, size.width > 0, size.height > 0 else { return }

        var path = Path()
        let binWidth = size.width / CGFloat(currentSpectrum.count)
        let maxDisplayHeight = size.height * 0.45

        for (i, val) in currentSpectrum.enumerated() {
            let safeVal = val.isFinite ? max(0.0, min(1.0, val)) : 0.0
            let x = CGFloat(i) * binWidth + (binWidth * 0.5)
            let y = size.height - (CGFloat(safeVal) * maxDisplayHeight)

            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        context.stroke(path, with: .color(Color.cyan.opacity(0.85)), lineWidth: 1.2)
    }

    private func drawFrequencyScale(context: GraphicsContext, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let stepHz = 500.0
        var currentHz = 500.0

        while currentHz < maxFrequency {
            let fraction = (currentHz - minFrequency) / (maxFrequency - minFrequency)
            let x = CGFloat(fraction) * size.width

            // Grid Line
            var gridLine = Path()
            gridLine.move(to: CGPoint(x: x, y: 0))
            gridLine.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(gridLine, with: .color(Color.white.opacity(0.12)), style: StrokeStyle(lineWidth: 0.8, dash: [3, 4]))

            // Frequency Text
            let text = Text("\(Int(currentHz))")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.45))
            context.draw(text, at: CGPoint(x: x + 14, y: 10))

            currentHz += stepHz
        }
    }

    private func colorForPower(_ value: Float) -> Color {
        let v = min(1.0, max(0.0, value))
        if v < 0.15 {
            return Color(red: 0.02, green: 0.05, blue: Double(v * 2.0))
        } else if v < 0.45 {
            let t = Double((v - 0.15) / 0.30)
            return Color(red: 0.0, green: t * 0.8, blue: 0.9)
        } else if v < 0.75 {
            let t = Double((v - 0.45) / 0.30)
            return Color(red: t, green: 0.9, blue: 0.1)
        } else {
            let t = Double((v - 0.75) / 0.25)
            return Color(red: 1.0, green: 1.0 - t * 0.7, blue: 0.1)
        }
    }

    // MARK: - Overlay Tuning Cursors

    @ViewBuilder
    private func tuningCursorsOverlay(size: CGSize) -> some View {
        if size.width > 0 && size.height > 0 {
            let width = size.width
            let centerHz = engine.centerFrequencyHz
            let markHz = engine.effectiveMarkFrequency
            let spaceHz = engine.effectiveSpaceFrequency

            let centerX = CGFloat((centerHz - minFrequency) / (maxFrequency - minFrequency)) * width
            let markX = CGFloat((markHz - minFrequency) / (maxFrequency - minFrequency)) * width
            let spaceX = CGFloat((spaceHz - minFrequency) / (maxFrequency - minFrequency)) * width

            ZStack(alignment: .topLeading) {
            // AFC Corridor
            if engine.afcEnabled {
                let corridorWidth = CGFloat(80.0 / (maxFrequency - minFrequency)) * width
                Rectangle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: corridorWidth, height: size.height)
                    .position(x: centerX, y: size.height * 0.5)
            }

            if engine.operatingMode.isRTTY {
                // Mark Cursor Line (Green/Red)
                Rectangle()
                    .fill(Color.green)
                    .frame(width: 1.5, height: size.height)
                    .position(x: markX, y: size.height * 0.5)

                // Space Cursor Line (Yellow)
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: 1.5, height: size.height)
                    .position(x: spaceX, y: size.height * 0.5)

                // Horizontal Shift Bracket linking Mark and Space
                let minX = min(markX, spaceX)
                let maxX = max(markX, spaceX)
                let bracketW = max(1.0, maxX - minX)

                Rectangle()
                    .fill(Color.orange)
                    .frame(width: bracketW, height: 2.0)
                    .position(x: minX + bracketW * 0.5, y: 16)

                // Labels
                Text("M: \(Int(markHz))")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                    .background(Color.black.opacity(0.75))
                    .position(x: markX, y: 26)

                Text("S: \(Int(spaceHz))")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow)
                    .background(Color.black.opacity(0.75))
                    .position(x: spaceX, y: 26)
            } else {
                // PSK31 Center Cursor
                Rectangle()
                    .fill(Color.cyan)
                    .frame(width: 2.0, height: size.height)
                    .position(x: centerX, y: size.height * 0.5)

                Text("\(Int(centerHz)) Hz")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                    .background(Color.black.opacity(0.75))
                    .position(x: centerX, y: 24)
            }
        }
        }
    }
}
