//
//  POTAParkDirectory.swift
//  YAAM
//
//  Offline Directory of POTA (Parks on the Air) and SOTA (Summits on the Air)
//  Fast local search by reference, name, country/state, and GPS/Grid proximity.
//

import Combine
import CoreLocation
import Foundation

@MainActor
public final class POTAParkDirectory: ObservableObject {
    public static let shared = POTAParkDirectory()

    @Published public private(set) var entries: [ParkDirectoryEntry] = []
    @Published public private(set) var isLoaded: Bool = false

    private init() {
        loadCuratedDirectory()
    }

    // MARK: - Search
    public func search(query: String, limit: Int = 50) -> [ParkDirectoryEntry] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanQuery.isEmpty else {
            return Array(entries.prefix(limit))
        }

        return entries.filter { entry in
            entry.reference.uppercased().contains(cleanQuery) ||
            entry.name.uppercased().contains(cleanQuery) ||
            entry.country.uppercased().contains(cleanQuery) ||
            entry.stateOrRegion.uppercased().contains(cleanQuery) ||
            entry.gridSquare.uppercased().contains(cleanQuery)
        }.prefix(limit).map { $0 }
    }

    // MARK: - Proximity Search
    public func nearestParks(to coordinate: CLLocationCoordinate2D, maxRadiusKm: Double = 500.0, limit: Int = 20) -> [(entry: ParkDirectoryEntry, distanceKm: Double)] {
        let sorted = entries.compactMap { entry -> (entry: ParkDirectoryEntry, distanceKm: Double)? in
            guard entry.latitude != 0.0 || entry.longitude != 0.0 else { return nil }
            let d = entry.distance(from: coordinate)
            guard d <= maxRadiusKm else { return nil }
            return (entry, d)
        }.sorted { $0.distanceKm < $1.distanceKm }

        return Array(sorted.prefix(limit))
    }

    public func nearestParks(toGrid grid: String, maxRadiusKm: Double = 500.0, limit: Int = 20) -> [(entry: ParkDirectoryEntry, distanceKm: Double)] {
        guard let box = MaidenheadGridEngine.boundingBox(for: grid) else { return [] }
        let coord = CLLocationCoordinate2D(latitude: box.center.latitude, longitude: box.center.longitude)
        return nearestParks(to: coord, maxRadiusKm: maxRadiusKm, limit: limit)
    }

    public func lookup(reference: String) -> ParkDirectoryEntry? {
        let cleanRef = reference.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return entries.first { $0.reference.uppercased() == cleanRef }
    }

    // MARK: - Pre-populated Curated Directory
    private func loadCuratedDirectory() {
        // High-interest parks & summits worldwide (US, Canada, Europe, Middle East, Japan, Australia)
        var list: [ParkDirectoryEntry] = []

        // Iran & Middle East (EP) Parks & Summits
        list.append(ParkDirectoryEntry(reference: "EP-0001", name: "Golestan National Park", program: .pota, country: "Iran", stateOrRegion: "Golestan", gridSquare: "LM57", latitude: 37.38, longitude: 55.80))
        list.append(ParkDirectoryEntry(reference: "EP-0002", name: "Kavir National Park", program: .pota, country: "Iran", stateOrRegion: "Semnan", gridSquare: "LM34", latitude: 34.70, longitude: 52.18))
        list.append(ParkDirectoryEntry(reference: "EP-0003", name: "Khar Turan National Park", program: .pota, country: "Iran", stateOrRegion: "Semnan", gridSquare: "LM65", latitude: 35.80, longitude: 56.10))
        list.append(ParkDirectoryEntry(reference: "EP-0004", name: "Urmia Lake National Park", program: .pota, country: "Iran", stateOrRegion: "West Azerbaijan", gridSquare: "LN07", latitude: 37.75, longitude: 45.30))
        list.append(ParkDirectoryEntry(reference: "EP-0005", name: "Lar National Park", program: .pota, country: "Iran", stateOrRegion: "Mazandaran", gridSquare: "LM35", latitude: 35.95, longitude: 51.90))
        list.append(ParkDirectoryEntry(reference: "EP-0006", name: "Kish Island Protected Area", program: .pota, country: "Iran", stateOrRegion: "Hormozgan", gridSquare: "LL46", latitude: 26.53, longitude: 53.98))
        list.append(ParkDirectoryEntry(reference: "EP-0007", name: "Qeshm Island Geopark", program: .pota, country: "Iran", stateOrRegion: "Hormozgan", gridSquare: "LL66", latitude: 26.85, longitude: 55.95))
        list.append(ParkDirectoryEntry(reference: "EP-0008", name: "Bakhtegan National Park", program: .pota, country: "Iran", stateOrRegion: "Fars", gridSquare: "LM49", latitude: 29.35, longitude: 53.60))
        list.append(ParkDirectoryEntry(reference: "EP/TE-001", name: "Mount Damavand (5609m)", program: .sota, country: "Iran", stateOrRegion: "Mazandaran", gridSquare: "LM35wx", latitude: 35.951, longitude: 52.110, elevationMeters: 5609))
        list.append(ParkDirectoryEntry(reference: "EP/TE-002", name: "Tochal Summit (3964m)", program: .sota, country: "Iran", stateOrRegion: "Tehran", gridSquare: "LM35su", latitude: 35.885, longitude: 51.417, elevationMeters: 3964))

        // Popular US & Canadian Parks
        list.append(ParkDirectoryEntry(reference: "K-0001", name: "Acadia National Park", program: .pota, country: "United States", stateOrRegion: "ME", gridSquare: "FN54", latitude: 44.35, longitude: -68.21))
        list.append(ParkDirectoryEntry(reference: "K-0002", name: "Arches National Park", program: .pota, country: "United States", stateOrRegion: "UT", gridSquare: "DM58", latitude: 38.68, longitude: -109.57))
        list.append(ParkDirectoryEntry(reference: "K-0020", name: "Grand Canyon National Park", program: .pota, country: "United States", stateOrRegion: "AZ", gridSquare: "DM36", latitude: 36.05, longitude: -112.14))
        list.append(ParkDirectoryEntry(reference: "K-0025", name: "Great Smoky Mountains National Park", program: .pota, country: "United States", stateOrRegion: "NC/TN", gridSquare: "EM85", latitude: 35.68, longitude: -83.53))
        list.append(ParkDirectoryEntry(reference: "K-0044", name: "Olympic National Park", program: .pota, country: "United States", stateOrRegion: "WA", gridSquare: "CN87", latitude: 47.80, longitude: -123.60))
        list.append(ParkDirectoryEntry(reference: "K-0062", name: "Rocky Mountain National Park", program: .pota, country: "United States", stateOrRegion: "CO", gridSquare: "DN70", latitude: 40.40, longitude: -105.58))
        list.append(ParkDirectoryEntry(reference: "K-0069", name: "Yellowstone National Park", program: .pota, country: "United States", stateOrRegion: "WY/MT/ID", gridSquare: "DN44", latitude: 44.60, longitude: -110.50))
        list.append(ParkDirectoryEntry(reference: "K-0071", name: "Yosemite National Park", program: .pota, country: "United States", stateOrRegion: "CA", gridSquare: "CM97", latitude: 37.86, longitude: -119.53))
        list.append(ParkDirectoryEntry(reference: "K-0073", name: "Zion National Park", program: .pota, country: "United States", stateOrRegion: "UT", gridSquare: "DM37", latitude: 37.30, longitude: -113.05))
        list.append(ParkDirectoryEntry(reference: "VE-0001", name: "Banff National Park", program: .pota, country: "Canada", stateOrRegion: "AB", gridSquare: "DO31", latitude: 51.18, longitude: -115.57))
        list.append(ParkDirectoryEntry(reference: "VE-0002", name: "Jasper National Park", program: .pota, country: "Canada", stateOrRegion: "AB", gridSquare: "DO22", latitude: 52.87, longitude: -118.08))

        // European Parks & Summits
        list.append(ParkDirectoryEntry(reference: "G-0001", name: "Lake District National Park", program: .pota, country: "United Kingdom", stateOrRegion: "England", gridSquare: "IO84", latitude: 54.45, longitude: -3.10))
        list.append(ParkDirectoryEntry(reference: "G-0002", name: "Peak District National Park", program: .pota, country: "United Kingdom", stateOrRegion: "England", gridSquare: "IO93", latitude: 53.35, longitude: -1.82))
        list.append(ParkDirectoryEntry(reference: "DL-0001", name: "Bavarian Forest National Park", program: .pota, country: "Germany", stateOrRegion: "Bavaria", gridSquare: "JN68", latitude: 48.95, longitude: 13.40))
        list.append(ParkDirectoryEntry(reference: "DL-0002", name: "Black Forest National Park", program: .pota, country: "Germany", stateOrRegion: "Baden-Württemberg", gridSquare: "JN48", latitude: 48.55, longitude: 8.22))
        list.append(ParkDirectoryEntry(reference: "F-0001", name: "Vanoise National Park", program: .pota, country: "France", stateOrRegion: "Savoie", gridSquare: "JN35", latitude: 45.33, longitude: 6.83))
        list.append(ParkDirectoryEntry(reference: "I-0001", name: "Gran Paradiso National Park", program: .pota, country: "Italy", stateOrRegion: "Valle d'Aosta", gridSquare: "JN35", latitude: 45.50, longitude: 7.30))
        list.append(ParkDirectoryEntry(reference: "EA-0001", name: "Picos de Europa National Park", program: .pota, country: "Spain", stateOrRegion: "Asturias", gridSquare: "IN73", latitude: 43.18, longitude: -4.83))

        // SOTA Classics
        list.append(ParkDirectoryEntry(reference: "W6/NC-423", name: "Mount Diablo (1173m)", program: .sota, country: "United States", stateOrRegion: "CA", gridSquare: "CM97", latitude: 37.88, longitude: -121.91, elevationMeters: 1173))
        list.append(ParkDirectoryEntry(reference: "W7W/KG-001", name: "Mount Rainier (4392m)", program: .sota, country: "United States", stateOrRegion: "WA", gridSquare: "CN86", latitude: 46.85, longitude: -121.76, elevationMeters: 4392))
        list.append(ParkDirectoryEntry(reference: "G/LD-001", name: "Scafell Pike (978m)", program: .sota, country: "United Kingdom", stateOrRegion: "England", gridSquare: "IO84", latitude: 54.45, longitude: -3.21, elevationMeters: 978))
        list.append(ParkDirectoryEntry(reference: "HB/VS-001", name: "Matterhorn (4478m)", program: .sota, country: "Switzerland", stateOrRegion: "Valais", gridSquare: "JN35", latitude: 45.97, longitude: 7.65, elevationMeters: 4478))

        self.entries = list
        self.isLoaded = true
    }
}
