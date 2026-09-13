//
//  AstronomicalSolarEngine.swift
//  YAAM
//

import Foundation

// MARK: - Astronomical Solar, Lunar & Geodesic Calculation Engine

public nonisolated struct GeoCoordinate: Equatable, Hashable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = max(-90.0, min(90.0, latitude))
        // Normalize longitude to -180.0 ... 180.0
        var lon = longitude.truncatingRemainder(dividingBy: 360.0)
        if lon > 180.0 { lon -= 360.0 }
        if lon < -180.0 { lon += 360.0 }
        self.longitude = lon
    }
}

public nonisolated struct SubSolarPosition: Equatable, Sendable {
    public let latitude: Double   // Solar Declination (-23.44° to +23.44°)
    public let longitude: Double  // Sub-solar Longitude (-180° to +180°)
    public let equationOfTimeMinutes: Double
    public let greenwichHourAngleDeg: Double
}

public typealias AstronomicalSolarEngine = SolarEphemeris

public nonisolated struct SolarEphemeris {
    public let subSolar: SubSolarPosition
    public let date: Date

    /// Computes the exact Sub-Solar Point for a given date/time
    public static func calculate(at date: Date = Date()) -> SubSolarPosition {
        let calendar = Calendar(identifier: .gregorian)
        var calUTC = calendar
        calUTC.timeZone = TimeZone(secondsFromGMT: 0)!

        let dayOfYear = Double(calUTC.ordinality(of: .day, in: .year, for: date) ?? 1)
        let hour = Double(calUTC.component(.hour, from: date))
        let minute = Double(calUTC.component(.minute, from: date))
        let second = Double(calUTC.component(.second, from: date))

        let universalTimeHours = hour + minute / 60.0 + second / 3600.0

        // Fractional year in radians
        let gamma = 2.0 * .pi / 365.0 * (dayOfYear - 1.0 + (universalTimeHours - 12.0) / 24.0)

        // Equation of time in minutes (Spencer 1971 formula)
        let eqtime = 229.18 * (0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
                              - 0.014615 * cos(2.0 * gamma) - 0.040849 * sin(2.0 * gamma))

        // Solar declination angle in radians (Spencer formula)
        let decl = 0.006918 - 0.399912 * cos(gamma) + 0.070257 * sin(gamma)
                   - 0.006758 * cos(2.0 * gamma) + 0.000907 * sin(2.0 * gamma)
                   - 0.002697 * cos(3.0 * gamma) + 0.001480 * sin(3.0 * gamma)

        let declinationDeg = decl * 180.0 / .pi

        // Greenwich Hour Angle (GHA) & Sub-solar longitude
        // At 12:00 UTC + EqTime, Sun is on the Greenwich meridian (0°).
        let subSolarLon = -(universalTimeHours - 12.0 + eqtime / 60.0) * 15.0
        var normalizedLon = subSolarLon.truncatingRemainder(dividingBy: 360.0)
        if normalizedLon > 180.0 { normalizedLon -= 360.0 }
        if normalizedLon < -180.0 { normalizedLon += 360.0 }

        let gha = (universalTimeHours * 15.0 + eqtime * 0.25).truncatingRemainder(dividingBy: 360.0)

        return SubSolarPosition(
            latitude: declinationDeg,
            longitude: normalizedLon,
            equationOfTimeMinutes: eqtime,
            greenwichHourAngleDeg: gha < 0 ? gha + 360.0 : gha
        )
    }

    /// Generates the Day/Night Solar Terminator boundary polygon coordinates
    public nonisolated static func terminatorCoordinates(at date: Date = Date(), stepDegrees: Double = 2.0) -> [GeoCoordinate] {
        let subSolar = calculate(at: date)
        let decRad = subSolar.latitude * .pi / 180.0
        let sunLonRad = subSolar.longitude * .pi / 180.0

        var coordinates: [GeoCoordinate] = []

        // Great circle perpendicular to the vector pointing from Earth center to the Sun
        var lonDeg = -180.0
        while lonDeg <= 180.0 {
            let lonRad = lonDeg * .pi / 180.0
            let deltaLon = lonRad - sunLonRad

            // lat = atan(-cos(deltaLon) / tan(decRad))
            if abs(tan(decRad)) < 1e-6 {
                // Equinox: terminator is along the meridians 90° away from the sun
                let lat = (cos(deltaLon) > 0) ? -90.0 : 90.0
                coordinates.append(GeoCoordinate(latitude: lat, longitude: lonDeg))
            } else {
                let termLatRad = atan(-cos(deltaLon) / tan(decRad))
                let termLatDeg = termLatRad * 180.0 / .pi
                coordinates.append(GeoCoordinate(latitude: termLatDeg, longitude: lonDeg))
            }
            lonDeg += stepDegrees
        }

        return coordinates
    }

    /// Determines whether a given coordinate is in daylight, twilight, or night
    public nonisolated static func solarElevation(for coord: GeoCoordinate, at date: Date = Date()) -> Double {
        let subSolar = calculate(at: date)
        let lat1 = coord.latitude * .pi / 180.0
        let lat2 = subSolar.latitude * .pi / 180.0
        let deltaLon = (coord.longitude - subSolar.longitude) * .pi / 180.0

        // sin(elevation) = sin(lat1)*sin(lat2) + cos(lat1)*cos(lat2)*cos(deltaLon)
        let sinAlt = sin(lat1) * sin(lat2) + cos(lat1) * cos(lat2) * cos(deltaLon)
        let elevationRad = asin(max(-1.0, min(1.0, sinAlt)))
        return elevationRad * 180.0 / .pi
    }

    public enum IlluminationState: String, Sendable {
        case daylight = "Daylight"
        case greylineCivil = "Civil Greyline"      // 0° to -6° (Optimal DX)
        case greylineNautical = "Nautical Twilight" // -6° to -12°
        case night = "Night"                       // < -12°
    }

    public nonisolated static func illuminationState(for coord: GeoCoordinate, at date: Date = Date()) -> IlluminationState {
        let elevation = solarElevation(for: coord, at: date)
        if elevation >= 0.0 {
            return .daylight
        } else if elevation >= -6.0 {
            return .greylineCivil
        } else if elevation >= -12.0 {
            return .greylineNautical
        } else {
            return .night
        }
    }

    /// Calculates Sunrise and Sunset times for a given coordinate on the current UTC date
    public nonisolated static func sunriseSunset(for coord: GeoCoordinate, date: Date = Date()) -> (sunrise: String, sunset: String) {
        let subSolar = calculate(at: date)
        let decRad = subSolar.latitude * .pi / 180.0
        let latRad = coord.latitude * .pi / 180.0

        // Standard refraction zenith: 90.833° (90° 50')
        let zenithRad = 90.833 * .pi / 180.0
        let cosH = (cos(zenithRad) - sin(latRad) * sin(decRad)) / (cos(latRad) * cos(decRad))

        // Polar day / Polar night checks
        if cosH > 1.0 {
            return ("Polar Night", "Polar Night")
        } else if cosH < -1.0 {
            return ("Midnight Sun", "Midnight Sun")
        }

        let hourAngleDeg = acos(cosH) * 180.0 / .pi
        let noonUTC = 12.0 - (coord.longitude / 15.0) - (subSolar.equationOfTimeMinutes / 60.0)

        let sunriseUTC = (noonUTC - hourAngleDeg / 15.0).truncatingRemainder(dividingBy: 24.0)
        let sunsetUTC = (noonUTC + hourAngleDeg / 15.0).truncatingRemainder(dividingBy: 24.0)

        let normSunrise = sunriseUTC < 0 ? sunriseUTC + 24.0 : sunriseUTC
        let normSunset = sunsetUTC < 0 ? sunsetUTC + 24.0 : sunsetUTC

        let sRiseH = Int(normSunrise)
        let sRiseM = Int((normSunrise - Double(sRiseH)) * 60.0)

        let sSetH = Int(normSunset)
        let sSetM = Int((normSunset - Double(sSetH)) * 60.0)

        return (
            String(format: "%02d:%02d UTC", sRiseH, sRiseM),
            String(format: "%02d:%02d UTC", sSetH, sSetM)
        )
    }

    public enum SolarEventType: String, Sendable {
        case sunrise = "Sunrise"
        case sunset = "Sunset"
    }

    public struct StationSolarStatus: Equatable, Sendable {
        public let elevationDeg: Double
        public let illumination: SolarEphemeris.IlluminationState
        public let nextEvent: SolarEventType
        public let nextEventDate: Date?
        public let countdownText: String
        public let isGreylineActive: Bool
        public let lowBandDuctingEfficiency: Double // 0.0 ... 1.0

        public init(
            elevationDeg: Double,
            illumination: SolarEphemeris.IlluminationState,
            nextEvent: SolarEventType,
            nextEventDate: Date?,
            countdownText: String,
            isGreylineActive: Bool,
            lowBandDuctingEfficiency: Double
        ) {
            self.elevationDeg = elevationDeg
            self.illumination = illumination
            self.nextEvent = nextEvent
            self.nextEventDate = nextEventDate
            self.countdownText = countdownText
            self.isGreylineActive = isGreylineActive
            self.lowBandDuctingEfficiency = lowBandDuctingEfficiency
        }
    }

    /// Generates coordinates along a specific solar elevation contour (e.g. 0° terminator, -6° civil twilight, -12° nautical twilight)
    public nonisolated static func twilightCoordinates(elevationDeg: Double, at date: Date = Date(), stepDegrees: Double = 2.0) -> [GeoCoordinate] {
        let subSolar = calculate(at: date)
        let decRad = subSolar.latitude * .pi / 180.0
        let sunLonRad = subSolar.longitude * .pi / 180.0
        let sinH = sin(elevationDeg * .pi / 180.0)

        var coordinates: [GeoCoordinate] = []
        var lonDeg = -180.0
        while lonDeg <= 180.0 {
            let lonRad = lonDeg * .pi / 180.0
            let deltaLon = lonRad - sunLonRad

            let A = sin(decRad)
            let B = cos(decRad) * cos(deltaLon)
            let R = sqrt(A * A + B * B)

            if R < 1e-6 {
                coordinates.append(GeoCoordinate(latitude: 0.0, longitude: lonDeg))
            } else if abs(sinH / R) <= 1.0 {
                let alpha = atan2(B, A)
                let phi1 = (asin(sinH / R) - alpha) * 180.0 / .pi
                var norm1 = phi1
                while norm1 > 180 { norm1 -= 360 }
                while norm1 < -180 { norm1 += 360 }

                let phi2 = (.pi - asin(sinH / R) - alpha) * 180.0 / .pi
                var norm2 = phi2
                while norm2 > 180 { norm2 -= 360 }
                while norm2 < -180 { norm2 += 360 }

                let termLatDeg: Double
                if abs(tan(decRad)) < 1e-6 {
                    termLatDeg = cos(deltaLon) > 0 ? -90.0 : 90.0
                } else {
                    termLatDeg = atan(-cos(deltaLon) / tan(decRad)) * 180.0 / .pi
                }

                let valid1 = abs(norm1) <= 90.0
                let valid2 = abs(norm2) <= 90.0

                let chosen: Double
                if valid1 && valid2 {
                    chosen = abs(norm1 - termLatDeg) < abs(norm2 - termLatDeg) ? norm1 : norm2
                } else if valid1 {
                    chosen = norm1
                } else if valid2 {
                    chosen = norm2
                } else {
                    chosen = termLatDeg > 0 ? 90.0 : -90.0
                }

                coordinates.append(GeoCoordinate(latitude: chosen, longitude: lonDeg))
            } else {
                let latDeg = (sinH > 0 ? (A >= 0 ? 90.0 : -90.0) : (A >= 0 ? -90.0 : 90.0))
                coordinates.append(GeoCoordinate(latitude: latDeg, longitude: lonDeg))
            }
            lonDeg += stepDegrees
        }
        return coordinates
    }

    /// Computes the next upcoming solar event (Sunrise / Sunset) and precise countdown
    public nonisolated static func nextSolarEvent(for coord: GeoCoordinate, at date: Date = Date()) -> (event: SolarEventType, date: Date?, countdownMinutes: Int, countdownText: String) {
        let calendar = Calendar(identifier: .gregorian)
        var calUTC = calendar
        calUTC.timeZone = TimeZone(secondsFromGMT: 0)!

        let subSolar = calculate(at: date)
        let decRad = subSolar.latitude * .pi / 180.0
        let latRad = coord.latitude * .pi / 180.0

        let zenithRad = 90.833 * .pi / 180.0
        let cosH = (cos(zenithRad) - sin(latRad) * sin(decRad)) / (cos(latRad) * cos(decRad))

        if cosH > 1.0 {
            return (.sunset, nil, 0, "Polar Night")
        } else if cosH < -1.0 {
            return (.sunset, nil, 0, "Midnight Sun")
        }

        let hourAngleDeg = acos(max(-1.0, min(1.0, cosH))) * 180.0 / .pi
        let noonUTC = 12.0 - (coord.longitude / 15.0) - (subSolar.equationOfTimeMinutes / 60.0)

        var sunriseUTC = (noonUTC - hourAngleDeg / 15.0).truncatingRemainder(dividingBy: 24.0)
        var sunsetUTC = (noonUTC + hourAngleDeg / 15.0).truncatingRemainder(dividingBy: 24.0)
        if sunriseUTC < 0 { sunriseUTC += 24.0 }
        if sunsetUTC < 0 { sunsetUTC += 24.0 }

        let startOfDay = calUTC.startOfDay(for: date)
        var riseDate = startOfDay.addingTimeInterval(sunriseUTC * 3600.0)
        var setDate = startOfDay.addingTimeInterval(sunsetUTC * 3600.0)

        if riseDate < date { riseDate = riseDate.addingTimeInterval(86400.0) }
        if setDate < date { setDate = setDate.addingTimeInterval(86400.0) }

        let nextEvent: SolarEventType
        let nextDate: Date
        if riseDate < setDate {
            nextEvent = .sunrise
            nextDate = riseDate
        } else {
            nextEvent = .sunset
            nextDate = setDate
        }

        let diff = max(0, nextDate.timeIntervalSince(date))
        let minutes = Int(diff / 60.0)
        let h = minutes / 60
        let m = minutes % 60
        let countdownText: String
        if h > 0 {
            countdownText = "\(nextEvent.rawValue) in \(h)h \(m)m"
        } else {
            countdownText = "\(nextEvent.rawValue) in \(m)m"
        }

        return (nextEvent, nextDate, minutes, countdownText)
    }

    /// Evaluates live station solar illumination, twilight ducting efficiency, and next event countdown
    public nonisolated static func stationSolarStatus(for coord: GeoCoordinate, at date: Date = Date()) -> StationSolarStatus {
        let elev = solarElevation(for: coord, at: date)
        let illumination = illuminationState(for: coord, at: date)
        let nextEvent = nextSolarEvent(for: coord, at: date)

        let isGreyline = (elev <= 0.0 && elev >= -12.0)

        let ductingEff: Double
        if elev <= 1.0 && elev >= -13.0 {
            let distFromPeak = abs(elev - (-4.5))
            ductingEff = max(0.0, min(1.0, 1.0 - (distFromPeak / 8.5)))
        } else {
            ductingEff = 0.0
        }

        return StationSolarStatus(
            elevationDeg: elev,
            illumination: illumination,
            nextEvent: nextEvent.event,
            nextEventDate: nextEvent.date,
            countdownText: nextEvent.countdownText,
            isGreylineActive: isGreyline,
            lowBandDuctingEfficiency: ductingEff
        )
    }

    /// Determines if the Great Circle propagation path between two stations coincides with the Greyline duct
    public nonisolated static func isPathInGreyline(from: GeoCoordinate, to: GeoCoordinate, at date: Date = Date()) -> (isInGreyline: Bool, ductFactor: Double) {
        let fromElev = solarElevation(for: from, at: date)
        let toElev = solarElevation(for: to, at: date)

        let fromInGreyline = (fromElev <= 1.0 && fromElev >= -12.0)
        let toInGreyline = (toElev <= 1.0 && toElev >= -12.0)

        let waypoints = GeodesicMath.greatCircleWaypoints(from: from, to: to, count: 12)
        var greylineCount = 0
        var totalDuct = 0.0

        for wp in waypoints {
            let el = solarElevation(for: wp, at: date)
            if el <= 1.5 && el >= -12.5 {
                greylineCount += 1
                let dist = abs(el - (-4.5))
                totalDuct += max(0.0, 1.0 - (dist / 8.0))
            }
        }

        let fractionInGreyline = Double(greylineCount) / Double(waypoints.count)
        let avgDuct = totalDuct / Double(max(1, waypoints.count))

        if (fromInGreyline && toInGreyline) || fractionInGreyline >= 0.35 {
            let boost = (fromInGreyline && toInGreyline) ? 0.40 : 0.0
            return (true, min(1.0, avgDuct + boost))
        }

        return (false, 0.0)
    }
}

// MARK: - Geodesic & Great Circle Path Calculations

public nonisolated enum GeodesicMath {
    public static let earthRadiusKm: Double = 6371.0088
    public static let kmToMiles: Double = 0.621371

    /// Computes great circle distance between two points in km
    public static func distanceKm(from: GeoCoordinate, to: GeoCoordinate) -> Double {
        let lat1 = from.latitude * .pi / 180.0
        let lat2 = to.latitude * .pi / 180.0
        let deltaLat = (to.latitude - from.latitude) * .pi / 180.0
        let deltaLon = (to.longitude - from.longitude) * .pi / 180.0

        let a = sin(deltaLat / 2.0) * sin(deltaLat / 2.0) +
                cos(lat1) * cos(lat2) *
                sin(deltaLon / 2.0) * sin(deltaLon / 2.0)
        let c = 2.0 * atan2(sqrt(a), sqrt(max(0.0, 1.0 - a)))
        return earthRadiusKm * c
    }

    /// Computes initial Short Path (SP) bearing from origin to target in degrees (0° - 360°)
    public nonisolated static func initialBearing(from: GeoCoordinate, to: GeoCoordinate) -> Double {
        let lat1 = from.latitude * .pi / 180.0
        let lat2 = to.latitude * .pi / 180.0
        let deltaLon = (to.longitude - from.longitude) * .pi / 180.0

        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let bearingRad = atan2(y, x)
        let bearingDeg = bearingRad * 180.0 / .pi
        return bearingDeg < 0 ? bearingDeg + 360.0 : bearingDeg
    }

    /// Computes Long Path (LP) bearing in degrees (0° - 360°)
    public nonisolated static func longPathBearing(from: GeoCoordinate, to: GeoCoordinate) -> Double {
        let sp = initialBearing(from: from, to: to)
        return (sp + 180.0).truncatingRemainder(dividingBy: 360.0)
    }

    /// Computes Long Path (LP) distance in km
    public nonisolated static func longPathDistanceKm(from: GeoCoordinate, to: GeoCoordinate) -> Double {
        let spDist = distanceKm(from: from, to: to)
        let earthCircumference = 2.0 * .pi * earthRadiusKm
        return max(0.0, earthCircumference - spDist)
    }

    /// Returns intermediate points along the Great Circle arc between origin and target (for smooth 3D/2D curve drawing)
    public nonisolated static func greatCircleWaypoints(from: GeoCoordinate, to: GeoCoordinate, count: Int = 30) -> [GeoCoordinate] {
        guard count >= 2 else { return [from, to] }

        let lat1 = from.latitude * .pi / 180.0
        let lon1 = from.longitude * .pi / 180.0
        let lat2 = to.latitude * .pi / 180.0
        let lon2 = to.longitude * .pi / 180.0

        // Angular distance d
        let deltaLat = lat2 - lat1
        let deltaLon = lon2 - lon1
        let a = sin(deltaLat / 2.0) * sin(deltaLat / 2.0) +
                cos(lat1) * cos(lat2) * sin(deltaLon / 2.0) * sin(deltaLon / 2.0)
        let d = 2.0 * atan2(sqrt(a), sqrt(max(0.0, 1.0 - a)))

        if d < 1e-6 { return [from, to] }

        var points: [GeoCoordinate] = []
        for i in 0..<count {
            let f = Double(i) / Double(count - 1)
            let A = sin((1.0 - f) * d) / sin(d)
            let B = sin(f * d) / sin(d)

            let x = A * cos(lat1) * cos(lon1) + B * cos(lat2) * cos(lon2)
            let y = A * cos(lat1) * sin(lon1) + B * cos(lat2) * sin(lon2)
            let z = A * sin(lat1) + B * sin(lat2)

            let ptLat = atan2(z, sqrt(x * x + y * y)) * 180.0 / .pi
            let ptLon = atan2(y, x) * 180.0 / .pi

            points.append(GeoCoordinate(latitude: ptLat, longitude: ptLon))
        }

        return points
    }

    /// Formats bearing to compass cardinal string (e.g. 295° -> WNW)
    public nonisolated static func compassCardinal(for bearing: Double) -> String {
        let directions = [
            "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"
        ]
        let rawIndex = Int(round(bearing / 22.5)) % 16
        let safeIndex = rawIndex < 0 ? rawIndex + 16 : rawIndex
        return directions[safeIndex]
    }

    /// Converts a GeoCoordinate into a 4-character Maidenhead locator (e.g. LL65)
    public nonisolated static func maidenheadLocator(from coord: GeoCoordinate) -> String {
        var lon = coord.longitude + 180.0
        var lat = coord.latitude + 90.0

        lon = max(0.0, min(359.9999, lon))
        lat = max(0.0, min(179.9999, lat))

        let fieldLon = Int(lon / 20.0)
        let fieldLat = Int(lat / 10.0)

        let remLon1 = lon.truncatingRemainder(dividingBy: 20.0)
        let remLat1 = lat.truncatingRemainder(dividingBy: 10.0)

        let squareLon = Int(remLon1 / 2.0)
        let squareLat = Int(remLat1 / 1.0)

        let charA = Character(UnicodeScalar(UInt8(Character("A").asciiValue! + UInt8(fieldLon))))
        let charB = Character(UnicodeScalar(UInt8(Character("A").asciiValue! + UInt8(fieldLat))))

        return "\(charA)\(charB)\(squareLon)\(squareLat)"
    }
}

// MARK: - Astronomical Lunar Ephemeris for EME & DXing

public struct SubLunarPosition: Equatable, Sendable {
    public let latitude: Double   // Moon Declination (-28.5° to +28.5°)
    public let longitude: Double  // Sub-lunar Longitude (-180° to +180°)
    public let phasePercent: Double // 0% (New) to 100% (Full)
}

public struct LunarEphemeris {
    /// Computes the Sub-Lunar Point and Phase for a given date (Meeus/Schlyter algorithm)
    public nonisolated static func calculate(at date: Date = Date()) -> SubLunarPosition {
        // Days since J2000.0 (2000-01-01 12:00:00 UTC)
        let j2000 = Date(timeIntervalSince1970: 946728000)
        let d = date.timeIntervalSince(j2000) / 86400.0

        // Moon mean orbital elements in degrees
        let L = (218.316 + 13.176396 * d).truncatingRemainder(dividingBy: 360.0) * .pi / 180.0
        let M = (134.963 + 13.064993 * d).truncatingRemainder(dividingBy: 360.0) * .pi / 180.0
        let F = (93.272 + 13.229350 * d).truncatingRemainder(dividingBy: 360.0) * .pi / 180.0

        // Ecliptic coordinates of the Moon
        let lambda = L + (6.289 * .pi / 180.0) * sin(M)
        let beta = (5.128 * .pi / 180.0) * sin(F)

        // Earth obliquity
        let eps = 23.439 * .pi / 180.0

        // Equatorial coordinates (Right Ascension alpha & Declination delta)
        let sinDelta = sin(beta) * cos(eps) + cos(beta) * sin(eps) * sin(lambda)
        let deltaRad = asin(max(-1.0, min(1.0, sinDelta)))
        let declinationDeg = deltaRad * 180.0 / .pi

        let y = sin(lambda) * cos(eps) - tan(beta) * sin(eps)
        let x = cos(lambda)
        var raRad = atan2(y, x)
        if raRad < 0 { raRad += 2.0 * .pi }
        let raDeg = raRad * 180.0 / .pi

        // Greenwich Mean Sidereal Time (GMST) in degrees
        let calendar = Calendar(identifier: .gregorian)
        var calUTC = calendar
        calUTC.timeZone = TimeZone(secondsFromGMT: 0)!
        let hour = Double(calUTC.component(.hour, from: date))
        let minute = Double(calUTC.component(.minute, from: date))
        let second = Double(calUTC.component(.second, from: date))
        let utHours = hour + minute / 60.0 + second / 3600.0

        let gmstDeg = (280.46061837 + 360.98564736629 * d + utHours * 15.0).truncatingRemainder(dividingBy: 360.0)

        // Sub-lunar longitude = GMST - RA (normalized to -180...180)
        var subLon = (gmstDeg - raDeg).truncatingRemainder(dividingBy: 360.0)
        if subLon > 180.0 { subLon -= 360.0 }
        if subLon < -180.0 { subLon += 360.0 }

        // Moon phase estimation
        let sunL = (280.466 + 0.9856474 * d).truncatingRemainder(dividingBy: 360.0) * .pi / 180.0
        let elongation = abs(L - sunL)
        let phase = (1.0 - cos(elongation)) / 2.0 * 100.0

        return SubLunarPosition(
            latitude: max(-28.5, min(28.5, declinationDeg)),
            longitude: subLon,
            phasePercent: phase
        )
    }
}
