//
//  CompetitorTrackingEngine.swift
//  YAAM
//
//  Competitor & Rival Activity Tracking Engine for Confirmed QSO Progress & Growth Analysis.
//  Enables multi-station comparative growth/decline charts, velocity benchmarking, and overtake forecasting.
//

import Combine
import Foundation
import SwiftUI

// MARK: - Competitor Station Model

public struct CompetitorStation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var callsign: String
    public var name: String
    public var country: String
    public var countryFlag: String
    public var confirmedCount: Int
    public var monthlyGrowthRate: Double
    public var colorHex: String
    public var isEnabled: Bool
    public var notes: String

    public init(
        id: UUID = UUID(),
        callsign: String,
        name: String = "",
        country: String = "",
        countryFlag: String = "",
        confirmedCount: Int,
        monthlyGrowthRate: Double = 25.0,
        colorHex: String = "#FF9500",
        isEnabled: Bool = true,
        notes: String = ""
    ) {
        self.id = id
        self.callsign = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.name = name
        self.country = country.isEmpty ? "Unknown" : country
        self.countryFlag = countryFlag.isEmpty ? (flagFromCallsignPrefix(callsign) ?? "🌐") : countryFlag
        self.confirmedCount = confirmedCount
        self.monthlyGrowthRate = monthlyGrowthRate
        self.colorHex = colorHex
        self.isEnabled = isEnabled
        self.notes = notes
    }

    public var displayColor: Color {
        Color(hex: colorHex) ?? .orange
    }

    /// Trend activity classification based on monthly rate
    public var activityTrend: CompetitorActivityTrend {
        if monthlyGrowthRate >= 80 { return .surging }
        if monthlyGrowthRate >= 35 { return .growing }
        if monthlyGrowthRate >= 10 { return .steady }
        return .cooling
    }
}

public enum CompetitorActivityTrend: String, CaseIterable, Sendable {
    case surging = "Surging"
    case growing = "Active Growth"
    case steady = "Steady Pace"
    case cooling = "Cooling / Plateau"

    public var icon: String {
        switch self {
        case .surging: return "arrow.up.forward.circle.fill"
        case .growing: return "arrow.up.right"
        case .steady: return "arrow.right"
        case .cooling: return "arrow.down.right"
        }
    }

    public var color: Color {
        switch self {
        case .surging: return .purple
        case .growing: return .green
        case .steady: return .blue
        case .cooling: return .orange
        }
    }
}

// MARK: - Multi-Series Timeline Point

public struct MultiSeriesTimelinePoint: Identifiable, Equatable, Sendable {
    public var id: String { "\(callsign)_\(monthLabel)" }
    public let callsign: String
    public let monthLabel: String
    public let cumulativeCount: Int
    public let isForecast: Bool
    public let isOwner: Bool
    public let colorHex: String
}

// MARK: - Competitor Store & Analytics Engine

@MainActor
public final class CompetitorTrackingStore: ObservableObject {
    public static let shared = CompetitorTrackingStore()

    private let storageKey = "yaam_competitor_stations_v1"

    @Published public var competitors: [CompetitorStation] = []

    public init() {
        loadCompetitors()
        if competitors.isEmpty {
            seedDefaultRivals()
        }
    }

    public func addCompetitor(
        callsign: String,
        name: String = "",
        confirmedCount: Int,
        monthlyRate: Double = 30.0,
        colorHex: String = "#FF9500"
    ) {
        let cleanCall = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanCall.isEmpty else { return }

        // Remove duplicate if already exists
        competitors.removeAll { $0.callsign == cleanCall }

        let flag = flagFromCallsignPrefix(cleanCall) ?? "🌐"
        let rival = CompetitorStation(
            callsign: cleanCall,
            name: name,
            countryFlag: flag,
            confirmedCount: max(0, confirmedCount),
            monthlyGrowthRate: max(1.0, monthlyRate),
            colorHex: colorHex,
            isEnabled: true
        )
        competitors.append(rival)
        saveCompetitors()
    }

    public func updateCompetitor(_ competitor: CompetitorStation) {
        if let idx = competitors.firstIndex(where: { $0.id == competitor.id }) {
            competitors[idx] = competitor
            saveCompetitors()
        }
    }

    public func deleteCompetitor(id: UUID) {
        competitors.removeAll { $0.id == id }
        saveCompetitors()
    }

    public func toggleVisibility(id: UUID) {
        if let idx = competitors.firstIndex(where: { $0.id == id }) {
            competitors[idx].isEnabled.toggle()
            saveCompetitors()
        }
    }

    public func seedDefaultRivals() {
        let presets: [(call: String, name: String, confirmed: Int, rate: Double, color: String)] = [
            ("EP2LMA", "Mohsen (Tehran DX)", 1150, 42.0, "#FF9500"),
            ("A61A", "Emirates Contest Club", 1850, 65.0, "#AF52DE"),
            ("HZ1FI", "Faisal (Riyadh)", 920, 28.0, "#FF2D55"),
            ("DL7ON", "Wolfgang (Berlin)", 1420, 35.0, "#30B0C7")
        ]

        competitors = presets.map { p in
            CompetitorStation(
                callsign: p.call,
                name: p.name,
                confirmedCount: p.confirmed,
                monthlyGrowthRate: p.rate,
                colorHex: p.color
            )
        }
        saveCompetitors()
    }

    private func saveCompetitors() {
        if let data = try? JSONEncoder().encode(competitors) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadCompetitors() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let list = try? JSONDecoder().decode([CompetitorStation].self, from: data) {
            competitors = list
        }
    }

    // MARK: - Multi-Series Timeline Generator

    /// Computes aligned chronological progress points for User + all active Competitors
    func generateMultiSeries(
        ownerCallsign: String,
        ownerPoints: [ConfirmedProgressPoint],
        ownerCurrentConfirmed: Int,
        ownerMonthlyRate: Double
    ) -> [String: [MultiSeriesTimelinePoint]] {
        var seriesDict: [String: [MultiSeriesTimelinePoint]] = [:]

        // 1. User Series
        let ownerSeries = ownerPoints.map { p in
            MultiSeriesTimelinePoint(
                callsign: ownerCallsign,
                monthLabel: p.label,
                cumulativeCount: p.cumulativeCount,
                isForecast: p.isForecast,
                isOwner: true,
                colorHex: "#34C759"
            )
        }
        seriesDict[ownerCallsign] = ownerSeries

        // Base month labels from user chart (history + forecasts)
        let monthLabels = ownerPoints.map(\.label)
        guard !monthLabels.isEmpty else { return seriesDict }

        let historicalCount = ownerPoints.filter { !$0.isForecast }.count
        let forecastCount = ownerPoints.filter { $0.isForecast }.count

        // 2. Competitor Series
        for comp in competitors where comp.isEnabled {
            var compPoints: [MultiSeriesTimelinePoint] = []
            let current = Double(comp.confirmedCount)
            let rate = comp.monthlyGrowthRate

            // Back-project historical points
            for (idx, label) in monthLabels.prefix(historicalCount).enumerated() {
                let monthsAgo = Double(historicalCount - 1 - idx)
                // Linear / progressive curve backwards
                let historicalCountVal = max(10, Int((current - (monthsAgo * rate)).rounded()))
                compPoints.append(MultiSeriesTimelinePoint(
                    callsign: comp.callsign,
                    monthLabel: label,
                    cumulativeCount: historicalCountVal,
                    isForecast: false,
                    isOwner: false,
                    colorHex: comp.colorHex
                ))
            }

            // Forward-project forecast points
            let forecastMonths = [3, 6, 12]
            for (idx, label) in monthLabels.suffix(forecastCount).enumerated() {
                let m = idx < forecastMonths.count ? forecastMonths[idx] : (idx + 1) * 3
                let projectedVal = Int((current + (Double(m) * rate)).rounded())
                compPoints.append(MultiSeriesTimelinePoint(
                    callsign: comp.callsign,
                    monthLabel: label,
                    cumulativeCount: projectedVal,
                    isForecast: true,
                    isOwner: false,
                    colorHex: comp.colorHex
                ))
            }

            seriesDict[comp.callsign] = compPoints
        }

        return seriesDict
    }
}

// MARK: - Color Hex Helper

extension Color {
    public init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r, g, b, a: Double
        if hexSanitized.count == 6 {
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
            a = 1.0
        } else if hexSanitized.count == 8 {
            r = Double((rgb & 0xFF000000) >> 24) / 255.0
            g = Double((rgb & 0x00FF0000) >> 16) / 255.0
            b = Double((rgb & 0x0000FF00) >> 8) / 255.0
            a = Double(rgb & 0x000000FF) / 255.0
        } else {
            return nil
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
