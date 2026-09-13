//
//  RTTYCrossedEllipsesScopeView.swift
//  YAAM
//
//  Iconic CRT Lissajous Crossed-Ellipses Oscilloscope for RTTY & PSK31
//  Renders authentic phosphor glow, concentric reticle grid, and real-time
//  Mark/Space orthogonal deflection as seen in MMTTY and HAL hardware terminal units.
//

import AppKit
import SwiftUI

public enum ScopeTheme: String, CaseIterable, Identifiable, Sendable {
    case phosphorGreen = "Phosphor Green"
    case electricCyan = "Electric Cyan"
    case retroAmber = "Retro Amber"

    public var id: String { rawValue }

    public var beamColor: Color {
        switch self {
        case .phosphorGreen: return Color(red: 0.2, green: 1.0, blue: 0.3)
        case .electricCyan: return Color(red: 0.1, green: 0.9, blue: 1.0)
        case .retroAmber: return Color(red: 1.0, green: 0.72, blue: 0.1)
        }
    }

    public var glowColor: Color {
        switch self {
        case .phosphorGreen: return Color(red: 0.0, green: 0.8, blue: 0.2).opacity(0.35)
        case .electricCyan: return Color(red: 0.0, green: 0.6, blue: 0.9).opacity(0.35)
        case .retroAmber: return Color(red: 0.9, green: 0.5, blue: 0.0).opacity(0.35)
        }
    }

    public var gridColor: Color {
        switch self {
        case .phosphorGreen: return Color(red: 0.1, green: 0.4, blue: 0.2).opacity(0.4)
        case .electricCyan: return Color(red: 0.1, green: 0.3, blue: 0.5).opacity(0.4)
        case .retroAmber: return Color(red: 0.5, green: 0.35, blue: 0.1).opacity(0.4)
        }
    }
}

public struct RTTYCrossedEllipsesScopeView: View {
    @ObservedObject var engine: DigitalModemEngine
    @AppStorage("rttyScopeTheme") private var scopeThemeRaw = ScopeTheme.phosphorGreen.rawValue

    private var theme: ScopeTheme {
        ScopeTheme(rawValue: scopeThemeRaw) ?? .phosphorGreen
    }

    public init(engine: DigitalModemEngine) {
        self.engine = engine
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Header / Legend Bar
            HStack {
                Label(engine.operatingMode.isRTTY ? "CROSSED-ELLIPSES SCOPE" : "PHASE CONSTELLATION", systemImage: "circle.grid.cross")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundColor(theme.beamColor)

                Spacer()

                // Mode / Status Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusIndicatorColor)
                        .frame(width: 6, height: 6)
                    Text(tuningStatusText)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Theme Switcher Menu
                Menu {
                    ForEach(ScopeTheme.allCases) { t in
                        Button(t.rawValue) {
                            scopeThemeRaw = t.rawValue
                        }
                    }
                } label: {
                    Image(systemName: "paintpalette.fill")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            // CRT Oscilloscope Bezel and Canvas
            ZStack {
                // Bezel outer gradient
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.12), Color(white: 0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(white: 0.22), lineWidth: 1.5)
                    )

                // Inner CRT Screen
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.02, green: 0.03, blue: 0.04))
                    .padding(5)
                    .shadow(color: theme.glowColor, radius: 10)

                // CRT Phosphor Trajectory Canvas
                Canvas { context, size in
                    drawReticleGrid(context: context, size: size, theme: theme)

                    if engine.operatingMode.isRTTY {
                        drawRTTYLissajous(context: context, size: size, theme: theme)
                    } else {
                        drawPSKConstellation(context: context, size: size, theme: theme)
                    }
                }
                .padding(8)

                // Glass Curved Highlight Overlay
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.06), Color.clear, Color.black.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(5)
                    .allowsHitTesting(false)

                // Mark & Space Axis Labels
                if engine.operatingMode.isRTTY {
                    VStack {
                        Text("MARK (Y)")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundColor(theme.beamColor.opacity(0.6))
                            .padding(.top, 10)
                        Spacer()
                        HStack {
                            Text("SPACE (X)")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(theme.beamColor.opacity(0.6))
                                .padding(.leading, 12)
                            Spacer()
                        }
                        .padding(.bottom, 10)
                    }
                }
            }
            .frame(minWidth: 170, minHeight: 170)
        }
    }

    private var statusIndicatorColor: Color {
        if engine.audioInputLevel < 0.02 { return .secondary }
        if engine.signalToNoiseRatioDb > 10.0 { return .green }
        return .yellow
    }

    private var tuningStatusText: String {
        if engine.audioInputLevel < 0.02 { return "NO SIGNAL" }
        if engine.afcEnabled && abs(engine.afcOffsetHz) < 5.0 && engine.signalToNoiseRatioDb > 8.0 {
            return "ON TUNE (AFC)"
        }
        if engine.signalToNoiseRatioDb > 6.0 {
            return "LOCKED"
        }
        return "SEARCHING"
    }

    // MARK: - Canvas Rendering Methods

    private func drawReticleGrid(context: GraphicsContext, size: CGSize, theme: ScopeTheme) {
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        let radius = min(size.width, size.height) * 0.44

        // Concentric Reticle Rings
        for ratio in [0.33, 0.66, 1.0] {
            let r = radius * CGFloat(ratio)
            let circleRect = CGRect(x: center.x - r, y: center.y - r, width: r * 2.0, height: r * 2.0)
            context.stroke(Path(ellipseIn: circleRect), with: .color(theme.gridColor), lineWidth: 0.8)
        }

        // Crosshairs
        var xHair = Path()
        xHair.move(to: CGPoint(x: center.x - radius, y: center.y))
        xHair.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        xHair.move(to: CGPoint(x: center.x, y: center.y - radius))
        xHair.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        context.stroke(xHair, with: .color(theme.gridColor), style: StrokeStyle(lineWidth: 1.0, dash: [4, 4]))

        // 45-degree angle diagonal guides
        let diag = radius * 0.7071
        var diagPath = Path()
        diagPath.move(to: CGPoint(x: center.x - diag, y: center.y - diag))
        diagPath.addLine(to: CGPoint(x: center.x + diag, y: center.y + diag))
        diagPath.move(to: CGPoint(x: center.x - diag, y: center.y + diag))
        diagPath.addLine(to: CGPoint(x: center.x + diag, y: center.y - diag))
        context.stroke(diagPath, with: .color(theme.gridColor.opacity(0.5)), style: StrokeStyle(lineWidth: 0.6, dash: [2, 4]))
    }

    private func drawRTTYLissajous(context: GraphicsContext, size: CGSize, theme: ScopeTheme) {
        let samples = engine.scopeSamples
        guard !samples.isEmpty else { return }

        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        let scale = min(size.width, size.height) * 0.40
        guard scale > 0 else { return }

        // Phosphor Glow Background Layer
        var glowPath = Path()
        var tracePath = Path()
        var hasStarted = false

        for pt in samples {
            guard pt.x.isFinite && pt.y.isFinite else { continue }
            let px = center.x + CGFloat(pt.x) * scale
            let py = center.y - CGFloat(pt.y) * scale // Inverted for CRT screen coordinates

            let p = CGPoint(x: px, y: py)
            if !hasStarted {
                glowPath.move(to: p)
                tracePath.move(to: p)
                hasStarted = true
            } else {
                glowPath.addLine(to: p)
                tracePath.addLine(to: p)
            }
        }

        guard hasStarted else { return }

        // Draw outer phosphor bloom
        context.stroke(glowPath, with: .color(theme.glowColor), lineWidth: 4.5)
        // Draw crisp electron beam core
        context.stroke(tracePath, with: .color(theme.beamColor), lineWidth: 1.6)

        // Draw intensity points at endpoints
        for pt in samples {
            guard pt.x.isFinite && pt.y.isFinite else { continue }
            let px = center.x + CGFloat(pt.x) * scale
            let py = center.y - CGFloat(pt.y) * scale
            let dotRect = CGRect(x: px - 1.2, y: py - 1.2, width: 2.4, height: 2.4)
            context.fill(Path(ellipseIn: dotRect), with: .color(Color.white.opacity(0.7)))
        }
    }

    private func drawPSKConstellation(context: GraphicsContext, size: CGSize, theme: ScopeTheme) {
        let points = engine.constellationPoints
        let center = CGPoint(x: size.width / 2.0, y: size.height / 2.0)
        let scale = min(size.width, size.height) * 0.35
        guard scale > 0 else { return }

        for pt in points {
            guard pt.x.isFinite && pt.y.isFinite else { continue }
            let px = center.x + CGFloat(pt.x) * scale
            let py = center.y - CGFloat(pt.y) * scale
            let rect = CGRect(x: px - 2.5, y: py - 2.5, width: 5.0, height: 5.0)

            context.fill(Path(ellipseIn: rect), with: .color(theme.glowColor))
            context.fill(Path(ellipseIn: CGRect(x: px - 1.2, y: py - 1.2, width: 2.4, height: 2.4)), with: .color(theme.beamColor))
        }

        // Draw horizontal binary phase markers at -scale and +scale
        let leftPole = CGPoint(x: center.x - scale * 0.85, y: center.y)
        let rightPole = CGPoint(x: center.x + scale * 0.85, y: center.y)

        context.stroke(Path(ellipseIn: CGRect(x: leftPole.x - 6, y: leftPole.y - 6, width: 12, height: 12)), with: .color(theme.beamColor.opacity(0.4)), lineWidth: 1.0)
        context.stroke(Path(ellipseIn: CGRect(x: rightPole.x - 6, y: rightPole.y - 6, width: 12, height: 12)), with: .color(theme.beamColor.opacity(0.4)), lineWidth: 1.0)
    }
}
