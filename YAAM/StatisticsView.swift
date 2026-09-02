//
//  StatisticsView.swift
//  ADIF to Excel
//
//  Created by factoreal on 7/31/26.
//

import SwiftUI
import AppKit

// MARK: - Interactive Log Statistics Window
struct StatisticsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismissWindow) private var dismissWindow
    
    @State private var selectedTab = 0
    @State private var selectedUnconfirmedBand = "All Bands"
    @State private var countryBandSearchText = ""
    @State private var selectedCoverageCountry: String?
    @State private var snapshot = StatisticsSnapshot.empty
    @State private var snapshotGeneration = 0
    @State private var isRefreshingSnapshot = false
    @State private var followUpScope: StatisticsFollowUpScope = .creditOpportunities
    @State private var emailLookupRecordID: UUID?
    @State private var selectedCountryBandDetails: StatisticsCountryBandDetailSelection?
    @ObservedObject private var competitorStore = CompetitorTrackingStore.shared

    private var currentSnapshot: StatisticsSnapshot {
        snapshot
    }

    private var unconfirmedBandOptions: [String] {
        ["All Bands"] + currentSnapshot.unconfirmedBandCountryStatistics.map(\.band)
    }

    private var visibleUnconfirmedBandCountryStatistics: [UnconfirmedBandCountryStatModel] {
        guard selectedUnconfirmedBand != "All Bands" else {
            return currentSnapshot.unconfirmedBandCountryStatistics
        }

        return currentSnapshot.unconfirmedBandCountryStatistics.filter { $0.band == selectedUnconfirmedBand }
    }

    private var progressSummary: ConfirmedProgressSummary {
        currentSnapshot.progressSummary
    }

    private var visibleCountryBandCoverage: [CountryBandCoverage] {
        let query = countryBandSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return currentSnapshot.countryBandCoverage }
        return currentSnapshot.countryBandCoverage.filter {
            $0.country.localizedCaseInsensitiveContains(query)
        }
    }

    private var selectedCountryBandCoverage: CountryBandCoverage? {
        let selectedCountry = selectedCoverageCountry ?? visibleCountryBandCoverage.first?.country
        return currentSnapshot.countryBandCoverage.first { $0.country == selectedCountry }
    }

    private var visibleFollowUpCandidates: [StatisticsFollowUpCandidate] {
        currentSnapshot.followUpCandidates.filter { candidate in
            switch followUpScope {
            case .creditOpportunities:
                return candidate.opportunity.addsCountryBandCredit || candidate.opportunity.addsGridCredit
            case .countryBand:
                return candidate.opportunity.addsCountryBandCredit
            case .grid:
                return candidate.opportunity.addsGridCredit
            case .allUnconfirmed:
                return true
            }
        }
    }

    var body: some View {
        let stats = currentSnapshot

        VStack(spacing: 14) {
            // Header Bar
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.doc.horizontal.fill")
                    .font(.title)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Log Statistics & Confirmation Breakdown")
                        .font(.title2)
                        .bold()
                    Text(appState.loadedFileName.isEmpty ? "No active log loaded" : appState.loadedFileName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button {
                    refreshSnapshot()
                } label: {
                    if isRefreshingSnapshot {
                        Label {
                            Text("Refreshing")
                        } icon: {
                            ProgressView().controlSize(.small)
                        }
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshingSnapshot)
                .help("Recalculate statistics from the active log")

                Button {
                    appState.syncConfirmations(completion: { _ in
                        refreshSnapshot()
                    })
                } label: {
                    Label(appState.isSyncingAPI ? "Syncing" : "Sync QSLs", systemImage: "icloud.and.arrow.down")
                }
                .disabled(appState.isSyncingAPI || appState.qsoRecords.isEmpty)
                .help("Download new LoTW and QRZ confirmations")

                Button {
                    appState.selectedTab = 0
                    appState.showConfirmationReconciliationSheet = true
                    dismissWindow(id: YAAMWindowID.statistics)
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Reconcile", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Compare local, LoTW, and QRZ confirmation totals")
            }
            .padding(.top, 4)
            
            Divider()
            
            // Analytics Summary Badges Cards
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 135, maximum: 220), spacing: 10)],
                spacing: 10
            ) {
                StatBadgeCard(title: "Total QSOs", value: "\(stats.totalQSOCount)", icon: "antenna.radiowaves.left.and.right", color: .blue)
                StatBadgeCard(title: "Confirmed", value: "\(stats.confirmedCount)", icon: "checkmark.seal.fill", color: .green)
                StatBadgeCard(title: "Unconfirmed", value: "\(stats.unconfirmedCount)", icon: "clock.fill", color: .orange)
                StatBadgeCard(title: "Confirmation Rate", value: String(format: "%.1f%%", stats.confirmationPercentage), icon: "percent", color: .teal)
                StatBadgeCard(title: "DXCC Countries", value: "\(stats.dxccCountryCount)", icon: "globe.americas.fill", color: .purple)
                StatBadgeCard(title: "Confirmed DXCC", value: "\(stats.confirmedDxccCountryCount)", icon: "checkmark.circle.fill", color: .mint)
                StatBadgeCard(title: "Worked 4-char Grids", value: "\(stats.workedGridCount)", icon: "square.grid.3x3.fill", color: .cyan)
                StatBadgeCard(title: "Confirmed Grids", value: "\(stats.confirmedGridCount)", icon: "checkmark.square.fill", color: .green)
                StatBadgeCard(
                    title: "Grid Confirmation",
                    value: String(format: "%.1f%%", stats.gridConfirmationPercentage),
                    icon: "percent",
                    color: .orange
                )
                StatBadgeCard(title: "Unique Callsigns", value: "\(stats.uniqueCallsignCount)", icon: "person.2.fill", color: .indigo)
                StatBadgeCard(title: "Active Modes", value: "\(stats.uniqueModeCount)", icon: "waveform", color: .pink)
            }
            
            Picker("", selection: $selectedTab) {
                Text("Action Center").tag(0)
                Text("Band Breakdown").tag(1)
                Text("Country Breakdown").tag(2)
                Text("Unconfirmed DXCC").tag(3)
                Text("Country Bands").tag(4)
                Text("Progress").tag(5)
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 2)
            
            // Tab 0: actionable confirmation workbench
            if selectedTab == 0 {
                actionCenterView
            } else if selectedTab == 1 {
                // Tab 1: Band Breakdown Table
                VStack(alignment: .leading, spacing: 6) {
                    ScrollView {
                        VStack(spacing: 0) {
                            HStack {
                                Text("BAND")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 54, alignment: .leading)
                                Text("QSOs")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 52, alignment: .trailing)
                                Text("CONF")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 52, alignment: .trailing)
                                Text("UNCONF")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 56, alignment: .trailing)
                                Text("DXCC")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 44, alignment: .trailing)
                                Text("CONF DXCC")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 68, alignment: .trailing)
                                Text("SHARE %")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 58, alignment: .trailing)
                                Text("DISTRIBUTION")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 10)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .background(Color.accentColor)
                            .border(Color.black.opacity(0.3), width: 0.5)
                            
                            ForEach(stats.bandStatistics) { stat in
                                HStack {
                                    Text(stat.band)
                                        .font(.system(.caption, design: .monospaced))
                                        .bold()
                                        .foregroundColor(.accentColor)
                                        .frame(width: 54, alignment: .leading)
                                    Text("\(stat.qsoCount)")
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(width: 52, alignment: .trailing)
                                    Text("\(stat.confirmedCount)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.green)
                                        .bold()
                                        .frame(width: 52, alignment: .trailing)
                                    Text("\(stat.unconfirmedCount)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.orange)
                                        .frame(width: 56, alignment: .trailing)
                                    Text("\(stat.dxccCount)")
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(width: 44, alignment: .trailing)
                                    Text("\(stat.confirmedDxccCount)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.green)
                                        .bold()
                                        .frame(width: 68, alignment: .trailing)
                                    Text(String(format: "%.1f%%", stat.percentage))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 58, alignment: .trailing)
                                    
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.15)).frame(height: 8)
                                            RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)).frame(width: max(4, geo.size.width * CGFloat(stat.percentage / 100.0)), height: 8)
                                        }
                                    }
                                    .frame(height: 8)
                                    .padding(.leading, 10)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                                .border(Color.gray.opacity(0.15), width: 0.5)
                            }
                        }
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                }
            } else if selectedTab == 2 {
                // Tab 2: Country Breakdown Table
                VStack(alignment: .leading, spacing: 6) {
                    ScrollView {
                        VStack(spacing: 0) {
                            HStack {
                                Text("COUNTRY")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("TOTAL QSOs")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 90, alignment: .trailing)
                                Text("CONFIRMED")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 90, alignment: .trailing)
                                Text("UNCONFIRMED")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 100, alignment: .trailing)
                                Text("UNCONF %")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 90, alignment: .trailing)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.accentColor)
                            .border(Color.black.opacity(0.3), width: 0.5)
                            
                            ForEach(stats.countryStatistics) { cStat in
                                HStack {
                                    HStack(spacing: 6) {
                                        Text(cStat.flag)
                                        Text(cStat.country)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(cStat.confirmedCount == 0 ? Color(red: 0.85, green: 0.2, blue: 0.2) : .primary)
                                            .bold()
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    Text("\(cStat.qsoCount)")
                                        .font(.system(.caption, design: .monospaced))
                                        .frame(width: 90, alignment: .trailing)
                                    
                                    Text("\(cStat.confirmedCount)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.green)
                                        .bold()
                                        .frame(width: 90, alignment: .trailing)
                                    
                                    Text("\(cStat.unconfirmedCount)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.orange)
                                        .frame(width: 100, alignment: .trailing)
                                    
                                    Text(String(format: "%.1f%%", cStat.unconfirmedPercentage))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.orange)
                                        .frame(width: 90, alignment: .trailing)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    cStat.confirmedCount == 0
                                    ? Color(red: 0.45, green: 0.08, blue: 0.08).opacity(0.18)
                                    : Color(NSColor.controlBackgroundColor).opacity(0.4)
                                )
                                .border(Color.gray.opacity(0.15), width: 0.5)
                            }
                        }
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                }
            } else if selectedTab == 3 {
                // Tab 3: Worked countries that are not confirmed on each band
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Band:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("", selection: $selectedUnconfirmedBand) {
                            ForEach(unconfirmedBandOptions, id: \.self) { band in
                                Text(band).tag(band)
                            }
                        }
                        .frame(width: 170)

                        Spacer()
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if visibleUnconfirmedBandCountryStatistics.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.largeTitle)
                                        .foregroundColor(.green)
                                    Text("All worked countries are confirmed on their bands.")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 220)
                            } else {
                                ForEach(visibleUnconfirmedBandCountryStatistics) { bandStat in
                                    let totalQSOs = bandStat.countries.reduce(0) { $0 + $1.qsoCount }
                                    let totalCallsigns = Set(bandStat.countries.flatMap { $0.callsigns }).count
                                    VStack(alignment: .leading, spacing: 8) {
                                        // ── Band Header Row ─────────────────────────────────
                                        HStack(spacing: 10) {
                                            Text(bandStat.band)
                                                .font(.system(.headline, design: .monospaced))
                                                .foregroundColor(.accentColor)
                                            Spacer()
                                            // Total unconfirmed QSOs
                                            HStack(spacing: 4) {
                                                Image(systemName: "dot.radiowaves.left.and.right")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundColor(.orange)
                                                Text("\(totalQSOs) QSOs")
                                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                    .foregroundColor(.orange)
                                            }
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Color.orange.opacity(0.12), in: Capsule())
                                            // Total unique callsigns
                                            HStack(spacing: 4) {
                                                Image(systemName: "person.2.wave.2.fill")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundColor(.purple)
                                                Text("\(totalCallsigns) calls")
                                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                    .foregroundColor(.purple)
                                            }
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(Color.purple.opacity(0.12), in: Capsule())
                                            // Country count
                                            Text("\(bandStat.countries.count) DXCC")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        // ── Country Cards Grid ───────────────────────────────
                                        // adaptive(min,max with same value) ensures all cards are equal width
                                        // and each card uses maxWidth:.infinity to eliminate trailing gaps
                                        LazyVGrid(
                                            columns: [GridItem(.adaptive(minimum: 148), spacing: 8)],
                                            alignment: .leading,
                                            spacing: 8
                                        ) {
                                            ForEach(bandStat.countries) { countryStat in
                                                UnconfirmedCountryButton(
                                                    band: bandStat.band,
                                                    countryStat: countryStat
                                                ) {
                                                    showUnconfirmedQSOs(
                                                        band: bandStat.band,
                                                        country: countryStat.country
                                                    )
                                                }
                                            }
                                        }
                                    }
                                    .padding(10)
                                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                                    .cornerRadius(6)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                                }
                            }
                        }
                        .padding(8)
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                }
            } else if selectedTab == 4 {
                countryBandCoverageView
            } else {
                confirmedProgressView
            }
            
            Spacer()
            Divider()
            
            HStack {
                Spacer()
                Button("Close") { dismissWindow(id: YAAMWindowID.statistics) }
                    .keyboardShortcut(.defaultAction)
                    .frame(width: 90)
            }
        }
        .padding(16)
        .frame(
            minWidth: 900,
            idealWidth: 1180,
            maxWidth: .infinity,
            minHeight: 620,
            idealHeight: 780,
            maxHeight: .infinity
        )
        .sheet(item: $selectedCountryBandDetails) { selection in
            StatisticsCountryBandDetailSheet(
                selection: selection,
                opportunityByRecordID: Dictionary(
                    uniqueKeysWithValues: currentSnapshot.followUpCandidates.map { ($0.record.id, $0.opportunity) }
                ),
                emailLookupRecordID: emailLookupRecordID,
                onShowInLog: showRecordInLog,
                onEmail: { record in
                    prepareEmail(for: record, qslDelivery: selection.state == .confirmed)
                },
                onFindEmail: { record in
                    lookupEmail(for: record, qslDelivery: selection.state == .confirmed)
                },
                onPreviewQSL: previewQSL,
                onOpenQRZ: openQRZ
            )
        }
        .onAppear {
            appState.refreshOwnerQRZRankIfNeeded()
            refreshSnapshot()
        }
    }

    private var actionCenterView: some View {
        let stats = currentSnapshot
        let countryBandOpportunityCount = stats.followUpCandidates.filter(\.opportunity.addsCountryBandCredit).count
        let gridOpportunityCount = stats.followUpCandidates.filter(\.opportunity.addsGridCredit).count

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Confirmation Sources")
                                .font(.headline)
                            Text("Provider counts can overlap when the same QSO is confirmed by more than one service.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180, maximum: 280), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(stats.providerStatistics) { provider in
                            StatisticsProviderCard(stat: provider)
                        }
                    }
                }

                HStack(spacing: 8) {
                    StatisticsPriorityChip(
                        title: "New country-band",
                        value: countryBandOpportunityCount,
                        icon: "flag.checkered",
                        color: .orange
                    )
                    StatisticsPriorityChip(
                        title: "New 4-char grid",
                        value: gridOpportunityCount,
                        icon: "square.grid.3x3.fill",
                        color: .cyan
                    )
                    StatisticsPriorityChip(
                        title: "Needs confirmation",
                        value: stats.followUpCandidates.count,
                        icon: "envelope.badge",
                        color: .blue
                    )
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Confirmation Follow-up")
                                .font(.headline)
                            Text("Prioritized contacts where a confirmation can add useful award credit.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $followUpScope) {
                            ForEach(StatisticsFollowUpScope.allCases) { scope in
                                Text(scope.title).tag(scope)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 560)
                    }

                    if visibleFollowUpCandidates.isEmpty {
                        ContentUnavailableView(
                            "No Follow-up Needed",
                            systemImage: "checkmark.seal.fill",
                            description: Text("No unconfirmed QSO matches the selected priority.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 150)
                    } else {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(visibleFollowUpCandidates.prefix(80))) { candidate in
                                StatisticsQSOActionRow(
                                    record: candidate.record,
                                    opportunity: candidate.opportunity,
                                    kind: .confirmationFollowUp,
                                    isLookingUpEmail: emailLookupRecordID == candidate.record.id,
                                    onShowInLog: { showRecordInLog(candidate.record) },
                                    onEmail: { prepareEmail(for: candidate.record, qslDelivery: false) },
                                    onFindEmail: { lookupEmail(for: candidate.record, qslDelivery: false) },
                                    onPreviewQSL: {},
                                    onOpenQRZ: { openQRZ(for: candidate.record) }
                                )
                            }
                        }

                        if visibleFollowUpCandidates.count > 80 {
                            Text("Showing the 80 highest-value contacts of \(visibleFollowUpCandidates.count). Use Show in Log to continue with the active filters.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recently Confirmed")
                            .font(.headline)
                        Text("Open the QSO, send its QSL card by email, or preview the card before delivery.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if stats.recentConfirmedRecords.isEmpty {
                        Text("No confirmed contacts are available in the active log.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else {
                        LazyVStack(spacing: 6) {
                            ForEach(stats.recentConfirmedRecords) { record in
                                StatisticsQSOActionRow(
                                    record: record,
                                    opportunity: nil,
                                    kind: .confirmedQSL,
                                    isLookingUpEmail: emailLookupRecordID == record.id,
                                    onShowInLog: { showRecordInLog(record) },
                                    onEmail: { prepareEmail(for: record, qslDelivery: true) },
                                    onFindEmail: { lookupEmail(for: record, qslDelivery: true) },
                                    onPreviewQSL: { previewQSL(for: record) },
                                    onOpenQRZ: { openQRZ(for: record) }
                                )
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
    }

    private func refreshSnapshot() {
        let records = appState.qsoRecords
        let ownerRankData = appState.ownerRankData
        let emailHistory = appState.emailHistory
        snapshotGeneration += 1
        let generation = snapshotGeneration
        isRefreshingSnapshot = true

        Task {
            let refreshed = await Task.detached(priority: .userInitiated) {
                StatisticsSnapshot.make(
                    records: records,
                    ownerRankData: ownerRankData,
                    emailHistory: emailHistory
                )
            }.value
            guard generation == snapshotGeneration else { return }
            snapshot = refreshed
            isRefreshingSnapshot = false

            let selectedStillExists = selectedCoverageCountry.map { selected in
                refreshed.countryBandCoverage.contains { $0.country == selected }
            } ?? false
            if !selectedStillExists {
                selectedCoverageCountry = refreshed.countryBandCoverage.first?.country
            }
        }
    }

    private func showRecordInLog(_ record: QSORecordModel) {
        let callsign = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines)
        var criteria = FilterCriteria()
        criteria.useCallsign = !callsign.isEmpty
        criteria.callsign = callsign
        appState.filterCriteria = criteria
        appState.searchText = ""
        appState.selectedRecordIDs = [record.id]
        appState.selectedTab = 0
        appState.appendLog("Showing \(callsign.isEmpty ? "selected QSO" : callsign) in the Log Table from Statistics.")
        selectedCountryBandDetails = nil
        dismissWindow(id: YAAMWindowID.statistics)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func prepareEmail(for record: QSORecordModel, qslDelivery: Bool) {
        let email = record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else {
            lookupEmail(for: record, qslDelivery: qslDelivery)
            return
        }

        appState.selectedTab = 0
        if qslDelivery {
            appState.openQSLCardEmailComposer(for: record)
        } else {
            appState.selectedEmailCallsign = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            appState.selectedEmailAddress = email
            appState.selectedEmailQSO = record
            appState.selectedEmailTemplate = "LoTW/QRZ Confirmation"
            appState.selectedEmailUnconfirmedQSOs = [record]
            appState.selectedEmailIncomingRequest = nil
            appState.showEmailComposer = true
        }
        selectedCountryBandDetails = nil
        dismissWindow(id: YAAMWindowID.statistics)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func lookupEmail(for record: QSORecordModel, qslDelivery: Bool) {
        let callsign = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !callsign.isEmpty, emailLookupRecordID == nil else { return }

        Task { @MainActor in
            emailLookupRecordID = record.id
            defer { emailLookupRecordID = nil }
            guard let email = await appState.fetchAndStoreQRZEmail(for: callsign), !email.isEmpty else { return }
            var enrichedRecord = record
            enrichedRecord.fields["EMAIL"] = email
            refreshSnapshot()
            prepareEmail(for: enrichedRecord, qslDelivery: qslDelivery)
        }
    }

    private func previewQSL(for record: QSORecordModel) {
        appState.selectedTab = 0
        appState.selectedQSLCardQSO = record
        appState.showQSLCardComposer = true
        selectedCountryBandDetails = nil
        dismissWindow(id: YAAMWindowID.statistics)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openQRZ(for record: QSORecordModel) {
        let callsign = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let rawURL = record["QRZ_URL"].trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = rawURL.isEmpty ? "https://www.qrz.com/db/\(callsign)" : rawURL
        guard !callsign.isEmpty, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private var countryBandCoverageView: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Find country", text: $countryBandSearchText)
                        .textFieldStyle(.plain)
                    if !countryBandSearchText.isEmpty {
                        Button {
                            countryBandSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(visibleCountryBandCoverage) { coverage in
                            Button {
                                selectedCoverageCountry = coverage.country
                            } label: {
                                HStack(spacing: 7) {
                                    Text(countryToFlag(coverage.country))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(coverage.country)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                        Text("\(coverage.confirmedBandCount) confirmed · \(coverage.workedUnconfirmedBandCount) pending")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    if selectedCountryBandCoverage?.country == coverage.country {
                                        Image(systemName: "chevron.right")
                                            .font(.caption.bold())
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .frame(height: 43)
                                .background(
                                    selectedCountryBandCoverage?.country == coverage.country
                                        ? Color.accentColor.opacity(0.12)
                                        : Color.clear
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(8)
            .frame(width: 238)
            .background(Color(NSColor.textBackgroundColor))

            Divider()

            if let coverage = selectedCountryBandCoverage {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Text(countryToFlag(coverage.country))
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(coverage.country)
                                .font(.headline)
                            Text("Band confirmation coverage")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        CountryBandSummaryChip(
                            title: "Confirmed",
                            value: coverage.confirmedBandCount,
                            icon: "checkmark.circle.fill",
                            color: .green
                        )
                        CountryBandSummaryChip(
                            title: "Pending",
                            value: coverage.workedUnconfirmedBandCount,
                            icon: "clock.fill",
                            color: .orange
                        )
                        CountryBandSummaryChip(
                            title: "Needed",
                            value: coverage.neededBandCount,
                            icon: "scope",
                            color: .secondary
                        )
                    }

                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 118, maximum: 150), spacing: 8)],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(coverage.bands) { band in
                                CountryBandCoverageTile(item: band) {
                                    showCountryBandQSOs(country: coverage.country, band: band)
                                }
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "globe.desk.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No confirmed country matches this search.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
    }

    private var confirmedProgressView: some View {
        let summary = progressSummary
        let ownerCall = appState.currentStationCallsign.isEmpty ? "EP2AES" : appState.currentStationCallsign
        let ownerConfirmedCount = appState.qsoRecords.filter(\.isConfirmed).count

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Top Metric Cards
                HStack(spacing: 10) {
                    ProgressMetricCard(title: "Today", value: "\(summary.todayCount)", icon: "calendar.day.timeline.left", color: .blue)
                    ProgressMetricCard(title: "This Week", value: "\(summary.weekCount)", icon: "calendar", color: .green)
                    ProgressMetricCard(title: "This Month", value: "\(summary.monthCount)", icon: "calendar.badge.clock", color: .orange)
                    ProgressMetricCard(title: "This Year", value: "\(summary.yearCount)", icon: "calendar.circle", color: .purple)
                }

                // Main Multi-Station Confirmed Progress Chart Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Confirmed QSO Progress & Competitor Comparison")
                                .font(.headline)
                            Text("Cumulative confirmed QSOs and growth trajectory vs competitors, with forecast projection.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("Your Rate: \(String(format: "%.1f", summary.monthlyRate)) / mo")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundColor(.green)
                    }

                    if summary.chartPoints.count < 2 {
                        VStack(spacing: 8) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("Not enough confirmed QSO history to draw a trend.")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        MultiStationConfirmedProgressChart(
                            ownerCallsign: ownerCall,
                            ownerPoints: summary.chartPoints,
                            ownerCurrentConfirmed: ownerConfirmedCount,
                            ownerMonthlyRate: summary.monthlyRate,
                            competitorStore: competitorStore
                        )
                        .frame(height: 270)
                    }
                }
                .padding(12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))

                // Competitor Velocity & Overtake Projections Table
                CompetitorVelocityComparisonTable(
                    ownerCallsign: ownerCall,
                    ownerConfirmedCount: ownerConfirmedCount,
                    ownerMonthlyRate: summary.monthlyRate,
                    competitorStore: competitorStore
                )

                // Forecast Cards
                VStack(alignment: .leading, spacing: 2) {
                    Text("Confirmed QSO Forecast")
                        .font(.headline)
                    Text("Projected totals and QRZ rank estimates use confirmed QSO history and the current enriched QRZ rankings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 10) {
                    ForEach(summary.forecasts) { forecast in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("+\(forecast.months) Months")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(forecast.projectedTotal)")
                                .font(.system(.title3, design: .monospaced))
                                .bold()
                            Text("+\(forecast.projectedGain) confirmed")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.10))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.green.opacity(0.25), lineWidth: 1))
                    }
                }
                .frame(height: 92)

                QRZRankProjectionTable(forecasts: summary.forecasts)
            }
            .padding(.bottom, 20)
        }
    }

    private func showCountryBandQSOs(country: String, band: CountryBandCoverageItem) {
        guard band.state != .needed else { return }
        let normalizedCountry = canonicalCountryName(country)
        let normalizedBand = band.band.lowercased()
        let records = appState.qsoRecords
            .filter { record in
                canonicalCountryName(record["COUNTRY"]) == normalizedCountry
                    && ConfirmationOpportunityIndex.normalizedBand(for: record).lowercased() == normalizedBand
                    && (band.state == .confirmed ? record.isConfirmed : !record.isConfirmed)
            }
            .sorted { StatisticsSnapshot.chronologicalKey(for: $0) > StatisticsSnapshot.chronologicalKey(for: $1) }

        selectedCountryBandDetails = StatisticsCountryBandDetailSelection(
            country: country,
            band: band.band,
            state: band.state,
            records: records
        )
    }

    private func showUnconfirmedQSOs(band: String, country: String) {
        var criteria = FilterCriteria()
        criteria.useBand = true
        criteria.band = band
        criteria.useCountry = true
        criteria.selectedCountries = [country]
        criteria.useConfirmation = true
        criteria.confirmationState = "Unconfirmed (N/Blank)"

        appState.filterCriteria = criteria
        appState.searchText = ""
        appState.clearSelection()
        appState.selectedTab = 0
        appState.appendLog("Showing unconfirmed QSOs for \(country) on \(band).")
        dismissWindow(id: YAAMWindowID.statistics)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum StatisticsFollowUpScope: String, CaseIterable, Identifiable {
    case creditOpportunities
    case countryBand
    case grid
    case allUnconfirmed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .creditOpportunities: return "Best Opportunities"
        case .countryBand: return "Country-Band"
        case .grid: return "New Grid"
        case .allUnconfirmed: return "All Unconfirmed"
        }
    }
}

nonisolated enum StatisticsConfirmationProvider: String, CaseIterable, Identifiable, Sendable {
    case lotw
    case qrz
    case eqsl
    case direct

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lotw: return "LoTW"
        case .qrz: return "QRZ Logbook"
        case .eqsl: return "eQSL"
        case .direct: return "Paper / Direct"
        }
    }

    var icon: String {
        switch self {
        case .lotw: return "checkmark.icloud.fill"
        case .qrz: return "globe.badge.chevron.backward"
        case .eqsl: return "envelope.badge.fill"
        case .direct: return "mail.stack.fill"
        }
    }

    var color: Color {
        switch self {
        case .lotw: return .blue
        case .qrz: return .green
        case .eqsl: return .purple
        case .direct: return .orange
        }
    }
}

nonisolated enum StatisticsConfirmationSourceClassifier {
    static func isPaperOrDirectConfirmed(_ record: QSORecordModel) -> Bool {
        guard isAffirmative(record["QSL_RCVD"]) else { return false }

        let receivedVia = normalized(record["QSL_RCVD_VIA"])
        if ["B", "D", "BUREAU", "BURO", "DIRECT"].contains(receivedVia) {
            return true
        }

        let explicitSources = [
            record["APP_YAAM_QSL_SOURCE"],
            record["APP_YAAM_CONFIRMATION_SOURCE"],
            record["APP_QSL_SOURCE"]
        ].map(normalized)
        let paperLabels = ["PAPER", "DIRECT", "CARD", "BUREAU", "BURO"]
        return explicitSources.contains { source in
            paperLabels.contains { source.contains($0) }
        }
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "_", with: " ")
    }

    private static func isAffirmative(_ rawValue: String) -> Bool {
        ["Y", "V", "C", "CONFIRMED", "VERIFIED"].contains(normalized(rawValue))
    }
}

nonisolated struct StatisticsConfirmationProviderStat: Identifiable, Sendable {
    var id: String { provider.id }
    let provider: StatisticsConfirmationProvider
    let count: Int
    let percentage: Double
}

nonisolated struct StatisticsFollowUpCandidate: Identifiable, Sendable {
    var id: UUID { record.id }
    let record: QSORecordModel
    let opportunity: QSOConfirmationOpportunity
    let priorityScore: Int
}

private enum StatisticsQSOActionKind {
    case confirmationFollowUp
    case confirmedQSL
}

private struct StatisticsCountryBandDetailSelection: Identifiable {
    var id: String { "\(country)|\(band)|\(state.rawValue)" }
    let country: String
    let band: String
    let state: CountryBandCoverageState
    let records: [QSORecordModel]
}

private struct StatisticsCountryBandDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let selection: StatisticsCountryBandDetailSelection
    let opportunityByRecordID: [UUID: QSOConfirmationOpportunity]
    let emailLookupRecordID: UUID?
    let onShowInLog: (QSORecordModel) -> Void
    let onEmail: (QSORecordModel) -> Void
    let onFindEmail: (QSORecordModel) -> Void
    let onPreviewQSL: (QSORecordModel) -> Void
    let onOpenQRZ: (QSORecordModel) -> Void

    private var isConfirmed: Bool {
        selection.state == .confirmed
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: isConfirmed ? "checkmark.seal.fill" : "clock.badge.exclamationmark.fill")
                    .font(.title2)
                    .foregroundStyle(isConfirmed ? Color.green : Color.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selection.country) · \(selection.band.uppercased())")
                        .font(.headline)
                    Text(
                        isConfirmed
                            ? "Confirmed contacts on this country-band"
                            : "Pending contacts that can complete this country-band"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(selection.records.count) QSO\(selection.records.count == 1 ? "" : "s")")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isConfirmed ? Color.green : Color.orange)
            }

            Divider()

            if selection.records.isEmpty {
                ContentUnavailableView(
                    "No Matching QSO",
                    systemImage: "waveform.path.ecg.rectangle",
                    description: Text("Refresh Statistics after the latest import or confirmation sync.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(selection.records) { record in
                            StatisticsQSOActionRow(
                                record: record,
                                opportunity: opportunityByRecordID[record.id],
                                kind: isConfirmed ? .confirmedQSL : .confirmationFollowUp,
                                isLookingUpEmail: emailLookupRecordID == record.id,
                                onShowInLog: { onShowInLog(record) },
                                onEmail: { onEmail(record) },
                                onFindEmail: { onFindEmail(record) },
                                onPreviewQSL: { onPreviewQSL(record) },
                                onOpenQRZ: { onOpenQRZ(record) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider()

            HStack {
                if !isConfirmed {
                    Label(
                        "Open a QSO in Log Table or compose a confirmation request from its email action.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(minWidth: 720, idealWidth: 840, minHeight: 380, idealHeight: 520)
    }
}

private struct StatisticsProviderCard: View {
    let stat: StatisticsConfirmationProviderStat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: stat.provider.icon)
                    .foregroundStyle(stat.provider.color)
                Text(stat.provider.title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(String(format: "%.1f%%", stat.percentage))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(stat.count.formatted())
                .font(.title3.monospacedDigit().bold())

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.14))
                    Capsule()
                        .fill(stat.provider.color)
                        .frame(width: max(3, geometry.size.width * min(1, stat.percentage / 100)))
                }
            }
            .frame(height: 6)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .background(stat.provider.color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(stat.provider.color.opacity(0.24)))
    }
}

private struct StatisticsPriorityChip: View {
    let title: String
    let value: Int
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value.formatted())
                .font(.caption.monospacedDigit().bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.22)))
    }
}

private struct StatisticsQSOActionRow: View {
    let record: QSORecordModel
    let opportunity: QSOConfirmationOpportunity?
    let kind: StatisticsQSOActionKind
    let isLookingUpEmail: Bool
    let onShowInLog: () -> Void
    let onEmail: () -> Void
    let onFindEmail: () -> Void
    let onPreviewQSL: () -> Void
    let onOpenQRZ: () -> Void

    private var callsign: String {
        record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var email: String {
        record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var country: String {
        let value = record["COUNTRY"].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Unknown country" : value
    }

    private var detail: String {
        let date = record["QSO_DATE"].trimmingCharacters(in: .whitespacesAndNewlines)
        let time = String(record["TIME_ON"].filter(\.isNumber).prefix(4))
        let band = ConfirmationOpportunityIndex.normalizedBand(for: record).uppercased()
        let mode = record["SUBMODE"].isEmpty ? record["MODE"] : record["SUBMODE"]
        return [date, time.isEmpty ? "" : "\(time) UTC", band, mode.uppercased()]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(countryToFlag(country))
                    Text(callsign.isEmpty ? "Unknown callsign" : callsign)
                        .font(.system(.body, design: .monospaced).weight(.bold))
                    Text(country)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 5) {
                if opportunity?.addsCountryBandCredit == true {
                    StatisticsCreditBadge(title: "New country-band", icon: "flag.checkered", color: .orange)
                }
                if opportunity?.addsGridCredit == true {
                    StatisticsCreditBadge(title: "New grid", icon: "square.grid.3x3.fill", color: .cyan)
                }
                if kind == .confirmedQSL {
                    StatisticsCreditBadge(title: "Confirmed", icon: "checkmark.seal.fill", color: .green)
                }
            }

            HStack(spacing: 5) {
                Button(action: onShowInLog) {
                    Image(systemName: "tablecells")
                        .frame(width: 22)
                }
                .help("Show this callsign in the Log Table")

                if email.isEmpty {
                    Button(action: onFindEmail) {
                        if isLookingUpEmail {
                            ProgressView().controlSize(.small).frame(width: 22)
                        } else {
                            Image(systemName: "magnifyingglass").frame(width: 22)
                        }
                    }
                    .disabled(isLookingUpEmail)
                    .help("Find the operator email using QRZ and HAMQTH, then prepare the message")
                } else {
                    Button(action: onEmail) {
                        Image(systemName: kind == .confirmedQSL ? "envelope.badge.fill" : "envelope.fill")
                            .frame(width: 22)
                    }
                    .help(kind == .confirmedQSL ? "Compose an email with this QSL card" : "Compose a confirmation request")
                }

                if kind == .confirmedQSL {
                    Button(action: onPreviewQSL) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .frame(width: 22)
                    }
                    .help("Preview or export the QSL card")
                }

                Button(action: onOpenQRZ) {
                    Image(systemName: "safari")
                        .frame(width: 22)
                }
                .help("Open the callsign on QRZ.com")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 58)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.14)))
    }
}

private struct StatisticsCreditBadge: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

struct CountryBandSummaryChip: View {
    let title: String
    let value: Int
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(value.formatted())
                .font(.caption.monospacedDigit().bold())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

struct CountryBandCoverageTile: View {
    let item: CountryBandCoverageItem
    let action: () -> Void

    private var color: Color {
        switch item.state {
        case .confirmed: return .green
        case .worked: return .orange
        case .needed: return .secondary
        }
    }

    private var icon: String {
        switch item.state {
        case .confirmed: return "checkmark.circle.fill"
        case .worked: return "clock.fill"
        case .needed: return "scope"
        }
    }

    private var status: String {
        switch item.state {
        case .confirmed: return "Confirmed"
        case .worked: return "Pending"
        case .needed: return "Needed"
        }
    }

    private var detail: String {
        switch item.state {
        case .confirmed:
            return "\(item.confirmedCount) of \(item.qsoCount) QSO(s) confirmed"
        case .worked:
            return "\(item.qsoCount) QSO(s), none confirmed"
        case .needed:
            return "No QSO"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(item.band.uppercased())
                        .font(.system(.headline, design: .monospaced))
                    Spacer(minLength: 4)
                    Image(systemName: icon)
                        .foregroundStyle(color)
                }
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text(detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
            .background(color.opacity(item.state == .needed ? 0.04 : 0.10))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.24), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(item.state == .needed)
        .help(item.state == .needed ? "No QSO is recorded on this band." : "Show \(status.lowercased()) QSOs on \(item.band).")
    }
}

struct UnconfirmedCountryButton: View {
    let band: String
    let countryStat: UnconfirmedCountryStatModel
    let action: () -> Void

    // Age-based Chroma: Bright green (fresh) -> Amber -> Brown (oldest)
    private var ageColor: Color {
        guard let daysAgo = countryStat.daysAgo else {
            return Color(red: 0.85, green: 0.45, blue: 0.15)
        }
        switch daysAgo {
        case 0...7:   return Color(red: 0.10, green: 0.76, blue: 0.42)  // Emerald Green
        case 8...30:  return Color(red: 0.45, green: 0.78, blue: 0.20)  // Lime Green
        case 31...90: return Color(red: 0.95, green: 0.65, blue: 0.12)  // Golden Amber
        case 91...240:return Color(red: 0.85, green: 0.42, blue: 0.12)  // Terracotta
        default:      return Color(red: 0.58, green: 0.28, blue: 0.14)  // Mahogany Brown
        }
    }

    private var dateBadgeText: String {
        guard !countryStat.latestQSODateString.isEmpty else { return "—" }
        if let d = countryStat.daysAgo {
            if d == 0  { return "Today" }
            if d == 1  { return "1d ago" }
            if d < 30  { return "\(d)d ago" }
            if d < 90  { return "\(max(1, d/7))w ago" }
            if d < 365 { return "\(max(1, d/30))mo ago" }
            return "\(max(1, d/365))yr ago"
        }
        return countryStat.latestQSODateString
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {

                // ── Row 1: Flag + Country Name ─────────────────────────
                HStack(spacing: 5) {
                    Text(countryToFlag(countryStat.country))
                        .font(.system(size: 14))
                    Text(countryStat.country)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }

                // ── Row 2: Date · Email · Stats ────────────────────────
                HStack(spacing: 4) {
                    // Age / Date badge
                    HStack(spacing: 2) {
                        Image(systemName: "calendar")
                            .font(.system(size: 7, weight: .medium))
                        Text(dateBadgeText)
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .lineLimit(1)
                    }
                    .foregroundColor(ageColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(ageColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))

                    Spacer(minLength: 2)

                    // Email badge
                    if countryStat.emailsSentCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 7.5))
                            Text("\(countryStat.emailsSentCount)")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(Color(red: 0.35, green: 0.65, blue: 1.0))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.35, green: 0.65, blue: 1.0).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                    }

                    // QSO count (radio waves icon = contacts on the air)
                    HStack(spacing: 2) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 7, weight: .semibold))
                        Text("\(countryStat.qsoCount)")
                            .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                    }
                    .foregroundColor(ageColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(ageColor.opacity(0.20), in: RoundedRectangle(cornerRadius: 4))

                    // Callsign count (person icon = unique operators)
                    if !countryStat.callsigns.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 7, weight: .semibold))
                            Text("\(countryStat.callsigns.count)")
                                .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                        }
                        .foregroundColor(.purple)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: 66)
        .background(ageColor.opacity(0.08))
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(ageColor.opacity(0.30), lineWidth: 1)
        )
        .buttonStyle(.plain)
        .help(tooltipText)
    }

    private var tooltipText: String {
        var lines = ["Show unconfirmed \(countryStat.country) QSOs on \(band)"]
        if !countryStat.latestQSODateString.isEmpty {
            let desc = countryStat.daysAgo.map { " (\($0) days ago)" } ?? ""
            lines.append("📅 Latest: \(countryStat.latestQSODateString)\(desc)")
        }
        if !countryStat.callsigns.isEmpty {
            let preview = countryStat.callsigns.prefix(5).joined(separator: ", ")
            let more = countryStat.callsigns.count > 5 ? " +\(countryStat.callsigns.count - 5) more" : ""
            lines.append("📡 \(preview)\(more)")
        }
        if countryStat.emailsSentCount > 0 {
            lines.append("✉️ \(countryStat.emailsSentCount) email(s) sent")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Stat Badge Card Component
struct StatBadgeCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            Text(value)
                .font(.system(.title2, design: .monospaced))
                .bold()
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
}

nonisolated struct ConfirmedProgressSummary: Sendable {
    let todayCount: Int
    let weekCount: Int
    let monthCount: Int
    let yearCount: Int
    let monthlyRate: Double
    let chartPoints: [ConfirmedProgressPoint]
    let forecasts: [ConfirmedForecast]
}

nonisolated struct ConfirmedProgressPoint: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let cumulativeCount: Int
    let isForecast: Bool
}

nonisolated struct ConfirmedForecast: Identifiable, Sendable {
    let id = UUID()
    let months: Int
    let projectedGain: Int
    let projectedTotal: Int
    let currentQsoRank: Int?
    let currentBandRank: Int?
    let currentDxccRank: Int?
    let projectedQsoScore: Int?
    let projectedBandScore: Int?
    let projectedDxccScore: Int?
    let projectedQsoRank: Int?
    let projectedBandRank: Int?
    let projectedDxccRank: Int?
}

nonisolated struct StatisticsSnapshot: Sendable {
    let totalQSOCount: Int
    let confirmedCount: Int
    let unconfirmedCount: Int
    let confirmationPercentage: Double
    let dxccCountryCount: Int
    let confirmedDxccCountryCount: Int
    let workedGridCount: Int
    let confirmedGridCount: Int
    let gridConfirmationPercentage: Double
    let uniqueCallsignCount: Int
    let uniqueModeCount: Int
    let providerStatistics: [StatisticsConfirmationProviderStat]
    let followUpCandidates: [StatisticsFollowUpCandidate]
    let recentConfirmedRecords: [QSORecordModel]
    let bandStatistics: [BandStatModel]
    let countryStatistics: [CountryStatModel]
    let unconfirmedBandCountryStatistics: [UnconfirmedBandCountryStatModel]
    let countryBandCoverage: [CountryBandCoverage]
    let progressSummary: ConfirmedProgressSummary

    static let empty = StatisticsSnapshot(
        totalQSOCount: 0,
        confirmedCount: 0,
        unconfirmedCount: 0,
        confirmationPercentage: 0,
        dxccCountryCount: 0,
        confirmedDxccCountryCount: 0,
        workedGridCount: 0,
        confirmedGridCount: 0,
        gridConfirmationPercentage: 0,
        uniqueCallsignCount: 0,
        uniqueModeCount: 0,
        providerStatistics: [],
        followUpCandidates: [],
        recentConfirmedRecords: [],
        bandStatistics: [],
        countryStatistics: [],
        unconfirmedBandCountryStatistics: [],
        countryBandCoverage: [],
        progressSummary: ConfirmedProgressSummary(
            todayCount: 0,
            weekCount: 0,
            monthCount: 0,
            yearCount: 0,
            monthlyRate: 0,
            chartPoints: [],
            forecasts: []
        )
    )

    static func make(
        records: [QSORecordModel],
        ownerRankData: QRZRankResponse?,
        emailHistory: [EmailHistoryEntry] = []
    ) -> StatisticsSnapshot {
        let availableCountries = Set(
            records.compactMap { record -> String? in
                let country = canonicalCountryName(record["COUNTRY"])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return country.isEmpty ? nil : country
            }
        )
        let confirmedDxccCountries = Set(
            records.compactMap { record -> String? in
                let country = canonicalCountryName(record["COUNTRY"])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return record.isConfirmed && !country.isEmpty ? country : nil
            }
        )

        let workedGrids = Set(records.compactMap { fourCharacterGrid(for: $0) })
        let confirmedGrids = Set(
            records.compactMap { record -> String? in
                guard record.isConfirmed else { return nil }
                return fourCharacterGrid(for: record)
            }
        )
        let gridConfirmationPercentage = workedGrids.isEmpty
            ? 0
            : Double(confirmedGrids.count) / Double(workedGrids.count) * 100
        let totalCount = records.count
        let confirmedCount = records.reduce(into: 0) { count, record in
            if record.isConfirmed { count += 1 }
        }
        let confirmationPercentage = totalCount == 0
            ? 0
            : Double(confirmedCount) / Double(totalCount) * 100
        let providerStatistics = makeProviderStatistics(records: records)
        let opportunityIndex = ConfirmationOpportunityIndex(records: records)
        let followUpCandidates = records.compactMap { record -> StatisticsFollowUpCandidate? in
            guard !record.isConfirmed,
                  let opportunity = opportunityIndex.opportunity(for: record.id) else { return nil }

            var score = 0
            if opportunity.addsCountryBandCredit { score += 100 }
            if opportunity.addsGridCredit { score += 80 }
            if !record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 20 }
            if !record["QRZ_URL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 5 }
            return StatisticsFollowUpCandidate(record: record, opportunity: opportunity, priorityScore: score)
        }
        .sorted { lhs, rhs in
            if lhs.priorityScore != rhs.priorityScore { return lhs.priorityScore > rhs.priorityScore }
            return chronologicalKey(for: lhs.record) > chronologicalKey(for: rhs.record)
        }
        let recentConfirmedRecords = records
            .filter(\.isConfirmed)
            .sorted { chronologicalKey(for: $0) > chronologicalKey(for: $1) }
            .prefix(20)

        return StatisticsSnapshot(
            totalQSOCount: totalCount,
            confirmedCount: confirmedCount,
            unconfirmedCount: totalCount - confirmedCount,
            confirmationPercentage: confirmationPercentage,
            dxccCountryCount: availableCountries.count,
            confirmedDxccCountryCount: confirmedDxccCountries.count,
            workedGridCount: workedGrids.count,
            confirmedGridCount: confirmedGrids.count,
            gridConfirmationPercentage: gridConfirmationPercentage,
            uniqueCallsignCount: Set(records.compactMap {
                let callsign = $0["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                return callsign.isEmpty ? nil : callsign
            }).count,
            uniqueModeCount: Set(records.compactMap {
                let mode = $0["MODE"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                return mode.isEmpty ? nil : mode
            }).count,
            providerStatistics: providerStatistics,
            followUpCandidates: followUpCandidates,
            recentConfirmedRecords: Array(recentConfirmedRecords),
            bandStatistics: makeBandStatistics(records: records),
            countryStatistics: makeCountryStatistics(records: records),
            unconfirmedBandCountryStatistics: makeUnconfirmedBandCountryStatistics(records: records, emailHistory: emailHistory),
            countryBandCoverage: opportunityIndex.countryBandCoverage,
            progressSummary: ConfirmedProgressAnalyzer.makeSummary(records: records, ownerRankData: ownerRankData)
        )
    }

    private static func makeBandStatistics(records: [QSORecordModel]) -> [BandStatModel] {
        guard !records.isEmpty else { return [] }
        var values: [String: (total: Int, confirmed: Int, countries: Set<String>, confirmedCountries: Set<String>)] = [:]

        for record in records {
            let normalizedBand = ConfirmationOpportunityIndex.normalizedBand(for: record)
            let band = normalizedBand.isEmpty ? "UNKNOWN" : normalizedBand.uppercased()
            let country = canonicalCountryName(record["COUNTRY"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var value = values[band] ?? (
                total: 0,
                confirmed: 0,
                countries: Set<String>(),
                confirmedCountries: Set<String>()
            )
            value.total += 1
            if record.isConfirmed { value.confirmed += 1 }
            if !country.isEmpty { value.countries.insert(country) }
            if record.isConfirmed, !country.isEmpty { value.confirmedCountries.insert(country) }
            values[band] = value
        }

        let total = Double(records.count)
        return values.map { band, value in
            BandStatModel(
                band: band,
                qsoCount: value.total,
                confirmedCount: value.confirmed,
                unconfirmedCount: value.total - value.confirmed,
                dxccCount: value.countries.count,
                confirmedDxccCount: value.confirmedCountries.count,
                percentage: Double(value.total) / total * 100
            )
        }
        .sorted { lhs, rhs in
            if lhs.qsoCount != rhs.qsoCount { return lhs.qsoCount > rhs.qsoCount }
            return lhs.band.localizedStandardCompare(rhs.band) == .orderedAscending
        }
    }

    private static func makeCountryStatistics(records: [QSORecordModel]) -> [CountryStatModel] {
        var values: [String: (total: Int, confirmed: Int)] = [:]
        for record in records {
            let canonical = canonicalCountryName(record["COUNTRY"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let country = canonical.isEmpty ? "Unknown" : canonical
            var value = values[country] ?? (0, 0)
            value.total += 1
            if record.isConfirmed { value.confirmed += 1 }
            values[country] = value
        }

        return values.map { country, value in
            CountryStatModel(
                country: country,
                flag: countryToFlag(country),
                qsoCount: value.total,
                confirmedCount: value.confirmed,
                unconfirmedCount: value.total - value.confirmed
            )
        }
        .sorted { lhs, rhs in
            if lhs.qsoCount != rhs.qsoCount { return lhs.qsoCount > rhs.qsoCount }
            return lhs.country.localizedStandardCompare(rhs.country) == .orderedAscending
        }
    }

    private static func makeUnconfirmedBandCountryStatistics(
        records: [QSORecordModel],
        emailHistory: [EmailHistoryEntry] = []
    ) -> [UnconfirmedBandCountryStatModel] {
        var values: [String: [String: (total: Int, confirmed: Int, dates: [Date], dateStrings: [String], callsigns: Set<String>)]] = [:]

        // Fast lookup map for sent email requests by callsign
        var emailCountsByCall: [String: (count: Int, lastDate: Date)] = [:]
        for entry in emailHistory {
            let call = entry.callsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !call.isEmpty else { continue }
            let existing = emailCountsByCall[call]?.count ?? 0
            let lastDate = emailCountsByCall[call]?.lastDate ?? entry.date
            emailCountsByCall[call] = (existing + 1, max(lastDate, entry.date))
        }

        for record in records {
            let normalizedBand = ConfirmationOpportunityIndex.normalizedBand(for: record)
            let band = normalizedBand.isEmpty ? "UNKNOWN" : normalizedBand.uppercased()
            let canonical = canonicalCountryName(record["COUNTRY"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let country = canonical.isEmpty ? "Unknown" : canonical
            var countryValues = values[band] ?? [:]
            var value = countryValues[country] ?? (total: 0, confirmed: 0, dates: [], dateStrings: [], callsigns: Set<String>())
            value.total += 1
            if record.isConfirmed { value.confirmed += 1 }

            let call = record["CALL"].uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !call.isEmpty { value.callsigns.insert(call) }

            let dateRaw = record["QSO_DATE"].filter(\.isNumber)
            if !dateRaw.isEmpty {
                value.dateStrings.append(dateRaw)
                if let parsedDate = parseADIFDate(dateRaw) {
                    value.dates.append(parsedDate)
                }
            }

            countryValues[country] = value
            values[band] = countryValues
        }

        let now = Date()
        let calendar = Calendar(identifier: .gregorian)

        return values.compactMap { band, countryValues in
            let countries = countryValues.compactMap { country, value -> UnconfirmedCountryStatModel? in
                guard value.total > 0, value.confirmed == 0 else { return nil }

                // Find latest QSO date
                let sortedDates = value.dates.sorted(by: >)
                let latestDate = sortedDates.first

                let latestDateString: String
                if let latest = latestDate {
                    let year = calendar.component(.year, from: latest)
                    let month = calendar.component(.month, from: latest)
                    let day = calendar.component(.day, from: latest)
                    latestDateString = String(format: "%04d-%02d-%02d", year, month, day)
                } else if let rawString = value.dateStrings.sorted(by: >).first, rawString.count == 8 {
                    latestDateString = "\(rawString.prefix(4))-\(rawString.dropFirst(4).prefix(2))-\(rawString.suffix(2))"
                } else {
                    latestDateString = value.dateStrings.sorted(by: >).first ?? ""
                }

                let daysAgo: Int?
                if let latest = latestDate {
                    let diff = calendar.dateComponents([.day], from: calendar.startOfDay(for: latest), to: calendar.startOfDay(for: now)).day
                    daysAgo = max(0, diff ?? 0)
                } else {
                    daysAgo = nil
                }

                // Check emails sent to any callsign for this unconfirmed country/band
                var sentEmails = 0
                var latestEmailDate: Date? = nil
                for call in value.callsigns {
                    if let stat = emailCountsByCall[call] {
                        sentEmails += stat.count
                        if let currentLatest = latestEmailDate {
                            latestEmailDate = max(currentLatest, stat.lastDate)
                        } else {
                            latestEmailDate = stat.lastDate
                        }
                    }
                }

                return UnconfirmedCountryStatModel(
                    country: country,
                    qsoCount: value.total,
                    latestQSODate: latestDate,
                    latestQSODateString: latestDateString,
                    daysAgo: daysAgo,
                    callsigns: Array(value.callsigns).sorted(),
                    emailsSentCount: sentEmails,
                    lastEmailDate: latestEmailDate
                )
            }
            .sorted { lhs, rhs in
                if lhs.qsoCount != rhs.qsoCount { return lhs.qsoCount > rhs.qsoCount }
                return lhs.country.localizedStandardCompare(rhs.country) == .orderedAscending
            }
            return countries.isEmpty ? nil : UnconfirmedBandCountryStatModel(band: band, countries: countries)
        }
        .sorted { $0.band.localizedStandardCompare($1.band) == .orderedAscending }
    }

    private static func fourCharacterGrid(for record: QSORecordModel) -> String? {
        ConfirmationOpportunityIndex.fourCharacterGrid(for: record)
    }

    private static func makeProviderStatistics(records: [QSORecordModel]) -> [StatisticsConfirmationProviderStat] {
        let total = records.count
        return StatisticsConfirmationProvider.allCases.map { provider in
            let fields: [String]
            switch provider {
            case .lotw:
                fields = ["LOTW_QSL_RCVD", "APP_LOTW_QSL_RCVD"]
            case .qrz:
                fields = ["QRZLOG_QSL_RCVD", "QRZCOM_QSL_RCVD", "APP_QRZLOG_STATUS"]
            case .eqsl:
                fields = ["EQSL_QSL_RCVD", "APP_EQSL_QSL_RCVD"]
            case .direct:
                fields = []
            }

            let count = records.filter { record in
                switch provider {
                case .direct:
                    return StatisticsConfirmationSourceClassifier.isPaperOrDirectConfirmed(record)
                default:
                    return fields.contains { field in
                        isAffirmative(record[field])
                    }
                }
            }.count
            let percentage = total == 0 ? 0 : Double(count) / Double(total) * 100
            return StatisticsConfirmationProviderStat(
                provider: provider,
                count: count,
                percentage: percentage
            )
        }
    }

    private static func isAffirmative(_ rawValue: String) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return ["Y", "V", "C", "CONFIRMED", "VERIFIED"].contains(value)
    }

    static func chronologicalKey(for record: QSORecordModel) -> String {
        let date = record["QSO_DATE"].filter(\.isNumber)
        let time = record["TIME_ON"].filter(\.isNumber)
        return "\(date)\(time.padding(toLength: 6, withPad: "0", startingAt: 0))\(String(format: "%012d", record.index))"
    }

    // Reusable ADIF date parser (yyyyMMdd -> Date)
    private static func parseADIFDate(_ raw: String) -> Date? {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count == 8 else { return nil }
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = Int(clean.prefix(4))
        components.month = Int(clean.dropFirst(4).prefix(2))
        components.day = Int(clean.suffix(2))
        return components.date
    }
}

nonisolated enum ConfirmedProgressAnalyzer {
    static func makeSummary(records: [QSORecordModel], ownerRankData: QRZRankResponse?) -> ConfirmedProgressSummary {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let confirmedDates = records.compactMap { record -> Date? in
            guard record.isConfirmed else { return nil }
            return confirmationDate(for: record) ?? parseADIFDate(record["QSO_DATE"])
        }

        let todayStart = calendar.startOfDay(for: now)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? todayStart
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? todayStart
        let yearStart = calendar.dateInterval(of: .year, for: now)?.start ?? todayStart

        let todayCount = confirmedDates.filter { calendar.isDate($0, inSameDayAs: now) }.count
        let weekCount = confirmedDates.filter { $0 >= weekStart }.count
        let monthCount = confirmedDates.filter { $0 >= monthStart }.count
        let yearCount = confirmedDates.filter { $0 >= yearStart }.count

        let monthlyCounts = monthlyConfirmedCounts(from: confirmedDates)
        let monthlyRate = recentMonthlyRate(monthlyCounts: monthlyCounts)
        let currentTotal = confirmedDates.count
        let historicalPoints = cumulativePoints(monthlyCounts: monthlyCounts)
        let currentQsoRank = parseRank(ownerRankData?.rank_qso ?? "")
        let currentBandRank = parseRank(ownerRankData?.rank_band ?? "")
        let currentDxccRank = parseRank(ownerRankData?.rank_countries ?? "")
        let currentQsoScore = parseRank(ownerRankData?.score_qso ?? "")
        let currentBandScore = parseRank(ownerRankData?.score_band ?? "")
        let currentDxccScore = parseRank(ownerRankData?.score_countries ?? "")

        let forecasts = [3, 6, 12].map { months in
            let gain = max(0, Int((monthlyRate * Double(months)).rounded()))
            let projectedQsoScore = projectedScore(from: currentQsoScore, qsoGain: gain, currentQsoScore: currentQsoScore, weight: 1.0)
            let projectedBandScore = projectedScore(from: currentBandScore, qsoGain: gain, currentQsoScore: currentQsoScore, weight: 1.0)
            let projectedDxccScore = projectedScore(from: currentDxccScore, qsoGain: gain, currentQsoScore: currentQsoScore, weight: 0.45)

            return ConfirmedForecast(
                months: months,
                projectedGain: gain,
                projectedTotal: currentTotal + gain,
                currentQsoRank: currentQsoRank,
                currentBandRank: currentBandRank,
                currentDxccRank: currentDxccRank,
                projectedQsoScore: projectedQsoScore,
                projectedBandScore: projectedBandScore,
                projectedDxccScore: projectedDxccScore,
                projectedQsoRank: projectedRank(from: currentQsoRank, currentScore: currentQsoScore, projectedScore: projectedQsoScore),
                projectedBandRank: projectedRank(from: currentBandRank, currentScore: currentBandScore, projectedScore: projectedBandScore),
                projectedDxccRank: projectedRank(from: currentDxccRank, currentScore: currentDxccScore, projectedScore: projectedDxccScore)
            )
        }

        let forecastPoints = forecasts.map {
            ConfirmedProgressPoint(label: "+\($0.months)m", cumulativeCount: $0.projectedTotal, isForecast: true)
        }

        return ConfirmedProgressSummary(
            todayCount: todayCount,
            weekCount: weekCount,
            monthCount: monthCount,
            yearCount: yearCount,
            monthlyRate: monthlyRate,
            chartPoints: historicalPoints + forecastPoints,
            forecasts: forecasts
        )
    }

    private static func confirmationDate(for record: QSORecordModel) -> Date? {
        let dateFields = [
            "APP_QRZLOG_QSLDATE",
            "QRZLOG_QSLRDATE",
            "APP_QRZLOG_QSLRDATE",
            "LOTW_QSLRDATE",
            "APP_LOTW_QSLRDATE",
            "EQSL_QSLRDATE",
            "APP_EQSL_QSLRDATE",
            "QSLRDATE"
        ]

        for field in dateFields {
            if let date = parseADIFDate(record[field]) {
                return date
            }
        }

        return nil
    }

    private static func parseADIFDate(_ raw: String) -> Date? {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count == 8 else { return nil }

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = Int(clean.prefix(4))
        components.month = Int(clean.dropFirst(4).prefix(2))
        components.day = Int(clean.suffix(2))
        return components.date
    }

    private static func monthlyConfirmedCounts(from dates: [Date]) -> [(key: String, count: Int)] {
        let calendar = Calendar(identifier: .gregorian)
        var buckets: [String: Int] = [:]

        for date in dates {
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let key = String(format: "%04d-%02d", year, month)
            buckets[key, default: 0] += 1
        }

        return buckets.keys.sorted().map { ($0, buckets[$0] ?? 0) }
    }

    private static func recentMonthlyRate(monthlyCounts: [(key: String, count: Int)]) -> Double {
        let activeCounts = monthlyCounts.map(\.count).filter { $0 > 0 }
        guard !activeCounts.isEmpty else { return 0 }

        let recent = activeCounts.suffix(12)
        return Double(recent.reduce(0, +)) / Double(recent.count)
    }

    private static func cumulativePoints(monthlyCounts: [(key: String, count: Int)]) -> [ConfirmedProgressPoint] {
        let visibleCounts = Array(monthlyCounts.suffix(24))
        let hiddenCounts = monthlyCounts.dropLast(visibleCounts.count)
        var runningTotal = hiddenCounts.reduce(0) { $0 + $1.count }

        return visibleCounts.map { item in
            runningTotal += item.count
            return ConfirmedProgressPoint(label: shortMonthLabel(item.key), cumulativeCount: runningTotal, isForecast: false)
        }
    }

    private static func shortMonthLabel(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2 else { return key }
        return "\(parts[1])/\(parts[0].suffix(2))"
    }

    private static func parseRank(_ raw: String) -> Int? {
        let digits = raw.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    private static func projectedScore(from currentScore: Int?, qsoGain: Int, currentQsoScore: Int?, weight: Double) -> Int? {
        guard let currentScore, currentScore > 0 else { return nil }
        guard let currentQsoScore, currentQsoScore > 0, qsoGain > 0 else { return currentScore }

        let scoreShare = Double(currentScore) / Double(currentQsoScore)
        let scoreGain = Int((Double(qsoGain) * scoreShare * weight).rounded())
        return currentScore + max(0, scoreGain)
    }

    private static func projectedRank(from currentRank: Int?, currentScore: Int?, projectedScore: Int?) -> Int? {
        guard let currentRank else { return nil }
        guard let currentScore, let projectedScore, currentScore > 0, projectedScore > currentScore else { return currentRank }

        let growthRatio = Double(projectedScore) / Double(currentScore)
        return max(1, Int((Double(currentRank) / growthRatio).rounded()))
    }
}

struct QRZRankProjectionTable: View {
    let forecasts: [ConfirmedForecast]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("QRZ Rank Projection")
                .font(.headline)

            VStack(spacing: 0) {
                rankHeader
                rankRow(title: "QSO Rank", currentRank: forecasts.first?.currentQsoRank ?? nil, ranks: forecasts.map(\.projectedQsoRank))
                rankRow(title: "Band Rank", currentRank: forecasts.first?.currentBandRank ?? nil, ranks: forecasts.map(\.projectedBandRank))
                rankRow(title: "DXCC Rank", currentRank: forecasts.first?.currentDxccRank ?? nil, ranks: forecasts.map(\.projectedDxccRank))
            }
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.25), lineWidth: 1))
        }
    }

    private var rankHeader: some View {
        HStack {
            Text("Ranking")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Now")
                .frame(width: 90, alignment: .trailing)
            ForEach(forecasts) { forecast in
                Text("+\(forecast.months)m")
                    .frame(width: 90, alignment: .trailing)
            }
        }
        .font(.caption.bold())
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
    }

    private func rankRow(title: String, currentRank: Int?, ranks: [Int?]) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .bold()
                .frame(maxWidth: .infinity, alignment: .leading)
            rankText(currentRank)
            ForEach(Array(ranks.enumerated()), id: \.offset) { _, rank in
                rankText(rank)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .border(Color.gray.opacity(0.12), width: 0.5)
    }

    private func rankText(_ rank: Int?) -> some View {
        Text(rank.map { "#\(formattedNumber($0))" } ?? "N/A")
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(rank == nil ? .secondary : .accentColor)
            .frame(width: 90, alignment: .trailing)
    }

    private func formattedNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

struct ProgressMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(.headline, design: .monospaced))
                    .bold()
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.25), lineWidth: 1))
    }
}

struct ConfirmedProgressChart: View {
    let points: [ConfirmedProgressPoint]

    private var maxValue: Int {
        max(points.map(\.cumulativeCount).max() ?? 1, 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let plotHeight = max(1, geometry.size.height - 28)
            let plotWidth = max(1, geometry.size.width - 42)
            let origin = CGPoint(x: 34, y: plotHeight)
            let step = points.count > 1 ? plotWidth / CGFloat(points.count - 1) : plotWidth
            let coordinates = points.enumerated().map { index, point in
                CGPoint(
                    x: origin.x + CGFloat(index) * step,
                    y: plotHeight - (CGFloat(point.cumulativeCount) / CGFloat(maxValue)) * (plotHeight - 12)
                )
            }

            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: origin.x, y: 0))
                    path.addLine(to: origin)
                    path.addLine(to: CGPoint(x: geometry.size.width, y: origin.y))
                }
                .stroke(Color.gray.opacity(0.35), lineWidth: 1)

                Path { path in
                    for row in 0...4 {
                        let y = CGFloat(row) * plotHeight / 4
                        path.move(to: CGPoint(x: origin.x, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }
                .stroke(Color.gray.opacity(0.12), lineWidth: 1)

                Path { path in
                    guard let first = coordinates.first else { return }
                    path.move(to: first)
                    for point in coordinates.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(LinearGradient(colors: [.green, .blue], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    let coordinate = coordinates[index]
                    Circle()
                        .fill(point.isForecast ? Color.orange : Color.green)
                        .frame(width: point.isForecast ? 7 : 5, height: point.isForecast ? 7 : 5)
                        .position(coordinate)
                        .help("\(point.label): \(point.cumulativeCount) confirmed")
                }

                Text("\(maxValue)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .position(x: 16, y: 8)

                Text(points.first?.label ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .position(x: origin.x + 12, y: geometry.size.height - 10)

                Text(points.last?.label ?? "")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .position(x: geometry.size.width - 22, y: geometry.size.height - 10)
            }
        }
    }
}
