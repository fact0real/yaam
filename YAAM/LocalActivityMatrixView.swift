//
//  LocalActivityMatrixView.swift
//  YAAM
//
//  Interactive Local Time Activity Matrix & DX Country Analytics
//

import SwiftUI
import AppKit

// MARK: - Parsed QSO Model for Local Time Analytics
struct ParsedLocalQSO: Identifiable, Sendable {
    let id: UUID
    let record: QSORecordModel
    let callsign: String
    let country: String
    let flag: String
    let band: String
    let mode: String
    let rstSent: String
    let rstRcvd: String
    let localDate: Date
    let localHour: Int        // 0...23
    let localWeekday: Int     // 1...7 (1=Sun, 2=Mon, ..., 7=Sat)
    let isConfirmed: Bool
    let localTimeStr: String   // "HH:mm"
    let localDateStr: String   // "yyyy-MM-dd"
}

// MARK: - Matrix Dimension Types
enum ActivityMatrixMode: String, CaseIterable, Identifiable {
    case dayVsHour = "Day of Week vs Local Hour"
    case bandVsHour = "Amateur Band vs Local Hour"
    case dayVsBand = "Day of Week vs Band"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .dayVsHour: return "Day vs Hour (روز / ساعت محلی)"
        case .bandVsHour: return "Band vs Hour (باند / ساعت محلی)"
        case .dayVsBand: return "Day vs Band (روز / باند)"
        }
    }

    var icon: String {
        switch self {
        case .dayVsHour: return "calendar.day.timeline.left"
        case .bandVsHour: return "waveform.path.ecg"
        case .dayVsBand: return "square.grid.3x3"
        }
    }
}

// MARK: - Solar Diurnal Phase Helper
enum LocalSolarPhase: String, CaseIterable {
    case night = "Night"
    case dawn = "Sunrise / Dawn"
    case day = "Daylight"
    case dusk = "Sunset / Dusk"

    var icon: String {
        switch self {
        case .night: return "moon.stars.fill"
        case .dawn: return "sunrise.fill"
        case .day: return "sun.max.fill"
        case .dusk: return "sunset.fill"
        }
    }

    var color: Color {
        switch self {
        case .night: return .indigo
        case .dawn: return .orange
        case .day: return .yellow
        case .dusk: return .pink
        }
    }

    static func phase(forHour hour: Int) -> LocalSolarPhase {
        switch hour {
        case 5...7: return .dawn
        case 8...16: return .day
        case 17...19: return .dusk
        default: return .night
        }
    }
}

// MARK: - Weekday Definition (Customized for Saturday-Friday sequence)
struct WeekdayDefinition: Identifiable, Hashable {
    let weekdayIndex: Int // 1=Sun, 2=Mon, 3=Tue, 4=Wed, 5=Thu, 6=Fri, 7=Sat
    let nameEn: String
    let nameFa: String
    let shortEn: String

    var id: Int { weekdayIndex }

    var displayLabel: String {
        "\(shortEn) · \(nameFa)"
    }

    // Standard sequence starting Saturday (customary in Iran and Middle East DXers)
    static let orderedWeekdays: [WeekdayDefinition] = [
        WeekdayDefinition(weekdayIndex: 7, nameEn: "Saturday", nameFa: "شنبه", shortEn: "Sat"),
        WeekdayDefinition(weekdayIndex: 1, nameEn: "Sunday", nameFa: "یکشنبه", shortEn: "Sun"),
        WeekdayDefinition(weekdayIndex: 2, nameEn: "Monday", nameFa: "دوشنبه", shortEn: "Mon"),
        WeekdayDefinition(weekdayIndex: 3, nameEn: "Tuesday", nameFa: "سه‌شنبه", shortEn: "Tue"),
        WeekdayDefinition(weekdayIndex: 4, nameEn: "Wednesday", nameFa: "چهارشنبه", shortEn: "Wed"),
        WeekdayDefinition(weekdayIndex: 5, nameEn: "Thursday", nameFa: "پنج‌شنبه", shortEn: "Thu"),
        WeekdayDefinition(weekdayIndex: 6, nameEn: "Friday", nameFa: "جمعه", shortEn: "Fri")
    ]
}

// MARK: - Main Interactive View
struct LocalActivityMatrixView: View {
    let records: [QSORecordModel]
    var onShowInLog: ((QSORecordModel) -> Void)?

    // 11 Standard Amateur Radio Bands
    static let amateur11Bands: [String] = [
        "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m"
    ]

    @State private var matrixMode: ActivityMatrixMode = .dayVsHour
    @State private var selectedBandFilter: String = "All"
    @State private var confirmationFilter: String = "All" // "All", "Confirmed", "Unconfirmed"
    @State private var searchQuery: String = ""

    // Selection State
    @State private var selectedSlotWeekday: Int? = nil
    @State private var selectedSlotHour: Int? = nil
    @State private var selectedSlotBand: String? = nil

    // Cache parsed QSOs
    @State private var parsedQSOs: [ParsedLocalQSO] = []
    @State private var isCalculating = false

    private var localTimeZone: TimeZone {
        TimeZone.current
    }

    private var localTimezoneName: String {
        let seconds = localTimeZone.secondsFromGMT()
        let hours = seconds / 3600
        let minutes = abs((seconds % 3600) / 60)
        let sign = hours >= 0 ? "+" : "-"
        let offsetStr = String(format: "UTC%@%d:%02d", sign, abs(hours), minutes)
        return "\(localTimeZone.identifier) (\(offsetStr))"
    }

    // Filtered QSOs based on top-level filters
    private var filteredQSOs: [ParsedLocalQSO] {
        parsedQSOs.filter { qso in
            if selectedBandFilter != "All" && qso.band.lowercased() != selectedBandFilter.lowercased() {
                return false
            }
            if confirmationFilter == "Confirmed" && !qso.isConfirmed {
                return false
            }
            if confirmationFilter == "Unconfirmed" && qso.isConfirmed {
                return false
            }
            if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
                let matchCountry = qso.country.lowercased().contains(query)
                let matchCall = qso.callsign.lowercased().contains(query)
                let matchBand = qso.band.lowercased().contains(query)
                if !matchCountry && !matchCall && !matchBand {
                    return false
                }
            }
            return true
        }
    }

    // QSOs in currently selected slot (if any)
    private var selectedSlotQSOs: [ParsedLocalQSO] {
        guard selectedSlotHour != nil || selectedSlotWeekday != nil || selectedSlotBand != nil else {
            return []
        }

        return filteredQSOs.filter { qso in
            if let h = selectedSlotHour, qso.localHour != h { return false }
            if let w = selectedSlotWeekday, qso.localWeekday != w { return false }
            if let b = selectedSlotBand, qso.band.lowercased() != b.lowercased() { return false }
            return true
        }
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 12) {
            // 1. Top Analytics Insight Badges (Peak Hour, Day, Band, Country)
            insightsHeaderCards

            // 2. Control Bar (Mode switcher, Band pills, Confirmation, Search)
            controlsBar

            // 3. Main Workspace (Heatmap Matrix + Detail Inspector)
            HSplitView {
                // Left Pane: Visual Matrix Heatmap
                VStack(alignment: .leading, spacing: 8) {
                    matrixHeaderInfo

                    ScrollView([.horizontal, .vertical]) {
                        switch matrixMode {
                        case .dayVsHour:
                            dayVsHourMatrixView
                        case .bandVsHour:
                            bandVsHourMatrixView
                        case .dayVsBand:
                            dayVsBandMatrixView
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25), lineWidth: 1))
                }
                .frame(minWidth: 540, maxWidth: .infinity)

                // Right Pane: Deep Dive Inspector (Countries & Contacts)
                inspectorDetailPane
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 460)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .onAppear {
            parseAllRecords()
        }
        .onChange(of: records.count) { _ in
            parseAllRecords()
        }
    }

    // MARK: - Insights Header Cards
    private var insightsHeaderCards: some View {
        let qsos = filteredQSOs
        let totalCount = qsos.count

        // 1. Peak Local Hour
        var hourCounts = [Int: Int]()
        for q in qsos { hourCounts[q.localHour, default: 0] += 1 }
        let peakHour = hourCounts.max(by: { $0.value < $1.value })

        // 2. Most Productive Day
        var dayCounts = [Int: Int]()
        for q in qsos { dayCounts[q.localWeekday, default: 0] += 1 }
        let peakDayIdx = dayCounts.max(by: { $0.value < $1.value })?.key
        let peakDayDef = WeekdayDefinition.orderedWeekdays.first(where: { $0.weekdayIndex == peakDayIdx })

        // 3. Top Band
        var bandCounts = [String: Int]()
        for q in qsos { bandCounts[q.band, default: 0] += 1 }
        let peakBand = bandCounts.max(by: { $0.value < $1.value })

        // 4. Top Country
        var countryCounts = [String: Int]()
        for q in qsos {
            if !q.country.isEmpty && q.country != "Unknown" {
                countryCounts[q.country, default: 0] += 1
            }
        }
        let peakCountry = countryCounts.max(by: { $0.value < $1.value })
        let peakCountryFlag = peakCountry != nil ? countryToFlag(peakCountry!.key) : "🌍"

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 230), spacing: 8)], spacing: 8) {
            InsightCard(
                title: "Peak Local Hour",
                value: peakHour != nil ? String(format: "%02d:00 - %02d:00", peakHour!.key, (peakHour!.key + 1) % 24) : "N/A",
                subtitle: peakHour != nil ? "\(peakHour!.value) QSOs (\(totalCount > 0 ? Int(Double(peakHour!.value)/Double(totalCount)*100) : 0)%)" : "No activity",
                icon: peakHour != nil ? LocalSolarPhase.phase(forHour: peakHour!.key).icon : "clock.fill",
                color: .orange
            )

            InsightCard(
                title: "Most Active Day",
                value: peakDayDef != nil ? peakDayDef!.nameFa : "N/A",
                subtitle: peakDayIdx != nil && dayCounts[peakDayIdx!] != nil ? "\(peakDayDef!.nameEn) · \(dayCounts[peakDayIdx!]!) QSOs" : "No activity",
                icon: "calendar.badge.clock",
                color: .blue
            )

            InsightCard(
                title: "Top Amateur Band",
                value: peakBand != nil ? peakBand!.key.uppercased() : "N/A",
                subtitle: peakBand != nil ? "\(peakBand!.value) QSOs on \(peakBand!.key)" : "11 Bands Potential",
                icon: "waveform.path.ecg",
                color: .teal
            )

            InsightCard(
                title: "Top DXCC Entity",
                value: peakCountry != nil ? "\(peakCountryFlag) \(peakCountry!.key)" : "N/A",
                subtitle: peakCountry != nil ? "\(peakCountry!.value) QSOs logged" : "Global DX",
                icon: "globe.americas.fill",
                color: .purple
            )

            InsightCard(
                title: "Local Time Base",
                value: localTimeZone.abbreviation() ?? "LOCAL",
                subtitle: localTimezoneName,
                icon: "globe.asia.australia.fill",
                color: .indigo
            )
        }
    }

    // MARK: - Controls Bar
    private var controlsBar: some View {
        HStack(spacing: 12) {
            // Mode Picker
            Picker("", selection: $matrixMode) {
                ForEach(ActivityMatrixMode.allCases) { mode in
                    Label(mode.localizedTitle, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 430)

            Divider().frame(height: 18)

            // Band Filter Pills Menu
            Menu {
                Button("All Bands") {
                    selectedBandFilter = "All"
                }
                Divider()
                ForEach(Self.amateur11Bands, id: \.self) { band in
                    Button(band.uppercased()) {
                        selectedBandFilter = band
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text(selectedBandFilter == "All" ? "All 11 Bands" : "Band: \(selectedBandFilter.uppercased())")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .menuStyle(.borderedButton)

            // Confirmation Filter
            Picker("", selection: $confirmationFilter) {
                Text("All").tag("All")
                Text("Confirmed").tag("Confirmed")
                Text("Unconfirmed").tag("Unconfirmed")
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            // Search by Country or Call
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Filter country or call...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            .frame(maxWidth: 200)

            Spacer()

            // Reset Selection Button
            if selectedSlotHour != nil || selectedSlotWeekday != nil || selectedSlotBand != nil {
                Button {
                    selectedSlotHour = nil
                    selectedSlotWeekday = nil
                    selectedSlotBand = nil
                } label: {
                    Label("Clear Selection", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Matrix Header Info & Solar Indicator
    private var matrixHeaderInfo: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.2.circlepath")
                .foregroundColor(.accentColor)
            Text("24-Hour Local Timeline Matrix")
                .font(.system(size: 12, weight: .bold))

            Text("• All hours aligned to local time (\(localTimeZone.identifier))")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            // Solar Phase Legend
            HStack(spacing: 8) {
                solarLegendItem(phase: .dawn)
                solarLegendItem(phase: .day)
                solarLegendItem(phase: .dusk)
                solarLegendItem(phase: .night)
            }
        }
        .padding(.horizontal, 4)
    }

    private func solarLegendItem(phase: LocalSolarPhase) -> some View {
        HStack(spacing: 3) {
            Image(systemName: phase.icon)
                .font(.system(size: 9))
                .foregroundColor(phase.color)
            Text(phase.rawValue)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Matrix 1: Day of Week vs Local Hour (7 rows x 24 cols)
    private var dayVsHourMatrixView: some View {
        let qsos = filteredQSOs

        // Build 2D lookup: [Weekday (1..7)][Hour (0..23)] -> [ParsedLocalQSO]
        var matrix: [Int: [Int: [ParsedLocalQSO]]] = [:]
        var maxSlotCount = 1

        for q in qsos {
            var row = matrix[q.localWeekday] ?? [:]
            var cell = row[q.localHour] ?? []
            cell.append(q)
            row[q.localHour] = cell
            matrix[q.localWeekday] = row
            if cell.count > maxSlotCount {
                maxSlotCount = cell.count
            }
        }

        return VStack(alignment: .leading, spacing: 3) {
            // Hours Axis Header (00..23)
            HStack(spacing: 3) {
                // Leading spacer for Weekday row header
                Text("DAY / TIME")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 96, alignment: .leading)

                ForEach(0..<24, id: \.self) { hour in
                    let phase = LocalSolarPhase.phase(forHour: hour)
                    VStack(spacing: 1) {
                        Image(systemName: phase.icon)
                            .font(.system(size: 8))
                            .foregroundColor(phase.color)
                        Text(String(format: "%02d", hour))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 34, height: 28)
                }

                // Total column header
                Text("TOTAL")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.bottom, 2)

            Divider()

            // Rows: Weekdays (Sat -> Fri)
            ForEach(WeekdayDefinition.orderedWeekdays) { day in
                let rowData = matrix[day.weekdayIndex] ?? [:]
                let rowTotal = rowData.values.reduce(0) { $0 + $1.count }

                HStack(spacing: 3) {
                    // Row Header
                    HStack(spacing: 4) {
                        Text(day.nameFa)
                            .font(.system(size: 10, weight: .bold))
                        Text(day.shortEn)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(width: 96, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedSlotWeekday == day.weekdayIndex && selectedSlotHour == nil {
                            selectedSlotWeekday = nil
                        } else {
                            selectedSlotWeekday = day.weekdayIndex
                            selectedSlotHour = nil
                            selectedSlotBand = nil
                        }
                    }

                    // 24 Hour Cells
                    ForEach(0..<24, id: \.self) { hour in
                        let cellQSOs = rowData[hour] ?? []
                        let isSelected = selectedSlotWeekday == day.weekdayIndex && selectedSlotHour == hour

                        HeatmapCell(
                            count: cellQSOs.count,
                            maxCount: maxSlotCount,
                            isSelected: isSelected,
                            width: 34,
                            height: 32
                        )
                        .onTapGesture {
                            if isSelected {
                                selectedSlotWeekday = nil
                                selectedSlotHour = nil
                            } else {
                                selectedSlotWeekday = day.weekdayIndex
                                selectedSlotHour = hour
                                selectedSlotBand = nil
                            }
                        }
                        .help("\(day.nameEn) (\(day.nameFa)) @ \(String(format: "%02d:00", hour)) Local: \(cellQSOs.count) QSOs")
                    }

                    // Row Total Badge
                    Text("\(rowTotal)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(rowTotal > 0 ? .primary : .secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.vertical, 1)
            }

            Divider()

            // Footer: Hourly totals across all days
            HStack(spacing: 3) {
                Text("HOURLY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 96, alignment: .leading)

                ForEach(0..<24, id: \.self) { hour in
                    let colCount = matrix.values.reduce(0) { $0 + ($1[hour]?.count ?? 0) }
                    Text(colCount > 0 ? "\(colCount)" : "·")
                        .font(.system(size: 9, weight: colCount > 0 ? .semibold : .regular, design: .monospaced))
                        .foregroundColor(colCount > 0 ? .accentColor : .secondary.opacity(0.4))
                        .frame(width: 34, alignment: .center)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedSlotHour == hour && selectedSlotWeekday == nil {
                                selectedSlotHour = nil
                            } else {
                                selectedSlotHour = hour
                                selectedSlotWeekday = nil
                                selectedSlotBand = nil
                            }
                        }
                }

                Text("\(qsos.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.top, 2)
        }
        .padding(10)
    }

    // MARK: - Matrix 2: Amateur Band vs Local Hour (11 rows x 24 cols)
    private var bandVsHourMatrixView: some View {
        let qsos = filteredQSOs

        // Build 2D lookup: [Band][Hour (0..23)] -> [ParsedLocalQSO]
        var matrix: [String: [Int: [ParsedLocalQSO]]] = [:]
        var maxSlotCount = 1

        for q in qsos {
            let b = q.band.lowercased()
            var row = matrix[b] ?? [:]
            var cell = row[q.localHour] ?? []
            cell.append(q)
            row[q.localHour] = cell
            matrix[b] = row
            if cell.count > maxSlotCount {
                maxSlotCount = cell.count
            }
        }

        return VStack(alignment: .leading, spacing: 3) {
            // Hours Axis Header
            HStack(spacing: 3) {
                Text("BAND / TIME")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 96, alignment: .leading)

                ForEach(0..<24, id: \.self) { hour in
                    let phase = LocalSolarPhase.phase(forHour: hour)
                    VStack(spacing: 1) {
                        Image(systemName: phase.icon)
                            .font(.system(size: 8))
                            .foregroundColor(phase.color)
                        Text(String(format: "%02d", hour))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 34, height: 28)
                }

                Text("TOTAL")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.bottom, 2)

            Divider()

            // Rows: 11 Amateur Bands
            ForEach(Self.amateur11Bands, id: \.self) { band in
                let rowData = matrix[band.lowercased()] ?? [:]
                let rowTotal = rowData.values.reduce(0) { $0 + $1.count }

                HStack(spacing: 3) {
                    HStack {
                        Text(band.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .frame(width: 96, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedSlotBand == band && selectedSlotHour == nil {
                            selectedSlotBand = nil
                        } else {
                            selectedSlotBand = band
                            selectedSlotHour = nil
                            selectedSlotWeekday = nil
                        }
                    }

                    ForEach(0..<24, id: \.self) { hour in
                        let cellQSOs = rowData[hour] ?? []
                        let isSelected = selectedSlotBand?.lowercased() == band.lowercased() && selectedSlotHour == hour

                        HeatmapCell(
                            count: cellQSOs.count,
                            maxCount: maxSlotCount,
                            isSelected: isSelected,
                            width: 34,
                            height: 28
                        )
                        .onTapGesture {
                            if isSelected {
                                selectedSlotBand = nil
                                selectedSlotHour = nil
                            } else {
                                selectedSlotBand = band
                                selectedSlotHour = hour
                                selectedSlotWeekday = nil
                            }
                        }
                        .help("\(band.uppercased()) @ \(String(format: "%02d:00", hour)) Local: \(cellQSOs.count) QSOs")
                    }

                    Text("\(rowTotal)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(rowTotal > 0 ? .primary : .secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.vertical, 1)
            }

            Divider()

            // Footer Hourly Totals
            HStack(spacing: 3) {
                Text("HOURLY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 96, alignment: .leading)

                ForEach(0..<24, id: \.self) { hour in
                    let colCount = matrix.values.reduce(0) { $0 + ($1[hour]?.count ?? 0) }
                    Text(colCount > 0 ? "\(colCount)" : "·")
                        .font(.system(size: 9, weight: colCount > 0 ? .semibold : .regular, design: .monospaced))
                        .foregroundColor(colCount > 0 ? .accentColor : .secondary.opacity(0.4))
                        .frame(width: 34, alignment: .center)
                }

                Text("\(qsos.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.top, 2)
        }
        .padding(10)
    }

    // MARK: - Matrix 3: Day of Week vs Band (7 rows x 11 cols)
    private var dayVsBandMatrixView: some View {
        let qsos = filteredQSOs

        // Build 2D lookup: [Weekday][Band] -> [ParsedLocalQSO]
        var matrix: [Int: [String: [ParsedLocalQSO]]] = [:]
        var maxSlotCount = 1

        for q in qsos {
            let b = q.band.lowercased()
            var row = matrix[q.localWeekday] ?? [:]
            var cell = row[b] ?? []
            cell.append(q)
            row[b] = cell
            matrix[q.localWeekday] = row
            if cell.count > maxSlotCount {
                maxSlotCount = cell.count
            }
        }

        return VStack(alignment: .leading, spacing: 3) {
            // Band Axis Header
            HStack(spacing: 4) {
                Text("DAY / BAND")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 96, alignment: .leading)

                ForEach(Self.amateur11Bands, id: \.self) { band in
                    Text(band.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 48, height: 26)
                }

                Text("TOTAL")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.bottom, 2)

            Divider()

            // Rows: Weekdays
            ForEach(WeekdayDefinition.orderedWeekdays) { day in
                let rowData = matrix[day.weekdayIndex] ?? [:]
                let rowTotal = rowData.values.reduce(0) { $0 + $1.count }

                HStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Text(day.nameFa)
                            .font(.system(size: 10, weight: .bold))
                        Text(day.shortEn)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(width: 96, alignment: .leading)

                    ForEach(Self.amateur11Bands, id: \.self) { band in
                        let cellQSOs = rowData[band.lowercased()] ?? []
                        let isSelected = selectedSlotWeekday == day.weekdayIndex && selectedSlotBand?.lowercased() == band.lowercased()

                        HeatmapCell(
                            count: cellQSOs.count,
                            maxCount: maxSlotCount,
                            isSelected: isSelected,
                            width: 48,
                            height: 32
                        )
                        .onTapGesture {
                            if isSelected {
                                selectedSlotWeekday = nil
                                selectedSlotBand = nil
                            } else {
                                selectedSlotWeekday = day.weekdayIndex
                                selectedSlotBand = band
                                selectedSlotHour = nil
                            }
                        }
                        .help("\(day.nameEn) on \(band.uppercased()): \(cellQSOs.count) QSOs")
                    }

                    Text("\(rowTotal)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(rowTotal > 0 ? .primary : .secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.vertical, 1)
            }

            Divider()

            // Footer Band Totals
            HStack(spacing: 4) {
                Text("BAND TOTAL")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 96, alignment: .leading)

                ForEach(Self.amateur11Bands, id: \.self) { band in
                    let colCount = matrix.values.reduce(0) { $0 + ($1[band.lowercased()]?.count ?? 0) }
                    Text(colCount > 0 ? "\(colCount)" : "·")
                        .font(.system(size: 9, weight: colCount > 0 ? .semibold : .regular, design: .monospaced))
                        .foregroundColor(colCount > 0 ? .accentColor : .secondary.opacity(0.4))
                        .frame(width: 48, alignment: .center)
                }

                Text("\(qsos.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.accentColor)
                    .frame(width: 44, alignment: .trailing)
            }
            .padding(.top, 2)
        }
        .padding(10)
    }

    // MARK: - Inspector Detail Pane (Right Side)
    private var inspectorDetailPane: some View {
        let activeQSOs = (selectedSlotHour != nil || selectedSlotWeekday != nil || selectedSlotBand != nil)
            ? selectedSlotQSOs
            : filteredQSOs

        return VStack(alignment: .leading, spacing: 10) {
            // Inspector Header
            HStack(spacing: 8) {
                Image(systemName: "chart.pie.fill")
                    .foregroundColor(.accentColor)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 1) {
                    Text(slotTitle)
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                    Text(slotSubtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Total QSOs badge
                Text("\(activeQSOs.count) QSO\(activeQSOs.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .foregroundColor(.accentColor)
                    .cornerRadius(4)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            Divider()

            // Country Breakdown Section
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("TOP COUNTRIES & ENTITIES")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("QSOs / Conf")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)

                let countryRankings = computeCountryBreakdown(from: activeQSOs)

                if countryRankings.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "globe.europe.africa.fill")
                            .font(.largeTitle)
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No contacts in this time slot")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(countryRankings) { ranking in
                            CountryRankingRow(ranking: ranking, totalInSlot: activeQSOs.count)
                        }

                        // Recent / Highlighted Contacts Section in this slot
                        Section(header: Text("CONTACTS IN THIS SLOT").font(.system(size: 9, weight: .bold))) {
                            ForEach(activeQSOs.prefix(35)) { qso in
                                HStack(spacing: 6) {
                                    Text(qso.flag)
                                    Text(qso.callsign)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    Text(qso.band.uppercased())
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    Text(qso.localTimeStr)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)

                                    if qso.isConfirmed {
                                        Image(systemName: "checkmark.seal.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.green)
                                    }

                                    if let onShowInLog {
                                        Button {
                                            onShowInLog(qso.record)
                                        } label: {
                                            Image(systemName: "arrow.right.circle")
                                                .font(.system(size: 11))
                                                .foregroundColor(.accentColor)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Show in Log Table")
                                    }
                                }
                                .padding(.vertical, 1)
                            }
                        }
                    }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25), lineWidth: 1))
    }

    private var slotTitle: String {
        if let h = selectedSlotHour, let w = selectedSlotWeekday {
            let dayDef = WeekdayDefinition.orderedWeekdays.first(where: { $0.weekdayIndex == w })
            let dayName = dayDef?.nameFa ?? "Day \(w)"
            return "\(dayName) @ \(String(format: "%02d:00 - %02d:00", h, (h + 1) % 24))"
        } else if let h = selectedSlotHour, let b = selectedSlotBand {
            return "\(b.uppercased()) @ \(String(format: "%02d:00 - %02d:00", h, (h + 1) % 24))"
        } else if let w = selectedSlotWeekday, let b = selectedSlotBand {
            let dayDef = WeekdayDefinition.orderedWeekdays.first(where: { $0.weekdayIndex == w })
            return "\(dayDef?.nameFa ?? "") on \(b.uppercased())"
        } else if let h = selectedSlotHour {
            return "\(String(format: "%02d:00 - %02d:00", h, (h + 1) % 24)) Local Time"
        } else if let w = selectedSlotWeekday {
            let dayDef = WeekdayDefinition.orderedWeekdays.first(where: { $0.weekdayIndex == w })
            return "\(dayDef?.nameFa ?? "") (\(dayDef?.nameEn ?? ""))"
        } else if let b = selectedSlotBand {
            return "Band \(b.uppercased()) (All Hours)"
        } else {
            return "Global Log Overview"
        }
    }

    private var slotSubtitle: String {
        if selectedSlotHour != nil || selectedSlotWeekday != nil || selectedSlotBand != nil {
            return "Selected slot details · Click any cell to inspect"
        } else {
            return "Showing top countries across all \(filteredQSOs.count) filtered QSOs"
        }
    }

    // MARK: - Country Breakdown Calculation
    private func computeCountryBreakdown(from qsos: [ParsedLocalQSO]) -> [CountryRankingItem] {
        var groups: [String: (flag: String, total: Int, confirmed: Int)] = [:]

        for q in qsos {
            let c = q.country.isEmpty ? "Unknown" : q.country
            var current = groups[c] ?? (flag: q.flag, total: 0, confirmed: 0)
            current.total += 1
            if q.isConfirmed {
                current.confirmed += 1
            }
            groups[c] = current
        }

        return groups.map { (country, val) in
            CountryRankingItem(
                id: country,
                country: country,
                flag: val.flag,
                totalQSOs: val.total,
                confirmedQSOs: val.confirmed
            )
        }
        .sorted(by: { $0.totalQSOs > $1.totalQSOs })
    }

    // MARK: - Parse All Records from UTC to Local Time
    private func parseAllRecords() {
        isCalculating = true
        let rawRecords = records
        let cal = Calendar(identifier: .gregorian)
        let utcTZ = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        let localTZ = TimeZone.current

        DispatchQueue.global(qos: .userInitiated).async {
            var results: [ParsedLocalQSO] = []
            results.reserveCapacity(rawRecords.count)

            let localDateFmt = DateFormatter()
            localDateFmt.dateFormat = "yyyy-MM-dd"
            localDateFmt.timeZone = localTZ

            let localTimeFmt = DateFormatter()
            localTimeFmt.dateFormat = "HH:mm"
            localTimeFmt.timeZone = localTZ

            for r in rawRecords {
                guard let localInfo = Self.extractLocalTime(record: r, cal: cal, utcTZ: utcTZ, localTZ: localTZ) else {
                    continue
                }

                let call = r["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let country = canonicalCountryName(r["COUNTRY"]).trimmingCharacters(in: .whitespacesAndNewlines)
                let flag = country.isEmpty ? "🌐" : countryToFlag(country)
                let band = ConfirmationOpportunityIndex.normalizedBand(for: r)
                let mode = r["SUBMODE"].isEmpty ? r["MODE"] : r["SUBMODE"]

                let item = ParsedLocalQSO(
                    id: r.id,
                    record: r,
                    callsign: call,
                    country: country,
                    flag: flag,
                    band: band,
                    mode: mode,
                    rstSent: r["RST_SENT"],
                    rstRcvd: r["RST_RCVD"],
                    localDate: localInfo.date,
                    localHour: localInfo.hour,
                    localWeekday: localInfo.weekday,
                    isConfirmed: r.isConfirmed,
                    localTimeStr: localTimeFmt.string(from: localInfo.date),
                    localDateStr: localDateFmt.string(from: localInfo.date)
                )
                results.append(item)
            }

            DispatchQueue.main.async {
                self.parsedQSOs = results
                self.isCalculating = false
            }
        }
    }

    // Convert (QSO_DATE, TIME_ON) from UTC to local Date, Hour, and Weekday
    private static func extractLocalTime(
        record: QSORecordModel,
        cal: Calendar,
        utcTZ: TimeZone,
        localTZ: TimeZone
    ) -> (date: Date, hour: Int, weekday: Int)? {
        let rawDate = record["QSO_DATE"].filter(\.isNumber)
        guard rawDate.count >= 8 else { return nil }

        let rawTime = (record["TIME_ON"].isEmpty ? record["TIME_OFF"] : record["TIME_ON"]).filter(\.isNumber)

        let year = Int(rawDate.prefix(4)) ?? 2000
        let month = Int(rawDate.dropFirst(4).prefix(2)) ?? 1
        let day = Int(rawDate.dropFirst(6).prefix(2)) ?? 1

        let hour = rawTime.count >= 2 ? (Int(rawTime.prefix(2)) ?? 0) : 0
        let minute = rawTime.count >= 4 ? (Int(rawTime.dropFirst(2).prefix(2)) ?? 0) : 0
        let second = rawTime.count >= 6 ? (Int(rawTime.dropFirst(4).prefix(2)) ?? 0) : 0

        var utcComps = DateComponents()
        utcComps.calendar = cal
        utcComps.timeZone = utcTZ
        utcComps.year = year
        utcComps.month = month
        utcComps.day = day
        utcComps.hour = hour
        utcComps.minute = minute
        utcComps.second = second

        guard let utcDate = cal.date(from: utcComps) else { return nil }

        // Local Calendar conversion
        let localComps = cal.dateComponents(in: localTZ, from: utcDate)
        guard let lHour = localComps.hour, let lWeekday = localComps.weekday else { return nil }

        return (date: utcDate, hour: lHour, weekday: lWeekday)
    }
}

// MARK: - Supporting Subviews & Models

// Single Heatmap Grid Cell
private struct HeatmapCell: View {
    let count: Int
    let maxCount: Int
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat

    private var intensity: Double {
        guard maxCount > 0, count > 0 else { return 0.0 }
        return min(1.0, max(0.12, Double(count) / Double(maxCount)))
    }

    private var cellColor: Color {
        guard count > 0 else {
            return Color(NSColor.controlBackgroundColor).opacity(0.2)
        }

        let ratio = intensity
        if ratio < 0.25 {
            return Color.blue.opacity(0.35 + ratio * 0.5)
        } else if ratio < 0.55 {
            return Color.teal.opacity(0.5 + ratio * 0.6)
        } else if ratio < 0.80 {
            return Color.orange.opacity(0.65 + ratio * 0.4)
        } else {
            return Color.red.opacity(0.85 + ratio * 0.15)
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(cellColor)

            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white, lineWidth: 2)
                    .shadow(color: .white.opacity(0.8), radius: 3)
            }

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: count > 99 ? 8 : 9, weight: .bold, design: .monospaced))
                    .foregroundColor(intensity > 0.45 ? .white : .primary)
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
    }
}

// Metric Insight Card for Top Bar
private struct InsightCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }
}

// Country Ranking Data Item
private struct CountryRankingItem: Identifiable {
    let id: String
    let country: String
    let flag: String
    let totalQSOs: Int
    let confirmedQSOs: Int
}

// Row in Inspector Top Countries List
private struct CountryRankingRow: View {
    let ranking: CountryRankingItem
    let totalInSlot: Int

    private var percentage: Double {
        totalInSlot > 0 ? (Double(ranking.totalQSOs) / Double(totalInSlot)) : 0.0
    }

    private var confirmRate: Double {
        ranking.totalQSOs > 0 ? (Double(ranking.confirmedQSOs) / Double(ranking.totalQSOs)) : 0.0
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text(ranking.flag)
                    .font(.system(size: 13))

                Text(ranking.country)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Text("\(ranking.totalQSOs)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))

                Text("(\(ranking.confirmedQSOs) conf)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            // Ratio Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(2, geo.size.width * CGFloat(percentage)))
                }
            }
            .frame(height: 3)
        }
        .padding(.vertical, 2)
    }
}
