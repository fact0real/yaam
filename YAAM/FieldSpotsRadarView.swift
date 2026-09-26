//
//  FieldSpotsRadarView.swift
//  YAAM
//
//  Real-Time POTA & SOTA Live Spots Radar
//  Displays active activators, highlights Park-to-Park (P2P) opportunities,
//  and enables 1-Click CAT QSY directly to any spotted station.
//

import Combine
import SwiftUI

public struct FieldSpotsRadarView: View {
    @ObservedObject private var spotsClient = POTASpotsClient.shared
    @ObservedObject private var potaEngine = POTASOTAEngine.shared

    private static let bands = ["ALL", "160M", "80M", "60M", "40M", "30M", "20M", "17M", "15M", "12M", "10M", "6M", "2M"]
    private static let modes = ["ALL", "CW", "SSB", "FT8"]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Filter Bar
            filterHeaderBar

            Divider()

            // Spots Content Table
            if spotsClient.selectedProgram == .pota {
                potaSpotsList
            } else {
                sotaSpotsList
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Filter Header Bar
    private var filterHeaderBar: some View {
        HStack(spacing: 12) {
            // Program Switcher
            Picker("Program", selection: $spotsClient.selectedProgram) {
                Text("POTA Spots").tag(FieldProgramType.pota)
                Text("SOTA Spots").tag(FieldProgramType.sota)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Divider().frame(height: 18)

            // Band Picker
            Picker("Band", selection: $spotsClient.selectedBand) {
                ForEach(Self.bands, id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 95)

            // Mode Picker
            Picker("Mode", selection: $spotsClient.selectedMode) {
                ForEach(Self.modes, id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 90)

            // Search Field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search call, park, state...", text: $spotsClient.searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

            Spacer()

            // Refresh Button
            Button {
                Task { await spotsClient.refreshSpots() }
            } label: {
                if spotsClient.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .help("Refresh live spots")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - POTA Spots List
    private var potaSpotsList: some View {
        Group {
            let spots = spotsClient.filteredPOTASpots
            if spots.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No POTA spots found matching your filter.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(spots) { spot in
                        potaSpotRow(spot: spot)
                            .listRowInsets(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func potaSpotRow(spot: POTASpotItem) -> some View {
        let isP2P = potaEngine.activeSession?.isActive == true

        return HStack(spacing: 10) {
            // Band & Mode Badge
            VStack(alignment: .leading, spacing: 2) {
                Text(spot.formattedFrequency)
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.accentColor)

                HStack(spacing: 4) {
                    Text(spot.band)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.secondary)

                    Text(spot.mode)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(modeColor(spot.mode))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(modeColor(spot.mode).opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                }
            }
            .frame(width: 120, alignment: .leading)

            // Callsign & Park Reference
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(spot.activator)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(.primary)

                    Text(spot.reference)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                    if isP2P {
                        Text("P2P")
                            .font(.system(size: 8.5, weight: .heavy))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                    }
                }

                Text(spot.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Location / Comments
            VStack(alignment: .trailing, spacing: 2) {
                if let loc = spot.locationDesc {
                    Text(loc)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                if let comm = spot.comments, !comm.isEmpty {
                    Text(comm)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 180, alignment: .trailing)

            // CAT Tune Button (1-Click QSY)
            Button {
                spotsClient.tuneRig(frequencyKHz: spot.frequencyKHz, mode: spot.mode)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Tune CAT")
                }
                .font(.system(size: 10.5, weight: .bold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 3)
    }

    // MARK: - SOTA Spots List
    private var sotaSpotsList: some View {
        Group {
            let spots = spotsClient.filteredSOTASpots
            if spots.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "mountain.2.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No SOTA spots found matching your filter.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(spots) { spot in
                        sotaSpotRow(spot: spot)
                            .listRowInsets(EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10))
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func sotaSpotRow(spot: SOTASpotItem) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(spot.formattedFrequency)
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.accentColor)

                HStack(spacing: 4) {
                    Text(spot.band)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.secondary)

                    Text(spot.mode)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(modeColor(spot.mode))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(modeColor(spot.mode).opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                }
            }
            .frame(width: 120, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(spot.activatorCallsign)
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(.primary)

                    Text(spot.summitCode)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }

                if let details = spot.summitDetails {
                    Text(details)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let comm = spot.comments {
                Text(comm)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 180, alignment: .trailing)
            }

            Button {
                spotsClient.tuneRig(frequencyKHz: spot.frequencyKHz, mode: spot.mode)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Tune CAT")
                }
                .font(.system(size: 10.5, weight: .bold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 3)
    }

    private func modeColor(_ mode: String) -> Color {
        let u = mode.uppercased()
        if u.contains("CW") { return .yellow }
        if u.contains("FT8") || u.contains("DATA") { return .green }
        return .orange
    }
}
