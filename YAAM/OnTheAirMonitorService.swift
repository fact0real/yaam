//
//  OnTheAirMonitorService.swift
//  YAAM
//
//  Live On-The-Air Telemetry & Radar Monitor
//  Monitors PSK Reporter (https://pskreporter.info) for 15-minute sliding windows (polled every 5 min)
//  to detect if the operator's active callsign has been heard worldwide across HF/VHF bands.
//

import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI

// MARK: - On-Air Spot Model

public struct OnAirSpot: Identifiable, Sendable, Hashable {
    public let id: String
    public let senderCall: String
    public let senderGrid: String
    public let listenerCall: String
    public let listenerGrid: String
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

    public var countryFlag: String {
        flagFromCallsignPrefix(listenerCall) ?? "🌐"
    }

    public var ageMinutes: Int {
        max(0, Int(Date().timeIntervalSince(timestamp) / 60))
    }

    public var ageText: String {
        if ageMinutes < 1 { return "Just now" }
        return "\(ageMinutes)m ago"
    }

    public var snrText: String {
        snr.map { "\($0) dB" } ?? "-"
    }

    public var snrColor: Color {
        guard let snr else { return .secondary }
        if snr >= 0 { return .green }
        if snr >= -10 { return .mint }
        if snr >= -18 { return .yellow }
        return .orange
    }
}

// MARK: - On-Air Status Enum

public enum OnAirState: Sendable, Equatable {
    case active(spotCount: Int, furthestDXKm: Double?, furthestCall: String?, bestSNR: Int?, activeBands: [String])
    case standby(lastHeard: Date?)
    case disabled

    public var isOnAir: Bool {
        if case .active = self { return true }
        return false
    }
}

// MARK: - On-The-Air Monitor Service

@MainActor
public final class OnTheAirMonitorService: ObservableObject {
    public static let shared = OnTheAirMonitorService()

    @Published public var state: OnAirState = .standby(lastHeard: nil)
    @Published public var spots: [OnAirSpot] = []
    @Published public var isPolling: Bool = false
    @Published public var countdownSeconds: Int = 300
    @Published public var pollIntervalSeconds: Int = 300 // 5 minutes
    @Published public var lastPollTime: Date?
    @Published public var sessionMaxDistanceKm: Double = 0.0
    @Published public var sessionMaxDXCall: String = ""
    @Published public var currentCallsign: String = ""
    @Published public var homeGrid: String = "LM35"
    @Published public var homeLatitude: Double = 35.6892
    @Published public var homeLongitude: Double = 51.3890

    private var pollerTask: Task<Void, Never>?
    private var lastNotifiedSpotID: String?
    private let speechSynth = AVSpeechSynthesizer()

    public init() {
        startPollerLoop()
    }

    deinit {
        pollerTask?.cancel()
    }

    // MARK: - Station Configuration
    public func setStation(callsign: String?, grid: String?, latitude: Double?, longitude: Double?) {
        let cleanCall = callsign?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        let isChanged = cleanCall != currentCallsign

        self.currentCallsign = cleanCall
        if let g = grid, !g.isEmpty {
            self.homeGrid = g.uppercased()
            if let coords = gridToCoordinate(g) {
                self.homeLatitude = coords.latitude
                self.homeLongitude = coords.longitude
            }
        }
        if let lat = latitude, let lon = longitude {
            self.homeLatitude = lat
            self.homeLongitude = lon
        }

        if isChanged && !cleanCall.isEmpty && cleanCall != "DEFAULT" && cleanCall != "NOCALL" {
            countdownSeconds = 5 // Poll quickly after station change
        }
    }

    // MARK: - Background Polling Loop
    private func startPollerLoop() {
        pollerTask?.cancel()
        pollerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self = self else { return }

                guard !self.currentCallsign.isEmpty,
                      self.currentCallsign != "DEFAULT",
                      self.currentCallsign != "NOCALL" else {
                    self.state = .disabled
                    continue
                }

                if !self.isPolling {
                    if self.countdownSeconds > 0 {
                        self.countdownSeconds -= 1
                    } else {
                        self.countdownSeconds = self.pollIntervalSeconds
                        await self.fetchOnAirTelemetry()
                    }
                }
            }
        }
    }

    // MARK: - Manual Immediate Refresh
    public func refreshNow() {
        guard !isPolling, !currentCallsign.isEmpty else { return }
        countdownSeconds = pollIntervalSeconds
        Task {
            await fetchOnAirTelemetry()
        }
    }

    // MARK: - Fetch PSK Reporter 15-Min Telemetry
    public func fetchOnAirTelemetry() async {
        guard !currentCallsign.isEmpty, currentCallsign != "DEFAULT", currentCallsign != "NOCALL" else {
            self.state = .disabled
            return
        }

        isPolling = true
        defer { isPolling = false }

        // Query last 15 minutes (flowStartSeconds=-900)
        let endpoint = "https://retrieve.pskreporter.info/query?senderCallsign=\(currentCallsign)&flowStartSeconds=-900&rptlimit=100"
        guard let url = URL(string: endpoint) else { return }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 12)
        req.setValue("YAAM-macOS/OnAirRadar-Engine factoreal", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                lastPollTime = Date()
                return
            }

            let newSpots = parsePSKReporterXML(data)
            self.spots = newSpots.sorted { $0.timestamp > $1.timestamp }
            self.lastPollTime = Date()

            if !newSpots.isEmpty {
                let maxDXSpot = newSpots.max { ($0.distanceKm ?? 0) < ($1.distanceKm ?? 0) }
                let bestSNR = newSpots.compactMap(\.snr).max()
                let activeBands = Array(Set(newSpots.map(\.band))).sorted()

                if let maxDist = maxDXSpot?.distanceKm, maxDist > sessionMaxDistanceKm {
                    sessionMaxDistanceKm = maxDist
                    sessionMaxDXCall = maxDXSpot?.listenerCall ?? ""
                }

                self.state = .active(
                    spotCount: newSpots.count,
                    furthestDXKm: maxDXSpot?.distanceKm,
                    furthestCall: maxDXSpot?.listenerCall,
                    bestSNR: bestSNR,
                    activeBands: activeBands
                )

                // Trigger Audio / Voice Chime on new spot
                if let newest = newSpots.first, newest.id != lastNotifiedSpotID {
                    lastNotifiedSpotID = newest.id
                    notifyFirstSpotHeard(spot: newest)
                }
            } else {
                self.state = .standby(lastHeard: lastPollTime)
            }
        } catch {
            lastPollTime = Date()
        }
    }

    // MARK: - Notifications
    private func notifyFirstSpotHeard(spot: OnAirSpot) {
        let soundEnabled = UserDefaults.standard.bool(forKey: "onAirSoundAlerts")
        let voiceEnabled = UserDefaults.standard.bool(forKey: "onAirVoiceAlerts")

        if soundEnabled {
            NSSound(named: "Ping")?.play()
        }

        if voiceEnabled {
            let country = countryNameFromPrefix(spot.listenerCall)
            let utterance = AVSpeechUtterance(string: "Signal spotted on \(spot.band) by \(spot.listenerCall) in \(country).")
            utterance.rate = 0.53
            speechSynth.speak(utterance)
        }
    }

    // MARK: - XML Parser
    private func parsePSKReporterXML(_ data: Data) -> [OnAirSpot] {
        let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let pattern = #"<receptionReport\b([^>]*)/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)

        var parsed: [OnAirSpot] = []
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

            if let rxCoord = gridToCoordinate(receiverGrid) {
                dist = calculateDistanceKm(lat1: homeLatitude, lon1: homeLongitude, lat2: rxCoord.latitude, lon2: rxCoord.longitude)
                let az = calculateAzimuth(fromLat: homeLatitude, fromLon: homeLongitude, toLat: rxCoord.latitude, toLon: rxCoord.longitude)
                bearing = az
                compass = degreesToCompass(az)
            }

            let spotId = "\(sender)-\(receiver)-\(freq)-\(Int(flowSeconds))"

            parsed.append(OnAirSpot(
                id: spotId,
                senderCall: sender,
                senderGrid: senderGrid,
                listenerCall: receiver,
                listenerGrid: receiverGrid,
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

    // MARK: - Mathematical & Frequency Helpers

    private func calculateDistanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180.0
        let p2 = lat2 * .pi / 180.0
        let dp = (lat2 - lat1) * .pi / 180.0
        let dl = (lon2 - lon1) * .pi / 180.0

        let a = sin(dp / 2.0) * sin(dp / 2.0) + cos(p1) * cos(p2) * sin(dl / 2.0) * sin(dl / 2.0)
        let c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
        return 6371.0 * c
    }

    private func calculateAzimuth(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double) -> Double {
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

    private func degreesToCompass(_ deg: Double) -> String {
        let compassPoints = [
            "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW", "N"
        ]
        let index = Int(round(deg.truncatingRemainder(dividingBy: 360.0) / 22.5))
        return compassPoints[max(0, min(16, index))]
    }

    private func gridToCoordinate(_ grid: String) -> (latitude: Double, longitude: Double)? {
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

    private func countryNameFromPrefix(_ call: String) -> String {
        let clean = call.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.hasPrefix("DL") || clean.hasPrefix("DK") || clean.hasPrefix("DJ") { return "Germany" }
        if clean.hasPrefix("EA") || clean.hasPrefix("EB") { return "Spain" }
        if clean.hasPrefix("I") || clean.hasPrefix("IK") || clean.hasPrefix("IU") { return "Italy" }
        if clean.hasPrefix("F") || clean.hasPrefix("TM") { return "France" }
        if clean.hasPrefix("G") || clean.hasPrefix("M") || clean.hasPrefix("2E") { return "United Kingdom" }
        if clean.hasPrefix("JA") || clean.hasPrefix("JH") || clean.hasPrefix("JR") { return "Japan" }
        if clean.hasPrefix("K") || clean.hasPrefix("W") || clean.hasPrefix("N") || clean.hasPrefix("AA") { return "USA" }
        if clean.hasPrefix("EP") { return "Iran" }
        return "Europe/World"
    }
}

// MARK: - Global Frequency to Band Conversion Helper

public func frequencyToBand(_ freqHz: Int) -> String {
    let mhz = Double(freqHz) / 1_000_000.0
    if mhz >= 1.8 && mhz <= 2.0 { return "160m" }
    if mhz >= 3.5 && mhz <= 4.0 { return "80m" }
    if mhz >= 5.3 && mhz <= 5.4 { return "60m" }
    if mhz >= 7.0 && mhz <= 7.3 { return "40m" }
    if mhz >= 10.1 && mhz <= 10.15 { return "30m" }
    if mhz >= 14.0 && mhz <= 14.35 { return "20m" }
    if mhz >= 18.068 && mhz <= 18.168 { return "17m" }
    if mhz >= 21.0 && mhz <= 21.45 { return "15m" }
    if mhz >= 24.89 && mhz <= 24.99 { return "12m" }
    if mhz >= 28.0 && mhz <= 29.7 { return "10m" }
    if mhz >= 50.0 && mhz <= 54.0 { return "6m" }
    if mhz >= 70.0 && mhz <= 70.5 { return "4m" }
    if mhz >= 144.0 && mhz <= 148.0 { return "2m" }
    if mhz >= 430.0 && mhz <= 450.0 { return "70cm" }
    return String(format: "%.1fM", mhz)
}
