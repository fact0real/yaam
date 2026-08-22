//
//  ConfirmationOpportunity.swift
//  YAAM
//

import Foundation

nonisolated enum ConfirmationCreditColumn {
    static let countryBand = "APP_VIEW_CONFIRM_BAND_CREDIT"
    static let grid = "APP_VIEW_CONFIRM_GRID_CREDIT"
    static let headers = [countryBand, grid]

    static func isDerived(_ header: String) -> Bool {
        headers.contains(header)
    }
}

nonisolated struct QSOConfirmationOpportunity: Sendable {
    let isConfirmed: Bool
    let country: String
    let band: String
    let grid: String?
    let addsCountryBandCredit: Bool
    let addsGridCredit: Bool

    var hasCountryBandData: Bool {
        !country.isEmpty && !band.isEmpty
    }
}

nonisolated enum CountryBandCoverageState: String, Sendable {
    case confirmed
    case worked
    case needed
}

nonisolated struct CountryBandCoverageItem: Identifiable, Sendable {
    var id: String { band }
    let band: String
    let state: CountryBandCoverageState
    let qsoCount: Int
    let confirmedCount: Int
}

nonisolated struct CountryBandCoverage: Identifiable, Sendable {
    var id: String { country }
    let country: String
    let bands: [CountryBandCoverageItem]

    var confirmedBandCount: Int {
        bands.filter { $0.state == .confirmed }.count
    }

    var workedUnconfirmedBandCount: Int {
        bands.filter { $0.state == .worked }.count
    }

    var neededBandCount: Int {
        bands.filter { $0.state == .needed }.count
    }
}

nonisolated struct ConfirmationOpportunityIndex: Sendable {
    private struct CountryBandKey: Hashable, Sendable {
        let country: String
        let band: String
    }

    private struct BandCounts: Sendable {
        var total = 0
        var confirmed = 0
    }

    static let standardBands = [
        "2190m", "630m", "160m", "80m", "60m", "40m", "30m", "20m", "17m",
        "15m", "12m", "10m", "6m", "4m", "2m", "1.25m", "70cm", "33cm",
        "23cm", "13cm", "9cm", "6cm", "3cm", "1.25cm"
    ]

    private let opportunitiesByRecordID: [UUID: QSOConfirmationOpportunity]
    let countryBandCoverage: [CountryBandCoverage]

    init(records: [QSORecordModel]) {
        var confirmedCountryBands = Set<CountryBandKey>()
        var confirmedGrids = Set<String>()
        var bandCountsByCountry: [String: [String: BandCounts]] = [:]
        var confirmedCountries = Set<String>()
        var observedBands = Set<String>()

        for record in records {
            let country = Self.normalizedCountry(for: record)
            let band = Self.normalizedBand(for: record)
            let grid = Self.fourCharacterGrid(for: record)

            if !band.isEmpty {
                observedBands.insert(band)
            }

            if !country.isEmpty, !band.isEmpty {
                var countryCounts = bandCountsByCountry[country] ?? [:]
                var counts = countryCounts[band] ?? BandCounts()
                counts.total += 1
                if record.isConfirmed {
                    counts.confirmed += 1
                    confirmedCountryBands.insert(CountryBandKey(country: country, band: band))
                    confirmedCountries.insert(country)
                }
                countryCounts[band] = counts
                bandCountsByCountry[country] = countryCounts
            } else if record.isConfirmed, !country.isEmpty {
                confirmedCountries.insert(country)
            }

            if record.isConfirmed, let grid {
                confirmedGrids.insert(grid)
            }
        }

        var opportunities: [UUID: QSOConfirmationOpportunity] = [:]
        opportunities.reserveCapacity(records.count)

        for record in records {
            let country = Self.normalizedCountry(for: record)
            let band = Self.normalizedBand(for: record)
            let grid = Self.fourCharacterGrid(for: record)
            let countryBandKey = CountryBandKey(country: country, band: band)
            let hasCountryBand = !country.isEmpty && !band.isEmpty

            opportunities[record.id] = QSOConfirmationOpportunity(
                isConfirmed: record.isConfirmed,
                country: country,
                band: band,
                grid: grid,
                addsCountryBandCredit: !record.isConfirmed
                    && hasCountryBand
                    && !confirmedCountryBands.contains(countryBandKey),
                addsGridCredit: !record.isConfirmed
                    && grid.map { !confirmedGrids.contains($0) } == true
            )
        }

        let bandUniverse = Self.orderedBandUniverse(observedBands: observedBands)
        countryBandCoverage = confirmedCountries
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { country in
                let countryCounts = bandCountsByCountry[country] ?? [:]
                let bands = bandUniverse.map { band -> CountryBandCoverageItem in
                    let counts = countryCounts[band] ?? BandCounts()
                    let state: CountryBandCoverageState
                    if counts.confirmed > 0 {
                        state = .confirmed
                    } else if counts.total > 0 {
                        state = .worked
                    } else {
                        state = .needed
                    }

                    return CountryBandCoverageItem(
                        band: band,
                        state: state,
                        qsoCount: counts.total,
                        confirmedCount: counts.confirmed
                    )
                }
                return CountryBandCoverage(country: country, bands: bands)
            }

        opportunitiesByRecordID = opportunities
    }

    func opportunity(for recordID: UUID) -> QSOConfirmationOpportunity? {
        opportunitiesByRecordID[recordID]
    }

    static func normalizedBand(for record: QSORecordModel) -> String {
        let rawBand = record["BAND"].trimmingCharacters(in: .whitespacesAndNewlines)
        let band = rawBand.isEmpty ? AmateurBandPlan.band(for: record["FREQ"]) ?? "" : rawBand
        guard !band.isEmpty else { return "" }

        let clean = band
            .lowercased()
            .replacingOccurrences(of: "meters", with: "m")
            .replacingOccurrences(of: "meter", with: "m")
            .replacingOccurrences(of: " ", with: "")

        if let standard = Self.standardBands.first(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
            return standard
        }
        return clean
    }

    static func fourCharacterGrid(for record: QSORecordModel) -> String? {
        GridLocator.fourCharacterGrid(from: record["GRIDSQUARE"])
            ?? GridLocator.fourCharacterGrid(from: record["GRID"])
            ?? GridLocator.fourCharacterGrid(latitude: record["LAT"], longitude: record["LON"])
            ?? GridLocator.fourCharacterGrid(latitude: record["LATITUDE"], longitude: record["LONGITUDE"])
    }

    private static func normalizedCountry(for record: QSORecordModel) -> String {
        canonicalCountryName(record["COUNTRY"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func orderedBandUniverse(observedBands: Set<String>) -> [String] {
        standardBands + observedBands
            .filter { !standardBands.contains($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
