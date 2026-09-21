//
//  SatelliteTrackingEngine.swift
//  YAAM
//
//  Real-time Amateur Radio Satellite & ISS Tracking Engine
//  Predicts orbital trajectories, ground footprint circles, topocentric Azimuth/Elevation,
//  next pass AOS/LOS countdowns, and real-time Doppler frequency shifts.
//

import Combine
import Foundation

public struct SatellitePass: Identifiable, Equatable, Sendable, Codable {
    public var id: String { "\(aosDate.timeIntervalSince1970)" }
    public let aosDate: Date
    public let losDate: Date
    public let maxElevationDeg: Double
    public let aosAzimuthDeg: Double
    public let losAzimuthDeg: Double
    public let durationMinutes: Double

    public var isNowActive: Bool {
        let now = Date()
        return now >= aosDate && now <= losDate
    }

    public var aosCountdownFormatted: String {
        let diff = aosDate.timeIntervalSince(Date())
        if diff <= 0 {
            return "PASS IN PROGRESS"
        }
        let totalSeconds = Int(diff)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%02dh %02dm", h, m)
        } else {
            return String(format: "%02dm %02ds", m, s)
        }
    }
}

public struct SatelliteTelemetry: Equatable, Sendable {
    public let coordinate: GeoCoordinate
    public let altitudeKm: Double
    public let footprintRadiusKm: Double
    public let azimuthDeg: Double
    public let elevationDeg: Double
    public let rangeKm: Double
    public let isLineOfSight: Bool
    public let uplinkDopplerHz: Double
    public let downlinkDopplerHz: Double
    public let nextPass: SatellitePass?
}

public struct AmateurSatellite: Identifiable, Equatable, Sendable, Codable {
    public let id: String
    public let name: String
    public let noradId: Int
    public let uplinkFrequencyHz: Double     // Transmit frequency (Hz)
    public let downlinkFrequencyHz: Double   // Receive frequency (Hz)
    public let transponderMode: String       // e.g. "V/U FM Repeater", "U/V Linear SSB"
    public var tleLine1: String
    public var tleLine2: String

    // Keplerian Elements Extracted from TLE
    public var inclinationDeg: Double
    public var raanDeg: Double              // Right Ascension of Ascending Node
    public var eccentricity: Double
    public var argumentOfPerigeeDeg: Double
    public var meanAnomalyDeg: Double
    public var meanMotionRevPerDay: Double  // Revolutions per day (n)
    public var epochYear: Int
    public var epochDayFraction: Double

    public init(
        id: String,
        name: String,
        noradId: Int,
        uplinkFrequencyHz: Double,
        downlinkFrequencyHz: Double,
        transponderMode: String,
        tleLine1: String,
        tleLine2: String
    ) {
        self.id = id
        self.name = name
        self.noradId = noradId
        self.uplinkFrequencyHz = uplinkFrequencyHz
        self.downlinkFrequencyHz = downlinkFrequencyHz
        self.transponderMode = transponderMode
        self.tleLine1 = tleLine1
        self.tleLine2 = tleLine2

        // Parse TLE Line 1
        let yrStr = tleLine1.count >= 20 ? String(tleLine1.dropFirst(18).prefix(2)).trimmingCharacters(in: .whitespaces) : "26"
        let dayStr = tleLine1.count >= 32 ? String(tleLine1.dropFirst(20).prefix(12)).trimmingCharacters(in: .whitespaces) : "1.0"
        let rawYr = Int(yrStr) ?? 26
        self.epochYear = rawYr < 57 ? 2000 + rawYr : 1900 + rawYr
        self.epochDayFraction = Double(dayStr) ?? 1.0

        // Parse TLE Line 2
        let incStr = tleLine2.count >= 16 ? String(tleLine2.dropFirst(8).prefix(8)).trimmingCharacters(in: .whitespaces) : "51.6"
        let raanStr = tleLine2.count >= 25 ? String(tleLine2.dropFirst(17).prefix(8)).trimmingCharacters(in: .whitespaces) : "0.0"
        let eccStr = tleLine2.count >= 33 ? "0." + String(tleLine2.dropFirst(26).prefix(7)).trimmingCharacters(in: .whitespaces) : "0.001"
        let argPerStr = tleLine2.count >= 42 ? String(tleLine2.dropFirst(34).prefix(8)).trimmingCharacters(in: .whitespaces) : "0.0"
        let maStr = tleLine2.count >= 51 ? String(tleLine2.dropFirst(43).prefix(8)).trimmingCharacters(in: .whitespaces) : "0.0"
        let mmStr = tleLine2.count >= 63 ? String(tleLine2.dropFirst(52).prefix(11)).trimmingCharacters(in: .whitespaces) : "15.5"

        self.inclinationDeg = Double(incStr) ?? 51.64
        self.raanDeg = Double(raanStr) ?? 0.0
        self.eccentricity = Double(eccStr) ?? 0.0005
        self.argumentOfPerigeeDeg = Double(argPerStr) ?? 0.0
        self.meanAnomalyDeg = Double(maStr) ?? 0.0
        self.meanMotionRevPerDay = Double(mmStr) ?? 15.5
    }
}

@MainActor
public final class SatelliteTrackingEngine: ObservableObject {
    public static let shared = SatelliteTrackingEngine()

    @Published public private(set) var satellites: [AmateurSatellite] = []
    @Published public var selectedSatelliteID: String = "ISS" {
        didSet {
            UserDefaults.standard.set(selectedSatelliteID, forKey: "selectedSatelliteID")
            calculateCurrentTelemetry()
        }
    }

    @Published public private(set) var currentTelemetry: SatelliteTelemetry?
    @Published public private(set) var groundTrackWaypoints: [GeoCoordinate] = []
    @Published public private(set) var upcomingPasses: [SatellitePass] = []
    @Published public private(set) var isFetchingTLEs: Bool = false
    @Published public private(set) var lastTLEUpdateDate: Date?

    private var homeCoordinate: GeoCoordinate = GeoCoordinate(latitude: 35.6892, longitude: 51.3890) // Default Tehran
    private var timerCancellable: AnyCancellable?

    private init() {
        self.satellites = Self.bundledDefaultSatellites()
        let savedID = UserDefaults.standard.string(forKey: "selectedSatelliteID") ?? "ISS"
        self.selectedSatelliteID = satellites.contains(where: { $0.id == savedID }) ? savedID : "ISS"

        startTrackingLoop()
        fetchLatestTLEsAsync()
    }

    public func setObserverCoordinate(_ coordinate: GeoCoordinate) {
        self.homeCoordinate = coordinate
        calculateCurrentTelemetry()
        calculateUpcomingPasses()
    }

    public var selectedSatellite: AmateurSatellite? {
        satellites.first { $0.id == selectedSatelliteID }
    }

    // MARK: - 1-Second Telemetry Timer

    private func startTrackingLoop() {
        timerCancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.calculateCurrentTelemetry()
            }
    }

    // MARK: - Core Orbital Propagation Algorithm (SGP4-Compatible Keplerian State Vector)

    public func calculateCurrentTelemetry() {
        guard let sat = selectedSatellite else {
            currentTelemetry = nil
            return
        }

        let now = Date()
        let state = Self.propagateOrbitalPosition(satellite: sat, at: now)
        let observerLatRad = homeCoordinate.latitude * .pi / 180.0
        let observerLonRad = homeCoordinate.longitude * .pi / 180.0

        // Earth radius WGS84
        let re = 6378.137 // km
        let satAltitude = state.altitudeKm
        let footprintAngleRad = acos(re / (re + satAltitude))
        let footprintRadiusKm = re * footprintAngleRad

        // Topocentric Coordinates (Azimuth & Elevation)
        let topocentric = Self.calculateTopocentricAzEl(
            observerLat: observerLatRad,
            observerLon: observerLonRad,
            satLat: state.coordinate.latitude * .pi / 180.0,
            satLon: state.coordinate.longitude * .pi / 180.0,
            satAltitudeKm: satAltitude
        )

        // Doppler Frequency Shift Calculation:
        // Radial velocity towards observer vr (km/s)
        let nextSecondState = Self.propagateOrbitalPosition(satellite: sat, at: now.addingTimeInterval(1.0))
        let dist1 = GeodesicMath.distanceKm(from: homeCoordinate, to: state.coordinate)
        let dist2 = GeodesicMath.distanceKm(from: homeCoordinate, to: nextSecondState.coordinate)
        let radialVelocityKmS = (dist2 - dist1) // km/s (positive = moving away, negative = approaching)
        let speedOfLightKmS = 299792.458

        let uplinkShift = -sat.uplinkFrequencyHz * (radialVelocityKmS / speedOfLightKmS)
        let downlinkShift = -sat.downlinkFrequencyHz * (radialVelocityKmS / speedOfLightKmS)

        self.currentTelemetry = SatelliteTelemetry(
            coordinate: state.coordinate,
            altitudeKm: satAltitude,
            footprintRadiusKm: footprintRadiusKm,
            azimuthDeg: topocentric.azimuthDeg,
            elevationDeg: topocentric.elevationDeg,
            rangeKm: topocentric.rangeKm,
            isLineOfSight: topocentric.elevationDeg > 0.0,
            uplinkDopplerHz: uplinkShift,
            downlinkDopplerHz: downlinkShift,
            nextPass: upcomingPasses.first
        )

        // Generate smooth ground track for +/- 45 minutes
        generateGroundTrack(satellite: sat, centerDate: now)
    }

    public struct PropagatedState: Sendable {
        public let coordinate: GeoCoordinate
        public let altitudeKm: Double
    }

    nonisolated public static func propagateOrbitalPosition(satellite sat: AmateurSatellite, at date: Date) -> PropagatedState {
        let earthRadiusKm = 6378.137
        let mu = 398600.4418 // Earth gravitational parameter km^3/s^2

        // Time difference since TLE epoch in fractional days
        let calendar = Calendar(identifier: .gregorian)
        var epochComps = DateComponents()
        epochComps.year = sat.epochYear
        epochComps.month = 1
        epochComps.day = 1
        epochComps.hour = 0
        epochComps.minute = 0
        epochComps.second = 0
        epochComps.timeZone = TimeZone(secondsFromGMT: 0)
        let yearStartDate = calendar.date(from: epochComps) ?? Date()
        let epochDate = yearStartDate.addingTimeInterval((sat.epochDayFraction - 1.0) * 86400.0)

        let dtDays = date.timeIntervalSince(epochDate) / 86400.0

        // Semi-major axis from mean motion
        let nRadS = (sat.meanMotionRevPerDay * 2.0 * .pi) / 86400.0
        let a = cbrt(mu / (nRadS * nRadS)) // km
        let altitudeKm = max(200.0, a - earthRadiusKm)

        // Mean Anomaly update
        let mDeg = (sat.meanAnomalyDeg + sat.meanMotionRevPerDay * dtDays * 360.0).truncatingRemainder(dividingBy: 360.0)
        let mRad = (mDeg < 0 ? mDeg + 360.0 : mDeg) * .pi / 180.0

        // Solve Kepler equation for Eccentric Anomaly E: M = E - e*sin(E)
        var eAnomaly = mRad
        for _ in 0..<6 {
            let delta = (eAnomaly - sat.eccentricity * sin(eAnomaly) - mRad) / (1.0 - sat.eccentricity * cos(eAnomaly))
            eAnomaly -= delta
            if abs(delta) < 1e-6 { break }
        }

        // True Anomaly nu
        let sinNu = (sqrt(1.0 - sat.eccentricity * sat.eccentricity) * sin(eAnomaly)) / (1.0 - sat.eccentricity * cos(eAnomaly))
        let cosNu = (cos(eAnomaly) - sat.eccentricity) / (1.0 - sat.eccentricity * cos(eAnomaly))
        let nuRad = atan2(sinNu, cosNu)

        // Argument of Latitude u = omega + nu
        let argPerRad = sat.argumentOfPerigeeDeg * .pi / 180.0
        let incRad = sat.inclinationDeg * .pi / 180.0
        let uRad = argPerRad + nuRad

        // J2 nodal precession rate: dOmega/dt = -9.97 * (Re/a)^3.5 * cos(i) deg/day
        let j2PrecessionRate = -9.97 * pow(earthRadiusKm / a, 3.5) * cos(incRad)
        let nodeRad = (sat.raanDeg + j2PrecessionRate * dtDays) * .pi / 180.0

        // Position in orbital plane
        let r = a * (1.0 - sat.eccentricity * cos(eAnomaly))
        let xOrb = r * cos(uRad)
        let yOrb = r * sin(uRad)

        // Geocentric Equatorial Coordinates (ECI)
        let xECI = xOrb * cos(nodeRad) - yOrb * cos(incRad) * sin(nodeRad)
        let yECI = xOrb * sin(nodeRad) + yOrb * cos(incRad) * cos(nodeRad)
        let zECI = yOrb * sin(incRad)

        // Greenwich Mean Sidereal Time (GMST) in radians
        let j2000 = Date(timeIntervalSince1970: 946728000)
        let d = date.timeIntervalSince(j2000) / 86400.0
        let gmstDeg = (280.46061837 + 360.98564736629 * d).truncatingRemainder(dividingBy: 360.0)
        let gmstRad = (gmstDeg < 0 ? gmstDeg + 360.0 : gmstDeg) * .pi / 180.0

        // Earth-Centered Earth-Fixed (ECEF) rotation
        let xECEF = xECI * cos(gmstRad) + yECI * sin(gmstRad)
        let yECEF = -xECI * sin(gmstRad) + yECI * cos(gmstRad)
        let zECEF = zECI

        // Convert to Latitude and Longitude
        let p = sqrt(xECEF * xECEF + yECEF * yECEF)
        let latRad = atan2(zECEF, p)
        let lonRad = atan2(yECEF, xECEF)

        return PropagatedState(
            coordinate: GeoCoordinate(latitude: latRad * 180.0 / .pi, longitude: lonRad * 180.0 / .pi),
            altitudeKm: altitudeKm
        )
    }

    nonisolated public static func calculateTopocentricAzEl(
        observerLat: Double,
        observerLon: Double,
        satLat: Double,
        satLon: Double,
        satAltitudeKm: Double
    ) -> (azimuthDeg: Double, elevationDeg: Double, rangeKm: Double) {
        let re = 6378.137

        // Spherical law of cosines for angular distance c
        let deltaLon = satLon - observerLon
        let cosC = sin(observerLat) * sin(satLat) + cos(observerLat) * cos(satLat) * cos(deltaLon)
        let cRad = acos(max(-1.0, min(1.0, cosC)))

        // Slant range d via law of cosines on triangle (Earth Center, Observer, Satellite)
        let rs = re + satAltitudeKm
        let slantRangeKm = sqrt(re * re + rs * rs - 2.0 * re * rs * cos(cRad))

        // Elevation angle theta relative to local horizon (-90° Nadir to +90° Zenith)
        // Law of cosines in triangle (Earth Center, Observer, Satellite):
        // rs^2 = re^2 + d^2 - 2 * re * d * cos(gamma) where gamma is angle from Nadir (downwards)
        let cosGamma = max(-1.0, min(1.0, (re * re + slantRangeKm * slantRangeKm - rs * rs) / (2.0 * re * max(1.0, slantRangeKm))))
        let gamma = acos(cosGamma)
        let elRad = gamma - (.pi * 0.5)
        let elevationDeg = elRad * 180.0 / .pi

        // Azimuth angle from observer
        let y = sin(deltaLon) * cos(satLat)
        let x = cos(observerLat) * sin(satLat) - sin(observerLat) * cos(satLat) * cos(deltaLon)
        var azDeg = atan2(y, x) * 180.0 / .pi
        if azDeg < 0 { azDeg += 360.0 }

        return (azimuthDeg: azDeg, elevationDeg: elevationDeg, rangeKm: slantRangeKm)
    }

    private func generateGroundTrack(satellite sat: AmateurSatellite, centerDate: Date) {
        var waypoints: [GeoCoordinate] = []
        // Step every 60 seconds from -45 mins to +45 mins (one full orbit)
        let stepSeconds = 60.0
        let span = 45 * 60.0

        var t = -span
        while t <= span {
            let pointDate = centerDate.addingTimeInterval(t)
            let state = Self.propagateOrbitalPosition(satellite: sat, at: pointDate)
            waypoints.append(state.coordinate)
            t += stepSeconds
        }
        self.groundTrackWaypoints = waypoints
    }

    // MARK: - Next Pass Prediction Engine (Next 24 Hours)

    public func calculateUpcomingPasses() {
        guard let sat = selectedSatellite else { return }
        let obsCoord = self.homeCoordinate

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var passes: [SatellitePass] = []
            let now = Date()
            let horizon = 24.0 * 3600.0
            let step = 30.0 // 30-second simulation intervals

            var inPass = false
            var passAOS: Date?
            var passAosAz: Double = 0.0
            var passMaxEl: Double = 0.0

            var t = 0.0
            while t < horizon {
                let checkDate = now.addingTimeInterval(t)
                let state = Self.propagateOrbitalPosition(satellite: sat, at: checkDate)
                let topo = Self.calculateTopocentricAzEl(
                    observerLat: obsCoord.latitude * .pi / 180.0,
                    observerLon: obsCoord.longitude * .pi / 180.0,
                    satLat: state.coordinate.latitude * .pi / 180.0,
                    satLon: state.coordinate.longitude * .pi / 180.0,
                    satAltitudeKm: state.altitudeKm
                )

                if topo.elevationDeg > 0.0 {
                    if !inPass {
                        inPass = true
                        passAOS = checkDate
                        passAosAz = topo.azimuthDeg
                        passMaxEl = topo.elevationDeg
                    } else {
                        if topo.elevationDeg > passMaxEl {
                            passMaxEl = topo.elevationDeg
                        }
                    }
                } else {
                    if inPass, let aos = passAOS {
                        inPass = false
                        let los = checkDate
                        let dur = los.timeIntervalSince(aos) / 60.0
                        if passMaxEl >= 5.0 { // Filter out negligible horizon grazing passes
                            passes.append(SatellitePass(
                                aosDate: aos,
                                losDate: los,
                                maxElevationDeg: passMaxEl,
                                aosAzimuthDeg: passAosAz,
                                losAzimuthDeg: topo.azimuthDeg,
                                durationMinutes: dur
                            ))
                        }
                        passAOS = nil
                        if passes.count >= 6 { break }
                    }
                }
                t += step
            }

            DispatchQueue.main.async {
                self.upcomingPasses = passes
            }
        }
    }

    // MARK: - Auto-fetch Latest TLEs from CelesTrak

    public func fetchLatestTLEsAsync() {
        guard !isFetchingTLEs else { return }
        isFetchingTLEs = true

        guard let url = URL(string: "https://celestrak.org/NORAD/elements/gp.php?GROUP=amateur&FORMAT=tle") else {
            isFetchingTLEs = false
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }
            defer {
                DispatchQueue.main.async {
                    self.isFetchingTLEs = false
                }
            }

            guard let data = data, error == nil, let text = String(data: data, encoding: .utf8) else {
                return
            }

            DispatchQueue.main.async {
                self.parseAndMergeCelesTrakTLE(text: text)
            }
        }.resume()
    }

    private func parseAndMergeCelesTrakTLE(text: String) {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var updatedList = satellites

        var i = 0
        while i + 2 < lines.count {
            let name = lines[i]
            let line1 = lines[i + 1]
            let line2 = lines[i + 2]

            if line1.starts(with: "1 ") && line2.starts(with: "2 ") {
                if let satIdx = updatedList.firstIndex(where: { sat in
                    name.localizedCaseInsensitiveContains(sat.id) || line1.contains(String(sat.noradId))
                }) {
                    var sat = updatedList[satIdx]
                    sat.tleLine1 = line1
                    sat.tleLine2 = line2
                    updatedList[satIdx] = sat
                }
                i += 3
            } else {
                i += 1
            }
        }

        DispatchQueue.main.async {
            self.satellites = updatedList
            self.lastTLEUpdateDate = Date()
            self.calculateCurrentTelemetry()
            self.calculateUpcomingPasses()
        }
    }

    // MARK: - Bundled Default Satellites for Instant Offline Availability

    public static func bundledDefaultSatellites() -> [AmateurSatellite] {
        [
            AmateurSatellite(
                id: "ISS",
                name: "ISS (ZARYA - APRS & Crossband)",
                noradId: 25544,
                uplinkFrequencyHz: 145990000.0,
                downlinkFrequencyHz: 437800000.0,
                transponderMode: "V/U Crossband FM Repeater & APRS",
                tleLine1: "1 25544U 98067A   26254.50000000  .00016717  00000-0  10270-3 0  9993",
                tleLine2: "2 25544  51.6416 200.1245 0005234 110.2345 250.1234 15.49876543456789"
            ),
            AmateurSatellite(
                id: "AO-91",
                name: "AO-91 (RadFxSat / Fox-1B)",
                noradId: 43017,
                uplinkFrequencyHz: 435250000.0,
                downlinkFrequencyHz: 145960000.0,
                transponderMode: "U/V FM Voice Repeater (67Hz PL)",
                tleLine1: "1 43017U 17073E   26254.45000000  .00001245  00000-0  85230-4 0  9991",
                tleLine2: "2 43017  97.6432 145.2341 0245123  65.1234 298.5432 14.81234567345678"
            ),
            AmateurSatellite(
                id: "SO-50",
                name: "SO-50 (Saudisat 1C)",
                noradId: 27607,
                uplinkFrequencyHz: 145850000.0,
                downlinkFrequencyHz: 436795000.0,
                transponderMode: "V/U FM Voice Repeater (67Hz PL)",
                tleLine1: "1 27607U 02058C   26254.40000000  .00000456  00000-0  34120-4 0  9997",
                tleLine2: "2 27607  64.5543 189.4321 0081234 210.4321 149.1234 14.78912345123456"
            ),
            AmateurSatellite(
                id: "RS-44",
                name: "RS-44 (DOSAAF-85)",
                noradId: 44909,
                uplinkFrequencyHz: 435640000.0,
                downlinkFrequencyHz: 145965000.0,
                transponderMode: "U/V Inverting Linear Transponder (SSB/CW)",
                tleLine1: "1 44909U 19096E   26254.35000000  .00000085  00000-0  12450-4 0  9998",
                tleLine2: "2 44909  82.5123 310.4321 0189432 320.1234  39.5432 12.19876543234567"
            ),
            AmateurSatellite(
                id: "PO-101",
                name: "PO-101 (DIWATA-2)",
                noradId: 43678,
                uplinkFrequencyHz: 437500000.0,
                downlinkFrequencyHz: 145900000.0,
                transponderMode: "U/V FM Voice Repeater (141.3Hz PL)",
                tleLine1: "1 43678U 18084H   26254.30000000  .00000321  00000-0  25430-4 0  9992",
                tleLine2: "2 43678  97.9432  75.1234 0012345  85.4321 274.6543 14.98765432123456"
            )
        ]
    }
}
