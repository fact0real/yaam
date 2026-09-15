//
//  ContestBandmapHUDView.swift
//  YAAM
//
//  Interactive Visual Contest Bandmap HUD.
//  Compact vertical frequency ruler with real-time VFO tracking, RBN / DX Cluster spot plotting,
//  contest status badges (MULT, NEW, DUPE), spot age decay, and 1-click CAT QSY.
//

import Combine
import SwiftUI

public struct ContestBandmapSpotItem: Identifiable, Sendable {
    public var id: String { "\(callsign)-\(frequencyKHz)" }
    public let callsign: String
    public let frequencyKHz: Double
    public let band: String
    public let mode: String
    public let spottedAt: Date
    public let flagEmoji: String
    public let entityName: String
    public let status: SCPMatchStatus
    public let snrDB: Int?

    public init(
        callsign: String,
        frequencyKHz: Double,
        band: String,
        mode: String,
        spottedAt: Date,
        flagEmoji: String,
        entityName: String,
        status: SCPMatchStatus,
        snrDB: Int? = nil
    ) {
        self.callsign = callsign
        self.frequencyKHz = frequencyKHz
        self.band = band
        self.mode = mode
        self.spottedAt = spottedAt
        self.flagEmoji = flagEmoji
        self.entityName = entityName
        self.status = status
        self.snrDB = snrDB
    }

    /// Age in minutes
    public var ageMinutes: Double {
        max(0, Date().timeIntervalSince(spottedAt) / 60.0)
    }

    /// Visual opacity based on age decay (0-5m: 1.0, 5-15m: 0.75, 15-30m: 0.45, >30m: 0.25)
    public var ageOpacity: Double {
        let age = ageMinutes
        if age < 5.0 { return 1.0 }
        if age < 15.0 { return 0.75 }
        if age < 30.0 { return 0.45 }
        return 0.25
    }
}

public struct ContestBandmapHUDView: View {
    @EnvironmentObject private var appState: AppState
    public var activeBand: String
    public var activeMode: String
    public var currentVFOFrequencyMHz: Double
    public var onSelectSpot: ((ContestBandmapSpotItem) -> Void)?

    @State private var hoveredSpotID: String? = nil
    @State private var filterOnlyMults: Bool = false

    public init(
        activeBand: String = "20M",
        activeMode: String = "CW",
        currentVFOFrequencyMHz: Double = 14.025,
        onSelectSpot: ((ContestBandmapSpotItem) -> Void)? = nil
    ) {
        self.activeBand = activeBand
        self.activeMode = activeMode
        self.currentVFOFrequencyMHz = currentVFOFrequencyMHz
        self.onSelectSpot = onSelectSpot
    }

    // Band limits in kHz (CW contest segment default)
    private var bandRangeKHz: (min: Double, max: Double) {
        switch activeBand.uppercased() {
        case "160M": return (1810.0, 1850.0)
        case "80M":  return (3500.0, 3570.0)
        case "40M":  return (7000.0, 7050.0)
        case "20M":  return (14000.0, 14070.0)
        case "15M":  return (21000.0, 21070.0)
        case "10M":  return (28000.0, 28070.0)
        case "6M":   return (50000.0, 50150.0)
        default:     return (14000.0, 14070.0)
        }
    }

    private var plottedSpots: [ContestBandmapSpotItem] {
        let (minF, maxF) = bandRangeKHz
        let clusterSpots = appState.dxClusterClient.spots
        let qsoRecords = appState.qsoRecords
        let band = activeBand.uppercased()
        let mode = activeMode.uppercased()

        var items: [ContestBandmapSpotItem] = []
        var seen = Set<String>()

        for spot in clusterSpots {
            let freq = spot.frequencyKHz
            guard freq >= minF && freq <= maxF else { continue }
            let call = spot.callsign.uppercased()
            guard !seen.contains(call) else { continue }
            seen.insert(call)

            // Evaluate contest status (MULT, NEW, DUPE)
            let dxcc = DXCCDatabase.resolve(callsign: call)
            let isDupe = qsoRecords.contains(where: { q in
                let qCall = q.fields["CALL"]?.uppercased() ?? ""
                let qBand = q.fields["BAND"]?.uppercased() ?? ""
                let qMode = q.fields["MODE"]?.uppercased() ?? ""
                return qCall == call && (band.isEmpty || qBand == band) && (mode.isEmpty || qMode == mode)
            })

            let status: SCPMatchStatus
            if isDupe {
                status = .duplicate
            } else {
                let workedEntity = qsoRecords.contains(where: { q in
                    let qCall = q.fields["CALL"] ?? ""
                    return DXCCDatabase.resolve(callsign: qCall).entityName == dxcc.entityName
                })
                if !workedEntity && !dxcc.entityName.isEmpty && dxcc.entityName != "Unknown" {
                    status = .newMultiplier
                } else {
                    status = .validNewCall
                }
            }

            if filterOnlyMults && status != .newMultiplier { continue }

            let item = ContestBandmapSpotItem(
                callsign: call,
                frequencyKHz: freq,
                band: band,
                mode: mode,
                spottedAt: spot.lastSeenAt,
                flagEmoji: dxcc.flagEmoji,
                entityName: dxcc.entityName,
                status: status,
                snrDB: spot.snrDB
            )
            items.append(item)
        }

        return items.sorted(by: { $0.frequencyKHz < $1.frequencyKHz })
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()

            // Visual Frequency Tape Ruler
            GeometryReader { geo in
                let (minF, maxF) = bandRangeKHz
                let range = max(1.0, maxF - minF)
                let height = geo.size.height

                ZStack(alignment: .topLeading) {
                    // Dark background with subtle grid lines
                    Color(NSColor.controlBackgroundColor).opacity(0.85)

                    // Major frequency tick marks (every 10 kHz)
                    Canvas { context, size in
                        let startTick = ceil(minF / 10.0) * 10.0
                        var tick = startTick
                        while tick <= maxF {
                            let fraction = (tick - minF) / range
                            let y = (1.0 - fraction) * size.height
                            let p1 = CGPoint(x: 0, y: y)
                            let p2 = CGPoint(x: 40, y: y)
                            var path = Path()
                            path.move(to: p1)
                            path.addLine(to: p2)
                            context.stroke(path, with: .color(Color.primary.opacity(0.18)), lineWidth: 1)

                            let label = String(format: "%.0f", tick)
                            context.draw(
                                Text(label).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(.secondary),
                                at: CGPoint(x: 22, y: y - 6)
                            )
                            tick += 10.0
                        }
                    }

                    // VFO Current Frequency Indicator Line
                    let vfoKHz = currentVFOFrequencyMHz * 1000.0
                    if vfoKHz >= minF && vfoKHz <= maxF {
                        let fraction = (vfoKHz - minF) / range
                        let vfoY = (1.0 - fraction) * height

                        HStack(spacing: 4) {
                            Rectangle()
                                .fill(Color.orange)
                                .frame(width: 35, height: 2)
                                .shadow(color: .orange.opacity(0.6), radius: 2)

                            HStack(spacing: 3) {
                                Image(systemName: "arrowtriangle.right.fill")
                                    .font(.system(size: 7))
                                    .foregroundColor(.orange)
                                Text(String(format: "%.3f", currentVFOFrequencyMHz))
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                        }
                        .offset(y: vfoY - 6)
                    }

                    // Plotted Spots along the vertical ruler
                    ForEach(plottedSpots) { spot in
                        let fraction = (spot.frequencyKHz - minF) / range
                        let spotY = (1.0 - fraction) * height

                        Button {
                            handleSpotSelection(spot)
                        } label: {
                            HStack(spacing: 4) {
                                // Dot on frequency axis
                                Circle()
                                    .fill(statusColor(spot.status))
                                    .frame(width: 5, height: 5)

                                // Country Flag
                                Text(spot.flagEmoji)
                                    .font(.system(size: 9))

                                // Callsign
                                Text(spot.callsign)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(spot.status == .duplicate ? .secondary : .primary)

                                // Status Badge
                                statusPill(spot.status)

                                if let snr = spot.snrDB {
                                    Text("\(snr)dB")
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                Text(String(format: "%.1f", spot.frequencyKHz))
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(hoveredSpotID == spot.id ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor).opacity(0.7))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(statusColor(spot.status).opacity(0.3), lineWidth: 0.8)
                            )
                            .opacity(spot.ageOpacity)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 55, y: max(0, min(height - 18, spotY - 8)))
                        .onHover { isHovered in
                            hoveredSpotID = isHovered ? spot.id : nil
                        }
                        .help("Click to QSY to \(spot.callsign) on \(String(format: "%.3f", spot.frequencyKHz / 1000.0)) MHz (\(spot.entityName))")
                    }

                    // Empty State Notice
                    if plottedSpots.isEmpty {
                        VStack(spacing: 5) {
                            Image(systemName: filterOnlyMults ? "star.slash" : "antenna.radiowaves.left.and.right")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary.opacity(0.6))
                            Text(filterOnlyMults ? "No unworked multipliers on \(activeBand)" : "No spots on \(activeBand) • Waiting for cluster")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(height: 220)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.95))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12), lineWidth: 1))
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 10))
                .foregroundColor(.orange)

            Text("CONTEST BANDMAP (\(activeBand))")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            Spacer()

            // Filter MULTs Only toggle
            Button {
                filterOnlyMults.toggle()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: filterOnlyMults ? "star.fill" : "star")
                        .font(.system(size: 8))
                    Text("MULTs Only")
                        .font(.system(size: 8, weight: .bold))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(filterOnlyMults ? Color.orange.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                .foregroundColor(filterOnlyMults ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(filterOnlyMults ? "Show all spots on active band" : "Filter bandmap to display only unworked DXCC multipliers")

            Text("\(plottedSpots.count) spots")
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func handleSpotSelection(_ spot: ContestBandmapSpotItem) {
        let freqMHz = spot.frequencyKHz / 1000.0
        // 1. Send CAT QSY command to rig
        Task { @MainActor in
            appState.quickLogDraft.callsign = spot.callsign
            appState.quickLogDraft.frequencyMHz = String(format: "%.3f", freqMHz)
            appState.quickLogDraft.band = spot.band
            appState.quickLogDraft.mode = spot.mode

            if appState.rigControlClient.state.isConnected {
                appState.rigControlClient.setFrequencyHz(UInt64(spot.frequencyKHz * 1_000))
            } else if FLRigClient.shared.isConnected {
                try? await FLRigClient.shared.setFrequency(hz: spot.frequencyKHz * 1_000.0)
            }
        }
        onSelectSpot?(spot)
    }

    private func statusColor(_ status: SCPMatchStatus) -> Color {
        switch status {
        case .newMultiplier: return .orange
        case .validNewCall: return .green
        case .duplicate: return .secondary
        }
    }

    private func statusPill(_ status: SCPMatchStatus) -> some View {
        Group {
            switch status {
            case .newMultiplier:
                Text("MULT")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 2))
            case .validNewCall:
                Text("NEW")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 2))
            case .duplicate:
                Text("DUPE")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 2))
            }
        }
    }
}
