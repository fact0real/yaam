//
//  AstronomicalSolarEngine.swift
//  YAAM
//

import Foundation

// MARK: - Astronomical Solar, Lunar & Geodesic Calculation Engine

public struct GeoCoordinate: Equatable, Hashable, Sendable, Codable {
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

public struct SubSolarPosition: Equatable, Sendable {
    public let latitude: Double   // Solar Declination (-23.44° to +23.44°)
    public let longitude: Double  // Sub-solar Longitude (-180° to +180°)
    public let equationOfTimeMinutes: Double
    public let greenwichHourAngleDeg: Double
}

public struct SolarEphemeris {
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
    public static func terminatorCoordinates(at date: Date = Date(), stepDegrees: Double = 2.0) -> [GeoCoordinate] {
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
    public static func solarElevation(for coord: GeoCoordinate, at date: Date = Date()) -> Double {
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

    public static func illuminationState(for coord: GeoCoordinate, at date: Date = Date()) -> IlluminationState {
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
    public static func sunriseSunset(for coord: GeoCoordinate, date: Date = Date()) -> (sunrise: String, sunset: String) {
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
}

// MARK: - Geodesic & Great Circle Path Calculations

public enum GeodesicMath {
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
    public static func initialBearing(from: GeoCoordinate, to: GeoCoordinate) -> Double {
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
    public static func longPathBearing(from: GeoCoordinate, to: GeoCoordinate) -> Double {
        let sp = initialBearing(from: from, to: to)
        return (sp + 180.0).truncatingRemainder(dividingBy: 360.0)
    }

    /// Computes Long Path (LP) distance in km
    public static func longPathDistanceKm(from: GeoCoordinate, to: GeoCoordinate) -> Double {
        let spDist = distanceKm(from: from, to: to)
        let earthCircumference = 2.0 * .pi * earthRadiusKm
        return max(0.0, earthCircumference - spDist)
    }

    /// Returns intermediate points along the Great Circle arc between origin and target (for smooth 3D/2D curve drawing)
    public static func greatCircleWaypoints(from: GeoCoordinate, to: GeoCoordinate, count: Int = 30) -> [GeoCoordinate] {
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
    public static func compassCardinal(for bearing: Double) -> String {
        let directions = [
            "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"
        ]
        let rawIndex = Int(round(bearing / 22.5)) % 16
        let safeIndex = rawIndex < 0 ? rawIndex + 16 : rawIndex
        return directions[safeIndex]
    }
}
