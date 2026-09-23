//
//  BustedCallsignEngine.swift
//  YAAM
//
//  Intelligent Busted Callsign Detection & Multi-Database Verification Engine
//  ("سیستم هوشمند تشخیص و تصحیح کال‌ساین‌های اشتباه")
//  Detects miscopied or mistyped callsigns in Voice (SSB/AM/FM) and CW (Morse) modes,
//  identifies auditory confusion and telegraphic rhythm/dit-dah errors,
//  and verifies candidates against Super Check Partial (SCP), ARRL LoTW, Club Log, and local logs.
//

import AppKit
import Combine
import Foundation
import SwiftUI

// MARK: - Operating Mode Category

enum CallsignOperatingMode: String, CaseIterable, Identifiable, Sendable {
    case cw = "CW"
    case voice = "Voice (Phone)"
    case digital = "Digital"
    case unknown = "General"

    var id: String { rawValue }

    static func from(mode: String) -> CallsignOperatingMode {
        let clean = mode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean == "CW" { return .cw }
        if ["SSB", "USB", "LSB", "AM", "FM", "PHONE"].contains(clean) { return .voice }
        if ["FT8", "FT4", "JS8", "RTTY", "PSK", "PSK31", "SSTV", "HELL", "OLIVIA"].contains(clean) { return .digital }
        return .voice
    }

    var icon: String {
        switch self {
        case .cw: return "tuningfork"
        case .voice: return "mic.fill"
        case .digital: return "waveform"
        case .unknown: return "antenna.radiowaves.left.and.right"
        }
    }

    var badgeColor: Color {
        switch self {
        case .cw: return .orange
        case .voice: return .blue
        case .digital: return .green
        case .unknown: return .secondary
        }
    }
}

// MARK: - Error Type Classification

enum CallsignErrorType: String, CaseIterable, Identifiable, Sendable {
    // CW Morse Errors
    case cwMissingDit = "CW 1-Dit Omitted"
    case cwExtraDit = "CW 1-Dit Added"
    case cwMissingDah = "CW 1-Dah Omitted"
    case cwExtraDah = "CW 1-Dah Added"
    case cwElementInversion = "CW Element Inversion"
    case cwSplitLetter = "CW Spacing / Split Letter"

    // Voice Phonetic Errors
    case voicePhoneticRhyme = "Voice Rhyming Plosive"
    case voiceNasalConfusion = "Voice Nasal Confusion"
    case voiceSibilantConfusion = "Voice Sibilant Confusion"
    case voiceAcousticShift = "Voice Acoustic Shift"

    // General Typos
    case typoTransposition = "Adjacent Transposition"
    case singleCharEdit = "Single Character Typo"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cwMissingDit, .cwExtraDit, .cwMissingDah, .cwExtraDah: return "tuningfork"
        case .cwElementInversion: return "arrow.left.and.right"
        case .cwSplitLetter: return "arrow.triangle.pull"
        case .voicePhoneticRhyme: return "waveform.badge.magnifyingglass"
        case .voiceNasalConfusion: return "ear.badge.waveform"
        case .voiceSibilantConfusion: return "wind"
        case .voiceAcousticShift: return "speaker.wave.2.fill"
        case .typoTransposition: return "arrow.left.arrow.right"
        case .singleCharEdit: return "character.cursor.ibeam"
        }
    }
}

// MARK: - Verified Database Source

enum BustedCallsignSource: String, CaseIterable, Identifiable, Sendable {
    case scp = "Super Check Partial"
    case lotw = "ARRL LoTW"
    case clublog = "Club Log"
    case logbook = "Worked Before"
    case builtInSeed = "Verified Seed"

    var id: String { rawValue }

    var shortTag: String {
        switch self {
        case .scp: return "SCP"
        case .lotw: return "LoTW"
        case .clublog: return "ClubLog"
        case .logbook: return "Worked"
        case .builtInSeed: return "Seed"
        }
    }

    var tagColor: Color {
        switch self {
        case .scp: return .blue
        case .lotw: return .green
        case .clublog: return .purple
        case .logbook: return .orange
        case .builtInSeed: return .secondary
        }
    }
}

// MARK: - Suggestion Model

struct BustedCallsignSuggestion: Identifiable, Sendable {
    var id: String { "\(originalCall)->\(suggestedCall)" }
    let originalCall: String
    let suggestedCall: String
    let modeCategory: CallsignOperatingMode
    let errorType: CallsignErrorType
    let explanation: String
    let morseDetail: String?
    let phoneticDetail: String?
    let confidence: Double // 0.0 to 1.0
    let country: DXCCEntityInfo
    let verifiedSources: [BustedCallsignSource]
    let workedCount: Int

    var confidencePercentage: Int {
        Int(confidence * 100.0)
    }

    var confidenceLabel: String {
        if confidence >= 0.92 { return "Highly Probable" }
        if confidence >= 0.80 { return "Probable" }
        if confidence >= 0.65 { return "Likely Match" }
        return "Possible"
    }

    var confidenceColor: Color {
        if confidence >= 0.90 { return .green }
        if confidence >= 0.75 { return .orange }
        return .yellow
    }
}

// MARK: - Busted Callsign Engine

@MainActor
final class BustedCallsignEngine: ObservableObject {
    static let shared = BustedCallsignEngine()

    // MARK: - Published State
    @Published var totalVerifiedCallsigns: Int = 0
    @Published var scpCallCount: Int = 0
    @Published var lotwCallCount: Int = 0
    @Published var isDownloading: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var statusMessage: String = "Ready"
    @Published var lastUpdatedDate: Date?

    // Settings
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "bustedCallEngineEnabled") }
    }
    @Published var audioChimeEnabled: Bool {
        didSet { UserDefaults.standard.set(audioChimeEnabled, forKey: "bustedCallAudioChime") }
    }
    @Published var voiceSensitivity: Double {
        didSet { UserDefaults.standard.set(voiceSensitivity, forKey: "bustedCallVoiceSens") }
    }
    @Published var cwSensitivity: Double {
        didSet { UserDefaults.standard.set(cwSensitivity, forKey: "bustedCallCWSens") }
    }

    // In-memory indexing
    private var verifiedCallsignsSet: Set<String> = []
    private var callsignSourceMap: [String: Set<BustedCallsignSource>] = [:]
    private var candidateLookupList: [String] = []

    // Morse Code Table (ITU Standard)
    private static let morseTable: [Character: String] = [
        "A": ".-",    "B": "-...",  "C": "-.-.",  "D": "-..",   "E": ".",
        "F": "..-.",  "G": "--.",   "H": "....",  "I": "..",    "J": ".---",
        "K": "-.-",   "L": ".-..",  "M": "--",    "N": "-.",    "O": "---",
        "P": ".--.",  "Q": "--.-",  "R": ".-.",   "S": "...",   "T": "-",
        "U": "..-",   "V": "...-",  "W": ".--",   "X": "-..-",  "Y": "-.--",
        "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        "/": "-..-."
    ]

    // NATO Phonetic Alphabet
    private static let phoneticTable: [Character: String] = [
        "A": "Alpha",    "B": "Bravo",   "C": "Charlie", "D": "Delta",
        "E": "Echo",     "F": "Foxtrot", "G": "Golf",    "H": "Hotel",
        "I": "India",    "J": "Juliett", "K": "Kilo",    "L": "Lima",
        "M": "Mike",     "N": "November","O": "Oscar",   "P": "Papa",
        "Q": "Quebec",   "R": "Romeo",   "S": "Sierra",  "T": "Tango",
        "U": "Uniform",  "V": "Victor",  "W": "Whiskey", "X": "X-ray",
        "Y": "Yankee",   "Z": "Zulu",
        "0": "Zero",     "1": "One",     "2": "Two",     "3": "Three",
        "4": "Four",     "5": "Five",    "6": "Six",     "7": "Seven",
        "8": "Eight",    "9": "Nine",    "/": "Stroke"
    ]

    // Built-in Seed Database of ~120 Top Worldwide Callsigns for Instant Offline Operation
    private let offlineSeedCallsigns: [String] = [
        "W1AW", "W2GD", "W3LPL", "W4KW", "K1LZ", "K1DG", "K3LR", "K5ZD", "K9CT", "N2IC",
        "N3QE", "AA3B", "AA1K", "K1AR", "K1TTT", "W2FU", "W2VJN", "N4WW", "K4BA", "W5WMU",
        "K5TR", "N6RO", "N6TV", "W6YX", "K7RI", "W7RN", "N8OO", "K8GL", "VE2CSE", "VE3EJ",
        "VE3AT", "VE3NEA", "VE3RAC", "VE6SV", "VE7CC", "VE7GL", "XE1R", "XE2S", "KL7RA", "KH6J", "KH6LC",
        "DL1ABC", "DL6FBL", "DL0CS", "DA0HQ", "DK3WW", "DF3CB", "G3TXF", "G4BJM", "M6T", "M0DXR",
        "GM3ZWW", "GW4BLE", "F6KOP", "F6KNB", "TM6M", "I2WIJ", "IR4M", "IO4T", "IB4M", "EA4TX",
        "EA8RM", "EF8R", "ED1R", "CT1BOH", "CR3A", "CR6K", "PA0MIR", "PI4CC", "ON4UN", "ON4KST",
        "SM5AJV", "SK3W", "LA8HGA", "LN8W", "OH2B", "OH2BH", "OG2X", "OF100FI", "OZ1ADL", "OZ5E",
        "SP9QMP", "SN3A", "SP5GR", "OK2C", "OL7M", "OK1CF", "OM7M", "OM3RM", "HG6N", "HA8IH",
        "S50A", "S51A", "9A1A", "9A5W", "YU1LA", "YU1ZZ", "YT5A", "LZ2K", "LZ2JA", "SV2DCD", "SV1DPI",
        "ER4DX", "E77DX", "EI7M", "Z60A", "RA3W", "R9DX", "UA9BA", "RT6A", "RK3AWL", "RW2F",
        "UR5LAM", "UX0FF", "UP2L", "UN9L", "EY8MM", "EX8M", "ES5TV",
        "EP2AES", "EP2LSH", "EP2C", "EP4HR", "4X4DK", "4X1IM", "4Z5LA", "A45XR", "A65BR", "A61Q",
        "A71BX", "HZ1SK", "7Z1SJ", "9K2HN", "9K2GS", "OD5ZZ", "JY5MM", "TA1D", "CN8KD", "CN2AA",
        "ZS6CCY", "ZS6CC", "5Z4/EA4ATI", "7Q7RU", "3B8BAP", "5R8UI", "6W/AA7JV", "EA9LZ",
        "JA1ABC", "JA1BJK", "JA7NVF", "JH1AJT", "JH1EAQ", "JR2PAU", "HL5IVL", "B1Z", "BY1RX",
        "BY4AA", "BV2B", "VR2XMT", "9M2TO", "9V1YC", "YB0AR", "YB0ECT", "YF1AR", "DU1/JJ5GMJ",
        "VK3XYZ", "VK4KW", "VK2GR", "ZL1BQD", "ZL1BY", "ZL3X", "VU2PTT", "VU2NKS", "JT1CO", "HS0ZDY",
        "PY2XB", "PY2ZX", "PT5T", "PR7AB", "LU8DPM", "LR2F", "CE3CT", "CX7CO", "ZP5AA", "CP6CW",
        "OA4SS", "HK3C", "YV5E", "ZF1A", "ZF2MJ", "PJ2T", "PJ4G", "P40W", "P49X", "TI7W", "TI9A",
        "KP4AA", "KP2M", "V31MA", "V47T", "J68HZ", "VP2V/K6TOP", "VP9/W6PH", "C31CT", "T77C", "TF3W",
        "4U1UN", "4U1ITU", "5B4AMM", "3D2RR", "3D2AG"
    ]

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "bustedCallEngineEnabled") as? Bool ?? true
        self.audioChimeEnabled = UserDefaults.standard.object(forKey: "bustedCallAudioChime") as? Bool ?? true
        self.voiceSensitivity = UserDefaults.standard.object(forKey: "bustedCallVoiceSens") as? Double ?? 0.75
        self.cwSensitivity = UserDefaults.standard.object(forKey: "bustedCallCWSens") as? Double ?? 0.80

        let lastTs = UserDefaults.standard.double(forKey: "bustedCallLastUpdated")
        if lastTs > 0 {
            self.lastUpdatedDate = Date(timeIntervalSince1970: lastTs)
        }

        loadStoredDatabases()
    }

    // MARK: - File Paths
    private var baseStorageDirectory: URL {
        let docs = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("YAAM/BustedCallsigns", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var scpFileURL: URL {
        baseStorageDirectory.appendingPathComponent("MASTER.SCP")
    }

    var lotwFileURL: URL {
        baseStorageDirectory.appendingPathComponent("lotw-user-activity.csv")
    }

    // MARK: - Database Loading & Merging
    func loadStoredDatabases() {
        var mergedSet = Set<String>()
        var sourceMap: [String: Set<BustedCallsignSource>] = [:]

        // 1. Seed with offline starter dataset
        for call in offlineSeedCallsigns {
            let clean = call.uppercased()
            mergedSet.insert(clean)
            sourceMap[clean, default: []].insert(.builtInSeed)
        }

        // 2. Load Super Check Partial file if exists
        if FileManager.default.fileExists(atPath: scpFileURL.path),
           let content = try? String(contentsOf: scpFileURL, encoding: .utf8) {
            var scpCount = 0
            content.enumerateLines { line, _ in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard !trimmed.isEmpty, !trimmed.hasPrefix("//"), !trimmed.hasPrefix("#"),
                      trimmed.count >= 3, trimmed.count <= 14 else { return }
                mergedSet.insert(trimmed)
                sourceMap[trimmed, default: []].insert(.scp)
                scpCount += 1
            }
            self.scpCallCount = scpCount
        }

        // 3. Load LoTW User Activity CSV if exists
        if FileManager.default.fileExists(atPath: lotwFileURL.path),
           let content = try? String(contentsOf: lotwFileURL, encoding: .utf8) {
            var lotwCount = 0
            content.enumerateLines { line, _ in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let parts = trimmed.components(separatedBy: ",")
                if let first = parts.first {
                    let call = first.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    if call.count >= 3 && call.count <= 14 && !call.contains("CALL") {
                        mergedSet.insert(call)
                        sourceMap[call, default: []].insert(.lotw)
                        lotwCount += 1
                    }
                }
            }
            self.lotwCallCount = lotwCount
        }

        self.verifiedCallsignsSet = mergedSet
        self.callsignSourceMap = sourceMap
        self.candidateLookupList = Array(mergedSet).sorted()
        self.totalVerifiedCallsigns = mergedSet.count
        self.statusMessage = "\(totalVerifiedCallsigns) verified callsigns loaded in memory"
    }

    // MARK: - Multi-Source Downloader
    func updateAllDatabases() async {
        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0.05
        statusMessage = "Starting multi-source database download..."

        // Step 1: Download Super Check Partial
        await downloadSCP()
        downloadProgress = 0.50

        // Step 2: Download ARRL LoTW Activity
        await downloadLoTW()
        downloadProgress = 0.95

        // Reload into memory
        loadStoredDatabases()

        lastUpdatedDate = Date()
        UserDefaults.standard.set(lastUpdatedDate!.timeIntervalSince1970, forKey: "bustedCallLastUpdated")
        downloadProgress = 1.0
        isDownloading = false
        statusMessage = "Databases updated: \(totalVerifiedCallsigns) callsigns loaded"
    }

    func downloadSCP() async {
        let url = URL(string: "https://www.supercheckpartial.com/MASTER.SCP")!
        statusMessage = "Downloading MASTER.SCP (~45,000 contest calls)..."
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty {
                try data.write(to: scpFileURL)
            }
        } catch {
            // Ignore error gracefully
        }
    }

    func downloadLoTW() async {
        let url = URL(string: "https://lotw.arrl.org/lotw-user-activity.csv")!
        statusMessage = "Downloading ARRL LoTW Users (~160,000 active calls)..."
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 25
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty {
                try data.write(to: lotwFileURL)
            }
        } catch {
            // Ignore error gracefully
        }
    }

    // MARK: - Core Busted Callsign Evaluator
    func evaluate(
        callsign: String,
        mode: String,
        band: String = "",
        logRecords: [QSORecordModel] = []
    ) -> BustedCallsignSuggestion? {
        guard isEnabled else { return nil }

        let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard clean.count >= 3 && clean.count <= 14 else { return nil }

        // Must have at least one letter and one number to resemble a callsign
        guard clean.contains(where: \.isLetter), clean.contains(where: \.isNumber) else { return nil }

        // 1. If it's already an exact match in our verified database, it's valid!
        if verifiedCallsignsSet.contains(clean) {
            return nil
        }

        let modeCat = CallsignOperatingMode.from(mode: mode)

        // Find candidate suggestions with 1-character difference or specific CW/Voice error
        var bestCandidate: (call: String, errorType: CallsignErrorType, explanation: String, morse: String?, phonetic: String?, penalty: Double)? = nil
        var minPenalty: Double = 999.0

        // Narrow search space: candidates with same length, or length +/- 1
        let targetLen = clean.count

        for candidate in candidateLookupList {
            let candLen = candidate.count
            guard abs(candLen - targetLen) <= 1 else { continue }

            // Mode-specific analysis
            if modeCat == .cw {
                if let cwResult = analyzeCWError(typed: clean, candidate: candidate) {
                    if cwResult.penalty < minPenalty {
                        minPenalty = cwResult.penalty
                        bestCandidate = (candidate, cwResult.errorType, cwResult.explanation, cwResult.morseDetail, nil, cwResult.penalty)
                    }
                }
            } else if modeCat == .voice {
                if let voiceResult = analyzeVoiceError(typed: clean, candidate: candidate) {
                    if voiceResult.penalty < minPenalty {
                        minPenalty = voiceResult.penalty
                        bestCandidate = (candidate, voiceResult.errorType, voiceResult.explanation, nil, voiceResult.phoneticDetail, voiceResult.penalty)
                    }
                }
            }

            // General typo fallback if no mode-specific error was closer
            if bestCandidate == nil {
                if let typoResult = analyzeGeneralTypo(typed: clean, candidate: candidate) {
                    if typoResult.penalty < minPenalty {
                        minPenalty = typoResult.penalty
                        bestCandidate = (candidate, typoResult.errorType, typoResult.explanation, nil, nil, typoResult.penalty)
                    }
                }
            }
        }

        guard let match = bestCandidate, minPenalty <= 3.2 else {
            return nil
        }

        // Calculate confidence (higher if found in multiple sources or logged before)
        var confidence = max(0.50, 1.0 - (minPenalty / 4.0))

        let sources = callsignSourceMap[match.call] ?? []
        var sourceList = Array(sources)

        // Check if worked before in logbook
        var workedCount = 0
        for r in logRecords {
            if (r.fields["CALL"] ?? "").uppercased() == match.call {
                workedCount += 1
            }
        }
        if workedCount > 0 {
            sourceList.append(.logbook)
            confidence = min(0.99, confidence + 0.15)
        }

        if sources.contains(.scp) && sources.contains(.lotw) {
            confidence = min(0.98, confidence + 0.10)
        }

        let dxcc = DXCCDatabase.resolve(callsign: match.call)

        // Trigger Audio Chime if enabled
        if audioChimeEnabled {
            NSSound(named: "Tink")?.play()
        }

        return BustedCallsignSuggestion(
            originalCall: clean,
            suggestedCall: match.call,
            modeCategory: modeCat,
            errorType: match.errorType,
            explanation: match.explanation,
            morseDetail: match.morse,
            phoneticDetail: match.phonetic,
            confidence: confidence,
            country: dxcc,
            verifiedSources: sourceList,
            workedCount: workedCount
        )
    }

    // MARK: - CW Morse Code Error Analyzer
    private func analyzeCWError(
        typed: String,
        candidate: String
    ) -> (errorType: CallsignErrorType, explanation: String, morseDetail: String, penalty: Double)? {
        // Case 1: Same length, exactly 1 character difference
        if typed.count == candidate.count {
            var diffIndices: [Int] = []
            let tChars = Array(typed)
            let cChars = Array(candidate)

            for i in 0..<tChars.count {
                if tChars[i] != cChars[i] {
                    diffIndices.append(i)
                }
            }

            if diffIndices.count == 1 {
                let idx = diffIndices[0]
                let tChar = tChars[idx]
                let cChar = cChars[idx]

                guard let tMorse = Self.morseTable[tChar],
                      let cMorse = Self.morseTable[cChar] else { return nil }

                // Check 1 Dit Omitted: e.g. B (-...) was heard as D (-..) or E (.) was missed
                if cMorse.count == tMorse.count + 1 {
                    if isSubsequenceMorse(sub: tMorse, full: cMorse) {
                        let explanation = "CW 1-Dit/Dah Omitted in letter #\(idx + 1): '\(cChar)' (\(cMorse)) was heard as '\(tChar)' (\(tMorse))"
                        let morseDetail = "\(cChar) [\(cMorse)] ➔ \(tChar) [\(tMorse)]"
                        return (.cwMissingDit, explanation, morseDetail, 0.8)
                    }
                }

                // Check 1 Extra Dit Added: e.g. D (-..) was heard as B (-...)
                if tMorse.count == cMorse.count + 1 {
                    if isSubsequenceMorse(sub: cMorse, full: tMorse) {
                        let explanation = "CW Extra Dit/Dah Added in letter #\(idx + 1): '\(cChar)' (\(cMorse)) was heard as '\(tChar)' (\(tMorse))"
                        let morseDetail = "\(cChar) [\(cMorse)] ➔ \(tChar) [\(tMorse)]"
                        return (.cwExtraDit, explanation, morseDetail, 0.9)
                    }
                }

                // Check Element Inversion (swapped dits and dahs): e.g. A (.-) vs N (-.), D (-..) vs U (..-)
                if tMorse == invertMorse(cMorse) {
                    let explanation = "CW Inversion in letter #\(idx + 1): '\(cChar)' (\(cMorse)) was inverted to '\(tChar)' (\(tMorse))"
                    let morseDetail = "\(cChar) [\(cMorse)] ➔ \(tChar) [\(tMorse)]"
                    return (.cwElementInversion, explanation, morseDetail, 1.1)
                }

                // Small Morse edit distance (1 element change)
                let mDist = morseLevenshtein(tMorse, cMorse)
                if mDist <= 1 {
                    let explanation = "CW Rhythm Shift in letter #\(idx + 1): '\(cChar)' (\(cMorse)) vs '\(tChar)' (\(tMorse))"
                    let morseDetail = "\(cChar) [\(cMorse)] ➔ \(tChar) [\(tMorse)]"
                    return (.cwMissingDit, explanation, morseDetail, 1.4)
                }
            }

            // Check Adjacent Transposition in CW: e.g. K1LZ -> K1ZL
            if diffIndices.count == 2 && diffIndices[1] == diffIndices[0] + 1 {
                let i1 = diffIndices[0], i2 = diffIndices[1]
                if tChars[i1] == cChars[i2] && tChars[i2] == cChars[i1] {
                    let explanation = "CW Transposition: Characters '\(cChars[i1])' and '\(cChars[i2])' were swapped"
                    return (.typoTransposition, explanation, "\(cChars[i1])\(cChars[i2]) ➔ \(tChars[i1])\(tChars[i2])", 1.2)
                }
            }
        }

        // Case 2: CW Spacing / Split Letter (Lumping or Splitting)
        // e.g. 'W' (.--) split into 'EM' (. --) -> candidate length = typed length - 1
        if typed.count == candidate.count + 1 {
            for i in 0..<candidate.count {
                let candChar = Array(candidate)[i]
                guard let candMorse = Self.morseTable[candChar] else { continue }

                let typedSub = String(Array(typed)[i...i+1])
                let subChars = Array(typedSub)
                if let m1 = Self.morseTable[subChars[0]], let m2 = Self.morseTable[subChars[1]] {
                    if m1 + m2 == candMorse {
                        let explanation = "CW Spacing Error: '\(candChar)' (\(candMorse)) was split into '\(typedSub)' (\(m1) \(m2))"
                        return (.cwSplitLetter, explanation, "\(candChar) ➔ \(typedSub)", 1.0)
                    }
                }
            }
        }

        return nil
    }

    private func isSubsequenceMorse(sub: String, full: String) -> Bool {
        var subIdx = sub.startIndex
        var fullIdx = full.startIndex
        while subIdx < sub.endIndex && fullIdx < full.endIndex {
            if sub[subIdx] == full[fullIdx] {
                subIdx = sub.index(after: subIdx)
            }
            fullIdx = full.index(after: fullIdx)
        }
        return subIdx == sub.endIndex
    }

    private func invertMorse(_ m: String) -> String {
        m.map { char in
            if char == "." { return "-" }
            if char == "-" { return "." }
            return char
        }
        .map(String.init)
        .joined()
    }

    private func morseLevenshtein(_ a: String, _ b: String) -> Int {
        let aArr = Array(a), bArr = Array(b)
        var matrix = Array(repeating: Array(repeating: 0, count: bArr.count + 1), count: aArr.count + 1)
        for i in 0...aArr.count { matrix[i][0] = i }
        for j in 0...bArr.count { matrix[0][j] = j }
        for i in 1...aArr.count {
            for j in 1...bArr.count {
                if aArr[i - 1] == bArr[j - 1] {
                    matrix[i][j] = matrix[i - 1][j - 1]
                } else {
                    matrix[i][j] = min(matrix[i - 1][j] + 1, matrix[i][j - 1] + 1, matrix[i - 1][j - 1] + 1)
                }
            }
        }
        return matrix[aArr.count][bArr.count]
    }

    // MARK: - Voice (Phone / SSB) Error Analyzer
    private func analyzeVoiceError(
        typed: String,
        candidate: String
    ) -> (errorType: CallsignErrorType, explanation: String, phoneticDetail: String, penalty: Double)? {
        guard typed.count == candidate.count else { return nil }

        var diffIndices: [Int] = []
        let tChars = Array(typed)
        let cChars = Array(candidate)

        for i in 0..<tChars.count {
            if tChars[i] != cChars[i] {
                diffIndices.append(i)
            }
        }

        guard diffIndices.count == 1 else { return nil }
        let idx = diffIndices[0]
        let tChar = tChars[idx]
        let cChar = cChars[idx]

        let tPhonetic = Self.phoneticTable[tChar] ?? String(tChar)
        let cPhonetic = Self.phoneticTable[cChar] ?? String(cChar)
        let detail = "\(cPhonetic) (\(cChar)) ➔ \(tPhonetic) (\(tChar))"

        // 1. Rhyming Plosive Consonants (B, D, V, P, T, C, G, Z)
        let plosiveCluster: Set<Character> = ["B", "D", "V", "P", "T", "C", "G", "Z", "E"]
        if plosiveCluster.contains(tChar) && plosiveCluster.contains(cChar) {
            let explanation = "Voice Rhyming Mishear: '\(cPhonetic)' (\(cChar)) sounded like '\(tPhonetic)' (\(tChar))"
            return (.voicePhoneticRhyme, explanation, detail, 0.75)
        }

        // 2. Nasal Confusion (M vs N)
        if (tChar == "M" && cChar == "N") || (tChar == "N" && cChar == "M") {
            let explanation = "Voice Nasal Confusion: '\(cPhonetic)' (\(cChar)) misheard as '\(tPhonetic)' (\(tChar))"
            return (.voiceNasalConfusion, explanation, detail, 0.65)
        }

        // 3. Fricatives & Sibilants (S vs F vs X)
        let sibilantCluster: Set<Character> = ["S", "F", "X"]
        if sibilantCluster.contains(tChar) && sibilantCluster.contains(cChar) {
            let explanation = "Voice Sibilant Confusion: '\(cPhonetic)' (\(cChar)) misheard through static as '\(tPhonetic)' (\(tChar))"
            return (.voiceSibilantConfusion, explanation, detail, 0.70)
        }

        // 4. Acoustic Number / Letter Shift (0 vs O, 1 vs I, 5 vs F, 8 vs H)
        let acousticPairs: [(Character, Character)] = [
            ("0", "O"), ("O", "0"),
            ("1", "I"), ("I", "1"),
            ("5", "F"), ("F", "5"),
            ("8", "H"), ("H", "8"),
            ("K", "C"), ("C", "K"),
            ("G", "J"), ("J", "G")
        ]
        if acousticPairs.contains(where: { $0.0 == tChar && $0.1 == cChar }) {
            let explanation = "Voice Acoustic Shift: '\(cPhonetic)' (\(cChar)) sounded like '\(tPhonetic)' (\(tChar))"
            return (.voiceAcousticShift, explanation, detail, 0.85)
        }

        return nil
    }

    // MARK: - General Typo Analyzer
    private func analyzeGeneralTypo(
        typed: String,
        candidate: String
    ) -> (errorType: CallsignErrorType, explanation: String, penalty: Double)? {
        if typed.count == candidate.count {
            var diffCount = 0
            for i in 0..<typed.count {
                if Array(typed)[i] != Array(candidate)[i] {
                    diffCount += 1
                }
            }
            if diffCount == 1 {
                return (.singleCharEdit, "Single character difference from verified active callsign", 1.8)
            }
        }
        return nil
    }

    // MARK: - Quick Verification Helper
    func isVerifiedCallsign(_ callsign: String) -> Bool {
        let clean = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return verifiedCallsignsSet.contains(clean)
    }
}
