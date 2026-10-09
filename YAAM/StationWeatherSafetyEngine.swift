//
//  StationWeatherSafetyEngine.swift
//  YAAM
//
//  Station Weather & Antenna Safety Radar Engine
//  Ingests live terrestrial weather telemetry and forecasts from Open-Meteo REST API,
//  maps Maidenhead grid locators to coordinates, and calculates ham-centric threat levels
//  for lightning strikes, precipitation static (P-static) coax arcing, tower wind loads,
//  and VHF/UHF tropospheric ducting.
//

import AppKit
import AVFoundation
import Combine
import Foundation
import SwiftUI

// MARK: - Ham Radio Threat Level Enums

public enum AntennaThreatLevel: String, CaseIterable, Identifiable {
    case safe = "Safe"
    case elevated = "Elevated"
    case warning = "Warning"
    case critical = "Critical Hazard"

    public var id: String { rawValue }

    public var color: Color {
        switch self {
        case .safe: return .green
        case .elevated: return .yellow
        case .warning: return .orange
        case .critical: return .red
        }
    }

    public var badgeIcon: String {
        switch self {
        case .safe: return "shield.lefthalf.filled"
        case .elevated: return "exclamationmark.triangle.fill"
        case .warning: return "wind"
        case .critical: return "bolt.trianglebadge.exclamationmark.fill"
        }
    }

    public var tacticalAction: String {
        switch self {
        case .safe:
            return "Atmospheric conditions nominal. Station operations safe."
        case .elevated:
            return "Precipitation or rising winds detected. Monitor feedlines."
        case .warning:
            return "Heavy rain or gusty winds. High P-static & tower load risk."
        case .critical:
            return "⚡️ SEVERE LIGHTNING HAZARD: Disconnect coaxial cables and ground antennas immediately!"
        }
    }
}

public enum PStaticRisk: String {
    case low = "Low"
    case moderate = "Moderate"
    case severe = "Severe (ESD Arcing)"

    public var color: Color {
        switch self {
        case .low: return .green
        case .moderate: return .yellow
        case .severe: return .red
        }
    }

    public var advice: String {
        switch self {
        case .low:
            return "Electrostatic accumulation is minimal."
        case .moderate:
            return "Frictional charge on wire/Yagi elements may elevate RF noise floor."
        case .severe:
            return "High static voltage build-up! Coaxial connectors may arc if left floating or ungrounded."
        }
    }
}

public enum WindLoadThreat: String {
    case low = "Low"
    case caution = "Caution"
    case high = "High Strain"
    case dangerous = "Dangerous"

    public var color: Color {
        switch self {
        case .low: return .green
        case .caution: return .yellow
        case .high: return .orange
        case .dangerous: return .red
        }
    }

    public var advice: String {
        switch self {
        case .low: return "Wind forces within normal antenna tolerances."
        case .caution: return "Noticeable element vibration and mast sway."
        case .high: return "High wind torque on Yagi boom. Consider parking rotator."
        case .dangerous: return "Severe wind gusts! Lower telescopic towers and lock rotators."
        }
    }
}

public enum TroposphericDuctingIndex: String {
    case nominal = "Nominal"
    case enhanced = "Enhanced"
    case openingExpected = "Tropo Ducting Likely"

    public var color: Color {
        switch self {
        case .nominal: return .secondary
        case .enhanced: return .blue
        case .openingExpected: return .cyan
        }
    }

    public var detail: String {
        switch self {
        case .nominal: return "Normal VHF/UHF line-of-sight propagation."
        case .enhanced: return "Atmospheric temperature/pressure inversion may extend 2m/70cm range."
        case .openingExpected: return "Significant tropospheric ducting favorable for 144/430 MHz DX contacts!"
        }
    }
}

// MARK: - Telemetry Models

public struct WeatherTelemetry: Equatable {
    public let temperature: Double
    public let humidity: Double
    public let apparentTemperature: Double
    public let precipitation: Double
    public let rain: Double
    public let weatherCode: Int
    public let windSpeed: Double
    public let windGusts: Double
    public let windDirection: Double
    public let surfacePressure: Double
    public let timestamp: Date

    public var isThunderstorm: Bool {
        weatherCode == 95 || weatherCode == 96 || weatherCode == 99
    }

    public var isHeavyRain: Bool {
        precipitation >= 5.0 || weatherCode == 65 || weatherCode == 82
    }

    public var conditionDescription: String {
        switch weatherCode {
        case 0: return "Clear Sky"
        case 1: return "Mainly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog & Depositing Rime"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61: return "Slight Rain"
        case 63: return "Moderate Rain"
        case 65: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 73, 75: return "Snow Fall"
        case 77: return "Snow Grains"
        case 80, 81, 82: return "Rain Showers"
        case 85, 86: return "Snow Showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Severe Thunderstorm with Hail"
        default: return "Atmospheric Activity (\(weatherCode))"
        }
    }

    public var conditionIcon: String {
        switch weatherCode {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67: return "cloud.rain.fill"
        case 71...77: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.sun.fill"
        }
    }
}

public struct HourlyThreatForecast: Identifiable, Equatable {
    public let id = UUID()
    public let time: Date
    public let temperature: Double
    public let precipProbability: Int
    public let precipitation: Double
    public let weatherCode: Int
    public let windSpeed: Double
    public let windGusts: Double
    public let threatLevel: AntennaThreatLevel

    public var isThunderstorm: Bool {
        weatherCode == 95 || weatherCode == 96 || weatherCode == 99
    }

    public var hourFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: time)
    }

    public var conditionIcon: String {
        switch weatherCode {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67: return "cloud.rain.fill"
        case 71...77: return "cloud.snow.fill"
        case 80...82: return "cloud.heavyrain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

// MARK: - Station Weather & Safety Engine

@MainActor
public final class StationWeatherSafetyEngine: ObservableObject {
    public static let shared = StationWeatherSafetyEngine()

    // MARK: - User Defaults / Configuration
    @Published public var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "weatherRadarEnabled") }
    }
    @Published public var audioAlertsEnabled: Bool {
        didSet { UserDefaults.standard.set(audioAlertsEnabled, forKey: "weatherAudioAlertsEnabled") }
    }
    @Published public var highWindThreshold: Double {
        didSet { UserDefaults.standard.set(highWindThreshold, forKey: "weatherHighWindThreshold") }
    }
    private var stationGrid: String {
        UserDefaults.standard.string(forKey: "stationGrid") ?? ""
    }

    // MARK: - Published State
    @Published public private(set) var currentTelemetry: WeatherTelemetry?
    @Published public private(set) var hourlyForecast: [HourlyThreatForecast] = []
    @Published public private(set) var threatLevel: AntennaThreatLevel = .safe
    @Published public private(set) var pStaticRisk: PStaticRisk = .low
    @Published public private(set) var windThreat: WindLoadThreat = .low
    @Published public private(set) var tropoIndex: TroposphericDuctingIndex = .nominal
    @Published public private(set) var recommendedRotatorHeading: Int = 0
    @Published public private(set) var resolvedGrid: String = ""
    @Published public private(set) var resolvedCoordinates: (lat: Double, lon: Double)?
    @Published public private(set) var lastUpdated: Date?
    @Published public private(set) var isFetching: Bool = false
    @Published public private(set) var fetchError: String?

    // Emergency Checklist States (Persisted for session safety)
    @Published public var checklistCoaxDisconnected: Bool = false
    @Published public var checklistGrounded: Bool = false
    @Published public var checklistPowerOff: Bool = false
    @Published public var checklistRotatorParked: Bool = false

    private var refreshTimer: Timer?
    private var lastSpokenThreatLevel: AntennaThreatLevel?
    private let speechSynthesizer = AVSpeechSynthesizer()

    private init() {
        self.isEnabled = UserDefaults.standard.object(forKey: "weatherRadarEnabled") as? Bool ?? true
        self.audioAlertsEnabled = UserDefaults.standard.object(forKey: "weatherAudioAlertsEnabled") as? Bool ?? true
        let savedWind = UserDefaults.standard.double(forKey: "weatherHighWindThreshold")
        self.highWindThreshold = savedWind > 0 ? savedWind : 50.0

        startTimer()
        Task { @MainActor in
            await refresh()
        }
    }

    deinit {
        refreshTimer?.invalidate()
    }

    private func startTimer() {
        refreshTimer?.invalidate()
        // Refresh every 20 minutes
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1200, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }

    // MARK: - Refresh Telemetry

    public func refresh(forcedGrid: String? = nil) async {
        guard isEnabled else { return }

        let targetGrid = (forcedGrid ?? stationGrid).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !targetGrid.isEmpty else {
            resolvedGrid = ""
            fetchError = "Set your locator in Settings > Stations to see the weather at your station."
            return
        }
        let effectiveGrid = targetGrid
        resolvedGrid = effectiveGrid

        guard let coords = coordinate(fromMaidenhead: effectiveGrid) else {
            fetchError = "Invalid Maidenhead Locator: \(effectiveGrid)"
            return
        }

        resolvedCoordinates = coords
        isFetching = true
        fetchError = nil

        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(coords.lat)&longitude=\(coords.lon)&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,rain,weather_code,wind_speed_10m,wind_gusts_10m,wind_direction_10m,surface_pressure&hourly=temperature_2m,precipitation_probability,precipitation,weather_code,wind_speed_10m,wind_gusts_10m&forecast_days=2&timezone=auto"

        guard let url = URL(string: urlString) else {
            isFetching = false
            fetchError = "Malformed Open-Meteo URL"
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(OpenMeteoResponse.self, from: data)

            processOpenMeteoData(decoded)
            lastUpdated = Date()
            isFetching = false
        } catch {
            isFetching = false
            fetchError = "Failed to update weather: \(error.localizedDescription)"
        }
    }

    // MARK: - Threat Evaluation Logic

    private func processOpenMeteoData(_ data: OpenMeteoResponse) {
        let current = WeatherTelemetry(
            temperature: data.current.temperature_2m,
            humidity: data.current.relative_humidity_2m,
            apparentTemperature: data.current.apparent_temperature,
            precipitation: data.current.precipitation,
            rain: data.current.rain,
            weatherCode: data.current.weather_code,
            windSpeed: data.current.wind_speed_10m,
            windGusts: data.current.wind_gusts_10m,
            windDirection: data.current.wind_direction_10m,
            surfacePressure: data.current.surface_pressure,
            timestamp: Date()
        )
        self.currentTelemetry = current

        // Calculate Rotator Heading: Pointing directly into the wind feathers the Yagi elements
        let windDir = Int(current.windDirection.rounded()) % 360
        self.recommendedRotatorHeading = (windDir + 360) % 360

        // Parse Hourly Forecast
        let isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")

        var parsedHourly: [HourlyThreatForecast] = []
        let count = min(data.hourly.time.count, data.hourly.temperature_2m.count, data.hourly.weather_code.count)
        let now = Date()

        for i in 0..<count {
            guard let time = isoFormatter.date(from: data.hourly.time[i]) else { continue }
            // Filter to upcoming 24 hours
            if time < now.addingTimeInterval(-3600) || time > now.addingTimeInterval(86400) {
                continue
            }

            let temp = data.hourly.temperature_2m[i]
            let prob = i < data.hourly.precipitation_probability.count ? data.hourly.precipitation_probability[i] : 0
            let prec = i < data.hourly.precipitation.count ? data.hourly.precipitation[i] : 0.0
            let code = data.hourly.weather_code[i]
            let speed = i < data.hourly.wind_speed_10m.count ? data.hourly.wind_speed_10m[i] : 0.0
            let gusts = i < data.hourly.wind_gusts_10m.count ? data.hourly.wind_gusts_10m[i] : speed

            let itemThreat = calculateThreat(code: code, windSpeed: speed, windGusts: gusts, precip: prec)
            parsedHourly.append(HourlyThreatForecast(
                time: time,
                temperature: temp,
                precipProbability: prob,
                precipitation: prec,
                weatherCode: code,
                windSpeed: speed,
                windGusts: gusts,
                threatLevel: itemThreat
            ))
        }
        self.hourlyForecast = parsedHourly

        // 1. Lightning & Overall Threat Calculation
        // Look at current + next 3 hours
        let immediateHorizon = parsedHourly.prefix(4)
        let hasImminentThunderstorm = immediateHorizon.contains { $0.isThunderstorm } || current.isThunderstorm

        if hasImminentThunderstorm || current.windGusts >= 75.0 {
            self.threatLevel = .critical
        } else if current.windGusts >= highWindThreshold || current.isHeavyRain || immediateHorizon.contains(where: { $0.threatLevel == .warning }) {
            self.threatLevel = .warning
        } else if current.precipitation > 0.5 || current.windGusts >= 35.0 || immediateHorizon.contains(where: { $0.threatLevel == .elevated }) {
            self.threatLevel = .elevated
        } else {
            self.threatLevel = .safe
        }

        // 2. Precipitation Static (P-Static) Threat
        // High static build-up occurs with rain/dry-snow + wind friction on element tips
        if current.isThunderstorm || (current.precipitation >= 4.0 && current.windSpeed >= 25.0) {
            self.pStaticRisk = .severe
        } else if current.precipitation >= 1.0 || (current.humidity < 30.0 && current.windSpeed >= 40.0) {
            self.pStaticRisk = .moderate
        } else {
            self.pStaticRisk = .low
        }

        // 3. Wind Load Threat
        if current.windGusts >= 75.0 {
            self.windThreat = .dangerous
        } else if current.windGusts >= highWindThreshold {
            self.windThreat = .high
        } else if current.windGusts >= 35.0 {
            self.windThreat = .caution
        } else {
            self.windThreat = .low
        }

        // 4. Tropospheric Ducting Index
        // High pressure (> 1018 hPa) with relative humidity transition indicates inversion layer
        if current.surfacePressure >= 1018.0 && current.humidity >= 70.0 && current.windSpeed <= 15.0 {
            self.tropoIndex = .openingExpected
        } else if current.surfacePressure >= 1015.0 && current.windSpeed <= 20.0 {
            self.tropoIndex = .enhanced
        } else {
            self.tropoIndex = .nominal
        }

        // 5. Audio Speech Alert if Critical Hazard
        checkAndAnnounceAlert()
    }

    private func calculateThreat(code: Int, windSpeed: Double, windGusts: Double, precip: Double) -> AntennaThreatLevel {
        if code == 95 || code == 96 || code == 99 || windGusts >= 75.0 {
            return .critical
        } else if windGusts >= highWindThreshold || precip >= 5.0 || code == 65 || code == 82 {
            return .warning
        } else if precip > 0.5 || windGusts >= 35.0 || code == 63 || code == 81 {
            return .elevated
        } else {
            return .safe
        }
    }

    private func checkAndAnnounceAlert() {
        guard audioAlertsEnabled else { return }

        if threatLevel == .critical && lastSpokenThreatLevel != .critical {
            lastSpokenThreatLevel = .critical
            speak(message: "Warning. Severe lightning or thunderstorm hazard detected at your station locator. Disconnect antenna coaxial cables immediately.")
        } else if threatLevel == .safe && lastSpokenThreatLevel != .safe {
            lastSpokenThreatLevel = .safe
        }
    }

    public func speak(message: String) {
        let utterance = AVSpeechUtterance(string: message)
        utterance.rate = 0.50
        utterance.volume = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speechSynthesizer.speak(utterance)
    }

    // MARK: - Maidenhead Grid Resolver

    public func coordinate(fromMaidenhead locator: String) -> (lat: Double, lon: Double)? {
        let value = locator.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard value.count >= 4 else { return nil }

        let chars = Array(value)
        guard
            let lonField = chars[0].asciiValue,
            let latField = chars[1].asciiValue,
            let lonSquare = chars[2].wholeNumberValue,
            let latSquare = chars[3].wholeNumberValue
        else {
            return nil
        }

        var longitude = Double(lonField - Character("A").asciiValue!) * 20 - 180 + Double(lonSquare) * 2 + 1
        var latitude = Double(latField - Character("A").asciiValue!) * 10 - 90 + Double(latSquare) + 0.5

        if value.count >= 6,
           let lonSub = chars[4].asciiValue,
           let latSub = chars[5].asciiValue {
            longitude += Double(lonSub - Character("A").asciiValue!) * (5.0 / 60.0) + (2.5 / 60.0) - 1
            latitude += Double(latSub - Character("A").asciiValue!) * (2.5 / 60.0) + (1.25 / 60.0) - 0.5
        }

        return (latitude, longitude)
    }
}

// MARK: - Open-Meteo JSON Decodable Schemas

private struct OpenMeteoResponse: Decodable {
    let current: CurrentWeather
    let hourly: HourlyWeather
}

private struct CurrentWeather: Decodable {
    let temperature_2m: Double
    let relative_humidity_2m: Double
    let apparent_temperature: Double
    let precipitation: Double
    let rain: Double
    let weather_code: Int
    let wind_speed_10m: Double
    let wind_gusts_10m: Double
    let wind_direction_10m: Double
    let surface_pressure: Double
}

private struct HourlyWeather: Decodable {
    let time: [String]
    let temperature_2m: [Double]
    let precipitation_probability: [Int]
    let precipitation: [Double]
    let weather_code: [Int]
    let wind_speed_10m: [Double]
    let wind_gusts_10m: [Double]
}
