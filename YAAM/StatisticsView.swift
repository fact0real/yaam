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

    private var unconfirmedBandOptions: [String] {
        ["All Bands"] + appState.unconfirmedBandCountryStatistics.map(\.band)
    }

    private var visibleUnconfirmedBandCountryStatistics: [UnconfirmedBandCountryStatModel] {
        guard selectedUnconfirmedBand != "All Bands" else {
            return appState.unconfirmedBandCountryStatistics
        }

        return appState.unconfirmedBandCountryStatistics.filter { $0.band == selectedUnconfirmedBand }
    }

    var body: some View {
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
                StatBadgeCard(title: "Total QSOs", value: "\(appState.qsoRecords.count)", icon: "antenna.radiowaves.left.and.right", color: .blue)
                StatBadgeCard(title: "Confirmed", value: "\(appState.totalConfirmedCount)", icon: "checkmark.seal.fill", color: .green)
                StatBadgeCard(title: "Unconfirmed", value: "\(appState.totalUnconfirmedCount)", icon: "clock.fill", color: .orange)
                StatBadgeCard(title: "DXCC Countries", value: "\(appState.availableCountries.count)", icon: "globe.americas.fill", color: .purple)
            }
            
            Picker("", selection: $selectedTab) {
                Text("Band Breakdown").tag(0)
                Text("Country Breakdown").tag(1)
                Text("Unconfirmed DXCC").tag(2)
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
                            
                            ForEach(appState.bandStatistics) { stat in
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
                            
                            ForEach(appState.countryStatistics) { cStat in
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
            } else {
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
        .frame(width: 620, height: 480)
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
