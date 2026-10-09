//
//  RoverModeEngine.swift
//  YAAM
//
//  Tactical Rover & Portable Scout Engine
//  Allows operators to temporarily project station location to an alternate Maidenhead grid
//  for POTA/SOTA or portable path exploration without altering their master station profile.
//

import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI

// MARK: - Rover Session Duration Enum

public enum RoverSessionDuration: Int, CaseIterable, Identifiable, Codable, Sendable {
    case oneHour = 3600
    case fourHours = 14400
    case eightHours = 28800
    case endOfDay = 86400
    case manual = 0

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .oneHour: return "1 Hour (Quick Scout)"
        case .fourHours: return "4 Hours (Half-Day Op)"
        case .eightHours: return "8 Hours (Full Shift)"
        case .endOfDay: return "Until End of UTC Day"
        case .manual: return "Indefinite (Manual Stop)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .oneHour: return "1h"
        case .fourHours: return "4h"
        case .eightHours: return "8h"
        case .endOfDay: return "End of Day"
        case .manual: return "Manual"
        }
    }
}

// MARK: - Rover Location Preset

public struct RoverPreset: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var grid: String
    public var note: String
    public var isBuiltIn: Bool

    public init(id: UUID = UUID(), name: String, grid: String, note: String = "", isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.grid = grid.uppercased()
        self.note = note
        self.isBuiltIn = isBuiltIn
    }
}

// MARK: - Active Rover Session Model

public struct RoverSession: Codable, Equatable, Sendable {
    public var targetGrid: String
    public var label: String
    public var startTime: Date
    public var duration: RoverSessionDuration
    public var expirationDate: Date?
    public var stampInOutgoingQSOs: Bool
    public var notes: String

    public init(
        targetGrid: String,
        label: String = "Tactical Rover",
        startTime: Date = Date(),
        duration: RoverSessionDuration = .fourHours,
        expirationDate: Date? = nil,
        stampInOutgoingQSOs: Bool = false,
        notes: String = ""
    ) {
        self.targetGrid = targetGrid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.label = label
        self.startTime = startTime
        self.duration = duration
        self.stampInOutgoingQSOs = stampInOutgoingQSOs
        self.notes = notes

        if let exp = expirationDate {
            self.expirationDate = exp
        } else {
            switch duration {
            case .oneHour:
                self.expirationDate = startTime.addingTimeInterval(3600)
            case .fourHours:
                self.expirationDate = startTime.addingTimeInterval(14400)
            case .eightHours:
                self.expirationDate = startTime.addingTimeInterval(28800)
            case .endOfDay:
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
                let startOfNextDay = cal.startOfDay(for: startTime).addingTimeInterval(86400)
                self.expirationDate = startOfNextDay
            case .manual:
                self.expirationDate = nil
            }
        }
    }

    public var isExpired: Bool {
        guard let exp = expirationDate else { return false }
        return Date() >= exp
    }

    public var remainingSeconds: TimeInterval {
        guard let exp = expirationDate else { return 86400 * 365 }
        return max(0, exp.timeIntervalSince(Date()))
    }

    public var formattedRemainingTime: String {
        guard let _ = expirationDate else { return "MANUAL" }
        let total = Int(remainingSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

// MARK: - Rover Telemetry Summary

public struct RoverTelemetry: Equatable, Sendable {
    public let homeGrid: String
    public let roverGrid: String
    public let distanceKm: Double
    public let distanceMiles: Double
    public let bearingDegrees: Double
    public let cardinalDirection: String
    public let roverCoordinates: GeoCoordinate
    public let formattedCoordinates: String
    public let daylightSummary: String
}

// MARK: - Rover Mode Engine (Singleton & Controller)

@MainActor
public final class RoverModeEngine: ObservableObject {
    public static let shared = RoverModeEngine()

    // MARK: - Published State
    @Published public private(set) var activeSession: RoverSession?
    @Published public private(set) var remainingSeconds: TimeInterval = 0
    @Published public private(set) var isRoverActive: Bool = false
    @Published public var customPresets: [RoverPreset] = []
    @Published public var lastNotificationMessage: String?

    // MARK: - Internal Engine Properties
    private var countdownTimer: AnyCancellable?
    private let speechSynth = AVSpeechSynthesizer()
    private let userDefaultsKey = "YAAM_RoverModeActiveSession"
    private let userPresetsKey = "YAAM_RoverModeCustomPresets"

    // MARK: - Built-In Geographic & Activity Presets
    public static let builtInPresets: [RoverPreset] = [
        RoverPreset(name: "Kish Island", grid: "LL46", note: "IOTA AS-166 · Persian Gulf", isBuiltIn: true),
        RoverPreset(name: "Qeshm Island", grid: "LL56", note: "IOTA AS-166 · Hormuz Strait", isBuiltIn: true),
        RoverPreset(name: "Mount Damavand Summit", grid: "LL65", note: "5,609m SOTA Peak · Alborz Range", isBuiltIn: true),
        RoverPreset(name: "Caspian Sea (Babolsar)", grid: "LM56", note: "Northern Coastal Line · Caspian Basin", isBuiltIn: true),
        RoverPreset(name: "Shiraz / Persepolis", grid: "LL49", note: "Fars Plateau · Historical Site", isBuiltIn: true),
        RoverPreset(name: "Isfahan / Zayandeh", grid: "LL42", note: "Central Plateau · Historical Station", isBuiltIn: true),
        RoverPreset(name: "Tabriz / Sahand", grid: "LN38", note: "Northwestern Azerbaijan", isBuiltIn: true),
        RoverPreset(name: "Chabahar / Makran", grid: "ML15", note: "Oman Sea Deep Coast", isBuiltIn: true)
    ]

    private init() {
        loadSavedState()
        startTimer()
    }

    // MARK: - Lifecycle & Persistence
    private func loadSavedState() {
        // Load custom presets
        if let data = UserDefaults.standard.data(forKey: userPresetsKey),
           let list = try? JSONDecoder().decode([RoverPreset].self, from: data) {
            self.customPresets = list
        }

        // Restore active session if not expired
        if let sessionData = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode(RoverSession.self, from: sessionData) {
            if !saved.isExpired {
                self.activeSession = saved
                self.isRoverActive = true
                self.remainingSeconds = saved.remainingSeconds
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }
        }
    }

    private func persistSession() {
        if let session = activeSession {
            if let data = try? JSONEncoder().encode(session) {
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        }
    }

    public func saveCustomPreset(name: String, grid: String, note: String = "") {
        guard let validated = GridLocator.fourCharacterGrid(from: grid) else { return }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = RoverPreset(
            name: cleanName.isEmpty ? validated : cleanName,
            grid: validated,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            isBuiltIn: false
        )
        customPresets.removeAll { $0.grid == validated }
        customPresets.append(preset)
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: userPresetsKey)
        }
    }

    public func deleteCustomPreset(id: UUID) {
        customPresets.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: userPresetsKey)
        }
    }

    public var allPresets: [RoverPreset] {
        Self.builtInPresets + customPresets
    }

    // MARK: - Timer & Auto-Expiration
    private func startTimer() {
        countdownTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.handleTimerTick()
            }
    }

    private func handleTimerTick() {
        guard let session = activeSession else {
            if isRoverActive { isRoverActive = false }
            return
        }

        if session.isExpired {
            expireSession()
        } else {
            remainingSeconds = session.remainingSeconds
        }
    }

    // MARK: - Session Control Methods

    /// Activates Rover Mode with a verified target grid and selected duration
    public func activate(
        grid: String,
        label: String = "Tactical Rover",
        duration: RoverSessionDuration = .fourHours,
        stampInOutgoingQSOs: Bool = false,
        notes: String = ""
    ) -> Bool {
        let clean = grid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count >= 4, GridLocator.fourCharacterGrid(from: clean) != nil else {
            return false
        }

        let session = RoverSession(
            targetGrid: clean,
            label: label.isEmpty ? "Rover \(clean)" : label,
            startTime: Date(),
            duration: duration,
            stampInOutgoingQSOs: stampInOutgoingQSOs,
            notes: notes
        )

        self.activeSession = session
        self.isRoverActive = true
        self.remainingSeconds = session.remainingSeconds
        persistSession()

        // Audio and announcement
        playActivationChime()
        announceVoice(text: "Rover mode active on grid \(clean)")
        return true
    }

    /// Deactivates Rover Mode and cleanly returns to Home Station
    public func deactivate() {
        let wasGrid = activeSession?.targetGrid ?? ""
        activeSession = nil
        isRoverActive = false
        remainingSeconds = 0
        persistSession()

        playDeactivationChime()
        if !wasGrid.isEmpty {
            announceVoice(text: "Rover mode disengaged. Returned to home station.")
        }
    }

    /// Extends current active session by the specified duration in seconds (default +1 Hour)
    public func extendDuration(seconds: TimeInterval = 3600) {
        guard var session = activeSession else { return }
        let currentExp = session.expirationDate ?? Date()
        session.expirationDate = currentExp.addingTimeInterval(seconds)
        activeSession = session
        remainingSeconds = session.remainingSeconds
        persistSession()
    }

    private func expireSession() {
        let _ = activeSession?.targetGrid ?? ""
        activeSession = nil
        isRoverActive = false
        remainingSeconds = 0
        persistSession()

        playExpirationChime()
        announceVoice(text: "Rover session expired. Returned to home grid.")
    }

    // MARK: - 4-Way Compass Grid Stepping (N, S, E, W)

    public func stepNorth() {
        stepGrid(dLon: 0, dLat: 1)
    }

    public func stepSouth() {
        stepGrid(dLon: 0, dLat: -1)
    }

    public func stepEast() {
        stepGrid(dLon: 1, dLat: 0)
    }

    public func stepWest() {
        stepGrid(dLon: -1, dLat: 0)
    }

    /// Increments/decrements the current target grid along latitude/longitude Maidenhead square indices
    public func stepGrid(dLon: Int, dLat: Int) {
        guard var session = activeSession else { return }
        let currentGrid = session.targetGrid

        if let stepped = Self.calculateSteppedGrid(from: currentGrid, dLon: dLon, dLat: dLat) {
            session.targetGrid = stepped
            activeSession = session
            persistSession()
            NSSound(named: "Tink")?.play()
        }
    }

    /// Standalone calculation for stepping any Maidenhead 4-character locator
    public static func calculateSteppedGrid(from rawGrid: String, dLon: Int, dLat: Int) -> String? {
        let clean = rawGrid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count >= 4 else { return nil }

        let chars = Array(clean)
        guard
            let lonFieldVal = chars[0].asciiValue, lonFieldVal >= Character("A").asciiValue!, lonFieldVal <= Character("R").asciiValue!,
            let latFieldVal = chars[1].asciiValue, latFieldVal >= Character("A").asciiValue!, latFieldVal <= Character("R").asciiValue!,
            let lonSquare = chars[2].wholeNumberValue,
            let latSquare = chars[3].wholeNumberValue
        else {
            return nil
        }

        let fLon = Int(lonFieldVal - Character("A").asciiValue!)
        let fLat = Int(latFieldVal - Character("A").asciiValue!)

        var lonIndex = fLon * 10 + lonSquare + dLon
        var latIndex = fLat * 10 + latSquare + dLat

        // Longitude wraps around globe (0 to 179 squares)
        lonIndex = (lonIndex % 180 + 180) % 180
        // Latitude clamps to poles (0 to 179 squares)
        latIndex = max(0, min(179, latIndex))

        let newFLon = lonIndex / 10
        let newSqLon = lonIndex % 10
        let newFLat = latIndex / 10
        let newSqLat = latIndex % 10

        let c1 = Character(UnicodeScalar(UInt8(Character("A").asciiValue! + UInt8(newFLon))))
        let c2 = Character(UnicodeScalar(UInt8(Character("A").asciiValue! + UInt8(newFLat))))

        let base4 = "\(c1)\(c2)\(newSqLon)\(newSqLat)"

        // If original was 6 characters, preserve the subsquares in standard lowercase format
        if clean.count >= 6 {
            let sub = clean.dropFirst(4).lowercased()
            return "\(base4)\(sub)"
        }
        return base4
    }

    // MARK: - Effective Grid & Coordinates Provider

    /// Returns the effective station grid: rover grid if active, otherwise the fallback home grid
    public func effectiveGrid(homeGrid: String) -> String {
        if let session = activeSession, !session.isExpired, !session.targetGrid.isEmpty {
            return session.targetGrid
        }
        return homeGrid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Returns the effective station coordinate: rover coordinate if active, otherwise home coordinate
    public func effectiveCoordinate(homeCoordinate: GeoCoordinate) -> GeoCoordinate {
        if let session = activeSession, !session.isExpired, !session.targetGrid.isEmpty {
            if let box = MaidenheadGridEngine.boundingBox(for: session.targetGrid) {
                return box.center
            }
        }
        return homeCoordinate
    }

    // MARK: - Telemetry & Geometry Diagnostics

    public func telemetry(homeGrid: String, roverGridOverride: String? = nil) -> RoverTelemetry? {
        guard let currentRover = roverGridOverride ?? activeSession?.targetGrid else { return nil }
        let effectiveHome = homeGrid

        guard let homeBox = MaidenheadGridEngine.boundingBox(for: effectiveHome),
              let roverBox = MaidenheadGridEngine.boundingBox(for: currentRover) else {
            return nil
        }

        let homeCoord = homeBox.center
        let roverCoord = roverBox.center

        let distKm = GeodesicMath.distanceKm(from: homeCoord, to: roverCoord)
        let distMi = distKm * 0.621371
        let bearing = GeodesicMath.initialBearing(from: homeCoord, to: roverCoord)
        let cardinal = SpotterDistanceEngine.cardinalDirection(for: bearing)

        let latStr = String(format: "%.3f° %@", abs(roverCoord.latitude), roverCoord.latitude >= 0 ? "N" : "S")
        let lonStr = String(format: "%.3f° %@", abs(roverCoord.longitude), roverCoord.longitude >= 0 ? "E" : "W")
        let formattedCoord = "\(latStr), \(lonStr)"

        // Calculate solar times
        let sunTimes = AstronomicalSolarEngine.sunriseSunset(for: roverCoord, date: Date())
        let daylight = "Sunrise: \(sunTimes.sunrise) · Sunset: \(sunTimes.sunset) UTC"

        return RoverTelemetry(
            homeGrid: effectiveHome,
            roverGrid: currentRover,
            distanceKm: distKm,
            distanceMiles: distMi,
            bearingDegrees: bearing,
            cardinalDirection: cardinal,
            roverCoordinates: roverCoord,
            formattedCoordinates: formattedCoord,
            daylightSummary: daylight
        )
    }

    // MARK: - Audio & Voice Feedback
    private func playActivationChime() {
        NSSound(named: "Hero")?.play()
    }

    private func playDeactivationChime() {
        NSSound(named: "Pop")?.play()
    }

    private func playExpirationChime() {
        NSSound(named: "Basso")?.play()
    }

    private func announceVoice(text: String) {
        guard UserDefaults.standard.bool(forKey: "voiceAlertsEnabled") != false else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.05
        speechSynth.speak(utterance)
    }
}
