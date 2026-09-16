//
//  ClubLogLeagueView.swift
//  YAAM
//
//  Displays the Club Log DXCC League rankings
//

import SwiftUI
import AppKit

struct ClubLogLeagueView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedEntryForDetail: ClubLogLeagueEntry? = nil
    @State private var scrollToRank: Int? = nil

    private var filteredEntries: [ClubLogLeagueEntry] {
        let query = appState.clubLogLeagueSearchText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !query.isEmpty else { return appState.clubLogLeagueEntries }
        return appState.clubLogLeagueEntries.filter {
            $0.callsign.contains(query) || $0.countryName.uppercased().contains(query)
        }
    }

    private var userEntry: ClubLogLeagueEntry? {
        let call = appState.currentStationCallsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !call.isEmpty else { return nil }
        return appState.clubLogLeagueEntries.first { $0.callsign == call }
    }

    private var cutoffEntry: ClubLogLeagueEntry? {
        appState.clubLogLeagueEntries.last
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Controls & Filter Bar
            filterToolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.4))

            Divider()

            // 2. Metrics & Status Banner
            metricsBanner
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.2))

            Divider()

            // 3. Main Content
            if appState.isFetchingClubLogLeague && appState.clubLogLeagueEntries.isEmpty {
                loadingState
            } else if let err = appState.clubLogLeagueError, appState.clubLogLeagueEntries.isEmpty {
                errorState(err)
            } else if filteredEntries.isEmpty {
                emptyState
            } else {
                leagueTable
            }
        }
        .onAppear {
            if appState.clubLogLeagueEntries.isEmpty && !appState.isFetchingClubLogLeague {
                appState.fetchClubLogLeague()
            }
        }
        .sheet(item: $selectedEntryForDetail) { entry in
            ClubLogEntryDetailSheet(entry: entry)
        }
    }

    // MARK: - Toolbar

    private var filterToolbar: some View {
        HStack(spacing: 12) {
            // Mode Picker
            Picker("Mode", selection: $appState.selectedClubLogLeagueMode) {
                ForEach(ClubLogLeagueMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 380)
            .onChange(of: appState.selectedClubLogLeagueMode) { _, _ in
                appState.fetchClubLogLeague()
            }

            // QSL Picker
            Picker("QSL", selection: $appState.selectedClubLogLeagueQSL) {
                ForEach(ClubLogLeagueQSL.allCases) { qsl in
                    Label(qsl.title, systemImage: qsl.icon).tag(qsl)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .onChange(of: appState.selectedClubLogLeagueQSL) { _, _ in
                appState.fetchClubLogLeague()
            }

            // Date Picker
            Menu {
                ForEach(ClubLogLeagueDate.allCases) { d in
                    Button {
                        appState.selectedClubLogLeagueDate = d
                        appState.fetchClubLogLeague()
                    } label: {
                        if appState.selectedClubLogLeagueDate == d {
                            Label(d.title, systemImage: "checkmark")
                        } else {
                            Text(d.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(appState.selectedClubLogLeagueDate.title)
                }
                .font(.caption.weight(.semibold))
            }
            .menuStyle(.borderedButton)
            .frame(width: 120)

            Spacer()

            // Search Box
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Filter callsign / DXCC...", text: $appState.clubLogLeagueSearchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !appState.clubLogLeagueSearchText.isEmpty {
                    Button {
                        appState.clubLogLeagueSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
            .frame(width: 200)

            // Refresh Button
            Button {
                appState.fetchClubLogLeague()
            } label: {
                if appState.isFetchingClubLogLeague {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(appState.isFetchingClubLogLeague)
        }
    }

    // MARK: - Metrics Banner

    private var metricsBanner: some View {
        HStack(spacing: 16) {
            // #1 Leader
            if let leader = appState.clubLogLeagueEntries.first {
                metricCard(
                    title: "Leader (#1)",
                    value: "\(leader.flagEmoji) \(leader.callsign)",
                    subvalue: "\(leader.slots) slots · \(leader.dxccs) DXCCs",
                    icon: "trophy.fill",
                    color: .yellow
                )
            }

            // Total Ranked
            metricCard(
                title: "Total Ranked",
                value: "\(appState.clubLogLeagueEntries.count)",
                subvalue: "Club Log DXCC League",
                icon: "person.3.fill",
                color: .blue
            )

            // Cutoff (#2000)
            if let cutoff = cutoffEntry {
                metricCard(
                    title: "Cutoff (#\(cutoff.rank))",
                    value: "\(cutoff.slots) slots",
                    subvalue: "\(cutoff.dxccs) DXCCs (\(cutoff.callsign))",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .orange
                )
            }

            // User Station Standing
            if let user = userEntry {
                metricCard(
                    title: "Your Station",
                    value: "#\(user.rank) \(user.callsign)",
                    subvalue: "\(user.slots) slots · \(user.dxccs) DXCCs",
                    icon: "star.fill",
                    color: .green
                )
            } else {
                let station = appState.currentStationCallsign.isEmpty ? "My Station" : appState.currentStationCallsign
                metricCard(
                    title: "Your Station",
                    value: station,
                    subvalue: cutoffEntry != nil ? "Outside Top 2000" : "Not ranked",
                    icon: "antenna.radiowaves.left.and.right",
                    color: .secondary
                )
            }

            Spacer()
        }
    }

    private func metricCard(title: String, value: String, subvalue: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(subvalue)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.2), lineWidth: 0.8))
    }

    // MARK: - Table

    private var leagueTable: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // Table Header
                HStack(spacing: 0) {
                    Text("Rank").font(.caption.bold()).frame(width: 60, alignment: .center)
                    Text("Callsign").font(.caption.bold()).frame(width: 140, alignment: .leading).padding(.leading, 8)
                    Text("DXCC Entities").font(.caption.bold()).frame(width: 110, alignment: .center)
                    Text("Challenge Slots").font(.caption.bold()).frame(width: 120, alignment: .center)
                    Text("Top Bands").font(.caption.bold()).frame(width: 240, alignment: .leading).padding(.leading, 12)
                    Spacer()
                    Text("Actions").font(.caption.bold()).frame(width: 110, alignment: .trailing).padding(.trailing, 16)
                }
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.85))

                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            rowView(for: entry)
                                .id(entry.rank)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(for entry: ClubLogLeagueEntry) -> some View {
        let isUser = entry.callsign == appState.currentStationCallsign.uppercased()

        HStack(spacing: 0) {
            // Rank
            ZStack {
                if entry.rank == 1 {
                    Text("🥇").font(.subheadline)
                } else if entry.rank == 2 {
                    Text("🥈").font(.subheadline)
                } else if entry.rank == 3 {
                    Text("🥉").font(.subheadline)
                } else {
                    Text("#\(entry.rank)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(isUser ? .green : .secondary)
                }
            }
            .frame(width: 60, alignment: .center)

            // Callsign + Flag + Country
            HStack(spacing: 6) {
                Text(entry.flagEmoji).font(.body)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.callsign)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(isUser ? .green : .primary)
                    Text(entry.countryName)
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 140, alignment: .leading)
            .padding(.leading, 8)

            // DXCC Entities
            HStack(spacing: 4) {
                Text("\(entry.dxccs)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(entry.dxccs >= 331 ? .yellow : .primary)
                Text("/ 340")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
            }
            .frame(width: 110, alignment: .center)

            // Challenge Slots
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.pink)
                Text("\(entry.slots)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.pink)
            }
            .frame(width: 120, alignment: .center)

            // Top Bands Preview (160, 80, 40, 20, 15, 10, 6)
            HStack(spacing: 4) {
                ForEach(["160", "80", "40", "20", "15", "10", "6"], id: \.self) { b in
                    let count = entry.bandCount(b)
                    VStack(spacing: 1) {
                        Text("\(b)m")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(.secondary)
                        Text(count > 0 ? "\(count)" : "-")
                            .font(.system(size: 9, weight: count >= 100 ? .bold : .regular, design: .monospaced))
                            .foregroundColor(count >= 100 ? .green : (count > 0 ? .primary : Color.secondary.opacity(0.4)))
                    }
                    .frame(width: 30)
                    .padding(.vertical, 2)
                    .background(count >= 100 ? Color.green.opacity(0.12) : Color.secondary.opacity(0.06))
                    .cornerRadius(4)
                }
            }
            .frame(width: 240, alignment: .leading)
            .padding(.leading, 12)

            Spacer()

            // Actions
            HStack(spacing: 6) {
                // Detail Button
                Button {
                    selectedEntryForDetail = entry
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("View full 16-band breakdown")

                // Compare VS Button
                Button {
                    let target = entry.callsign
                    appState.leaderboardSearchCallsign = target
                    appState.nationalLeaderboardTab = .headToHead
                    appState.fetchQRZLeaderboardComparisons(for: [target])
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "swords")
                        Text("VS")
                    }
                    .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.orange)
                .help("Compare head-to-head with this operator")
            }
            .frame(width: 110, alignment: .trailing)
            .padding(.trailing, 16)
        }
        .padding(.vertical, 6)
        .background(isUser ? Color.green.opacity(0.10) : Color.clear)
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.3)
            Text("Fetching Club Log DXCC League rankings...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            Text("Failed to load Club Log League")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                appState.fetchClubLogLeague()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No matching callsigns found in Top 2000")
                .font(.headline)
            Button("Clear Search") {
                appState.clubLogLeagueSearchText = ""
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Detail Sheet for Operator's 16 Bands

struct ClubLogEntryDetailSheet: View {
    let entry: ClubLogLeagueEntry
    @Environment(\.dismiss) private var dismiss

    private let allBands = [
        ("160m", "160", "Topband"),
        ("80m",  "80",  "HF"),
        ("60m",  "60",  "HF"),
        ("40m",  "40",  "HF"),
        ("30m",  "30",  "WARC"),
        ("20m",  "20",  "HF"),
        ("17m",  "17",  "WARC"),
        ("15m",  "15",  "HF"),
        ("12m",  "12",  "WARC"),
        ("10m",  "10",  "HF"),
        ("6m",   "6",   "VHF"),
        ("4m",   "4",   "VHF"),
        ("2m",   "2",   "VHF"),
        ("70cm", "70",  "UHF"),
        ("23cm", "23",  "SHF"),
        ("13cm", "13",  "SHF")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.orange.opacity(0.18)).frame(width: 48, height: 48)
                    Text(entry.flagEmoji).font(.system(size: 26))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.callsign)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                        Text("#\(entry.rank)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                    Text("\(entry.countryName) · \(entry.slots) Challenge Slots · \(entry.dxccs) DXCCs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }

            Divider()

            Text("Band-by-Band Entities Breakdown (16 Bands)")
                .font(.subheadline.bold())

            // 16 Bands Grid
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 10)], spacing: 10) {
                ForEach(allBands, id: \.0) { bandLabel, key, cls in
                    let count = entry.bandCount(key)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(bandLabel)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                            Spacer()
                            Text(cls)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text("\(count)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(count >= 100 ? .green : (count > 0 ? .primary : .secondary))
                            Text("entities")
                                .font(.system(size: 8.5))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .background(count >= 100 ? Color.green.opacity(0.08) : Color(NSColor.controlBackgroundColor).opacity(0.4))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(count >= 100 ? Color.green.opacity(0.3) : Color.secondary.opacity(0.15)))
                }
            }
        }
        .padding(20)
        .frame(width: 540)
    }
}
