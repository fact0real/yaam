import Foundation

/// Band history describes observed contacts, never a promise of present availability.
nonisolated struct SKEDDiscoveryContact: Identifiable, Sendable {
    var id: String { operatorInfo.callsign }
    let operatorInfo: SKEDOperator
    let countryISO: String
    let countryName: String
    var workedBands: Set<String>
    var sources: Set<String>
}

nonisolated enum SKEDContactDiscovery {
    static let continents = [("AF", "Africa"), ("AN", "Antarctica"), ("AS", "Asia"),
                             ("EU", "Europe"), ("NA", "North America"), ("OC", "Oceania"), ("SA", "South America")]

    static func continent(for country: SKEDCountryOption) -> String {
        // The provider splits the Middle East out of Asia.
        switch country.regionID.lowercased() {
        case "me": "AS"
        case "sam": "SA"
        default: country.regionID.uppercased()
        }
    }

    static func loggedContacts(rows: [[String: String]], stationCallsign: String,
                               resolve: @Sendable (String, String) -> SKEDCountryOption,
                               bandForFrequency: @Sendable (String) -> String?) -> ([SKEDDiscoveryContact], [SKEDCountryOption]) {
        var history: [String: Set<String>] = [:]
        var byCall: [String: SKEDDiscoveryContact] = [:]
        var countries: [String: SKEDCountryOption] = [:]
        let ordered = rows.sorted {
            ($0["QSO_DATE"] ?? "") + ($0["TIME_ON"] ?? "") > ($1["QSO_DATE"] ?? "") + ($1["TIME_ON"] ?? "")
        }
        for fields in ordered {
            let call = (fields["CALL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !call.isEmpty, call != stationCallsign.uppercased() else { continue }
            let recordedBand = (fields["BAND"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let band = recordedBand.isEmpty ? fields["FREQ"].flatMap(bandForFrequency) ?? "" : recordedBand
            if !band.isEmpty { history[call, default: []].insert(band) }
            let item = SKEDOperator(rank: 0, callsign: call, name: fields["NAME"], email: fields["EMAIL"], score: nil,
                confirmedQSOs: nil, dxccCountries: nil, bandSlots: nil, mailto: nil)
            if let previous = byCall[call] {
                if previous.operatorInfo.validEmail == nil && item.validEmail != nil {
                    byCall[call] = SKEDDiscoveryContact(operatorInfo: item, countryISO: previous.countryISO,
                        countryName: previous.countryName, workedBands: [], sources: ["Your log"])
                }
            } else {
                let country = resolve(call, fields["COUNTRY"] ?? "")
                countries[country.iso] = country
                byCall[call] = SKEDDiscoveryContact(operatorInfo: item, countryISO: country.iso,
                    countryName: country.serviceName, workedBands: [], sources: ["Your log"])
            }
        }
        let contacts = byCall.values.map { contact in
            var result = contact
            result.workedBands = history[contact.id] ?? []
            return result
        }
        return (contacts, Array(countries.values))
    }

    static func savePlans(contacts: [SKEDDiscoveryContact], bandsByCallsign: [String: Set<String>],
                          stationCallsign: String, defaults: UserDefaults) {
        for (destination, recipients) in Dictionary(grouping: contacts, by: \.countryISO) {
            let key = "sked.bandPlans.v1.\(stationCallsign).\(destination)"
            var saved = defaults.data(forKey: key)
                .flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
            for contact in recipients { saved[contact.id] = SKEDMailTemplate.ordered(bandsByCallsign[contact.id, default: []]) }
            if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: key) }
        }
    }

    static func merge(_ contacts: [SKEDDiscoveryContact]) -> [SKEDDiscoveryContact] {
        var result: [String: SKEDDiscoveryContact] = [:]
        for incoming in contacts where incoming.operatorInfo.validEmail != nil {
            let item = incoming.operatorInfo
            let key = incoming.id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !key.isEmpty else { continue }
            let contact = SKEDDiscoveryContact(operatorInfo: SKEDOperator(rank: item.rank, callsign: key,
                name: item.name, email: item.validEmail, score: item.score, confirmedQSOs: item.confirmedQSOs,
                dxccCountries: item.dxccCountries, bandSlots: item.bandSlots, mailto: item.mailto),
                countryISO: SKEDCountryPresentation.canonicalISO(incoming.countryISO), countryName: SKEDCountryPresentation.name(iso: incoming.countryISO, fallback: incoming.countryName),
                workedBands: Set(incoming.workedBands.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }),
                sources: incoming.sources)
            if var previous = result[key] {
                let combinedBands = previous.workedBands.union(contact.workedBands)
                let combinedSources = previous.sources.union(contact.sources)
                if contact.sources.contains("QRZ Rank") && !previous.sources.contains("QRZ Rank") { previous = contact }
                previous.workedBands = combinedBands
                previous.sources = combinedSources
                result[key] = previous
            } else {
                result[key] = contact
            }
        }
        return result.values.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    static func filtered(_ contacts: [SKEDDiscoveryContact], bands: Set<String>, historyOnly: Bool,
                         query: String) -> [SKEDDiscoveryContact] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return contacts.filter { contact in
            (!historyOnly || !contact.workedBands.isDisjoint(with: bands)) &&
            (text.isEmpty || [contact.id, contact.operatorInfo.name ?? "", contact.operatorInfo.validEmail ?? "", contact.countryName]
                .contains { $0.localizedCaseInsensitiveContains(text) })
        }
    }
}

nonisolated struct SKEDDiscoverySnapshot: Sendable {
    var contacts: [SKEDDiscoveryContact]
    var failures: [String]
    var progress: String
    var countryStatuses: [String: SKEDCountryLoadStatus] = [:]
}

nonisolated enum SKEDDiscoveryLoader {
    /// Assemble one prepared batch off the UI actor, merging the contact pool only once.
    static func prepared(countries: [SKEDCountryOption], directories: [String: [String: SKEDDirectory]],
                         localContacts: [SKEDDiscoveryContact]) throws -> SKEDDiscoverySnapshot {
        let allowed = Set(countries.map(\.iso))
        var contacts = localContacts.filter { allowed.contains($0.countryISO) }
        var history: [String: Set<String>] = [:]
        for contact in localContacts { history[contact.id.uppercased(), default: []].formUnion(contact.workedBands) }
        var statuses: [String: SKEDCountryLoadStatus] = [:]
        for country in countries {
            for category in ["qso", "countries", "band"] {
                guard let directory = directories[country.iso]?[category] else { throw SKEDDirectoryError.badResponse }
                contacts += directory.operators.map { item in
                    SKEDDiscoveryContact(operatorInfo: item, countryISO: country.iso, countryName: country.displayName,
                        workedBands: history[item.callsign.uppercased()] ?? [], sources: ["QRZ Rank"])
                }
            }
            statuses[country.iso] = .complete
        }
        return SKEDDiscoverySnapshot(contacts: SKEDContactDiscovery.merge(contacts), failures: [], progress: "",
                                     countryStatuses: statuses)
    }

    /// Sequential requests keep continent searches cancellable without flooding the provider.
    static func load(countries: [SKEDCountryOption], localContacts: [SKEDDiscoveryContact],
                     targetEmailCount: Int? = nil, excludingCallsign: String = "",
                     fetch: @Sendable (String, String) async throws -> SKEDDirectory,
                     update: @Sendable (SKEDDiscoverySnapshot) async -> Void) async throws {
        let allowed = Set(countries.map(\.iso))
        var state = SKEDDiscoverySnapshot(
            contacts: SKEDContactDiscovery.merge(localContacts.filter { allowed.contains($0.countryISO) }),
            failures: [], progress: "")
        var history: [String: Set<String>] = [:]
        for contact in localContacts { history[contact.id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), default: []].formUnion(contact.workedBands) }
        for (index, country) in countries.enumerated() {
            try Task.checkCancellation()
            state.progress = "\(index + 1) / \(countries.count) · \(country.serviceName)"
            state.countryStatuses[country.iso] = .loading
            await update(state)
            var successfulCategories = 0
            for category in ["qso", "countries", "band"] {
                do {
                    let directory = try await fetch(country.iso, category)
                    try Task.checkCancellation()
                    let additions = directory.operators.map { item in
                        SKEDDiscoveryContact(operatorInfo: item, countryISO: country.iso,
                            countryName: country.serviceName, workedBands: history[item.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()] ?? [], sources: ["QRZ Rank"])
                    }
                    state.contacts = SKEDContactDiscovery.merge(state.contacts + additions)
                    successfulCategories += 1
                    let emailCount = state.contacts.filter {
                        $0.countryISO == country.iso && $0.id != excludingCallsign.uppercased()
                    }.count
                    if let targetEmailCount, targetEmailCount > 0, emailCount >= targetEmailCount,
                       successfulCategories < 3 {
                        state.countryStatuses[country.iso] = .suggested
                        await update(state)
                        break
                    }
                    await update(state)
                } catch {
                    try Task.checkCancellation()
                    var stop = false
                    switch error {
                    case SKEDDirectoryError.missingToken, SKEDDirectoryError.malformedToken:
                        stop = true
                    case SKEDDirectoryError.server(let status, _):
                        stop = [401, 403, 429].contains(status)
                    default: break
                    }
                    state.countryStatuses[country.iso] = successfulCategories > 0 ? .partial : .failed
                    state.failures.append("\(country.serviceName): \(error.localizedDescription)")
                    if stop {
                        state.failures.append("Search stopped; remaining directory results were not loaded")
                        state.progress = ""
                        await update(state)
                        return
                    }
                    // Keep successful categories and continue to the next country after a failure.
                    break
                }
            }
            if successfulCategories == 3 { state.countryStatuses[country.iso] = .complete }
            await update(state)
        }
        state.progress = ""
        await update(state)
    }
}
