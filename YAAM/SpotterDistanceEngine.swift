//
//  SpotterDistanceEngine.swift
//  YAAM
//
//  Calculates Great-Circle distance and azimuth bearing from Maidenhead grid locators
//  to filter DX cluster spotters by physical proximity and propagation relevance.
//

import Foundation

public struct SpotterLocationInfo: Equatable, Sendable {
    public let distanceKm: Double
    public let bearingDeg: Double
    public let cardinalDirection: String

    public var distanceMiles: Double {
        distanceKm * 0.621371
    }

    public var formattedSummary: String {
        "\(Int(distanceKm.rounded())) km · \(Int(bearingDeg.rounded()))° \(cardinalDirection)"
    }
}

public enum SpotterDistanceEngine {
    private static let earthRadiusKm = 6371.0

    /// Converts a 4-char or 6-char Maidenhead grid locator to (latitude, longitude) center point
    public static func coordinates(forGrid rawGrid: String) -> (lat: Double, lon: Double)? {
        let grid = rawGrid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard grid.count >= 4 else { return nil }

        let chars = Array(grid)
        guard chars[0].isLetter, chars[1].isLetter,
              chars[2].isNumber, chars[3].isNumber else {
            return nil
        }

        let lonField = Double(chars[0].asciiValue! - Character("A").asciiValue!)
        let latField = Double(chars[1].asciiValue! - Character("A").asciiValue!)
        guard (0...17).contains(lonField), (0...17).contains(latField) else { return nil }

        let lonSquare = Double(chars[2].wholeNumberValue!)
        let latSquare = Double(chars[3].wholeNumberValue!)

        if grid.count >= 6, chars[4].isLetter, chars[5].isLetter {
            let lonSub = Double(chars[4].asciiValue! - Character("A").asciiValue!)
            let latSub = Double(chars[5].asciiValue! - Character("A").asciiValue!)
            guard (0...23).contains(lonSub), (0...23).contains(latSub) else { return nil }

            let lon = (lonField * 20.0 - 180.0) + (lonSquare * 2.0) + (lonSub * (2.0 / 24.0)) + (1.0 / 24.0)
            let lat = (latField * 10.0 - 90.0) + (latSquare * 1.0) + (latSub * (1.0 / 24.0)) + (0.5 / 24.0)
            return (lat: lat, lon: lon)
        } else {
            let lon = (lonField * 20.0 - 180.0) + (lonSquare * 2.0) + 1.0
            let lat = (latField * 10.0 - 90.0) + (latSquare * 1.0) + 0.5
            return (lat: lat, lon: lon)
        }
    }

    /// Calculates distance (km) and bearing (degrees) between two Maidenhead locators
    public static func locationInfo(fromGrid: String, toGrid: String) -> SpotterLocationInfo? {
        guard let fromCoord = coordinates(forGrid: fromGrid),
              let toCoord = coordinates(forGrid: toGrid) else {
            return nil
        }

        let lat1 = fromCoord.lat * .pi / 180.0
        let lon1 = fromCoord.lon * .pi / 180.0
        let lat2 = toCoord.lat * .pi / 180.0
        let lon2 = toCoord.lon * .pi / 180.0

        let dLat = lat2 - lat1
        let dLon = lon2 - lon1

        let a = sin(dLat / 2.0) * sin(dLat / 2.0) +
                cos(lat1) * cos(lat2) * sin(dLon / 2.0) * sin(dLon / 2.0)
        let c = 2.0 * atan2(sqrt(a), sqrt(max(0.0, 1.0 - a)))
        let distanceKm = earthRadiusKm * c

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        var bearingDeg = atan2(y, x) * 180.0 / .pi
        if bearingDeg < 0.0 {
            bearingDeg += 360.0
        }

        let cardinal = cardinalDirection(for: bearingDeg)

        return SpotterLocationInfo(
            distanceKm: distanceKm,
            bearingDeg: bearingDeg,
            cardinalDirection: cardinal
        )
    }

    /// Determines cardinal compass direction (16-point compass)
    public static func cardinalDirection(for bearing: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                          "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int(((bearing + 11.25).truncatingRemainder(dividingBy: 360.0)) / 22.5)
        return directions[max(0, min(index, directions.count - 1))]
    }
}
