import Foundation

@main struct SKEDCountryDiscoveryRegression {
    static let france = SKEDCountryOption(iso: "fr", regionID: "eu", serviceName: "France")
    static let germany = SKEDCountryOption(iso: "de", regionID: "eu", serviceName: "Germany")
    static let spain = SKEDCountryOption(iso: "es", regionID: "eu", serviceName: "Spain")
    static let italy = SKEDCountryOption(iso: "it", regionID: "eu", serviceName: "Italy")

    static func contact(_ call: String, iso: String, rank: Int, email: String? = "op@example.org") -> SKEDDiscoveryContact {
        .init(operatorInfo: .init(rank: rank, callsign: call, name: "Operator \(call)", email: email,
            score: nil, confirmedQSOs: nil, dxccCountries: nil, bandSlots: nil, mailto: nil),
              countryISO: iso, countryName: iso, workedBands: [], sources: ["QRZ Rank"])
    }

    static func main() async throws {
        precondition(SKEDCountryDiscovery.flag(for: "fr") == "🇫🇷")
        precondition(SKEDCountryDiscovery.flag(for: "bq1") == "🇧🇶")
        precondition(SKEDCountryDiscovery.flag(for: "x1") == "🌐")
        let rows: [[String: String]] = [
            ["CALL": "F1A", "COUNTRY": "France", "BAND": " 10M ", "QSL_RCVD": "N"], // no email or confirmation
            ["CALL": "F1A", "COUNTRY": "Germany", "BAND": "20m", "QSO_DATE": "20261021"], // don't collapse countries by callsign
            ["CALL": "DL1A", "COUNTRY": "Germany", "BAND": "", "FREQ": "14.074"],
            ["CALL": "EA1A", "COUNTRY": "Spain", "BAND": "   ", "FREQ": "28.074"],
            ["CALL": "I1A", "COUNTRY": "Italy", "BAND": ""], // uncertain band history remains visible
            ["CALL": "SELF", "COUNTRY": "Italy", "BAND": "10m"],
            ["CALL": "UNKNOWN", "COUNTRY": "Unknown", "BAND": "10m"]
        ]
        let history = SKEDCountryBandHistory.make(rows: rows, stationCallsign: "SELF", resolve: { _, country in
            switch country {
            case "France": return france
            case "Germany": return germany
            case "Spain": return spain
            case "Italy": return italy
            default: return .init(iso: "--", regionID: "??", serviceName: "Unknown")
            }
        }, bandForFrequency: { frequency in frequency == "28.074" ? "10m" : frequency == "14.074" ? "20m" : nil })
        precondition(history.worked["fr"] == ["10m"] && history.worked["de"] == ["20m"])
        precondition(history.worked["es"] == ["10m"])
        precondition(history.missingBandCounts["it"] == 1 && history.unresolvedCount == 1)
        let countries = [france, germany, spain, italy]
        precondition(history.targets(countries: countries, bands: ["10m"], unworkedOnly: true).map(\.iso) == ["de", "it"])
        precondition(history.targets(countries: countries, bands: ["20m"], unworkedOnly: true).map(\.iso) == ["fr", "es", "it"])
        precondition(history.targets(countries: countries, bands: ["10m", "20m"], unworkedOnly: true).map(\.iso) == ["it"])
        precondition(history.targets(countries: countries, bands: ["10m"], unworkedOnly: false).count == 4)
        precondition(history.targets(countries: countries, bands: [], unworkedOnly: true).isEmpty)
        precondition(SKEDCountryBandHistory().targets(countries: countries, bands: ["10m"], unworkedOnly: true).count == 4)
        // A country never contacted at all still comes from the continent catalog.
        let austria = SKEDCountryOption(iso: "at", regionID: "eu", serviceName: "Austria")
        let destinations = history.targets(countries: countries + [austria], bands: ["10m"], unworkedOnly: true)
        precondition(destinations.map(\.iso) == ["de", "it", "at"])

        let operators = (1...15).reversed().map { contact("DL\($0)TEST", iso: "de", rank: $0) }
            + [contact("SELF", iso: "de", rank: 1), contact("DLBAD", iso: "de", rank: 1, email: nil),
               contact("DL1TEST", iso: "de", rank: 1), contact("I1TEST", iso: "it", rank: 1),
               contact("F1OUT", iso: "fr", rank: 1)]
        let groups = SKEDCountryDiscovery.suggestions(countries: destinations, contacts: operators,
            limit: 10, query: "", stationCallsign: "SELF")
        precondition(groups.count == 3)
        precondition(groups[0].contacts.count == 10 && groups[0].availableCount == 15)
        precondition(groups[0].contacts.map { $0.operatorInfo.rank } == Array(1...10))
        precondition(groups[1].contacts.count == 1 && groups[2].contacts.isEmpty)
        precondition(groups.flatMap(\.contacts).allSatisfy { $0.id != "SELF" && $0.countryISO != "fr" })
        let specific = SKEDCountryDiscovery.suggestions(countries: destinations, contacts: operators,
            limit: 1, query: "DL15TEST", stationCallsign: "SELF")
        precondition(specific.count == 1 && specific[0].contacts[0].id == "DL15TEST", "Search happens before the country limit")
        let emptyCountry = SKEDCountryDiscovery.suggestions(countries: destinations, contacts: operators,
            limit: 10, query: "Austria", stationCallsign: "SELF")
        precondition(emptyCountry.count == 1 && emptyCountry[0].contacts.isEmpty)

        let pool = SKEDCountryDiscovery.suggestions(countries: destinations, contacts: operators,
            limit: Int.max, query: "", stationCallsign: "SELF").flatMap(\.contacts)
        let selected = SKEDCountryDiscovery.selecting(groups.flatMap(\.contacts), current: ["DL15TEST"], pool: pool, limit: 10)
        precondition(selected.contains("DL15TEST"), "An explicit choice outside the initial top 10 must survive text filtering")
        precondition(pool.filter { selected.contains($0.id) && $0.countryISO == "de" }.count == 10)
        precondition(selected.contains("I1TEST"), "Limits apply separately to each country")
        let reduced = SKEDCountryDiscovery.selecting([], current: selected, pool: pool, limit: 2)
        precondition(pool.filter { reduced.contains($0.id) && $0.countryISO == "de" }.count == 2)

        let recorder = CountryRecorder()
        try await SKEDDiscoveryLoader.load(countries: destinations, localContacts: [], fetch: { iso, category in
            await recorder.request(iso)
            if iso == "it" { throw SKEDDirectoryError.server(503, "Unavailable") }
            if iso == "de" && category == "countries" { throw SKEDDirectoryError.server(503, "Unavailable") }
            return .init(countryISO: iso, countryName: iso, category: category,
                         operators: iso == "de" ? [contact("DL1TEST", iso: "de", rank: 1).operatorInfo] : [])
        }, update: { await recorder.record($0) })
        let result = await recorder.last()
        let requested = await recorder.requested()
        precondition(!requested.contains("fr") && !requested.contains("es"), "Worked countries must never be fetched")
        precondition(result.countryStatuses["de"] == .partial && result.countryStatuses["it"] == .failed)
        precondition(result.countryStatuses["at"] == .complete && !result.contacts.contains { $0.countryISO == "at" })
        let enough = CountryRecorder()
        try await SKEDDiscoveryLoader.load(countries: [germany], localContacts: [], targetEmailCount: 10,
            excludingCallsign: "SELF", fetch: { iso, _ in
                await enough.request(iso)
                return .init(countryISO: iso, countryName: iso, category: "qso", operators: operators.map(\.operatorInfo))
            }, update: { await enough.record($0) })
        let enoughRequests = await enough.requested()
        let enoughSnapshot = await enough.last()
        precondition(enoughRequests.count == 1 && enoughSnapshot.countryStatuses["de"] == .suggested,
                     "Stop requesting additional rankings once the requested number of email contacts is available")

        print("SKED country discovery regression passed: all-log band history, unworked eligibility, empty targets, per-country limits, ranking, query, self exclusion and coverage states.")
    }
}

actor CountryRecorder {
    var countries: [String] = []
    var snapshots: [SKEDDiscoverySnapshot] = []
    func request(_ country: String) { countries.append(country) }
    func record(_ snapshot: SKEDDiscoverySnapshot) { snapshots.append(snapshot) }
    func last() -> SKEDDiscoverySnapshot { snapshots.last! }
    func requested() -> [String] { countries }
}
