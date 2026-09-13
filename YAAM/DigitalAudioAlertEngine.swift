//
//  DigitalAudioAlertEngine.swift
//  YAAM
//
//  Native macOS Speech Alert Engine for Digital Modes (FT8 / FT4 / JS8).
//  Utilizes AVSpeechSynthesizer with cycle debouncing, priority queuing,
//  and full user customization for hands-free DX notification.
//

import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI

@MainActor
public final class DigitalAudioAlertEngine: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    public static let shared = DigitalAudioAlertEngine()

    // MARK: - User Settings
    @Published public var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "audioAlertsEnabled") }
    }
    @Published public var alertOnNewDXCC: Bool {
        didSet { UserDefaults.standard.set(alertOnNewDXCC, forKey: "audioAlertNewDXCC") }
    }
    @Published public var alertOnNewBand: Bool {
        didSet { UserDefaults.standard.set(alertOnNewBand, forKey: "audioAlertNewBand") }
    }
    @Published public var alertOnNewGrid: Bool {
        didSet { UserDefaults.standard.set(alertOnNewGrid, forKey: "audioAlertNewGrid") }
    }
    @Published public var alertOnDirectedToMe: Bool {
        didSet { UserDefaults.standard.set(alertOnDirectedToMe, forKey: "audioAlertDirectedToMe") }
    }
    @Published public var playChimeFirst: Bool {
        didSet { UserDefaults.standard.set(playChimeFirst, forKey: "audioAlertChimeFirst") }
    }
    @Published public var speechRate: Double {
        didSet { UserDefaults.standard.set(speechRate, forKey: "audioAlertSpeechRate") }
    }
    @Published public var speechVolume: Double {
        didSet { UserDefaults.standard.set(speechVolume, forKey: "audioAlertSpeechVolume") }
    }
    @Published public var selectedVoiceID: String {
        didSet { UserDefaults.standard.set(selectedVoiceID, forKey: "audioAlertVoiceID") }
    }

    // MARK: - Published State
    @Published public private(set) var isSpeaking: Bool = false
    @Published public private(set) var lastSpokenMessage: String = ""
    @Published public private(set) var recentAlertsCount: Int = 0

    // MARK: - Private Properties
    private let synthesizer = AVSpeechSynthesizer()
    private var spokenHistory: [String: Date] = [:] // callsign -> timestamp
    private var pendingQueue: [QueuedAlert] = []
    private var isProcessingQueue = false
    private let historyRetentionSeconds: TimeInterval = 60.0

    private struct QueuedAlert: Comparable {
        let priority: Int // 1 = DirectedToMe, 2 = NewDXCC, 3 = NewBand, 4 = NewGrid
        let message: String
        let callsign: String
        let timestamp: Date

        static func < (lhs: QueuedAlert, rhs: QueuedAlert) -> Bool {
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.timestamp < rhs.timestamp
        }
    }

    public override init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "audioAlertsEnabled") as? Bool ?? true
        self.alertOnNewDXCC = UserDefaults.standard.object(forKey: "audioAlertNewDXCC") as? Bool ?? true
        self.alertOnNewBand = UserDefaults.standard.object(forKey: "audioAlertNewBand") as? Bool ?? true
        self.alertOnNewGrid = UserDefaults.standard.object(forKey: "audioAlertNewGrid") as? Bool ?? true
        self.alertOnDirectedToMe = UserDefaults.standard.object(forKey: "audioAlertDirectedToMe") as? Bool ?? true
        self.playChimeFirst = UserDefaults.standard.object(forKey: "audioAlertChimeFirst") as? Bool ?? true
        let rate = UserDefaults.standard.double(forKey: "audioAlertSpeechRate")
        self.speechRate = rate > 0 ? rate : 0.52
        let vol = UserDefaults.standard.object(forKey: "audioAlertSpeechVolume") as? Double
        self.speechVolume = vol ?? 1.0
        self.selectedVoiceID = UserDefaults.standard.string(forKey: "audioAlertVoiceID") ?? ""

        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Available System Voices
    public var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.starts(with: "en")
        }
    }

    public struct VoiceOption: Identifiable, Hashable, Sendable {
        public let id: String
        public let name: String
        public let language: String
        public let regionName: String
        public let flagEmoji: String

        public var displayName: String {
            "\(flagEmoji) \(name) (\(regionName))"
        }
    }

    public var voiceOptions: [VoiceOption] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let enVoices = voices.filter { $0.language.starts(with: "en") }
        let targetList = enVoices.isEmpty ? voices : enVoices

        let noveltyNames: Set<String> = [
            "Bad News", "Bahh", "Bells", "Boing", "Bubbles", "Cellos", "Deranged",
            "Wobble", "Good News", "Hysterical", "Jester", "Organ", "Trinoids",
            "Whisper", "Zarvox"
        ]

        let filtered = targetList.filter { !noveltyNames.contains($0.name) }

        return filtered.map { v in
            let flag: String
            let region: String
            switch v.language {
            case "en-US":
                flag = "🇺🇸"
                region = "United States"
            case "en-GB":
                flag = "🇬🇧"
                region = "United Kingdom"
            case "en-AU":
                flag = "🇦🇺"
                region = "Australia"
            case "en-CA":
                flag = "🇨🇦"
                region = "Canada"
            case "en-IE":
                flag = "🇮🇪"
                region = "Ireland"
            case "en-IN":
                flag = "🇮🇳"
                region = "India"
            case "en-ZA":
                flag = "🇿🇦"
                region = "South Africa"
            case "en-NZ":
                flag = "🇳🇿"
                region = "New Zealand"
            default:
                flag = "🌐"
                let loc = Locale(identifier: v.language)
                region = loc.localizedString(forIdentifier: v.language) ?? v.language
            }
            return VoiceOption(id: v.identifier, name: v.name, language: v.language, regionName: region, flagEmoji: flag)
        }.sorted { (a, b) -> Bool in
            if a.name == "Samantha" && b.name != "Samantha" { return true }
            if b.name == "Samantha" && a.name != "Samantha" { return false }
            if a.name == "Daniel" && b.name != "Daniel" { return true }
            if b.name == "Daniel" && a.name != "Daniel" { return false }
            return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
        }
    }

    // MARK: - Public Dispatch APIs

    /// Dispatches an alert for an all-time new DXCC entity
    public func announceNewDXCC(callsign: String, country: String, band: String) {
        guard isEnabled && alertOnNewDXCC else { return }
        let cleanCountry = country.isEmpty ? "new entity" : country
        let phrase = "New DXCC! \(cleanCountry), \(formatCallsignForSpeech(callsign)) on \(band)"
        enqueueAlert(priority: 2, message: phrase, callsign: callsign)
    }

    /// Dispatches an alert for a new DXCC on this specific band
    public func announceNewBand(callsign: String, country: String, band: String) {
        guard isEnabled && alertOnNewBand else { return }
        let cleanCountry = country.isEmpty ? "entity" : country
        let phrase = "New band! \(cleanCountry), \(formatCallsignForSpeech(callsign)) on \(band)"
        enqueueAlert(priority: 3, message: phrase, callsign: callsign)
    }

    /// Dispatches an alert for a new Maidenhead grid square
    public func announceNewGrid(callsign: String, grid: String, band: String) {
        guard isEnabled && alertOnNewGrid else { return }
        let phoneticGrid = formatGridForSpeech(grid)
        let phrase = "New Grid! \(phoneticGrid) on \(band)"
        enqueueAlert(priority: 4, message: phrase, callsign: callsign)
    }

    /// Dispatches an alert when a station is directly calling the operator
    public func announceDirectedToMe(caller: String, snr: Int32, band: String) {
        guard isEnabled && alertOnDirectedToMe else { return }
        let phrase = "Calling you! \(formatCallsignForSpeech(caller)) at \(snr) D B on \(band)"
        enqueueAlert(priority: 1, message: phrase, callsign: caller)
    }

    /// Triggers a test voice announcement
    public func testVoiceAlert() {
        let voiceName: String
        if !selectedVoiceID.isEmpty, let v = AVSpeechSynthesisVoice(identifier: selectedVoiceID) {
            voiceName = v.name
        } else {
            voiceName = "Samantha"
        }
        let speedMultiplier = String(format: "%.1f", speechRate / 0.5)
        let sample = "YAAM Voice Alert active. Voice is \(voiceName), speed \(speedMultiplier)x. New DXCC Japan, Juliet Alpha One Alpha Bravo Charlie on 20 meters."
        speakNow(sample)
    }

    // MARK: - Queue & Speech Processing

    private func enqueueAlert(priority: Int, message: String, callsign: String) {
        cleanSpokenHistory()

        // Debounce: don't repeat the same callsign within history retention window
        if let lastSpoken = spokenHistory[callsign], Date().timeIntervalSince(lastSpoken) < historyRetentionSeconds {
            return
        }

        spokenHistory[callsign] = Date()
        recentAlertsCount += 1

        let alert = QueuedAlert(priority: priority, message: message, callsign: callsign, timestamp: Date())
        pendingQueue.append(alert)
        pendingQueue.sort()

        // Keep maximum 3 alerts in queue to avoid speech runaway
        if pendingQueue.count > 3 {
            pendingQueue = Array(pendingQueue.prefix(3))
        }

        processNextAlert()
    }

    private func processNextAlert() {
        guard !synthesizer.isSpeaking && !isProcessingQueue else { return }
        guard !pendingQueue.isEmpty else { return }

        isProcessingQueue = true
        let alert = pendingQueue.removeFirst()

        if playChimeFirst {
            NSSound.beep()
        }

        speakNow(alert.message)
    }

    private func speakNow(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = Float(max(0.1, min(1.0, speechRate)))
        utterance.volume = Float(max(0.1, min(1.0, speechVolume)))
        utterance.pitchMultiplier = 1.0

        if !selectedVoiceID.isEmpty, let matchedVoice = AVSpeechSynthesisVoice(identifier: selectedVoiceID) {
            utterance.voice = matchedVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        lastSpokenMessage = text
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isProcessingQueue = false
            // Small pause between multiple queued alerts
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.processNextAlert()
        }
    }

    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.isProcessingQueue = false
        }
    }

    public func stopSpeaking() {
        pendingQueue.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isProcessingQueue = false
    }

    // MARK: - Formatting Helpers

    private func formatCallsignForSpeech(_ call: String) -> String {
        let clean = call.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var spoken = ""
        for char in clean {
            spoken.append("\(char) ")
        }
        return clean.count <= 6 ? clean : spoken.trimmingCharacters(in: .whitespaces)
    }

    private func formatGridForSpeech(_ grid: String) -> String {
        let clean = grid.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 4 else { return clean }
        let chars = Array(clean)
        return "\(chars[0]) \(chars[1]) \(chars[2]) \(chars[3])"
    }

    private func cleanSpokenHistory() {
        let now = Date()
        spokenHistory = spokenHistory.filter { now.timeIntervalSince($0.value) < historyRetentionSeconds }
    }
}
