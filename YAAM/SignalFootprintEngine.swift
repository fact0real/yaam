//
//  SignalFootprintEngine.swift
//  YAAM
//
//  Live PSKReporter & Reverse Beacon Network (RBN) Signal Footprint Engine
//  ("ردپای سیگنال من در جهان")
//  Dual-feed aggregator providing real-time telemetry on where and how strong
//  the operator's transmitted signals (FT8, FT4, CW, RTTY, etc.) are heard worldwide.
//

import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI

// MARK: - Feed Source Enum

public enum SignalFootprintSource: String, CaseIterable, Identifiable, Sendable {
    case pskReporter = "PSK Reporter"
    case rbn = "RBN Skimmer"
    case dxCluster = "DX Cluster"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .pskReporter: return "dot.radiowaves.left.and.right"
        case .rbn: return "waveform.badge.magnifyingglass"
        case .dxCluster: return "antenna.radiowaves.left.and.right"
        }
    }

    public var badgeColor: Color {
        switch self {
        case .pskReporter: return .blue
        case .rbn: return .purple
        case .dxCluster: return .orange
        }
    }
}

// MARK: - Time Range Window Enum

public enum SignalFootprintTimeRange: Int, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes = 900
    case oneHour = 3600
    case sixHours = 21600
    case twentyFourHours = 86400

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .fifteenMinutes: return "15 Min"
        case .oneHour: return "1 Hour"
        case .sixHours: return "6 Hours"
        case .twentyFourHours: return "24 Hours"
        }
    }

    public var shortLabel: String {
        switch self {
        case .fifteenMinutes: return "15m"
        case .oneHour: return "1h"
        case .sixHours: return "6h"
        case .twentyFourHours: return "24h"
        }
    }

    public var reportLimit: Int {
        switch self {
        case .fifteenMinutes: return 150
        case .oneHour: return 250
        case .sixHours: return 400
        case .twentyFourHours: return 600
        }
    }
}

// MARK: - Signal Footprint Spot Model

public struct SignalFootprintSpot: Identifiable, Sendable, Hashable {
    public let id: String
    public let source: SignalFootprintSource
    public let senderCall: String
    public let senderGrid: String
    public let listenerCall: String
    public let listenerGrid: String
    public let listenerCountry: String
    public let flag: String
    public let frequencyHz: Int
    public let mode: String
    public let snr: Int?
    public let distanceKm: Double?
    public let bearingDeg: Double?
    public let bearingCompass: String?
    public let timestamp: Date

    public var frequencyMHz: Double {
        Double(frequencyHz) / 1_000_000.0
    }

    public var band: String {
        frequencyToBand(frequencyHz)
    }

    public var ageMinutes: Int {
        max(0, Int(Date().timeIntervalSince(timestamp) / 60))
    }

    public var ageText: String {
        if ageMinutes < 1 { return "Just now" }
        if ageMinutes < 60 { return "\(ageMinutes)m ago" }
        return "\(ageMinutes / 60)h \(ageMinutes % 60)m ago"
    }

    public var snrText: String {
        guard let snr else { return "-" }
        return snr > 0 ? "+\(snr) dB" : "\(snr) dB"
    }

    public var snrColor: Color {
        guard let snr else { return .secondary }
        if snr >= 3 { return .green }
        if snr >= -3 { return .mint }
        if snr >= -10 { return .yellow }
        if snr >= -18 { return .orange }
        return .red
    }

    public var coordinate: GeoCoordinate {
        if !listenerGrid.isEmpty, let box = MaidenheadGridEngine.boundingBox(for: listenerGrid) {
            return box.center
        }
        // Fallback default coordinates if grid is missing
        return GeoCoordinate(latitude: 30.0, longitude: 0.0)
    }
}

// MARK: - Polar Sector Antenna Coverage Model

public struct PolarSectorCoverage: Identifiable, Sendable {
    public let id = UUID()
    public let sectorIndex: Int
    public let bearingDeg: Double
    public let name: String
    public let spotCount: Int
    public let maxDistanceKm: Double
    public let avgSNR: Double
    public let bestCall: String
}

// MARK: - Band Propagation Statistics Model

public struct BandPropagationStat: Identifiable, Sendable {
    public var id: String { band }
    public let band: String
    public let spotCount: Int
    public let maxDistanceKm: Double
    public let furthestCall: String
    public let furthestCountry: String
    public let furthestFlag: String
    public let avgSNR: Double
    public let bestSNR: Int?
}

// MARK: - Signal Footprint Engine

@MainActor
public final class SignalFootprintEngine: ObservableObject {
    public static let shared = SignalFootprintEngine()

    // MARK: - Published State
    @Published public var spots: [SignalFootprintSpot] = []
    @Published public var selectedTimeRange: SignalFootprintTimeRange = .fifteenMinutes {
        didSet {
            if oldValue != selectedTimeRange {
                refreshNow()
            }
        }
    }
    @Published public var isPolling: Bool = false
    @Published public var countdownSeconds: Int = 300
    @Published public var pollIntervalSeconds: Int = 300 // 5 minutes
    @Published public var lastPollTime: Date?
    @Published public var sessionMaxDistanceKm: Double = 0.0
    @Published public var sessionMaxDXCall: String = ""
    @Published public var sessionMaxDXFlag: String = ""
    @Published public var sessionMaxDXCountry: String = ""
    @Published public var sessionMaxDXBearing: Double = 0.0
    @Published public var stationCallsign: String = ""
    @Published public var homeGrid: String = ""
    @Published public var homeCoordinate: GeoCoordinate = GeoCoordinate(latitude: 35.6892, longitude: 51.3890)
    @Published public var audioAlertsEnabled: Bool = true
    @Published public var voiceAlertsEnabled: Bool = false
    @Published public var filterBand: String = "ALL"
    @Published public var filterMode: String = "ALL"
    @Published public var filterSource: String = "ALL"
    @Published public var isSimulatedData: Bool = false

    private var pollerTask: Task<Void, Never>?
    private var lastNotifiedSpotID: String?
    private let speechSynth = AVSpeechSynthesizer()

    public init() {
        startPollerLoop()
    }

    deinit {
        pollerTask?.cancel()
    }

    // MARK: - Filtered Spots
    public var filteredSpots: [SignalFootprintSpot] {
        spots.filter { spot in
            if filterBand != "ALL" && spot.band != filterBand { return false }
            if filterMode != "ALL" && !spot.mode.localizedCaseInsensitiveContains(filterMode) { return false }
            if filterSource != "ALL" && spot.source.rawValue != filterSource { return false }
            return true
        }
    }

    // MARK: - Station Configuration
    public func setStation(callsign: String?, grid: String?, latitude: Double?, longitude: Double?) {
        let cleanCall = callsign?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let isChanged = cleanCall != stationCallsign

        self.stationCallsign = cleanCall
        if let g = grid, !g.isEmpty {
            self.homeGrid = g.uppercased()
            if let box = MaidenheadGridEngine.boundingBox(for: g) {
                self.homeCoordinate = box.center
            }
        }
        if let lat = latitude, let lon = longitude {
            self.homeCoordinate = GeoCoordinate(latitude: lat, longitude: lon)
        }

        if isChanged && !cleanCall.isEmpty && cleanCall != "DEFAULT" && cleanCall != "NOCALL" {
            countdownSeconds = 3 // Fast poll after callsign change
        }
    }

    // MARK: - Background Polling Loop
    private func startPollerLoop() {
        pollerTask?.cancel()
        pollerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self = self else { return }

                guard !self.stationCallsign.isEmpty,
                      self.stationCallsign != "DEFAULT",
                      self.stationCallsign != "NOCALL" else {
                    continue
                }

                if !self.isPolling && !self.isSimulatedData {
                    if self.countdownSeconds > 0 {
                        self.countdownSeconds -= 1
                    } else {
                        self.countdownSeconds = self.pollIntervalSeconds
                        await self.fetchFootprintTelemetry()
                    }
                }
            }
        }
    }

    // MARK: - Manual Refresh
    public func refreshNow() {
        guard !isPolling, !stationCallsign.isEmpty else { return }
        isSimulatedData = false
        countdownSeconds = pollIntervalSeconds
        Task { @MainActor in
            await self.fetchFootprintTelemetry()
        }
    }

    // MARK: - Ingest RBN / Cluster Spot
    public func ingestRBNSpot(callsign: String, spotter: String, freqKHz: Double, comment: String, time: Date) {
        guard !stationCallsign.isEmpty, callsign.uppercased() == stationCallsign else { return }

        let cleanSpotter = spotter.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let freqHz = Int(freqKHz * 1000.0)
        let mode = AmateurBandPlan.inferredMode(frequencyMHz: freqKHz / 1000.0, comment: comment)
        let dxcc = DXCCDatabase.resolve(callsign: cleanSpotter)
        let snr = extractSNRFromComment(comment)

        let spotterGrid: String
        let gridMatch = comment.range(of: #"\b([A-R]{2}[0-9]{2}(?:[A-X]{2})?)\b"#, options: .regularExpression)
        if let match = gridMatch {
            spotterGrid = String(comment[match]).uppercased()
        } else {
            spotterGrid = ""
        }

        let coord: GeoCoordinate
        if !spotterGrid.isEmpty, let box = MaidenheadGridEngine.boundingBox(for: spotterGrid) {
            coord = box.center
        } else {
            coord = GeoCoordinate(latitude: 35.0, longitude: 10.0)
        }

        let dist = GeodesicMath.distanceKm(from: homeCoordinate, to: coord)
        let bearing = GeodesicMath.initialBearing(from: homeCoordinate, to: coord)
        let compass = GeodesicMath.compassCardinal(for: bearing)

        let spotId = "rbn-\(cleanSpotter)-\(freqHz)-\(Int(time.timeIntervalSince1970))"

        let spot = SignalFootprintSpot(
            id: spotId,
            source: .rbn,
            senderCall: stationCallsign,
            senderGrid: homeGrid,
            listenerCall: cleanSpotter,
            listenerGrid: spotterGrid,
            listenerCountry: dxcc.entityName,
            flag: dxcc.flagEmoji,
            frequencyHz: freqHz,
            mode: mode,
            snr: snr,
            distanceKm: dist,
            bearingDeg: bearing,
            bearingCompass: compass,
            timestamp: time
        )

        // Insert at beginning and deduplicate
        var updated = spots.filter { $0.id != spot.id }
        updated.insert(spot, at: 0)
        self.spots = updated
        updateSummaryKPIs(from: updated)
    }

    private func extractSNRFromComment(_ text: String) -> Int? {
        let pattern = #"\b(-?\d+)\s*dB\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[captureRange])
    }

    // MARK: - Fetch PSK Reporter REST XML
    public func fetchFootprintTelemetry() async {
        guard !stationCallsign.isEmpty, stationCallsign != "DEFAULT", stationCallsign != "NOCALL" else {
            return
        }

        isPolling = true
        defer { isPolling = false }

        let windowSeconds = selectedTimeRange.rawValue
        let limit = selectedTimeRange.reportLimit
        let endpoint = "https://retrieve.pskreporter.info/query?senderCallsign=\(stationCallsign)&flowStartSeconds=-\(windowSeconds)&rptlimit=\(limit)"
        guard let url = URL(string: endpoint) else { return }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 14)
        req.setValue("YAAM-macOS/SignalFootprint-Engine factoreal", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                lastPollTime = Date()
                return
            }

            let parsedSpots = parsePSKReporterXML(data)
            self.spots = parsedSpots.sorted { $0.timestamp > $1.timestamp }
            self.lastPollTime = Date()
            updateSummaryKPIs(from: parsedSpots)

            // Trigger alert on new farthest or strong spot
            if let newest = parsedSpots.first, newest.id != lastNotifiedSpotID {
                lastNotifiedSpotID = newest.id
                triggerAlert(for: newest)
            }
        } catch {
            lastPollTime = Date()
        }
    }

    private func updateSummaryKPIs(from newSpots: [SignalFootprintSpot]) {
        guard !newSpots.isEmpty else { return }
        if let maxDX = newSpots.max(by: { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) }),
           let dist = maxDX.distanceKm, dist > 0 {
            sessionMaxDistanceKm = dist
            sessionMaxDXCall = maxDX.listenerCall
            sessionMaxDXFlag = maxDX.flag
            sessionMaxDXCountry = maxDX.listenerCountry
            sessionMaxDXBearing = maxDX.bearingDeg ?? 0.0
        }
    }

    // MARK: - XML Parser
    private func parsePSKReporterXML(_ data: Data) -> [SignalFootprintSpot] {
        let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let pattern = #"<receptionReport\b([^>]*)/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)

        var parsed: [SignalFootprintSpot] = []
        for match in regex.matches(in: xml, range: range) where match.numberOfRanges > 1 {
            guard let attrRange = Range(match.range(at: 1), in: xml) else { continue }
            let attrs = parseXMLAttributes(String(xml[attrRange]))
            guard let sender = attrs["senderCallsign"],
                  let receiver = attrs["receiverCallsign"] else { continue }

            let freq = Int(attrs["frequency"] ?? "0") ?? 0
            let senderGrid = attrs["senderLocator"] ?? homeGrid
            let receiverGrid = attrs["receiverLocator"] ?? ""
            let mode = attrs["mode"] ?? "FT8"
            let snr = Int(attrs["sNR"] ?? "")
            let flowSeconds = Double(attrs["flowStartSeconds"] ?? "") ?? Date().timeIntervalSince1970
            let spotTime = Date(timeIntervalSince1970: flowSeconds)

            var dist: Double? = nil
            var bearing: Double? = nil
            var compass: String? = nil

            let dxcc = DXCCDatabase.resolve(callsign: receiver)

            if !receiverGrid.isEmpty, let box = MaidenheadGridEngine.boundingBox(for: receiverGrid) {
                let rxCoord = box.center
                dist = GeodesicMath.distanceKm(from: homeCoordinate, to: rxCoord)
                let az = GeodesicMath.initialBearing(from: homeCoordinate, to: rxCoord)
                bearing = az
                compass = GeodesicMath.compassCardinal(for: az)
            }

            let spotId = "\(sender)-\(receiver)-\(freq)-\(Int(flowSeconds))"

            parsed.append(SignalFootprintSpot(
                id: spotId,
                source: .pskReporter,
                senderCall: sender,
                senderGrid: senderGrid,
                listenerCall: receiver,
                listenerGrid: receiverGrid,
                listenerCountry: dxcc.entityName,
                flag: dxcc.flagEmoji,
                frequencyHz: freq,
                mode: mode,
                snr: snr,
                distanceKm: dist,
                bearingDeg: bearing,
                bearingCompass: compass,
                timestamp: spotTime
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

    // MARK: - Polar Antenna Radiation Pattern Calculation
    public func computePolarCoverage() -> [PolarSectorCoverage] {
        let sectorLabels = [
            "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"
        ]
        let sectorWidth = 360.0 / 16.0

        var sectors: [PolarSectorCoverage] = []

        for (index, label) in sectorLabels.enumerated() {
            let centerBearing = Double(index) * sectorWidth
            let minBearing = (centerBearing - sectorWidth / 2.0 + 360.0).truncatingRemainder(dividingBy: 360.0)
            let maxBearing = (centerBearing + sectorWidth / 2.0).truncatingRemainder(dividingBy: 360.0)

            let sectorSpots = filteredSpots.filter { spot in
                guard let b = spot.bearingDeg else { return false }
                if minBearing > maxBearing {
                    return b >= minBearing || b < maxBearing
                } else {
                    return b >= minBearing && b < maxBearing
                }
            }

            let count = sectorSpots.count
            let maxDist = sectorSpots.compactMap(\.distanceKm).max() ?? 0.0
            let snrs = sectorSpots.compactMap(\.snr)
            let avgSNR = snrs.isEmpty ? -30.0 : Double(snrs.reduce(0, +)) / Double(snrs.count)
            let bestSpot = sectorSpots.max(by: { ($0.snr ?? -99) < ($1.snr ?? -99) })

            sectors.append(PolarSectorCoverage(
                sectorIndex: index,
                bearingDeg: centerBearing,
                name: label,
                spotCount: count,
                maxDistanceKm: maxDist,
                avgSNR: avgSNR,
                bestCall: bestSpot?.listenerCall ?? ""
            ))
        }

        return sectors
    }

    // MARK: - Band Propagation Statistics
    public func computeBandStats() -> [BandPropagationStat] {
        let bands = Array(Set(spots.map(\.band))).sorted()
        var list: [BandPropagationStat] = []

        for b in bands {
            let bandSpots = spots.filter { $0.band == b }
            guard !bandSpots.isEmpty else { continue }
            let maxDX = bandSpots.max(by: { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) })
            let snrs = bandSpots.compactMap(\.snr)
            let avgSNR = snrs.isEmpty ? 0.0 : Double(snrs.reduce(0, +)) / Double(snrs.count)
            let bestSNR = snrs.max()

            list.append(BandPropagationStat(
                band: b,
                spotCount: bandSpots.count,
                maxDistanceKm: maxDX?.distanceKm ?? 0.0,
                furthestCall: maxDX?.listenerCall ?? "-",
                furthestCountry: maxDX?.listenerCountry ?? "-",
                furthestFlag: maxDX?.flag ?? "🌐",
                avgSNR: avgSNR,
                bestSNR: bestSNR
            ))
        }

        return list.sorted { $0.maxDistanceKm > $1.maxDistanceKm }
    }

    // MARK: - Audio & Voice Alerts
    private func triggerAlert(for spot: SignalFootprintSpot) {
        if audioAlertsEnabled {
            NSSound(named: "Ping")?.play()
        }

        if voiceAlertsEnabled {
            let country = spot.listenerCountry.isEmpty ? "World" : spot.listenerCountry
            let utterance = AVSpeechUtterance(string: "Signal footprint spotted on \(spot.band) by \(spot.listenerCall) in \(country).")
            utterance.rate = 0.52
            speechSynth.speak(utterance)
        }
    }

    // MARK: - Simulation Telemetry Generator
    public func loadSampleFootprintTelemetry() {
        let sampleStations: [(call: String, grid: String, freq: Int, mode: String, snr: Int, source: SignalFootprintSource)] = [
            ("JA1XRH", "QM05", 14074000, "FT8", 6, .pskReporter),
            ("JH4UYB", "PM64", 21074000, "FT8", 2, .pskReporter),
            ("DL0IGI", "JN57", 14074000, "FT8", -3, .pskReporter),
            ("W1AW", "FN31", 14074000, "FT8", -14, .pskReporter),
            ("K6LL", "DM34", 14074000, "FT8", -19, .pskReporter),
            ("VK2DX", "QF56", 21074000, "FT8", -18, .pskReporter),
            ("VK6HD", "OF78", 28074000, "FT8", -11, .pskReporter),
            ("ZS6DN", "KG44", 21074000, "FT8", -7, .pskReporter),
            ("PY2XB", "GG66", 14074000, "FT8", -16, .pskReporter),
            ("LU8EOT", "GF05", 7074000, "FT8", -21, .pskReporter),
            ("G4FOC", "IO91", 7074000, "FT8", 3, .pskReporter),
            ("OH2BAD", "KP20", 14074000, "FT8", -5, .pskReporter),
            ("UA0IT", "QP19", 14074000, "FT8", -12, .pskReporter),
            ("VU2TS", "MK82", 28074000, "FT8", 8, .pskReporter),
            ("EA8URL", "IL18", 14074000, "FT8", -9, .pskReporter),
            ("W3LPL-#", "FM19", 14025000, "CW", 16, .rbn),
            ("SK3W-#", "JP80", 7015000, "CW", 12, .rbn),
            ("ED1ZAB-#", "IN73", 21028000, "CW", 9, .rbn),
            ("KM3T-#", "FN42", 14032000, "CW", -2, .rbn),
            ("TF3Y-#", "HP94", 14080000, "RTTY", 4, .rbn)
        ]

        var newSpots: [SignalFootprintSpot] = []
        let call = stationCallsign.isEmpty ? TransmitIdentity.callsignNotSetLabel : stationCallsign

        for (index, s) in sampleStations.enumerated() {
            let targetCoord: GeoCoordinate
            if let box = MaidenheadGridEngine.boundingBox(for: s.grid) {
                targetCoord = box.center
            } else {
                targetCoord = GeoCoordinate(latitude: 0, longitude: 0)
            }

            let dist = GeodesicMath.distanceKm(from: homeCoordinate, to: targetCoord)
            let bearing = GeodesicMath.initialBearing(from: homeCoordinate, to: targetCoord)
            let compass = GeodesicMath.compassCardinal(for: bearing)
            let dxcc = DXCCDatabase.resolve(callsign: s.call)

            let spot = SignalFootprintSpot(
                id: "sim-\(index)-\(s.call)",
                source: s.source,
                senderCall: call,
                senderGrid: homeGrid,
                listenerCall: s.call,
                listenerGrid: s.grid,
                listenerCountry: dxcc.entityName,
                flag: dxcc.flagEmoji,
                frequencyHz: s.freq,
                mode: s.mode,
                snr: s.snr,
                distanceKm: dist,
                bearingDeg: bearing,
                bearingCompass: compass,
                timestamp: Date().addingTimeInterval(-Double(index * 60))
            )
            newSpots.append(spot)
        }

        self.spots = newSpots
        self.isSimulatedData = true
        self.lastPollTime = Date()
        updateSummaryKPIs(from: newSpots)
    }
}
