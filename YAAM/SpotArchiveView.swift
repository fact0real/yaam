//
//  SpotArchiveView.swift
//  YAAM
//
//  Dedicated multi-day spot archive search, historical propagation inspector,
//  and CSV export interface.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct SpotArchiveView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var archiveDB = SpotArchiveDatabase.shared

    @State private var searchQuery: String = ""
    @State private var selectedBand: String = "All"
    @State private var selectedMode: String = "All"
    @State private var selectedTimeWindowHours: Int = 48
    @State private var searchResults: [ArchivedSpotRecord] = []
    @State private var isExporting: Bool = false
    @State private var exportStatusMessage: String? = nil

    private let timeWindows = [
        ("6 Hours", 6),
        ("12 Hours", 12),
        ("24 Hours (1 Day)", 24),
        ("48 Hours (2 Days)", 48),
        ("7 Days (1 Week)", 168)
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()

            searchFilterToolbar

            Divider()

            resultsTable

            Divider()

            statusBar
        }
        .frame(minWidth: 860, minHeight: 520)
        .onAppear {
            performSearch()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title2)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Historical Spot Archive & Activity Inspector")
                    .font(.headline.weight(.bold))
                Text("Persistent multi-day SQLite archive (\(archiveDB.totalStoredSpots) spots stored)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                exportArchiveToCSV()
            } label: {
                Label("Export to CSV", systemImage: "square.and.arrow.up")
            }
            .help("Export currently displayed search results to a CSV file")

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Search Filters

    private var searchFilterToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search callsign (e.g. 3Y0*, EP*, W1AW)", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit { performSearch() }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                        performSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            .frame(minWidth: 240)

            Picker("Band", selection: $selectedBand) {
                Text("All Bands").tag("All")
                ForEach(AmateurBandPlan.commonBands, id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 120)
            .onChange(of: selectedBand) { _, _ in performSearch() }

            Picker("Mode", selection: $selectedMode) {
                Text("All Modes").tag("All")
                Text("CW").tag("CW")
                Text("SSB").tag("SSB")
                Text("FT8").tag("FT8")
                Text("RTTY").tag("RTTY")
            }
            .frame(width: 110)
            .onChange(of: selectedMode) { _, _ in performSearch() }

            Picker("Time Window", selection: $selectedTimeWindowHours) {
                ForEach(timeWindows, id: \.1) { item in
                    Text(item.0).tag(item.1)
                }
            }
            .frame(width: 150)
            .onChange(of: selectedTimeWindowHours) { _, _ in performSearch() }

            Button("Search") {
                performSearch()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Table of Results

    private var resultsTable: some View {
        Group {
            if searchResults.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No archived spots matched your criteria")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Try widening the time window or clearing search filters.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(searchResults) {
                    TableColumn("UTC") { spot in
                        Text(spot.spottedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(.caption, design: .monospaced))
                    }
                    .width(min: 110, ideal: 125)

                    TableColumn("Frequency") { spot in
                        Text(String(format: "%.1f kHz", spot.frequencyKHz))
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                    }
                    .width(min: 85, ideal: 95)

                    TableColumn("Callsign") { spot in
                        HStack(spacing: 4) {
                            if !spot.flagEmoji.isEmpty {
                                Text(spot.flagEmoji)
                            }
                            Text(spot.callsign)
                                .font(.system(.body, design: .monospaced).weight(.bold))
                            if spot.reportCount > 1 {
                                Text("×\(spot.reportCount)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.15), in: Capsule())
                            }
                        }
                    }
                    .width(min: 130, ideal: 145)

                    TableColumn("Band/Mode") { spot in
                        HStack(spacing: 3) {
                            Text(spot.band)
                                .font(.caption.weight(.medium))
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(spot.mode)
                                .font(.caption)
                        }
                    }
                    .width(min: 70, ideal: 85)

                    TableColumn("SNR") { spot in
                        if let snr = spot.snrDB {
                            Text("\(snr > 0 ? "+\(snr)" : "\(snr)")dB")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(snrColor(snr))
                        } else {
                            Text("-").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .width(min: 48, ideal: 52)

                    TableColumn("Beam") { spot in
                        if let beam = spot.beamHeadingDeg {
                            Text(String(format: "%03.0f°", beam))
                                .font(.system(.caption, design: .monospaced))
                        } else {
                            Text("-").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .width(min: 45, ideal: 50)

                    TableColumn("Country") { spot in
                        Text(spot.dxccEntity.isEmpty ? "-" : spot.dxccEntity)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .width(min: 100, ideal: 120)

                    TableColumn("Spotter") { spot in
                        Text(spot.spotter)
                            .font(.system(.caption, design: .monospaced))
                    }
                    .width(min: 80, ideal: 90)

                    TableColumn("Comment") { spot in
                        Text(spot.comment.isEmpty ? "-" : spot.comment)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 140, ideal: 200)

                    TableColumn("Action") { spot in
                        HStack(spacing: 6) {
                            Button {
                                tuneToSpot(spot)
                            } label: {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                            .help("Tune connected radio to \(String(format: "%.1f", spot.frequencyKHz)) kHz")

                            Button {
                                prepareLog(spot)
                            } label: {
                                Image(systemName: "square.and.pencil")
                            }
                            .help("Load into Quick Log")
                        }
                        .buttonStyle(.borderless)
                    }
                    .width(55)
                }
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            Text("Showing \(searchResults.count) matching spots from the last \(selectedTimeWindowHours) hours")
                .foregroundStyle(.secondary)

            if let msg = exportStatusMessage {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(msg)
                    .foregroundStyle(.green)
            }

            Spacer()

            Text("Double-click any spot to tune CAT radio & prepare Quick Log")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Helper Methods

    private func performSearch() {
        searchResults = archiveDB.searchArchive(
            callsign: searchQuery,
            band: selectedBand,
            mode: selectedMode,
            sinceHours: selectedTimeWindowHours,
            limit: 600
        )
    }

    private func snrColor(_ snr: Int) -> Color {
        if snr >= 20 { return .green }
        if snr >= 10 { return .yellow }
        if snr >= 3  { return .orange }
        return .red
    }

    private func tuneToSpot(_ spot: ArchivedSpotRecord) {
        if appState.rigControlClient.state.isConnected {
            appState.rigControlClient.setFrequencyHz(UInt64(spot.frequencyKHz * 1000.0))
        }
    }

    private func prepareLog(_ spot: ArchivedSpotRecord) {
        appState.quickLogDraft.callsign = spot.callsign
        appState.quickLogDraft.band = spot.band
        appState.quickLogDraft.mode = spot.mode
        appState.quickLogDraft.frequencyMHz = String(format: "%.6f", spot.frequencyMHz)
        appState.quickLogDraft.comment = spot.comment
        appState.quickLogStatus = "Archived spot \(spot.callsign) loaded into Quick Log"
    }

    private func exportArchiveToCSV() {
        guard !searchResults.isEmpty else { return }
        let csv = SpotArchiveDatabase.generateCSV(from: searchResults)

        let panel = NSSavePanel()
        panel.title = "Export Spot Archive to CSV"
        panel.nameFieldStringValue = "YAAM_Spot_Archive_\(selectedBand)_\(Date().formatted(date: .numeric, time: .omitted)).csv"
        panel.allowedContentTypes = [.commaSeparatedText]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                exportStatusMessage = "Successfully exported \(searchResults.count) spots to \(url.lastPathComponent)"
            } catch {
                exportStatusMessage = "Failed to export CSV: \(error.localizedDescription)"
            }
        }
    }
}
