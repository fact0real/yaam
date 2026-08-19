//
//  GridLocator.swift
//  YAAM
//

import Foundation

nonisolated enum GridLocator {
    private enum Axis {
        case latitude
        case longitude

        var limit: Double {
            switch self {
            case .latitude: return 90
            case .longitude: return 180
            }
        }

        func accepts(hemisphere: Character) -> Bool {
            switch self {
            case .latitude: return hemisphere == "N" || hemisphere == "S"
            case .longitude: return hemisphere == "E" || hemisphere == "W"
            }
        }
    }

    static func fourCharacterGrid(from rawGrid: String) -> String? {
        let value = rawGrid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard value.count >= 4 else { return nil }

        let characters = Array(value.prefix(4))
        guard
            let longitudeField = characters[0].asciiValue,
            let latitudeField = characters[1].asciiValue,
            longitudeField >= Character("A").asciiValue!,
            longitudeField <= Character("R").asciiValue!,
            latitudeField >= Character("A").asciiValue!,
            latitudeField <= Character("R").asciiValue!,
            characters[2].wholeNumberValue != nil,
            characters[3].wholeNumberValue != nil
        else {
            return nil
        }

        return String(characters)
    }

    static func fourCharacterGrid(latitude rawLatitude: String, longitude rawLongitude: String) -> String? {
        guard
            let latitude = coordinate(from: rawLatitude, axis: .latitude),
            let longitude = coordinate(from: rawLongitude, axis: .longitude)
        else {
            return nil
        }

        return fourCharacterGrid(latitude: latitude, longitude: longitude)
    }

    static func fourCharacterGrid(latitude: Double, longitude: Double) -> String? {
        guard
            latitude.isFinite,
            longitude.isFinite,
            (-90...90).contains(latitude),
            (-180...180).contains(longitude)
        else {
            return nil
        }

        let boundedLatitude = min(latitude, 89.999_999_999)
        let boundedLongitude = min(longitude, 179.999_999_999)
        let shiftedLatitude = boundedLatitude + 90
        let shiftedLongitude = boundedLongitude + 180

        let longitudeFieldIndex = Int(floor(shiftedLongitude / 20))
        let latitudeFieldIndex = Int(floor(shiftedLatitude / 10))
        let longitudeSquare = Int(floor(shiftedLongitude.truncatingRemainder(dividingBy: 20) / 2))
        let latitudeSquare = Int(floor(shiftedLatitude.truncatingRemainder(dividingBy: 10)))

        guard
            let longitudeField = UnicodeScalar(65 + UInt32(longitudeFieldIndex)),
            let latitudeField = UnicodeScalar(65 + UInt32(latitudeFieldIndex))
        else {
            return nil
        }

        return "\(Character(longitudeField))\(Character(latitudeField))\(longitudeSquare)\(latitudeSquare)"
    }

    private static func coordinate(from rawValue: String, axis: Axis) -> Double? {
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: ",", with: ".")
        guard !value.isEmpty else { return nil }

        let hemisphere = value.first(where: { "NSEW".contains($0) })
        if let hemisphere, !axis.accepts(hemisphere: hemisphere) {
            return nil
        }

        let pattern = #"[-+]?\d+(?:\.\d+)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let components = expression.matches(in: value, range: range).compactMap { match -> Double? in
            guard let componentRange = Range(match.range, in: value) else { return nil }
            return Double(value[componentRange])
        }
        guard let rawDegrees = components.first, components.count <= 3 else { return nil }

        let minutes = components.count > 1 ? abs(components[1]) : 0
        let seconds = components.count > 2 ? abs(components[2]) : 0
        guard minutes < 60, seconds < 60 else { return nil }

        let magnitude = abs(rawDegrees) + minutes / 60 + seconds / 3600
        let sign: Double
        if let hemisphere {
            sign = hemisphere == "S" || hemisphere == "W" ? -1 : 1
        } else {
            sign = rawDegrees < 0 ? -1 : 1
        }

        let coordinate = magnitude * sign
        guard abs(coordinate) <= axis.limit else { return nil }
        return coordinate
    }
}
