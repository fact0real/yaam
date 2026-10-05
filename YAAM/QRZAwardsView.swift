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
            let baseList = !appState.qrzAwardSummaries.isEmpty
                ? appState.qrzAwardSummaries
                : buildLogbookAwards(from: allConfirmedRecords)
            return enrichAwards(baseList, records: allConfirmedRecords)
        case .eqsl:
            return buildEQSLAwards(from: eqslRecords)
        case .clublog:
            if let matrix = appState.clubLogDXCCMatrix {
                return matrix.toAwardSummaries()
            }
            if !clublogRecords.isEmpty {
                return ClubLogDXCCMatrix.matrixFromLogbook(records: clublogRecords).toAwardSummaries()
            }
            return ClubLogDXCCMatrix.empty().toAwardSummaries()
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
            if selectedSource == .eqsl && eqslRecords.isEmpty && !appState.isProcessingQSLQueue {
                let user = UserDefaults.standard.string(forKey: "eqslUsername") ?? ""
                if !user.isEmpty {
                    Task { await appState.downloadEQSLConfirmations() }
                }
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
            if newSrc == .eqsl && eqslRecords.isEmpty && !appState.isProcessingQSLQueue {
                let user = UserDefaults.standard.string(forKey: "eqslUsername") ?? ""
                if !user.isEmpty {
                    Task { await appState.downloadEQSLConfirmations() }
                }
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
            HStack(spacing: 8) {
                actionPill(
                    label: appState.isProcessingQSLQueue ? "Syncing…" : "Sync eQSL",
                    icon: "arrow.clockwise.icloud",
                    disabled: appState.isProcessingQSLQueue
                ) {
                    Task { await appState.downloadEQSLConfirmations() }
                }
                actionPill(label: "eQSL.cc", icon: "safari", disabled: false) {
                    if let url = URL(string: "https://www.eqsl.cc/qslcard/Awards.cfm") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

        case .combined:
            actionPill(label: "Sync All", icon: "arrow.triangle.2.circlepath", disabled: appState.isProcessingQSLQueue) {
                appState.downloadLoTWAndQRZConfirmations()
                Task { await appState.downloadEQSLConfirmations() }
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
                if appState.isFetchingClubLogAwards {
                    loadingStatCards
                } else {
                    let matrix = appState.clubLogDXCCMatrix
                        ?? (!clublogRecords.isEmpty ? ClubLogDXCCMatrix.matrixFromLogbook(records: clublogRecords) : ClubLogDXCCMatrix.empty())
                    statCard("Confirmed",  value: "\(matrix.totalConfirmed)",             icon: "checkmark.seal.fill",                    color: .green)
                    statCard("Worked",     value: "\(matrix.totalWorked)",                icon: "antenna.radiowaves.left.and.right",       color: selectedSource.accentColor)
                    statCard("CQ Zones",   value: "\(matrix.cqZonesConfirmed.count)/40",  icon: "map.circle.fill",                         color: .orange)
                    statCard("Continents", value: "\(matrix.continentsConfirmed.count)/6",icon: "globe",                                  color: .purple)
                    statCard("Challenge",  value: "\(matrix.dxccChallengePoints)",        icon: "flame.fill",                              color: .pink)
                }
            }
        }
    }

    private var loadingStatCards: some View {
        ForEach(0..<5, id: \.self) { _ in
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
        case .qrz:
            standardAwardsContent

        case .combined:
            VStack(alignment: .leading, spacing: 16) {
                lotwProgressPanel
                standardAwardsContent
            }

        case .eqsl:
            VStack(alignment: .leading, spacing: 16) {
                if eqslRecords.isEmpty {
                    eqslSyncBanner
                }
                agmTierView
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
                    let previewMatrix = !clublogRecords.isEmpty
                        ? ClubLogDXCCMatrix.matrixFromLogbook(records: clublogRecords)
                        : ClubLogDXCCMatrix.empty()
                    clubLogBandMatrix(previewMatrix)
                }
                standardAwardsContent
            }
        }
    }

    // MARK: eQSL Sync Banner

    private var eqslSyncBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope.badge.shield.half.filled.fill")
                .font(.system(size: 26))
                .foregroundStyle(selectedSource.accentColor)

            VStack(alignment: .leading, spacing: 3) {
                Text("Sync eQSL Confirmations")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)

                let user = UserDefaults.standard.string(forKey: "eqslUsername") ?? ""
                if !user.isEmpty {
                    Text("eQSL account (\(user)) is configured. Tap Sync Inbox to download your electronic QSL cards.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Configure your eQSL.cc credentials in Settings to download and match electronic confirmations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task { await appState.downloadEQSLConfirmations() }
            } label: {
                HStack(spacing: 6) {
                    if appState.isProcessingQSLQueue {
                        ProgressView().controlSize(.small)
                        Text("Syncing…")
                    } else {
                        Image(systemName: "arrow.clockwise.icloud.fill")
                        Text("Sync Inbox Now")
                    }
                }
                .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(selectedSource.accentColor)
            .disabled(appState.isProcessingQSLQueue)
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.60))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selectedSource.accentColor.opacity(0.30)))
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
        let states = Set(lotwRecs.filter { AwardEngine.countsAsUSState($0.fields) }.map { $0["STATE"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }).count
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
        let bands = ClubLogDXCCMatrix.allBands

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Label("DXCC Band Matrix", systemImage: "chart.bar.xaxis")
                    .font(.headline)

                Spacer()

                // Quick Summary Chips
                HStack(spacing: 6) {
                    summaryChip(icon: "crown.fill", text: "\(matrix.fiveBandDXCCCompletedBands)/5 5BDX", color: .orange)
                    summaryChip(icon: "sparkles", text: "\(matrix.nineBandDXCCCompletedBands)/9 9BDX", color: .purple)
                    summaryChip(icon: "flame.fill", text: "\(matrix.dxccChallengePoints) pts", color: .pink)
                    summaryChip(icon: "map.circle.fill", text: "\(matrix.cqZonesConfirmed.count)/40 WAZ", color: .red)
                }

                Spacer()

                Text("Updated \(matrix.fetchedAt, style: .relative) ago")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Text("Band").font(.caption.bold()).frame(width: 72, alignment: .leading).padding(.leading, 8)
                        Text("Class").font(.caption.bold()).frame(width: 58, alignment: .center)
                        Text("Worked").font(.caption.bold()).frame(width: 66, alignment: .center)
                        Text("Confirmed").font(.caption.bold()).frame(width: 78, alignment: .center)
                        Text("DXCC Progress").font(.caption.bold()).frame(width: 150, alignment: .center)
                    }
                    .padding(.vertical, 7)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.75))

                    Divider()

                    ForEach(Array(bands.enumerated()), id: \.element) { idx, band in
                        let worked    = matrix.workedCount(band: band)
                        let confirmed = matrix.confirmedCount(band: band)
                        let target    = targetForBand(band)
                        let pct       = min(1.0, Double(confirmed) / Double(target))
                        let bType     = bandType(band)

                        HStack(spacing: 0) {
                            Text(band.uppercased())
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .frame(width: 72, alignment: .leading).padding(.leading, 8)

                            Text(bType.label)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(bType.color.opacity(0.16))
                                .foregroundStyle(bType.color)
                                .cornerRadius(4)
                                .frame(width: 58, alignment: .center)

                            Text("\(worked)")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(worked > 0 ? .primary : .secondary)
                                .frame(width: 66, alignment: .center)

                            HStack(spacing: 4) {
                                Text("\(confirmed)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(confirmed >= target ? .green : (confirmed > 0 ? selectedSource.accentColor : .secondary))
                                if confirmed >= target {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 9)).foregroundStyle(.green)
                                }
                            }
                            .frame(width: 78, alignment: .center)

                            HStack(spacing: 6) {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.secondary.opacity(0.12))
                                        Capsule()
                                            .fill(confirmed >= target ? Color.green.opacity(0.8) : selectedSource.accentColor.opacity(0.75))
                                            .frame(width: geo.size.width * pct)
                                    }
                                }
                                .frame(height: 7)

                                Text("\(Int((pct * 100).rounded()))%")
                                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(confirmed >= target ? .green : .secondary)
                                    .frame(width: 32, alignment: .trailing)
                            }
                            .frame(width: 150)
                            .padding(.horizontal, 6)
                        }
                        .padding(.vertical, 5)
                        .background(idx.isMultiple(of: 2)
                                    ? Color(NSColor.controlBackgroundColor).opacity(0.22)
                                    : Color.clear)
                    }
                }
            }
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.16)))
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.50))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selectedSource.accentColor.opacity(0.24)))
    }

    private func targetForBand(_ band: String) -> Int {
        switch band.lowercased() {
        case "60m": return 50
        case "2m":  return 25
        case "70cm": return 10
        default:    return 100
        }
    }

    private func bandType(_ band: String) -> (label: String, color: Color) {
        let b = band.lowercased()
        if ["80m", "40m", "20m", "15m", "10m"].contains(b) {
            return ("5BDX", .orange)
        } else if ["30m", "17m", "12m"].contains(b) {
            return ("WARC", .teal)
        } else if ["6m", "2m", "70cm"].contains(b) {
            return ("VHF/UHF", .purple)
        } else {
            return ("HF", .blue)
        }
    }

    private func summaryChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
            Text(text).font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.12))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.25), lineWidth: 0.8))
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

        let total    = records.count
        let dxccSet  = Set(records.map { $0["DXCC"] }.filter { !$0.isEmpty && $0 != "0" && $0 != "UNKNOWN" })
        let stateSet = Set(records.filter { AwardEngine.countsAsUSState($0.fields) }.map { $0["STATE"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })
        let contSet  = Set(records.map { $0["CONT"].uppercased() }.filter { !$0.isEmpty })
        let gridSet  = Set(records.map {
            ($0["GRIDSQUARE"].isEmpty ? $0["GRID"] : $0["GRIDSQUARE"]).prefix(4).uppercased()
        }.filter { $0.count == 4 })

        // AGM (Authenticard Gold Medal)
        let agmTarget: Int
        let agmName: String
        let prevThreshold: Int
        if total >= 5000      { agmTarget = 5000; agmName = "Platinum"; prevThreshold = 1000 }
        else if total >= 1000 { agmTarget = 5000; agmName = "Gold";     prevThreshold = 1000 }
        else if total >= 500  { agmTarget = 1000; agmName = "Silver";   prevThreshold = 500  }
        else if total >= 100  { agmTarget = 500;  agmName = "Bronze";   prevThreshold = 100  }
        else                  { agmTarget = 100;  agmName = "Bronze";   prevThreshold = 0    }

        let agmPct: Double
        if total >= 100 {
            agmPct = min(100.0, Double(total - prevThreshold) / Double(max(1, agmTarget - prevThreshold)) * 100.0)
        } else {
            agmPct = min(100.0, Double(total) / 100.0 * 100.0)
        }

        list.append(QRZAwardSummary(
            id: "eqsl_agm",
            title: total >= 100 ? "AGM \(agmName)" : "AGM Bronze (Authenticard)",
            detail: total >= 100 ? "\(total) AG eQSL cards received" : "\(total) AG eQSL cards received (100 needed for Bronze)",
            percentComplete: agmPct,
            status: total >= 5000 ? "Platinum achieved!" : (total >= 100 ? "\(max(0, agmTarget - total)) to next level" : "\(max(0, 100 - total)) cards to Bronze"),
            earned: total >= 100,
            progressAvailable: true,
            achievement: "\(total) / \(total >= 100 ? agmTarget : 100) Confirmations",
            awardType: "eqsl",
            ribbonURL: ""
        ))

        list.append(make("eqsl_dxcc", "DX World via eQSL", dxccSet.count, 100, "dxcc", "\(dxccSet.count) entities confirmed via eQSL", "Entities"))
        list.append(make("eqsl_wac",  "All Continents via eQSL", contSet.count, 6, "continent", contSet.isEmpty ? "No continents confirmed via eQSL yet" : contSet.sorted().joined(separator: " · "), "Continents"))
        list.append(make("eqsl_was",  "All US States via eQSL",  stateSet.count, 50, "was", "\(stateSet.count) of 50 US states confirmed via eQSL", "States"))
        list.append(make("eqsl_grid", "Grid Award via eQSL (100)", gridSet.count, 100, "grid", "\(gridSet.count) Maidenhead grids confirmed via eQSL", "Grids"))

        let cwRecs  = records.filter { $0["MODE"].uppercased() == "CW" }
        let ssbRecs = records.filter { ["SSB","LSB","USB","FM","AM"].contains($0["MODE"].uppercased()) }
        let digRecs = records.filter { ["FT8","FT4","PSK31","PSK","JS8","WSPR","RTTY","DATA","DIGITAL"].contains($0["MODE"].uppercased()) }

        list.append(make("eqsl_cw",  "CW Award via eQSL",      cwRecs.count,  100, "cw",      "\(cwRecs.count) CW QSOs confirmed via eQSL",      "CW QSOs"))
        list.append(make("eqsl_ssb", "Phone Award via eQSL",   ssbRecs.count, 100, "phone",   "\(ssbRecs.count) Phone QSOs confirmed via eQSL",  "Phone QSOs"))
        list.append(make("eqsl_dig", "Digital Award via eQSL", digRecs.count, 100, "digital", "\(digRecs.count) Digital QSOs confirmed via eQSL","Digital QSOs"))

        for (band, label, target) in [("160m","160m",50),("80m","80m",100),("40m","40m",100),
                                       ("20m","20m",100),("15m","15m",100),("10m","10m",100),
                                       ("6m","6m Magic Band",50),("2m","2m",25)] as [(String,String,Int)] {
            let recs = records.filter { $0["BAND"].lowercased() == band }
            list.append(make("eqsl_band_\(band)", "\(label) Band Award via eQSL", recs.count, target, "band", "\(recs.count) QSOs on \(label) confirmed via eQSL", "QSOs on \(band)"))
        }

        for (id, title, code, target) in [("eu","Europe Award via eQSL","EU",25),("as","Asia Award via eQSL","AS",25),
                                           ("af","Africa Award via eQSL","AF",25),("na","North America Award via eQSL","NA",25),
                                           ("oc","Oceania Award via eQSL","OC",15),("sa","South America Award via eQSL","SA",10)] as [(String,String,String,Int)] {
            let ents = Set(records.filter { $0["CONT"].uppercased() == code }.map { $0["DXCC"] }.filter { !$0.isEmpty && $0 != "0" && $0 != "UNKNOWN" })
            list.append(make("eqsl_cont_\(id)", title, ents.count, target, "geographic", "\(ents.count) \(code) entities confirmed via eQSL", "Entities in \(code)"))
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
        let stateSet = Set(records.filter { AwardEngine.countsAsUSState($0.fields) }.map { $0["STATE"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })
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

    private func enrichAwards(_ awards: [QRZAwardSummary], records: [QSORecordModel]) -> [QRZAwardSummary] {
        guard !awards.isEmpty else { return awards }

        var qsosByContinent: [String: Int] = [:]
        var entitiesByContinent: [String: Set<String>] = [:]
        var allConfirmedDXCC = Set<String>()
        var allConfirmedStates = Set<String>()
        var allConfirmedGrids = Set<String>()
        var winterDays = Set<String>()

        for record in records {
            let cont = record["CONT"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let dxcc = record["DXCC"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

            if !cont.isEmpty {
                qsosByContinent[cont, default: 0] += 1
                if !dxcc.isEmpty, dxcc != "0", dxcc != "UNKNOWN" {
                    entitiesByContinent[cont, default: []].insert(dxcc)
                }
            }
            if !dxcc.isEmpty, dxcc != "0", dxcc != "UNKNOWN" {
                allConfirmedDXCC.insert(dxcc)
            }
            let st = record["STATE"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if AwardEngine.countsAsUSState(record.fields) {
                allConfirmedStates.insert(st)
            }
            let grid = (record["GRIDSQUARE"].isEmpty ? record["GRID"] : record["GRIDSQUARE"]).prefix(4).uppercased()
            if grid.count == 4 {
                allConfirmedGrids.insert(String(grid))
            }
            let cleanDate = record["QSO_DATE"].filter { $0.isNumber }
            if cleanDate.count >= 8 {
                let month = String(cleanDate.dropFirst(4).prefix(2))
                if month == "12" || month == "01" || month == "02" {
                    winterDays.insert(String(cleanDate.prefix(8)))
                }
            }
        }

        return awards.map { award in
            // 1. If already earned, keep completed status clean
            if award.earned {
                return QRZAwardSummary(
                    id: award.id,
                    title: award.title,
                    detail: award.detail.isEmpty ? "Issued by QRZ Logbook Awards" : award.detail,
                    percentComplete: 100.0,
                    status: award.status.isEmpty ? "Award received" : award.status,
                    earned: true,
                    progressAvailable: true,
                    achievement: (award.achievement.isEmpty || award.achievement == "Not reported") ? "Award received" : award.achievement,
                    awardType: award.awardType,
                    ribbonURL: award.ribbonURL
                )
            }

            // 2. Check if award already has a ratio like "X / Y Unit" in achievement
            var fixedPercent = award.percentComplete
            var parsedRatio: (curr: Int, target: Int)? = nil
            if let match = award.achievement.range(of: #"(\d+)\s*/\s*(\d+)"#, options: .regularExpression) {
                let parts = String(award.achievement[match]).components(separatedBy: "/")
                if parts.count == 2,
                   let curr = Int(parts[0].trimmingCharacters(in: .whitespaces)),
                   let target = Int(parts[1].trimmingCharacters(in: .whitespaces)),
                   target > 0 {
                    parsedRatio = (curr, target)
                    let mathPct = min(100.0, max(0.0, Double(curr) / Double(target) * 100.0))
                    if abs(fixedPercent - mathPct) > 0.5 {
                        fixedPercent = mathPct
                    }
                }
            }

            // 3. Does this award have valid progress from QRZ?
            let hasValidProgress = award.progressAvailable
                && award.achievement != "Not reported"
                && !award.detail.contains("QRZ did not return analysis")
                && (fixedPercent > 0 || (parsedRatio != nil && parsedRatio!.curr == 0))

            if hasValidProgress {
                return QRZAwardSummary(
                    id: award.id,
                    title: award.title,
                    detail: award.detail,
                    percentComplete: fixedPercent,
                    status: award.status.isEmpty ? (fixedPercent >= 100 ? "Eligible to apply" : "In progress") : award.status,
                    earned: fixedPercent >= 100,
                    progressAvailable: true,
                    achievement: award.achievement,
                    awardType: award.awardType,
                    ribbonURL: award.ribbonURL
                )
            }

            // 4. Enrich / fallback from local confirmed logbook records
            let norm = award.title.uppercased()

            // A) Worked All Continents (WAC) sub-awards or individual continents
            if norm.contains("WORKED ALL CONTINENTS") || norm.contains("WAC") || norm.contains("CONTINENT") {
                let continentMap: [(name: String, code: String, title: String)] = [
                    ("AFRICA",        "AF", "Africa"),
                    ("ASIA",          "AS", "Asia"),
                    ("EUROPE",        "EU", "Europe"),
                    ("NORTH AMERICA", "NA", "North America"),
                    ("SOUTH AMERICA", "SA", "South America"),
                    ("OCEANIA",       "OC", "Oceania")
                ]

                if let found = continentMap.first(where: { norm.contains($0.name) }) {
                    let count = qsosByContinent[found.code] ?? 0
                    let achieved = count >= 1
                    let pct: Double = achieved ? 100.0 : 0.0
                    return QRZAwardSummary(
                        id: award.id,
                        title: award.title,
                        detail: achieved ? "1 confirmed QSO in \(found.title)" : "No confirmed contacts in \(found.title) yet",
                        percentComplete: pct,
                        status: achieved ? "Eligible to apply" : "1 Continent remaining",
                        earned: achieved,
                        progressAvailable: true,
                        achievement: "\(achieved ? 1 : 0) / 1 Continents",
                        awardType: award.awardType.isEmpty ? "Mode: Mixed" : award.awardType,
                        ribbonURL: award.ribbonURL
                    )
                }

                // Global WAC (6 continents)
                let confirmedContinents = continentMap.filter { (qsosByContinent[$0.code] ?? 0) > 0 }.count
                let pct = min(100.0, Double(confirmedContinents) / 6.0 * 100.0)
                let achieved = confirmedContinents >= 6
                return QRZAwardSummary(
                    id: award.id,
                    title: award.title,
                    detail: "\(confirmedContinents) of 6 continents confirmed in logbook",
                    percentComplete: pct,
                    status: achieved ? "Eligible to apply" : "\(6 - confirmedContinents) Continents remaining",
                    earned: achieved,
                    progressAvailable: true,
                    achievement: "\(confirmedContinents) / 6 Continents",
                    awardType: award.awardType.isEmpty ? "Mode: Mixed" : award.awardType,
                    ribbonURL: award.ribbonURL
                )
            }

            // B) Master of Radio Communication
            if norm.contains("MASTER OF RADIO") || norm.contains("RADIO COMMUNICATION") {
                let mrcTargets: [(name: String, code: String, target: Int, title: String)] = [
                    ("AFRICA",        "AF", 76, "Africa"),
                    ("ASIA",          "AS", 40, "Asia"),
                    ("EUROPE",        "EU", 67, "Europe"),
                    ("NORTH AMERICA", "NA", 49, "North America"),
                    ("SOUTH AMERICA", "SA", 14, "South America"),
                    ("OCEANIA",       "OC", 30, "Oceania")
                ]

                if let found = mrcTargets.first(where: { norm.contains($0.name) }) {
                    let ents = entitiesByContinent[found.code]?.count ?? 0
                    let pct = min(100.0, Double(ents) / Double(found.target) * 100.0)
                    let achieved = ents >= found.target
                    return QRZAwardSummary(
                        id: award.id,
                        title: award.title,
                        detail: "\(ents) of \(found.target) \(found.title) DXCC entities confirmed",
                        percentComplete: pct,
                        status: achieved ? "Eligible to apply" : "\(max(0, found.target - ents)) Entities remaining",
                        earned: achieved,
                        progressAvailable: true,
                        achievement: "\(ents) / \(found.target) Entities",
                        awardType: award.awardType.isEmpty ? "Mode: Mixed" : award.awardType,
                        ribbonURL: award.ribbonURL
                    )
                }
            }

            // C) 12 Days of QRZ
            if norm.contains("12 DAYS") {
                let count = winterDays.count
                let pct = min(100.0, Double(count) / 12.0 * 100.0)
                let achieved = count >= 12
                return QRZAwardSummary(
                    id: award.id,
                    title: award.title,
                    detail: "\(count) winter days logged with confirmed QSOs (Dec–Feb)",
                    percentComplete: pct,
                    status: achieved ? "Eligible to apply" : "\(max(0, 12 - count)) days remaining",
                    earned: achieved,
                    progressAvailable: true,
                    achievement: "\(min(count, 12)) / 12 Winter Days",
                    awardType: award.awardType.isEmpty ? "Mode: Mixed" : award.awardType,
                    ribbonURL: award.ribbonURL
                )
            }

            // D) QRZ 30th Anniversary Award
            if norm.contains("30") && (norm.contains("YEAR") || norm.contains("ANNIVERSARY")) {
                let count = records.count
                let pct = min(100.0, Double(count) / 30.0 * 100.0)
                let achieved = count >= 30
                return QRZAwardSummary(
                    id: award.id,
                    title: award.title,
                    detail: "\(count) confirmed QSOs in logbook (30 needed)",
                    percentComplete: pct,
                    status: achieved ? "Eligible to apply" : "\(max(0, 30 - count)) QSOs remaining",
                    earned: achieved,
                    progressAvailable: true,
                    achievement: "\(min(count, 30)) / 30 Confirmed QSOs",
                    awardType: award.awardType.isEmpty ? "Mode: Mixed" : award.awardType,
                    ribbonURL: award.ribbonURL
                )
            }

            // E) DX World / DXCC
            if norm.contains("DX WORLD") || norm.contains("DXCC") {
                let count = allConfirmedDXCC.count
                let pct = min(100.0, Double(count) / 100.0 * 100.0)
                let achieved = count >= 100
                return QRZAwardSummary(
                    id: award.id,
                    title: award.title,
                    detail: "\(count) DXCC entities confirmed",
                    percentComplete: pct,
                    status: achieved ? "Eligible to apply" : "\(max(0, 100 - count)) Entities remaining",
                    earned: achieved,
                    progressAvailable: true,
                    achievement: "\(count) / 100 Entities",
                    awardType: award.awardType.isEmpty ? "Mode: Mixed" : award.awardType,
                    ribbonURL: award.ribbonURL
                )
            }

            // F) Worked All States / WAS
            if norm.contains("STATES") || norm.contains("WAS") {
                let count = allConfirmedStates.count
                let pct = min(100.0, Double(count) / 50.0 * 100.0)
                let achieved = count >= 50
                return QRZAwardSummary(
                    id: award.id,
                    title: award.title,
                    detail: "\(count) of 50 US states confirmed",
                    percentComplete: pct,
                    status: achieved ? "Eligible to apply" : "\(max(0, 50 - count)) States remaining",
                    earned: achieved,
                    progressAvailable: true,
                    achievement: "\(count) / 50 States",
                    awardType: award.awardType.isEmpty ? "Mode: Mixed" : award.awardType,
                    ribbonURL: award.ribbonURL
                )
            }

            // G) Grid Master / VUCC
            if norm.contains("GRID") || norm.contains("VUCC") {
                let count = allConfirmedGrids.count
                let pct = min(100.0, Double(count) / 100.0 * 100.0)
                let achieved = count >= 100
                return QRZAwardSummary(
                    id: award.id,
                    title: award.title,
                    detail: "\(count) Maidenhead grids confirmed",
                    percentComplete: pct,
                    status: achieved ? "Eligible to apply" : "\(max(0, 100 - count)) Grids remaining",
                    earned: achieved,
                    progressAvailable: true,
                    achievement: "\(count) / 100 Grids",
                    awardType: award.awardType.isEmpty ? "Mode: Mixed" : award.awardType,
                    ribbonURL: award.ribbonURL
                )
            }

            // H) Default graceful fallback - never show "--" or "Not reported"
            return QRZAwardSummary(
                id: award.id,
                title: award.title,
                detail: award.detail.isEmpty || award.detail.contains("QRZ did not return") ? "Tracked in QRZ Logbook" : award.detail,
                percentComplete: fixedPercent,
                status: "In progress",
                earned: false,
                progressAvailable: true,
                achievement: "\(Int(fixedPercent.rounded()))% complete",
                awardType: award.awardType,
                ribbonURL: award.ribbonURL
            )
        }
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
            LinearGradient(colors: [tintColor.opacity(0.70), tintColor.opacity(0.35)],
                           startPoint: .leading, endPoint: .trailing)
            .frame(height: 4)
            .cornerRadius(2)

            VStack(alignment: .leading, spacing: 8) {
                // Top Header Row (unified fixed height 44)
                HStack(alignment: .center, spacing: 8) {
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

                    if isComplete {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(4)
                            .background(Circle().fill(Color.green.opacity(0.12)))
                            .help("Award achieved")
                    }
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
        let s = ([award.title, award.detail, award.awardType, award.id].joined(separator: " ")).uppercased()
        let t = Set(s.split(separator: " ").map(String.init))

        // Specialized Club Log & League Awards
        if s.contains("5BDX") || s.contains("5-BAND") || award.awardType == "5bdx" {
            return Sig(symbol: "crown.fill", abbr: "5BDX", title: "5B DXCC", colors: [.yellow, .orange])
        }
        if s.contains("9BDX") || s.contains("9-BAND") || award.awardType == "9bdx" {
            return Sig(symbol: "sparkles", abbr: "9BDX", title: "9B DXCC", colors: [.indigo, .purple])
        }
        if s.contains("CHALLENGE") || award.awardType == "challenge" {
            return Sig(symbol: "flame.fill", abbr: "CHL", title: "Challenge", colors: [.purple, .pink])
        }
        if s.contains("WAZ") || s.contains("ZONE") || award.awardType == "zone" {
            return Sig(symbol: "map.circle.fill", abbr: "WAZ", title: "CQ Zones", colors: [.orange, .red])
        }
        if s.contains("LF CHAL") || s.contains("LF_") {
            return Sig(symbol: "antenna.radiowaves.left.and.right", abbr: "CDXC", title: "LF Chal", colors: [.brown, .orange])
        }
        if s.contains("HF CHAL") || s.contains("HF_") {
            return Sig(symbol: "bolt.horizontal.fill", abbr: "HF", title: "HF Chal", colors: [.red, .orange])
        }
        if s.contains("WARC") {
            return Sig(symbol: "waveform.path.ecg", abbr: "WARC", title: "WARC Band", colors: [.teal, .blue])
        }

        // Continents
        if s.contains("NORTH AMERICA") || t.contains("NA")  { return Sig(symbol: "globe.americas.fill",           abbr: "NA",  title: "N.America",  colors: [.blue,.teal]) }
        if s.contains("SOUTH AMERICA") || t.contains("SA")  { return Sig(symbol: "globe.americas.fill",           abbr: "SA",  title: "S.America",  colors: [.green,.yellow]) }
        if s.contains("EUROPE")        || t.contains("EU")  { return Sig(symbol: "globe.europe.africa.fill",      abbr: "EU",  title: "Europe",     colors: [.blue,.indigo]) }
        if s.contains("AFRICA")        || t.contains("AF")  { return Sig(symbol: "globe.europe.africa.fill",      abbr: "AF",  title: "Africa",     colors: [.orange,.green]) }
        if s.contains("ASIA")          || t.contains("AS")  { return Sig(symbol: "globe.central.south.asia.fill", abbr: "AS",  title: "Asia",       colors: [.red,.yellow]) }
        if s.contains("OCEANIA")       || t.contains("OC")  { return Sig(symbol: "globe.asia.australia.fill",     abbr: "OC",  title: "Oceania",    colors: [.cyan,.green]) }

        // Specific Bands
        if s.contains("160M") || s.contains("TOPBAND")      { return Sig(symbol: "waveform.badge.magnifyingglass", abbr: "160", title: "160m Top",  colors: [.red,.orange]) }
        if s.contains("80M")                                 { return Sig(symbol: "waveform",                      abbr: "80m", title: "80m Band",  colors: [.orange,.yellow]) }
        if s.contains("60M")                                 { return Sig(symbol: "waveform",                      abbr: "60m", title: "60m Band",  colors: [.orange,.pink]) }
        if s.contains("40M")                                 { return Sig(symbol: "waveform",                      abbr: "40m", title: "40m Band",  colors: [.blue,.cyan]) }
        if s.contains("30M")                                 { return Sig(symbol: "waveform.path.ecg",              abbr: "30m", title: "30m WARC",  colors: [.teal,.cyan]) }
        if s.contains("20M")                                 { return Sig(symbol: "waveform",                      abbr: "20m", title: "20m Band",  colors: [.blue,.indigo]) }
        if s.contains("17M")                                 { return Sig(symbol: "waveform.path.ecg",              abbr: "17m", title: "17m WARC",  colors: [.mint,.teal]) }
        if s.contains("15M")                                 { return Sig(symbol: "waveform",                      abbr: "15m", title: "15m Band",  colors: [.purple,.blue]) }
        if s.contains("12M")                                 { return Sig(symbol: "waveform.path.ecg",              abbr: "12m", title: "12m WARC",  colors: [.pink,.purple]) }
        if s.contains("10M")                                 { return Sig(symbol: "waveform",                      abbr: "10m", title: "10m Band",  colors: [.pink,.orange]) }
        if s.contains("6M") || s.contains("MAGIC BAND")     { return Sig(symbol: "bolt.badge.clock.fill",          abbr: "6m",  title: "6m Magic",  colors: [.pink,.purple]) }
        if s.contains("2M")                                  { return Sig(symbol: "antenna.radiowaves.left.and.right", abbr: "2m", title: "2m VHF",   colors: [.cyan,.teal]) }
        if s.contains("70CM")                                { return Sig(symbol: "circle.grid.cross",             abbr: "70cm", title: "70cm UHF", colors: [.indigo,.teal]) }

        // General awards
        if s.contains("DXCC") || s.contains("DX WORLD")     { return Sig(symbol: "globe",                         abbr: "DX",  title: "DX World",   colors: [.purple,.blue]) }
        if s.contains("GRID") || s.contains("VUCC")         { return Sig(symbol: "square.grid.3x3.fill",          abbr: "GR",  title: "Grid",       colors: [.teal,.blue]) }
        if s.contains("UNITED STATES") || s.contains("WAS") { return Sig(symbol: "map.fill",                      abbr: "US",  title: "All States", colors: [.blue,.red]) }
        if s.contains("CONTINENT") || s.contains("WAC")     { return Sig(symbol: "globe",                         abbr: "WC",  title: "Continents", colors: [.green,.yellow]) }
        if s.contains("PREFIX") || s.contains("WPX")        { return Sig(symbol: "textformat.abc",                abbr: "WPX", title: "Prefix",     colors: [.pink,.purple]) }
        if s.contains("CW")                                  { return Sig(symbol: "dot.radiowaves.left.and.right", abbr: "CW",  title: "CW",         colors: [.brown,.orange]) }
        if s.contains("DIGITAL") || s.contains("FT8")       { return Sig(symbol: "waveform",                      abbr: "DIG", title: "Digital",    colors: [.cyan,.blue]) }
        if s.contains("PHONE") || s.contains("SSB")         { return Sig(symbol: "mic.fill",                      abbr: "SSB", title: "Phone",      colors: [.green,.teal]) }
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
