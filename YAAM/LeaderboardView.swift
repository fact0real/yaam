//
//  LeaderboardView.swift
//  YAAM
//
//  Created by factoreal on 7/30/26.
//

import SwiftUI

// MARK: - Helper to parse rank strings like "#16,278" into Int
func parseRankInt(_ rankStr: String?) -> Int? {
    guard let str = rankStr else { return nil }
    let cleaned = str.replacingOccurrences(of: "#", with: "").replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
    return Int(cleaned)
}

// MARK: - Full Page Leaderboard View with VS Mode
struct LeaderboardView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedHistoryMetric: RankHistoryMetric = .qso
    @State private var lastLeaderboardAction: LeaderboardAction? = nil

    private enum LeaderboardAction {
        case compare
        case track
    }

    private let randomComparisonPool = [
        "AA3B", "K1LZ", "N2NT", "W3LPL", "K3LR", "EA8RM", "S50A", "DL7ON",
        "YB5QZ", "JA1YPA", "PY5EG", "LU7HN", "VK2IM", "ZL3IO", "9A1A", "LZ9W"
    ]

    private var parsedLeaderboardTargets: [String] {
        appState.leaderboardSearchCallsign
            .split { $0 == "," || $0 == " " || $0 == ";" }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
    }

    private var allEnteredTargetsTracked: Bool {
        guard !parsedLeaderboardTargets.isEmpty else { return false }
        let tracked = Set(appState.trackedRankCallsigns.map { $0.uppercased() })
        return parsedLeaderboardTargets.allSatisfy { tracked.contains($0) }
    }

    private func randomizeComparisons() {
        let selected = Array(randomComparisonPool.shuffled().prefix(3))
        lastLeaderboardAction = .compare
        appState.leaderboardSearchCallsign = selected.joined(separator: ", ")
        appState.fetchQRZLeaderboardComparisons(for: selected)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Search Bar Area
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title3)
                    .foregroundColor(.secondary)
                
                TextField(
                    "Enter callsigns to compare or track (e.g. AA3B, YB5QZ, EA1DR)...",
                    text: Binding(
                        get: { appState.leaderboardSearchCallsign },
                        set: {
                            appState.leaderboardSearchCallsign = $0.uppercased()
                            lastLeaderboardAction = nil
                        }
                    ),
                    onCommit: {
                        lastLeaderboardAction = .compare
                        appState.fetchQRZLeaderboardComparisons(for: parsedLeaderboardTargets)
                    }
                )
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .bold, design: .monospaced))

                Button(action: randomizeComparisons) {
                    HStack(spacing: 4) {
                        Image(systemName: "shuffle")
                        Text("Random 3")
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                
                Button(action: {
                    lastLeaderboardAction = .compare
                    appState.fetchQRZLeaderboardComparisons(for: parsedLeaderboardTargets)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "swords")
                        Text("Compare")
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(parsedLeaderboardTargets.isEmpty)

                Button(action: {
                    lastLeaderboardAction = .track
                    appState.addTrackedRankCallsigns(parsedLeaderboardTargets)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: allEnteredTargetsTracked ? "checkmark.circle.fill" : "scope")
                        Text(allEnteredTargetsTracked ? "Tracked" : "Track")
                            .fontWeight(.bold)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(allEnteredTargetsTracked || lastLeaderboardAction == .track ? .green : .blue)
                .disabled(parsedLeaderboardTargets.isEmpty)
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()

            if !appState.rankServiceStatus.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: rankStatusIcon)
                        .foregroundStyle(rankStatusColor)
                    Text(appState.rankServiceStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    if rankServiceNeedsConfiguration {
                        SettingsLink {
                            Label("Configure Rank Service", systemImage: "gearshape")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(rankStatusColor.opacity(0.08))
                Divider()
            }
            
            // 2. Main Content
            if appState.isFetchingRank {
                VStack(spacing: 20) {
                    ProgressView().scaleEffect(1.4)
                    Text("Fetching global rankings & analyzing scores...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
                
            } else if !appState.qrzComparisonRankData.isEmpty {
                let owner = appState.ownerRankData

                ScrollView {
                    LazyVStack(spacing: 18) {
                        PlayerCard(
                            title: "YOU (STATION)",
                            callsign: owner?.callsign ?? appState.currentStationCallsign,
                            countryIso: owner?.country_iso,
                            isOwner: true
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                        RankPerformanceMonitor(
                            metric: $selectedHistoryMetric,
                            series: appState.rankTrendSeries(metric: selectedHistoryMetric),
                            trackedCallsigns: appState.trackedRankCallsigns,
                            isRefreshing: appState.isRefreshingRankHistory,
                            status: appState.rankHistoryStatus,
                            refreshAction: { appState.refreshTrackedRankHistoryIfNeeded(force: true) },
                            removeAction: { appState.removeTrackedRankCallsign($0) }
                        )
                        .padding(.horizontal, 24)

                        Leaderboard360RadarView(
                            owner: owner,
                            rivals: appState.qrzComparisonRankData,
                            stationRecords: appState.qsoRecords
                        )
                        .padding(.horizontal, 24)

                        LeaderboardInvestmentPanel(owner: owner, rivals: appState.qrzComparisonRankData)
                            .padding(.horizontal, 24)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 14)], spacing: 14) {
                            ForEach(appState.qrzComparisonRankData, id: \.callsign) { rival in
                                RivalComparisonPanel(owner: owner, rival: rival)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 30)
                    }
                }
                .background(Color(NSColor.textBackgroundColor))

            } else if let searched = appState.qrzRankData {
                let owner = appState.ownerRankData
                let isSelfSearch = (owner?.callsign?.uppercased() == searched.callsign?.uppercased())
                
                ScrollView {
                    LazyVStack(spacing: 24) {
                        
                        // VS Battle Banner
                        HStack(spacing: 20) {
                            // Left Player: YOU
                            PlayerCard(
                                title: "YOU (STATION)",
                                callsign: owner?.callsign ?? appState.currentStationCallsign,
                                countryIso: owner?.country_iso,
                                isOwner: true
                            )
                            
                            // Center VS Badge
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom))
                                        .frame(width: 50, height: 50)
                                        .shadow(color: .orange.opacity(0.5), radius: 8)
                                    
                                    Text("VS")
                                        .font(.system(size: 20, weight: .black, design: .rounded))
                                        .foregroundColor(.white)
                                }
                                if isSelfSearch {
                                    Text("Self View")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // Right Player: RIVAL
                            PlayerCard(
                                title: isSelfSearch ? "TARGET" : "RIVAL OPERATOR",
                                callsign: searched.callsign ?? "UNKNOWN",
                                countryIso: searched.country_iso,
                                isOwner: false
                            )
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                        RankPerformanceMonitor(
                            metric: $selectedHistoryMetric,
                            series: appState.rankTrendSeries(metric: selectedHistoryMetric),
                            trackedCallsigns: appState.trackedRankCallsigns,
                            isRefreshing: appState.isRefreshingRankHistory,
                            status: appState.rankHistoryStatus,
                            refreshAction: { appState.refreshTrackedRankHistoryIfNeeded(force: true) },
                            removeAction: { appState.removeTrackedRankCallsign($0) }
                        )
                        .padding(.horizontal, 24)

                        Leaderboard360RadarView(
                            owner: owner,
                            rivals: appState.qrzComparisonRankData.isEmpty ? [searched] : appState.qrzComparisonRankData,
                            stationRecords: appState.qsoRecords
                        )
                        .padding(.horizontal, 24)

                        LeaderboardInvestmentPanel(owner: owner, rivals: [searched])
                            .padding(.horizontal, 24)
                        
                        // Comparison Categories
                        VStack(spacing: 16) {
                            Text("HEAD-TO-HEAD STANDINGS")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                                .kerning(1.5)
                            
                            ComparisonRow(
                                category: "QSO World Rank",
                                icon: "antenna.radiowaves.left.and.right",
                                ownerRank: owner?.rank_qso,
                                searchedRank: searched.rank_qso,
                                ownerScore: owner?.score_qso,
                                searchedScore: searched.score_qso,
                                isSelf: isSelfSearch
                            )
                            
                            ComparisonRow(
                                category: "Bands World Rank",
                                icon: "waveform.path.ecg",
                                ownerRank: owner?.rank_band,
                                searchedRank: searched.rank_band,
                                ownerScore: owner?.score_band,
                                searchedScore: searched.score_band,
                                isSelf: isSelfSearch
                            )
                            
                            ComparisonRow(
                                category: "DXCC World Rank",
                                icon: "globe.americas.fill",
                                ownerRank: owner?.rank_countries,
                                searchedRank: searched.rank_countries,
                                ownerScore: owner?.score_countries,
                                searchedScore: searched.score_countries,
                                isSelf: isSelfSearch
                            )
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 30)
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
                
            } else {
                let owner = appState.ownerRankData

                ScrollView {
                    LazyVStack(spacing: 20) {
                        PlayerCard(
                            title: "YOU (STATION)",
                            callsign: owner?.callsign ?? appState.currentStationCallsign,
                            countryIso: owner?.country_iso,
                            isOwner: true
                        )
                        .padding(.horizontal, 24)
                        .padding(.top, 20)

                        RankPerformanceMonitor(
                            metric: $selectedHistoryMetric,
                            series: appState.rankTrendSeries(metric: selectedHistoryMetric),
                            trackedCallsigns: appState.trackedRankCallsigns,
                            isRefreshing: appState.isRefreshingRankHistory,
                            status: appState.rankHistoryStatus,
                            refreshAction: { appState.refreshTrackedRankHistoryIfNeeded(force: true) },
                            removeAction: { appState.removeTrackedRankCallsign($0) }
                        )
                        .padding(.horizontal, 24)

                        Leaderboard360RadarView(
                            owner: owner,
                            rivals: [],
                            stationRecords: appState.qsoRecords
                        )
                        .padding(.horizontal, 24)

                        HStack(spacing: 10) {
                            Image(systemName: "swords")
                                .foregroundColor(.orange)
                            Text("Type rival callsigns above and click Compare to launch side-by-side head-to-head rankings.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 30)
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
            }
        }
        .onAppear {
            if !parsedLeaderboardTargets.isEmpty && appState.qrzComparisonRankData.isEmpty && appState.qrzRankData == nil {
                appState.fetchQRZLeaderboardComparisons(for: parsedLeaderboardTargets)
            }
            appState.refreshTrackedRankHistoryIfNeeded()
        }
    }

    private var rankServiceNeedsConfiguration: Bool {
        let status = appState.rankServiceStatus.lowercased()
        return status.contains("token")
            || status.contains("unauthorized")
            || status.contains("authentication")
            || status.contains("subscription")
            || status.contains("quota")
    }

    private var rankStatusColor: Color {
        let status = appState.rankServiceStatus.lowercased()
        if status.contains("failed") || status.contains("invalid") || status.contains("unavailable") {
            return .red
        }
        if rankServiceNeedsConfiguration || status.contains("saved") || status.contains("offline") {
            return .orange
        }
        return .green
    }

    private var rankStatusIcon: String {
        if rankServiceNeedsConfiguration { return "key.fill" }
        let status = appState.rankServiceStatus.lowercased()
        if status.contains("failed") || status.contains("invalid") || status.contains("unavailable") {
            return "exclamationmark.triangle.fill"
        }
        return "checkmark.circle.fill"
    }
}

private let rankTrendPalette: [Color] = [.blue, .purple, .orange, .green, .pink, .cyan, .red, .indigo, .mint]

struct RankPerformanceMonitor: View {
    @Binding var metric: RankHistoryMetric
    let series: [RankTrendSeries]
    let trackedCallsigns: [String]
    let isRefreshing: Bool
    let status: String
    let refreshAction: () -> Void
    let removeAction: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Label("Rival Performance Monitor", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)

                Picker("Metric", selection: $metric) {
                    ForEach(RankHistoryMetric.allCases) { item in
                        Label(item.title, systemImage: item.icon).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 360)

                Spacer()

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }

                Button(action: refreshAction) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing)
            }

            LeaderboardMomentumBanner(series: series)

            if trackedCallsigns.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "scope")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Type rival callsigns above, then click Track to start daily QRZ rank history.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text("Daily QRZ rank movement")
                                .font(.subheadline.weight(.semibold))
                            Text("• Click any bullet to inspect rank & daily delta")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.cyan)
                        }
                        Text("Every line starts at zero. Above the center line means that operator climbed; below it means they slipped.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        RankMovementTrendChart(series: series)
                            .frame(minHeight: 220)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Position")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        ForEach(Array(series.enumerated()), id: \.element.id) { index, item in
                            TrackedRivalRow(
                                callsign: item.callsign,
                                countryIso: item.countryIso,
                                isOwner: item.isOwner,
                                latestRank: item.latestRank,
                                latestGap: item.latestGap,
                                latestMovement: item.latestMovement,
                                trendColor: rankTrendPalette[index % rankTrendPalette.count],
                                removeAction: item.isOwner ? nil : { removeAction(item.callsign) }
                            )
                        }

                        if !status.isEmpty {
                            Text(status)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    .frame(width: 280, alignment: .topLeading)
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.65))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.blue.opacity(0.22), lineWidth: 1))
    }
}

private struct LeaderboardMomentumBanner: View {
    let series: [RankTrendSeries]

    private var momentum: (title: String, detail: String, icon: String, color: Color) {
        let owner = series.first(where: \.isOwner)
        let rivals = series.filter { !$0.isOwner }
        let deltas = rivals.compactMap(\.latestGapMovement)
        guard !deltas.isEmpty else {
            return (
                "Need one more day of rank snapshots",
                "Track rivals and refresh once per day. The next snapshot will show each operator's climb or fall and your relative change.",
                "calendar.badge.plus",
                .secondary
            )
        }

        let improved = deltas.filter { $0 > 0 }.count
        let slipped = deltas.filter { $0 < 0 }.count
        let net = deltas.reduce(0, +)
        let formatted = NumberFormatter.localizedString(from: NSNumber(value: abs(net)), number: .decimal)
        let ownerMove: String
        if let movement = owner?.latestMovement, movement > 0 {
            ownerMove = "You climbed \(movement.formatted()) rank(s) today. "
        } else if let movement = owner?.latestMovement, movement < 0 {
            ownerMove = "You slipped \(abs(movement).formatted()) rank(s) today. "
        } else if owner?.latestMovement != nil {
            ownerMove = "Your rank was unchanged today. "
        } else {
            ownerMove = ""
        }
        if net > 0 {
            return (
                "Good day against tracked rivals",
                "\(ownerMove)Your relative position improved by \(formatted) rank point(s); you gained ground against \(improved) of \(deltas.count) comparable rival(s).",
                "hand.thumbsup.fill",
                .green
            )
        }
        if net < 0 {
            return (
                "You lost ground today",
                "\(ownerMove)Tracked rivals gained \(formatted) net rank point(s); \(slipped) comparison(s) moved against you today.",
                "exclamationmark.triangle.fill",
                .orange
            )
        }
        return (
            "Stable versus rivals",
            "\(ownerMove)Your combined relative position is unchanged across \(improved + slipped) tracked comparison(s).",
            "equal.circle.fill",
            .blue
        )
    }

    var body: some View {
        let item = momentum
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .foregroundStyle(item.color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(10)
        .background(item.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(item.color.opacity(0.22)))
    }
}

private struct LeaderboardInvestmentPanel: View {
    let owner: QRZRankResponse?
    let rivals: [QRZRankResponse]

    private struct Gap {
        let title: String
        let icon: String
        let ownerRank: Int
        let bestRivalRank: Int

        var deficit: Int { max(0, ownerRank - bestRivalRank) }
    }

    private var gaps: [Gap] {
        guard let owner else { return [] }
        let rankedRivals = rivals.filter(\.hasRankingValue)
        func gap(_ title: String, _ icon: String, _ ownerValue: String?, _ rivalValue: (QRZRankResponse) -> String?) -> Gap? {
            guard let ownerRank = parseRankInt(ownerValue) else { return nil }
            let best = rankedRivals.compactMap { parseRankInt(rivalValue($0)) }.min()
            guard let best else { return nil }
            return Gap(title: title, icon: icon, ownerRank: ownerRank, bestRivalRank: best)
        }
        return [
            gap("QSO volume", "antenna.radiowaves.left.and.right", owner.rank_qso, { $0.rank_qso }),
            gap("Band coverage", "waveform.path.ecg", owner.rank_band, { $0.rank_band }),
            gap("DXCC reach", "globe.americas.fill", owner.rank_countries, { $0.rank_countries })
        ].compactMap { $0 }
    }

    private var recommendation: String {
        guard let weakest = gaps.max(by: { $0.deficit < $1.deficit }), weakest.deficit > 0 else {
            return "You are tied with or ahead of the loaded rivals in the available QRZ rank categories. Invest next in 6m monitoring and contest timing to create harder-to-copy gains."
        }
        switch weakest.title {
        case "QSO volume":
            return "Best investment: increase daily QSO volume during high-activity windows and contests. This is the largest visible gap against loaded rivals."
        case "Band coverage":
            return "Best investment: expand band coverage, especially 6m/10m openings and underused bands. Band rank is currently the weakest competitive axis."
        default:
            return "Best investment: chase new DXCC entities and confirmations. Your country-rank gap is the biggest opportunity in the loaded comparison."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Competitive investment", systemImage: "chart.bar.xaxis")
                .font(.headline)

            Text(recommendation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !gaps.isEmpty {
                HStack(spacing: 10) {
                    ForEach(gaps, id: \.title) { gap in
                        VStack(alignment: .leading, spacing: 6) {
                            Image(systemName: gap.icon)
                                .foregroundStyle(gap.deficit == 0 ? .green : .orange)
                            Text(gap.title)
                                .font(.caption.weight(.semibold))
                            Text(gap.deficit == 0 ? "Ahead/tied" : "\(gap.deficit.formatted()) ranks behind")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.65))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.22), lineWidth: 1))
    }
}

struct TrackedRivalRow: View {
    let callsign: String
    let countryIso: String?
    let isOwner: Bool
    let latestRank: Int?
    let latestGap: Int?
    let latestMovement: Int?
    let trendColor: Color
    let removeAction: (() -> Void)?

    private var gapText: String {
        if isOwner { return "Your station" }
        guard let latestGap else { return "No same-day comparison yet" }
        let formatted = NumberFormatter.localizedString(from: NSNumber(value: abs(latestGap)), number: .decimal)
        if latestGap > 0 { return "You lead by \(formatted)" }
        if latestGap < 0 { return "You trail by \(formatted)" }
        return "Tied with you"
    }

    private var gapColor: Color {
        guard let latestGap else { return .secondary }
        if latestGap > 0 { return .green }
        if latestGap < 0 { return .red }
        return .secondary
    }

    private var movementText: String? {
        guard let latestMovement else { return nil }
        if latestMovement > 0 { return "▲ Climbed \(latestMovement.formatted())" }
        if latestMovement < 0 { return "▼ Slipped \(abs(latestMovement).formatted())" }
        return "● Unchanged"
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(trendColor)
                .frame(width: 8, height: 8)
            Text(countryToFlag(countryIso ?? ""))
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(callsign)
                        .font(.system(.subheadline, design: .monospaced))
                        .bold()
                    if isOwner {
                        Text("YOU")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.blue)
                    }
                    if let latestRank {
                        Text("#\(latestRank.formatted())")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text(gapText)
                    .font(.caption2)
                    .foregroundColor(gapColor)
                if let movementText {
                    Text(movementText)
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(latestMovement == 0 ? .secondary : (latestMovement ?? 0) > 0 ? .green : .orange)
                }
            }
            Spacer()
            if let removeAction {
                Button(action: removeAction) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Stop tracking \(callsign)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(6)
    }
}

struct RankMovementTrendChart: View {
    let series: [RankTrendSeries]

    private let maximumVisibleDays = 90

    @State private var selectedPointDetail: SelectedPointDetail? = nil

    private struct SelectedPointDetail: Identifiable {
        var id: String { "\(callsign)-\(point.id)" }
        let callsign: String
        let countryIso: String?
        let isOwner: Bool
        let point: RankTrendPoint
        let movement: Int
        let deltaFromPrev: Int?
        let color: Color
        let position: CGPoint
    }

    private struct PlottedPoint: Identifiable {
        var id: String { point.id }
        let point: RankTrendPoint
        let movement: Int
        let position: CGPoint
    }

    private var visibleDates: [Date] {
        let days = Set(series.flatMap(\.points).map { Calendar.current.startOfDay(for: $0.date) })
        return Array(days.sorted().suffix(maximumVisibleDays))
    }

    private var allMovements: [Int] {
        series.flatMap { item -> [Int] in
            let points = visiblePoints(item.points)
            guard let startingRank = points.first?.rank else { return [] }
            return points.map { startingRank - $0.rank }
        }
    }

    private var maxAbsMovement: Int {
        max(allMovements.map(abs).max() ?? 1, 1)
    }

    var body: some View {
        GeometryReader { geometry in
            if series.flatMap(\.points).isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Refresh once today; tomorrow's snapshot will start the visible trend.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let plotWidth = max(1, geometry.size.width - 68)
                let plotHeight = max(1, geometry.size.height - 44)
                let origin = CGPoint(x: 54, y: 12 + plotHeight / 2)
                let step = visibleDates.count > 1
                    ? plotWidth / CGFloat(visibleDates.count - 1)
                    : 0
                let yScale = max(1, plotHeight / 2 - 12) / CGFloat(maxAbsMovement)

                ZStack(alignment: .topLeading) {
                    chartGrid(width: geometry.size.width, height: plotHeight, origin: origin)

                    ForEach(Array(series.enumerated()), id: \.element.id) { index, item in
                        let color = rankTrendPalette[index % rankTrendPalette.count]
                        let plotted = plottedPoints(
                            for: item.points,
                            origin: origin,
                            plotWidth: plotWidth,
                            step: step,
                            yScale: yScale
                        )

                        linePath(plotted.map(\.position))
                            .stroke(
                                color,
                                style: StrokeStyle(
                                    lineWidth: item.isOwner ? 3.6 : 2.5,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )

                        ForEach(plotted) { plottedPoint in
                            let isSelected = selectedPointDetail?.id == "\(item.callsign)-\(plottedPoint.point.id)"
                            ZStack {
                                Color.clear
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())

                                if isSelected {
                                    Circle()
                                        .stroke(Color.white, lineWidth: 2)
                                        .frame(width: 15, height: 15)
                                    Circle()
                                        .fill(color.opacity(0.35))
                                        .frame(width: 20, height: 20)
                                }
                                Circle()
                                    .fill(color)
                                    .overlay {
                                        if item.isOwner {
                                            Circle().stroke(Color.white.opacity(0.85), lineWidth: 1)
                                        }
                                    }
                                    .frame(width: isSelected ? 10 : (item.isOwner ? 8 : 7), height: isSelected ? 10 : (item.isOwner ? 8 : 7))
                            }
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.25)) {
                                    if isSelected {
                                        selectedPointDetail = nil
                                    } else {
                                        let sorted = visiblePoints(item.points)
                                        let idx = sorted.firstIndex(where: { $0.id == plottedPoint.point.id }) ?? 0
                                        let prev = idx > 0 ? sorted[idx - 1] : nil
                                        let delta = prev.map { $0.rank - plottedPoint.point.rank }
                                        selectedPointDetail = SelectedPointDetail(
                                            callsign: item.callsign,
                                            countryIso: item.countryIso,
                                            isOwner: item.isOwner,
                                            point: plottedPoint.point,
                                            movement: plottedPoint.movement,
                                            deltaFromPrev: delta,
                                            color: color,
                                            position: plottedPoint.position
                                        )
                                    }
                                }
                            }
                            .onHover { isHovered in
                                if isHovered {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .help(pointHelp(item: item, plottedPoint: plottedPoint))
                            .position(plottedPoint.position)
                        }
                    }

                    axisLabel("▲ +\(formattedNumber(maxAbsMovement))", color: .green)
                        .position(x: 26, y: 14)
                    axisLabel("0", color: .secondary)
                        .position(x: 38, y: origin.y)
                    axisLabel("▼ -\(formattedNumber(maxAbsMovement))", color: .orange)
                        .position(x: 26, y: 12 + plotHeight)

                    if let first = visibleDates.first {
                        dateLabel(first)
                            .position(x: 70, y: geometry.size.height - 10)
                    }
                    if visibleDates.count > 1, let last = visibleDates.last {
                        dateLabel(last)
                            .position(x: geometry.size.width - 38, y: geometry.size.height - 10)
                    }

                    // Interactive day bullet vertical guide and details card popover
                    if let detail = selectedPointDetail {
                        Path { path in
                            path.move(to: CGPoint(x: detail.position.x, y: 12))
                            path.addLine(to: CGPoint(x: detail.position.x, y: 12 + plotHeight))
                        }
                        .stroke(detail.color.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))

                        pointDetailPopover(detail, in: geometry.size)
                    }
                }
            }
        }
    }

    private func pointDetailPopover(_ detail: SelectedPointDetail, in size: CGSize) -> some View {
        let cardWidth: CGFloat = 220
        let cardHeight: CGFloat = 82
        let posX = min(max(detail.position.x, cardWidth / 2 + 10), size.width - cardWidth / 2 - 10)
        let posY = detail.position.y > 90 ? detail.position.y - 52 : detail.position.y + 52

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(detail.color).frame(width: 8, height: 8)
                Text(countryToFlag(detail.countryIso ?? ""))
                    .font(.caption)
                Text(detail.callsign)
                    .font(.system(size: 11.5, weight: .heavy, design: .monospaced))
                    .foregroundColor(.primary)
                if detail.isOwner {
                    Text("YOU")
                        .font(.system(size: 7.5, weight: .black))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.2), in: Capsule())
                        .foregroundStyle(.blue)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.2)) { selectedPointDetail = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatter.string(from: detail.point.date))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                    Text("Rank: #\(detail.point.rank.formatted())")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    let net = detail.movement
                    Text(net >= 0 ? "▲ +\(net)" : "▼ \(net)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(net > 0 ? .green : (net < 0 ? .orange : .secondary))
                    if let d = detail.deltaFromPrev {
                        Text(d >= 0 ? "(+\(d) daily)" : "(\(d) daily)")
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(d >= 0 ? .green : .red)
                    }
                }
            }
        }
        .padding(8)
        .frame(width: cardWidth, height: cardHeight)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(detail.color, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 3)
        .position(x: posX, y: posY)
    }

    private func visiblePoints(_ points: [RankTrendPoint]) -> [RankTrendPoint] {
        guard let firstVisibleDate = visibleDates.first else { return [] }
        return points
            .filter { Calendar.current.startOfDay(for: $0.date) >= firstVisibleDate }
            .sorted { $0.date < $1.date }
    }

    private func plottedPoints(
        for points: [RankTrendPoint],
        origin: CGPoint,
        plotWidth: CGFloat,
        step: CGFloat,
        yScale: CGFloat
    ) -> [PlottedPoint] {
        let points = visiblePoints(points)
        guard let startingRank = points.first?.rank else { return [] }
        let indexByDay = Dictionary(uniqueKeysWithValues: visibleDates.enumerated().map {
            (Calendar.current.startOfDay(for: $0.element), $0.offset)
        })

        return points.compactMap { point in
            let day = Calendar.current.startOfDay(for: point.date)
            guard let dayIndex = indexByDay[day] else { return nil }
            let movement = startingRank - point.rank
            let x = visibleDates.count > 1
                ? origin.x + CGFloat(dayIndex) * step
                : origin.x + plotWidth / 2
            return PlottedPoint(
                point: point,
                movement: movement,
                position: CGPoint(x: x, y: origin.y - CGFloat(movement) * yScale)
            )
        }
    }

    private func chartGrid(width: CGFloat, height: CGFloat, origin: CGPoint) -> some View {
        Path { path in
            for row in 0...4 {
                let y = 12 + CGFloat(row) * height / 4
                path.move(to: CGPoint(x: origin.x, y: y))
                path.addLine(to: CGPoint(x: width - 8, y: y))
            }
            path.move(to: CGPoint(x: origin.x, y: 12))
            path.addLine(to: CGPoint(x: origin.x, y: 12 + height))
        }
        .stroke(Color.gray.opacity(0.18), lineWidth: 1)
        .overlay(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: origin.x, y: origin.y))
                path.addLine(to: CGPoint(x: width - 8, y: origin.y))
            }
            .stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        }
    }

    private func linePath(_ coordinates: [CGPoint]) -> Path {
        Path { path in
            guard let first = coordinates.first else { return }
            path.move(to: first)
            for point in coordinates.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func pointHelp(item: RankTrendSeries, plottedPoint: PlottedPoint) -> String {
        let movement: String
        if plottedPoint.movement > 0 {
            movement = "climbed \(formattedNumber(plottedPoint.movement)) places"
        } else if plottedPoint.movement < 0 {
            movement = "slipped \(formattedNumber(abs(plottedPoint.movement))) places"
        } else {
            movement = "starting point"
        }
        return "\(item.callsign) · \(plottedPoint.point.label) · rank #\(formattedNumber(plottedPoint.point.rank)) · \(movement)"
    }

    private func axisLabel(_ value: String, color: Color) -> some View {
        Text(value)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(color)
    }

    private func dateLabel(_ date: Date) -> some View {
        Text(date.formatted(.dateTime.month(.abbreviated).day()))
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func formattedNumber(_ value: Int) -> String {
        NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}

// MARK: - Player Profile Banner Card
struct PlayerCard: View {
    let title: String
    let callsign: String
    let countryIso: String?
    let isOwner: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            if isOwner {
                Text(countryToFlag(countryIso ?? ""))
                    .font(.system(size: 40))
            }
            
            VStack(alignment: isOwner ? .leading : .trailing, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isOwner ? .blue : .purple)
                
                Text(callsign)
                    .font(.system(size: 28, weight: .heavy, design: .monospaced))
                    .foregroundColor(.primary)
            }
            
            if !isOwner {
                Text(countryToFlag(countryIso ?? ""))
                    .font(.system(size: 40))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: isOwner ? .leading : .trailing)
        .background(isOwner ? Color.blue.opacity(0.1) : Color.purple.opacity(0.1))
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(isOwner ? Color.blue.opacity(0.3) : Color.purple.opacity(0.3), lineWidth: 1.5))
    }
}

struct RivalComparisonPanel: View {
    let owner: QRZRankResponse?
    let rival: QRZRankResponse

    private var isSelf: Bool {
        owner?.callsign?.uppercased() == rival.callsign?.uppercased()
    }

    var body: some View {
        VStack(spacing: 12) {
            PlayerCard(
                title: isSelf ? "TARGET" : "RIVAL OPERATOR",
                callsign: rival.callsign ?? "UNKNOWN",
                countryIso: rival.country_iso,
                isOwner: false
            )

            ComparisonRow(
                category: "QSO World Rank",
                icon: "antenna.radiowaves.left.and.right",
                ownerRank: owner?.rank_qso,
                searchedRank: rival.rank_qso,
                ownerScore: owner?.score_qso,
                searchedScore: rival.score_qso,
                isSelf: isSelf
            )

            ComparisonRow(
                category: "Bands World Rank",
                icon: "waveform.path.ecg",
                ownerRank: owner?.rank_band,
                searchedRank: rival.rank_band,
                ownerScore: owner?.score_band,
                searchedScore: rival.score_band,
                isSelf: isSelf
            )

            ComparisonRow(
                category: "DXCC World Rank",
                icon: "globe.americas.fill",
                ownerRank: owner?.rank_countries,
                searchedRank: rival.rank_countries,
                ownerScore: owner?.score_countries,
                searchedScore: rival.score_countries,
                isSelf: isSelf
            )
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.purple.opacity(0.22), lineWidth: 1))
    }
}

// MARK: - Head-to-Head Comparison Row Widget
struct ComparisonRow: View {
    let category: String
    let icon: String
    let ownerRank: String?
    let searchedRank: String?
    let ownerScore: String?
    let searchedScore: String?
    let isSelf: Bool
    
    // In rankings, LOWER number is BETTER! (#100 > #5000)
    private var deltaText: (text: String, color: Color, icon: String) {
        guard !isSelf,
              let oInt = parseRankInt(ownerRank),
              let sInt = parseRankInt(searchedRank) else {
            return ("Equal", .gray, "minus")
        }
        
        let diff = abs(oInt - sInt)
        let formattedDiff = NumberFormatter.localizedString(from: NSNumber(value: diff), number: .decimal)
        
        if oInt < sInt {
            return (" You lead by \(formattedDiff) ranks", .green, "arrow.up.circle.fill")
        } else if oInt > sInt {
            return ("\(formattedDiff) ranks behind", .red, "arrow.down.circle.fill")
        } else {
            return ("Tied Rank", .gray, "equal.circle.fill")
        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Category Title & Delta Badge
            HStack {
                Label(category, systemImage: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !isSelf {
                    HStack(spacing: 4) {
                        Image(systemName: deltaText.icon)
                        Text(deltaText.text)
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(deltaText.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(deltaText.color.opacity(0.12))
                    .cornerRadius(8)
                }
            }
            
            // Side by Side Stats Grid
            HStack(spacing: 0) {
                // Left: Owner Rank
                VStack(spacing: 2) {
                    Text(ownerRank ?? "N/A")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(.blue)
                    Text("Score: \(ownerScore ?? "N/A")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                Divider().frame(height: 30)
                
                // Right: Rival Rank
                VStack(spacing: 2) {
                    Text(searchedRank ?? "N/A")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(.purple)
                    Text("Score: \(searchedScore ?? "N/A")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - 360° Radial Performance & Rank Radar Dashboard

struct Leaderboard360RadarView: View {
    let owner: QRZRankResponse?
    let rivals: [QRZRankResponse]
    let stationRecords: [QSORecordModel]

    @State private var selectedOperatorCall: String = ""

    private var availableOperators: [(title: String, isOwner: Bool, response: QRZRankResponse)] {
        var list: [(title: String, isOwner: Bool, response: QRZRankResponse)] = []
        if let owner, let call = owner.callsign, !call.isEmpty {
            list.append(("YOU (\(call))", true, owner))
        }
        for r in rivals {
            if let call = r.callsign, !call.isEmpty, call.uppercased() != owner?.callsign?.uppercased() {
                list.append((call, false, r))
            }
        }
        return list
    }

    private var activeOperator: (title: String, isOwner: Bool, response: QRZRankResponse)? {
        if let found = availableOperators.first(where: { $0.response.callsign?.uppercased() == selectedOperatorCall.uppercased() }) {
            return found
        }
        return availableOperators.first
    }

    // QRZ Leaderboard Potentials:
    // 12 amateur bands * 340 active entities = 4,080 total Band-Countries
    private let totalBandCountriesPotential: Double = 4080.0
    // 340 currently active DXCC entities
    private let totalActiveDXCCEntities: Double = 340.0

    // 360° Percentile & Coverage Calculations (0.02 to 1.0)
    private func qsoPercentile(for rankStr: String?) -> Double {
        guard let rank = parseRankInt(rankStr), rank > 0 else { return 0.25 }
        let normalized = max(0.05, min(1.0, 1.0 - (Double(rank) / 75_000.0)))
        return normalized
    }

    private func bandCoverage(for scoreBandStr: String?, isOwner: Bool) -> Double {
        let count: Double
        if let parsed = parseRankInt(scoreBandStr), parsed > 0 {
            count = Double(parsed)
        } else if isOwner {
            var uniqueBandCountries = Set<String>()
            for r in stationRecords {
                let country = r["COUNTRY"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let band = r["BAND"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if !country.isEmpty && !band.isEmpty {
                    uniqueBandCountries.insert("\(country)|\(band)")
                }
            }
            count = Double(uniqueBandCountries.count)
        } else {
            count = 0
        }
        return max(0.02, min(1.0, count / totalBandCountriesPotential))
    }

    private func dxccCoverage(for scoreCountriesStr: String?, isOwner: Bool) -> Double {
        let count: Double
        if let parsed = parseRankInt(scoreCountriesStr), parsed > 0 {
            count = Double(parsed)
        } else if isOwner {
            let uniqueCountries = Set(stationRecords.map { $0["COUNTRY"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty })
            count = Double(uniqueCountries.count)
        } else {
            count = 0
        }
        return max(0.02, min(1.0, count / totalActiveDXCCEntities))
    }

    private var todaysQSOCount: Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let todayStr = formatter.string(from: Date())
        return stationRecords.filter { $0["QSO_DATE"].replacingOccurrences(of: "-", with: "") == todayStr }.count
    }

    var body: some View {
        let op = activeOperator
        let target = op?.response
        let isOwner = op?.isOwner ?? true

        let qsoVal = qsoPercentile(for: target?.rank_qso)
        let bandVal = bandCoverage(for: target?.score_band, isOwner: isOwner)
        let dxccVal = dxccCoverage(for: target?.score_countries, isOwner: isOwner)
        let composite = Int(((qsoVal + bandVal + dxccVal) / 3.0) * 100.0)

        VStack(alignment: .leading, spacing: 14) {
            // Header with title and operator segmented picker
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "circle.circle.fill")
                        .foregroundColor(.cyan)
                    Text("360° Radar Performance & Rank Dashboard")
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Spacer()

                if availableOperators.count > 1 {
                    Picker("Operator", selection: Binding(
                        get: { activeOperator?.response.callsign ?? "" },
                        set: { selectedOperatorCall = $0 }
                    )) {
                        ForEach(availableOperators, id: \.response.callsign) { item in
                            Text(item.title).tag(item.response.callsign ?? "")
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(maxWidth: 340)
                }
            }

            HStack(alignment: .center, spacing: 22) {
                // ─── 1. Concentric 360° Radial Gauge ───
                ZStack {
                    // Radar crosshair lines
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        .frame(width: 190, height: 190)

                    Path { path in
                        path.move(to: CGPoint(x: 95, y: 0))
                        path.addLine(to: CGPoint(x: 95, y: 190))
                        path.move(to: CGPoint(x: 0, y: 95))
                        path.addLine(to: CGPoint(x: 190, y: 95))
                    }
                    .stroke(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: 190, height: 190)

                    // Outer Ring: QSO World Standing (360°)
                    Circle()
                        .stroke(Color.blue.opacity(0.14), lineWidth: 10)
                        .frame(width: 176, height: 176)
                    Circle()
                        .trim(from: 0, to: CGFloat(qsoVal))
                        .stroke(
                            LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 176, height: 176)
                        .rotationEffect(.degrees(-90))

                    // Middle Ring: Band Coverage (360°)
                    Circle()
                        .stroke(Color.orange.opacity(0.14), lineWidth: 10)
                        .frame(width: 146, height: 146)
                    Circle()
                        .trim(from: 0, to: CGFloat(bandVal))
                        .stroke(
                            LinearGradient(colors: [.orange, .yellow], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 146, height: 146)
                        .rotationEffect(.degrees(-90))

                    // Inner Ring: DXCC Countries Reach (360°)
                    Circle()
                        .stroke(Color.green.opacity(0.14), lineWidth: 10)
                        .frame(width: 116, height: 116)
                    Circle()
                        .trim(from: 0, to: CGFloat(dxccVal))
                        .stroke(
                            LinearGradient(colors: [.green, .mint], startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 116, height: 116)
                        .rotationEffect(.degrees(-90))

                    // Center Hub Core
                    VStack(spacing: 1) {
                        Text(countryToFlag(target?.country_iso ?? ""))
                            .font(.title3)
                        Text("\(composite)%")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("360° INDEX")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(.secondary)
                            .tracking(1)
                    }
                }
                .frame(width: 195, height: 195)

                // ─── 2. Multi-Metric Performance Cards ───
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        radarMetricTile(
                            title: "QSO WORLD STANDING",
                            value: target?.rank_qso ?? "N/A",
                            subtitle: "\(Int(qsoVal * 100))th Percentile Tier",
                            icon: "antenna.radiowaves.left.and.right",
                            color: .blue,
                            progress: qsoVal
                        )

                        radarMetricTile(
                            title: "BAND COVERAGE",
                            value: target?.rank_band ?? "N/A",
                            subtitle: "\(target?.score_band ?? "0") / 4,080 Band-Countries",
                            icon: "waveform.path.ecg",
                            color: .orange,
                            progress: bandVal
                        )
                    }

                    HStack(spacing: 12) {
                        radarMetricTile(
                            title: "DXCC ENTITY REACH",
                            value: target?.rank_countries ?? "N/A",
                            subtitle: "\(target?.score_countries ?? "0") / 340 Active DXCC",
                            icon: "globe.americas.fill",
                            color: .green,
                            progress: dxccVal
                        )

                        radarDailyVelocityTile(
                            isOwner: isOwner,
                            todaysQSOs: todaysQSOCount,
                            target: target
                        )
                    }
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.65))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.25), lineWidth: 1))
    }

    private func radarMetricTile(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        color: Color,
        progress: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                Spacer()
                Text("\(Int(round(progress * 100)))%")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(color)
            }

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(.primary)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(color)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(7)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.2), lineWidth: 1))
    }

    private func radarDailyVelocityTile(
        isOwner: Bool,
        todaysQSOs: Int,
        target: QRZRankResponse?
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.cyan)
                Text("DAILY PERFORMANCE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                Spacer()
                if isOwner {
                    Text("LIVE")
                        .font(.system(size: 8, weight: .black))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.2), in: Capsule())
                        .foregroundColor(.green)
                }
            }

            if isOwner {
                Text("\(todaysQSOs) QSOs Today")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)

                ProgressView(value: min(1.0, Double(todaysQSOs) / 25.0))
                    .progressViewStyle(.linear)
                    .tint(.cyan)

                Text(todaysQSOs >= 20 ? "🔥 Outstanding daily logging pace!" : (todaysQSOs > 0 ? "Steady daily activity." : "No QSOs logged today yet."))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Text(target?.callsign ?? "RIVAL")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)

                ProgressView(value: 0.75)
                    .progressViewStyle(.linear)
                    .tint(.purple)

                Text("Tracked rival in Leaderboard")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.textBackgroundColor))
        .cornerRadius(7)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.cyan.opacity(0.2), lineWidth: 1))
    }
}

