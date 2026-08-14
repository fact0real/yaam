//
//  StatisticsView.swift
//  ADIF to Excel
//
//  Created by factoreal on 7/31/26.
//

import SwiftUI

// MARK: - Interactive Log Statistics Window
struct StatisticsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab = 0
    @State private var selectedUnconfirmedBand = "All Bands"
    @State private var snapshot: StatisticsSnapshot?

    private var currentSnapshot: StatisticsSnapshot {
        snapshot ?? StatisticsSnapshot.make(from: appState)
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
            }
            .padding(.top, 4)
            
            Divider()
            
            // Analytics Summary Badges Cards
            HStack(spacing: 10) {
                StatBadgeCard(title: "Total QSOs", value: "\(stats.totalQSOCount)", icon: "antenna.radiowaves.left.and.right", color: .blue)
                StatBadgeCard(title: "Confirmed", value: "\(stats.confirmedCount)", icon: "checkmark.seal.fill", color: .green)
                StatBadgeCard(title: "Unconfirmed", value: "\(stats.unconfirmedCount)", icon: "clock.fill", color: .orange)
                StatBadgeCard(title: "DXCC Countries", value: "\(stats.dxccCountryCount)", icon: "globe.americas.fill", color: .purple)
            }
            
            Picker("", selection: $selectedTab) {
                Text("Band Breakdown").tag(0)
                Text("Country Breakdown").tag(1)
                Text("Unconfirmed DXCC").tag(2)
                Text("Progress").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 2)
            
            // Tab 0: Band Breakdown Table
            if selectedTab == 0 {
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
            } else if selectedTab == 1 {
                // Tab 1: Country Breakdown Table
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
                                }
                                .padding(.horizontal, 10)
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
                // Tab 2: Worked countries that are not confirmed on each band
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
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(bandStat.band)
                                                .font(.system(.headline, design: .monospaced))
                                                .foregroundColor(.accentColor)
                                            Spacer()
                                            Text("\(bandStat.countries.count) unconfirmed DXCC")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }

                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 8)], alignment: .leading, spacing: 8) {
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
            } else {
                confirmedProgressView
            }
            
            Spacer()
            Divider()
            
            HStack {
                Spacer()
                Button("OK") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .frame(width: 90)
            }
        }
        .padding(16)
        .frame(width: 900, height: 680)
        .onAppear {
            appState.refreshOwnerQRZRankIfNeeded()
            snapshot = StatisticsSnapshot.make(from: appState)
        }
    }

    private var confirmedProgressView: some View {
        let summary = progressSummary

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ProgressMetricCard(title: "Today", value: "\(summary.todayCount)", icon: "calendar.day.timeline.left", color: .blue)
                    ProgressMetricCard(title: "This Week", value: "\(summary.weekCount)", icon: "calendar", color: .green)
                    ProgressMetricCard(title: "This Month", value: "\(summary.monthCount)", icon: "calendar.badge.clock", color: .orange)
                    ProgressMetricCard(title: "This Year", value: "\(summary.yearCount)", icon: "calendar.circle", color: .purple)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Confirmed QSO Progress")
                                .font(.headline)
                            Text("Cumulative confirmed QSOs by confirmation date, with projection based on recent confirmed log history.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("Rate: \(String(format: "%.1f", summary.monthlyRate)) / month")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
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
                        ConfirmedProgressChart(points: summary.chartPoints)
                            .frame(height: 240)
                    }
                }
                .padding(12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))

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
        }
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
        dismiss()
    }
}

struct UnconfirmedCountryButton: View {
    let band: String
    let countryStat: UnconfirmedCountryStatModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(countryToFlag(countryStat.country))
                Text(countryStat.country)
                    .font(.caption)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(countryStat.qsoCount)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.orange)
                    .bold()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
        .buttonStyle(.plain)
        .help("Show unconfirmed \(countryStat.country) QSOs on \(band)")
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

struct ConfirmedProgressSummary {
    let todayCount: Int
    let weekCount: Int
    let monthCount: Int
    let yearCount: Int
    let monthlyRate: Double
    let chartPoints: [ConfirmedProgressPoint]
    let forecasts: [ConfirmedForecast]
}

struct ConfirmedProgressPoint: Identifiable {
    let id = UUID()
    let label: String
    let cumulativeCount: Int
    let isForecast: Bool
}

struct ConfirmedForecast: Identifiable {
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

struct StatisticsSnapshot {
    let totalQSOCount: Int
    let confirmedCount: Int
    let unconfirmedCount: Int
    let dxccCountryCount: Int
    let bandStatistics: [BandStatModel]
    let countryStatistics: [CountryStatModel]
    let unconfirmedBandCountryStatistics: [UnconfirmedBandCountryStatModel]
    let progressSummary: ConfirmedProgressSummary

    static func make(from appState: AppState) -> StatisticsSnapshot {
        StatisticsSnapshot(
            totalQSOCount: appState.qsoRecords.count,
            confirmedCount: appState.totalConfirmedCount,
            unconfirmedCount: appState.totalUnconfirmedCount,
            dxccCountryCount: appState.availableCountries.count,
            bandStatistics: appState.bandStatistics,
            countryStatistics: appState.countryStatistics,
            unconfirmedBandCountryStatistics: appState.unconfirmedBandCountryStatistics,
            progressSummary: ConfirmedProgressAnalyzer.makeSummary(records: appState.qsoRecords, ownerRankData: appState.ownerRankData)
        )
    }
}

enum ConfirmedProgressAnalyzer {
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
