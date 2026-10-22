import Foundation

nonisolated struct GridLocationPoint: Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    var latitudeText: String { String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), latitude) }
    var longitudeText: String { String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), longitude) }
}

nonisolated struct PreciseGridBounds: Equatable, Sendable {
    let grid: String
    let minLatitude: Double
    let minLongitude: Double
    let latitudeSize: Double
    let longitudeSize: Double
    var center: GridLocationPoint { GridLocationPoint(latitude: minLatitude + latitudeSize / 2, longitude: minLongitude + longitudeSize / 2)! }
    var heightMeters: Double { latitudeSize * 111_195 }
    var widthMeters: Double { longitudeSize * 111_195 * cos(center.latitude * .pi / 180) }
}

nonisolated enum PreciseGridLocator {
    static let precisions = [4, 6, 8, 10]

    static func coordinate(_ raw: String) -> Double? {
        let converted = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "٫", with: ".").replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "−", with: "-")
        let value = converted.map { character -> String in
            if let digit = character.wholeNumberValue, (0...9).contains(digit) { return String(digit) }
            return String(character)
        }.joined()
        guard let number = Double(value), number.isFinite else { return nil }
        return number
    }

    static func point(latitude: String, longitude: String) -> GridLocationPoint? {
        guard let lat = coordinate(latitude), let lon = coordinate(longitude) else { return nil }
        return GridLocationPoint(latitude: lat, longitude: lon)
    }

    static func locator(_ point: GridLocationPoint, length: Int) -> String? {
        guard [2, 4, 6, 8, 10].contains(length) else { return nil }
        var x = min(point.longitude + 180, 360.0.nextDown)
        var y = min(point.latitude + 90, 180.0.nextDown)
        var dx = 20.0, dy = 10.0
        let fieldX = min(17, Int(floor(x / dx))), fieldY = min(17, Int(floor(y / dy)))
        var result = String(UnicodeScalar(65 + fieldX)!) + String(UnicodeScalar(65 + fieldY)!)
        x -= Double(fieldX) * dx; y -= Double(fieldY) * dy
        for pair in 1..<(length / 2) {
            let count = pair % 2 == 1 ? 10 : 24
            dx /= Double(count); dy /= Double(count)
            let ix = min(count - 1, max(0, Int(floor(x / dx))))
            let iy = min(count - 1, max(0, Int(floor(y / dy))))
            let base = pair % 2 == 1 ? 48 : 65
            result += String(UnicodeScalar(base + ix)!) + String(UnicodeScalar(base + iy)!)
            x -= Double(ix) * dx; y -= Double(iy) * dy
        }
        return result
    }

    static func bounds(_ raw: String) -> PreciseGridBounds? {
        let grid = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let chars = Array(grid.utf8)
        guard [2, 4, 6, 8, 10].contains(chars.count),
              chars.allSatisfy({ $0 < 128 }), (65...82).contains(chars[0]), (65...82).contains(chars[1]) else { return nil }
        var dx = 20.0, dy = 10.0
        var x = Double(chars[0] - 65) * dx - 180
        var y = Double(chars[1] - 65) * dy - 90
        for pair in 1..<(chars.count / 2) {
            let digits = pair % 2 == 1
            let base: UInt8 = digits ? 48 : 65
            let count: UInt8 = digits ? 10 : 24
            let a = chars[pair * 2], b = chars[pair * 2 + 1]
            guard a >= base, a < base + count, b >= base, b < base + count else { return nil }
            dx /= Double(count); dy /= Double(count)
            x += Double(a - base) * dx; y += Double(b - base) * dy
        }
        return PreciseGridBounds(grid: grid, minLatitude: y, minLongitude: x, latitudeSize: dy, longitudeSize: dx)
    }
}

nonisolated struct StationLocationSelection: Equatable, Sendable {
    let point: GridLocationPoint
    let grid: String
    var latitude: String { point.latitudeText }
    var longitude: String { point.longitudeText }

    init?(point: GridLocationPoint, length: Int) {
        // Encode the same rounded coordinates that will be saved in the profile.
        guard let saved = PreciseGridLocator.point(latitude: point.latitudeText, longitude: point.longitudeText),
              let grid = PreciseGridLocator.locator(saved, length: length), PreciseGridLocator.precisions.contains(length) else { return nil }
        self.point = saved
        self.grid = grid
    }
}

nonisolated struct StationLocationFix: Equatable, Sendable {
    let point: GridLocationPoint
    let accuracy: Double
}

nonisolated enum StationLocationFixPolicy {
    static func accepts(point: GridLocationPoint?, accuracy: Double, timestamp: Date, now: Date) -> Bool {
        point != nil && accuracy.isFinite && accuracy >= 0 && now.timeIntervalSince(timestamp) >= -5 && now.timeIntervalSince(timestamp) <= 60
    }
}
