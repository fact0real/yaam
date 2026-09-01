//
//  WorldVectorGeography.swift
//  YAAM
//
//  High-Precision Global Vector Coastlines, Borders & Cartographic Graticule Mesh
//  Optimized for NS6T-style Azimuthal Equidistant and Equirectangular projections.
//  Provides detailed continental contours, islands, country borders, and dynamic lat/lon curves.
//

import CoreGraphics
import Foundation
import SwiftUI

// MARK: - Country Entity Model

public struct WorldCountryEntity: Identifiable, Sendable {
    public let id: String // ISO 2-letter code
    public let name: String
    public let flag: String
    public let primaryPrefix: String
    public let center: GeoCoordinate
    public let cqZone: Int
    public let ituZone: Int
    public let labelOffset: CGPoint

    public init(
        id: String,
        name: String,
        flag: String,
        primaryPrefix: String,
        center: GeoCoordinate,
        cqZone: Int,
        ituZone: Int,
        labelOffset: CGPoint = .zero
    ) {
        self.id = id
        self.name = name
        self.flag = flag
        self.primaryPrefix = primaryPrefix
        self.center = center
        self.cqZone = cqZone
        self.ituZone = ituZone
        self.labelOffset = labelOffset
    }
}

// MARK: - Vector Polygon Model

public struct VectorCountryPolygon: Sendable {
    public let countryId: String
    public let countryName: String
    public let primaryPrefix: String
    public let fillColor: Color
    public let coordinates: [GeoCoordinate] // (lat, lon)

    public init(
        countryId: String,
        countryName: String,
        primaryPrefix: String,
        fillColor: Color = Color.white,
        coordinates: [GeoCoordinate]
    ) {
        self.countryId = countryId
        self.countryName = countryName
        self.primaryPrefix = primaryPrefix
        self.fillColor = fillColor
        self.coordinates = coordinates
    }
}

// MARK: - Vector Line Model (Borders & Graticules)

public struct VectorLineString: Sendable {
    public let coordinates: [GeoCoordinate]
    public let isMajor: Bool

    public init(coordinates: [GeoCoordinate], isMajor: Bool = false) {
        self.coordinates = coordinates
        self.isMajor = isMajor
    }
}

// MARK: - Global Vector Geography Engine

public enum WorldVectorGeography {

    // NS6T Authentic Cartographic Palette
    public static let colorOcean = Color(red: 0.37, green: 0.72, blue: 0.89)      // NS6T Sky Blue Ocean (#5EB8E3)
    public static let colorOceanDark = Color(red: 0.28, green: 0.58, blue: 0.75)  // Ocean Depth Tint
    public static let colorLand = Color(red: 0.98, green: 0.99, blue: 1.00)       // Pure Crisp White Land (#FAFCFF)
    public static let colorLandStroke = Color(red: 0.12, green: 0.20, blue: 0.30) // Dark Navy Coastline
    public static let colorBorder = Color(red: 0.45, green: 0.55, blue: 0.65)     // Slate Internal Border
    public static let colorGraticule = Color(red: 0.20, green: 0.45, blue: 0.65).opacity(0.40) // Cyan-Slate Mesh
    public static let colorGraticuleMajor = Color(red: 0.15, green: 0.35, blue: 0.55).opacity(0.65) // Equator / Prime Meridian

    // MARK: - Dynamic Lat / Lon Graticule Mesh Generator

    public static func generateGraticuleLines() -> [VectorLineString] {
        var lines: [VectorLineString] = []

        // 1. Latitude Parallels (every 15° from -75° to +75°)
        for lat in stride(from: -75.0, through: 75.0, by: 15.0) {
            var coords: [GeoCoordinate] = []
            for lon in stride(from: -180.0, through: 180.0, by: 3.0) {
                coords.append(GeoCoordinate(latitude: lat, longitude: lon))
            }
            lines.append(VectorLineString(coordinates: coords, isMajor: abs(lat) < 0.1))
        }

        // 2. Longitude Meridians (every 15° or 30° from -180° to 180°)
        for lon in stride(from: -180.0, through: 180.0, by: 30.0) {
            var coords: [GeoCoordinate] = []
            for lat in stride(from: -85.0, through: 85.0, by: 3.0) {
                coords.append(GeoCoordinate(latitude: lat, longitude: lon))
            }
            lines.append(VectorLineString(coordinates: coords, isMajor: abs(lon) < 0.1 || abs(abs(lon) - 180.0) < 0.1))
        }

        return lines
    }

    // MARK: - Detailed Country & DXCC Entity Anchors

    public static let countries: [WorldCountryEntity] = [
        WorldCountryEntity(id: "RU", name: "Russia", flag: "🇷🇺", primaryPrefix: "UA", center: GeoCoordinate(latitude: 61.5, longitude: 95.0), cqZone: 16, ituZone: 29),
        WorldCountryEntity(id: "CN", name: "China", flag: "🇨🇳", primaryPrefix: "BY", center: GeoCoordinate(latitude: 35.8, longitude: 104.2), cqZone: 24, ituZone: 44),
        WorldCountryEntity(id: "US", name: "United States", flag: "🇺🇸", primaryPrefix: "K", center: GeoCoordinate(latitude: 39.5, longitude: -98.3), cqZone: 5, ituZone: 8),
        WorldCountryEntity(id: "CA", name: "Canada", flag: "🇨🇦", primaryPrefix: "VE", center: GeoCoordinate(latitude: 56.1, longitude: -106.3), cqZone: 4, ituZone: 9),
        WorldCountryEntity(id: "BR", name: "Brazil", flag: "🇧🇷", primaryPrefix: "PY", center: GeoCoordinate(latitude: -14.2, longitude: -51.9), cqZone: 11, ituZone: 15),
        WorldCountryEntity(id: "AQ", name: "Antarctica", flag: "🇦🇶", primaryPrefix: "CE9", center: GeoCoordinate(latitude: -80.0, longitude: 0.0), cqZone: 39, ituZone: 71),
        WorldCountryEntity(id: "AU", name: "Australia", flag: "🇦🇺", primaryPrefix: "VK", center: GeoCoordinate(latitude: -25.2, longitude: 133.7), cqZone: 30, ituZone: 59),
        WorldCountryEntity(id: "IR", name: "Iran", flag: "🇮🇷", primaryPrefix: "EP", center: GeoCoordinate(latitude: 32.4, longitude: 53.7), cqZone: 21, ituZone: 40),
        WorldCountryEntity(id: "SA", name: "Saudi Arabia", flag: "🇸🇦", primaryPrefix: "HZ", center: GeoCoordinate(latitude: 23.8, longitude: 45.0), cqZone: 21, ituZone: 39),
        WorldCountryEntity(id: "IN", name: "India", flag: "🇮🇳", primaryPrefix: "VU", center: GeoCoordinate(latitude: 20.5, longitude: 78.9), cqZone: 22, ituZone: 41),
        WorldCountryEntity(id: "JP", name: "Japan", flag: "🇯🇵", primaryPrefix: "JA", center: GeoCoordinate(latitude: 36.2, longitude: 138.2), cqZone: 25, ituZone: 45),
        WorldCountryEntity(id: "GB", name: "United Kingdom", flag: "🇬🇧", primaryPrefix: "G", center: GeoCoordinate(latitude: 54.5, longitude: -2.5), cqZone: 14, ituZone: 27),
        WorldCountryEntity(id: "DE", name: "Germany", flag: "🇩🇪", primaryPrefix: "DL", center: GeoCoordinate(latitude: 51.1, longitude: 10.4), cqZone: 14, ituZone: 28),
        WorldCountryEntity(id: "FR", name: "France", flag: "🇫🇷", primaryPrefix: "F", center: GeoCoordinate(latitude: 46.2, longitude: 2.2), cqZone: 14, ituZone: 27),
        WorldCountryEntity(id: "IT", name: "Italy", flag: "🇮🇹", primaryPrefix: "I", center: GeoCoordinate(latitude: 41.8, longitude: 12.5), cqZone: 15, ituZone: 28),
        WorldCountryEntity(id: "ES", name: "Spain", flag: "🇪🇸", primaryPrefix: "EA", center: GeoCoordinate(latitude: 40.4, longitude: -3.7), cqZone: 14, ituZone: 37),
        WorldCountryEntity(id: "ZA", name: "South Africa", flag: "🇿🇦", primaryPrefix: "ZS", center: GeoCoordinate(latitude: -30.5, longitude: 25.0), cqZone: 38, ituZone: 57),
        WorldCountryEntity(id: "EG", name: "Egypt", flag: "🇪🇬", primaryPrefix: "SU", center: GeoCoordinate(latitude: 26.8, longitude: 30.8), cqZone: 34, ituZone: 38),
        WorldCountryEntity(id: "AR", name: "Argentina", flag: "🇦🇷", primaryPrefix: "LU", center: GeoCoordinate(latitude: -38.4, longitude: -63.6), cqZone: 13, ituZone: 14),
        WorldCountryEntity(id: "NZ", name: "New Zealand", flag: "🇳🇿", primaryPrefix: "ZL", center: GeoCoordinate(latitude: -40.9, longitude: 174.8), cqZone: 32, ituZone: 60),
        WorldCountryEntity(id: "GL", name: "Greenland", flag: "🇬🇱", primaryPrefix: "OX", center: GeoCoordinate(latitude: 72.0, longitude: -40.0), cqZone: 40, ituZone: 5)
    ]

    public static var countryBoundaries: [VectorCountryPolygon] { landmassPolygons }

    // MARK: - High-Resolution Global Landmasses & Island Polygons

    public static let landmassPolygons: [VectorCountryPolygon] = [
        // 1. North America & Central America
        VectorCountryPolygon(
            countryId: "NA",
            countryName: "North America",
            primaryPrefix: "K/VE/XE",
            coordinates: [
                // Alaska
                GeoCoordinate(latitude: 71.3, longitude: -156.5),
                GeoCoordinate(latitude: 70.5, longitude: -161.8),
                GeoCoordinate(latitude: 65.5, longitude: -168.0),
                GeoCoordinate(latitude: 64.5, longitude: -165.5),
                GeoCoordinate(latitude: 60.0, longitude: -166.5),
                GeoCoordinate(latitude: 58.5, longitude: -162.0),
                GeoCoordinate(latitude: 55.0, longitude: -163.0),
                GeoCoordinate(latitude: 57.0, longitude: -154.0),
                GeoCoordinate(latitude: 60.5, longitude: -145.0),
                GeoCoordinate(latitude: 58.0, longitude: -136.0),
                GeoCoordinate(latitude: 54.5, longitude: -130.5),
                // Canada West Coast
                GeoCoordinate(latitude: 51.0, longitude: -128.0),
                GeoCoordinate(latitude: 49.0, longitude: -124.0),
                // US West Coast
                GeoCoordinate(latitude: 46.2, longitude: -124.0),
                GeoCoordinate(latitude: 42.0, longitude: -124.5),
                GeoCoordinate(latitude: 38.0, longitude: -123.0),
                GeoCoordinate(latitude: 34.0, longitude: -120.0),
                GeoCoordinate(latitude: 32.5, longitude: -117.2),
                // Baja California
                GeoCoordinate(latitude: 28.0, longitude: -114.5),
                GeoCoordinate(latitude: 23.0, longitude: -110.0),
                GeoCoordinate(latitude: 24.5, longitude: -110.5),
                GeoCoordinate(latitude: 31.5, longitude: -114.5),
                // Mexico West & Central America
                GeoCoordinate(latitude: 22.0, longitude: -105.5),
                GeoCoordinate(latitude: 18.5, longitude: -103.5),
                GeoCoordinate(latitude: 16.0, longitude: -97.0),
                GeoCoordinate(latitude: 14.5, longitude: -92.5),
                GeoCoordinate(latitude: 13.5, longitude: -89.0),
                GeoCoordinate(latitude: 10.0, longitude: -85.5),
                GeoCoordinate(latitude: 8.5, longitude: -80.0),
                // Central America East Coast & Yucatan
                GeoCoordinate(latitude: 9.5, longitude: -82.5),
                GeoCoordinate(latitude: 13.5, longitude: -83.5),
                GeoCoordinate(latitude: 16.0, longitude: -88.5),
                GeoCoordinate(latitude: 18.5, longitude: -88.0),
                GeoCoordinate(latitude: 21.5, longitude: -87.0),
                GeoCoordinate(latitude: 21.0, longitude: -90.5),
                GeoCoordinate(latitude: 19.0, longitude: -91.5),
                // Mexico Gulf Coast & Texas
                GeoCoordinate(latitude: 22.0, longitude: -97.8),
                GeoCoordinate(latitude: 26.0, longitude: -97.2),
                GeoCoordinate(latitude: 29.0, longitude: -95.0),
                GeoCoordinate(latitude: 29.8, longitude: -90.0),
                // Florida Peninsula
                GeoCoordinate(latitude: 30.5, longitude: -86.5),
                GeoCoordinate(latitude: 28.0, longitude: -82.8),
                GeoCoordinate(latitude: 25.0, longitude: -81.0),
                GeoCoordinate(latitude: 25.5, longitude: -80.2),
                GeoCoordinate(latitude: 28.5, longitude: -80.5),
                GeoCoordinate(latitude: 31.0, longitude: -81.5),
                // US East Coast
                GeoCoordinate(latitude: 34.0, longitude: -77.8),
                GeoCoordinate(latitude: 37.0, longitude: -76.0),
                GeoCoordinate(latitude: 39.0, longitude: -74.5),
                GeoCoordinate(latitude: 41.5, longitude: -71.0),
                GeoCoordinate(latitude: 44.5, longitude: -67.0),
                // Canada East Coast & Nova Scotia
                GeoCoordinate(latitude: 45.0, longitude: -63.5),
                GeoCoordinate(latitude: 47.0, longitude: -60.5),
                GeoCoordinate(latitude: 50.0, longitude: -60.0),
                GeoCoordinate(latitude: 55.0, longitude: -59.0),
                GeoCoordinate(latitude: 60.5, longitude: -64.5),
                // Hudson Bay & Arctic Canada
                GeoCoordinate(latitude: 62.5, longitude: -78.0),
                GeoCoordinate(latitude: 55.0, longitude: -80.0),
                GeoCoordinate(latitude: 53.0, longitude: -82.0),
                GeoCoordinate(latitude: 58.0, longitude: -94.0),
                GeoCoordinate(latitude: 64.0, longitude: -90.0),
                GeoCoordinate(latitude: 69.0, longitude: -90.0),
                GeoCoordinate(latitude: 70.0, longitude: -120.0),
                GeoCoordinate(latitude: 71.0, longitude: -140.0)
            ]
        ),

        // 2. Greenland
        VectorCountryPolygon(
            countryId: "GL",
            countryName: "Greenland",
            primaryPrefix: "OX",
            coordinates: [
                GeoCoordinate(latitude: 83.5, longitude: -35.0),
                GeoCoordinate(latitude: 81.0, longitude: -18.0),
                GeoCoordinate(latitude: 76.0, longitude: -20.0),
                GeoCoordinate(latitude: 70.0, longitude: -22.0),
                GeoCoordinate(latitude: 65.0, longitude: -38.0),
                GeoCoordinate(latitude: 60.0, longitude: -44.0),
                GeoCoordinate(latitude: 64.0, longitude: -52.0),
                GeoCoordinate(latitude: 70.0, longitude: -54.0),
                GeoCoordinate(latitude: 76.0, longitude: -68.0),
                GeoCoordinate(latitude: 81.5, longitude: -60.0)
            ]
        ),

        // 3. South America
        VectorCountryPolygon(
            countryId: "SA",
            countryName: "South America",
            primaryPrefix: "PY/LU/CE",
            coordinates: [
                GeoCoordinate(latitude: 12.5, longitude: -71.5),
                GeoCoordinate(latitude: 10.5, longitude: -62.0),
                GeoCoordinate(latitude: 7.0, longitude: -58.0),
                GeoCoordinate(latitude: 4.5, longitude: -51.5),
                GeoCoordinate(latitude: 0.0, longitude: -48.0),
                GeoCoordinate(latitude: -2.5, longitude: -44.0),
                GeoCoordinate(latitude: -5.5, longitude: -35.2), // Eastern Tip (Recife)
                GeoCoordinate(latitude: -13.0, longitude: -38.5),
                GeoCoordinate(latitude: -23.0, longitude: -44.0),
                GeoCoordinate(latitude: -30.0, longitude: -50.0),
                GeoCoordinate(latitude: -35.0, longitude: -55.0),
                GeoCoordinate(latitude: -38.5, longitude: -58.0),
                GeoCoordinate(latitude: -45.0, longitude: -66.0),
                GeoCoordinate(latitude: -52.0, longitude: -68.0),
                GeoCoordinate(latitude: -55.0, longitude: -67.0), // Cape Horn
                GeoCoordinate(latitude: -52.5, longitude: -74.0),
                GeoCoordinate(latitude: -45.0, longitude: -75.0),
                GeoCoordinate(latitude: -37.0, longitude: -73.5),
                GeoCoordinate(latitude: -25.0, longitude: -70.5),
                GeoCoordinate(latitude: -15.0, longitude: -75.5),
                GeoCoordinate(latitude: -5.0, longitude: -81.2),  // Western Tip (Peru)
                GeoCoordinate(latitude: 1.0, longitude: -79.5),
                GeoCoordinate(latitude: 8.0, longitude: -77.5),
                GeoCoordinate(latitude: 11.0, longitude: -74.5)
            ]
        ),

        // 4. Europe & Scandinavia
        VectorCountryPolygon(
            countryId: "EU",
            countryName: "Europe",
            primaryPrefix: "DL/F/EA/I",
            coordinates: [
                // Iberian Peninsula
                GeoCoordinate(latitude: 36.0, longitude: -5.5),
                GeoCoordinate(latitude: 37.0, longitude: -9.0),
                GeoCoordinate(latitude: 43.5, longitude: -9.2),
                GeoCoordinate(latitude: 43.5, longitude: -1.8),
                // France & Benelux
                GeoCoordinate(latitude: 47.0, longitude: -3.0),
                GeoCoordinate(latitude: 49.5, longitude: -1.5),
                GeoCoordinate(latitude: 51.0, longitude: 2.0),
                GeoCoordinate(latitude: 53.5, longitude: 7.0),
                GeoCoordinate(latitude: 55.5, longitude: 8.5),
                // Scandinavia (Norway / Sweden / Finland)
                GeoCoordinate(latitude: 58.0, longitude: 7.0),
                GeoCoordinate(latitude: 62.0, longitude: 5.0),
                GeoCoordinate(latitude: 68.0, longitude: 14.0),
                GeoCoordinate(latitude: 71.0, longitude: 26.0), // North Cape
                GeoCoordinate(latitude: 70.0, longitude: 31.0),
                GeoCoordinate(latitude: 66.0, longitude: 40.0), // White Sea
                GeoCoordinate(latitude: 60.0, longitude: 30.0), // St Petersburg
                GeoCoordinate(latitude: 59.0, longitude: 24.0),
                GeoCoordinate(latitude: 55.0, longitude: 21.0),
                GeoCoordinate(latitude: 54.0, longitude: 14.0),
                // Southern Europe & Mediterranean
                GeoCoordinate(latitude: 45.5, longitude: 13.5),
                GeoCoordinate(latitude: 41.0, longitude: 16.5),
                GeoCoordinate(latitude: 38.0, longitude: 15.5), // Italy
                GeoCoordinate(latitude: 40.5, longitude: 18.5),
                GeoCoordinate(latitude: 39.0, longitude: 20.5), // Greece
                GeoCoordinate(latitude: 36.5, longitude: 23.0),
                GeoCoordinate(latitude: 38.5, longitude: 24.0),
                GeoCoordinate(latitude: 41.0, longitude: 29.0), // Bosphorus
                // Black Sea & Eastern Europe
                GeoCoordinate(latitude: 44.5, longitude: 34.0), // Crimea
                GeoCoordinate(latitude: 46.5, longitude: 38.0),
                GeoCoordinate(latitude: 43.5, longitude: 40.0),
                GeoCoordinate(latitude: 42.0, longitude: 42.0),
                // Central European Tie
                GeoCoordinate(latitude: 48.0, longitude: 18.0),
                GeoCoordinate(latitude: 45.0, longitude: 7.0),
                GeoCoordinate(latitude: 43.5, longitude: 4.5),
                GeoCoordinate(latitude: 41.5, longitude: 2.5),
                GeoCoordinate(latitude: 36.8, longitude: -2.2)
            ]
        ),

        // 5. British Isles & Ireland
        VectorCountryPolygon(
            countryId: "GB",
            countryName: "United Kingdom & Ireland",
            primaryPrefix: "G/EI",
            coordinates: [
                GeoCoordinate(latitude: 50.0, longitude: -5.5),
                GeoCoordinate(latitude: 51.5, longitude: 1.4),
                GeoCoordinate(latitude: 53.0, longitude: 0.3),
                GeoCoordinate(latitude: 56.0, longitude: -2.5),
                GeoCoordinate(latitude: 58.5, longitude: -3.0),
                GeoCoordinate(latitude: 58.5, longitude: -5.0),
                GeoCoordinate(latitude: 55.5, longitude: -5.5),
                GeoCoordinate(latitude: 54.0, longitude: -3.0),
                GeoCoordinate(latitude: 51.5, longitude: -4.5),
                GeoCoordinate(latitude: 50.0, longitude: -5.5)
            ]
        ),

        // 6. Africa & Madagascar
        VectorCountryPolygon(
            countryId: "AF",
            countryName: "Africa",
            primaryPrefix: "ZS/EA8/5Z",
            coordinates: [
                GeoCoordinate(latitude: 35.8, longitude: -5.5), // Strait of Gibraltar
                GeoCoordinate(latitude: 37.0, longitude: 10.0), // Cape Bon
                GeoCoordinate(latitude: 33.0, longitude: 11.5),
                GeoCoordinate(latitude: 31.0, longitude: 28.0),
                GeoCoordinate(latitude: 31.5, longitude: 32.5), // Suez
                GeoCoordinate(latitude: 27.5, longitude: 34.0),
                GeoCoordinate(latitude: 22.0, longitude: 37.0),
                GeoCoordinate(latitude: 12.0, longitude: 43.5), // Bab-el-Mandeb
                GeoCoordinate(latitude: 11.8, longitude: 51.2), // Horn of Africa (Somalia)
                GeoCoordinate(latitude: 2.0, longitude: 45.5),
                GeoCoordinate(latitude: -5.0, longitude: 39.0),
                GeoCoordinate(latitude: -15.0, longitude: 40.5),
                GeoCoordinate(latitude: -25.0, longitude: 33.0),
                GeoCoordinate(latitude: -34.0, longitude: 26.0),
                GeoCoordinate(latitude: -34.8, longitude: 20.0), // Cape of Good Hope
                GeoCoordinate(latitude: -30.0, longitude: 17.5),
                GeoCoordinate(latitude: -22.0, longitude: 14.5),
                GeoCoordinate(latitude: -12.0, longitude: 13.5),
                GeoCoordinate(latitude: -5.0, longitude: 12.0),
                GeoCoordinate(latitude: 4.5, longitude: 9.0),   // Gulf of Guinea
                GeoCoordinate(latitude: 5.5, longitude: 0.0),
                GeoCoordinate(latitude: 4.5, longitude: -7.5),
                GeoCoordinate(latitude: 12.0, longitude: -16.5),
                GeoCoordinate(latitude: 15.0, longitude: -17.5), // Dakar (Western Tip)
                GeoCoordinate(latitude: 21.0, longitude: -17.0),
                GeoCoordinate(latitude: 28.0, longitude: -12.5),
                GeoCoordinate(latitude: 33.0, longitude: -9.0)
            ]
        ),

        // 7. Middle East, Arabian Peninsula & Iran
        VectorCountryPolygon(
            countryId: "ME",
            countryName: "Middle East & Iran",
            primaryPrefix: "EP/HZ/A6/4X",
            coordinates: [
                GeoCoordinate(latitude: 31.0, longitude: 34.5),
                GeoCoordinate(latitude: 28.0, longitude: 34.5),
                GeoCoordinate(latitude: 22.0, longitude: 39.0),
                GeoCoordinate(latitude: 13.0, longitude: 44.5),
                GeoCoordinate(latitude: 12.5, longitude: 53.5),
                GeoCoordinate(latitude: 17.0, longitude: 55.0),
                GeoCoordinate(latitude: 22.5, longitude: 59.5), // Oman
                GeoCoordinate(latitude: 26.0, longitude: 56.5), // Strait of Hormuz
                GeoCoordinate(latitude: 25.0, longitude: 55.0), // UAE
                GeoCoordinate(latitude: 25.5, longitude: 51.0), // Qatar
                GeoCoordinate(latitude: 29.5, longitude: 48.5), // Kuwait
                GeoCoordinate(latitude: 30.0, longitude: 50.0), // Persian Gulf Iran Coast
                GeoCoordinate(latitude: 27.0, longitude: 56.0),
                GeoCoordinate(latitude: 25.3, longitude: 60.5), // Chabahar
                GeoCoordinate(latitude: 31.5, longitude: 61.5), // East Iran Border
                GeoCoordinate(latitude: 37.5, longitude: 59.0),
                GeoCoordinate(latitude: 37.0, longitude: 54.0), // Caspian Sea (Gorgan)
                GeoCoordinate(latitude: 37.5, longitude: 49.5), // Rasht/Anzali
                GeoCoordinate(latitude: 39.0, longitude: 48.5), // Azerbaijan Border
                GeoCoordinate(latitude: 39.5, longitude: 44.5), // Mount Ararat
                GeoCoordinate(latitude: 37.0, longitude: 43.0),
                GeoCoordinate(latitude: 36.5, longitude: 36.0), // Mediterranean Turkey
                GeoCoordinate(latitude: 33.0, longitude: 35.0)
            ]
        ),

        // 8. Asia, Russia & Siberia
        VectorCountryPolygon(
            countryId: "AS",
            countryName: "Asia & Russia",
            primaryPrefix: "UA/BY/VU/JA",
            coordinates: [
                // Ural / Arctic Russia
                GeoCoordinate(latitude: 69.0, longitude: 60.0),
                GeoCoordinate(latitude: 73.0, longitude: 70.0), // Yamal
                GeoCoordinate(latitude: 76.0, longitude: 100.0), // Taymyr
                GeoCoordinate(latitude: 74.0, longitude: 135.0),
                GeoCoordinate(latitude: 70.0, longitude: 170.0),
                GeoCoordinate(latitude: 66.0, longitude: 190.0), // Bering Strait (170W)
                GeoCoordinate(latitude: 60.0, longitude: 175.0),
                // Kamchatka & Sea of Okhotsk
                GeoCoordinate(latitude: 52.0, longitude: 158.0),
                GeoCoordinate(latitude: 59.0, longitude: 150.0),
                GeoCoordinate(latitude: 54.0, longitude: 140.0),
                GeoCoordinate(latitude: 45.0, longitude: 136.0), // Vladivostok
                // Korean Peninsula
                GeoCoordinate(latitude: 38.5, longitude: 128.5),
                GeoCoordinate(latitude: 35.0, longitude: 129.0),
                GeoCoordinate(latitude: 37.5, longitude: 126.0),
                // China Coast
                GeoCoordinate(latitude: 40.0, longitude: 122.0),
                GeoCoordinate(latitude: 37.0, longitude: 122.5), // Shandong
                GeoCoordinate(latitude: 32.0, longitude: 121.5), // Shanghai
                GeoCoordinate(latitude: 25.0, longitude: 119.0),
                GeoCoordinate(latitude: 22.5, longitude: 114.0), // Hong Kong
                GeoCoordinate(latitude: 21.0, longitude: 110.0),
                // Southeast Asia (Vietnam / Thailand / Malaysia)
                GeoCoordinate(latitude: 16.0, longitude: 108.5),
                GeoCoordinate(latitude: 10.5, longitude: 107.0),
                GeoCoordinate(latitude: 8.5, longitude: 100.5),
                GeoCoordinate(latitude: 1.5, longitude: 103.8), // Singapore
                GeoCoordinate(latitude: 5.5, longitude: 100.0),
                GeoCoordinate(latitude: 15.0, longitude: 98.0),
                // Bay of Bengal & India
                GeoCoordinate(latitude: 21.5, longitude: 89.0), // Bangladesh
                GeoCoordinate(latitude: 17.5, longitude: 83.0),
                GeoCoordinate(latitude: 13.0, longitude: 80.2), // Chennai
                GeoCoordinate(latitude: 8.2, longitude: 77.5),  // Cape Comorin
                GeoCoordinate(latitude: 15.0, longitude: 74.0), // Goa
                GeoCoordinate(latitude: 19.0, longitude: 72.8), // Mumbai
                GeoCoordinate(latitude: 23.0, longitude: 69.0), // Gujarat
                GeoCoordinate(latitude: 25.0, longitude: 62.0), // Pakistan (Gwadar)
                // Inland Western Border Tie
                GeoCoordinate(latitude: 37.0, longitude: 59.0),
                GeoCoordinate(latitude: 50.0, longitude: 55.0),
                GeoCoordinate(latitude: 60.0, longitude: 60.0)
            ]
        ),

        // 9. Japan Archipelago
        VectorCountryPolygon(
            countryId: "JP",
            countryName: "Japan",
            primaryPrefix: "JA",
            coordinates: [
                GeoCoordinate(latitude: 45.5, longitude: 142.0), // Hokkaido
                GeoCoordinate(latitude: 43.5, longitude: 145.5),
                GeoCoordinate(latitude: 41.5, longitude: 141.0),
                GeoCoordinate(latitude: 38.0, longitude: 141.0), // Honshu
                GeoCoordinate(latitude: 35.0, longitude: 140.0), // Tokyo
                GeoCoordinate(latitude: 33.5, longitude: 135.5),
                GeoCoordinate(latitude: 31.0, longitude: 130.5), // Kyushu
                GeoCoordinate(latitude: 34.0, longitude: 131.0),
                GeoCoordinate(latitude: 37.5, longitude: 137.0),
                GeoCoordinate(latitude: 40.5, longitude: 140.0)
            ]
        ),

        // 10. Australia & Tasmania
        VectorCountryPolygon(
            countryId: "AU",
            countryName: "Australia",
            primaryPrefix: "VK",
            coordinates: [
                GeoCoordinate(latitude: -11.0, longitude: 142.5), // Cape York
                GeoCoordinate(latitude: -18.0, longitude: 146.0),
                GeoCoordinate(latitude: -25.0, longitude: 153.0),
                GeoCoordinate(latitude: -34.0, longitude: 151.2), // Sydney
                GeoCoordinate(latitude: -38.0, longitude: 147.0),
                GeoCoordinate(latitude: -38.5, longitude: 144.0), // Melbourne
                GeoCoordinate(latitude: -35.0, longitude: 136.0), // Adelaide
                GeoCoordinate(latitude: -32.0, longitude: 128.0), // Great Australian Bight
                GeoCoordinate(latitude: -34.0, longitude: 119.0),
                GeoCoordinate(latitude: -32.0, longitude: 115.5), // Perth
                GeoCoordinate(latitude: -22.0, longitude: 114.0), // Northwest Cape
                GeoCoordinate(latitude: -17.5, longitude: 122.0),
                GeoCoordinate(latitude: -14.0, longitude: 126.0),
                GeoCoordinate(latitude: -12.5, longitude: 131.0), // Darwin
                GeoCoordinate(latitude: -15.0, longitude: 136.0),
                GeoCoordinate(latitude: -14.0, longitude: 141.0)
            ]
        ),

        // 11. New Zealand
        VectorCountryPolygon(
            countryId: "NZ",
            countryName: "New Zealand",
            primaryPrefix: "ZL",
            coordinates: [
                GeoCoordinate(latitude: -34.5, longitude: 172.8), // North Island
                GeoCoordinate(latitude: -37.5, longitude: 178.5),
                GeoCoordinate(latitude: -41.3, longitude: 174.8), // Wellington
                GeoCoordinate(latitude: -43.5, longitude: 172.7), // Christchurch
                GeoCoordinate(latitude: -46.5, longitude: 168.5), // South Island
                GeoCoordinate(latitude: -45.0, longitude: 166.5),
                GeoCoordinate(latitude: -41.0, longitude: 172.0),
                GeoCoordinate(latitude: -38.0, longitude: 174.8)
            ]
        ),

        // 12. Antarctica
        VectorCountryPolygon(
            countryId: "AQ",
            countryName: "Antarctica",
            primaryPrefix: "CE9",
            coordinates: [
                GeoCoordinate(latitude: -63.5, longitude: -57.0), // Antarctic Peninsula
                GeoCoordinate(latitude: -68.0, longitude: -65.0),
                GeoCoordinate(latitude: -73.0, longitude: -80.0),
                GeoCoordinate(latitude: -75.0, longitude: -120.0),
                GeoCoordinate(latitude: -78.0, longitude: -165.0), // Ross Ice Shelf
                GeoCoordinate(latitude: -72.0, longitude: 170.0),
                GeoCoordinate(latitude: -66.0, longitude: 140.0),
                GeoCoordinate(latitude: -66.0, longitude: 90.0),
                GeoCoordinate(latitude: -69.0, longitude: 40.0),
                GeoCoordinate(latitude: -70.0, longitude: 0.0),
                GeoCoordinate(latitude: -75.0, longitude: -30.0)
            ]
        )
    ]

    // MARK: - Country Internal Division Borders

    public static let countryBorders: [VectorLineString] = [
        // US - Canada Border (49th Parallel & Great Lakes)
        VectorLineString(coordinates: [
            GeoCoordinate(latitude: 49.0, longitude: -123.0),
            GeoCoordinate(latitude: 49.0, longitude: -95.0),
            GeoCoordinate(latitude: 48.0, longitude: -89.5),
            GeoCoordinate(latitude: 45.0, longitude: -82.0),
            GeoCoordinate(latitude: 42.0, longitude: -82.5),
            GeoCoordinate(latitude: 43.5, longitude: -79.0),
            GeoCoordinate(latitude: 45.0, longitude: -74.5),
            GeoCoordinate(latitude: 47.0, longitude: -68.0)
        ]),

        // US - Mexico Border
        VectorLineString(coordinates: [
            GeoCoordinate(latitude: 32.5, longitude: -117.1),
            GeoCoordinate(latitude: 31.3, longitude: -111.0),
            GeoCoordinate(latitude: 31.8, longitude: -106.5),
            GeoCoordinate(latitude: 29.5, longitude: -104.0),
            GeoCoordinate(latitude: 26.0, longitude: -97.2)
        ]),

        // Europe - France/Spain Border (Pyrenees)
        VectorLineString(coordinates: [
            GeoCoordinate(latitude: 43.4, longitude: -1.8),
            GeoCoordinate(latitude: 42.5, longitude: 1.5),
            GeoCoordinate(latitude: 42.4, longitude: 3.2)
        ]),

        // Germany - Poland Border (Oder-Neisse)
        VectorLineString(coordinates: [
            GeoCoordinate(latitude: 53.9, longitude: 14.2),
            GeoCoordinate(latitude: 52.0, longitude: 14.8),
            GeoCoordinate(latitude: 50.8, longitude: 15.0)
        ]),

        // Russia - China Border (Amur River)
        VectorLineString(coordinates: [
            GeoCoordinate(latitude: 53.5, longitude: 124.0),
            GeoCoordinate(latitude: 48.5, longitude: 135.0),
            GeoCoordinate(latitude: 45.0, longitude: 131.0)
        ]),

        // India - Pakistan Border
        VectorLineString(coordinates: [
            GeoCoordinate(latitude: 24.0, longitude: 69.0),
            GeoCoordinate(latitude: 27.5, longitude: 71.0),
            GeoCoordinate(latitude: 32.0, longitude: 74.5),
            GeoCoordinate(latitude: 35.5, longitude: 76.5)
        ])
    ]
}
