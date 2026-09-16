//
//  CountryThemeProfile.swift
//  YAAM
//
//  Created by factoreal on 9/15/26.
//

import SwiftUI
import CoreLocation
import MapKit

// MARK: - Country Theme Profile
public struct CountryThemeProfile: Sendable {
    public let iso: String
    public let name: String
    public let prefix: String
    public let flagEmoji: String
    public let continent: String
    public let continentCode: String
    public let cqZone: String
    public let ituZone: String
    public let centerCoordinate: CLLocationCoordinate2D
    public let coordinateSpan: MKCoordinateSpan
    public let gradientColors: [Color]
    public let accentColor: Color
    public let secondaryColor: Color

    public init(
        iso: String,
        name: String,
        prefix: String,
        flagEmoji: String,
        continent: String,
        continentCode: String,
        cqZone: String,
        ituZone: String,
        centerCoordinate: CLLocationCoordinate2D,
        coordinateSpan: MKCoordinateSpan,
        gradientColors: [Color],
        accentColor: Color,
        secondaryColor: Color
    ) {
        self.iso = iso.lowercased()
        self.name = name
        self.prefix = prefix
        self.flagEmoji = flagEmoji
        self.continent = continent
        self.continentCode = continentCode
        self.cqZone = cqZone
        self.ituZone = ituZone
        self.centerCoordinate = centerCoordinate
        self.coordinateSpan = coordinateSpan
        self.gradientColors = gradientColors
        self.accentColor = accentColor
        self.secondaryColor = secondaryColor
    }
}

// MARK: - Country Theme Registry
public enum CountryThemeRegistry {
    private static let predefinedProfiles: [String: CountryThemeProfile] = [
        "ir": CountryThemeProfile(
            iso: "ir",
            name: "Iran",
            prefix: "EP",
            flagEmoji: "🇮🇷",
            continent: "Asia",
            continentCode: "AS",
            cqZone: "Zone 21",
            ituZone: "Zone 39",
            centerCoordinate: CLLocationCoordinate2D(latitude: 32.4279, longitude: 53.6880),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 13.0, longitudeDelta: 14.0),
            gradientColors: [
                Color(red: 0.0, green: 0.55, blue: 0.32),
                Color(red: 0.95, green: 0.95, blue: 0.96),
                Color(red: 0.85, green: 0.05, blue: 0.08)
            ],
            accentColor: Color(red: 0.0, green: 0.68, blue: 0.42),
            secondaryColor: Color(red: 0.90, green: 0.15, blue: 0.20)
        ),
        "ma": CountryThemeProfile(
            iso: "ma",
            name: "Morocco",
            prefix: "CN",
            flagEmoji: "🇲🇦",
            continent: "Africa",
            continentCode: "AF",
            cqZone: "Zone 33",
            ituZone: "Zone 37",
            centerCoordinate: CLLocationCoordinate2D(latitude: 31.7917, longitude: -7.0926),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 11.0, longitudeDelta: 12.0),
            gradientColors: [
                Color(red: 0.76, green: 0.15, blue: 0.18),
                Color(red: 0.0, green: 0.38, blue: 0.20)
            ],
            accentColor: Color(red: 0.85, green: 0.20, blue: 0.22),
            secondaryColor: Color(red: 0.0, green: 0.50, blue: 0.28)
        ),
        "us": CountryThemeProfile(
            iso: "us",
            name: "United States",
            prefix: "W / K / N / AA-AL",
            flagEmoji: "🇺🇸",
            continent: "North America",
            continentCode: "NA",
            cqZone: "Zones 3, 4, 5",
            ituZone: "Zones 6, 7, 8",
            centerCoordinate: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 25.0, longitudeDelta: 35.0),
            gradientColors: [
                Color(red: 0.04, green: 0.19, blue: 0.38),
                Color(red: 0.95, green: 0.95, blue: 0.98),
                Color(red: 0.70, green: 0.10, blue: 0.26)
            ],
            accentColor: Color(red: 0.20, green: 0.50, blue: 0.95),
            secondaryColor: Color(red: 0.92, green: 0.25, blue: 0.25)
        ),
        "de": CountryThemeProfile(
            iso: "de",
            name: "Germany",
            prefix: "DL / DK / DJ",
            flagEmoji: "🇩🇪",
            continent: "Europe",
            continentCode: "EU",
            cqZone: "Zone 14",
            ituZone: "Zone 28",
            centerCoordinate: CLLocationCoordinate2D(latitude: 51.1657, longitude: 10.4515),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 8.0, longitudeDelta: 8.0),
            gradientColors: [
                Color(red: 0.10, green: 0.10, blue: 0.12),
                Color(red: 0.87, green: 0.0, blue: 0.0),
                Color(red: 1.0, green: 0.80, blue: 0.0)
            ],
            accentColor: Color(red: 1.0, green: 0.72, blue: 0.05),
            secondaryColor: Color(red: 0.90, green: 0.15, blue: 0.15)
        ),
        "jp": CountryThemeProfile(
            iso: "jp",
            name: "Japan",
            prefix: "JA / JH / JR",
            flagEmoji: "🇯🇵",
            continent: "Asia",
            continentCode: "AS",
            cqZone: "Zone 25",
            ituZone: "Zone 45",
            centerCoordinate: CLLocationCoordinate2D(latitude: 36.2048, longitude: 138.2529),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 14.0, longitudeDelta: 14.0),
            gradientColors: [
                Color(red: 0.95, green: 0.95, blue: 0.96),
                Color(red: 0.74, green: 0.0, blue: 0.18)
            ],
            accentColor: Color(red: 0.88, green: 0.12, blue: 0.28),
            secondaryColor: Color(red: 0.96, green: 0.40, blue: 0.48)
        ),
        "gb": CountryThemeProfile(
            iso: "gb",
            name: "United Kingdom",
            prefix: "G / M / 2E",
            flagEmoji: "🇬🇧",
            continent: "Europe",
            continentCode: "EU",
            cqZone: "Zone 14",
            ituZone: "Zone 27",
            centerCoordinate: CLLocationCoordinate2D(latitude: 55.3781, longitude: -3.4360),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 9.0, longitudeDelta: 8.0),
            gradientColors: [
                Color(red: 0.0, green: 0.13, blue: 0.41),
                Color(red: 0.78, green: 0.06, blue: 0.18)
            ],
            accentColor: Color(red: 0.15, green: 0.40, blue: 0.90),
            secondaryColor: Color(red: 0.85, green: 0.15, blue: 0.20)
        ),
        "it": CountryThemeProfile(
            iso: "it",
            name: "Italy",
            prefix: "I / IK / IZ",
            flagEmoji: "🇮🇹",
            continent: "Europe",
            continentCode: "EU",
            cqZone: "Zone 15",
            ituZone: "Zone 28",
            centerCoordinate: CLLocationCoordinate2D(latitude: 41.8719, longitude: 12.5674),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 10.0, longitudeDelta: 10.0),
            gradientColors: [
                Color(red: 0.0, green: 0.57, blue: 0.27),
                Color(red: 0.95, green: 0.95, blue: 0.95),
                Color(red: 0.80, green: 0.13, blue: 0.16)
            ],
            accentColor: Color(red: 0.06, green: 0.70, blue: 0.45),
            secondaryColor: Color(red: 0.90, green: 0.20, blue: 0.22)
        ),
        "fr": CountryThemeProfile(
            iso: "fr",
            name: "France",
            prefix: "F / TM",
            flagEmoji: "🇫🇷",
            continent: "Europe",
            continentCode: "EU",
            cqZone: "Zone 14",
            ituZone: "Zone 27",
            centerCoordinate: CLLocationCoordinate2D(latitude: 46.2276, longitude: 2.2137),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 9.0, longitudeDelta: 9.0),
            gradientColors: [
                Color(red: 0.0, green: 0.15, blue: 0.33),
                Color(red: 0.95, green: 0.95, blue: 0.96),
                Color(red: 0.93, green: 0.16, blue: 0.22)
            ],
            accentColor: Color(red: 0.20, green: 0.45, blue: 0.95),
            secondaryColor: Color(red: 0.95, green: 0.25, blue: 0.35)
        ),
        "es": CountryThemeProfile(
            iso: "es",
            name: "Spain",
            prefix: "EA / EB / EC",
            flagEmoji: "🇪🇸",
            continent: "Europe",
            continentCode: "EU",
            cqZone: "Zone 14",
            ituZone: "Zone 37",
            centerCoordinate: CLLocationCoordinate2D(latitude: 40.4637, longitude: -3.7492),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 10.0, longitudeDelta: 10.0),
            gradientColors: [
                Color(red: 0.67, green: 0.08, blue: 0.11),
                Color(red: 0.95, green: 0.75, blue: 0.0)
            ],
            accentColor: Color(red: 0.95, green: 0.70, blue: 0.05),
            secondaryColor: Color(red: 0.85, green: 0.15, blue: 0.15)
        ),
        "br": CountryThemeProfile(
            iso: "br",
            name: "Brazil",
            prefix: "PY / PP / PT",
            flagEmoji: "🇧🇷",
            continent: "South America",
            continentCode: "SA",
            cqZone: "Zone 11",
            ituZone: "Zones 12-15",
            centerCoordinate: CLLocationCoordinate2D(latitude: -14.2350, longitude: -51.9253),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 26.0, longitudeDelta: 26.0),
            gradientColors: [
                Color(red: 0.0, green: 0.59, blue: 0.22),
                Color(red: 0.99, green: 0.87, blue: 0.0),
                Color(red: 0.0, green: 0.13, blue: 0.38)
            ],
            accentColor: Color(red: 0.13, green: 0.75, blue: 0.37),
            secondaryColor: Color(red: 0.98, green: 0.80, blue: 0.08)
        ),
        "ca": CountryThemeProfile(
            iso: "ca",
            name: "Canada",
            prefix: "VE / VA / VY",
            flagEmoji: "🇨🇦",
            continent: "North America",
            continentCode: "NA",
            cqZone: "Zones 1-5",
            ituZone: "Zones 2-4",
            centerCoordinate: CLLocationCoordinate2D(latitude: 56.1304, longitude: -106.3468),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 25.0, longitudeDelta: 35.0),
            gradientColors: [
                Color(red: 0.90, green: 0.0, blue: 0.0),
                Color(red: 0.98, green: 0.98, blue: 0.98)
            ],
            accentColor: Color(red: 0.92, green: 0.18, blue: 0.20),
            secondaryColor: Color(red: 0.96, green: 0.40, blue: 0.42)
        ),
        "au": CountryThemeProfile(
            iso: "au",
            name: "Australia",
            prefix: "VK / AX",
            flagEmoji: "🇦🇺",
            continent: "Oceania",
            continentCode: "OC",
            cqZone: "Zones 29, 30",
            ituZone: "Zones 55, 59",
            centerCoordinate: CLLocationCoordinate2D(latitude: -25.2744, longitude: 133.7751),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 24.0, longitudeDelta: 30.0),
            gradientColors: [
                Color(red: 0.0, green: 0.0, blue: 0.55),
                Color(red: 1.0, green: 0.80, blue: 0.0)
            ],
            accentColor: Color(red: 0.95, green: 0.75, blue: 0.05),
            secondaryColor: Color(red: 0.20, green: 0.45, blue: 0.90)
        ),
        "pl": CountryThemeProfile(
            iso: "pl",
            name: "Poland",
            prefix: "SP / SQ / SN",
            flagEmoji: "🇵🇱",
            continent: "Europe",
            continentCode: "EU",
            cqZone: "Zone 15",
            ituZone: "Zone 28",
            centerCoordinate: CLLocationCoordinate2D(latitude: 51.9194, longitude: 19.1451),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 8.0, longitudeDelta: 8.0),
            gradientColors: [
                Color(red: 0.98, green: 0.98, blue: 0.98),
                Color(red: 0.86, green: 0.08, blue: 0.24)
            ],
            accentColor: Color(red: 0.90, green: 0.18, blue: 0.30),
            secondaryColor: Color(red: 0.95, green: 0.45, blue: 0.55)
        ),
        "ru": CountryThemeProfile(
            iso: "ru",
            name: "Russia",
            prefix: "RA / R / UA",
            flagEmoji: "🇷🇺",
            continent: "Europe / Asia",
            continentCode: "EU",
            cqZone: "Zones 16-19",
            ituZone: "Zones 29-34",
            centerCoordinate: CLLocationCoordinate2D(latitude: 61.5240, longitude: 105.3188),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 35.0, longitudeDelta: 60.0),
            gradientColors: [
                Color(red: 0.95, green: 0.95, blue: 0.98),
                Color(red: 0.0, green: 0.22, blue: 0.65),
                Color(red: 0.84, green: 0.17, blue: 0.12)
            ],
            accentColor: Color(red: 0.20, green: 0.45, blue: 0.95),
            secondaryColor: Color(red: 0.90, green: 0.20, blue: 0.20)
        ),
        "ua": CountryThemeProfile(
            iso: "ua",
            name: "Ukraine",
            prefix: "UR / US / UT",
            flagEmoji: "🇺🇦",
            continent: "Europe",
            continentCode: "EU",
            cqZone: "Zone 16",
            ituZone: "Zone 29",
            centerCoordinate: CLLocationCoordinate2D(latitude: 48.3794, longitude: 31.1656),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 8.0, longitudeDelta: 11.0),
            gradientColors: [
                Color(red: 0.0, green: 0.34, blue: 0.72),
                Color(red: 1.0, green: 0.84, blue: 0.0)
            ],
            accentColor: Color(red: 0.20, green: 0.55, blue: 0.95),
            secondaryColor: Color(red: 1.0, green: 0.80, blue: 0.05)
        ),
        "nl": CountryThemeProfile(
            iso: "nl",
            name: "Netherlands",
            prefix: "PA / PB / PE",
            flagEmoji: "🇳🇱",
            continent: "Europe",
            continentCode: "EU",
            cqZone: "Zone 14",
            ituZone: "Zone 27",
            centerCoordinate: CLLocationCoordinate2D(latitude: 52.1326, longitude: 5.2913),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 4.0, longitudeDelta: 4.0),
            gradientColors: [
                Color(red: 0.68, green: 0.11, blue: 0.16),
                Color(red: 0.95, green: 0.95, blue: 0.95),
                Color(red: 0.13, green: 0.27, blue: 0.55)
            ],
            accentColor: Color(red: 0.98, green: 0.45, blue: 0.10),
            secondaryColor: Color(red: 0.20, green: 0.45, blue: 0.90)
        ),
        "se": CountryThemeProfile(
            iso: "se",
            name: "Sweden",
            prefix: "SM / SA / SK",
            flagEmoji: "🇸🇪",
            continent: "Europe",
            continentCode: "EU",
            cqZone: "Zone 14",
            ituZone: "Zone 18",
            centerCoordinate: CLLocationCoordinate2D(latitude: 60.1282, longitude: 18.6435),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 12.0, longitudeDelta: 8.0),
            gradientColors: [
                Color(red: 0.0, green: 0.42, blue: 0.65),
                Color(red: 1.0, green: 0.80, blue: 0.0)
            ],
            accentColor: Color(red: 0.20, green: 0.55, blue: 0.90),
            secondaryColor: Color(red: 0.98, green: 0.80, blue: 0.10)
        ),
        "ch": CountryThemeProfile(
            iso: "ch",
            name: "Switzerland",
            prefix: "HB9 / HB0",
            flagEmoji: "🇨🇭",
            continent: "Europe",
            continentCode: "EU",
            cqZone: "Zone 14",
            ituZone: "Zone 28",
            centerCoordinate: CLLocationCoordinate2D(latitude: 46.8182, longitude: 8.2275),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 4.0, longitudeDelta: 5.0),
            gradientColors: [
                Color(red: 0.85, green: 0.05, blue: 0.08),
                Color(red: 0.98, green: 0.98, blue: 0.98)
            ],
            accentColor: Color(red: 0.90, green: 0.15, blue: 0.20),
            secondaryColor: Color(red: 0.95, green: 0.40, blue: 0.45)
        ),
        "at": CountryThemeProfile(
            iso: "at",
            name: "Austria",
            prefix: "OE",
            flagEmoji: "🇦🇹",
            continent: "Europe",
            continentCode: "EU",
            cqZone: "Zone 15",
            ituZone: "Zone 28",
            centerCoordinate: CLLocationCoordinate2D(latitude: 47.5162, longitude: 14.5501),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 6.0),
            gradientColors: [
                Color(red: 0.93, green: 0.16, blue: 0.22),
                Color(red: 0.98, green: 0.98, blue: 0.98)
            ],
            accentColor: Color(red: 0.90, green: 0.15, blue: 0.20),
            secondaryColor: Color(red: 0.95, green: 0.35, blue: 0.40)
        ),
        "tr": CountryThemeProfile(
            iso: "tr",
            name: "Turkey",
            prefix: "TA / TC",
            flagEmoji: "🇹🇷",
            continent: "Europe / Asia",
            continentCode: "EU",
            cqZone: "Zone 20",
            ituZone: "Zone 39",
            centerCoordinate: CLLocationCoordinate2D(latitude: 38.9637, longitude: 35.2433),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 9.0, longitudeDelta: 14.0),
            gradientColors: [
                Color(red: 0.89, green: 0.04, blue: 0.09),
                Color(red: 0.98, green: 0.98, blue: 0.98)
            ],
            accentColor: Color(red: 0.90, green: 0.12, blue: 0.18),
            secondaryColor: Color(red: 0.95, green: 0.35, blue: 0.40)
        ),
        "kr": CountryThemeProfile(
            iso: "kr",
            name: "South Korea",
            prefix: "HL / DS / 6K",
            flagEmoji: "🇰🇷",
            continent: "Asia",
            continentCode: "AS",
            cqZone: "Zone 25",
            ituZone: "Zone 44",
            centerCoordinate: CLLocationCoordinate2D(latitude: 35.9078, longitude: 127.7669),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0),
            gradientColors: [
                Color(red: 0.98, green: 0.98, blue: 0.98),
                Color(red: 0.0, green: 0.20, blue: 0.47),
                Color(red: 0.78, green: 0.05, blue: 0.19)
            ],
            accentColor: Color(red: 0.20, green: 0.50, blue: 0.95),
            secondaryColor: Color(red: 0.90, green: 0.20, blue: 0.25)
        ),
        "in": CountryThemeProfile(
            iso: "in",
            name: "India",
            prefix: "VU",
            flagEmoji: "🇮🇳",
            continent: "Asia",
            continentCode: "AS",
            cqZone: "Zone 22",
            ituZone: "Zone 41",
            centerCoordinate: CLLocationCoordinate2D(latitude: 20.5937, longitude: 78.9629),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 18.0, longitudeDelta: 18.0),
            gradientColors: [
                Color(red: 1.0, green: 0.60, blue: 0.20),
                Color(red: 0.98, green: 0.98, blue: 0.98),
                Color(red: 0.07, green: 0.53, blue: 0.03)
            ],
            accentColor: Color(red: 1.0, green: 0.55, blue: 0.10),
            secondaryColor: Color(red: 0.10, green: 0.65, blue: 0.20)
        ),
        "za": CountryThemeProfile(
            iso: "za",
            name: "South Africa",
            prefix: "ZS / ZR",
            flagEmoji: "🇿🇦",
            continent: "Africa",
            continentCode: "AF",
            cqZone: "Zone 38",
            ituZone: "Zone 57",
            centerCoordinate: CLLocationCoordinate2D(latitude: -30.5595, longitude: 22.9375),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 14.0, longitudeDelta: 16.0),
            gradientColors: [
                Color(red: 0.0, green: 0.48, blue: 0.24),
                Color(red: 1.0, green: 0.71, blue: 0.07),
                Color(red: 0.87, green: 0.22, blue: 0.19),
                Color(red: 0.0, green: 0.14, blue: 0.58)
            ],
            accentColor: Color(red: 0.08, green: 0.65, blue: 0.35),
            secondaryColor: Color(red: 1.0, green: 0.75, blue: 0.10)
        ),
        "ar": CountryThemeProfile(
            iso: "ar",
            name: "Argentina",
            prefix: "LU / LW",
            flagEmoji: "🇦🇷",
            continent: "South America",
            continentCode: "SA",
            cqZone: "Zone 13",
            ituZone: "Zones 14, 16",
            centerCoordinate: CLLocationCoordinate2D(latitude: -38.4161, longitude: -63.6167),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 20.0, longitudeDelta: 14.0),
            gradientColors: [
                Color(red: 0.45, green: 0.67, blue: 0.87),
                Color(red: 0.98, green: 0.98, blue: 0.98),
                Color(red: 0.45, green: 0.67, blue: 0.87)
            ],
            accentColor: Color(red: 0.35, green: 0.65, blue: 0.95),
            secondaryColor: Color(red: 0.98, green: 0.75, blue: 0.10)
        ),
        "cl": CountryThemeProfile(
            iso: "cl",
            name: "Chile",
            prefix: "CE / XQ",
            flagEmoji: "🇨🇱",
            continent: "South America",
            continentCode: "SA",
            cqZone: "Zone 12",
            ituZone: "Zones 14, 16",
            centerCoordinate: CLLocationCoordinate2D(latitude: -35.6751, longitude: -71.5430),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 22.0, longitudeDelta: 8.0),
            gradientColors: [
                Color(red: 0.0, green: 0.22, blue: 0.65),
                Color(red: 0.98, green: 0.98, blue: 0.98),
                Color(red: 0.84, green: 0.17, blue: 0.12)
            ],
            accentColor: Color(red: 0.20, green: 0.50, blue: 0.95),
            secondaryColor: Color(red: 0.90, green: 0.20, blue: 0.25)
        ),
        "mx": CountryThemeProfile(
            iso: "mx",
            name: "Mexico",
            prefix: "XE / 4A-4C",
            flagEmoji: "🇲🇽",
            continent: "North America",
            continentCode: "NA",
            cqZone: "Zone 6",
            ituZone: "Zone 10",
            centerCoordinate: CLLocationCoordinate2D(latitude: 23.6345, longitude: -102.5528),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 14.0, longitudeDelta: 18.0),
            gradientColors: [
                Color(red: 0.0, green: 0.41, blue: 0.28),
                Color(red: 0.98, green: 0.98, blue: 0.98),
                Color(red: 0.81, green: 0.07, blue: 0.15)
            ],
            accentColor: Color(red: 0.08, green: 0.60, blue: 0.35),
            secondaryColor: Color(red: 0.90, green: 0.18, blue: 0.25)
        )
    ]

    public static func profile(for iso: String, fallbackName: String = "") -> CountryThemeProfile {
        let key = iso.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let existing = predefinedProfiles[key] {
            return existing
        }

        // Algorithmic fallback profile for any other country
        let flag = flagForCountryIso(key)
        let resolvedName = fallbackName.isEmpty ? key.uppercased() : fallbackName
        let hashVal = abs(key.hashValue)
        let hue = Double(hashVal % 360) / 360.0
        let accent = Color(hue: hue, saturation: 0.75, brightness: 0.9)
        let secondary = Color(hue: fmod(hue + 0.3, 1.0), saturation: 0.7, brightness: 0.85)

        return CountryThemeProfile(
            iso: key,
            name: resolvedName,
            prefix: key.uppercased(),
            flagEmoji: flag,
            continent: "Global",
            continentCode: "GL",
            cqZone: "Global",
            ituZone: "Global",
            centerCoordinate: CLLocationCoordinate2D(latitude: 20.0, longitude: 0.0),
            coordinateSpan: MKCoordinateSpan(latitudeDelta: 30.0, longitudeDelta: 40.0),
            gradientColors: [accent, secondary],
            accentColor: accent,
            secondaryColor: secondary
        )
    }
}
