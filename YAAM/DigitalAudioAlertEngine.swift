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

    // MARK: - User Settings (AppStorage-backed)
    @AppStorage("audioAlertsEnabled") public var isEnabled: Bool = true
    @AppStorage("audioAlertNewDXCC") public var alertOnNewDXCC: Bool = true
    @AppStorage("audioAlertNewBand") public var alertOnNewBand: Bool = true
    @AppStorage("audioAlertNewGrid") public var alertOnNewGrid: Bool = true
    @AppStorage("audioAlertDirectedToMe") public var alertOnDirectedToMe: Bool = true
    @AppStorage("audioAlertChimeFirst") public var playChimeFirst: Bool = true
    @AppStorage("audioAlertSpeechRate") public var speechRate: Double = 0.52
    @AppStorage("audioAlertSpeechVolume") public var speechVolume: Double = 1.0
    @AppStorage("audioAlertVoiceID") public var selectedVoiceID: String = ""

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
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Available System Voices
    public var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.starts(with: "en")
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
        let sample = "YAAM Voice Alert active. New DXCC Fiji, Three Delta Two Romeo Romeo on 20 meters."
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
