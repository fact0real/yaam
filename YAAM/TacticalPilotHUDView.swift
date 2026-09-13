//
//  TacticalPilotHUDView.swift
//  YAAM
//
//  High-UX Tactical Pilot HUD (Heads-Up Display) for SDR-Control & WSJT-X / FT8 operations.
//  Provides real-time decode telemetry, apex DX target highlighting, automated priority scoring,
//  and 1-click band switching recommendations.
//

import AppKit
import SwiftUI

public struct TacticalPilotHUDView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var advisor = TacticalBandAdvisor.shared
    @ObservedObject private var roster = DigitalCallRosterEngine.shared
    @ObservedObject private var queue = DigitalTargetQueueEngine.shared
    @ObservedObject private var rig = RigControlEngine.shared

    @State private var isAutoPilotExpanded = false

    public init() {}

    private var activeBand: String {
        let band = appState.wsjtxListener.lastStatus?.band.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return band.isEmpty ? advisor.activeBand : band.uppercased()
    }

    public var body: some View {
        VStack(spacing: 10) {
            // 1. Top Telemetry & Status Strip
            telemetryStrip

            // 2. Band Switch Recommendation Alert (if active)
            if let rec = advisor.activeRecommendation {
                bandSwitchBanner(rec)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 3. Apex DX Target Card (The #1 Hunt Opportunity)
            apexTargetCard
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.25), value: advisor.activeRecommendation)
        .animation(.easeInOut(duration: 0.25), value: roster.apexTarget?.callsign)
        .onAppear {
            advisor.setActiveBand(activeBand)
        }
        .onChange(of: appState.wsjtxListener.lastStatus?.band) { _, newBand in
            if let b = newBand, !b.isEmpty {
                advisor.setActiveBand(b)
            }
        }
    }

    // MARK: - Telemetry Strip

    private var telemetryStrip: some View {
        HStack(spacing: 12) {
            // SDR / WSJT-X UDP Link
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.wsjtxListener.state.isListening ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text("UDP (\(String(appState.wsjtxListener.currentPort))):")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Text("\(appState.wsjtxListener.decodesCount) decodes")
                    .font(.caption)
                    .monospacedDigit()
                    .fontWeight(.bold)
            }

            Divider().frame(height: 14)

            // Current Band & Propagation Health Meter
            HStack(spacing: 6) {
                Text(activeBand)
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))

                if advisor.currentBandHealth == 0 || (advisor.currentBandDecodesPerMin == 0 && (advisor.bandSnapshots[activeBand]?.clusterSpotCount ?? 0) == 0) {
                    HStack(spacing: 4) {
                        Text("Health: --")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                        Text("(Standby)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: advisor.currentBandTrend.icon)
                            .font(.caption)
                            .foregroundStyle(advisor.currentBandTrend.color)

                        Text("Health: \(advisor.currentBandHealth)%")
                            .font(.caption)
                            .monospacedDigit()
                            .fontWeight(.bold)
                            .foregroundStyle(healthColor(advisor.currentBandHealth))

                        Text("(\(String(format: "%.1f", advisor.currentBandDecodesPerMin)) dec/m)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .help("Band Propagation Health: Evaluates real-time band openness (0–100%) based on FT8/FT4 decode rate, signal SNR, and DX cluster spots.")

            Spacer()

            // Transceiver CAT Status
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(rig.isConnected ? Color.green : Color.secondary)
                Text(rig.isConnected ? "CAT: \(rig.rigModel)" : "CAT Offline")
                    .font(.caption2)
                    .foregroundStyle(rig.isConnected ? Color.primary : Color.secondary)
            }

            Divider().frame(height: 14)

            // High-Contrast Auto-Pilot Button
            Button {
                queue.toggleAutoPilot()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(queue.isAutoPilotActive ? Color.orange : Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)

                    Image(systemName: queue.isAutoPilotActive ? "bolt.shield.fill" : "bolt.shield")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(queue.isAutoPilotActive ? Color.orange : Color.secondary)

                    Text(queue.isAutoPilotActive ? "Auto-Pilot: ACTIVE" : "Auto-Pilot: OFF")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(queue.isAutoPilotActive ? Color.orange : Color.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(queue.isAutoPilotActive ? Color.orange.opacity(0.15) : Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(queue.isAutoPilotActive ? Color.orange.opacity(0.8) : Color.secondary.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Autonomous Pilot: Automatically locks and hunts the top target on each 15s FT8 slot")
        }
    }

    // MARK: - Band Switch Recommendation Banner

    private func bandSwitchBanner(_ rec: BandSwitchRecommendation) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.yellow)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("PROPAGATION ADVISOR:")
                        .font(.caption)
                        .fontWeight(.heavy)
                        .foregroundStyle(.orange)
                    Text("Switch from \(rec.fromBand) to \(rec.targetBand)")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                Text(rec.reason)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                advisor.executeQSY(to: rec, rigClient: appState.rigControlClient)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("1-Click QSY \(rec.targetBand)")
                }
                .font(.caption)
                .fontWeight(.bold)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)

            Button {
                advisor.dismissActiveRecommendation()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Apex Target Card

    private var apexTargetCard: some View {
        Group {
            if let target = roster.apexTarget {
                HStack(spacing: 14) {
                    // Country Flag & Priority Badge
                    VStack(spacing: 4) {
                        Text(target.countryInfo.flagEmoji)
                            .font(.system(size: 32))
                        
                        Text(target.status.rawValue)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(target.status.badgeColor, in: Capsule())
                            .foregroundStyle(.white)
                    }

                    // Callsign, Entity, and Geodesic info
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(target.callsign)
                                .font(.system(size: 20, weight: .black, design: .monospaced))
                                .foregroundStyle(target.status.badgeColor)

                            Text(target.countryInfo.entityName)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            if !target.grid.isEmpty {
                                Label(target.grid, systemImage: "square.grid.2x2")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            if let dist = target.distanceKm {
                                Label("\(Int(dist)) km", systemImage: "arrow.up.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            if let b = target.bearingDeg {
                                Label("\(b)°", systemImage: "safari")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Label(target.snrFormatted, systemImage: "waveform")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(target.snrColor)

                            Text("Score: \(target.tacticalScore)")
                                .font(.caption2)
                                .fontWeight(.heavy)
                                .foregroundStyle(.purple)
                        }

                        Text(target.message)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.top, 1)
                    }

                    Spacer()

                    // Action Buttons
                    VStack(alignment: .trailing, spacing: 6) {
                        Button {
                            huntTarget(target)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "target")
                                Text("1-Click Hunt & Call")
                            }
                            .font(.caption)
                            .fontWeight(.bold)
                            .frame(minWidth: 140)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

                        Button {
                            queue.enqueue(
                                callsign: target.callsign,
                                grid: target.grid,
                                deltaFrequencyHz: target.deltaFrequencyHz,
                                snr: target.snr,
                                mode: target.mode
                            )
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle")
                                Text("Enqueue Target")
                            }
                            .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.blue)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                )
            } else {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(appState.wsjtxListener.state.isListening ? (queue.isAutoPilotActive ? Color.orange.opacity(0.15) : Color.blue.opacity(0.12)) : Color.secondary.opacity(0.1))
                            .frame(width: 32, height: 32)

                        Image(systemName: queue.isAutoPilotActive ? "bolt.shield.fill" : "scope")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(queue.isAutoPilotActive ? Color.orange : (appState.wsjtxListener.state.isListening ? Color.blue : Color.secondary))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(queue.isAutoPilotActive ? "Auto-Pilot Armed — Ready to Call" : "Target Hunter Standby")
                                .font(.caption)
                                .fontWeight(.bold)

                            if queue.isAutoPilotActive {
                                Text("AUTONOMOUS")
                                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.orange.opacity(0.2), in: Capsule())
                                    .foregroundStyle(Color.orange)
                            } else {
                                Text("MANUAL")
                                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.secondary.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(appState.wsjtxListener.state.isListening ?
                             "Monitoring UDP port \(String(appState.wsjtxListener.currentPort)) for live FT8/FT4 decodes. Priority DXCC & needed contacts will appear here." :
                             "UDP Listener is stopped. Click Start Listener in toolbar to receive live decodes.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Cycle countdown when active
                    if appState.wsjtxListener.state.isListening {
                        HStack(spacing: 5) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text(String(format: "Cycle: %.1fs", queue.secondsRemainingInCycle))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1), in: Capsule())
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                )
            }
        }
    }

    // MARK: - Actions

    private func huntTarget(_ entry: DigitalRosterEntry) {
        // 1. Reply via WSJT-X / SDR-Control UDP
        if let raw = entry.rawDecode {
            appState.wsjtxListener.sendReply(to: raw)
        }

        // 2. Also inform target queue
        queue.enqueue(
            callsign: entry.callsign,
            grid: entry.grid,
            deltaFrequencyHz: entry.deltaFrequencyHz,
            snr: entry.snr,
            mode: entry.mode
        )
    }

    private func healthColor(_ health: Int) -> Color {
        switch health {
        case 70...: return .green
        case 40 ..< 70: return .yellow
        default: return .red
        }
    }
}
