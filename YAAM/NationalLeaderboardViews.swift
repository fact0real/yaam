//
//  NationalLeaderboardViews.swift
//  YAAM
//
//  Created by factoreal on 9/14/26.
//

import SwiftUI
import AppKit

// MARK: - Inspecting Station Item Wrapper
struct InspectingStationItem: Identifiable {
    var id: String { callsign }
    let callsign: String
}

// MARK: - Flag Helper
func flagForCountryIso(_ countryIso: String) -> String {
    let lower = countryIso.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    switch lower {
    case "ir": return "🇮🇷"
    case "ma": return "🇲🇦"
    case "us": return "🇺🇸"
    case "de": return "🇩🇪"
    case "jp": return "🇯🇵"
    case "gb": return "🇬🇧"
    case "it": return "🇮🇹"
    case "es": return "🇪🇸"
    case "fr": return "🇫🇷"
    case "br": return "🇧🇷"
    case "ru": return "🇷🇺"
    case "ca": return "🇨🇦"
    case "au": return "🇦🇺"
    case "pl": return "🇵🇱"
    case "ua": return "🇺🇦"
    case "nl": return "🇳🇱"
    case "se": return "🇸🇪"
    case "ch": return "🇨🇭"
    case "at": return "🇦🇹"
    case "cz": return "🇨🇿"
    case "hu": return "🇭🇺"
    case "ar": return "🇦🇷"
    case "cl": return "🇨🇱"
    case "kr": return "🇰🇷"
    case "in": return "🇮🇳"
    case "za": return "🇿🇦"
    case "tr": return "🇹🇷"
    case "gr": return "🇬🇷"
    case "ro": return "🇷🇴"
    case "bg": return "🇧🇬"
    case "rs": return "🇷🇸"
    case "hr": return "🇭🇷"
    case "fi": return "🇫🇮"
    case "no": return "🇳🇴"
    case "dk": return "🇩🇰"
    case "be": return "🇧🇪"
    case "pt": return "🇵🇹"
    case "mx": return "🇲🇽"
    default:
        guard lower.count == 2 else { return "🌐" }
        let base: UInt32 = 127397
        var s = ""
        for v in lower.uppercased().unicodeScalars {
            guard let scalar = UnicodeScalar(base + v.value) else { return "🌐" }
            s.unicodeScalars.append(scalar)
        }
        return s.isEmpty ? "🌐" : s
    }
}

// MARK: - Quick Country Pills View
struct QuickCountryPillsView: View {
    @EnvironmentObject var appState: AppState

    struct QuickCountry: Identifiable {
        var id: String { iso }
        let iso: String
        let name: String
        let flag: String
    }

    private let quickCountries: [QuickCountry] = [
        QuickCountry(iso: "ir", name: "Iran", flag: "🇮🇷"),
        QuickCountry(iso: "ma", name: "Morocco", flag: "🇲🇦"),
        QuickCountry(iso: "us", name: "USA", flag: "🇺🇸"),
        QuickCountry(iso: "de", name: "Germany", flag: "🇩🇪"),
        QuickCountry(iso: "jp", name: "Japan", flag: "🇯🇵"),
        QuickCountry(iso: "gb", name: "UK", flag: "🇬🇧"),
        QuickCountry(iso: "it", name: "Italy", flag: "🇮🇹"),
        QuickCountry(iso: "es", name: "Spain", flag: "🇪🇸"),
        QuickCountry(iso: "fr", name: "France", flag: "🇫🇷"),
        QuickCountry(iso: "br", name: "Brazil", flag: "🇧🇷"),
        QuickCountry(iso: "ru", name: "Russia", flag: "🇷🇺"),
        QuickCountry(iso: "ca", name: "Canada", flag: "🇨🇦"),
        QuickCountry(iso: "au", name: "Australia", flag: "🇦🇺"),
        QuickCountry(iso: "pl", name: "Poland", flag: "🇵🇱")
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickCountries) { item in
                    let isSelected = appState.selectedNationalCountryIso.lowercased() == item.iso.lowercased()
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.selectedNationalCountryIso = item.iso
                            appState.fetchNationalLeaderboard(countryIso: item.iso)
                        }
                    }) {
                        HStack(spacing: 5) {
                            Text(item.flag)
                                .font(.system(size: 14))
                            Text(item.name)
                                .font(.caption)
                                .fontWeight(isSelected ? .bold : .medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.cyan.opacity(0.22) : Color(NSColor.controlBackgroundColor))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? Color.cyan : Color.secondary.opacity(0.25), lineWidth: isSelected ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
    }
}

// MARK: - World Champions Showcase View
struct WorldChampionsShowcaseView: View {
    @EnvironmentObject var appState: AppState
    var onInspectStation: ((String) -> Void)?
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.yellow)
                    Text("WORLD CHAMPIONS SHOWCASE")
                        .font(.caption)
                        .fontWeight(.heavy)
                        .foregroundColor(.yellow)
                        .kerning(1.0)
                }

                Spacer()

                if appState.isFetchingWorldChampions {
                    ProgressView().controlSize(.small)
                }

                Button(action: {
                    withAnimation(.spring()) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Hide" : "Show All (\(appState.worldChampions.count))")
                            .font(.caption2)
                            .fontWeight(.semibold)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.borderless)
            }

            if isExpanded {
                if appState.worldChampions.isEmpty {
                    if appState.isFetchingWorldChampions {
                        HStack {
                            Spacer()
                            ProgressView("Loading global champions...")
                                .font(.caption)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    } else {
                        Text("World champions data will be populated once loaded.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(appState.worldChampions) { champ in
                                WorldChampionCard(champ: champ, onInspectStation: onInspectStation)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.7))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.3), lineWidth: 1))
        )
        .onAppear {
            if appState.worldChampions.isEmpty && !appState.isFetchingWorldChampions {
                appState.fetchWorldChampions()
            }
        }
    }
}

struct WorldChampionCard: View {
    @EnvironmentObject var appState: AppState
    let champ: QRZWorldChampionItem
    var onInspectStation: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(flagForCountryIso(champ.countryIso))
                    .font(.system(size: 16))
                Text(champ.countryName)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 4) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.yellow)
                Text(champ.callsign)
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundColor(.primary)
            }

            Text("\(champ.formattedScore) QSOs")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(.cyan)

            HStack(spacing: 6) {
                Button("Inspect") {
                    onInspectStation?(champ.callsign)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("Leaderboard") {
                    withAnimation {
                        appState.selectedNationalCountryIso = champ.countryIso
                        appState.fetchNationalLeaderboard(countryIso: champ.countryIso)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
            .padding(.top, 2)
        }
        .padding(10)
        .frame(width: 175)
        .background(Color(NSColor.textBackgroundColor).opacity(0.6))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - National Leaderboard Container View
struct NationalLeaderboardContainerView: View {
    @EnvironmentObject var appState: AppState
    @State private var inspectingStation: InspectingStationItem? = nil

    private let fallbackCountries: [(iso: String, name: String)] = [
        ("ir", "Iran (EP)"),
        ("ma", "Morocco (CN)"),
        ("us", "United States (W/K/N/A)"),
        ("de", "Germany (DL/DK)"),
        ("jp", "Japan (JA/JH)"),
        ("gb", "United Kingdom (G/M)"),
        ("it", "Italy (I/IK)"),
        ("fr", "France (F)"),
        ("es", "Spain (EA)"),
        ("br", "Brazil (PY)"),
        ("ru", "Russia (RA/UA)")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Quick Country Select Horizontal Pills
            QuickCountryPillsView()

            Divider()

            // Filter & Depth Bar
            HStack(spacing: 14) {
                // Country Picker
                HStack(spacing: 6) {
                    Image(systemName: "flag.fill")
                        .foregroundColor(.cyan)
                    Text("Country:")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)

                    Picker("", selection: $appState.selectedNationalCountryIso) {
                        if !appState.qrzRankCountries.isEmpty {
                            ForEach(appState.qrzRankCountries) { c in
                                Text("\(c.name) (\(c.iso.uppercased())) · \(c.stationCount ?? 0) stns")
                                    .tag(c.iso.lowercased())
                            }
                        } else {
                            ForEach(fallbackCountries, id: \.iso) { c in
                                Text(c.name).tag(c.iso)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                    .onChange(of: appState.selectedNationalCountryIso) { newIso in
                        appState.fetchNationalLeaderboard(countryIso: newIso)
                    }
                }

                Divider().frame(height: 20)

                // Depth Switcher (Top 10 | Top 25 | Top 50)
                HStack(spacing: 6) {
                    Text("Depth:")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)

                    Picker("", selection: $appState.selectedNationalDepth) {
                        Text("Top 10").tag(10)
                        Text("Top 25").tag(25)
                        Text("Top 50").tag(50)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }

                Divider().frame(height: 20)

                // Category Switcher
                Picker("Category", selection: $appState.selectedNationalCategory) {
                    Text("QSO Volume").tag("qso")
                    Text("DXCC Countries").tag("countries")
                    Text("Band-Countries").tag("band")
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                .onChange(of: appState.selectedNationalCategory) { newCat in
                    appState.fetchNationalLeaderboard(category: newCat)
                }

                Spacer()

                if appState.isFetchingNationalLeaderboard {
                    ProgressView().controlSize(.small)
                }

                Button(action: {
                    appState.fetchNationalLeaderboard()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(appState.isFetchingNationalLeaderboard)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Main Content Area
            if appState.isFetchingNationalLeaderboard && appState.nationalLeaderboard == nil {
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.3)
                    Text("Loading national rankings...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            } else if let data = appState.nationalLeaderboard, !data.leaderboard.isEmpty {
                let filteredItems = Array(data.leaderboard.prefix(appState.selectedNationalDepth))

                ScrollView {
                    LazyVStack(spacing: 20) {
                        // World Champions Showcase Section
                        WorldChampionsShowcaseView(onInspectStation: { call in
                            inspectingStation = InspectingStationItem(callsign: call)
                        })
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                        // Country Banner
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(data.countryName.uppercased()) HALL OF FAME")
                                    .font(.caption)
                                    .fontWeight(.heavy)
                                    .foregroundColor(.cyan)
                                    .kerning(1.2)

                                HStack(spacing: 8) {
                                    Text("\(data.totalStations) Ranked Stations")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Text("· Top \(min(appState.selectedNationalDepth, data.totalStations)) Displayed")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 24)

                        // Top 3 Podium Cards
                        let top3 = Array(filteredItems.prefix(3))
                        if !top3.isEmpty {
                            PodiumSectionView(top3: top3, category: data.category, onInspectStation: { call in
                                inspectingStation = InspectingStationItem(callsign: call)
                            })
                            .padding(.horizontal, 24)
                        }

                        // Standings Table (Items past podium up to selectedNationalDepth)
                        let tableItems = filteredItems.count > 3 ? Array(filteredItems.dropFirst(3)) : []
                        if !tableItems.isEmpty {
                            NationalTableView(items: tableItems, category: data.category, onInspectStation: { call in
                                inspectingStation = InspectingStationItem(callsign: call)
                            })
                            .padding(.horizontal, 24)
                            .padding(.bottom, 30)
                        }
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "flag.slash")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                    Text("No national rankings available yet for this country.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Button("Load Iranian (EP) Standings") {
                        appState.selectedNationalCountryIso = "ir"
                        appState.fetchNationalLeaderboard(countryIso: "ir")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .sheet(item: $inspectingStation) { item in
            StationAnalysisSheetView(targetCallsign: item.callsign, countryIso: appState.selectedNationalCountryIso)
                .environmentObject(appState)
        }
        .onAppear {
            appState.fetchQRZRankCountries()
            if appState.nationalLeaderboard == nil {
                appState.fetchNationalLeaderboard()
            }
        }
    }
}

// MARK: - Podium Section View
struct PodiumSectionView: View {
    @EnvironmentObject var appState: AppState
    let top3: [QRZCountryLeaderboardItem]
    let category: String
    var onInspectStation: ((String) -> Void)?

    var body: some View {
        HStack(spacing: 16) {
            // Rank 2 (Silver)
            if top3.count > 1 {
                PodiumCard(item: top3[1], medal: "🥈 #2 Silver", color: .gray, onInspectStation: onInspectStation)
            }

            // Rank 1 (Gold)
            if !top3.isEmpty {
                PodiumCard(item: top3[0], medal: "👑 #1 Champion", color: .yellow, isChampion: true, onInspectStation: onInspectStation)
                    .scaleEffect(1.04)
            }

            // Rank 3 (Bronze)
            if top3.count > 2 {
                PodiumCard(item: top3[2], medal: "🥉 #3 Bronze", color: .brown, onInspectStation: onInspectStation)
            }
        }
        .padding(.vertical, 8)
    }
}

struct PodiumCard: View {
    @EnvironmentObject var appState: AppState
    let item: QRZCountryLeaderboardItem
    let medal: String
    let color: Color
    var isChampion: Bool = false
    var onInspectStation: ((String) -> Void)?

    private var scoreTitle: String {
        "\(item.score.formatted())"
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(medal)
                .font(.caption)
                .fontWeight(.heavy)
                .foregroundColor(color)
                .textCase(.uppercase)

            Button(action: {
                onInspectStation?(item.callsign)
            }) {
                Text(item.callsign)
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .help("Click to view quick station analysis")

            Text(scoreTitle)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundColor(.cyan)

            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text("Countries")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(item.scoreCountries ?? 0)")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                Divider().frame(height: 18)
                VStack(spacing: 2) {
                    Text("Bands")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(item.scoreBand ?? 0)")
                        .font(.caption)
                        .fontWeight(.bold)
                }
            }

            Button(action: {
                onInspectStation?(item.callsign)
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Quick Analysis")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isChampion ? Color.yellow.opacity(0.8) : color.opacity(0.4), lineWidth: isChampion ? 2 : 1.5)
                )
                .shadow(color: isChampion ? Color.yellow.opacity(0.25) : color.opacity(0.12), radius: isChampion ? 12 : 8)
        )
    }
}

// MARK: - National Table View
struct NationalTableView: View {
    @EnvironmentObject var appState: AppState
    let items: [QRZCountryLeaderboardItem]
    let category: String
    var onInspectStation: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Table Header
            HStack {
                Text("# Rank")
                    .frame(width: 75, alignment: .leading)
                Text("Callsign")
                    .frame(width: 140, alignment: .leading)
                Text("Score")
                    .frame(width: 110, alignment: .trailing)
                Text("Countries")
                    .frame(width: 90, alignment: .trailing)
                Text("Bands")
                    .frame(width: 90, alignment: .trailing)
                Text("Global Rank")
                    .frame(width: 100, alignment: .trailing)
                Spacer()
                Text("Action")
                    .frame(width: 90, alignment: .trailing)
            }
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Rows
            ForEach(items) { item in
                let isTop10 = item.rank <= 10
                HStack {
                    HStack(spacing: 4) {
                        Text("#\(item.rank)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(isTop10 ? .cyan : .secondary)

                        if isTop10 {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.yellow)
                        }
                    }
                    .frame(width: 75, alignment: .leading)

                    Button(action: {
                        onInspectStation?(item.callsign)
                    }) {
                        Text(item.callsign)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 140, alignment: .leading)

                    Text(item.score.formatted())
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                        .frame(width: 110, alignment: .trailing)

                    Text("\(item.scoreCountries ?? 0)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 90, alignment: .trailing)

                    Text("\(item.scoreBand ?? 0)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 90, alignment: .trailing)

                    Text(item.rankQso.map { "#\($0.formatted())" } ?? "-")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 100, alignment: .trailing)

                    Spacer()

                    Button(action: {
                        onInspectStation?(item.callsign)
                    }) {
                        Text("Analyze")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .frame(width: 90, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Smart Rank Climb Roadmap View
struct RankRoadmapContainerView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Header & Target Operator
                let targetCallsign = appState.leaderboardSearchCallsign.isEmpty
                    ? appState.currentStationCallsign
                    : (appState.leaderboardSearchCallsign.components(separatedBy: [",", " ", ";"]).first ?? appState.currentStationCallsign)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("OPERATOR ROADMAP & AI INSIGHTS")
                                .font(.caption)
                                .fontWeight(.heavy)
                                .foregroundColor(.orange)
                                .kerning(1.2)

                            if targetCallsign.uppercased() == appState.currentStationCallsign.uppercased() {
                                Text("YOUR STATION")
                                    .font(.system(size: 9, weight: .black))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue, in: Capsule())
                                    .foregroundColor(.white)
                            }
                        }

                        Text(targetCallsign.uppercased())
                            .font(.system(size: 28, weight: .black, design: .monospaced))
                    }

                    Spacer()

                    if appState.isFetchingStationAnalysis {
                        ProgressView().controlSize(.small)
                    }

                    Button(action: {
                        appState.fetchStationAnalysis(callsign: targetCallsign)
                    }) {
                        Label("Re-Analyze", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.isFetchingStationAnalysis)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                if let analysis = appState.stationAnalysis {
                    // National Standing Card
                    if let ns = analysis.nationalStanding {
                        NationalStandingCardView(standing: ns, countryName: analysis.countryName, countryIso: analysis.countryIso)
                            .padding(.horizontal, 24)
                    }

                    // Badges Row
                    if !analysis.badges.isEmpty {
                        BadgesShowcaseView(badges: analysis.badges)
                            .padding(.horizontal, 24)
                    }

                    // Strategic Rank Elevation Plan Card
                    if let rec = analysis.recommendations {
                        StrategicPlanCardView(recommendations: rec)
                            .padding(.horizontal, 24)
                    }

                    // Confirmation Credit Intelligence Integration Card
                    PendingConfirmationROICardView(recommendations: analysis.recommendations)
                        .padding(.horizontal, 24)

                    // Peer Rivals Table
                    if !analysis.peerRivals.isEmpty {
                        PeerRivalsTableView(rivals: analysis.peerRivals, currentCallsign: analysis.callsign)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 30)
                    }
                } else if appState.isFetchingStationAnalysis {
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.2)
                        Text("Analyzing operator metrics, badges, and national standing...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(height: 200)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No station analysis loaded yet.")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Button("Analyze \(targetCallsign)") {
                            appState.fetchStationAnalysis(callsign: targetCallsign)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(height: 200)
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            let call = appState.leaderboardSearchCallsign.isEmpty
                ? appState.currentStationCallsign
                : (appState.leaderboardSearchCallsign.components(separatedBy: [",", " ", ";"]).first ?? appState.currentStationCallsign)
            if appState.stationAnalysis == nil {
                appState.fetchStationAnalysis(callsign: call)
            }
        }
    }
}

// MARK: - National Standing Card
struct NationalStandingCardView: View {
    let standing: QRZNationalStanding
    let countryName: String
    let countryIso: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NATIONAL STANDINGS")
                        .font(.caption2)
                        .fontWeight(.heavy)
                        .foregroundColor(.indigo)
                    Text("\(countryName) (\(countryIso.uppercased()))")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                Spacer()
                Text("\(standing.totalCountryStations ?? 0) stations tracked")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 14) {
                StandingMetricPill(
                    label: "QSO National Rank",
                    value: standing.countryRankQso.map { "#\($0)" } ?? "N/A",
                    icon: "antenna.radiowaves.left.and.right",
                    color: .indigo
                )
                StandingMetricPill(
                    label: "DXCC National Rank",
                    value: standing.countryRankDxcc.map { "#\($0)" } ?? "N/A",
                    icon: "globe.americas.fill",
                    color: .cyan
                )
                StandingMetricPill(
                    label: "Band National Rank",
                    value: standing.countryRankBand.map { "#\($0)" } ?? "N/A",
                    icon: "waveform.path.ecg",
                    color: .green
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.indigo.opacity(0.3), lineWidth: 1))
        )
    }
}

struct StandingMetricPill: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 20, weight: .black, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
        .cornerRadius(10)
    }
}

// MARK: - Badges Showcase
struct BadgesShowcaseView: View {
    let badges: [QRZStationBadge]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HONORS & BADGES")
                .font(.caption2)
                .fontWeight(.heavy)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(badges) { badge in
                        HStack(spacing: 6) {
                            Text(badge.icon)
                            Text(badge.label)
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(badgeColor(badge.color).opacity(0.15))
                        .overlay(Capsule().stroke(badgeColor(badge.color).opacity(0.4), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func badgeColor(_ color: String) -> Color {
        switch color {
        case "amber": return .orange
        case "emerald": return .green
        case "purple": return .purple
        default: return .cyan
        }
    }
}

// MARK: - Strategic Plan Card
struct StrategicPlanCardView: View {
    let recommendations: QRZStationRecommendations

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "target")
                    .foregroundColor(.cyan)
                Text(recommendations.title ?? "Strategic Rank Elevation Plan")
                    .font(.headline)
                    .fontWeight(.bold)
            }

            if let text = recommendations.text {
                Text(text)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
            }

            HStack(spacing: 14) {
                // Next Step Ahead
                if let next = recommendations.immediateNextTarget {
                    MilestoneBox(
                        title: "Next Rank Step",
                        subtitle: "+\(next.gapQso.formatted()) QSOs to surpass \(next.callsign)",
                        badge: next.rankQso.map { "Target: #\($0)" } ?? "",
                        icon: "bolt.fill",
                        color: .orange
                    )
                }

                // National Champion
                if let champ = recommendations.nationalChampion {
                    MilestoneBox(
                        title: "National Champion",
                        subtitle: "\(champ.callsign) (\(champ.scoreQso.formatted()) QSOs)",
                        badge: "Gap: \(champ.gapToChamp.formatted())",
                        icon: "crown.fill",
                        color: .purple
                    )
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
        )
    }
}

struct MilestoneBox: View {
    let title: String
    let subtitle: String
    let badge: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.caption2)
                        .fontWeight(.heavy)
                        .foregroundColor(color)
                    Spacer()
                    if !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.textBackgroundColor).opacity(0.5))
        .cornerRadius(10)
    }
}

// MARK: - Confirmation Credit ROI Card
struct PendingConfirmationROICardView: View {
    @EnvironmentObject var appState: AppState
    let recommendations: QRZStationRecommendations?

    private var unconfirmedCount: Int {
        appState.qsoRecords.filter { !$0.isConfirmed }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
                Text("YAAM Confirmation Credit Intelligence")
                    .font(.subheadline)
                    .fontWeight(.bold)
                Spacer()
                Text("\(unconfirmedCount) Unconfirmed in Log")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let next = recommendations?.immediateNextTarget, unconfirmedCount > 0 {
                let canSurpass = unconfirmedCount >= next.gapQso
                HStack(spacing: 12) {
                    Image(systemName: canSurpass ? "sparkles" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(canSurpass ? .green : .orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(canSurpass
                             ? "You have \(unconfirmedCount) pending QSOs in YAAM! Getting \(next.gapQso) confirmed on QRZ will immediately elevate your rank past \(next.callsign)!"
                             : "You have \(unconfirmedCount) pending confirmations. Confirming them will close the gap to \(next.callsign) from \(next.gapQso) down to \(max(0, next.gapQso - unconfirmedCount)) QSOs!"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Keep logging and submitting QSLs via LoTW and QRZ Logbook to maintain high confirmation ROI and secure higher standings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.green.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.green.opacity(0.2), lineWidth: 1))
        )
    }
}

// MARK: - Peer Rivals Table
struct PeerRivalsTableView: View {
    @EnvironmentObject var appState: AppState
    let rivals: [QRZPeerRival]
    let currentCallsign: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "swords")
                    .foregroundColor(.orange)
                Text("Direct Peer Rivals (Closest Competitors)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                Spacer()
                Text("Head-to-Head Standing")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Header
            HStack {
                Text("Callsign")
                    .frame(width: 140, alignment: .leading)
                Text("QSOs")
                    .frame(width: 100, alignment: .trailing)
                Text("Countries")
                    .frame(width: 90, alignment: .trailing)
                Text("Bands")
                    .frame(width: 90, alignment: .trailing)
                Text("World Rank")
                    .frame(width: 100, alignment: .trailing)
                Spacer()
                Text("Action")
                    .frame(width: 80, alignment: .trailing)
            }
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            ForEach(rivals) { rival in
                let isCurrent = rival.callsign.uppercased() == currentCallsign.uppercased()
                HStack {
                    HStack(spacing: 6) {
                        Text(rival.callsign)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(isCurrent ? .indigo : .primary)
                        if isCurrent {
                            Text("YOU")
                                .font(.system(size: 8, weight: .black))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.indigo, in: Capsule())
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 140, alignment: .leading)

                    Text(rival.scoreQso.map { "\($0.formatted())" } ?? "-")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                        .frame(width: 100, alignment: .trailing)

                    Text("\(rival.scoreCountries ?? 0)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 90, alignment: .trailing)

                    Text("\(rival.scoreBand ?? 0)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 90, alignment: .trailing)

                    Text(rival.rankQso.map { "#\($0.formatted())" } ?? "-")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 100, alignment: .trailing)

                    Spacer()

                    if !isCurrent {
                        Button("Compare") {
                            appState.leaderboardSearchCallsign = "\(currentCallsign), \(rival.callsign)"
                            appState.nationalLeaderboardTab = .headToHead
                            appState.fetchQRZLeaderboardComparisons(for: [currentCallsign, rival.callsign])
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .frame(width: 80, alignment: .trailing)
                    } else {
                        Spacer().frame(width: 80)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isCurrent ? Color.indigo.opacity(0.08) : Color.clear)

                Divider()
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Station Quick Analysis Sheet View
struct StationAnalysisSheetView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let targetCallsign: String
    let countryIso: String?

    @State private var simulatedDeltaQSO: Int = 25
    @State private var customDeltaText: String = "25"

    private var unconfirmedCount: Int {
        appState.qsoRecords.filter { !$0.isConfirmed }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sheet Header Bar
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.title2)
                    .foregroundColor(.cyan)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(targetCallsign.uppercased())
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .foregroundColor(.primary)

                        if let iso = countryIso {
                            Text("\(flagForCountryIso(iso)) \(iso.uppercased())")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                        }

                        if targetCallsign.uppercased() == appState.currentStationCallsign.uppercased() {
                            Text("YOUR STATION")
                                .font(.system(size: 9, weight: .black))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue, in: Capsule())
                                .foregroundColor(.white)
                        }
                    }

                    Text("Live QRZ National Standings & Strategy Insights")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if appState.isFetchingInspectedAnalysis {
                    ProgressView().controlSize(.small)
                }

                Button(action: {
                    appState.fetchInspectedStationAnalysis(callsign: targetCallsign)
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Refresh Station Analysis")

                Button("Open in Full Roadmap") {
                    appState.leaderboardSearchCallsign = targetCallsign
                    appState.stationAnalysis = appState.inspectedStationAnalysis
                    appState.nationalLeaderboardTab = .roadmap
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main Content Area
            if appState.isFetchingInspectedAnalysis && appState.inspectedStationAnalysis == nil {
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.3)
                    Text("Fetching detailed station telemetry for \(targetCallsign)...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            } else if let analysis = appState.inspectedStationAnalysis {
                ScrollView {
                    LazyVStack(spacing: 18) {
                        // 1. National Standing Card
                        if let ns = analysis.nationalStanding {
                            NationalStandingCardView(standing: ns, countryName: analysis.countryName, countryIso: analysis.countryIso)
                        }

                        // 2. Badges Showcase
                        if !analysis.badges.isEmpty {
                            BadgesShowcaseView(badges: analysis.badges)
                        }

                        // 3. Interactive Rank Climb Simulator
                        StationRankSimulatorCardView(
                            targetCallsign: targetCallsign,
                            simulatedDeltaQSO: $simulatedDeltaQSO,
                            customDeltaText: $customDeltaText,
                            unconfirmedCount: unconfirmedCount
                        )

                        // 4. Strategic Elevation Plan
                        if let rec = analysis.recommendations {
                            StrategicPlanCardView(recommendations: rec)
                        }

                        // 5. Pending Confirmation ROI Card
                        PendingConfirmationROICardView(recommendations: analysis.recommendations)

                        // 6. Direct Peer Rivals Table
                        if !analysis.peerRivals.isEmpty {
                            PeerRivalsTableView(rivals: analysis.peerRivals, currentCallsign: analysis.callsign)
                        }
                    }
                    .padding(20)
                }
                .background(Color(NSColor.textBackgroundColor))
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundColor(.orange)
                    Text("Failed to load telemetry for \(targetCallsign).")
                        .font(.headline)
                    Button("Try Again") {
                        appState.fetchInspectedStationAnalysis(callsign: targetCallsign)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .frame(minWidth: 700, idealWidth: 780, minHeight: 600, idealHeight: 720)
        .onAppear {
            appState.fetchInspectedStationAnalysis(callsign: targetCallsign)
        }
    }
}

// MARK: - Station Rank Simulator Card View
struct StationRankSimulatorCardView: View {
    @EnvironmentObject var appState: AppState
    let targetCallsign: String
    @Binding var simulatedDeltaQSO: Int
    @Binding var customDeltaText: String
    let unconfirmedCount: Int

    private var simulation: RankSimulationResult? {
        appState.simulateRankClimb(for: targetCallsign, additionalQso: simulatedDeltaQSO)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "speedometer")
                        .foregroundColor(.cyan)
                    Text("Interactive Rank Climb Simulator")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                Spacer()
                Text("What-If Engine")
                    .font(.caption2)
                    .fontWeight(.heavy)
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.15), in: Capsule())
            }

            Text("Simulate how confirmed QSO gains elevate \(targetCallsign)'s national standing:")
                .font(.caption)
                .foregroundColor(.secondary)

            // Preset Delta Buttons
            HStack(spacing: 8) {
                ForEach([10, 25, 50, 100, 250, 500], id: \.self) { delta in
                    let isSelected = simulatedDeltaQSO == delta
                    Button("+\(delta) QSOs") {
                        simulatedDeltaQSO = delta
                        customDeltaText = "\(delta)"
                    }
                    .buttonStyle(.bordered)
                    .tint(isSelected ? .cyan : .secondary)
                    .controlSize(.small)
                }

                if unconfirmedCount > 0 {
                    Button(action: {
                        simulatedDeltaQSO = unconfirmedCount
                        customDeltaText = "\(unconfirmedCount)"
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                            Text("Pending Log (\(unconfirmedCount))")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.small)
                }
            }

            // Results Display
            if let sim = simulation {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SIMULATED SCORE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            Text("\(sim.simulatedScore.formatted())")
                                .font(.system(size: 20, weight: .black, design: .monospaced))
                                .foregroundColor(.cyan)
                            Text("(+\(sim.additionalQso))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider().frame(height: 36)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("PROJECTED RANK")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            Text("#\(sim.simulatedRank)")
                                .font(.system(size: 22, weight: .black, design: .monospaced))
                                .foregroundColor(.yellow)

                            if let orig = sim.originalRank, orig > sim.simulatedRank {
                                let gained = orig - sim.simulatedRank
                                Text("▲ +\(gained) spots!")
                                    .font(.system(size: 11, weight: .heavy))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.15), in: Capsule())
                            }
                        }
                    }

                    Spacer()

                    if let nextAbove = sim.nextStationAboveCallsign, let gap = sim.nextStationGap {
                        VStack(alignment: .trailing, spacing: 3) {
                            Text("NEXT TARGET AHEAD")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                            Text("\(nextAbove) · +\(gap) away")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(12)
                .background(Color(NSColor.textBackgroundColor).opacity(0.6))
                .cornerRadius(10)

                if !sim.leapfroggedCallsigns.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "figure.walk.motion")
                            .foregroundColor(.green)
                        Text("Will leapfrog \(sim.leapfroggedCallsigns.count) stations:")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(sim.leapfroggedCallsigns, id: \.self) { c in
                                    Text(c)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.15), in: Capsule())
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Leaderboard data required for simulation calculation.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
        )
    }
}
