//
//  OnTheAirRadarView.swift
//  YAAM
//
//  Interactive On-The-Air Telemetry Radar & Live Signal HUD
//  Renders a compact glowing on-air status pill (guaranteed single-line)
//  and an expansive, legible, and unclipped interactive signal HUD popover.
//

import AppKit
import SwiftUI

// MARK: - Live On-The-Air Toolbar Pill Component (Single-Line & Responsive)

public struct OnTheAirPillView: View {
    @ObservedObject var service = OnTheAirMonitorService.shared
    @State private var showHUDPopover = false
    @State private var isPulsing = false

    public init() {}

    public var body: some View {
        Button {
            showHUDPopover.toggle()
        } label: {
            HStack(spacing: 5) {
                // Pulsating radar beacon dot
                ZStack {
                    if service.state.isOnAir {
                        Circle()
                            .fill(Color.green.opacity(isPulsing ? 0.6 : 0.2))
                            .frame(width: 12, height: 12)
                            .scaleEffect(isPulsing ? 1.25 : 0.85)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: isPulsing)

                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                    } else if service.isPolling {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 10, height: 10)
                    } else {
                        Circle()
                            .fill(Color.secondary.opacity(0.4))
                            .frame(width: 7, height: 7)
                    }
                }
                .frame(width: 12, height: 12)
                .onAppear { isPulsing = true }

                // Text badge - Strictly single-line to prevent vertical wrapping in crowded toolbar
                Group {
                    if case let .active(spotCount, _, _, _, _) = service.state {
                        HStack(spacing: 4) {
                            Text("ON AIR")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(Color.green)

                            Text("(\(spotCount))")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.22), in: Capsule())
                                .foregroundStyle(Color.green)
                        }
                    } else if service.isPolling {
                        Text("Querying...")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Standby")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                service.state.isOnAir ?
                Color.green.opacity(0.12) :
                Color(nsColor: .controlBackgroundColor).opacity(0.6),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(service.state.isOnAir ? Color.green.opacity(0.45) : Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1)
            )
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .help(tooltipText)
        .popover(isPresented: $showHUDPopover, arrowEdge: .bottom) {
            OnTheAirHUDPopoverView(service: service)
        }
    }

    private var tooltipText: String {
        switch service.state {
        case let .active(spotCount, furthestKm, furthestCall, bestSNR, activeBands):
            var text = "\(spotCount) live PSK reception reports in last 15m.\n"
            if let furthestCall, let furthestKm {
                text += "Furthest DX: \(furthestCall) (\(Int(furthestKm)) km)\n"
            }
            if let bestSNR {
                text += "Best SNR: \(bestSNR) dB\n"
            }
            if !activeBands.isEmpty {
                text += "Active Bands: \(activeBands.joined(separator: ", "))\n"
            }
            text += "Click to view full Signal HUD."
            return text
        case .standby:
            return "No signals heard in last 15 minutes. Next poll in \(service.countdownSeconds)s."
        case .disabled:
            return "Station callsign not configured."
        }
    }
}

// MARK: - Interactive Signal HUD Popover View (Spacious & Non-Clipping)

public struct OnTheAirHUDPopoverView: View {
    @ObservedObject var service: OnTheAirMonitorService
    @AppStorage("onAirSoundAlerts") private var soundAlertsEnabled = true
    @AppStorage("onAirVoiceAlerts") private var voiceAlertsEnabled = false

    private var personalPSKMapURL: URL {
        let call = service.currentCallsign.isEmpty ? "EP2AES" : service.currentCallsign
        return URL(string: "https://pskreporter.info/pskmap.html?preset&callsign=\(call)&timerange=900")!
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Station Callsign & Live Telemetry State
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(service.state.isOnAir ? Color.green.opacity(0.16) : Color.secondary.opacity(0.12))
                    Image(systemName: service.state.isOnAir ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(service.state.isOnAir ? Color.green : Color.secondary)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(service.currentCallsign.isEmpty ? "No Callsign" : service.currentCallsign)
                            .font(.headline.monospaced().weight(.bold))

                        if service.state.isOnAir {
                            Text("LIVE ON AIR")
                                .font(.system(size: 9, weight: .heavy))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2), in: Capsule())
                                .foregroundStyle(Color.green)
                        } else {
                            Text("STANDBY")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Home Grid: \(service.homeGrid) · 15-Minute PSK Reporter Telemetry")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button {
                    service.refreshNow()
                } label: {
                    HStack(spacing: 4) {
                        if service.isPolling {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh (\(service.countdownSeconds)s)")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(service.isPolling)
            }

            Divider()

            // Key Metrics Cards
            HStack(spacing: 10) {
                hudMetricCard(
                    title: "Live Spots (15m)",
                    value: "\(service.spots.count)",
                    unit: "stations",
                    icon: "dot.radiowaves.left.and.right",
                    color: service.spots.isEmpty ? .secondary : .green
                )

                hudMetricCard(
                    title: "Best SNR",
                    value: service.spots.compactMap(\.snr).max().map { "\($0 > 0 ? "+\($0)" : "\($0)") dB" } ?? "-",
                    unit: "",
                    icon: "waveform.path.ecg",
                    color: .mint
                )

                let maxDX = service.spots.max { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) }
                hudMetricCard(
                    title: "Furthest Listener (DX)",
                    value: maxDX?.distanceKm.map { "\(Int($0)) km" } ?? "-",
                    unit: maxDX?.listenerCall ?? "",
                    icon: "globe.americas.fill",
                    color: .orange
                )
            }

            // Active Bands Breakdown
            if !service.spots.isEmpty {
                let bands = Array(Set(service.spots.map(\.band))).sorted()
                HStack(spacing: 6) {
                    Text("ACTIVE BANDS:")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)

                    ForEach(bands, id: \.self) { band in
                        let count = service.spots.filter { $0.band == band }.count
                        HStack(spacing: 3) {
                            Text(band)
                                .font(.caption2.weight(.bold))
                            Text("(\(count))")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(.blue)
                    }
                }
            }

            // Live Spots List Table
            if service.spots.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No signal reports for \(service.currentCallsign) in the last 15 minutes.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text("Transmit CQ on FT8/CW to see live global listeners appear here automatically.")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Text("LISTENER (RX)")
                            .frame(width: 125, alignment: .leading)
                        Text("BAND / MODE")
                            .frame(width: 90, alignment: .leading)
                        Text("SNR")
                            .frame(width: 65, alignment: .leading)
                        Text("DISTANCE")
                            .frame(width: 90, alignment: .leading)
                        Text("BEARING")
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Text("AGE")
                            .frame(width: 60, alignment: .trailing)
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .separatorColor).opacity(0.12))

                    Divider()

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(service.spots.prefix(12))) { spot in
                                HStack(spacing: 0) {
                                    HStack(spacing: 5) {
                                        Text(spot.countryFlag)
                                            .font(.caption)
                                        Text(spot.listenerCall)
                                            .font(.caption.monospaced().weight(.semibold))
                                            .lineLimit(1)
                                    }
                                    .frame(width: 125, alignment: .leading)

                                    HStack(spacing: 4) {
                                        Text(spot.band)
                                            .font(.caption2.bold())
                                            .foregroundStyle(.blue)
                                        Text(spot.mode)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 90, alignment: .leading)

                                    Text(spot.snrText)
                                        .font(.caption2.monospacedDigit().weight(.bold))
                                        .foregroundStyle(spot.snrColor)
                                        .frame(width: 65, alignment: .leading)

                                    Text(spot.distanceKm.map { "\(Int($0)) km" } ?? "-")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.primary)
                                        .frame(width: 90, alignment: .leading)

                                    Text(spot.bearingCompass.map { "\(spot.bearingDeg.map { "\(Int($0))°" } ?? "") \($0)" } ?? "-")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 80, alignment: .leading)

                                    Spacer()

                                    Text(spot.ageText)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 60, alignment: .trailing)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)

                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor).opacity(0.25), lineWidth: 1))
            }

            // Bottom Actions & External Map Launcher
            HStack {
                Link(destination: personalPSKMapURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "map.fill")
                        Text("Open My Live PSKMap")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.blue)

                Spacer()

                Toggle("Audio Chime", isOn: $soundAlertsEnabled)
                    .font(.caption2)
                    .toggleStyle(.checkbox)

                Toggle("Voice Speech", isOn: $voiceAlertsEnabled)
                    .font(.caption2)
                    .toggleStyle(.checkbox)
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(minWidth: 560, idealWidth: 590, minHeight: 380, maxHeight: 460)
    }

    private func hudMetricCard(title: String, value: String, unit: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.caption)
                Spacer()
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.subheadline, design: .rounded).monospacedDigit().weight(.bold))
                    .foregroundStyle(.primary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9).bold())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.25), lineWidth: 1))
    }
}
