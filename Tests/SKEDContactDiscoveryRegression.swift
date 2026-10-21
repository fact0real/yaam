import Foundation

actor DiscoveryRecorder {
    var calls: [String] = []
    var snapshots: [SKEDDiscoverySnapshot] = []
    func call(_ value: String) { calls.append(value) }
    func record(_ value: SKEDDiscoverySnapshot) { snapshots.append(value) }
    func last() -> SKEDDiscoverySnapshot { snapshots.last! }
    func count() -> Int { calls.count }
}

@main struct SKEDContactDiscoveryRegression {
    static func contact(_ call: String, email: String? = "op@example.org", iso: String = "ir",
                        bands: Set<String> = [], source: String = "Your log") -> SKEDDiscoveryContact {
        .init(operatorInfo: .init(rank: 1, callsign: call, name: "Alex", email: email, score: nil,
            confirmedQSOs: nil, dxccCountries: nil, bandSlots: nil, mailto: nil), countryISO: iso,
            countryName: iso == "ir" ? "Iran" : "France", workedBands: bands, sources: [source])
    }
    static func main() async throws {
        let iran = SKEDCountryOption(iso: "ir", regionID: "me", serviceName: "Iran")
        let france = SKEDCountryOption(iso: "fr", regionID: "eu", serviceName: "France")
        precondition(SKEDContactDiscovery.continent(for: iran) == "AS")
        precondition(SKEDContactDiscovery.continent(for: france) == "EU")
        precondition(SKEDContactDiscovery.continents.count == 7)
        for invalid in ["", "@", "a@@example.org", "a@example.org,b@example.org", "a@example.org;b@example.org", "a@example.org\r\nBcc:x@y.org", "a@-example.org"] {
            precondition(contact("EP1A", email: invalid).operatorInfo.validEmail == nil)
        }
        precondition(contact("EP1A", email: " first.last+sked@example.org ").operatorInfo.validEmail == "first.last+sked@example.org")
        let merged = SKEDContactDiscovery.merge([
            contact(" ep1a ", bands: ["20M"]), contact("EP1A", email: "current@example.org", bands: ["40m"], source: "QRZ Rank"),
            contact("F1AAA", iso: "fr"), contact("EP2BAD", email: nil)])
        precondition(merged.count == 2)
        let ep = merged.first { $0.id == "EP1A" }!
        precondition(ep.workedBands == ["20m", "40m"] && ep.sources.count == 2)
        precondition(ep.operatorInfo.validEmail == "current@example.org")
        precondition(SKEDContactDiscovery.filtered(merged, bands: ["40m", "10m"], historyOnly: true, query: "").map(\.id) == ["EP1A"])
        precondition(SKEDContactDiscovery.filtered(merged, bands: ["6m"], historyOnly: true, query: "").isEmpty)
        precondition(SKEDContactDiscovery.filtered(merged, bands: ["6m"], historyOnly: false, query: " france ").map(\.id) == ["F1AAA"])
        precondition(SKEDContactDiscovery.filtered(merged, bands: [], historyOnly: false, query: "CURRENT@").count == 1)

        let (logged, loggedCountries) = SKEDContactDiscovery.loggedContacts(rows: [
            ["CALL": " ep1a ", "EMAIL": "old@example.org", "BAND": "40M", "QSO_DATE": "20250101"],
            ["CALL": "EP1A", "EMAIL": "new@example.org", "BAND": " ", "FREQ": "14.074", "QSO_DATE": "20261020"],
            ["CALL": "EP2A", "BAND": "10m"], ["CALL": "MYCALL", "EMAIL": "self@example.org"]
        ], stationCallsign: "MYCALL", resolve: { _, _ in iran }, bandForFrequency: { $0 == "14.074" ? "20m" : nil })
        precondition(logged.count == 2 && loggedCountries.count == 1)
        let latest = logged.first { $0.id == "EP1A" }!
        precondition(latest.operatorInfo.validEmail == "new@example.org" && latest.workedBands == ["40m", "20m"])
        precondition(logged.first { $0.id == "EP2A" }!.operatorInfo.validEmail == nil, "Keep history for later directory email enrichment")

        let suite = "YAAM.SKEDDiscoveryRegression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(["EP9KEEP": ["10m"]]), forKey: "sked.bandPlans.v1.W1TEST.ir")
        SKEDContactDiscovery.savePlans(contacts: [contact("EP1A"), contact("F1AAA", iso: "fr")],
            bandsByCallsign: ["EP1A": ["40m", "20m"], "F1AAA": ["15m"]], stationCallsign: "W1TEST", defaults: defaults)
        let iranPlans = try JSONDecoder().decode([String: [String]].self, from: defaults.data(forKey: "sked.bandPlans.v1.W1TEST.ir")!)
        let francePlans = try JSONDecoder().decode([String: [String]].self, from: defaults.data(forKey: "sked.bandPlans.v1.W1TEST.fr")!)
        precondition(iranPlans == ["EP9KEEP": ["10m"], "EP1A": ["40m", "20m"]])
        precondition(francePlans == ["F1AAA": ["15m"]])
        precondition(defaults.data(forKey: "sked.bandPlans.v1.OTHER.ir") == nil, "Other station plans stay isolated")

        let recorder = DiscoveryRecorder()
        try await SKEDDiscoveryLoader.load(countries: [iran, france], localContacts: [
            contact("EP1LOCAL", bands: ["20m"]), contact("F1REMOTE", email: nil, iso: "fr", bands: ["10m"]),
            contact("K1OUTSIDE", iso: "us")], fetch: { iso, category in
                await recorder.call("\(iso):\(category)")
                if iso == "ir" && category == "countries" { throw SKEDDirectoryError.server(503, "Unavailable") }
                let item = contact(iso == "ir" ? "EP1NEW" : "F1REMOTE", iso: iso, source: "QRZ Rank").operatorInfo
                return SKEDDirectory(countryISO: iso, countryName: iso, category: category, operators: [item])
            }, update: { await recorder.record($0) })
        let result = await recorder.last()
        precondition(result.contacts.count == 3 && result.failures.count == 1 && result.progress.isEmpty)
        precondition(result.contacts.first { $0.id == "F1REMOTE" }!.workedBands == ["10m"])
        precondition(!result.contacts.contains { $0.id == "K1OUTSIDE" })
        let count = await recorder.count()
        precondition(count == 5, "One failed category keeps earlier results and continues the next country")

        for status in [401, 403, 429] {
            let blocked = DiscoveryRecorder()
            try await SKEDDiscoveryLoader.load(countries: [iran, france], localContacts: [contact("EP1LOCAL")],
                fetch: { _, _ in await blocked.call("request"); throw SKEDDirectoryError.server(status, "Blocked") },
                update: { await blocked.record($0) })
            let blockedCount = await blocked.count()
            let snapshot = await blocked.last()
            precondition(blockedCount == 1 && snapshot.contacts.count == 1 && snapshot.failures.count == 2)
        }
        let missing = DiscoveryRecorder()
        try await SKEDDiscoveryLoader.load(countries: [iran, france], localContacts: [],
            fetch: { _, _ in await missing.call("request"); throw SKEDDirectoryError.missingToken },
            update: { await missing.record($0) })
        let missingCount = await missing.count()
        precondition(missingCount == 1)
        let started = DiscoveryRecorder()
        let cancelled = Task {
            try await SKEDDiscoveryLoader.load(countries: [iran], localContacts: [],
                fetch: { _, _ in
                    await started.call("started")
                    try await Task.sleep(for: .seconds(30))
                    fatalError("Cancelled fetch must not finish")
                },
                update: { _ in })
        }
        while await started.count() == 0 { await Task.yield() }
        cancelled.cancel()
        do { try await cancelled.value; preconditionFailure("Cancellation must propagate") }
        catch is CancellationError { }
        let empty = DiscoveryRecorder()
        try await SKEDDiscoveryLoader.load(countries: [iran], localContacts: [], fetch: { iso, category in
            SKEDDirectory(countryISO: iso, countryName: "Iran", category: category, operators: [])
        }, update: { await empty.record($0) })
        let emptyResult = await empty.last()
        precondition(emptyResult.contacts.isEmpty && emptyResult.failures.isEmpty, "Empty success is distinct from service failure")
        let invitation = SKEDMailTemplate.render(SKEDMailTemplate.defaultBody, callsign: "EP1A", name: "Alex",
            bands: ["20m", "40m"], stationCallsign: "W1TEST", stationGrid: "FN42", stationQTH: "Boston")
        precondition(invitation.contains("40m and 20m") && invitation.contains("station and availability"))
        precondition(!invitation.contains("antenna's resonance"))
        print("SKED contact discovery regression passed: geography, email validation, deduplication, band matching, partial coverage, rate limits and cancellation.")
    }
}
