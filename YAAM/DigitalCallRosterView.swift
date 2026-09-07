//
//  DigitalCallRosterView.swift
//  YAAM
//
//  Live Digital Call Roster Console for macOS.
//  Real-time triage of WSJT-X / JTDX and internal FT8 decodes, matching against
//  the Master Log for New DXCC, New Band, New Grid, and 1-Click Double-Click Reply.
//

import AppKit
import AVFoundation
import SwiftUI

public struct DigitalCallRosterView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var roster = DigitalCallRosterEngine.shared
    @ObservedObject private var audioAlerts = DigitalAudioAlertEngine.shared

    @State private var filterMode: RosterFilterMode = .neededOnly
    @State private var minSNRFilter: Int = -30
    @State private var searchText: String = ""
    @State private var selectedEntryID: UUID? = nil
    @State private var showingAudioSettings = false
    @State private var showingDetailSheet = false
    @State private var selectedEntryForDetail: DigitalRosterEntry? = nil

    public enum RosterFilterMode: String, CaseIterable, Identifiable {
        case neededOnly = "⚡️ Needed Only"
        case cqOnly = "CQ Only"
        case directedToMe = "To Me"
        case all = "All Decodes"

        public var id: String { rawValue }
    }

    public init() {}

    private var activeBand: String {
        let reported = appState.wsjtxListener.lastStatus?.band.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return reported.isEmpty ? "20M" : reported.uppercased()
    }

    private var filteredEntries: [DigitalRosterEntry] {
        roster.entries.filter { entry in
            // Filter mode
            switch filterMode {
            case .neededOnly:
                if !entry.status.isNeeded { return false }
            case .cqOnly:
                if !entry.isCQ { return false }
            case .directedToMe:
                if !entry.isToMe { return false }
            case .all:
                break
            }

            // Min SNR
            if entry.snr < Int32(minSNRFilter) {
                return false
            }

            // Search query
            if !searchText.isEmpty {
                let q = searchText.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let matchesCall = entry.callsign.contains(q)
                let matchesCountry = entry.countryInfo.entityName.uppercased().contains(q)
                let matchesGrid = entry.grid.contains(q)
                let matchesMsg = entry.message.uppercased().contains(q)
                if !matchesCall && !matchesCountry && !matchesGrid && !matchesMsg {
                    return false
                }
            }

            return true
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            topControlBar
            Divider()
            filterAndStatsBar
            Divider()

            if filteredEntries.isEmpty {
                emptyRosterState
            } else {
                rosterTable
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingAudioSettings) {
            audioSettingsSheet
        }
        .sheet(item: $selectedEntryForDetail) { entry in
            entryDetailSheet(entry)
        }
        .onAppear {
            if !appState.wsjtxListener.state.isListening {
                appState.wsjtxListener.start(port: 2237)
            }
            syncContextAndRebuild()
            if !appState.wsjtxListener.liveDecodes.isEmpty {
                roster.processDecodes(appState.wsjtxListener.liveDecodes, activeBand: activeBand)
            } else if roster.entries.isEmpty {
                loadSampleDecodes()
            }
        }
        .onChange(of: appState.qsoRecordsRevision) { _, _ in
            roster.rebuildLogCache(records: appState.qsoRecords)
        }
        .onChange(of: appState.wsjtxListener.liveDecodes) { _, newDecodes in
            roster.processDecodes(newDecodes, activeBand: activeBand)
        }
    }

    // MARK: - Top Control Bar

    private var topControlBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.and.person.filled")
                    .foregroundColor(.accentColor)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Digital Call Roster")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text("Real-Time FT8/FT4 Triage & Smart Log-Needs Matching")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Transceiver CAT Control HUD
            RigControlToolbarView()

            // Radio / Dial Band Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.wsjtxListener.state.isListening ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(appState.wsjtxListener.lastStatus?.frequencyMHz.isEmpty == false ?
                     "\(appState.wsjtxListener.lastStatus!.frequencyMHz) MHz (\(activeBand))" :
                     "Band: \(activeBand)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)

            // WSJT-X Listener Start/Stop Button
            Button {
                if appState.wsjtxListener.state.isListening {
                    appState.wsjtxListener.stop()
                } else {
                    appState.wsjtxListener.start(port: 2237)
                }
            } label: {
                Label(
                    appState.wsjtxListener.state.isListening ? "Listening (2237)" : "Start Listener",
                    systemImage: appState.wsjtxListener.state.isListening ? "antenna.radiowaves.left.and.right" : "play.fill"
                )
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(appState.wsjtxListener.state.isListening ? .green : .blue)

            // Audio Speech Alerts Popover Button
            Button {
                showingAudioSettings = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: audioAlerts.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .foregroundColor(audioAlerts.isEnabled ? .accentColor : .secondary)
                    Text("Voice Alerts")
                        .font(.caption)
                }
            }
            .buttonStyle(.bordered)
            .help("Configure Hands-Free Audio Speech Alerts")

            // Clear Roster Button
            Button {
                roster.clearRoster()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .help("Clear current roster entries")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Filter & Counters Bar

    private var filterAndStatsBar: some View {
        HStack(spacing: 12) {
            // Mode Segmented Control
            Picker("", selection: $filterMode) {
                ForEach(RosterFilterMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            // Min SNR Filter
            Menu {
                Button("All Signals") { minSNRFilter = -30 }
                Divider()
                Button("≥ -20 dB") { minSNRFilter = -20 }
                Button("≥ -15 dB") { minSNRFilter = -15 }
                Button("≥ -10 dB") { minSNRFilter = -10 }
                Button("≥ -5 dB") { minSNRFilter = -5 }
                Button("≥ 0 dB (Strong)") { minSNRFilter = 0 }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                    Text(minSNRFilter <= -30 ? "SNR: All" : "SNR ≥ \(minSNRFilter) dB")
                }
                .font(.caption)
            }
            .frame(width: 120)

            // Search Field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Search call, grid, country...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)

            Spacer()

            // Summary Badges
            HStack(spacing: 8) {
                summaryBadge(title: "Total", count: roster.totalDecodesCount, color: .primary)
                summaryBadge(title: "Needed", count: roster.neededCount, color: .purple)
                summaryBadge(title: "CQs", count: roster.cqCount, color: .blue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func summaryBadge(title: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("\(count)")
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
    }

    // MARK: - Roster Table

    private var rosterTable: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                // Table Header
                tableHeaderView
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))

                ForEach(filteredEntries) { entry in
                    rosterRow(entry)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            selectedEntryID == entry.id ?
                                Color.accentColor.opacity(0.15) :
                                (entry.status.isNeeded ? entry.status.badgeColor.opacity(0.06) : Color(NSColor.controlBackgroundColor).opacity(0.3))
                        )
                        .cornerRadius(6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedEntryID = entry.id
                        }
                        .onTapGesture(count: 2) {
                            callStation(entry)
                        }
                        .contextMenu {
                            Button("Call \(entry.callsign) (Reply)") {
                                callStation(entry)
                            }
                            Button("Inspect Details & Log History") {
                                selectedEntryForDetail = entry
                            }
                            Button("Open QRZ.com (\(entry.callsign))") {
                                if let url = URL(string: "https://www.qrz.com/db/\(entry.callsign)") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var tableHeaderView: some View {
        HStack(spacing: 8) {
            Text("PRIORITY")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .leading)

            Text("CALLSIGN & COUNTRY")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(minWidth: 180, alignment: .leading)

            Text("GRID / DISTANCE")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)

            Text("SNR")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 65, alignment: .center)

            Text("OFFSET")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 65, alignment: .trailing)

            Text("MESSAGE")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("ACTION")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
                .frame(width: 75, alignment: .trailing)
        }
    }

    private func rosterRow(_ entry: DigitalRosterEntry) -> some View {
        HStack(spacing: 8) {
            // Priority Badge
            HStack(spacing: 4) {
                Image(systemName: entry.status.badgeIcon)
                    .font(.system(size: 10))
                Text(entry.status.rawValue)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(entry.status.badgeColor)
            .cornerRadius(4)
            .frame(width: 110, alignment: .leading)

            // Callsign & Country
            HStack(spacing: 6) {
                Text(entry.countryInfo.flagEmoji)
                    .font(.body)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.callsign)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.bold)
                    Text(entry.countryInfo.entityName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 180, alignment: .leading)

            // Grid / Distance / Bearing
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.grid.isEmpty ? "-" : entry.grid)
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                if let dist = entry.distanceKm, let bearing = entry.bearingDeg {
                    Text("\(Int(dist)) km • \(bearing)°")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 140, alignment: .leading)

            // SNR Badge
            Text(entry.snrFormatted)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(entry.snrColor)
                .frame(width: 65, alignment: .center)

            // Offset
            Text(entry.deltaFrequencyFormatted)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 65, alignment: .trailing)

            // Raw Message
            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(entry.isCQ ? .accentColor : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Action: 1-Click Tune Rig & Call Reply
            HStack(spacing: 4) {
                Button {
                    let dialHz = appState.wsjtxListener.lastStatus?.dialFrequencyHz ?? 14074000
                    RigControlEngine.shared.tune(frequencyHz: dialHz, mode: "USB-D")
                } label: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 9))
                }
                .buttonStyle(.bordered)
                .help("Tune Transceiver to this Band/Freq")

                Button {
                    callStation(entry)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                        Text("Call")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(entry.status.isNeeded ? .purple : .accentColor)
            }
            .frame(width: 105, alignment: .trailing)
        }
    }

    // MARK: - Empty State

    private var emptyRosterState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            VStack(spacing: 6) {
                Text("Listening for Digital Mode Decodes")
                    .font(.headline)
                Text("Incoming FT8 / FT4 decodes on port \(appState.wsjtxListener.currentPort) will automatically appear here with real-time log-matching.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 12) {
                if !appState.wsjtxListener.state.isListening {
                    Button("Start WSJT-X Listener (Port 2237)") {
                        appState.wsjtxListener.start(port: 2237)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Load Live Sample Decodes") {
                    loadSampleDecodes()
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func loadSampleDecodes() {
        let samples: [WSJTXLiveDecode] = [
            WSJTXLiveDecode(sourceID: "WSJT-X", isNew: true, timeMillis: 120000, snr: 14, deltaTimeSec: 0.2, deltaFrequencyHz: 1420, mode: "FT8", message: "CQ 3D2RR RH42", lowConfidence: false, offAir: false, callerCallsign: "3D2RR", targetCallsign: "", grid: "RH42", report: ""),
            WSJTXLiveDecode(sourceID: "WSJT-X", isNew: true, timeMillis: 120000, snr: -4, deltaTimeSec: 0.1, deltaFrequencyHz: 1650, mode: "FT8", message: "CQ JA1ABC PM95", lowConfidence: false, offAir: false, callerCallsign: "JA1ABC", targetCallsign: "", grid: "PM95", report: ""),
            WSJTXLiveDecode(sourceID: "WSJT-X", isNew: true, timeMillis: 120000, snr: 6, deltaTimeSec: 0.3, deltaFrequencyHz: 980, mode: "FT8", message: "CQ W1AW FN31", lowConfidence: false, offAir: false, callerCallsign: "W1AW", targetCallsign: "", grid: "FN31", report: ""),
            WSJTXLiveDecode(sourceID: "WSJT-X", isNew: true, timeMillis: 120000, snr: -12, deltaTimeSec: 0.2, deltaFrequencyHz: 2100, mode: "FT8", message: "CQ VK3XYZ QF22", lowConfidence: false, offAir: false, callerCallsign: "VK3XYZ", targetCallsign: "", grid: "QF22", report: ""),
            WSJTXLiveDecode(sourceID: "WSJT-X", isNew: true, timeMillis: 120000, snr: -6, deltaTimeSec: 0.1, deltaFrequencyHz: 1200, mode: "FT8", message: "EP2AES DL1ABC JO50", lowConfidence: false, offAir: false, callerCallsign: "DL1ABC", targetCallsign: "EP2AES", grid: "JO50", report: ""),
            WSJTXLiveDecode(sourceID: "WSJT-X", isNew: true, timeMillis: 120000, snr: 8, deltaTimeSec: 0.4, deltaFrequencyHz: 1850, mode: "FT8", message: "CQ ZL1BQD RE78", lowConfidence: false, offAir: false, callerCallsign: "ZL1BQD", targetCallsign: "", grid: "RE78", report: "")
        ]
        roster.processDecodes(samples, activeBand: activeBand)
    }

    private func callStation(_ entry: DigitalRosterEntry) {
        if let raw = entry.rawDecode {
            appState.wsjtxListener.sendReply(to: raw)
        }
        if RigControlEngine.shared.isConnected {
            let dialHz = appState.wsjtxListener.lastStatus?.dialFrequencyHz ?? 14074000
            RigControlEngine.shared.tune(frequencyHz: dialHz, mode: "USB-D")
        }
    }

    private func syncContextAndRebuild() {
        roster.updateStationContext(
            callsign: appState.currentStationCallsign,
            grid: appState.activeStationProfile?.grid ?? ""
        )
        roster.rebuildLogCache(records: appState.qsoRecords)
    }

    // MARK: - Audio Settings Sheet

    private var audioSettingsSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Smart Audio Speech Alerts", systemImage: "speaker.wave.3.fill")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    showingAudioSettings = false
                }
                .buttonStyle(.borderedProminent)
            }

            Divider()

            Toggle("Enable Hands-Free Speech Alerts", isOn: $audioAlerts.isEnabled)
                .font(.subheadline)
                .fontWeight(.semibold)

            if audioAlerts.isEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ALERT TRIGGERS")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)

                    Toggle("⭐️ All-Time New DXCC (ATNO)", isOn: $audioAlerts.alertOnNewDXCC)
                    Toggle("🎯 New DXCC Entity on Current Band", isOn: $audioAlerts.alertOnNewBand)
                    Toggle("💠 New Maidenhead Grid Square", isOn: $audioAlerts.alertOnNewGrid)
                    Toggle("🔔 Station Calling Me Directly", isOn: $audioAlerts.alertOnDirectedToMe)
                    Toggle("Play Chime Before Speaking", isOn: $audioAlerts.playChimeFirst)
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 12) {
                    Text("VOICE & SPEED")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)

                    HStack {
                        Text("Speech Rate:")
                            .font(.caption)
                        Slider(value: $audioAlerts.speechRate, in: 0.3...0.7)
                        Text(String(format: "%.2fx", audioAlerts.speechRate / 0.5))
                            .font(.caption)
                            .frame(width: 40)
                    }

                    HStack {
                        Text("Volume:")
                            .font(.caption)
                        Slider(value: $audioAlerts.speechVolume, in: 0.2...1.0)
                        Text("\(Int(audioAlerts.speechVolume * 100))%")
                            .font(.caption)
                            .frame(width: 40)
                    }

                    Button {
                        audioAlerts.testVoiceAlert()
                    } label: {
                        HStack {
                            Image(systemName: "play.circle.fill")
                            Text("Test Voice Announcement")
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 450, height: 460)
    }

    // MARK: - Detail Sheet

    private func entryDetailSheet(_ entry: DigitalRosterEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(entry.countryInfo.flagEmoji)
                    .font(.system(size: 32))
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.callsign)
                        .font(.title2)
                        .bold()
                    Text(entry.countryInfo.entityName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Close") {
                    selectedEntryForDetail = nil
                }
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Triage Status:").foregroundColor(.secondary)
                    Text(entry.status.rawValue).fontWeight(.bold).foregroundColor(entry.status.badgeColor)
                }
                GridRow {
                    Text("Grid Square:").foregroundColor(.secondary)
                    Text(entry.grid.isEmpty ? "Unknown" : entry.grid).font(.system(.body, design: .monospaced))
                }
                if let dist = entry.distanceKm, let bearing = entry.bearingDeg {
                    GridRow {
                        Text("Distance / Beam:").foregroundColor(.secondary)
                        Text("\(Int(dist)) km · Bearing \(bearing)°")
                    }
                }
                GridRow {
                    Text("Signal Report:").foregroundColor(.secondary)
                    Text("\(entry.snrFormatted) at \(entry.deltaFrequencyFormatted)")
                }
                GridRow {
                    Text("Raw Message:").foregroundColor(.secondary)
                    Text(entry.message).font(.system(.caption, design: .monospaced))
                }
            }
            .font(.caption)

            Spacer()

            HStack {
                Button("Open in QRZ.com") {
                    if let url = URL(string: "https://www.qrz.com/db/\(entry.callsign)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
                Button("Reply in WSJT-X ⚡️") {
                    callStation(entry)
                    selectedEntryForDetail = nil
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420, height: 320)
    }
}
