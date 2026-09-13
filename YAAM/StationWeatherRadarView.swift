//
//  StationWeatherRadarView.swift
//  YAAM
//
//  Station Weather & Antenna Safety Radar HUD & Popover
//  Provides real-time visualization of terrestrial weather, lightning threats,
//  precipitation static (P-static) coax arcing risks, wind load strain, and
//  a 24-hour tactical safety horizon for the radio operator.
//

import AppKit
import SwiftUI

// MARK: - Global HUD Pill (Window Header Widget)

public struct StationWeatherPillView: View {
    @ObservedObject private var engine = StationWeatherSafetyEngine.shared
    @State private var isPresented = false
    @State private var isHovered = false
    @State private var pulseAnimation = false

    public init() {}

    public var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                // Condition Icon & Temperature
                if let current = engine.currentTelemetry {
                    Image(systemName: current.conditionIcon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(iconColor(for: current))

                    Text("\(Int(current.temperature.rounded()))°C")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    // Wind / Gust indicator
                    HStack(spacing: 2) {
                        Image(systemName: "wind")
                            .font(.system(size: 9))
                        Text("\(Int(current.windGusts.rounded()))")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)

                    Divider()
                        .frame(height: 12)

                    // Threat Status Pill
                    HStack(spacing: 4) {
                        Circle()
                            .fill(engine.threatLevel.color)
                            .frame(width: 7, height: 7)
                            .scaleEffect(engine.threatLevel == .critical && pulseAnimation ? 1.4 : 1.0)
                            .opacity(engine.threatLevel == .critical && pulseAnimation ? 0.6 : 1.0)

                        Text(engine.threatLevel == .critical ? "⚡️ UNPLUG COAX" : engine.threatLevel.rawValue.uppercased())
                            .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(engine.threatLevel == .critical ? Color.red : engine.threatLevel.color)
                    }
                } else if engine.isFetching {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Weather...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "cloud.sun")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(engine.resolvedGrid.isEmpty ? "Radar" : engine.resolvedGrid)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: engine.threatLevel == .critical ? 1.5 : 0.8)
            )
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
        .help("Station Weather & Antenna Safety Radar: Click to view lightning, P-static, and wind threats.")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            StationWeatherRadarPopoverView(isPresented: $isPresented)
        }
        .onAppear {
            if engine.threatLevel == .critical {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            }
        }
        .onChange(of: engine.threatLevel) { _, newLevel in
            if newLevel == .critical {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
            } else {
                pulseAnimation = false
            }
        }
    }

    private var backgroundColor: Color {
        switch engine.threatLevel {
        case .critical:
            return Color.red.opacity(0.18)
        case .warning:
            return Color.orange.opacity(0.14)
        case .elevated:
            return Color.yellow.opacity(0.12)
        case .safe:
            return Color(NSColor.controlBackgroundColor).opacity(0.85)
        }
    }

    private var borderColor: Color {
        switch engine.threatLevel {
        case .critical:
            return Color.red.opacity(0.7)
        case .warning:
            return Color.orange.opacity(0.6)
        case .elevated:
            return Color.yellow.opacity(0.5)
        case .safe:
            return Color(NSColor.separatorColor).opacity(0.5)
        }
    }

    private func iconColor(for telemetry: WeatherTelemetry) -> Color {
        if telemetry.isThunderstorm { return .red }
        if telemetry.isHeavyRain { return .blue }
        if telemetry.windGusts >= engine.highWindThreshold { return .orange }
        return .cyan
    }
}

// MARK: - Station Weather & Antenna Safety Radar Popover

public struct StationWeatherRadarPopoverView: View {
    @ObservedObject private var engine = StationWeatherSafetyEngine.shared
    @Binding var isPresented: Bool
    @State private var selectedTab = 0 // 0: Live Radar & Threat, 1: 24h Horizon, 2: Safety Checklist

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    tacticalHeroBanner

                    if engine.threatLevel != .safe {
                        emergencyChecklistCard
                    }

                    telemetryMetricsGrid

                    windRotatorCompassCard

                    twentyFourHourHorizonCard
                }
                .padding(16)
            }
            .frame(maxHeight: 520)

            Divider()
            footerBar
        }
        .frame(width: 460)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.accentColor)

                    Text("Antenna Safety & Weather Radar")
                        .font(.system(size: 13, weight: .bold))
                }

                HStack(spacing: 6) {
                    Text("QTH Locator:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text(engine.resolvedGrid)
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)

                    if let coords = engine.resolvedCoordinates {
                        Text(String(format: "(%.3f°, %.3f°)", coords.lat, coords.lon))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button {
                Task {
                    await engine.refresh()
                }
            } label: {
                if engine.isFetching {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .focusable(false)
            .focusEffectDisabled()
            .disabled(engine.isFetching)
            .help("Refresh live weather telemetry now")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
    }

    // MARK: - Tactical Hero Threat Banner

    private var tacticalHeroBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: engine.threatLevel.badgeIcon)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(engine.threatLevel.color)
                .frame(width: 36, height: 36)
                .background(engine.threatLevel.color.opacity(0.18), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("THREAT LEVEL: \(engine.threatLevel.rawValue.uppercased())")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(engine.threatLevel.color)

                    Spacer()

                    if let current = engine.currentTelemetry {
                        Text(current.conditionDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(engine.threatLevel.tacticalAction)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(engine.threatLevel.color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(engine.threatLevel.color.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Emergency Operator Checklist

    private var emergencyChecklistCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Emergency Antenna Protection Checklist", systemImage: "checklist.checked")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(Color.red)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                checklistRow(
                    title: "Disconnect Coax Feedlines from Transceivers",
                    subtitle: "Prevents high-voltage ESD arcing into receiver front-end diodes/FETs.",
                    isChecked: $engine.checklistCoaxDisconnected
                )

                checklistRow(
                    title: "Connect Antennas to Ground / Lightning Arrestor",
                    subtitle: "Safely bleeds precipitation static buildup to earth ground.",
                    isChecked: $engine.checklistGrounded
                )

                checklistRow(
                    title: "Power Off & Unplug High-Voltage Linear Amplifiers",
                    subtitle: "Eliminates inductive surge damage via AC mains or feedline.",
                    isChecked: $engine.checklistPowerOff
                )

                checklistRow(
                    title: "Park Rotator into Wind Heading (\(engine.recommendedRotatorHeading)°)",
                    subtitle: "Feathers Yagi elements parallel to gusts to reduce mechanical boom torque.",
                    isChecked: $engine.checklistRotatorParked
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }

    private func checklistRow(title: String, subtitle: String, isChecked: Binding<Bool>) -> some View {
        Button {
            isChecked.wrappedValue.toggle()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isChecked.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundStyle(isChecked.wrappedValue ? Color.green : Color.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isChecked.wrappedValue ? Color.secondary : Color.primary)
                        .strikethrough(isChecked.wrappedValue)

                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .focusEffectDisabled()
    }

    // MARK: - 4 Telemetry Metrics Grid

    private var telemetryMetricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            // 1. Lightning & ESD Static Threat
            metricCard(
                icon: "bolt.fill",
                title: "Lightning & ESD Risk",
                value: engine.currentTelemetry?.isThunderstorm == true ? "ACTIVE THREAT" : (engine.threatLevel == .critical ? "HIGH RISK" : "NOMINAL"),
                badgeText: engine.currentTelemetry?.isThunderstorm == true ? "WMO 95+" : "Clear",
                statusColor: engine.currentTelemetry?.isThunderstorm == true ? .red : (engine.threatLevel == .critical ? .orange : .green),
                footer: engine.pStaticRisk.advice
            )

            // 2. Wind Load & Tower Strain
            let gusts = Int(engine.currentTelemetry?.windGusts.rounded() ?? 0)
            let speed = Int(engine.currentTelemetry?.windSpeed.rounded() ?? 0)
            metricCard(
                icon: "wind",
                title: "Wind & Peak Gusts",
                value: "\(speed) km/h (Gust \(gusts))",
                badgeText: engine.windThreat.rawValue,
                statusColor: engine.windThreat.color,
                footer: engine.windThreat.advice
            )

            // 3. Precipitation & P-Static
            let rain = String(format: "%.1f mm/h", engine.currentTelemetry?.precipitation ?? 0.0)
            metricCard(
                icon: "cloud.rain.fill",
                title: "Rain & P-Static",
                value: rain,
                badgeText: engine.pStaticRisk.rawValue,
                statusColor: engine.pStaticRisk.color,
                footer: "Static build-up on dry or wet elements elevates noise floor."
            )

            // 4. VHF/UHF Tropospheric Ducting
            let pressure = Int(engine.currentTelemetry?.surfacePressure.rounded() ?? 1013)
            metricCard(
                icon: "waveform.badge.magnifyingglass",
                title: "VHF/UHF Tropo Ducting",
                value: "\(pressure) hPa",
                badgeText: engine.tropoIndex.rawValue,
                statusColor: engine.tropoIndex.color,
                footer: engine.tropoIndex.detail
            )
        }
    }

    private func metricCard(
        icon: String,
        title: String,
        value: String,
        badgeText: String,
        statusColor: Color,
        footer: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(statusColor)

                Text(title)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(badgeText)
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(statusColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            Text(value)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)

            Text(footer)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 0.8)
        )
    }

    // MARK: - Wind Rotator Compass & Feathering Guide

    private var windRotatorCompassCard: some View {
        HStack(spacing: 14) {
            // Mini Compass Indicator
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1.5)
                    .frame(width: 44, height: 44)

                // Compass Cardinal points
                Text("N")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(.secondary)
                    .offset(y: -16)

                // Wind Direction Needle
                let dir = engine.currentTelemetry?.windDirection ?? 0.0
                Image(systemName: "location.north.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.orange)
                    .rotationEffect(.degrees(dir))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Yagi Rotator Feathering Heading:")
                        .font(.system(size: 11, weight: .bold))
                    Spacer()
                    Text("\(engine.recommendedRotatorHeading)°")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                }

                Text("Pointing your beam into \(engine.recommendedRotatorHeading)° minimizes frontal wind cross-section and element vibration during high gusts.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(0.25), lineWidth: 0.8)
        )
    }

    // MARK: - 24-Hour Threat Horizon

    private var twentyFourHourHorizonCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("24-Hour Threat Horizon", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Upcoming Safety Forecast")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if engine.hourlyForecast.isEmpty {
                Text("No hourly forecast available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(engine.hourlyForecast) { item in
                            hourlyBadge(item)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 0.8)
        )
    }

    private func hourlyBadge(_ item: HourlyThreatForecast) -> some View {
        VStack(spacing: 4) {
            Text(item.hourFormatted)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            Image(systemName: item.conditionIcon)
                .font(.system(size: 13))
                .foregroundStyle(item.threatLevel.color)
                .frame(height: 16)

            Text("\(Int(item.temperature.rounded()))°")
                .font(.system(size: 10, weight: .bold, design: .rounded))

            HStack(spacing: 1.5) {
                Image(systemName: "wind")
                    .font(.system(size: 7))
                Text("\(Int(item.windGusts.rounded()))")
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(.secondary)

            // Threat Dot
            Circle()
                .fill(item.threatLevel.color)
                .frame(width: 5, height: 5)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(item.threatLevel.color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(item.threatLevel.color.opacity(0.25), lineWidth: 0.6)
        )
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            if let updated = engine.lastUpdated {
                Text("Updated \(timeAgo(from: updated)) via Open-Meteo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let error = engine.fetchError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Color.red)
            }

            Spacer()

            Button("Close") {
                isPresented = false
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }
}
