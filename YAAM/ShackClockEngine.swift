//
//  ShackClockEngine.swift
//  YAAM
//
//  High-Precision Multi-Timekeeping & Shack Kiosk Clock Engine
//  Maintains UTC, Local, Local Mean Solar Time (LMST), and Local Sidereal Time (LST),
//  along with Shack Operating Stopwatch, Contest Countdown, and Hourly Audio/CW Chime.
//

import AppKit
import AVFoundation
import Combine
import Foundation

public enum HourlyChimeMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case subtleBeep = "Subtle Tone"
    case cwMorseUTC = "CW 'UTC'"
    case systemSound = "System Alert"

    public var id: String { rawValue }
}

@MainActor
public final class ShackClockEngine: ObservableObject {
    public static let shared = ShackClockEngine()

    // MARK: - Live Clocks Telemetry
    @Published public private(set) var currentDate: Date = Date()
    @Published public private(set) var utcTimeFormatted: String = "--:--:--"
    @Published public private(set) var utcDateFormatted: String = "--- -- --- ----"
    @Published public private(set) var utcDayOfYear: Int = 1
    @Published public private(set) var localTimeFormatted: String = "--:--:--"
    @Published public private(set) var localDateFormatted: String = "--- -- --- ----"
    @Published public private(set) var localTimeZoneCode: String = "LOC"
    @Published public private(set) var localSiderealTime: String = "--:--:--"
    @Published public private(set) var localSolarTime: String = "--:--:--"

    // MARK: - Shack Operating Stopwatch & Timer
    @Published public var isStopwatchRunning: Bool = false
    @Published public var stopwatchElapsed: TimeInterval = 0.0

    // MARK: - Hourly Audio Chime
    @Published public var isHourlyChimeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isHourlyChimeEnabled, forKey: "shackClockHourlyChimeEnabled")
        }
    }
    @Published public var hourlyChimeMode: HourlyChimeMode {
        didSet {
            UserDefaults.standard.set(hourlyChimeMode.rawValue, forKey: "shackClockHourlyChimeMode")
        }
    }

    // MARK: - Shack Night Vision Mode (High-contrast Red HUD)
    @Published public var isNightVisionMode: Bool {
        didSet {
            UserDefaults.standard.set(isNightVisionMode, forKey: "shackClockNightVisionMode")
        }
    }

    private var stationLongitude: Double = 51.4 // Default Tehran longitude, updated via Station Profile
    private var tickerCancellable: AnyCancellable?
    private var stopwatchTimerCancellable: AnyCancellable?
    private var lastChimedHour: Int = -1
    private var audioPlayer: AVAudioPlayer?

    private let utcDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "EEE, dd MMM yyyy"
        return f
    }()

    private let localDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        f.timeZone = TimeZone.current
        f.dateFormat = "EEE, dd MMM yyyy"
        return f
    }()

    private init() {
        self.isHourlyChimeEnabled = UserDefaults.standard.object(forKey: "shackClockHourlyChimeEnabled") as? Bool ?? true
        let savedMode = UserDefaults.standard.string(forKey: "shackClockHourlyChimeMode") ?? HourlyChimeMode.cwMorseUTC.rawValue
        self.hourlyChimeMode = HourlyChimeMode(rawValue: savedMode) ?? .cwMorseUTC
        self.isNightVisionMode = UserDefaults.standard.bool(forKey: "shackClockNightVisionMode")

        updateAllClocks(at: Date())
        startTicker()
    }

    public func setStationLongitude(_ longitude: Double) {
        self.stationLongitude = longitude
        updateAllClocks(at: currentDate)
    }

    // MARK: - Ticker Loop (Runs every second)

    private func startTicker() {
        tickerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] now in
                guard let self = self else { return }
                self.updateAllClocks(at: now)
                self.evaluateHourlyChime(at: now)
            }
    }

    private func updateAllClocks(at date: Date) {
        self.currentDate = date

        // 1. UTC Clock
        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(secondsFromGMT: 0)!
        let utcHour = utcCal.component(.hour, from: date)
        let utcMin = utcCal.component(.minute, from: date)
        let utcSec = utcCal.component(.second, from: date)
        self.utcTimeFormatted = String(format: "%02d:%02d:%02d", utcHour, utcMin, utcSec)
        self.utcDateFormatted = utcDateFormatter.string(from: date).uppercased()
        self.utcDayOfYear = utcCal.ordinality(of: .day, in: .year, for: date) ?? 1

        // 2. Local Clock
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = TimeZone.current
        let locHour = localCal.component(.hour, from: date)
        let locMin = localCal.component(.minute, from: date)
        let locSec = localCal.component(.second, from: date)
        self.localTimeFormatted = String(format: "%02d:%02d:%02d", locHour, locMin, locSec)
        self.localDateFormatted = localDateFormatter.string(from: date).uppercased()
        self.localTimeZoneCode = TimeZone.current.abbreviation() ?? "LOC"

        // 3. Local Sidereal Time (LST)
        self.localSiderealTime = calculateLST(for: date, longitude: stationLongitude)

        // 4. Local Mean Solar Time (LMST)
        self.localSolarTime = calculateSolarTime(for: date, longitude: stationLongitude)

        // 5. Stopwatch increment
        if isStopwatchRunning {
            stopwatchElapsed += 1.0
        }
    }

    // MARK: - Sidereal & Solar Calculation Algorithms

    /// Computes Local Sidereal Time (LST) based on Greenwich Mean Sidereal Time (GMST) and observer longitude
    public func calculateLST(for date: Date, longitude: Double) -> String {
        // J2000.0 epoch offset in days
        let j2000 = Date(timeIntervalSince1970: 946728000)
        let d = date.timeIntervalSince(j2000) / 86400.0

        var calUTC = Calendar(identifier: .gregorian)
        calUTC.timeZone = TimeZone(secondsFromGMT: 0)!
        let hour = Double(calUTC.component(.hour, from: date))
        let minute = Double(calUTC.component(.minute, from: date))
        let second = Double(calUTC.component(.second, from: date))
        let utHours = hour + minute / 60.0 + second / 3600.0

        // GMST in degrees (Astronomical Almanac formula)
        let gmstDeg = (280.46061837 + 360.98564736629 * d + utHours * 15.0).truncatingRemainder(dividingBy: 360.0)
        let gmstPos = gmstDeg < 0 ? gmstDeg + 360.0 : gmstDeg

        // Local Sidereal Time: LST = GMST + Longitude (East positive, West negative)
        var lstDeg = (gmstPos + longitude).truncatingRemainder(dividingBy: 360.0)
        if lstDeg < 0 { lstDeg += 360.0 }

        // Convert degrees to hours (360° = 24h -> 15° = 1h)
        let lstHoursTotal = lstDeg / 15.0
        let lstH = Int(lstHoursTotal) % 24
        let lstM = Int((lstHoursTotal - Double(lstH)) * 60.0) % 60
        let lstS = Int(((lstHoursTotal - Double(lstH)) * 60.0 - Double(lstM)) * 60.0) % 60

        return String(format: "%02d:%02d:%02d LST", lstH, lstM, lstS)
    }

    /// Computes Local Mean Solar Time (LMST) accounting for longitude offset from UTC meridian
    public func calculateSolarTime(for date: Date, longitude: Double) -> String {
        var calUTC = Calendar(identifier: .gregorian)
        calUTC.timeZone = TimeZone(secondsFromGMT: 0)!
        let hour = Double(calUTC.component(.hour, from: date))
        let minute = Double(calUTC.component(.minute, from: date))
        let second = Double(calUTC.component(.second, from: date))
        let utHours = hour + minute / 60.0 + second / 3600.0

        // Longitude offset: 4 minutes per degree
        let solarHours = (utHours + (longitude / 15.0)).truncatingRemainder(dividingBy: 24.0)
        let normSolar = solarHours < 0 ? solarHours + 24.0 : solarHours

        let solH = Int(normSolar) % 24
        let solM = Int((normSolar - Double(solH)) * 60.0) % 60
        let solS = Int(((normSolar - Double(solH)) * 60.0 - Double(solM)) * 60.0) % 60

        return String(format: "%02d:%02d:%02d SOL", solH, solM, solS)
    }

    // MARK: - Stopwatch Controls

    public func toggleStopwatch() {
        isStopwatchRunning.toggle()
    }

    public func resetStopwatch() {
        isStopwatchRunning = false
        stopwatchElapsed = 0.0
    }

    public var stopwatchFormatted: String {
        let total = Int(stopwatchElapsed)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%02d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }

    // MARK: - Hourly Chime Triggers

    private func evaluateHourlyChime(at date: Date) {
        guard isHourlyChimeEnabled else { return }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let minute = cal.component(.minute, from: date)
        let second = cal.component(.second, from: date)
        let hour = cal.component(.hour, from: date)

        // Trigger at exactly minute 00, second 00 (or up to second 01)
        if minute == 0 && second <= 1 && lastChimedHour != hour {
            lastChimedHour = hour
            playHourlyChime()
        }
    }

    public func playHourlyChime() {
        switch hourlyChimeMode {
        case .subtleBeep:
            playTone(frequency: 880.0, duration: 0.15)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
                self?.playTone(frequency: 1760.0, duration: 0.3)
            }
        case .cwMorseUTC:
            // Play Morse code for "UTC": ..-  -  -.-.
            playMorseUTC()
        case .systemSound:
            NSSound.beep()
        }
    }

    private func playMorseUTC() {
        // Morse code "UTC": ..- / - / -.-.
        let dot = 0.07
        let dash = 0.21
        let elementSpace = 0.07
        let charSpace = 0.21

        let morsePattern: [(isTone: Bool, duration: Double)] = [
            // U: ..-
            (true, dot), (false, elementSpace),
            (true, dot), (false, elementSpace),
            (true, dash), (false, charSpace),
            // T: -
            (true, dash), (false, charSpace),
            // C: -.-.
            (true, dash), (false, elementSpace),
            (true, dot), (false, elementSpace),
            (true, dash), (false, elementSpace),
            (true, dot)
        ]

        var accumulatedDelay = 0.0
        for item in morsePattern {
            if item.isTone {
                DispatchQueue.main.asyncAfter(deadline: .now() + accumulatedDelay) { [weak self] in
                    self?.playTone(frequency: 750.0, duration: item.duration)
                }
            }
            accumulatedDelay += item.duration
        }
    }

    /// Plays a pure sine wave tone at the requested frequency and duration
    private func playTone(frequency: Double, duration: Double) {
        let sampleRate = 44100.0
        let numSamples = Int(sampleRate * duration)
        var samples = [Int16](repeating: 0, count: numSamples)

        for i in 0..<numSamples {
            let t = Double(i) / sampleRate
            let attackTime = min(0.015, duration * 0.1)
            let decayTime = min(0.02, duration * 0.1)
            var env = 1.0
            if t < attackTime {
                env = t / attackTime
            } else if t > (duration - decayTime) {
                env = (duration - t) / decayTime
            }

            let value = sin(2.0 * .pi * frequency * t) * env * 0.4
            samples[i] = Int16(value * Double(Int16.max))
        }

        let audioData = Data(bytes: samples, count: numSamples * MemoryLayout<Int16>.size)
        let wavData = createWavData(from: audioData, sampleRate: Int(sampleRate))
        do {
            audioPlayer = try AVAudioPlayer(data: wavData)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            NSSound.beep()
        }
    }

    private func createWavData(from pcmData: Data, sampleRate: Int) -> Data {
        var data = Data()
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)
        let subchunk2Size: UInt32 = UInt32(pcmData.count)
        let chunkSize: UInt32 = 36 + subchunk2Size

        data.append("RIFF".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: chunkSize) { Data($0) })
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        let subchunk1Size: UInt32 = 16
        data.append(withUnsafeBytes(of: subchunk1Size) { Data($0) })
        let audioFormat: UInt16 = 1 // PCM
        data.append(withUnsafeBytes(of: audioFormat) { Data($0) })
        data.append(withUnsafeBytes(of: numChannels) { Data($0) })
        let sRate: UInt32 = UInt32(sampleRate)
        data.append(withUnsafeBytes(of: sRate) { Data($0) })
        data.append(withUnsafeBytes(of: byteRate) { Data($0) })
        data.append(withUnsafeBytes(of: blockAlign) { Data($0) })
        data.append(withUnsafeBytes(of: bitsPerSample) { Data($0) })
        data.append("data".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: subchunk2Size) { Data($0) })
        data.append(pcmData)

        return data
    }
}
