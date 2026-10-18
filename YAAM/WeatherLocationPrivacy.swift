import Foundation

/// Only this resolved position may be used in an Open-Meteo request.
nonisolated enum WeatherLocationPrecision: String, CaseIterable, Identifiable {
    case square = "square4"
    case subsquare = "subsquare6"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .square: return "Approximate · 4-character square"
        case .subsquare: return "Precise · up to 6-character locator"
        }
    }

    func location(for rawGrid: String) -> (grid: String, latitude: Double, longitude: Double)? {
        let value = rawGrid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let chars = Array(value.utf8)
        guard [4, 6, 8, 10].contains(chars.count),
              (65...82).contains(chars[0]), (65...82).contains(chars[1]),
              (48...57).contains(chars[2]), (48...57).contains(chars[3]) else { return nil }
        // Validate the whole locator before discarding precision. Never interpret malformed text as a location.
        for index in stride(from: 4, to: chars.count, by: 2) {
            let range: ClosedRange<UInt8> = index == 6 ? 48...57 : 65...88
            guard range.contains(chars[index]), range.contains(chars[index + 1]) else { return nil }
        }
        var lon = Double(chars[0] - 65) * 20 - 180 + Double(chars[2] - 48) * 2 + 1
        var lat = Double(chars[1] - 65) * 10 - 90 + Double(chars[3] - 48) + 0.5
        let precise = self == .subsquare && chars.count >= 6
        if precise {
            lon += Double(chars[4] - 65) / 12 + 1.0 / 24 - 1
            lat += Double(chars[5] - 65) / 24 + 1.0 / 48 - 0.5
        }
        return (String(value.prefix(precise ? 6 : 4)), lat, lon)
    }
}
