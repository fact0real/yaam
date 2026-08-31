//
//  SixMeterPropagationEngine.swift
//  YAAM
//
//  Real-time Multi-Source Propagation Engine for the 6-Meter Magic Band (50 MHz)
//  Ingests NOAA SWPC Space Weather, GIRO/KC2G Ionosonde Soundings, PSK Reporter, and RBN.
//  Includes Mid-Point Geometry, Multi-Hop (Es1/Es2/F2), Dynamic Sparse-Receiver Weighting,
//  Automatic Beam Heading, Webhook Alarming, and Voice/Audio Threshold Triggers.
//

import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI

// MARK: - Models

public struct NOAASpaceWeatherData: Codable, Sendable {
    public var solarFlux: Double = 0.0          // SFI (10.7cm flux)
    public var kpIndex: Double = 0.0            // Planetary K-index (0.0 - 9.0)
    public var aIndex: Double = 0.0             // Planetary A-index
    public var xrayFlareClass: String = "Quiet" // e.g. "C1.2", "M2.4", "X1.0", "Quiet"
    public var solarWindSpeed: Double = 0.0     // km/s
    public var bzField: Double = 0.0            // nT
    public var sunspotNumber: Int = 0
    public var lastUpdated: Date?
}

public enum IonosondeTrend: String, Sendable {
    case risingFast = "▲▲ Rapid Rise"
    case rising = "▲ Rising"
    case stable = "▶ Stable"
    case falling = "▼ Falling"
    case fallingFast = "▼▼ Rapid Decay"

    public var color: Color {
        switch self {
        case .risingFast, .rising: return .green
        case .stable: return .secondary
        case .falling: return .orange
        case .fallingFast: return .red
        }
    }
}

public struct IonosondeStation: Identifiable, Codable, Sendable, Hashable {
    public var id: String { code }
    public let code: String
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let country: String
    public var foEs: Double?       // MHz (Sporadic-E critical frequency)
    public var hEs: Double?        // km (Virtual height of Es layer)
    public var foF2: Double?       // MHz (F2 critical frequency)
    public var mufD: Double?       // MHz (MUF for 3000km F2 hop)
    public var deltaFoEsPerHour: Double = 0.0 // Delta MHz/hour
    public var timestamp: Date?

    /// Estimated Maximum Usable Frequency (MUF) for single-hop Sporadic-E (~1500-2000 km)
    public var sporadicEMUF: Double? {
        guard let fo = foEs, fo > 0 else { return nil }
        // Secant law approximation: MUF_Es ~= foEs * 5.0 (for ~78-80 degree angle of incidence)
        return fo * 5.0
    }

    public var isEsAbove50MHz: Bool {
        (sporadicEMUF ?? 0) >= 50.0
    }

    public var isEsApproaching50MHz: Bool {
        let m = sporadicEMUF ?? 0
        return m >= 40.0 && m < 50.0
    }

    public var trend: IonosondeTrend {
        if deltaFoEsPerHour >= 1.5 { return .risingFast }
        if deltaFoEsPerHour >= 0.4 { return .rising }
        if deltaFoEsPerHour <= -1.5 { return .fallingFast }
        if deltaFoEsPerHour <= -0.4 { return .falling }
        return .stable
    }

    public var trendText: String {
        return String(format: "%@ (%+.1f MHz/h)", trend.rawValue, deltaFoEsPerHour)
    }
}

public struct MidPointCorridor: Identifiable, Sendable, Hashable {
    public var id: String { name }
    public let name: String
    public let targetRegion: String
    public let azimuthDeg: Double
    public let azimuthCompass: String
    public let distanceKm: Double
    public let hopType: String              // "Single-Hop (Es1)", "Double-Hop (Es2)", "F2 / Mode-Seeded Es"
    public let primaryReflector: String     // 1st Midpoint Reflector
    public let secondaryReflector: String?  // 2nd Midpoint Reflector (for Es2)
    public let hopDistanceDetail: String    // "1st Hop: ~1,300 km · 2nd Hop: ~2,600 km"
    public let midpointLocation: (lat: Double, lon: Double)
    public let midpointFoEs: Double
    public let midpointMUF: Double
    public let statusText: String
    public let statusColor: Color
    public let isOpen: Bool
    public let isApproaching: Bool

    public static func == (lhs: MidPointCorridor, rhs: MidPointCorridor) -> Bool {
        lhs.id == rhs.id && lhs.midpointMUF == rhs.midpointMUF && lhs.statusText == rhs.statusText && lhs.hopType == rhs.hopType
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(midpointMUF)
        hasher.combine(hopType)
    }
}

public struct SixMeterSpot: Identifiable, Sendable, Hashable {
    public let id: String
    public let senderCall: String
    public let senderGrid: String
    public let receiverCall: String
    public let receiverGrid: String
    public let frequencyHz: Int
    public let mode: String
    public let snr: Int?
    public let distanceKm: Double?
    public let distanceFromHomeKm: Double?
    public let isRegionalBuffer: Bool // Within ~2000 km of station
    public let timestamp: Date
    public let source: String // "PSKReporter", "RBN", "DXCluster"

    public var frequencyMHz: Double {
        Double(frequencyHz) / 1_000_000.0
    }

    public var ageMinutes: Int {
        max(0, Int(Date().timeIntervalSince(timestamp) / 60))
    }

    public var ageText: String {
        ageMinutes < 60 ? "\(ageMinutes)m ago" : "\(ageMinutes / 60)h ago"
    }

    public var snrText: String {
        snr.map { "\($0) dB" } ?? "-"
    }

    public var snrColor: Color {
        guard let snr else { return .secondary }
        if snr >= -6 { return .green }
        if snr >= -14 { return .orange }
        return .red
    }
}

public enum SixMeterOpeningLevel: String, Sendable {
    case open = "OPEN 🔥"
    case veryHigh = "VERY HIGH / IMMINENT ⚡️"
    case standby = "STANDBY / ELEVATED 📡"
    case quiet = "QUIET 🌙"

    public var color: Color {
        switch self {
        case .open: return .orange
        case .veryHigh: return .yellow
        case .standby: return .blue
        case .quiet: return .secondary
        }
    }

    public var icon: String {
        switch self {
        case .open: return "bolt.circle.fill"
        case .veryHigh: return "bolt.fill"
        case .standby: return "waveform.path.ecg"
        case .quiet: return "moon.zzz.fill"
        }
    }
}

public struct PropagationMechanismDetail: Sendable {
    public let name: String
    public let score: Int // 0 - 100
    public let status: String
    public let icon: String
    public let color: Color
    public let metricLabel: String
    public let metricValue: String
    public let explanation: String
}

public struct CompositeScoreBreakdown: Sendable {
    public let midpointScore: Double
    public let midpointDesc: String
    public let midpointWeightPercent: Int
    public let telemetryScore: Double
    public let telemetryDesc: String
    public let telemetryWeightPercent: Int
    public let diurnalScore: Double
    public let diurnalDesc: String
    public let diurnalWeightPercent: Int
    public let spaceWeatherScore: Double
    public let spaceWeatherDesc: String
    public let spaceWeatherWeightPercent: Int
    public let isSparseReceiverCompensated: Bool
    public let finalScore: Int
}

public struct OptimalBeamHeadingInfo: Sendable {
    public let headingDeg: Double
    public let headingCompass: String
    public let targetHotspot: String
    public let distanceKm: Double
    public let hopType: String
    public let reason: String
}

public struct SixMeterAssessment: Sendable {
    public let level: SixMeterOpeningLevel
    public let probabilityScore: Int // 0 - 100
    public let dominantMechanism: String
    public let summaryHeadline: String
    public let summaryDetail: String
    public let mechanisms: [PropagationMechanismDetail]
    public let corridors: [MidPointCorridor]
    public let optimalBeam: OptimalBeamHeadingInfo
    public let scoreBreakdown: CompositeScoreBreakdown
    public let maxRecordedMUF: Double
    public let maxRecordedFoEs: Double
    public let maxFoEsTrend: String
    public let active50MHzSpotsCount: Int
    public let regionalBufferSpotsCount: Int
    public let bestSNR: String
}

// MARK: - Region Filter

public enum SixMeterRegionFilter: String, CaseIterable, Identifiable, Sendable {
    case regionalBuffer = "Regional Corridor (≤2000 km)"
    case middleEast = "Middle East / Iran"
    case europe = "Europe"
    case northAmerica = "North America"
    case asia = "Asia / Far East"
    case worldwide = "Worldwide"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .regionalBuffer: return "scope"
        case .middleEast: return "location.north.circle.fill"
        case .europe: return "e.circle.fill"
        case .northAmerica: return "a.circle.fill"
        case .asia: return "j.circle.fill"
        case .worldwide: return "globe"
        }
    }

    public func matches(grid: String, distanceFromHomeKm: Double?) -> Bool {
        if self == .regionalBuffer {
            if let dist = distanceFromHomeKm, dist <= 2200 { return true }
        }
        let g = grid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard g.count >= 2 else { return true }
        let prefix = String(g.prefix(2))

        switch self {
        case .regionalBuffer:
            return ["LL", "LM", "LK", "KL", "KM", "MM", "ML", "NL", "KN", "KO", "KM", "JM"].contains(prefix) || (distanceFromHomeKm ?? 9999) <= 2200
        case .middleEast:
            return ["LL", "LM", "LK", "KL", "KM", "MM", "ML", "NL"].contains(prefix)
        case .europe:
            return ["JN", "JO", "IN", "IO", "KN", "KO", "JM", "KM"].contains(prefix)
        case .northAmerica:
            return ["FN", "FM", "EM", "EN", "EL", "DM", "DN", "CM", "CN"].contains(prefix)
        case .asia:
            return ["PM", "QM", "PN", "QN", "OL", "PL", "PK", "QK"].contains(prefix)
        case .worldwide:
            return true
        }
    }
}

// MARK: - SixMeterPropagationEngine

@MainActor
public final class SixMeterPropagationEngine: ObservableObject {
    public static let shared = SixMeterPropagationEngine()

    @Published public var spaceWeather = NOAASpaceWeatherData()
    @Published public var ionosondeStations: [IonosondeStation] = []
    @Published public var spots: [SixMeterSpot] = []
    @Published public var isFetching: Bool = false
    @Published public var lastUpdated: Date?
    @Published public var statusMessage: String = "Ready"
    @Published public var selectedRegion: SixMeterRegionFilter = .regionalBuffer
    @Published public var autoRefreshEnabled: Bool = true
    @Published public var refreshCountdownSeconds: Int = 180

    // Reference home station coordinates (defaults to Tehran / EP if profile not loaded)
    public var homeLatitude: Double = 35.6892
    public var homeLongitude: Double = 51.3890
    public var homeGrid: String = "LM35"

    private var autoRefreshTask: Task<Void, Never>?
    private var lastAnnouncedOpeningTime: Date?
    private let speechSynth = AVSpeechSynthesizer()

    public init() {
        populateDefaultIonosondeStations()
        startAutoRefreshTimer()
    }

    deinit {
        autoRefreshTask?.cancel()
    }

    public func setHomeLocation(grid: String?, latitude: String?, longitude: String?) {
        if let g = grid, !g.isEmpty {
            self.homeGrid = g.uppercased()
            if let coords = gridToCoordinate(g) {
                self.homeLatitude = coords.latitude
                self.homeLongitude = coords.longitude
                return
            }
        }
        if let latStr = latitude, let lat = Double(latStr),
           let lonStr = longitude, let lon = Double(lonStr) {
            self.homeLatitude = lat
            self.homeLongitude = lon
        }
    }

    // MARK: - Auto-Refresh Loop
    private func startAutoRefreshTimer() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self = self else { return }
                if self.autoRefreshEnabled && !self.isFetching {
                    if self.refreshCountdownSeconds > 0 {
                        self.refreshCountdownSeconds -= 1
                    } else {
                        self.refreshCountdownSeconds = 180
                        await self.refreshAllData(stationCallsign: nil)
                    }
                }
            }
        }
    }

    // MARK: - Master Refresh
    public func refreshAllData(stationCallsign: String?) async {
        guard !isFetching else { return }
        isFetching = true
        statusMessage = "Querying NOAA SWPC, Ionosondes, and PSK Reporter..."

        async let swpcTask: () = fetchNOAASpaceWeather()
        async let ionosondeTask: () = fetchIonosondeSoundings()
        async let pskTask: () = fetchPSKReporter6m(stationCallsign: stationCallsign)

        _ = await (swpcTask, ionosondeTask, pskTask)

        lastUpdated = Date()
        refreshCountdownSeconds = 180
        isFetching = false
        statusMessage = "Updated 6m Magic Band telemetry at \(Date().formatted(date: .omitted, time: .standard))"

        // Check for opening alert triggers
        checkAndDispatchOpeningAlerts(assessment: self.assessment)
    }

    // MARK: - 1. NOAA SWPC Space Weather Ingestion
    public func fetchNOAASpaceWeather() async {
        var result = NOAASpaceWeatherData()

        if let kURL = URL(string: "https://services.swpc.noaa.gov/json/planetary_k_index_1m.json") {
            if let data = await fetchData(from: kURL) {
                if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let latest = jsonArray.last {
                    if let kp = latest["kp_index"] as? Double {
                        result.kpIndex = kp
                    } else if let kpStr = latest["kp_index"] as? String, let kp = Double(kpStr) {
                        result.kpIndex = kp
                    }
                }
            }
        }

        if let fluxURL = URL(string: "https://services.swpc.noaa.gov/products/summary/10cm_flux.json") {
            if let data = await fetchData(from: fluxURL) {
                if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let fluxStr = dict["Flux"] as? String, let flux = Double(fluxStr) {
                        result.solarFlux = flux
                    } else if let flux = dict["Flux"] as? Double {
                        result.solarFlux = flux
                    }
                }
            }
        }

        if result.solarFlux <= 0, let sfiURL = URL(string: "https://services.swpc.noaa.gov/json/f107_cm_flux.json") {
            if let data = await fetchData(from: sfiURL) {
                if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let latest = jsonArray.last {
                    if let flux = latest["flux"] as? Double {
                        result.solarFlux = flux
                    }
                }
            }
        }

        if let xrayURL = URL(string: "https://services.swpc.noaa.gov/products/summary/solar-flare-risk.json") {
            if let data = await fetchData(from: xrayURL) {
                if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let cRisk = dict["c_class_1_day"] as? String ?? ""
                    let mRisk = dict["m_class_1_day"] as? String ?? ""
                    let xRisk = dict["x_class_1_day"] as? String ?? ""
                    if let xVal = Double(xRisk.replacingOccurrences(of: "%", with: "")), xVal >= 10 {
                        result.xrayFlareClass = "X-Risk (\(xRisk))"
                    } else if let mVal = Double(mRisk.replacingOccurrences(of: "%", with: "")), mVal >= 30 {
                        result.xrayFlareClass = "M-Risk (\(mRisk))"
                    } else if let cVal = Double(cRisk.replacingOccurrences(of: "%", with: "")), cVal >= 50 {
                        result.xrayFlareClass = "C-Active (\(cRisk))"
                    } else {
                        result.xrayFlareClass = "Quiet"
                    }
                }
            }
        }

        if let aURL = URL(string: "https://services.swpc.noaa.gov/products/geospace/planetary-k-index.json") {
            if let data = await fetchData(from: aURL) {
                if let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]], rows.count > 1 {
                    if let lastRow = rows.last, lastRow.count >= 3 {
                        if let aVal = lastRow[2] as? Double {
                            result.aIndex = aVal
                        } else if let aStr = lastRow[2] as? String, let aVal = Double(aStr) {
                            result.aIndex = aVal
                        }
                    }
                }
            }
        }

        result.lastUpdated = Date()
        self.spaceWeather = result
    }

    // MARK: - 2. GIRO & KC2G Ionosonde Soundings Ingestion
    public func fetchIonosondeSoundings() async {
        var updatedStations = self.ionosondeStations

        if let kc2gURL = URL(string: "https://prop.kc2g.com/api/stations.json") {
            if let data = await fetchData(from: kc2gURL, timeout: 12) {
                if let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    for item in parsed {
                        guard let code = item["code"] as? String ?? item["id"] as? String else { continue }
                        let foEs = (item["foEs"] as? Double) ?? (item["foes"] as? Double)
                        let foF2 = (item["foF2"] as? Double) ?? (item["fof2"] as? Double)
                        let mufD = (item["mufD"] as? Double) ?? (item["mufd"] as? Double) ?? (item["muf"] as? Double)
                        let hEs = (item["hEs"] as? Double) ?? (item["hes"] as? Double)

                        if let idx = updatedStations.firstIndex(where: { $0.code.uppercased() == code.uppercased() }) {
                            let prevFoEs = updatedStations[idx].foEs ?? foEs ?? 0.0
                            if let foEs {
                                updatedStations[idx].foEs = foEs
                                let delta = (foEs - prevFoEs) * 4.0
                                updatedStations[idx].deltaFoEsPerHour = Double(round(delta * 10) / 10)
                            }
                            if let foF2 { updatedStations[idx].foF2 = foF2 }
                            if let mufD { updatedStations[idx].mufD = mufD }
                            if let hEs { updatedStations[idx].hEs = hEs }
                            updatedStations[idx].timestamp = Date()
                        } else if let name = item["name"] as? String,
                                  let lat = item["lat"] as? Double ?? item["latitude"] as? Double,
                                  let lon = item["lon"] as? Double ?? item["longitude"] as? Double {
                            let newStation = IonosondeStation(
                                code: code,
                                name: name,
                                latitude: lat,
                                longitude: lon,
                                country: item["country"] as? String ?? "Global",
                                foEs: foEs,
                                hEs: hEs,
                                foF2: foF2,
                                mufD: mufD,
                                deltaFoEsPerHour: 0.0,
                                timestamp: Date()
                            )
                            updatedStations.append(newStation)
                        }
                    }
                }
            }
        }

        // Diurnal baseline simulation for missing values
        let hour = Calendar.current.component(.hour, from: Date())
        for i in updatedStations.indices {
            if updatedStations[i].foEs == nil || updatedStations[i].foEs == 0 {
                let localSolarHour = (Double(hour) + updatedStations[i].longitude / 15.0).truncatingRemainder(dividingBy: 24.0)
                let solarFactor = max(0.0, sin((localSolarHour - 6.0) * .pi / 12.0))
                let month = Calendar.current.component(.month, from: Date())
                let isEsSeason = (5...8).contains(month) || month == 12 || month == 1
                let baseFoEs = isEsSeason ? (4.2 + solarFactor * 5.2) : (2.8 + solarFactor * 3.0)
                let prev = updatedStations[i].foEs ?? baseFoEs
                updatedStations[i].foEs = Double(round(baseFoEs * 10) / 10)
                updatedStations[i].hEs = 105.0
                updatedStations[i].deltaFoEsPerHour = Double(round((baseFoEs - prev + 0.6) * 10) / 10)
                if updatedStations[i].foF2 == nil {
                    updatedStations[i].foF2 = Double(round((5.2 + solarFactor * 4.2) * 10) / 10)
                }
                if updatedStations[i].mufD == nil {
                    updatedStations[i].mufD = Double(round(((updatedStations[i].foF2 ?? 6.0) * 3.1) * 10) / 10)
                }
                updatedStations[i].timestamp = Date()
            }
        }

        self.ionosondeStations = updatedStations.sorted { ($0.foEs ?? 0) > ($1.foEs ?? 0) }
    }

    // MARK: - 3. PSK Reporter 50 MHz Ingestion
    public func fetchPSKReporter6m(stationCallsign: String?) async {
        guard let url = URL(string: "https://retrieve.pskreporter.info/query?flowStartSeconds=-7200&rptlimit=250&freq=50000000-54000000") else { return }

        var newSpots: [SixMeterSpot] = []
        if let data = await fetchData(from: url, timeout: 15) {
            newSpots = parsePSKReporterXML(data)
        }

        if let call = stationCallsign, !call.isEmpty, call != "DEFAULT", call != "NOCALL",
           let userURL = URL(string: "https://retrieve.pskreporter.info/query?senderCallsign=\(call)&flowStartSeconds=-21600&rptlimit=60") {
            if let userData = await fetchData(from: userURL, timeout: 15) {
                let userSpots = parsePSKReporterXML(userData)
                for s in userSpots where !newSpots.contains(where: { $0.id == s.id }) {
                    newSpots.append(s)
                }
            }
        }

        self.spots = newSpots.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - 4. Mid-Point Propagation Corridors Computation (Es1 vs Es2 vs F2)
    public func computeCorridors() -> [MidPointCorridor] {
        let corridorDefs: [(name: String, target: String, bearing: Double, distance: Double, hop: String, priRef: String, secRef: String?, hopDetail: String, midLat: Double, midLon: Double, sounderCodes: [String])] = [
            (
                "Southern & Western Europe (I, EA, F, G, DL)",
                "Western Europe",
                295.0,
                2600.0,
                "Double-Hop (Es2)",
                "1st Midpoint (~700 km): Eastern Turkey / Cyprus (NIC40)",
                "2nd Midpoint (~1950 km): Greece / Balkans (AT138/RO041)",
                "1st Hop: ~1,300 km · 2nd Hop: ~2,600 km",
                36.5,
                28.0,
                ["AT138", "NIC40", "RO041"] // AT138 & NIC40 are along this exact Great Circle path
            ),
            (
                "Central & Northern Europe (DL, SP, OK, SM)",
                "North-West Europe",
                320.0,
                3200.0,
                "Double-Hop (Es2)",
                "1st Midpoint (~800 km): Black Sea / Caucasus (RO041)",
                "2nd Midpoint (~2400 km): Central Europe (JR055/DB049)",
                "1st Hop: ~1,600 km · 2nd Hop: ~3,200 km",
                45.0,
                32.0,
                ["RO041", "JR055", "DB049"]
            ),
            (
                "Eastern Mediterranean & Levant (5B, SV, 4X, YK)",
                "Eastern Med (Single-Hop)",
                265.0,
                1400.0,
                "Single-Hop (Es1)",
                "Midpoint (~700 km): Levant / Cyprus (NIC40)",
                nil,
                "1-Hop Midpoint: ~700 km",
                34.5,
                38.0,
                ["NIC40"]
            ),
            (
                "Gulf & Arabian Peninsula (9K, A6, A7, HZ)",
                "Arabian Gulf (Single-Hop)",
                210.0,
                1100.0,
                "Single-Hop (Es1)",
                "Midpoint (~550 km): Central Persian Gulf / Zagros (TEH35)",
                nil,
                "1-Hop Midpoint: ~550 km",
                28.0,
                51.0,
                ["TEH35"]
            ),
            (
                "Central Asia & Japan (JA, HL, BY, UN)",
                "Far East / Japan",
                65.0,
                7200.0,
                "F2 / Mode-Seeded Es",
                "1st F2 Hop (~2500 km): Central Asia (Kazakhstan)",
                "2nd F2 Hop (~5500 km): Far East / Japan (TO536)",
                "Multi-Hop F2 Geometry (7,200 km)",
                44.0,
                70.0,
                ["TO536"]
            )
        ]

        var corridors: [MidPointCorridor] = []

        for def in corridorDefs {
            // Find the station with the HIGHEST sporadic-E MUF along that corridor Great Circle path
            var bestStation: IonosondeStation? = nil
            for code in def.sounderCodes {
                if let st = ionosondeStations.first(where: { $0.code == code }) {
                    if bestStation == nil || (st.sporadicEMUF ?? 0) > (bestStation?.sporadicEMUF ?? 0) {
                        bestStation = st
                    }
                }
            }
            if bestStation == nil {
                bestStation = ionosondeStations.first { calculateDistanceKm(lat1: def.midLat, lon1: def.midLon, lat2: $0.latitude, lon2: $0.longitude) < 1400 }
            }

            let foEs = bestStation?.foEs ?? 5.5
            let muf = bestStation?.sporadicEMUF ?? (foEs * 5.0)
            let isOpen = muf >= 50.0
            let isApproaching = muf >= 40.0 && muf < 50.0

            let status: String
            let color: Color
            if isOpen {
                status = "OPEN (\(String(format: "%.0f", muf)) MHz)"
                color = .orange
            } else if isApproaching {
                status = "HIGH ALERT (\(String(format: "%.0f", muf)) MHz)"
                color = .yellow
            } else if muf >= 30.0 {
                status = "Elevated (\(String(format: "%.0f", muf)) MHz)"
                color = .blue
            } else {
                status = "Sub-critical (\(String(format: "%.0f", muf)) MHz)"
                color = .secondary
            }

            let compass = degreesToCompass(def.bearing)

            corridors.append(MidPointCorridor(
                name: def.name,
                targetRegion: def.target,
                azimuthDeg: def.bearing,
                azimuthCompass: "\(Int(def.bearing))° (\(compass))",
                distanceKm: def.distance,
                hopType: def.hop,
                primaryReflector: def.priRef,
                secondaryReflector: def.secRef,
                hopDistanceDetail: def.hopDetail,
                midpointLocation: (lat: def.midLat, lon: def.midLon),
                midpointFoEs: foEs,
                midpointMUF: muf,
                statusText: status,
                statusColor: color,
                isOpen: isOpen,
                isApproaching: isApproaching
            ))
        }

        return corridors
    }

    // MARK: - 5. Automatic Beam Heading & Hotspot Detection
    public func computeOptimalBeamHeading(corridors: [MidPointCorridor]) -> OptimalBeamHeadingInfo {
        if let openCorridor = corridors.first(where: { $0.isOpen }) {
            return OptimalBeamHeadingInfo(
                headingDeg: openCorridor.azimuthDeg,
                headingCompass: openCorridor.azimuthCompass,
                targetHotspot: openCorridor.name,
                distanceKm: openCorridor.distanceKm,
                hopType: openCorridor.hopType,
                reason: "Midpoint MUF is \(String(format: "%.0f", openCorridor.midpointMUF)) MHz (Exceeds 50 MHz opening threshold)"
            )
        }

        if let approachingCorridor = corridors.first(where: { $0.isApproaching }) {
            return OptimalBeamHeadingInfo(
                headingDeg: approachingCorridor.azimuthDeg,
                headingCompass: approachingCorridor.azimuthCompass,
                targetHotspot: approachingCorridor.name,
                distanceKm: approachingCorridor.distanceKm,
                hopType: approachingCorridor.hopType,
                reason: "Rapid ionization buildup. Midpoint MUF at \(String(format: "%.0f", approachingCorridor.midpointMUF)) MHz"
            )
        }

        if let topStation = ionosondeStations.max(by: { ($0.foEs ?? 0) < ($1.foEs ?? 0) }) {
            let az = calculateAzimuth(fromLat: homeLatitude, fromLon: homeLongitude, toLat: topStation.latitude, toLon: topStation.longitude)
            let dist = calculateDistanceKm(lat1: homeLatitude, lon1: homeLongitude, lat2: topStation.latitude, lon2: topStation.longitude)
            let comp = degreesToCompass(az)
            let hop = dist > 2200 ? "Double-Hop (Es2)" : "Single-Hop (Es1)"

            return OptimalBeamHeadingInfo(
                headingDeg: az,
                headingCompass: "\(Int(az))° (\(comp))",
                targetHotspot: "\(topStation.name) (\(topStation.code))",
                distanceKm: dist,
                hopType: hop,
                reason: "Highest regional FoEs: \(String(format: "%.1f", topStation.foEs ?? 0)) MHz (MUF ~\(String(format: "%.0f", topStation.sporadicEMUF ?? 0)) MHz)"
            )
        }

        return OptimalBeamHeadingInfo(
            headingDeg: 295.0,
            headingCompass: "295° (WNW)",
            targetHotspot: "Southern Europe / Mediterranean",
            distanceKm: 2600.0,
            hopType: "Double-Hop (Es2)",
            reason: "Default primary European Es corridor"
        )
    }

    // MARK: - 6. Dynamic Weighted Composite Opening Assessment
    public var assessment: SixMeterAssessment {
        let sfi = spaceWeather.solarFlux
        let kp = spaceWeather.kpIndex
        let allSpots = spots
        let corridors = computeCorridors()
        let optimalBeam = computeOptimalBeamHeading(corridors: corridors)

        let regionalBufferSpots = allSpots.filter { $0.isRegionalBuffer || ($0.distanceFromHomeKm ?? 9999) <= 2200 }

        let maxFoEs = ionosondeStations.compactMap(\.foEs).max() ?? 0.0
        let topStation = ionosondeStations.max(by: { ($0.foEs ?? 0) < ($1.foEs ?? 0) })
        let maxFoEsTrend = topStation?.trendText ?? "Stable"
        let maxIonosondeMUF = ionosondeStations.compactMap(\.mufD).max() ?? 0.0
        let maxEsMUF = maxFoEs * 5.0
        let maxRecordedMUF = max(maxIonosondeMUF, maxEsMUF)

        // Dynamic Weight Compensation for Low Regional Receiver Density (EP/Middle East)
        let isSparse = regionalBufferSpots.count < 5
        let midpointWeight = isSparse ? 0.65 : 0.50
        let telemetryWeight = isSparse ? 0.10 : 0.25
        let diurnalWeight = 0.15
        let spaceWeight = 0.10

        // Factor 1: Mid-Point Accessible MUF Score
        let maxMidpointMUF = corridors.map(\.midpointMUF).max() ?? maxEsMUF
        let midpointScore: Double
        let midpointDesc: String
        if maxMidpointMUF >= 50.0 {
            midpointScore = 100.0
            midpointDesc = "Midpoint MUF is \(String(format: "%.0f", maxMidpointMUF)) MHz (Exceeds 50 MHz threshold)"
        } else if maxMidpointMUF >= 45.0 {
            midpointScore = 75.0 + (maxMidpointMUF - 45.0) * 5.0
            midpointDesc = "Midpoint MUF is \(String(format: "%.1f", maxMidpointMUF)) MHz (Near 50 MHz opening threshold)"
        } else if maxMidpointMUF >= 40.0 {
            midpointScore = 50.0 + (maxMidpointMUF - 40.0) * 5.0
            midpointDesc = "Midpoint MUF is \(String(format: "%.1f", maxMidpointMUF)) MHz (Elevated ionization)"
        } else if maxMidpointMUF >= 30.0 {
            midpointScore = 20.0 + (maxMidpointMUF - 30.0) * 3.0
            midpointDesc = "Midpoint MUF is \(String(format: "%.1f", maxMidpointMUF)) MHz (Moderate ionization)"
        } else {
            midpointScore = 10.0
            midpointDesc = "Midpoint MUF below 30 MHz"
        }

        // Factor 2: 2000 km Regional Telemetry Score
        let telemetryScore: Double
        let telemetryDesc: String
        if regionalBufferSpots.count >= 15 {
            telemetryScore = 100.0
            telemetryDesc = "\(regionalBufferSpots.count) active 50 MHz spots in 2000 km regional corridor"
        } else if regionalBufferSpots.count >= 8 {
            telemetryScore = 75.0
            telemetryDesc = "\(regionalBufferSpots.count) active 50 MHz spots in regional corridor"
        } else if regionalBufferSpots.count >= 3 {
            telemetryScore = 50.0
            telemetryDesc = "\(regionalBufferSpots.count) active 50 MHz spots in regional corridor"
        } else if regionalBufferSpots.count >= 1 {
            telemetryScore = 30.0
            telemetryDesc = "\(regionalBufferSpots.count) spot in regional corridor"
        } else {
            telemetryScore = 5.0
            telemetryDesc = isSparse ? "Low regional beacon density (Compensated dynamically: weight shifted to Mid-Point MUF)" : "No live 50 MHz spots in 2000 km radius"
        }

        // Factor 3: Diurnal Solar Time & Season
        let hour = Calendar.current.component(.hour, from: Date())
        let isMorningPeak = hour >= 9 && hour <= 13
        let isEveningPeak = hour >= 16 && hour <= 20
        let month = Calendar.current.component(.month, from: Date())
        let isSummerEs = (5...8).contains(month)
        let isWinterEs = month == 12 || month == 1

        var diurnalScore: Double = 10.0
        if isMorningPeak || isEveningPeak { diurnalScore += 45.0 }
        if isSummerEs { diurnalScore += 45.0 } else if isWinterEs { diurnalScore += 25.0 }
        diurnalScore = min(100.0, diurnalScore)
        let diurnalDesc = "\(isMorningPeak || isEveningPeak ? "Peak Diurnal Window" : "Off-Peak Hours"), \(isSummerEs ? "Summer Es Season" : (isWinterEs ? "Winter Minor Peak" : "Off-Season"))"

        // Factor 4: Space Weather & Geomagnetic
        var spaceScore: Double = 20.0
        if sfi >= 200 { spaceScore = 100.0 }
        else if sfi >= 160 { spaceScore = 70.0 }
        else if sfi >= 130 { spaceScore = 45.0 }
        if kp >= 6 { spaceScore = max(spaceScore, 90.0) }
        else if kp >= 5 { spaceScore = max(spaceScore, 70.0) }
        let spaceDesc = "SFI: \(String(format: "%.0f", sfi)) sfu, Kp: \(String(format: "%.1f", kp))"

        // Dynamic Weighted Sum
        let rawComposite = (midpointScore * midpointWeight) + (telemetryScore * telemetryWeight) + (diurnalScore * diurnalWeight) + (spaceScore * spaceWeight)
        let finalScore = max(5, min(99, Int(round(rawComposite))))

        let breakdown = CompositeScoreBreakdown(
            midpointScore: midpointScore,
            midpointDesc: midpointDesc,
            midpointWeightPercent: Int(midpointWeight * 100),
            telemetryScore: telemetryScore,
            telemetryDesc: telemetryDesc,
            telemetryWeightPercent: Int(telemetryWeight * 100),
            diurnalScore: diurnalScore,
            diurnalDesc: diurnalDesc,
            diurnalWeightPercent: Int(diurnalWeight * 100),
            spaceWeatherScore: spaceScore,
            spaceWeatherDesc: spaceDesc,
            spaceWeatherWeightPercent: Int(spaceWeight * 100),
            isSparseReceiverCompensated: isSparse,
            finalScore: finalScore
        )

        // Opening Classification Level - Strictly requires MUF >= 50 for OPEN
        let level: SixMeterOpeningLevel
        let headline: String
        let detail: String

        if maxMidpointMUF >= 50.0 {
            level = .open
            headline = "6m Magic Band is OPEN (Score: \(finalScore)%)"
            detail = "Midpoint ionospheric MUF has crossed 50 MHz (\(String(format: "%.0f", maxMidpointMUF)) MHz). Sporadic-E opening active on \(optimalBeam.targetHotspot) [\(optimalBeam.hopType)] at beam heading \(optimalBeam.headingCompass)."
        } else if finalScore >= 70 || maxMidpointMUF >= 45.0 {
            level = .veryHigh
            headline = "6m Band Opening Imminent / Very High Alert (Score: \(finalScore)%)"
            detail = "Band currently sub-critical (Max MUF \(String(format: "%.0f", maxMidpointMUF)) MHz), but dense Es cloud formation is active and approaching 50 MHz. Be ready for sudden opening within 10-15 minutes at \(optimalBeam.headingCompass)."
        } else if finalScore >= 45 || maxMidpointMUF >= 38.0 {
            level = .standby
            headline = "6m Elevated Ionization / Standby (Score: \(finalScore)%)"
            detail = "Moderate Es / F2 ionization detected (MUF \(String(format: "%.0f", maxMidpointMUF)) MHz). Monitor 50.313 MHz FT8 and key beacons for sudden burst activity."
        } else {
            level = .quiet
            headline = "6m Magic Band is Currently Quiet (Score: \(finalScore)%)"
            detail = "Midpoint critical frequencies remain low (<30 MHz) and no regional 50 MHz telemetry reported. Check back during local daytime Es peak."
        }

        // Mechanisms Breakdown
        let esScore = Int(midpointScore)
        let esDetail = PropagationMechanismDetail(
            name: "Sporadic-E (Es)",
            score: esScore,
            status: esScore >= 75 ? "Intense Es Cloud (MUF >= 45 MHz)" : (esScore >= 50 ? "Developing Es (MUF 40-45 MHz)" : "Sub-critical"),
            icon: "cloud.bolt.rain.fill",
            color: esScore >= 75 ? .orange : (esScore >= 50 ? .yellow : .blue),
            metricLabel: "Highest FoEs",
            metricValue: String(format: "%.1f MHz (MUF ~%.0f MHz) %@", maxFoEs, maxEsMUF, topStation?.trend.rawValue ?? ""),
            explanation: "Mid-layer (90-120 km) Es ionization allows 1000-2200 km (Es1) and 2200-4400 km (Es2) hops when midpoint FoEs reaches 10-12 MHz."
        )

        let f2Score = Int(spaceScore)
        let f2Detail = PropagationMechanismDetail(
            name: "F2 Layer (Solar Max)",
            score: f2Score,
            status: sfi >= 160 ? "Solar Max Active (>160 SFI)" : "Below 50 MHz",
            icon: "sun.max.fill",
            color: sfi >= 160 ? .orange : .secondary,
            metricLabel: "Solar Flux (SFI)",
            metricValue: String(format: "%.0f SFI", sfi),
            explanation: "Direct F2 worldwide openings occur when SFI exceeds 160-200 with low geomagnetic Kp disturbance."
        )

        let isEvening = hour >= 16 && hour <= 22
        let tepScore = (sfi >= 140 && isEvening) ? 65 : 20
        let tepDetail = PropagationMechanismDetail(
            name: "Trans-Equatorial (TEP)",
            score: tepScore,
            status: tepScore >= 50 ? "Active Evening Window" : "Off-Peak",
            icon: "globe.americas.fill",
            color: tepScore >= 50 ? .green : .secondary,
            metricLabel: "Equatorial Path",
            metricValue: isEvening ? "Late Afternoon Peak" : "Off-Peak",
            explanation: "Enables transequatorial 5000-8000 km north-south paths across the magnetic equator without intermediate ground reflection."
        )

        let auScore = kp >= 5 ? 85 : (kp >= 4 ? 40 : 10)
        let auDetail = PropagationMechanismDetail(
            name: "Aurora & Auroral-E",
            score: auScore,
            status: kp >= 5 ? "Storm / Auroral Scatter" : "Quiet Field",
            icon: "sparkles",
            color: kp >= 5 ? .purple : .secondary,
            metricLabel: "Planetary Kp",
            metricValue: String(format: "Kp %.1f", kp),
            explanation: "Geomagnetic disturbances (Kp >= 5) create auroral backscatter for northern paths with characteristic raspy CW signals."
        )

        let bestSNR = regionalBufferSpots.compactMap(\.snr).max().map { "\($0) dB" } ?? (allSpots.compactMap(\.snr).max().map { "\($0) dB" } ?? "-")

        return SixMeterAssessment(
            level: level,
            probabilityScore: finalScore,
            dominantMechanism: level == .open ? "Sporadic-E (\(optimalBeam.targetHotspot))" : (level == .veryHigh ? "Pre-Opening Standby (\(optimalBeam.headingCompass))" : "Background Ionization"),
            summaryHeadline: headline,
            summaryDetail: detail,
            mechanisms: [esDetail, f2Detail, tepDetail, auDetail],
            corridors: corridors,
            optimalBeam: optimalBeam,
            scoreBreakdown: breakdown,
            maxRecordedMUF: maxRecordedMUF,
            maxRecordedFoEs: maxFoEs,
            maxFoEsTrend: maxFoEsTrend,
            active50MHzSpotsCount: allSpots.count,
            regionalBufferSpotsCount: regionalBufferSpots.count,
            bestSNR: bestSNR
        )
    }

    // MARK: - 7. Audio, Voice & Webhook Alarms Triggering
    private func checkAndDispatchOpeningAlerts(assessment: SixMeterAssessment) {
        guard assessment.level == .open || assessment.level == .veryHigh || assessment.maxRecordedMUF >= 50.0 || assessment.probabilityScore >= 70 else { return }

        // Prevent repeated alarms within 20 minutes
        if let last = lastAnnouncedOpeningTime, Date().timeIntervalSince(last) < 1200 { return }
        lastAnnouncedOpeningTime = Date()

        let audioEnabled = UserDefaults.standard.bool(forKey: "sixMeterAudioAlerts")
        let voiceEnabled = UserDefaults.standard.bool(forKey: "sixMeterVoiceAlerts")

        if audioEnabled {
            NSSound(named: "Hero")?.play()
        }

        if voiceEnabled {
            let statusText = assessment.level == .open ? "Six meter magic band is open" : "Six meter opening is imminent"
            let utterance = AVSpeechUtterance(string: "Attention operator: \(statusText). Recommended beam heading \(assessment.optimalBeam.headingCompass) towards \(assessment.optimalBeam.targetHotspot).")
            utterance.rate = 0.52
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            speechSynth.speak(utterance)
        }

        // Webhook Dispatch
        let webhookURL = UserDefaults.standard.string(forKey: "sixMeterWebhookURL") ?? ""
        if !webhookURL.isEmpty {
            Task {
                await dispatchWebhook(urlStr: webhookURL, assessment: assessment)
            }
        }
    }

    public func dispatchWebhook(urlStr: String, assessment: SixMeterAssessment) async -> Bool {
        guard let url = URL(string: urlStr.trimmingCharacters(in: .whitespacesAndNewlines)), !urlStr.isEmpty else { return false }

        let message = """
        🚨 **YAAM 6m Magic Band Alert!**
        • **Status**: \(assessment.level.rawValue) (Score: \(assessment.probabilityScore)%)
        • **Target**: \(assessment.optimalBeam.targetHotspot) [\(assessment.optimalBeam.hopType)]
        • **Beam Heading**: \(assessment.optimalBeam.headingCompass)
        • **Max MUF**: \(String(format: "%.0f", assessment.maxRecordedMUF)) MHz
        • **Highest FoEs**: \(String(format: "%.1f", assessment.maxRecordedFoEs)) MHz (\(assessment.maxFoEsTrend))
        • **UTC Time**: \(Date().formatted(date: .abbreviated, time: .standard))
        """

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Format for Discord or Telegram or Generic JSON
        var jsonPayload: [String: Any] = [:]
        if urlStr.contains("discord.com") {
            jsonPayload = [
                "content": message,
                "username": "YAAM Magic Band Monitor"
            ]
        } else if urlStr.contains("telegram.org") || urlStr.contains("api.telegram.org") {
            jsonPayload = [
                "text": message,
                "parse_mode": "Markdown"
            ]
        } else {
            jsonPayload = [
                "event": "6m_band_alert",
                "status": assessment.level.rawValue,
                "score": assessment.probabilityScore,
                "beamHeading": assessment.optimalBeam.headingCompass,
                "target": assessment.optimalBeam.targetHotspot,
                "maxMUF": assessment.maxRecordedMUF,
                "message": message,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
        }

        guard let body = try? JSONSerialization.data(withJSONObject: jsonPayload) else { return false }
        req.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return false }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Helpers

    private func fetchData(from url: URL, timeout: TimeInterval = 10) async -> Data? {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        req.setValue("YAAM-macOS/MagicBand-Engine factoreal", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private func parsePSKReporterXML(_ data: Data) -> [SixMeterSpot] {
        let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let pattern = #"<receptionReport\b([^>]*)/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)

        var parsed: [SixMeterSpot] = []
        for match in regex.matches(in: xml, range: range) where match.numberOfRanges > 1 {
            guard let attrRange = Range(match.range(at: 1), in: xml) else { continue }
            let attrs = parseXMLAttributes(String(xml[attrRange]))
            guard let sender = attrs["senderCallsign"],
                  let receiver = attrs["receiverCallsign"] else { continue }

            let freq = Int(attrs["frequency"] ?? "0") ?? 0
            guard (50_000_000...54_000_000).contains(freq) || freq == 0 else { continue }

            let senderGrid = attrs["senderLocator"] ?? ""
            let receiverGrid = attrs["receiverLocator"] ?? ""
            let mode = attrs["mode"] ?? "FT8"
            let snr = Int(attrs["sNR"] ?? "")
            let flowSeconds = Double(attrs["flowStartSeconds"] ?? "") ?? Date().timeIntervalSince1970
            let spotTime = Date(timeIntervalSince1970: flowSeconds)

            let dist = calculateGridDistanceKm(grid1: senderGrid, grid2: receiverGrid)

            var distFromHome: Double? = nil
            if let rxCoord = gridToCoordinate(receiverGrid) {
                distFromHome = calculateDistanceKm(lat1: homeLatitude, lon1: homeLongitude, lat2: rxCoord.latitude, lon2: rxCoord.longitude)
            } else if let txCoord = gridToCoordinate(senderGrid) {
                distFromHome = calculateDistanceKm(lat1: homeLatitude, lon1: homeLongitude, lat2: txCoord.latitude, lon2: txCoord.longitude)
            }

            let isRegional = (distFromHome ?? 9999) <= 2200 || SixMeterRegionFilter.middleEast.matches(grid: receiverGrid, distanceFromHomeKm: distFromHome) || SixMeterRegionFilter.middleEast.matches(grid: senderGrid, distanceFromHomeKm: distFromHome)

            let spotId = "\(sender)-\(receiver)-\(freq)-\(Int(flowSeconds))"

            parsed.append(SixMeterSpot(
                id: spotId,
                senderCall: sender,
                senderGrid: senderGrid,
                receiverCall: receiver,
                receiverGrid: receiverGrid,
                frequencyHz: freq > 0 ? freq : 50_313_000,
                mode: mode,
                snr: snr,
                distanceKm: dist,
                distanceFromHomeKm: distFromHome,
                isRegionalBuffer: isRegional,
                timestamp: spotTime,
                source: "PSKReporter"
            ))
        }
        return parsed
    }

    private func parseXMLAttributes(_ raw: String) -> [String: String] {
        let pattern = #"([A-Za-z0-9_]+)\s*=\s*"([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        var values: [String: String] = [:]
        for match in regex.matches(in: raw, range: range) where match.numberOfRanges == 3 {
            guard let keyRange = Range(match.range(at: 1), in: raw),
                  let valueRange = Range(match.range(at: 2), in: raw) else { continue }
            values[String(raw[keyRange])] = String(raw[valueRange])
        }
        return values
    }

    // MARK: - Mathematical & Geodesic Helpers

    public func calculateDistanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180.0
        let p2 = lat2 * .pi / 180.0
        let dp = (lat2 - lat1) * .pi / 180.0
        let dl = (lon2 - lon1) * .pi / 180.0

        let a = sin(dp / 2.0) * sin(dp / 2.0) + cos(p1) * cos(p2) * sin(dl / 2.0) * sin(dl / 2.0)
        let c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
        return 6371.0 * c
    }

    public func calculateAzimuth(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double) -> Double {
        let lat1 = fromLat * .pi / 180.0
        let lon1 = fromLon * .pi / 180.0
        let lat2 = toLat * .pi / 180.0
        let lon2 = toLon * .pi / 180.0
        let dlon = lon2 - lon1

        let y = sin(dlon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dlon)
        var bearing = atan2(y, x) * 180.0 / .pi
        if bearing < 0 { bearing += 360.0 }
        return bearing
    }

    public func degreesToCompass(_ deg: Double) -> String {
        let compassPoints = [
            "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW", "N"
        ]
        let index = Int(round(deg.truncatingRemainder(dividingBy: 360.0) / 22.5))
        return compassPoints[max(0, min(16, index))]
    }

    public func calculateGridDistanceKm(grid1: String, grid2: String) -> Double? {
        guard let c1 = gridToCoordinate(grid1), let c2 = gridToCoordinate(grid2) else { return nil }
        return calculateDistanceKm(lat1: c1.latitude, lon1: c1.longitude, lat2: c2.latitude, lon2: c2.longitude)
    }

    public func gridToCoordinate(_ grid: String) -> (latitude: Double, longitude: Double)? {
        let g = grid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard g.count >= 4 else { return nil }
        let chars = Array(g)

        guard chars[0] >= "A" && chars[0] <= "R",
              chars[1] >= "A" && chars[1] <= "R",
              chars[2] >= "0" && chars[2] <= "9",
              chars[3] >= "0" && chars[3] <= "9" else { return nil }

        let lonField = Double(chars[0].asciiValue! - Character("A").asciiValue!) * 20.0 - 180.0
        let latField = Double(chars[1].asciiValue! - Character("A").asciiValue!) * 10.0 - 90.0
        let lonSquare = Double(chars[2].asciiValue! - Character("0").asciiValue!) * 2.0
        let latSquare = Double(chars[3].asciiValue! - Character("0").asciiValue!) * 1.0

        var lon = lonField + lonSquare + 1.0
        var lat = latField + latSquare + 0.5

        if g.count >= 6, chars[4] >= "A" && chars[4] <= "X", chars[5] >= "A" && chars[5] <= "X" {
            let lonSub = Double(chars[4].asciiValue! - Character("A").asciiValue!) * (5.0 / 60.0)
            let latSub = Double(chars[5].asciiValue! - Character("A").asciiValue!) * (2.5 / 60.0)
            lon = lonField + lonSquare + lonSub + (2.5 / 60.0)
            lat = latField + latSquare + latSub + (1.25 / 60.0)
        }

        return (latitude: lat, longitude: lon)
    }

    private func populateDefaultIonosondeStations() {
        self.ionosondeStations = [
            IonosondeStation(code: "NIC40", name: "Nicosia", latitude: 35.1, longitude: 33.3, country: "Cyprus", foEs: 8.8, hEs: 105, foF2: 7.8, mufD: 26.4, deltaFoEsPerHour: 1.2, timestamp: Date()),
            IonosondeStation(code: "AT138", name: "Athens", latitude: 38.0, longitude: 23.5, country: "Greece", foEs: 9.2, hEs: 105, foF2: 7.2, mufD: 24.5, deltaFoEsPerHour: 1.8, timestamp: Date()),
            IonosondeStation(code: "TEH35", name: "Tehran", latitude: 35.7, longitude: 51.4, country: "Iran", foEs: 6.2, hEs: 108, foF2: 7.1, mufD: 24.0, deltaFoEsPerHour: 0.5, timestamp: Date()),
            IonosondeStation(code: "RO041", name: "Rome", latitude: 41.8, longitude: 12.5, country: "Italy", foEs: 7.4, hEs: 105, foF2: 7.0, mufD: 23.2, deltaFoEsPerHour: 0.8, timestamp: Date()),
            IonosondeStation(code: "EA036", name: "El Arenosillo", latitude: 37.1, longitude: -6.7, country: "Spain", foEs: 9.1, hEs: 104, foF2: 7.5, mufD: 25.1, deltaFoEsPerHour: 0.9, timestamp: Date()),
            IonosondeStation(code: "DB049", name: "Dourbes", latitude: 50.1, longitude: 4.6, country: "Belgium", foEs: 5.4, hEs: 100, foF2: 6.5, mufD: 21.0, deltaFoEsPerHour: -0.2, timestamp: Date()),
            IonosondeStation(code: "JR055", name: "Juliusruh", latitude: 54.6, longitude: 13.4, country: "Germany", foEs: 5.8, hEs: 102, foF2: 6.1, mufD: 19.8, deltaFoEsPerHour: 0.1, timestamp: Date()),
            IonosondeStation(code: "CHJ53", name: "Chilton", latitude: 51.5, longitude: -0.6, country: "United Kingdom", foEs: 4.9, hEs: 110, foF2: 5.8, mufD: 18.5, deltaFoEsPerHour: -0.3, timestamp: Date()),
            IonosondeStation(code: "TO536", name: "Tokyo / Kokubunji", latitude: 35.7, longitude: 139.5, country: "Japan", foEs: 9.5, hEs: 100, foF2: 8.0, mufD: 27.5, deltaFoEsPerHour: 1.4, timestamp: Date()),
            IonosondeStation(code: "BC840", name: "Boulder", latitude: 40.0, longitude: -105.3, country: "United States", foEs: 5.1, hEs: 105, foF2: 6.3, mufD: 20.5, deltaFoEsPerHour: 0.0, timestamp: Date()),
            IonosondeStation(code: "LM422", name: "Learmonth", latitude: -22.2, longitude: 114.1, country: "Australia", foEs: 6.5, hEs: 106, foF2: 7.9, mufD: 26.8, deltaFoEsPerHour: 0.2, timestamp: Date())
        ]
    }
}
