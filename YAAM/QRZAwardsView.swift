//
//  QRZAwardsView.swift
//  YAAM
//
//  Multi-source awards hub — macOS native sidebar layout
//

import SwiftUI

// MARK: - Award Source

enum AwardSource: String, CaseIterable, Identifiable {
    case qrz      = "QRZ"
    case eqsl     = "eQSL"
    case clublog  = "ClubLog"
    case combined = "All Sources"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .qrz:      return "globe.badge.chevron.backward"
        case .eqsl:     return "envelope.badge.shield.half.filled.fill"
        case .clublog:  return "person.3.fill"
        case .combined: return "star.circle.fill"
        }
    }

    var gradient: [Color] {
        switch self {
        case .qrz:      return [Color(hue: 0.60, saturation: 0.80, brightness: 0.94),
                                Color(hue: 0.63, saturation: 0.90, brightness: 0.72)]
        case .eqsl:     return [Color(hue: 0.38, saturation: 0.76, brightness: 0.88),
                                Color(hue: 0.43, saturation: 0.90, brightness: 0.60)]
        case .clublog:  return [Color(hue: 0.07, saturation: 0.86, brightness: 0.98),
                                Color(hue: 0.04, saturation: 0.92, brightness: 0.74)]
        case .combined: return [Color(hue: 0.76, saturation: 0.68, brightness: 0.92),
                                Color(hue: 0.80, saturation: 0.85, brightness: 0.66)]
        }
    }

    var accentColor: Color { gradient[0] }

    var subtitle: String {
        switch self {
        case .qrz:      return "Fetched live from QRZ.com Logbook"
        case .eqsl:     return "Computed from eQSL-confirmed QSOs in log"
        case .clublog:  return "Personal DXCC matrix via Club Log API"
        case .combined: return "Union of all confirmed QSOs — all services"
        }
    }

    var sidebarLabel: String {
        switch self {
        case .qrz:      return "QRZ Logbook"
        case .eqsl:     return "eQSL Awards"
        case .clublog:  return "Club Log DXCC"
        case .combined: return "All Sources"
        }
    }
}

// MARK: - Data Models

struct QRZAwardSummary: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let detail: String
    let percentComplete: Double
    let status: String
    let earned: Bool
    let progressAvailable: Bool
    let achievement: String
    let awardType: String
    let ribbonURL: String

    var remainingPercent: Double { max(0, 100 - percentComplete) }
    var progressText: String { progressAvailable ? "\(Int(percentComplete.rounded()))%" : "--" }
}

struct QRZAwardsFetchResult {
    let awards: [QRZAwardSummary]
    let message: String
}

// MARK: - Main View

struct QRZAwardsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSource: AwardSource = .qrz
    @State private var animateIcon: Bool = false

    // MARK: Filtered QSO subsets

    private var eqslRecords: [QSORecordModel] {
        appState.qsoRecords.filter {
            ["Y","V","C"].contains($0["EQSL_QSL_RCVD"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
        }
    }
    private var clublogRecords: [QSORecordModel] {
        appState.qsoRecords.filter {
            $0["CLUBLOG_QSO_UPLOAD_STATUS"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "Y"
        }
    }
    private var allConfirmedRecords: [QSORecordModel] {
        appState.qsoRecords.filter(\.isConfirmed)
    }

    // MARK: Effective awards

    private var effectiveAwards: [QRZAwardSummary] {
        switch selectedSource {
        case .qrz:
            if !appState.qrzAwardSummaries.isEmpty { return appState.qrzAwardSummaries }
            return buildLogbookAwards(from: allConfirmedRecords)
        case .eqsl:
            return buildEQSLAwards(from: eqslRecords)
        case .clublog:
            return appState.clubLogDXCCMatrix?.toAwardSummaries()
                ?? buildLogbookAwards(from: clublogRecords)
        case .combined:
            return buildLogbookAwards(from: allConfirmedRecords)
        }
    }

    private var earnedAwards:     [QRZAwardSummary] { effectiveAwards.filter(\.earned).sorted { $0.title < $1.title } }
    private var inProgressAwards: [QRZAwardSummary] {
        effectiveAwards.filter { !$0.earned }.sorted { $0.percentComplete > $1.percentComplete }
    }

    // MARK: Body ─ Sidebar + Content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {

            // ── LEFT SIDEBAR ──────────────────────────────────────
            sourceSidebar

            // ── DIVIDER ───────────────────────────────────────────
            Divider()

            // ── RIGHT CONTENT ─────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    contentHeader
                    statsRow
                    mainContent
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { animateIcon = true }
            if selectedSource == .qrz && appState.qrzAwardSummaries.isEmpty && !appState.isFetchingQRZAwards {
                appState.fetchQRZAwards()
            }
        }
        .onChange(of: selectedSource) { _, newSrc in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                animateIcon = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { animateIcon = true }
            }
            if newSrc == .qrz && appState.qrzAwardSummaries.isEmpty && !appState.isFetchingQRZAwards {
                appState.fetchQRZAwards()
            }
            if newSrc == .clublog && appState.clubLogDXCCMatrix == nil && !appState.isFetchingClubLogAwards {
                appState.fetchClubLogDXCCMatrix()
            }
        }
    }

    // MARK: ── Left Sidebar ───────────────────────────────────────

    private var sourceSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(colors: [.yellow, .orange],
                                           startPoint: .top, endPoint: .bottom)
                        )
                    Text("Awards Hub")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Text("QRZ, eQSL, ClubLog achievements")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().padding(.horizontal, 10)

            // Source label
            Text("DATA SOURCES")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1.2)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            // Source navigation items
            ForEach(AwardSource.allCases) { source in
                sidebarNavItem(source)
            }

            Divider().padding(.horizontal, 10).padding(.top, 10)

            // Status / loading
            sidebarStatusArea

            Spacer()
        }
        .frame(width: 190)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
    }

    private func sidebarNavItem(_ source: AwardSource) -> some View {
        let isSelected = selectedSource == source
        let count      = recordCount(for: source)

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                selectedSource = source
            }
        } label: {
            HStack(spacing: 11) {
                // Gradient icon tile
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(colors: source.gradient,
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)
                        )
                        .frame(width: 34, height: 34)
                        .shadow(color: source.accentColor.opacity(0.30), radius: 4, x: 0, y: 2)

                    Image(systemName: source.icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }

                // Label + count
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.sidebarLabel)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? source.accentColor : .primary)
                        .lineLimit(1)
                    if count > 0 {
                        Text(formatCount(count, source: source))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(source.accentColor)
                        .frame(width: 3, height: 20)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                          ? source.accentColor.opacity(0.10)
                          : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false).focusEffectDisabled()
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var sidebarStatusArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Fetching indicator
            if appState.isFetchingQRZAwards || appState.isFetchingClubLogAwards {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(appState.isFetchingQRZAwards ? "Fetching QRZ…" : "Fetching ClubLog…")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }

            // Status string
            let status = currentStatusText
            if !status.isEmpty {
                Text(status)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 14)
                    .padding(.top, appState.isFetchingQRZAwards || appState.isFetchingClubLogAwards ? 4 : 10)
            }
        }
    }

    private var currentStatusText: String {
        switch selectedSource {
        case .qrz:      return appState.qrzAwardsStatus
        case .clublog:  return appState.clubLogAwardsStatus
        case .eqsl:     return eqslRecords.isEmpty ? "Sync eQSL inbox in QSL Hub first." : "\(eqslRecords.count) confirmed cards in log"
        case .combined: return "\(allConfirmedRecords.count) total confirmed QSOs"
        }
    }

    private func formatCount(_ count: Int, source: AwardSource) -> String {
        let unit: String
        switch source {
        case .qrz:      unit = count == 1 ? "award" : "awards"
        case .eqsl:     unit = count == 1 ? "confirmed card" : "confirmed cards"
        case .clublog:  unit = count == 1 ? "entity" : "entities confirmed"
        case .combined: unit = count == 1 ? "confirmed QSO" : "confirmed QSOs"
        }
        if count >= 1_000_000 { return String(format: "%.1fM \(unit)", Double(count) / 1_000_000) }
        if count >= 1_000     { return String(format: "%.1fK \(unit)", Double(count) / 1_000) }
        return "\(count) \(unit)"
    }

    private func recordCount(for source: AwardSource) -> Int {
        switch source {
        case .qrz:      return appState.qrzAwardSummaries.count
        case .eqsl:     return eqslRecords.count
        case .clublog:  return appState.clubLogDXCCMatrix?.totalConfirmed ?? 0
        case .combined: return allConfirmedRecords.count
        }
    }

    // MARK: ── Content Header ─────────────────────────────────────

    private var contentHeader: some View {
        ZStack(alignment: .leading) {
            // Gradient background
            LinearGradient(
                colors: selectedSource.gradient.map { $0.opacity(0.82) },
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .cornerRadius(14)

            // Decorative bubbles
            HStack {
                Spacer()
                ZStack {
                    Circle().fill(.white.opacity(0.05)).frame(width: 150).offset(x: 30, y: -20)
                    Circle().fill(.white.opacity(0.04)).frame(width: 90).offset(x: -20, y: 30)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 16) {
                // Animated source icon
                ZStack {
                    Circle().fill(.white.opacity(0.16)).frame(width: 52, height: 52)
                    Image(systemName: selectedSource.icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .scaleEffect(animateIcon ? 1.0 : 0.6)
                        .opacity(animateIcon ? 1.0 : 0.0)
                        .animation(.spring(response: 0.45, dampingFraction: 0.65), value: animateIcon)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(selectedSource.rawValue) Awards")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(selectedSource.subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }

                Spacer()

                // Action button
                actionButton
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(height: 82)
        .shadow(color: selectedSource.accentColor.opacity(0.28), radius: 12, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.30), value: selectedSource)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch selectedSource {
        case .qrz:
            actionPill(
                label: appState.isFetchingQRZAwards ? "Loading…" : "Refresh",
                icon: "arrow.clockwise",
                disabled: appState.isFetchingQRZAwards
            ) { appState.fetchQRZAwards() }

        case .clublog:
            actionPill(
                label: appState.isFetchingClubLogAwards ? "Loading…" : "Fetch Matrix",
                icon: "arrow.down.circle",
                disabled: appState.isFetchingClubLogAwards
            ) { appState.fetchClubLogDXCCMatrix() }

        case .eqsl:
            actionPill(label: "Open eQSL.cc", icon: "safari", disabled: false) {
                if let url = URL(string: "https://www.eqsl.cc/qslcard/Awards.cfm") {
                    NSWorkspace.shared.open(url)
                }
            }

        case .combined:
            actionPill(label: "Sync All", icon: "arrow.triangle.2.circlepath", disabled: false) {
                appState.downloadLoTWAndQRZConfirmations()
            }
        }
    }

    private func actionPill(label: String, icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(.white.opacity(0.18), in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .focusable(false).focusEffectDisabled()
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1.0)
    }

    // MARK: ── Stats Row ──────────────────────────────────────────

    private var statsRow: some View {
        HStack(spacing: 10) {
            switch selectedSource {
            case .qrz, .combined:
                statCard("Awarded",   value: "\(earnedAwards.count)",              icon: "checkmark.seal.fill", color: .green)
                statCard("Analyzed",  value: "\(effectiveAwards.count)",           icon: "square.grid.2x2.fill", color: selectedSource.accentColor)
                statCard("Average",   value: "\(Int(avgProgress.rounded()))%",     icon: "gauge.with.dots.needle.50percent", color: .purple)
                statCard("Closest",   value: bestProgressText,                     icon: "target", color: .orange)

            case .eqsl:
                let dxcc = Set(eqslRecords.map { $0["DXCC"] }.filter { !$0.isEmpty }).count
                statCard("eQSL Cards", value: "\(eqslRecords.count)",   icon: "envelope.badge.shield.half.filled.fill", color: .green)
                statCard("Countries",  value: "\(dxcc)",                icon: "globe",               color: selectedSource.accentColor)
                statCard("Awarded",    value: "\(earnedAwards.count)",  icon: "checkmark.seal.fill", color: .yellow)
                statCard("AGM Level",  value: agmLevelText(eqslRecords.count), icon: "medal.fill", color: .orange)

            case .clublog:
                if let matrix = appState.clubLogDXCCMatrix {
                    statCard("Confirmed",  value: "\(matrix.totalConfirmed)", icon: "checkmark.seal.fill",                    color: .green)
                    statCard("Worked",     value: "\(matrix.totalWorked)",    icon: "antenna.radiowaves.left.and.right",       color: selectedSource.accentColor)
                    statCard("Continents", value: "\(matrix.continentsConfirmed.count)/6", icon: "globe",                    color: .purple)
                    statCard("Bands",      value: "\(activeBands(matrix))",   icon: "waveform",                               color: .orange)
                } else if appState.isFetchingClubLogAwards {
                    loadingStatCards
                } else {
                    placeholderStatCards
                }
            }
        }
    }

    private var loadingStatCards: some View {
        ForEach(0..<4, id: \.self) { _ in
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
                .frame(height: 78)
                .overlay(ProgressView().controlSize(.small))
                .frame(maxWidth: .infinity)
        }
    }

    private var placeholderStatCards: some View {
        ForEach(0..<4, id: \.self) { _ in
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.30))
                .frame(height: 78)
                .overlay(Image(systemName: "ellipsis").foregroundStyle(.secondary))
                .frame(maxWidth: .infinity)
        }
    }

    private func statCard(_ title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.headline, design: .rounded).bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.20)))
    }

    private var avgProgress: Double {
        let items = effectiveAwards.filter(\.progressAvailable)
        guard !items.isEmpty else { return 0 }
        return items.reduce(0) { $0 + $1.percentComplete } / Double(items.count)
    }
    private var bestProgressText: String {
        guard let top = inProgressAwards.filter(\.progressAvailable).first else { return "All done!" }
        return "\(Int(top.remainingPercent.rounded()))% left"
    }
    private func agmLevelText(_ count: Int) -> String {
        if count >= 5000 { return "Platinum" }
        if count >= 1000 { return "Gold" }
        if count >= 500  { return "Silver" }
        if count >= 100  { return "Bronze" }
        return "\(count)/100"
    }
    private func activeBands(_ matrix: ClubLogDXCCMatrix) -> Int {
        Set(matrix.entities.flatMap { $0.confirmedBands }).count
    }

    // MARK: ── Main Content ───────────────────────────────────────

    @ViewBuilder
    private var mainContent: some View {
        switch selectedSource {
        case .qrz, .combined:
            standardAwardsContent

        case .eqsl:
            VStack(alignment: .leading, spacing: 16) {
                agmTierView
                lotwProgressPanel
                standardAwardsContent
            }

        case .clublog:
            VStack(alignment: .leading, spacing: 16) {
                if let matrix = appState.clubLogDXCCMatrix {
                    clubLogBandMatrix(matrix)
                } else if appState.isFetchingClubLogAwards {
                    loadingPanel("Fetching DXCC matrix from Club Log…")
                } else {
                    clubLogEmptyState
                }
                standardAwardsContent
            }
        }
    }

    // MARK: Standard Awards

    @ViewBuilder
    private var standardAwardsContent: some View {
        if effectiveAwards.isEmpty {
            emptyState
        } else {
            if !earnedAwards.isEmpty     { awardSection(title: "🏆 Awarded",     awards: earnedAwards) }
            if !inProgressAwards.isEmpty { awardSection(title: "📈 In Progress", awards: inProgressAwards) }

            let footer = currentStatusText
            if !footer.isEmpty && !footer.contains("confirmed") {
                HStack(spacing: 5) {
                    Image(systemName: "info.circle").font(.caption2)
                    Text(footer).font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
        }
    }

    private func awardSection(title: String, awards: [QRZAwardSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 280, maximum: 340), spacing: 12)],
                alignment: .leading, spacing: 12
            ) {
                ForEach(awards) { award in
                    AwardCard(award: award, accentColor: selectedSource.accentColor)
                }
            }
        }
    }

    // MARK: eQSL AGM Tier

    private var agmTierView: some View {
        let count  = eqslRecords.count
        let tiers: [(name: String, min: Int, color: Color, icon: String)] = [
            ("Bronze",   100,  Color(hue: 0.07, saturation: 0.68, brightness: 0.72), "medal.fill"),
            ("Silver",   500,  Color(hue: 0.00, saturation: 0.00, brightness: 0.82), "medal.fill"),
            ("Gold",     1000, Color(hue: 0.13, saturation: 0.88, brightness: 0.98), "medal.fill"),
            ("Platinum", 5000, Color(hue: 0.55, saturation: 0.32, brightness: 0.90), "crown.fill"),
        ]
        let _ = tiers.last { count >= $0.min }
        let next = tiers.first { count < $0.min }

        return VStack(alignment: .leading, spacing: 12) {
            Label("eQSL AGM — Authenticard Gold Medal", systemImage: "medal.fill")
                .font(.headline)

            HStack(spacing: 0) {
                ForEach(tiers, id: \.name) { tier in
                    let achieved = count >= tier.min
                    VStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(achieved ? tier.color.opacity(0.18) : Color(NSColor.controlBackgroundColor).opacity(0.4))
                                .frame(width: 44, height: 44)
                            Image(systemName: tier.icon)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(achieved ? tier.color : Color.secondary.opacity(0.28))
                        }
                        Text(tier.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(achieved ? tier.color : .secondary)
                        Text("\(tier.min)+")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    if tier.name != "Platinum" {
                        Rectangle()
                            .fill(count >= tier.min ? Color.green.opacity(0.45) : Color.secondary.opacity(0.18))
                            .frame(height: 2).frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 4)

            if let next {
                let prev = tiers.last { count >= $0.min }?.min ?? 0
                let progress = min(1.0, Double(count - prev) / Double(max(1, next.min - prev)))
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Progress to \(next.name)")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(count) / \(next.min)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.14))
                            Capsule().fill(LinearGradient(colors: [next.color.opacity(0.7), next.color],
                                                          startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 8)
                }
            } else {
                Label("Platinum achieved! \(count) AG confirmations", systemImage: "crown.fill")
                    .font(.caption).foregroundStyle(.yellow)
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.24)))
    }

    // MARK: LoTW Panel

    private var lotwProgressPanel: some View {
        let lotwRecs = appState.qsoRecords.filter {
            ["Y","V","C","CONFIRMED"].contains($0["LOTW_QSL_RCVD"].uppercased())
        }
        let dxcc   = Set(lotwRecs.map { $0["DXCC"] }.filter { !$0.isEmpty }).count
        let states = Set(lotwRecs.map { $0["STATE"].uppercased() }.filter { !$0.isEmpty }).count
        let grids  = Set(lotwRecs.filter { $0["BAND"].lowercased() == "6m" }.map {
            ($0["GRIDSQUARE"].isEmpty ? $0["GRID"] : $0["GRIDSQUARE"]).uppercased()
        }.filter { !$0.isEmpty }).count

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("LoTW Progress", systemImage: "checkmark.seal.fill").font(.headline)
                Spacer()
                Button {
                    appState.downloadLoTWAndQRZConfirmations()
                } label: {
                    Label("Sync", systemImage: "arrow.clockwise.icloud").font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(appState.isSyncingAPI)
            }
            HStack(spacing: 10) {
                lotwMetric("Confirmed QSOs", "\(lotwRecs.count)", "q.circle.fill",       .green)
                lotwMetric("DXCC",           "\(dxcc)/100",       "globe.americas.fill",  .blue)
                lotwMetric("US States",      "\(states)/50",      "map.fill",             .purple)
                lotwMetric("6m Grids",       "\(grids)",          "square.grid.3x3.fill", .orange)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.50))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.20)))
    }

    private func lotwMetric(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(color).font(.system(size: 12))
            Text(value).font(.system(.subheadline, design: .rounded).bold())
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.40))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.20)))
    }

    // MARK: ClubLog Band Matrix

    private func clubLogBandMatrix(_ matrix: ClubLogDXCCMatrix) -> some View {
        let bands = ClubLogDXCCMatrix.hfBands.filter {
            matrix.confirmedCount(band: $0) > 0 || matrix.workedCount(band: $0) > 0
        }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("DXCC Band Matrix", systemImage: "chart.bar.xaxis").font(.headline)
                Spacer()
                Text("Updated \(matrix.fetchedAt, style: .relative) ago")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if bands.isEmpty {
                Text("No band data found. Fetch the matrix first.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            Text("Band").font(.caption.bold()).frame(width: 52, alignment: .leading).padding(.leading, 6)
                            ForEach(["Worked", "Confirmed", "Progress"], id: \.self) { col in
                                Text(col).font(.caption.bold())
                                    .frame(width: col == "Progress" ? 88 : 74, alignment: .center)
                            }
                        }
                        .padding(.vertical, 6)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.70))

                        Divider()

                        ForEach(Array(bands.enumerated()), id: \.element) { idx, band in
                            let worked    = matrix.workedCount(band: band)
                            let confirmed = matrix.confirmedCount(band: band)
                            let pct       = min(1.0, Double(confirmed) / max(1, Double(worked)))

                            HStack(spacing: 0) {
                                Text(band.uppercased())
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .frame(width: 52, alignment: .leading).padding(.leading, 6)

                                Text("\(worked)")
                                    .font(.system(size: 11, design: .rounded))
                                    .frame(width: 74, alignment: .center)

                                HStack(spacing: 4) {
                                    Text("\(confirmed)")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundStyle(confirmed >= 100 ? .green : selectedSource.accentColor)
                                    if confirmed >= 100 {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.system(size: 9)).foregroundStyle(.green)
                                    }
                                }
                                .frame(width: 74, alignment: .center)

                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.secondary.opacity(0.12))
                                        Capsule()
                                            .fill(pct > 0.9 ? Color.green.opacity(0.68) : selectedSource.accentColor.opacity(0.65))
                                            .frame(width: geo.size.width * pct)
                                    }
                                }
                                .frame(width: 68, height: 7).padding(.horizontal, 10)
                            }
                            .padding(.vertical, 6)
                            .background(idx.isMultiple(of: 2)
                                        ? Color(NSColor.controlBackgroundColor).opacity(0.22)
                                        : Color.clear)
                        }
                    }
                }
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.16)))
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.50))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selectedSource.accentColor.opacity(0.24)))
    }

    private var clubLogEmptyState: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color.orange.opacity(0.55))
            VStack(alignment: .leading, spacing: 4) {
                Text("Club Log DXCC Matrix not loaded")
                    .font(.headline)
                Text(appState.clubLogAwardsStatus.isEmpty
                     ? "Tap \"Fetch Matrix\" to load your DXCC data from Club Log."
                     : appState.clubLogAwardsStatus)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { appState.fetchClubLogDXCCMatrix() } label: {
                Label("Fetch Matrix", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent).tint(.orange)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.50))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.28)))
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: selectedSource.icon)
                .font(.system(size: 46)).foregroundStyle(selectedSource.accentColor.opacity(0.45))
            Text("No award data for \(selectedSource.rawValue)")
                .font(.headline)
            Text(emptySubtitle)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.28))
        .cornerRadius(12)
    }

    private var emptySubtitle: String {
        switch selectedSource {
        case .qrz:
            return appState.qrzAwardsStatus.isEmpty
            ? "Tap Refresh to fetch your QRZ Logbook Awards."
            : appState.qrzAwardsStatus
        case .eqsl:    return "No eQSL confirmations in log. Sync eQSL inbox from QSL Hub first."
        case .clublog:
            return appState.clubLogAwardsStatus.isEmpty
            ? "Configure Club Log credentials in Settings, then tap Fetch Matrix."
            : appState.clubLogAwardsStatus
        case .combined: return "No confirmed QSOs found. Sync LoTW, eQSL, or QRZ first."
        }
    }

    private func loadingPanel(_ message: String) -> some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.regular)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.40))
        .cornerRadius(12)
    }

    // MARK: ── Award Synthesis ────────────────────────────────────

    private func buildEQSLAwards(from records: [QSORecordModel]) -> [QRZAwardSummary] {
        var list = [QRZAwardSummary]()
        guard !records.isEmpty else { return list }

        let total    = records.count
        let dxccSet  = Set(records.map { $0["DXCC"] }.filter { !$0.isEmpty })
        let stateSet = Set(records.map { $0["STATE"].uppercased() }.filter { !$0.isEmpty })
        let contSet  = Set(records.map { $0["CONT"].uppercased() }.filter { !$0.isEmpty })
        let gridSet  = Set(records.map {
            ($0["GRIDSQUARE"].isEmpty ? $0["GRID"] : $0["GRIDSQUARE"]).prefix(4).uppercased()
        }.filter { $0.count == 4 })

        // AGM
        let agmTarget: Int; let agmName: String; let prevThreshold: Int
        if total >= 5000      { agmTarget = 5000; agmName = "Platinum"; prevThreshold = 1000 }
        else if total >= 1000 { agmTarget = 5000; agmName = "Gold";     prevThreshold = 1000 }
        else if total >= 500  { agmTarget = 1000; agmName = "Silver";   prevThreshold = 500  }
        else if total >= 100  { agmTarget = 500;  agmName = "Bronze";   prevThreshold = 100  }
        else                  { agmTarget = 100;  agmName = "Working…"; prevThreshold = 0    }
        let agmPct = min(100, Double(total - prevThreshold) / Double(agmTarget - prevThreshold) * 100)
        list.append(QRZAwardSummary(id: "eqsl_agm", title: "AGM \(agmName)", detail: "\(total) AG eQSL cards received",
            percentComplete: agmPct, status: total >= 5000 ? "Platinum achieved!" : "\(max(0, agmTarget - total)) to next level",
            earned: total >= 100, progressAvailable: true, achievement: "\(total) Confirmations", awardType: "eqsl", ribbonURL: ""))

        list.append(make("eqsl_dxcc", "DX World via eQSL", dxccSet.count, 100, "dxcc", "\(dxccSet.count) entities confirmed", "Entities"))
        list.append(make("eqsl_wac",  "All Continents via eQSL", contSet.count, 6, "continent", contSet.sorted().joined(separator: " · "), "Continents"))
        list.append(make("eqsl_was",  "All US States via eQSL",  stateSet.count, 50, "was", "\(stateSet.count) of 50 states", "States"))
        list.append(make("eqsl_grid", "Grid Award via eQSL (100)", gridSet.count, 100, "grid", "\(gridSet.count) Maidenhead grids", "Grids"))

        let cwRecs  = records.filter { $0["MODE"].uppercased() == "CW" }
        let ssbRecs = records.filter { ["SSB","LSB","USB","FM","AM"].contains($0["MODE"].uppercased()) }
        let digRecs = records.filter { ["FT8","FT4","PSK31","PSK","JS8","WSPR","RTTY","DATA","DIGITAL"].contains($0["MODE"].uppercased()) }
        if cwRecs.count  > 0 { list.append(make("eqsl_cw",  "CW Award via eQSL",      cwRecs.count,  100, "cw",      "\(cwRecs.count) CW QSOs",      "CW QSOs")) }
        if ssbRecs.count > 0 { list.append(make("eqsl_ssb", "Phone Award via eQSL",   ssbRecs.count, 100, "phone",   "\(ssbRecs.count) Phone QSOs",  "Phone QSOs")) }
        if digRecs.count > 0 { list.append(make("eqsl_dig", "Digital Award via eQSL", digRecs.count, 100, "digital", "\(digRecs.count) Digital QSOs","Digital QSOs")) }

        for (band, label, target) in [("160m","160m",50),("80m","80m",100),("40m","40m",100),
                                       ("20m","20m",100),("15m","15m",100),("10m","10m",100),
                                       ("6m","6m Magic Band",50),("2m","2m",25)] as [(String,String,Int)] {
            let recs = records.filter { $0["BAND"].lowercased() == band }
            if recs.count > 0 {
                list.append(make("eqsl_band_\(band)", "\(label) Band Award", recs.count, target, "band", "\(recs.count) QSOs on \(label)", "QSOs on \(band)"))
            }
        }

        for (id, title, code, target) in [("eu","Europe Award","EU",25),("as","Asia Award","AS",25),
                                           ("af","Africa Award","AF",25),("na","North America Award","NA",25),
                                           ("oc","Oceania Award","OC",15),("sa","South America Award","SA",10)] as [(String,String,String,Int)] {
            let ents = Set(records.filter { $0["CONT"].uppercased() == code }.map { $0["DXCC"] }.filter { !$0.isEmpty })
            if !ents.isEmpty {
                list.append(make("eqsl_cont_\(id)", title, ents.count, target, "geographic", "\(ents.count) \(code) entities", "Entities in \(code)"))
            }
        }
        return list
    }

    private func make(_ id: String, _ title: String, _ count: Int, _ target: Int, _ type: String,
                      _ detail: String, _ unit: String) -> QRZAwardSummary {
        let pct = min(100.0, Double(count) / Double(target) * 100)
        return QRZAwardSummary(
            id: id, title: title, detail: detail,
            percentComplete: pct,
            status: count >= target ? "✓ Achieved!" : "\(max(0, target - count)) \(unit) remaining",
            earned: count >= target, progressAvailable: true,
            achievement: "\(count) / \(target) \(unit)", awardType: type, ribbonURL: "")
    }

    private func buildLogbookAwards(from records: [QSORecordModel]) -> [QRZAwardSummary] {
        let dxccSet  = Set(records.map { $0["DXCC"] }.filter { !$0.isEmpty })
        let stateSet = Set(records.map { $0["STATE"].uppercased() }.filter { !$0.isEmpty })
        let contSet  = Set(records.map { $0["CONT"].uppercased() }.filter { !$0.isEmpty })
        let gridSet  = Set(records.map {
            ($0["GRIDSQUARE"].isEmpty ? $0["GRID"] : $0["GRIDSQUARE"]).prefix(4).uppercased()
        }.filter { $0.count == 4 })
        let sixGrids = Set(records.filter { $0["BAND"].lowercased() == "6m" }.map {
            ($0["GRIDSQUARE"].isEmpty ? $0["GRID"] : $0["GRIDSQUARE"]).prefix(4).uppercased()
        }.filter { $0.count == 4 })
        let wpx = Set(records.map { derivePrefix($0["CALL"]) }.filter { !$0.isEmpty })
        return [
            make("dxcc_100", "DX World (DXCC 100)",      dxccSet.count,  100, "dxcc",      "\(dxccSet.count) DXCC entities confirmed",   "Entities"),
            make("wac",      "Worked All Continents",     contSet.count,  6,   "continent", contSet.sorted().joined(separator: " · "),     "Continents"),
            make("was_50",   "Worked All States (WAS)",   stateSet.count, 50,  "was",       "\(stateSet.count) of 50 US states confirmed", "States"),
            make("vucc",     "Grid Master (VUCC 100)",    gridSet.count,  100, "grid",      "\(gridSet.count) Maidenhead grids confirmed", "Grids"),
            make("wpx",      "CQ WPX (300 Prefixes)",     wpx.count,      300, "wpx",       "\(wpx.count) unique prefixes",                "Prefixes"),
            make("six_50",   "6m Magic Band (50 Grids)",  sixGrids.count, 50,  "vhf",       "\(sixGrids.count) 6m grids confirmed",        "6m Grids"),
        ]
    }

    private func derivePrefix(_ call: String) -> String {
        let c = call.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return "" }
        if let i = c.firstIndex(where: { $0.isNumber }) { return String(c[...i]) }
        return String(c.prefix(3))
    }
}

// MARK: - Award Card

struct AwardCard: View {
    let award: QRZAwardSummary
    let accentColor: Color
    @Environment(\.colorScheme) private var colorScheme

    private var progress:   Double { min(max(award.percentComplete, 0), 100) }
    private var isComplete: Bool   { award.earned || (award.progressAvailable && progress >= 100) }

    private var tintColor: Color {
        if isComplete { return .green }
        guard award.progressAvailable else { return .secondary }
        let h = 0.015 + 0.315 * pow(progress / 100, 1.65)
        return Color(hue: h, saturation: 0.84, brightness: colorScheme == .dark ? 0.94 : 0.76)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top colour stripe
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [tintColor.opacity(0.70), tintColor.opacity(0.35)],
                               startPoint: .leading, endPoint: .trailing)
                .frame(height: 5).cornerRadius(2)
                if isComplete {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.green)
                        .offset(x: -10, y: 5)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                // Top Header Row (unified fixed height 44)
                HStack(alignment: .center, spacing: 9) {
                    AwardContinentIcon(award: award, tint: tintColor)
                        .frame(width: 80, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(award.title)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .topLeading)

                        Text(award.status)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(tintColor)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(height: 44, alignment: .leading)

                // Metric Row (Progress & Achievement) (unified fixed height 34)
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Progress").font(.system(size: 9.5)).foregroundStyle(.secondary)
                        Text(award.progressText)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(tintColor)
                    }
                    .frame(width: 68, alignment: .leading)

                    Divider().frame(height: 24)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Achievement").font(.system(size: 9.5)).foregroundStyle(.secondary)
                        Text(award.achievement)
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.leading, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 34, alignment: .leading)

                // Progress Bar (unified fixed height 6)
                ZStack(alignment: .leading) {
                    Capsule().fill(tintColor.opacity(award.progressAvailable ? 0.14 : 0.08))
                    if award.progressAvailable {
                        GeometryReader { g in
                            Capsule()
                                .fill(LinearGradient(colors: [tintColor.opacity(0.80), tintColor],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(0, min(g.size.width, g.size.width * progress / 100)))
                        }
                    }
                }
                .frame(height: 6)

                // Footnote / Detail text (unified fixed height 28)
                Text(award.detail.isEmpty ? award.status : award.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(height: 28, alignment: .topLeading)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .background(ZStack {
            Color(NSColor.controlBackgroundColor).opacity(0.55)
            tintColor.opacity(isComplete ? 0.04 : 0.02)
        })
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(tintColor.opacity(isComplete ? 0.50 : 0.26),
                    lineWidth: isComplete ? 1.5 : 1.0))
        .shadow(color: isComplete ? Color.green.opacity(0.08) : Color.clear, radius: 4)
    }
}

// MARK: - Continent Icon

private struct AwardContinentIcon: View {
    let award: QRZAwardSummary
    let tint: Color

    private struct Sig { let symbol: String; let abbr: String; let title: String; let colors: [Color] }

    private var sig: Sig {
        let s = ([award.title, award.detail, award.awardType].joined(separator: " ")).uppercased()
        let t = Set(s.split(separator: " ").map(String.init))
        if s.contains("NORTH AMERICA") || t.contains("NA")  { return Sig(symbol: "globe.americas.fill",           abbr: "NA",  title: "N.America",  colors: [.blue,.teal]) }
        if s.contains("SOUTH AMERICA") || t.contains("SA")  { return Sig(symbol: "globe.americas.fill",           abbr: "SA",  title: "S.America",  colors: [.green,.yellow]) }
        if s.contains("EUROPE")        || t.contains("EU")  { return Sig(symbol: "globe.europe.africa.fill",      abbr: "EU",  title: "Europe",     colors: [.blue,.indigo]) }
        if s.contains("AFRICA")        || t.contains("AF")  { return Sig(symbol: "globe.europe.africa.fill",      abbr: "AF",  title: "Africa",     colors: [.orange,.green]) }
        if s.contains("ASIA")          || t.contains("AS")  { return Sig(symbol: "globe.central.south.asia.fill", abbr: "AS",  title: "Asia",       colors: [.red,.yellow]) }
        if s.contains("OCEANIA")       || t.contains("OC")  { return Sig(symbol: "globe.asia.australia.fill",     abbr: "OC",  title: "Oceania",    colors: [.cyan,.green]) }
        if s.contains("DXCC") || s.contains("DX WORLD")     { return Sig(symbol: "globe",                         abbr: "DX",  title: "DX World",   colors: [.purple,.blue]) }
        if s.contains("GRID") || s.contains("VUCC")         { return Sig(symbol: "square.grid.3x3.fill",          abbr: "GR",  title: "Grid",       colors: [.teal,.blue]) }
        if s.contains("UNITED STATES") || s.contains("WAS") { return Sig(symbol: "map.fill",                      abbr: "US",  title: "All States", colors: [.blue,.red]) }
        if s.contains("CONTINENT") || s.contains("WAC")     { return Sig(symbol: "globe",                         abbr: "WC",  title: "Continents", colors: [.green,.yellow]) }
        if s.contains("PREFIX") || s.contains("WPX")        { return Sig(symbol: "textformat.abc",                abbr: "WPX", title: "Prefix",     colors: [.pink,.purple]) }
        if s.contains("CW")                                  { return Sig(symbol: "dot.radiowaves.left.and.right", abbr: "CW",  title: "CW",         colors: [.brown,.orange]) }
        if s.contains("DIGITAL") || s.contains("FT8")       { return Sig(symbol: "waveform",                      abbr: "DIG", title: "Digital",    colors: [.cyan,.blue]) }
        if s.contains("PHONE") || s.contains("SSB")         { return Sig(symbol: "mic.fill",                      abbr: "SSB", title: "Phone",      colors: [.green,.teal]) }
        if s.contains("160M")                                { return Sig(symbol: "waveform.badge.magnifyingglass", abbr: "160", title: "160m",      colors: [.red,.orange]) }
        if s.contains("6M") || s.contains("MAGIC BAND")     { return Sig(symbol: "bolt.badge.clock.fill",          abbr: "6m",  title: "6m Magic",  colors: [.pink,.purple]) }
        if s.contains("2M")                                  { return Sig(symbol: "antenna.radiowaves.left.and.right", abbr: "2m", title: "2m",     colors: [.cyan,.teal]) }
        if s.contains("BAND")                                { return Sig(symbol: "waveform",                      abbr: "BND", title: "Band",       colors: [.orange,.yellow]) }
        if s.contains("AGM") || s.contains("EQSL")          { return Sig(symbol: "envelope.badge.shield.half.filled.fill", abbr: "AGM", title: "eQSL AGM", colors: [.green,.teal]) }
        return Sig(symbol: "trophy.fill", abbr: "AWD", title: "Award", colors: [tint, .yellow])
    }

    var body: some View {
        let item = sig
        HStack(spacing: 5) {
            ZStack {
                Circle().fill(.white.opacity(0.20)).frame(width: 28, height: 28)
                Image(systemName: item.symbol).font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(item.abbr)
                    .font(.system(size: item.abbr.count > 3 ? 11 : 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                Text(item.title)
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: item.colors.map { $0.opacity(0.88) },
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.18)))
    }
}
