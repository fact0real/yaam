import Foundation

nonisolated struct SKEDCountryBandHistory: Sendable {
    var worked: [String: Set<String>] = [:]
    var missingBandCounts: [String: Int] = [:]
    var unresolvedCount = 0

    static func make(rows: [[String: String]], stationCallsign: String,
                     resolve: @Sendable (String, String) -> SKEDCountryOption,
                     bandForFrequency: @Sendable (String) -> String?) -> Self {
        var result = Self()
        var resolved: [String: String] = [:]
        for fields in rows {
            let call = (fields["CALL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard call != stationCallsign.uppercased() || call.isEmpty else { continue }
            let name = (fields["COUNTRY"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let cacheKey = "\(call)|\(name)"
            let iso: String
            if let cached = resolved[cacheKey] { iso = cached }
            else {
                iso = resolve(call, name).iso.lowercased()
                resolved[cacheKey] = iso
            }
            guard !iso.isEmpty, iso != "--", iso != "??" else { result.unresolvedCount += 1; continue }
            let recorded = (fields["BAND"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let band = recorded.isEmpty ? fields["FREQ"].flatMap(bandForFrequency) ?? "" : recorded
            if band.isEmpty { result.missingBandCounts[iso, default: 0] += 1 }
            else { result.worked[iso, default: []].insert(band) }
        }
        return result
    }

    func targets(countries: [SKEDCountryOption], bands: Set<String>, unworkedOnly: Bool) -> [SKEDCountryOption] {
        guard !bands.isEmpty else { return [] }
        return countries.filter { !unworkedOnly || worked[$0.iso.lowercased(), default: []].isDisjoint(with: bands) }
    }
}

nonisolated enum SKEDCountryLoadStatus: Sendable {
    case loading, complete, partial, failed, stopped, suggested

    var title: String {
        switch self {
        case .loading: return "Loading directory…"
        case .complete: return "Directory checked"
        case .partial: return "Partial directory results"
        case .failed: return "Directory unavailable"
        case .stopped: return "Search stopped"
        case .suggested: return "Suggestions loaded"
        }
    }
}

nonisolated struct SKEDCountrySuggestions: Identifiable, Sendable {
    var id: String { country.iso }
    let country: SKEDCountryOption
    let contacts: [SKEDDiscoveryContact]
    let availableCount: Int
}

nonisolated enum SKEDCountryDiscovery {
    static func flag(for iso: String) -> String {
        let canonical = SKEDCountryPresentation.canonicalISO(iso)
        let code = canonical == "bq1" ? "BQ" : canonical.uppercased()
        guard code == "XK" || Locale.Region.isoRegions.contains(where: { $0.identifier == code }),
              code.utf8.count == 2, code.utf8.allSatisfy({ (65...90).contains($0) }) else { return "🌐" }
        return String(String.UnicodeScalarView(code.unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }))
    }

    static func selecting(_ candidates: [SKEDDiscoveryContact], current: Set<String>,
                          pool: [SKEDDiscoveryContact], limit: Int) -> Set<String> {
        var selected = Set<String>()
        var counts: [String: Int] = [:]
        // Existing explicit choices win when a search displays different suggestions.
        for contact in pool.filter({ current.contains($0.id) }) + candidates {
            guard !selected.contains(contact.id), counts[contact.countryISO, default: 0] < max(0, limit) else { continue }
            selected.insert(contact.id)
            counts[contact.countryISO, default: 0] += 1
        }
        return selected
    }

    /// Retain empty countries so a missing directory result never hides a target country.
    static func suggestions(countries: [SKEDCountryOption], contacts: [SKEDDiscoveryContact], limit: Int,
                            query: String, stationCallsign: String) -> [SKEDCountrySuggestions] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let eligible = SKEDContactDiscovery.merge(contacts).filter { $0.id != stationCallsign.uppercased() }
        let grouped = Dictionary(grouping: eligible, by: \.countryISO)
        return countries.compactMap { country in
            let all = grouped[country.iso.lowercased(), default: []].sorted {
                let left = $0.operatorInfo.rank > 0 ? $0.operatorInfo.rank : Int.max
                let right = $1.operatorInfo.rank > 0 ? $1.operatorInfo.rank : Int.max
                return left == right ? $0.id.localizedStandardCompare($1.id) == .orderedAscending : left < right
            }
            let matchesCountry = cleanQuery.isEmpty || country.serviceName.localizedCaseInsensitiveContains(cleanQuery)
                || country.iso.localizedCaseInsensitiveContains(cleanQuery)
            let matching = matchesCountry ? all : SKEDContactDiscovery.filtered(all, bands: [], historyOnly: false, query: cleanQuery)
            guard matchesCountry || !matching.isEmpty else { return nil }
            return SKEDCountrySuggestions(country: country, contacts: Array(matching.prefix(max(0, limit))), availableCount: all.count)
        }
    }
}

nonisolated enum SKEDDiscoveryLogInput {
    static let fields = ["CALL", "COUNTRY", "BAND", "FREQ", "NAME", "EMAIL", "QSO_DATE", "TIME_ON"]
    static let historyFields = ["CALL", "COUNTRY", "BAND", "FREQ", "QSO_DATE", "TIME_ON"]
    static func matches(_ lhs: [[String: String]], _ rhs: [[String: String]], historyOnly: Bool = false) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let relevant = historyOnly ? historyFields : fields
        return zip(lhs, rhs).allSatisfy { left, right in
            if left == right { return true }
            return relevant.allSatisfy { left[$0] == right[$0] }
        }
    }
}
