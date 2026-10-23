import Foundation

@main struct SKEDReadinessRegression {
    static func main() throws {
        let row = ["CALL": "HB0TEST", "COUNTRY": "Liechtenstein", "BAND": "10m", "EMAIL": "op@example.org"]
        var metadataOnly = row
        metadataOnly["QSL_RCVD"] = "Y"
        metadataOnly["QRZ_RANK"] = "1"
        precondition(SKEDDiscoveryLogInput.matches([row], [metadataOnly]), "Background confirmation/rank enrichment must not lock Find contacts")
        for field in SKEDDiscoveryLogInput.fields {
            var changed = row; changed[field] = "changed"
            precondition(!SKEDDiscoveryLogInput.matches([row], [changed]), "Real discovery input changes must revalidate history: \(field)")
        }
        for field in ["NAME", "EMAIL"] {
            var enriched = row; enriched[field] = "updated"
            precondition(!SKEDDiscoveryLogInput.matches([row], [enriched]), "Contact display should refresh")
            precondition(SKEDDiscoveryLogInput.matches([row], [enriched], historyOnly: true), "Contact enrichment must not disable Find or Prepare")
        }
        for field in SKEDDiscoveryLogInput.historyFields {
            var edited = row; edited[field] = "updated"
            precondition(!SKEDDiscoveryLogInput.matches([row], [edited], historyOnly: true), "Country/band eligibility must revalidate")
        }
        precondition(!SKEDDiscoveryLogInput.matches([row], []))
        precondition(!SKEDDiscoveryLogInput.matches([row], [row, row]), "Every logged QSO counts")
        for (iso, name, flag) in [("li", "Liechtenstein", "🇱🇮"), ("sm", "San Marino", "🇸🇲"),
                                   ("ze", "United Kingdom", "🇬🇧"), ("dk", "Denmark", "🇩🇰")] {
            let option = SKEDCountryOption(iso: iso, regionID: "eu", serviceName: iso.uppercased())
            precondition(option.displayName == name)
            precondition(option.menuTitle == "\(flag) \(name)")
        }
        precondition(SKEDCountryDiscovery.flag(for: "zz") == "🌐", "Unknown provider codes must not generate broken flag glyphs")
        precondition(SKEDContactDiscovery.continent(for: .init(iso: "br", regionID: "sam", serviceName: "Brazil")) == "SA")
        let request = try SKEDPreparedDirectoryContract.request(countries: ["li", "gb"], token: "sample-token", userAgent: "Regression")
        precondition(request.url?.path == "/api/v1/sked-ready")
        precondition(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "li,gb")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer sample-token")
        for invalid in [[], Array(repeating: "li", count: 65), ["../li"], ["li", "li"]] {
            do { _ = try SKEDPreparedDirectoryContract.request(countries: invalid, token: "sample", userAgent: "Regression"); preconditionFailure("Invalid batch accepted") }
            catch SKEDDirectoryError.invalidCountry {} catch { preconditionFailure("Wrong validation error") }
        }
        do { _ = try SKEDPreparedDirectoryContract.request(countries: ["li"], token: "bad\r\nHeader", userAgent: "Regression"); preconditionFailure("Header injection accepted") }
        catch SKEDDirectoryError.malformedToken {}
        let entries = Dictionary(uniqueKeysWithValues: ["qso", "countries", "band"].map { ($0, ["country_iso": "li", "country_name": "Liechtenstein", "operators": []] as [String: Any]) })
        let data = try JSONSerialization.data(withJSONObject: ["directories": ["li": entries]])
        let decoded = try SKEDPreparedDirectoryContract.decode(data, countries: ["li"])
        precondition(decoded["li"]?.count == 3 && decoded["li"]?["qso"]?.operators.isEmpty == true, "Empty countries are valid results")
        let localOperator = SKEDOperator(rank: 0, callsign: "HB0TEST", name: "Test", email: "op@example.org", score: nil,
            confirmedQSOs: nil, dxccCountries: nil, bandSlots: nil, mailto: nil)
        let country = SKEDCountryOption(iso: "li", regionID: "eu", serviceName: "LI")
        let local = SKEDDiscoveryContact(operatorInfo: localOperator, countryISO: "li", countryName: "Liechtenstein", workedBands: ["20m"], sources: ["Your log"])
        var rankings = decoded
        rankings["li"]?["band"] = SKEDDirectory(countryISO: "li", countryName: "Liechtenstein", category: "band", operators: [localOperator])
        let assembled = try SKEDDiscoveryLoader.prepared(countries: [country], directories: rankings, localContacts: [local])
        precondition(assembled.contacts.count == 1 && assembled.contacts[0].sources == ["QRZ Rank", "Your log"])
        precondition(assembled.contacts[0].workedBands == ["20m"] && assembled.countryStatuses["li"] == .complete)
        do { _ = try SKEDDiscoveryLoader.prepared(countries: [country], directories: [:], localContacts: [local]); preconditionFailure("Unchecked country marked complete") }
        catch SKEDDirectoryError.badResponse {}

        do { _ = try SKEDPreparedDirectoryContract.decode(data, countries: ["li", "sm"]); preconditionFailure("Incomplete batch silently accepted") }
        catch SKEDDirectoryError.badResponse {}
        var mismatched = entries
        mismatched["qso"] = ["country_iso": "de", "operators": []]
        let bad = try JSONSerialization.data(withJSONObject: ["directories": ["li": mismatched]])
        do { _ = try SKEDPreparedDirectoryContract.decode(bad, countries: ["li"]); preconditionFailure("Cross-country response accepted") }
        catch SKEDDirectoryError.badResponse {}
        print("SKED readiness regression passed: semantic log changes, country names/flags, South America, authenticated bounded prepared batches and incomplete/mismatched response rejection")
    }
}
