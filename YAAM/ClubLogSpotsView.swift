//
//  ClubLogSpotsView.swift
//  YAAM
//

import SwiftUI
import WebKit

struct ClubLogSpotsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var spotsService = ClubLogSpotsService()
    
    @State private var filterBand: String = "All"
    @State private var filterMode: String = "All"
    @State private var filterText: String = ""

    // MARK: - Band Opportunity & Recommendation Model
    struct BandOpportunitySummary: Identifiable {
        var id: String { band }
        let band: String
        let totalSpots: Int
        let neededSpots: Int
        let dominantMode: String
        let score: Double
    }

    private var confirmedBandEntities: Set<String> {
        var confirmed = Set<String>()
        for r in appState.qsoRecords where r.isConfirmed {
            let country = r["COUNTRY"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let band = r["BAND"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !country.isEmpty && !band.isEmpty {
                confirmed.insert("\(country)|\(band)")
            }
        }
        return confirmed
    }

    private var bandOpportunities: [BandOpportunitySummary] {
        let confirmed = confirmedBandEntities
        let grouped = Dictionary(grouping: spotsService.spots) { $0.band.uppercased() }
            .filter { !$0.key.isEmpty && $0.key != "ALL" }

        return grouped.map { band, spots in
            let needed = spots.filter { spot in
                let country = spot.dxcc.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                return !country.isEmpty && !confirmed.contains("\(country)|\(band)")
            }.count

            let modeCounts = Dictionary(grouping: spots) { $0.mode.uppercased() }
                .mapValues { $0.count }
            let topMode = modeCounts.max(by: { $0.value < $1.value })?.key ?? "FT8"
            let score = Double(spots.count) + Double(needed) * 3.5

            return BandOpportunitySummary(
                band: band,
                totalSpots: spots.count,
                neededSpots: needed,
                dominantMode: topMode,
                score: score
            )
        }
        .sorted { $0.score > $1.score }
    }

    private var topRecommendedBand: BandOpportunitySummary? {
        bandOpportunities.first
    }

    private var availableBands: [String] {
        let bands = Set(spotsService.spots.map { $0.band.uppercased() }).filter { !$0.isEmpty }
        return ["All"] + bands.sorted()
    }

    private var availableSpecificModes: [String] {
        let modes = Set(spotsService.spots.map { $0.mode.uppercased() }).filter { !$0.isEmpty }
        return modes.sorted()
    }

    private var filteredSpots: [ClubLogSpotModel] {
        spotsService.spots.filter { spot in
            if filterBand != "All" && spot.band.uppercased() != filterBand.uppercased() {
                return false
            }
            if filterMode != "All" {
                switch filterMode {
                case "Digital":
                    if !spot.isDigital { return false }
                case "Phone", "Voice":
                    if !spot.isVoice { return false }
                case "CW":
                    if !spot.isCW { return false }
                default:
                    if spot.mode.uppercased() != filterMode.uppercased() {
                        return false
                    }
                }
            }
            if !filterText.isEmpty {
                let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return spot.callsign.lowercased().contains(query) ||
                    spot.dxcc.lowercased().contains(query) ||
                    spot.spotter.lowercased().contains(query) ||
                    spot.comment.lowercased().contains(query) ||
                    spot.mode.lowercased().contains(query)
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Toolbar Header
            HStack(spacing: 12) {
                Label("Club Log Personal Spots", systemImage: "person.3.fill")
                    .font(.headline)
                    .foregroundColor(.accentColor)

                Spacer()

                HStack(spacing: 8) {
                    Picker("Band", selection: $filterBand) {
                        ForEach(availableBands, id: \.self) { band in
                            Text(band == "All" ? "All Bands" : band).tag(band)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 85)

                    Picker("Mode", selection: $filterMode) {
                        Text("All Modes").tag("All")
                        Divider()
                        Text("⚡️ Digital (FT8, FT4...)").tag("Digital")
                        Text("FT8").tag("FT8")
                        Text("FT4").tag("FT4")
                        Text("RTTY").tag("RTTY")
                        Divider()
                        Text("📻 CW").tag("CW")
                        Divider()
                        Text("🎙 Phone (SSB, USB, LSB)").tag("Phone")
                        Text("SSB").tag("SSB")
                        Text("USB").tag("USB")
                        Text("LSB").tag("LSB")

                        let extraModes = availableSpecificModes.filter { !["CW", "FT8", "FT4", "RTTY", "SSB", "USB", "LSB"].contains($0) }
                        if !extraModes.isEmpty {
                            Divider()
                            ForEach(extraModes, id: \.self) { em in
                                Text(em).tag(em)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)

                    if filterBand != "All" || filterMode != "All" || !filterText.isEmpty {
                        Button {
                            filterBand = "All"
                            filterMode = "All"
                            filterText = ""
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("Reset all filters")
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        TextField("Filter spots...", text: $filterText)
                            .textFieldStyle(.plain)
                            .font(.caption)
                        if !filterText.isEmpty {
                            Button(action: { filterText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    .frame(width: 135)

                    Button {
                        Task {
                            await refreshSpots()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(spotsService.isLoading)

                    if ClubLogSessionStore.hasSavedSession() {
                        Button {
                            appState.showClubLogLoginSheet = true
                        } label: {
                            Label("2FA Active", systemImage: "checkmark.shield.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                        .help("Club Log 2FA session is active. Click to verify or manage session.")
                    } else {
                        Button {
                            appState.showClubLogLoginSheet = true
                        } label: {
                            Label("2FA Login", systemImage: "lock.shield.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                        .help("Open Club Log WebKit Authenticator to sign in with 2FA/MFA")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Warning / Credentials Banner
            if let errorMsg = spotsService.errorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(errorMsg)
                        .font(.caption)
                    Spacer()
                    Button("2FA / Web Authenticator") {
                        appState.showClubLogLoginSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .font(.caption)

                    Button("Open Settings") {
                        appState.selectedTab = 5
                        appState.operatorDeskSection = 5
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                Divider()
            }

            // Band Recommendation & Real-Time Propagation Alert Banner
            bandRecommendationBanner

            Divider()

            nativeSpotsTable
        }
        .task {
            if spotsService.spots.isEmpty {
                await refreshSpots()
            }
        }
        .sheet(isPresented: $appState.showClubLogLoginSheet, onDismiss: {
            Task {
                await refreshSpots()
            }
        }) {
            ClubLogLoginView()
                .environmentObject(appState)
        }
    }

    // MARK: - Band Recommendation & Activity HUD Banner
    @ViewBuilder
    private var bandRecommendationBanner: some View {
        if let top = topRecommendedBand, !spotsService.spots.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("BAND RECOMMENDATION & PROPAGATION ALERT")
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(.secondary)
                                .tracking(1.1)

                            if top.neededSpots > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 8))
                                    Text("\(top.neededSpots) NEEDED DXCC")
                                        .font(.system(size: 8.5, weight: .heavy))
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.green.opacity(0.18), in: Capsule())
                                .foregroundColor(.green)
                            }
                        }

                        HStack(spacing: 6) {
                            Text("Best Band to Operate Now:")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(top.band)
                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                .foregroundColor(.orange)
                            Text("· \(top.totalSpots) active spots · Peak Mode: \(top.dominantMode)")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }

                    Spacer()

                    if filterBand != top.band {
                        Button {
                            filterBand = top.band
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                Text("Filter to \(top.band)")
                            }
                            .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                    }
                }

                // Interactive band pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Button {
                            filterBand = "All"
                        } label: {
                            Text("All Bands (\(spotsService.spots.count))")
                                .font(.system(size: 10, weight: filterBand == "All" ? .bold : .medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(filterBand == "All" ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.12), in: Capsule())
                                .overlay(Capsule().stroke(filterBand == "All" ? Color.accentColor : Color.clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        ForEach(bandOpportunities) { opp in
                            Button {
                                filterBand = opp.band
                            } label: {
                                HStack(spacing: 4) {
                                    Text(opp.band)
                                        .fontWeight(.bold)
                                    Text("\(opp.totalSpots)")
                                        .font(.system(size: 9.5, design: .monospaced))
                                    if opp.neededSpots > 0 {
                                        Text("★ \(opp.neededSpots) new")
                                            .font(.system(size: 9, weight: .heavy))
                                            .foregroundColor(.green)
                                    }
                                }
                                .font(.system(size: 10))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(filterBand == opp.band ? Color.orange.opacity(0.2) : Color.gray.opacity(0.12), in: Capsule())
                                .overlay(Capsule().stroke(filterBand == opp.band ? Color.orange : Color.clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.orange.opacity(0.06))
            .overlay(Rectangle().frame(height: 1).foregroundColor(Color.orange.opacity(0.2)), alignment: .bottom)
        }
    }

    private var nativeSpotsTable: some View {
        Group {
            if spotsService.isLoading && spotsService.spots.isEmpty {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Fetching Personal Spots from Club Log...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if spotsService.spots.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 42))
                        .foregroundColor(.accentColor.opacity(0.8))
                    Text("No Personal Spots Found")
                        .font(.title3.weight(.bold))
                    Text("Ensure your Club Log credentials (Email & Application Password) are configured, or use the 2FA WebKit Authenticator to sign in directly.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)

                    HStack(spacing: 12) {
                        Button("Refresh Spots Now") {
                            Task { await refreshSpots() }
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            appState.showClubLogLoginSheet = true
                        } label: {
                            Label("Sign in with 2FA / Authenticator", systemImage: "lock.shield.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.blue)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("Showing \(filteredSpots.count) of \(spotsService.spots.count) spots")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)

                        if filterBand != "All" || filterMode != "All" || !filterText.isEmpty {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("Filtered: \(filterBand != "All" ? "Band: \(filterBand) " : "")\(filterMode != "All" ? "Mode: \(filterMode) " : "")\(filterText.isEmpty ? "" : "\"\(filterText)\"")")
                                .font(.caption2.bold())
                                .foregroundColor(.accentColor)
                        }

                        if let lastRefreshed = spotsService.lastRefreshed {
                            Text("• Refreshed: \(lastRefreshed.formatted(date: .omitted, time: .standard))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    Table(filteredSpots) {
                        TableColumn("Callsign") { spot in
                            HStack(spacing: 6) {
                                Text(flagForSpot(spot))
                                Text(spot.callsign)
                                    .fontWeight(.bold)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        .width(min: 120, ideal: 140)

                        TableColumn("Freq (MHz)") { spot in
                            Text(spot.frequency)
                                .font(.system(.body, design: .monospaced))
                        }
                        .width(min: 80, ideal: 100)

                        TableColumn("Band") { spot in
                            Text(spot.band)
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15))
                                .cornerRadius(4)
                        }
                        .width(min: 60, ideal: 75)

                        TableColumn("Mode") { spot in
                            let modeColor: Color = spot.isDigital ? .green : (spot.isCW ? .orange : .purple)
                            Text(spot.mode)
                                .font(.caption.bold())
                                .foregroundColor(modeColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(modeColor.opacity(0.12))
                                .cornerRadius(4)
                        }
                        .width(min: 65, ideal: 80)

                        TableColumn("DXCC Entity") { spot in
                            Text(spot.dxcc)
                                .font(.caption)
                        }
                        .width(min: 100, ideal: 140)

                        TableColumn("Spotter") { spot in
                            Text(spot.spotter)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .width(min: 80, ideal: 110)

                        TableColumn("Comment") { spot in
                            Text(spot.comment)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .width(min: 100, ideal: 160)

                        TableColumn("Status") { spot in
                            let isNeeded = spot.status.lowercased().contains("needed") || spot.status.lowercased().contains("most-wanted")
                            let isLoTW = spot.status.lowercased().contains("lotw")
                            let color: Color = isNeeded ? .orange : (isLoTW ? .blue : .green)
                            Text(spot.status)
                                .font(.caption2.bold())
                                .foregroundColor(color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(color.opacity(0.12))
                                .cornerRadius(4)
                        }
                        .width(min: 80, ideal: 110)

                        TableColumn("Time (UTC)") { spot in
                            Text(spot.timeStr)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .width(min: 70, ideal: 90)

                        TableColumn("Actions") { spot in
                            HStack(spacing: 6) {
                                Button {
                                    appState.selectedTab = 0
                                    appState.logSearchMode = .callsign
                                    appState.searchText = spot.callsign
                                } label: {
                                    Label("Find in Log", systemImage: "magnifyingglass")
                                        .font(.caption2)
                                }
                                .buttonStyle(.borderless)

                                if let freqDouble = Double(spot.frequency) {
                                    Button {
                                        let freqHz = UInt64(freqDouble * 1_000_000)
                                        appState.rigControlClient.setFrequencyHz(freqHz)
                                        if !spot.mode.isEmpty {
                                            appState.rigControlClient.setMode(spot.mode)
                                        }
                                    } label: {
                                        Label("Tune", systemImage: "radio")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        .width(min: 140, ideal: 170)
                    }
                }
            }
        }
    }

    private func flagForSpot(_ spot: ClubLogSpotModel) -> String {
        if !spot.dxcc.isEmpty {
            let flag = countryToFlag(spot.dxcc)
            if flag != "🌐" { return flag }
        }
        return countryToFlag(spot.callsign)
    }

    private func refreshSpots() async {
        let creds = appState.qslServiceCredentials(for: [.clubLog])
        await spotsService.fetchPersonalSpots(credentials: creds)
    }
}
