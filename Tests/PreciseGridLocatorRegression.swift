import Foundation

// Inert stand-in for log aggregation, which is unrelated to the shared geometry under test.
struct QSORecordModel {
    var fields: [String: String] = [:]
    var isConfirmed = false
    subscript(_ key: String) -> String { fields[key] ?? "" }
}

@main struct PreciseGridLocatorRegression {
    static func main() throws {
        let london = GridLocationPoint(latitude: 51.5074, longitude: -0.1278)!
        precondition(PreciseGridLocator.locator(london, length: 6) == "IO91WM")
        precondition(PreciseGridLocator.locator(GridLocationPoint(latitude: 0, longitude: 0)!, length: 4) == "JJ00")
        precondition(GridLocationPoint(latitude: .nan, longitude: 0) == nil)
        precondition(GridLocationPoint(latitude: 91, longitude: 0) == nil)
        precondition(GridLocationPoint(latitude: 0, longitude: .infinity) == nil)
        precondition(PreciseGridLocator.point(latitude: "۳۵٫۶۸۹۲", longitude: "۵۱٫۳۸۹۰") == GridLocationPoint(latitude: 35.6892, longitude: 51.389))
        precondition(PreciseGridLocator.point(latitude: "51,5074", longitude: "−0,1278") == london)
        for invalid in ["nan", "inf", "12junk", "51N", "12 34", "", "1.2.3"] {
            precondition(PreciseGridLocator.coordinate(invalid) == nil)
        }
        for invalid in ["", "IO9", "IO91W", "IO91WZ", "SS00", "IO91WMAB", "IO91WM12YY", "IO91WM12AAjunk", "IO۹۱", "IO91WM12A"] {
            precondition(PreciseGridLocator.bounds(invalid) == nil)
            precondition(MaidenheadGridEngine.boundingBox(for: invalid) == nil)
        }
        precondition(PreciseGridLocator.bounds(" io91wm12 ")?.grid == "IO91WM12")
        precondition(PreciseGridLocator.locator(london, length: 5) == nil)
        var seed: UInt64 = 385
        func random() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
        var points = [london, GridLocationPoint(latitude: -90, longitude: -180)!,
                      GridLocationPoint(latitude: 90, longitude: 180)!,
                      GridLocationPoint(latitude: 0, longitude: 180)!, GridLocationPoint(latitude: 0, longitude: -180)!]
        for _ in 0..<5_000 { points.append(GridLocationPoint(latitude: random() * 180 - 90, longitude: random() * 360 - 180)!) }
        for point in points {
            for length in [2, 4, 6, 8, 10] {
                let locator = PreciseGridLocator.locator(point, length: length)!
                let bounds = PreciseGridLocator.bounds(locator)!
                precondition(locator.count == length)
                precondition(PreciseGridLocator.locator(bounds.center, length: length) == locator)
                precondition(point.latitude >= bounds.minLatitude - 1e-10 && point.latitude <= bounds.minLatitude + bounds.latitudeSize + 1e-10)
                precondition(point.longitude >= bounds.minLongitude - 1e-10 && point.longitude <= bounds.minLongitude + bounds.longitudeSize + 1e-10)
                let shared = MaidenheadGridEngine.boundingBox(for: locator)!
                precondition(abs(shared.center.latitude - bounds.center.latitude) < 1e-12)
                precondition(abs(shared.center.longitude - bounds.center.longitude) < 1e-12)
                if length >= 4 {
                    let saved = StationLocationSelection(point: point, length: length)!
                    precondition(PreciseGridLocator.locator(PreciseGridLocator.point(latitude: saved.latitude, longitude: saved.longitude)!, length: length) == saved.grid)
                }
            }
        }
        let coarse = PreciseGridLocator.bounds("IO91WM")!
        let fine = PreciseGridLocator.bounds("IO91WM12AA")!
        precondition(abs(coarse.latitudeSize / fine.latitudeSize - 240) < 1e-9)
        precondition(fine.heightMeters < 20 && fine.widthMeters < 30)
        let now = Date(timeIntervalSince1970: 1_000)
        precondition(StationLocationFixPolicy.accepts(point: london, accuracy: 8, timestamp: now, now: now))
        precondition(!StationLocationFixPolicy.accepts(point: london, accuracy: -1, timestamp: now, now: now))
        precondition(!StationLocationFixPolicy.accepts(point: london, accuracy: .nan, timestamp: now, now: now))
        precondition(!StationLocationFixPolicy.accepts(point: london, accuracy: 8, timestamp: now.addingTimeInterval(-61), now: now))
        precondition(!StationLocationFixPolicy.accepts(point: london, accuracy: 8, timestamp: now.addingTimeInterval(6), now: now))
        precondition(!StationLocationFixPolicy.accepts(point: nil, accuracy: 8, timestamp: now, now: now))

        let original = StationProfile(name: "Portable", callsign: "W1TEST/P", qth: "Keep QTH", grid: "FN42", latitude: "42", longitude: "-71", country: "United States", radioModel: "Keep radio")
        let selection = StationLocationSelection(point: london, length: 10)!
        precondition(WeatherLocationPrecision.square.location(for: selection.grid)?.grid == String(selection.grid.prefix(4)))
        precondition(WeatherLocationPrecision.subsquare.location(for: selection.grid)?.grid == String(selection.grid.prefix(6)))
        precondition(GridLocator.fourCharacterGrid(from: selection.grid) == String(selection.grid.prefix(4)))
        let updated = selection.applying(to: original)
        precondition(updated.id == original.id && updated.callsign == original.callsign && updated.qth == original.qth && updated.radioModel == original.radioModel)
        precondition(updated.country == original.country && updated.createdAt == original.createdAt && updated.updatedAt == original.updatedAt)
        precondition(original.grid == "FN42" && updated.grid == selection.grid)
        let restored = try JSONDecoder().decode(StationProfile.self, from: JSONEncoder().encode(updated))
        precondition(restored == updated && restored.validationMessage() == nil)
        print("Precise grid regression passed: 25,025 round trips, poles/dateline, strict parsing, shared geometry, fix freshness and isolated profile draft updates.")
    }
}
