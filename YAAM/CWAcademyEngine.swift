//
//  CWAcademyEngine.swift
//  YAAM
//
//  Scientific Morse Code Learning & Ear-Training Engine
//  Implements the 40-step Koch Method, Farnsworth timing spacing,
//  Callsign Sprint (RufzXP style), common ham abbreviations, and progression tracking.
//

import AVFoundation
import Combine
import Foundation

public enum CWTrainingMode: String, CaseIterable, Identifiable, Sendable {
    case kochLessons = "Koch Method (Levels 1–40)"
    case callsignSprint = "Callsign Sprint (Contest/DX)"
    case commonWords = "Common Words & Abbreviations"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .kochLessons: return "Koch Method"
        case .callsignSprint: return "Callsign Sprint"
        case .commonWords: return "Vocabulary"
        }
    }

    public var subtitle: String {
        switch self {
        case .kochLessons: return "Progressive 40-step sequence"
        case .callsignSprint: return "Contest prefixes & suffixes"
        case .commonWords: return "Essential Q-codes and QSO terms"
        }
    }

    public var iconName: String {
        switch self {
        case .kochLessons: return "graduationcap.fill"
        case .callsignSprint: return "bolt.horizontal.fill"
        case .commonWords: return "text.bubble.fill"
        }
    }
}

public struct CWLessonTrial: Identifiable, Sendable {
    public let id = UUID()
    public let targetText: String
    public let userInput: String
    public let isCorrect: Bool
    public let timestamp: Date
}

@MainActor
public final class CWAcademyEngine: ObservableObject {
    public static let shared = CWAcademyEngine()

    // MARK: - Koch Sequence (Standard 40-character international order)
    public static let kochSequence: [Character] = [
        "K", "M", "R", "S", "U", "A", "P", "T", "L", "O",
        "W", "I", ".", "N", "J", "E", "F", "0", "Y", "V",
        ",", "G", "5", "/", "Q", "9", "Z", "H", "3", "8",
        "B", "?", "4", "2", "7", "C", "1", "D", "6", "X"
    ]

    // MARK: - Published State
    @Published public var mode: CWTrainingMode = .kochLessons
    @Published public var kochLevel: Int = 2 // 2...40 (Starts with K & M)
    @Published public var characterWPM: Int = 22 // Acoustic sound speed
    @Published public var effectiveWPM: Int = 14 // Farnsworth spacing speed
    @Published public var sidetonePitchHz: Double = 650.0

    // Active Challenge & Session
    @Published public var currentPrompt: String = ""
    @Published public var lastPrompt: String = ""
    @Published public var isPlayingAudio: Bool = false
    @Published public var autoAdvanceOnSuccess: Bool = true
    @Published public var autoPlayNext: Bool = true

    // Scoring & Statistics
    @Published public var trialsCount: Int = 0
    @Published public var correctCount: Int = 0
    @Published public var currentStreak: Int = 0
    @Published public var bestStreak: Int = 0
    @Published public var recentTrials: [CWLessonTrial] = []
    @Published public var eligibleForLevelUp: Bool = false

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var playTask: Task<Void, Never>?

    public init() {
        let savedLevel = UserDefaults.standard.integer(forKey: "cwAcademyKochLevel")
        self.kochLevel = (savedLevel >= 2 && savedLevel <= 40) ? savedLevel : 2
        let savedCharWPM = UserDefaults.standard.integer(forKey: "cwAcademyCharWPM")
        self.characterWPM = savedCharWPM >= 14 ? savedCharWPM : 22
        let savedEffWPM = UserDefaults.standard.integer(forKey: "cwAcademyEffWPM")
        self.effectiveWPM = savedEffWPM >= 8 ? savedEffWPM : 14
        self.bestStreak = UserDefaults.standard.integer(forKey: "cwAcademyBestStreak")

        setupAudioEngine()
        generateNewPrompt()
    }

    // MARK: - Audio Sidetone Setup

    @discardableResult
    private func ensureAudioEngineRunning() -> Bool {
        if let engine = audioEngine, let player = playerNode, engine.isRunning, player.isPlaying || true {
            return true
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)

        let mainMixer = engine.mainMixerNode
        let format = mainMixer.outputFormat(forBus: 0)
        engine.connect(player, to: mainMixer, format: format)

        do {
            try engine.start()
            self.audioEngine = engine
            self.playerNode = player
            return true
        } catch {
            print("CWAcademy audio engine init error: \(error)")
            return false
        }
    }

    private func setupAudioEngine() {
        _ = ensureAudioEngineRunning()
    }

    // MARK: - Prompt Generation

    public func generateNewPrompt() {
        lastPrompt = currentPrompt

        switch mode {
        case .kochLessons:
            let activeChars = Array(Self.kochSequence.prefix(kochLevel))
            // Generate a random 5-character group or 2 short words
            var group = ""
            for _ in 0..<5 {
                if let randomChar = activeChars.randomElement() {
                    group.append(randomChar)
                }
            }
            currentPrompt = group

        case .callsignSprint:
            currentPrompt = generateRealisticCallsign()

        case .commonWords:
            currentPrompt = Self.commonCWVocabulary.randomElement() ?? "73"
        }
    }

    public func generateRealisticCallsign() -> String {
        let prefixes = [
            "W", "K", "N", "AA", "AB", "AC", "VE", "VA", "G", "M", "DL", "DJ", "DK",
            "JA", "JH", "JR", "VK", "ZL", "F", "I", "IK", "EA", "EB", "SP", "PY", "LU",
            "OH", "SM", "LA", "OE", "HB9", "EP", "A6", "HZ", "9K", "JY", "4X"
        ]
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let prefix = prefixes.randomElement() ?? "DL"
        let digit = Int.random(in: 0...9)
        let suffixLen = Int.random(in: 1...3)
        var suffix = ""
        for _ in 0..<suffixLen {
            if let l = letters.randomElement() {
                suffix.append(l)
            }
        }
        return "\(prefix)\(digit)\(suffix)"
    }

    // MARK: - Verification & Scoring

    public func submitAnswer(_ answer: String) -> Bool {
        let cleanInput = answer.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleanTarget = currentPrompt.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let isMatch = (cleanInput == cleanTarget)

        trialsCount += 1
        if isMatch {
            correctCount += 1
            currentStreak += 1
            if currentStreak > bestStreak {
                bestStreak = currentStreak
                UserDefaults.standard.set(bestStreak, forKey: "cwAcademyBestStreak")
            }
        } else {
            currentStreak = 0
        }

        let trial = CWLessonTrial(
            targetText: cleanTarget,
            userInput: cleanInput,
            isCorrect: isMatch,
            timestamp: Date()
        )
        recentTrials.insert(trial, at: 0)
        if recentTrials.count > 20 {
            recentTrials.removeLast()
        }

        // Check Koch level-up eligibility: >= 90% in last 10 trials
        let lastTen = recentTrials.prefix(10)
        if lastTen.count >= 10 {
            let correctInTen = lastTen.filter(\.isCorrect).count
            eligibleForLevelUp = (Double(correctInTen) / Double(lastTen.count)) >= 0.9 && kochLevel < 40
        } else {
            eligibleForLevelUp = false
        }

        return isMatch
    }

    public func advanceKochLevel() {
        guard kochLevel < 40 else { return }
        kochLevel += 1
        UserDefaults.standard.set(kochLevel, forKey: "cwAcademyKochLevel")
        eligibleForLevelUp = false
        recentTrials.removeAll()
        generateNewPrompt()
    }

    public func resetLessonProgress() {
        trialsCount = 0
        correctCount = 0
        currentStreak = 0
        recentTrials.removeAll()
        eligibleForLevelUp = false
    }

    public var accuracyPercentage: Double {
        guard trialsCount > 0 else { return 100.0 }
        return (Double(correctCount) / Double(trialsCount)) * 100.0
    }

    public var activeCharacters: [Character] {
        return Array(Self.kochSequence.prefix(kochLevel))
    }

    public var nextCharacterToUnlock: Character? {
        guard kochLevel < Self.kochSequence.count else { return nil }
        return Self.kochSequence[kochLevel]
    }

    // MARK: - Farnsworth Morse Playback

    public func playCurrentPrompt() {
        playText(currentPrompt)
    }

    public func stopAudio() {
        playTask?.cancel()
        playTask = nil
        playerNode?.stop()
        isPlayingAudio = false
    }

    public func playText(_ text: String) {
        playMorseAudio(text: text, wpm: characterWPM)
    }

    public func playMorseAudio(text: String, wpm: Int) {
        stopAudio()
        guard ensureAudioEngineRunning(), let player = playerNode else { return }

        guard let buffer = synthesizeMorseBuffer(text: text, wpm: wpm, sidetoneHz: sidetonePitchHz) else { return }

        isPlayingAudio = true
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            Task { @MainActor [weak self] in
                self?.isPlayingAudio = false
            }
        }
        player.play()
    }

    private func synthesizeMorseBuffer(text: String, wpm: Int, sidetoneHz: Double, volume: Float = 0.28) -> AVAudioPCMBuffer? {
        guard let player = playerNode else { return nil }
        let format = player.outputFormat(forBus: 0)
        let sampleRate = format.sampleRate > 0 ? format.sampleRate : 48000.0
        let channels = Int(format.channelCount)
        guard channels > 0 else { return nil }

        let ditDuration = 1.2 / Double(max(5, wpm))
        let ditFrames = max(1, Int(ditDuration * sampleRate))
        let dahFrames = ditFrames * 3
        let intraCharSpaceFrames = ditFrames
        let interCharSpaceFrames = ditFrames * 3
        let wordSpaceFrames = ditFrames * 7
        let rampFrames = max(1, min(Int(sampleRate * 0.005), ditFrames / 3)) // 5ms soft cosine ramp

        var blocks: [(isTone: Bool, frames: Int)] = []
        let morseTable = CWKeyerService.morseAlphabet
        let cleanText = text.uppercased()

        for (charIdx, char) in cleanText.enumerated() {
            if char == " " {
                blocks.append((false, wordSpaceFrames))
                continue
            }
            guard let pattern = morseTable[char] else { continue }

            for (symIdx, sym) in pattern.enumerated() {
                if sym == "." {
                    blocks.append((true, ditFrames))
                } else if sym == "-" {
                    blocks.append((true, dahFrames))
                }
                if symIdx < pattern.count - 1 {
                    blocks.append((false, intraCharSpaceFrames))
                }
            }

            if charIdx < cleanText.count - 1 {
                blocks.append((false, interCharSpaceFrames))
            }
        }

        let totalFrames = blocks.reduce(0) { $0 + $1.frames }
        guard totalFrames > 0 else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)) else { return nil }
        buffer.frameLength = AVAudioFrameCount(totalFrames)

        var monoSamples = [Float](repeating: 0, count: totalFrames)
        var writePos = 0
        let omega = 2.0 * .pi * sidetoneHz / sampleRate
        var phase: Double = 0.0

        for block in blocks {
            let frames = block.frames
            if !block.isTone {
                writePos += frames
                phase = 0.0
            } else {
                let rf = min(rampFrames, frames / 2)
                for f in 0..<frames {
                    let s = Float(sin(phase)) * volume
                    var env: Float = 1.0
                    if f < rf {
                        env = 0.5 * (1.0 - cos(Float.pi * Float(f) / Float(rf)))
                    } else if f > (frames - rf) {
                        let endF = frames - f
                        env = 0.5 * (1.0 - cos(Float.pi * Float(endF) / Float(rf)))
                    }
                    monoSamples[writePos + f] = s * env
                    phase += omega
                    if phase > 2.0 * .pi { phase -= 2.0 * .pi }
                }
                writePos += frames
            }
        }

        // Copy mono samples to all channels (Mono, Stereo, etc.)
        for ch in 0..<channels {
            if let chData = buffer.floatChannelData?[ch] {
                for i in 0..<totalFrames {
                    chData[i] = monoSamples[i]
                }
            }
        }

        return buffer
    }

    // MARK: - Common CW Vocabulary
    public static let commonCWVocabulary: [String] = [
        "CQ", "TEST", "DE", "5NN", "TU", "73", "FB", "BK", "ES", "UR",
        "RST", "QTH", "NAME", "RIG", "ANT", "WX", "HR", "HW?", "CFM", "AGN",
        "PSE", "R", "K", "SK", "GL", "OP", "SIG", "SRI", "TNX", "VY",
        "TEMP", "SNOW", "RAIN", "SUN", "WARM", "COLD", "PWR", "DIPOLE", "BEAM"
    ]
}
