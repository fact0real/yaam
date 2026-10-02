//
//  NationalLeaderboardViews.swift
//  YAAM
//
//  Created by factoreal on 9/14/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
        let prefix: String
    }

    private let quickCountries: [QuickCountry] = [
        QuickCountry(iso: "ir", name: "Iran", flag: "🇮🇷", prefix: "EP"),
        QuickCountry(iso: "ma", name: "Morocco", flag: "🇲🇦", prefix: "CN"),
        QuickCountry(iso: "us", name: "USA", flag: "🇺🇸", prefix: "W/K"),
        QuickCountry(iso: "de", name: "Germany", flag: "🇩🇪", prefix: "DL"),
        QuickCountry(iso: "jp", name: "Japan", flag: "🇯🇵", prefix: "JA"),
        QuickCountry(iso: "gb", name: "UK", flag: "🇬🇧", prefix: "G"),
        QuickCountry(iso: "it", name: "Italy", flag: "🇮🇹", prefix: "I"),
        QuickCountry(iso: "es", name: "Spain", flag: "🇪🇸", prefix: "EA"),
        QuickCountry(iso: "fr", name: "France", flag: "🇫🇷", prefix: "F"),
        QuickCountry(iso: "br", name: "Brazil", flag: "🇧🇷", prefix: "PY"),
        QuickCountry(iso: "ca", name: "Canada", flag: "🇨🇦", prefix: "VE"),
        QuickCountry(iso: "au", name: "Australia", flag: "🇦🇺", prefix: "VK"),
        QuickCountry(iso: "pl", name: "Poland", flag: "🇵🇱", prefix: "SP"),
        QuickCountry(iso: "ru", name: "Russia", flag: "🇷🇺", prefix: "RA")
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickCountries) { item in
                    let isSelected = appState.selectedNationalCountryIso.lowercased() == item.iso.lowercased()
                    let profile = CountryThemeRegistry.profile(for: item.iso, fallbackName: item.name)

                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            appState.selectedNationalCountryIso = item.iso
                            appState.fetchNationalLeaderboard(countryIso: item.iso)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text(item.flag)
                                .font(.system(size: 15))

                            Text(item.name)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? .primary : .secondary)

                            Text(item.prefix)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(isSelected ? profile.accentColor : .secondary.opacity(0.7))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? profile.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
                                )
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isSelected ? profile.accentColor.opacity(0.16) : Color(NSColor.controlBackgroundColor).opacity(0.6))
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    isSelected ? profile.accentColor : Color.primary.opacity(0.1),
                                    lineWidth: isSelected ? 1.5 : 1
                                )
                        )
                        .shadow(color: isSelected ? profile.accentColor.opacity(0.3) : Color.clear, radius: 4, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
    }
}

// MARK: - World Champions Showcase View
struct WorldChampionsShowcaseView: View {
    @EnvironmentObject var appState: AppState
    var onInspectStation: ((String) -> Void)?
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 0.95, green: 0.65, blue: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 22, height: 22)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black)
                    }

                    Text("GLOBAL QRZ CHAMPIONS & PIONEERS")
                        .font(.caption)
                        .fontWeight(.heavy)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.85, blue: 0.2), Color(red: 0.95, green: 0.65, blue: 0.1)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .kerning(1.1)

                    if !appState.worldChampions.isEmpty {
                        Text("\(appState.worldChampions.count)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.18), in: Capsule())
                            .foregroundColor(.yellow)
                    }
                }

                Spacer()

                if appState.isFetchingWorldChampions {
                    ProgressView().controlSize(.small)
                }

                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 5) {
                        Text(isExpanded ? "Collapse" : "Show All (\(appState.worldChampions.count))")
                            .font(.caption2)
                            .fontWeight(.semibold)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.05), in: Capsule())
                }
                .buttonStyle(.plain)
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
                        .padding(.vertical, 14)
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
                        .padding(.horizontal, 2)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [Color.yellow.opacity(0.35), Color.orange.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
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
        let profile = CountryThemeRegistry.profile(for: champ.countryIso, fallbackName: champ.countryName)

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(flagForCountryIso(champ.countryIso))
                    .font(.system(size: 17))
                Text(champ.countryName)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(profile.prefix)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(profile.accentColor)
            }

            HStack(spacing: 5) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.1))
                Text(champ.callsign)
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundColor(.primary)
            }

            HStack(spacing: 4) {
                Text(champ.formattedScore)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)
                Text("QSOs")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 6) {
                Button(action: {
                    onInspectStation?(champ.callsign)
                }) {
                    Text("Inspect")
                        .font(.system(size: 10, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button(action: {
                    withAnimation {
                        appState.selectedNationalCountryIso = champ.countryIso
                        appState.fetchNationalLeaderboard(countryIso: champ.countryIso)
                    }
                }) {
                    Text("National")
                        .font(.system(size: 10, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(profile.accentColor)
            }
            .padding(.top, 2)
        }
        .padding(11)
        .frame(width: 178)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [Color.yellow.opacity(0.3), profile.accentColor.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - National Leaderboard Container View
struct NationalLeaderboardContainerView: View {
    @EnvironmentObject var appState: AppState
    @State private var inspectingStation: InspectingStationItem? = nil
    @State private var isExportingCSV = false
    @State private var csvExportError: String?

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
        let currentProfile = CountryThemeRegistry.profile(
            for: appState.selectedNationalCountryIso,
            fallbackName: appState.nationalLeaderboard?.countryName ?? ""
        )

        VStack(spacing: 0) {
            // Quick Country Select Horizontal Pills
            QuickCountryPillsView()

            Divider()

            // Filter & Depth Bar
            HStack(spacing: 14) {
                // Country Picker with Flag
                HStack(spacing: 6) {
                    Text(currentProfile.flagEmoji)
                        .font(.system(size: 16))

                    Text("Country:")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)

                    Picker("", selection: $appState.selectedNationalCountryIso) {
                        if !appState.qrzRankCountries.isEmpty {
                            ForEach(appState.qrzRankCountries) { c in
                                Text("\(flagForCountryIso(c.iso)) \(c.name) (\(c.iso.uppercased())) · \(c.stationCount ?? 0) stns")
                                    .tag(c.iso.lowercased())
                            }
                        } else {
                            ForEach(fallbackCountries, id: \.iso) { c in
                                Text("\(flagForCountryIso(c.iso)) \(c.name)").tag(c.iso)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 230)
                    .onChange(of: appState.selectedNationalCountryIso) { _, newIso in
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
                .onChange(of: appState.selectedNationalCategory) { _, newCat in
                    appState.fetchNationalLeaderboard(category: newCat)
                }

                Spacer()

                if appState.isFetchingNationalLeaderboard {
                    ProgressView().controlSize(.small)
                }

                Button(action: exportLeaderboardCSV) {
                    Label("Export CSV", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(isExportingCSV)

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

            // Main Content Area with Dynamic Flag & Map Background
            ZStack {
                // Layer 1: Ambient National Color Aura Gradients
                ZStack {
                    Color(NSColor.windowBackgroundColor)

                    // Top-right national color ambient glow
                    RadialGradient(
                        colors: [
                            currentProfile.accentColor.opacity(0.18),
                            Color.clear
                        ],
                        center: .topTrailing,
                        startRadius: 40,
                        endRadius: 500
                    )

                    // Bottom-left national color ambient glow
                    RadialGradient(
                        colors: [
                            currentProfile.secondaryColor.opacity(0.14),
                            Color.clear
                        ],
                        center: .bottomLeading,
                        startRadius: 40,
                        endRadius: 550
                    )

                    // Centered Flag Watermark
                    VStack {
                        HStack {
                            Spacer()
                            Text(currentProfile.flagEmoji)
                                .font(.system(size: 260))
                                .opacity(0.06)
                                .blur(radius: 2)
                                .rotationEffect(.degrees(-8))
                                .offset(x: 40, y: -20)
                        }
                        Spacer()
                    }
                }
                .ignoresSafeArea()

                // Layer 2: Main Content ScrollView
                if appState.isFetchingNationalLeaderboard && appState.nationalLeaderboard == nil {
                    VStack(spacing: 16) {
                        ProgressView().scaleEffect(1.3)
                        Text("Loading national rankings for \(currentProfile.name)...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                            // Country Hero Banner with Integrated Country Map
                            CountryHeroBannerView(
                                data: data,
                                profile: currentProfile,
                                displayedDepth: min(appState.selectedNationalDepth, data.totalStations)
                            )
                            .padding(.horizontal, 24)

                            // Top 3 Podium Section
                            let top3 = Array(filteredItems.prefix(3))
                            if !top3.isEmpty {
                                PodiumSectionView(
                                    top3: top3,
                                    category: data.category,
                                    profile: currentProfile,
                                    onInspectStation: { call in
                                        inspectingStation = InspectingStationItem(callsign: call)
                                    }
                                )
                                .padding(.horizontal, 24)
                            }

                            // Standings Table
                            let tableItems = filteredItems.count > 3 ? Array(filteredItems.dropFirst(3)) : []
                            if !tableItems.isEmpty {
                                NationalTableView(
                                    items: tableItems,
                                    category: data.category,
                                    profile: currentProfile,
                                    highestScore: top3.first?.score ?? (tableItems.first?.score ?? 1),
                                    onInspectStation: { call in
                                        inspectingStation = InspectingStationItem(callsign: call)
                                    }
                                )
                                .padding(.horizontal, 24)
                                .padding(.bottom, 30)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "flag.slash")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("No national rankings available yet for \(currentProfile.name).")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Button("Load Iranian (EP) Standings") {
                            appState.selectedNationalCountryIso = "ir"
                            appState.fetchNationalLeaderboard(countryIso: "ir")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(currentProfile.accentColor)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .sheet(item: $inspectingStation) { item in
            StationAnalysisSheetView(targetCallsign: item.callsign, countryIso: appState.selectedNationalCountryIso)
                .environmentObject(appState)
        }
        .alert("CSV export failed", isPresented: Binding(
            get: { csvExportError != nil },
            set: { if !$0 { csvExportError = nil } }
        )) {
            Button("OK", role: .cancel) { csvExportError = nil }
        } message: {
            Text(csvExportError ?? "Unknown error")
        }
        .onAppear {
            appState.fetchQRZRankCountries()
            if appState.nationalLeaderboard == nil {
                appState.fetchNationalLeaderboard()
            }
        }
    }

    private func exportLeaderboardCSV() {
        let iso = appState.selectedNationalCountryIso
        let category = appState.selectedNationalCategory
        let panel = NSSavePanel()
        panel.title = "Export national leaderboard"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Leaderboard_\(iso.uppercased())_\(category).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isExportingCSV = true
        Task { @MainActor in
            do {
                let token = CredentialVault.value(for: .qrzRankAPIToken)
                let data = try await QRZRankService.shared.fetchCountryLeaderboardCSV(
                    countryIso: iso, category: category, token: token,
                    userAgent: "YAAM-macOS/\(appState.currentVersion)"
                )
                try data.write(to: url, options: .atomic)
            } catch {
                csvExportError = error.localizedDescription
            }
            isExportingCSV = false
        }
    }
}

// MARK: - Country Hero Banner View (Combines Flag, Title, Radio Stats, and Live MapKit Country Map)
struct CountryHeroBannerView: View {
    let data: QRZCountryLeaderboardResponse
    let profile: CountryThemeProfile
    let displayedDepth: Int

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            // Left Column: Prestige Badge, Titles & Stats
            VStack(alignment: .leading, spacing: 10) {
                // Hall of Fame Header Chip
                HStack(spacing: 8) {
                    Text(profile.flagEmoji)
                        .font(.system(size: 26))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("\(data.countryName.uppercased()) HALL OF FAME")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [profile.accentColor, profile.secondaryColor],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .kerning(1.3)

                            Text(profile.prefix)
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(profile.accentColor.opacity(0.18), in: Capsule())
                                .foregroundColor(profile.accentColor)
                        }

                        Text("National QRZ Operator Rankings & Elite Standings")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Main Stats Row
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(data.totalStations)")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Ranked Stations")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                    }

                    Divider().frame(height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Top \(displayedDepth)")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(profile.accentColor)
                        Text("Displayed")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                    }

                    Divider().frame(height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.continent)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                        Text("\(profile.cqZone) · \(profile.ituZone)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)

                // Category Metric Explanation
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundColor(profile.accentColor)
                    Text(categoryDescription(for: data.category))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [profile.accentColor.opacity(0.4), profile.secondaryColor.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
            )

            // Right Column: Native Interactive Country Map Card
            CountryHeroMapCardView(profile: profile)
                .frame(width: 320)
        }
    }

    private func categoryDescription(for category: String) -> String {
        switch category {
        case "countries": return "Ranked by unique DXCC entities confirmed"
        case "band": return "Ranked by DXCC band-slots confirmed across all amateur bands"
        default: return "Ranked by total verified QSO volume logged on QRZ"
        }
    }
}

// MARK: - Podium Section View
struct PodiumSectionView: View {
    @EnvironmentObject var appState: AppState
    let top3: [QRZCountryLeaderboardItem]
    let category: String
    let profile: CountryThemeProfile
    var onInspectStation: ((String) -> Void)?

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            // Rank 2 (Silver)
            if top3.count > 1 {
                PodiumCard(
                    item: top3[1],
                    medal: "🥈 #2 Silver Medalist",
                    medalGradient: LinearGradient(
                        colors: [Color(red: 0.90, green: 0.93, blue: 0.96), Color(red: 0.65, green: 0.70, blue: 0.78)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    accentColor: Color(red: 0.75, green: 0.80, blue: 0.88),
                    onInspectStation: onInspectStation
                )
            }

            // Rank 1 (Gold Champion) - Elevated Pedestal
            if !top3.isEmpty {
                PodiumCard(
                    item: top3[0],
                    medal: "👑 #1 National Champion",
                    medalGradient: LinearGradient(
                        colors: [Color(red: 1.0, green: 0.86, blue: 0.1), Color(red: 0.95, green: 0.65, blue: 0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    accentColor: Color(red: 1.0, green: 0.82, blue: 0.1),
                    isChampion: true,
                    onInspectStation: onInspectStation
                )
                .scaleEffect(1.05)
                .offset(y: -8)
            }

            // Rank 3 (Bronze)
            if top3.count > 2 {
                PodiumCard(
                    item: top3[2],
                    medal: "🥉 #3 Bronze Medalist",
                    medalGradient: LinearGradient(
                        colors: [Color(red: 0.92, green: 0.62, blue: 0.40), Color(red: 0.68, green: 0.40, blue: 0.22)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    accentColor: Color(red: 0.85, green: 0.55, blue: 0.35),
                    onInspectStation: onInspectStation
                )
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}

struct PodiumCard: View {
    @EnvironmentObject var appState: AppState
    let item: QRZCountryLeaderboardItem
    let medal: String
    let medalGradient: LinearGradient
    let accentColor: Color
    var isChampion: Bool = false
    var onInspectStation: ((String) -> Void)?

    private var scoreTitle: String {
        "\(item.score.formatted())"
    }

    var body: some View {
        VStack(spacing: 10) {
            // Medal Header
            HStack(spacing: 5) {
                if isChampion {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(accentColor)
                }
                Text(medal)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(medalGradient)
                    .textCase(.uppercase)
            }

            // Callsign
            Button(action: {
                onInspectStation?(item.callsign)
            }) {
                Text(item.callsign)
                    .font(.system(size: isChampion ? 24 : 20, weight: .black, design: .monospaced))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .help("Click to inspect station analysis")

            // Big Score
            VStack(spacing: 1) {
                Text(scoreTitle)
                    .font(.system(size: isChampion ? 28 : 24, weight: .black, design: .rounded))
                    .foregroundStyle(medalGradient)

                Text("POINTS / QSOS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
            }

            // Stats row (DXCC Countries & Bands)
            HStack(spacing: 14) {
                VStack(spacing: 2) {
                    Text("DXCC")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Text("\(item.scoreCountries ?? 0)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }

                Divider().frame(height: 18)

                VStack(spacing: 2) {
                    Text("BANDS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Text("\(item.scoreBand ?? 0)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }

                Divider().frame(height: 18)

                VStack(spacing: 2) {
                    Text("GLOBAL")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(item.rankQso.map { "#\($0)" } ?? "-")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

            // Quick Station Analysis Action Button
            Button(action: {
                onInspectStation?(item.callsign)
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Quick Analysis")
                        .font(.system(size: 11, weight: .bold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    medalGradient,
                    lineWidth: isChampion ? 2.5 : 1.5
                )
        )
        .shadow(
            color: isChampion ? accentColor.opacity(0.35) : accentColor.opacity(0.18),
            radius: isChampion ? 14 : 8,
            x: 0,
            y: isChampion ? 4 : 2
        )
    }
}

// MARK: - National Table View
struct NationalTableView: View {
    @EnvironmentObject var appState: AppState
    let items: [QRZCountryLeaderboardItem]
    let category: String
    let profile: CountryThemeProfile
    let highestScore: Int
    var onInspectStation: ((String) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Table Header
            HStack {
                Text("# Rank")
                    .frame(width: 80, alignment: .leading)
                Text("Callsign")
                    .frame(width: 130, alignment: .leading)
                Text("Score")
                    .frame(width: 140, alignment: .trailing)
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
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))

            Divider()

            // Rows
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let isTop10 = item.rank <= 10
                let isEven = index % 2 == 0

                HStack {
                    // Rank Badge
                    HStack(spacing: 4) {
                        Text("#\(item.rank)")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundColor(isTop10 ? profile.accentColor : .secondary)

                        if isTop10 {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                                .foregroundColor(Color(red: 1.0, green: 0.82, blue: 0.1))
                        }
                    }
                    .frame(width: 80, alignment: .leading)

                    // Callsign
                    Button(action: {
                        onInspectStation?(item.callsign)
                    }) {
                        Text(item.callsign)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 130, alignment: .leading)

                    // Score + Relative Progress bar
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(item.score.formatted())
                            .font(.system(size: 13, weight: .heavy, design: .monospaced))
                            .foregroundColor(profile.accentColor)

                        // Relative Progress Bar
                        let progress = highestScore > 0 ? Double(item.score) / Double(highestScore) : 0.0
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(height: 3)

                                Capsule()
                                    .fill(profile.accentColor.opacity(0.7))
                                    .frame(width: max(4, geo.size.width * CGFloat(progress)), height: 3)
                            }
                        }
                        .frame(width: 90, height: 3)
                    }
                    .frame(width: 140, alignment: .trailing)

                    // Countries
                    Text("\(item.scoreCountries ?? 0)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 90, alignment: .trailing)

                    // Bands
                    Text("\(item.scoreBand ?? 0)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 90, alignment: .trailing)

                    // Global Rank
                    let categoryGlobalRank: Int? = {
                        switch category {
                        case "countries": return item.rankCountries
                        case "band": return item.rankBand
                        default: return item.rankQso
                        }
                    }()
                    Text(categoryGlobalRank.map { "#\($0.formatted())" } ?? "-")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 100, alignment: .trailing)

                    Spacer()

                    // Action Button
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
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(isEven ? Color.primary.opacity(0.02) : Color.clear)

                if index < items.count - 1 {
                    Divider().opacity(0.6)
                }
            }
        }
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(profile.accentColor.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
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
