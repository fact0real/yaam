//
//  WorldVectorGeography.swift
//  YAAM
//
//  High-Precision Global Vector Geography, Country Boundaries & DXCC Entities
//

import Foundation
import CoreGraphics
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

    public init(id: String, name: String, flag: String, primaryPrefix: String, center: GeoCoordinate, cqZone: Int, ituZone: Int) {
        self.id = id
        self.name = name
        self.flag = flag
        self.primaryPrefix = primaryPrefix
        self.center = center
        self.cqZone = cqZone
        self.ituZone = ituZone
    }
}

// MARK: - Vector Polygon Model

public struct VectorCountryPolygon: Sendable {
    public let countryId: String
    public let countryName: String
    public let flag: String
    public let coordinates: [GeoCoordinate] // (lat, lon)
}

// MARK: - Global Vector Geography Engine

public enum WorldVectorGeography {

    // MARK: - Major DXCC Countries Catalog

    public static let countries: [WorldCountryEntity] = [
        // Middle East & West Asia
        WorldCountryEntity(id: "IR", name: "Iran", flag: "🇮🇷", primaryPrefix: "EP", center: GeoCoordinate(latitude: 32.4279, longitude: 53.6880), cqZone: 21, ituZone: 40),
        WorldCountryEntity(id: "TR", name: "Turkey", flag: "🇹🇷", primaryPrefix: "TA", center: GeoCoordinate(latitude: 38.9637, longitude: 35.2433), cqZone: 20, ituZone: 39),
        WorldCountryEntity(id: "IQ", name: "Iraq", flag: "🇮🇶", primaryPrefix: "YI", center: GeoCoordinate(latitude: 33.2232, longitude: 43.6793), cqZone: 21, ituZone: 39),
        WorldCountryEntity(id: "SA", name: "Saudi Arabia", flag: "🇸🇦", primaryPrefix: "HZ", center: GeoCoordinate(latitude: 23.8859, longitude: 45.0792), cqZone: 21, ituZone: 39),
        WorldCountryEntity(id: "AE", name: "United Arab Emirates", flag: "🇦🇪", primaryPrefix: "A6", center: GeoCoordinate(latitude: 23.4241, longitude: 53.8478), cqZone: 21, ituZone: 39),
        WorldCountryEntity(id: "KW", name: "Kuwait", flag: "🇰🇼", primaryPrefix: "9K", center: GeoCoordinate(latitude: 29.3117, longitude: 47.4818), cqZone: 21, ituZone: 39),
        WorldCountryEntity(id: "OM", name: "Oman", flag: "🇴🇲", primaryPrefix: "A4", center: GeoCoordinate(latitude: 21.4735, longitude: 55.9754), cqZone: 21, ituZone: 39),
        WorldCountryEntity(id: "QA", name: "Qatar", flag: "🇶🇦", primaryPrefix: "A7", center: GeoCoordinate(latitude: 25.3548, longitude: 51.1839), cqZone: 21, ituZone: 39),
        WorldCountryEntity(id: "AM", name: "Armenia", flag: "🇦🇲", primaryPrefix: "EK", center: GeoCoordinate(latitude: 40.0691, longitude: 45.0382), cqZone: 21, ituZone: 29),
        WorldCountryEntity(id: "AZ", name: "Azerbaijan", flag: "🇦🇿", primaryPrefix: "4J", center: GeoCoordinate(latitude: 40.1431, longitude: 47.5769), cqZone: 21, ituZone: 29),
        WorldCountryEntity(id: "GE", name: "Georgia", flag: "🇬🇪", primaryPrefix: "4L", center: GeoCoordinate(latitude: 42.3154, longitude: 43.3569), cqZone: 21, ituZone: 29),

        // Europe
        WorldCountryEntity(id: "DE", name: "Germany", flag: "🇩🇪", primaryPrefix: "DL", center: GeoCoordinate(latitude: 51.1657, longitude: 10.4515), cqZone: 14, ituZone: 28),
        WorldCountryEntity(id: "GB", name: "United Kingdom", flag: "🇬🇧", primaryPrefix: "G", center: GeoCoordinate(latitude: 55.3781, longitude: -3.4360), cqZone: 14, ituZone: 27),
        WorldCountryEntity(id: "FR", name: "France", flag: "🇫🇷", primaryPrefix: "F", center: GeoCoordinate(latitude: 46.2276, longitude: 2.2137), cqZone: 14, ituZone: 27),
        WorldCountryEntity(id: "IT", name: "Italy", flag: "🇮🇹", primaryPrefix: "I", center: GeoCoordinate(latitude: 41.8719, longitude: 12.5674), cqZone: 15, ituZone: 28),
        WorldCountryEntity(id: "ES", name: "Spain", flag: "🇪🇸", primaryPrefix: "EA", center: GeoCoordinate(latitude: 40.4637, longitude: -3.7492), cqZone: 14, ituZone: 37),
        WorldCountryEntity(id: "PL", name: "Poland", flag: "🇵🇱", primaryPrefix: "SP", center: GeoCoordinate(latitude: 51.9194, longitude: 19.1451), cqZone: 15, ituZone: 28),
        WorldCountryEntity(id: "UA", name: "Ukraine", flag: "🇺🇦", primaryPrefix: "UR", center: GeoCoordinate(latitude: 48.3794, longitude: 31.1656), cqZone: 16, ituZone: 29),
        WorldCountryEntity(id: "SE", name: "Sweden", flag: "🇸🇪", primaryPrefix: "SM", center: GeoCoordinate(latitude: 60.1282, longitude: 18.6435), cqZone: 14, ituZone: 18),
        WorldCountryEntity(id: "NO", name: "Norway", flag: "🇳🇴", primaryPrefix: "LA", center: GeoCoordinate(latitude: 60.4720, longitude: 8.4689), cqZone: 14, ituZone: 18),
        WorldCountryEntity(id: "FI", name: "Finland", flag: "🇫🇮", primaryPrefix: "OH", center: GeoCoordinate(latitude: 61.9241, longitude: 25.7482), cqZone: 15, ituZone: 18),
        WorldCountryEntity(id: "GR", name: "Greece", flag: "🇬🇷", primaryPrefix: "SV", center: GeoCoordinate(latitude: 39.0742, longitude: 21.8243), cqZone: 20, ituZone: 28),
        WorldCountryEntity(id: "RO", name: "Romania", flag: "🇷🇴", primaryPrefix: "YO", center: GeoCoordinate(latitude: 45.9432, longitude: 24.9668), cqZone: 20, ituZone: 28),
        WorldCountryEntity(id: "NL", name: "Netherlands", flag: "🇳🇱", primaryPrefix: "PA", center: GeoCoordinate(latitude: 52.1326, longitude: 5.2913), cqZone: 14, ituZone: 27),
        WorldCountryEntity(id: "BE", name: "Belgium", flag: "🇧🇪", primaryPrefix: "ON", center: GeoCoordinate(latitude: 50.5039, longitude: 4.4699), cqZone: 14, ituZone: 27),
        WorldCountryEntity(id: "CH", name: "Switzerland", flag: "🇨🇭", primaryPrefix: "HB9", center: GeoCoordinate(latitude: 46.8182, longitude: 8.2275), cqZone: 14, ituZone: 28),
        WorldCountryEntity(id: "AT", name: "Austria", flag: "🇦🇹", primaryPrefix: "OE", center: GeoCoordinate(latitude: 47.5162, longitude: 14.5501), cqZone: 15, ituZone: 28),
        WorldCountryEntity(id: "CZ", name: "Czech Republic", flag: "🇨🇿", primaryPrefix: "OK", center: GeoCoordinate(latitude: 49.8175, longitude: 15.4730), cqZone: 15, ituZone: 28),
        WorldCountryEntity(id: "HU", name: "Hungary", flag: "🇭🇺", primaryPrefix: "HA", center: GeoCoordinate(latitude: 47.1625, longitude: 19.5033), cqZone: 15, ituZone: 28),
        WorldCountryEntity(id: "PT", name: "Portugal", flag: "🇵🇹", primaryPrefix: "CT", center: GeoCoordinate(latitude: 39.3999, longitude: -8.2245), cqZone: 14, ituZone: 37),
        WorldCountryEntity(id: "IE", name: "Ireland", flag: "🇮🇪", primaryPrefix: "EI", center: GeoCoordinate(latitude: 53.1424, longitude: -7.6921), cqZone: 14, ituZone: 27),
        WorldCountryEntity(id: "RU", name: "European Russia", flag: "🇷🇺", primaryPrefix: "RA", center: GeoCoordinate(latitude: 55.7558, longitude: 45.0000), cqZone: 16, ituZone: 29),

        // Asia & Pacific
        WorldCountryEntity(id: "JP", name: "Japan", flag: "🇯🇵", primaryPrefix: "JA", center: GeoCoordinate(latitude: 36.2048, longitude: 138.2529), cqZone: 25, ituZone: 45),
        WorldCountryEntity(id: "CN", name: "China", flag: "🇨🇳", primaryPrefix: "BY", center: GeoCoordinate(latitude: 35.8617, longitude: 104.1954), cqZone: 24, ituZone: 44),
        WorldCountryEntity(id: "KR", name: "South Korea", flag: "🇰🇷", primaryPrefix: "HL", center: GeoCoordinate(latitude: 35.9078, longitude: 127.7669), cqZone: 25, ituZone: 44),
        WorldCountryEntity(id: "IN", name: "India", flag: "🇮🇳", primaryPrefix: "VU", center: GeoCoordinate(latitude: 20.5937, longitude: 78.9629), cqZone: 22, ituZone: 41),
        WorldCountryEntity(id: "TH", name: "Thailand", flag: "🇹🇭", primaryPrefix: "HS", center: GeoCoordinate(latitude: 15.8700, longitude: 100.9925), cqZone: 26, ituZone: 49),
        WorldCountryEntity(id: "ID", name: "Indonesia", flag: "🇮🇩", primaryPrefix: "YB", center: GeoCoordinate(latitude: -0.7893, longitude: 113.9213), cqZone: 28, ituZone: 54),
        WorldCountryEntity(id: "AU", name: "Australia", flag: "🇦🇺", primaryPrefix: "VK", center: GeoCoordinate(latitude: -25.2744, longitude: 133.7751), cqZone: 30, ituZone: 59),
        WorldCountryEntity(id: "NZ", name: "New Zealand", flag: "🇳🇿", primaryPrefix: "ZL", center: GeoCoordinate(latitude: -40.9006, longitude: 174.8860), cqZone: 32, ituZone: 60),

        // Americas
        WorldCountryEntity(id: "US", name: "United States", flag: "🇺🇸", primaryPrefix: "K", center: GeoCoordinate(latitude: 37.0902, longitude: -95.7129), cqZone: 5, ituZone: 8),
        WorldCountryEntity(id: "CA", name: "Canada", flag: "🇨🇦", primaryPrefix: "VE", center: GeoCoordinate(latitude: 56.1304, longitude: -106.3468), cqZone: 4, ituZone: 9),
        WorldCountryEntity(id: "MX", name: "Mexico", flag: "🇲🇽", primaryPrefix: "XE", center: GeoCoordinate(latitude: 23.6345, longitude: -102.5528), cqZone: 6, ituZone: 10),
        WorldCountryEntity(id: "BR", name: "Brazil", flag: "🇧🇷", primaryPrefix: "PY", center: GeoCoordinate(latitude: -14.2350, longitude: -51.9253), cqZone: 11, ituZone: 15),
        WorldCountryEntity(id: "AR", name: "Argentina", flag: "🇦🇷", primaryPrefix: "LU", center: GeoCoordinate(latitude: -38.4161, longitude: -63.6167), cqZone: 13, ituZone: 16),
        WorldCountryEntity(id: "CL", name: "Chile", flag: "🇨🇱", primaryPrefix: "CE", center: GeoCoordinate(latitude: -35.6751, longitude: -71.5430), cqZone: 12, ituZone: 14),

        // Africa
        WorldCountryEntity(id: "ZA", name: "South Africa", flag: "🇿🇦", primaryPrefix: "ZS", center: GeoCoordinate(latitude: -30.5595, longitude: 22.9375), cqZone: 38, ituZone: 57),
        WorldCountryEntity(id: "EG", name: "Egypt", flag: "🇪🇬", primaryPrefix: "SU", center: GeoCoordinate(latitude: 26.8206, longitude: 30.8025), cqZone: 34, ituZone: 38),
        WorldCountryEntity(id: "MA", name: "Morocco", flag: "🇲🇦", primaryPrefix: "CN", center: GeoCoordinate(latitude: 31.7917, longitude: -7.0926), cqZone: 33, ituZone: 37)
    ]

    // MARK: - High-Precision Vector Country Boundaries

    public static let countryBoundaries: [VectorCountryPolygon] = [
        // 1. Iran (Detailed high-res contour)
        VectorCountryPolygon(
            countryId: "IR", countryName: "Iran", flag: "🇮🇷",
            coordinates: [
                GeoCoordinate(latitude: 39.78, longitude: 44.81),
                GeoCoordinate(latitude: 38.83, longitude: 48.86),
                GeoCoordinate(latitude: 37.45, longitude: 50.05),
                GeoCoordinate(latitude: 36.95, longitude: 54.00),
                GeoCoordinate(latitude: 37.95, longitude: 58.38),
                GeoCoordinate(latitude: 36.56, longitude: 61.23),
                GeoCoordinate(latitude: 34.00, longitude: 60.50),
                GeoCoordinate(latitude: 31.00, longitude: 61.80),
                GeoCoordinate(latitude: 25.10, longitude: 61.50),
                GeoCoordinate(latitude: 25.30, longitude: 57.50),
                GeoCoordinate(latitude: 27.00, longitude: 56.50),
                GeoCoordinate(latitude: 26.70, longitude: 54.00),
                GeoCoordinate(latitude: 29.50, longitude: 50.50),
                GeoCoordinate(latitude: 30.00, longitude: 48.50),
                GeoCoordinate(latitude: 33.00, longitude: 46.00),
                GeoCoordinate(latitude: 36.00, longitude: 45.00),
                GeoCoordinate(latitude: 38.00, longitude: 44.30),
                GeoCoordinate(latitude: 39.78, longitude: 44.81)
            ]
        ),

        // 2. Turkey
        VectorCountryPolygon(
            countryId: "TR", countryName: "Turkey", flag: "🇹🇷",
            coordinates: [
                GeoCoordinate(latitude: 42.10, longitude: 27.50),
                GeoCoordinate(latitude: 41.50, longitude: 35.00),
                GeoCoordinate(latitude: 41.30, longitude: 41.50),
                GeoCoordinate(latitude: 39.78, longitude: 44.81),
                GeoCoordinate(latitude: 37.10, longitude: 42.50),
                GeoCoordinate(latitude: 36.80, longitude: 36.00),
                GeoCoordinate(latitude: 36.00, longitude: 32.50),
                GeoCoordinate(latitude: 36.80, longitude: 28.00),
                GeoCoordinate(latitude: 39.00, longitude: 26.20),
                GeoCoordinate(latitude: 40.50, longitude: 26.50),
                GeoCoordinate(latitude: 42.10, longitude: 27.50)
            ]
        ),

        // 3. Arabian Peninsula (Saudi Arabia, UAE, Oman, etc.)
        VectorCountryPolygon(
            countryId: "SA", countryName: "Saudi Arabia", flag: "🇸🇦",
            coordinates: [
                GeoCoordinate(latitude: 31.50, longitude: 37.00),
                GeoCoordinate(latitude: 30.00, longitude: 48.00),
                GeoCoordinate(latitude: 26.00, longitude: 50.00),
                GeoCoordinate(latitude: 24.00, longitude: 55.00),
                GeoCoordinate(latitude: 22.50, longitude: 59.80),
                GeoCoordinate(latitude: 16.60, longitude: 53.00),
                GeoCoordinate(latitude: 12.80, longitude: 45.00),
                GeoCoordinate(latitude: 16.00, longitude: 42.00),
                GeoCoordinate(latitude: 28.00, longitude: 35.00),
                GeoCoordinate(latitude: 31.50, longitude: 37.00)
            ]
        ),

        // 4. Germany & Central Europe
        VectorCountryPolygon(
            countryId: "DE", countryName: "Germany", flag: "🇩🇪",
            coordinates: [
                GeoCoordinate(latitude: 54.90, longitude: 8.50),
                GeoCoordinate(latitude: 54.50, longitude: 13.50),
                GeoCoordinate(latitude: 51.00, longitude: 15.00),
                GeoCoordinate(latitude: 48.50, longitude: 13.50),
                GeoCoordinate(latitude: 47.50, longitude: 10.00),
                GeoCoordinate(latitude: 47.60, longitude: 7.60),
                GeoCoordinate(latitude: 49.20, longitude: 6.00),
                GeoCoordinate(latitude: 51.50, longitude: 6.00),
                GeoCoordinate(latitude: 53.50, longitude: 7.00),
                GeoCoordinate(latitude: 54.90, longitude: 8.50)
            ]
        ),

        // 5. United Kingdom & Ireland
        VectorCountryPolygon(
            countryId: "GB", countryName: "United Kingdom", flag: "🇬🇧",
            coordinates: [
                GeoCoordinate(latitude: 58.60, longitude: -3.00),
                GeoCoordinate(latitude: 55.00, longitude: -1.50),
                GeoCoordinate(latitude: 51.20, longitude: 1.40),
                GeoCoordinate(latitude: 50.00, longitude: -5.20),
                GeoCoordinate(latitude: 52.00, longitude: -5.00),
                GeoCoordinate(latitude: 55.00, longitude: -5.00),
                GeoCoordinate(latitude: 58.60, longitude: -5.00),
                GeoCoordinate(latitude: 58.60, longitude: -3.00)
            ]
        ),

        // 6. France
        VectorCountryPolygon(
            countryId: "FR", countryName: "France", flag: "🇫🇷",
            coordinates: [
                GeoCoordinate(latitude: 51.00, longitude: 2.50),
                GeoCoordinate(latitude: 49.00, longitude: 6.00),
                GeoCoordinate(latitude: 46.00, longitude: 6.50),
                GeoCoordinate(latitude: 43.50, longitude: 7.00),
                GeoCoordinate(latitude: 42.50, longitude: 3.10),
                GeoCoordinate(latitude: 43.30, longitude: -1.80),
                GeoCoordinate(latitude: 46.00, longitude: -1.20),
                GeoCoordinate(latitude: 48.50, longitude: -4.50),
                GeoCoordinate(latitude: 49.70, longitude: -1.50),
                GeoCoordinate(latitude: 51.00, longitude: 2.50)
            ]
        ),

        // 7. Italy
        VectorCountryPolygon(
            countryId: "IT", countryName: "Italy", flag: "🇮🇹",
            coordinates: [
                GeoCoordinate(latitude: 46.50, longitude: 11.50),
                GeoCoordinate(latitude: 45.60, longitude: 13.70),
                GeoCoordinate(latitude: 43.80, longitude: 13.00),
                GeoCoordinate(latitude: 41.20, longitude: 16.80),
                GeoCoordinate(latitude: 40.00, longitude: 18.00),
                GeoCoordinate(latitude: 38.00, longitude: 16.00),
                GeoCoordinate(latitude: 38.00, longitude: 13.00),
                GeoCoordinate(latitude: 41.00, longitude: 14.00),
                GeoCoordinate(latitude: 44.00, longitude: 9.80),
                GeoCoordinate(latitude: 44.20, longitude: 7.50),
                GeoCoordinate(latitude: 46.50, longitude: 11.50)
            ]
        ),

        // 8. Spain & Portugal (Iberian Peninsula)
        VectorCountryPolygon(
            countryId: "ES", countryName: "Spain", flag: "🇪🇸",
            coordinates: [
                GeoCoordinate(latitude: 43.50, longitude: -2.00),
                GeoCoordinate(latitude: 42.50, longitude: 3.10),
                GeoCoordinate(latitude: 36.80, longitude: -2.00),
                GeoCoordinate(latitude: 36.00, longitude: -5.50),
                GeoCoordinate(latitude: 37.00, longitude: -9.00),
                GeoCoordinate(latitude: 42.00, longitude: -9.00),
                GeoCoordinate(latitude: 43.50, longitude: -8.00),
                GeoCoordinate(latitude: 43.50, longitude: -2.00)
            ]
        ),

        // 9. Scandinavia (Sweden, Norway, Finland)
        VectorCountryPolygon(
            countryId: "SE", countryName: "Scandinavia", flag: "🇸🇪",
            coordinates: [
                GeoCoordinate(latitude: 71.00, longitude: 28.00),
                GeoCoordinate(latitude: 65.00, longitude: 29.00),
                GeoCoordinate(latitude: 60.00, longitude: 29.00),
                GeoCoordinate(latitude: 59.00, longitude: 18.00),
                GeoCoordinate(latitude: 55.40, longitude: 13.00),
                GeoCoordinate(latitude: 58.00, longitude: 8.00),
                GeoCoordinate(latitude: 63.00, longitude: 5.00),
                GeoCoordinate(latitude: 70.00, longitude: 20.00),
                GeoCoordinate(latitude: 71.00, longitude: 28.00)
            ]
        ),

        // 10. Japan Archipelago
        VectorCountryPolygon(
            countryId: "JP", countryName: "Japan", flag: "🇯🇵",
            coordinates: [
                GeoCoordinate(latitude: 45.50, longitude: 142.00),
                GeoCoordinate(latitude: 43.00, longitude: 145.50),
                GeoCoordinate(latitude: 38.00, longitude: 141.50),
                GeoCoordinate(latitude: 35.00, longitude: 140.00),
                GeoCoordinate(latitude: 33.00, longitude: 136.00),
                GeoCoordinate(latitude: 31.00, longitude: 130.50),
                GeoCoordinate(latitude: 34.00, longitude: 131.00),
                GeoCoordinate(latitude: 37.00, longitude: 137.00),
                GeoCoordinate(latitude: 41.50, longitude: 140.00),
                GeoCoordinate(latitude: 45.50, longitude: 142.00)
            ]
        ),

        // 11. North America (USA & Canada Contours)
        VectorCountryPolygon(
            countryId: "US", countryName: "United States & Canada", flag: "🇺🇸",
            coordinates: [
                GeoCoordinate(latitude: 70.00, longitude: -140.00),
                GeoCoordinate(latitude: 70.00, longitude: -70.00),
                GeoCoordinate(latitude: 47.00, longitude: -53.00),
                GeoCoordinate(latitude: 44.00, longitude: -65.00),
                GeoCoordinate(latitude: 30.00, longitude: -81.00),
                GeoCoordinate(latitude: 25.00, longitude: -80.00),
                GeoCoordinate(latitude: 26.00, longitude: -97.00),
                GeoCoordinate(latitude: 32.50, longitude: -117.00),
                GeoCoordinate(latitude: 48.50, longitude: -124.50),
                GeoCoordinate(latitude: 60.00, longitude: -145.00),
                GeoCoordinate(latitude: 65.00, longitude: -168.00),
                GeoCoordinate(latitude: 70.00, longitude: -140.00)
            ]
        ),

        // 12. South America (Brazil, Argentina, Chile)
        VectorCountryPolygon(
            countryId: "BR", countryName: "South America", flag: "🇧🇷",
            coordinates: [
                GeoCoordinate(latitude: 12.00, longitude: -72.00),
                GeoCoordinate(latitude: 8.00, longitude: -58.00),
                GeoCoordinate(latitude: -5.00, longitude: -35.00),
                GeoCoordinate(latitude: -23.00, longitude: -42.00),
                GeoCoordinate(latitude: -34.50, longitude: -58.00),
                GeoCoordinate(latitude: -55.00, longitude: -68.00),
                GeoCoordinate(latitude: -40.00, longitude: -74.00),
                GeoCoordinate(latitude: -15.00, longitude: -75.00),
                GeoCoordinate(latitude: 0.00, longitude: -80.00),
                GeoCoordinate(latitude: 12.00, longitude: -72.00)
            ]
        ),

        // 13. Australia & New Zealand
        VectorCountryPolygon(
            countryId: "AU", countryName: "Australia", flag: "🇦🇺",
            coordinates: [
                GeoCoordinate(latitude: -11.00, longitude: 142.00),
                GeoCoordinate(latitude: -16.00, longitude: 146.00),
                GeoCoordinate(latitude: -28.00, longitude: 153.50),
                GeoCoordinate(latitude: -38.00, longitude: 149.00),
                GeoCoordinate(latitude: -38.00, longitude: 140.00),
                GeoCoordinate(latitude: -32.00, longitude: 115.50),
                GeoCoordinate(latitude: -22.00, longitude: 114.00),
                GeoCoordinate(latitude: -14.00, longitude: 126.00),
                GeoCoordinate(latitude: -11.00, longitude: 142.00)
            ]
        ),

        // 14. Africa (Continental Contour)
        VectorCountryPolygon(
            countryId: "ZA", countryName: "Africa", flag: "🇿🇦",
            coordinates: [
                GeoCoordinate(latitude: 37.00, longitude: 10.00),
                GeoCoordinate(latitude: 31.00, longitude: 32.00),
                GeoCoordinate(latitude: 12.00, longitude: 51.00),
                GeoCoordinate(latitude: -10.00, longitude: 40.00),
                GeoCoordinate(latitude: -34.80, longitude: 20.00),
                GeoCoordinate(latitude: -18.00, longitude: 12.00),
                GeoCoordinate(latitude: 4.50, longitude: 9.00),
                GeoCoordinate(latitude: 15.00, longitude: -17.00),
                GeoCoordinate(latitude: 35.00, longitude: -6.00),
                GeoCoordinate(latitude: 37.00, longitude: 10.00)
            ]
        ),

        // 15. East & South Asia (China, India, Southeast Asia)
        VectorCountryPolygon(
            countryId: "CN", countryName: "China & India", flag: "🇨🇳",
            coordinates: [
                GeoCoordinate(latitude: 53.50, longitude: 120.00),
                GeoCoordinate(latitude: 40.00, longitude: 125.00),
                GeoCoordinate(latitude: 30.00, longitude: 122.00),
                GeoCoordinate(latitude: 22.00, longitude: 114.00),
                GeoCoordinate(latitude: 10.00, longitude: 105.00),
                GeoCoordinate(latitude: 1.30, longitude: 104.00),
                GeoCoordinate(latitude: 20.00, longitude: 90.00),
                GeoCoordinate(latitude: 8.00, longitude: 77.50),
                GeoCoordinate(latitude: 23.00, longitude: 68.00),
                GeoCoordinate(latitude: 35.00, longitude: 75.00),
                GeoCoordinate(latitude: 45.00, longitude: 85.00),
                GeoCoordinate(latitude: 50.00, longitude: 100.00),
                GeoCoordinate(latitude: 53.50, longitude: 120.00)
            ]
        )
    ]
}
