import Foundation
@main struct NextCreditRegression {
    static func main() {
        func c(_ call: String, _ country: String, _ band: String, _ grid: String?, confirmed: Bool = false, route: Bool = false) -> NextCreditContact {
            NextCreditContact(id: UUID(), identity: call + country + band + (grid ?? ""), call: call, country: country, band: band, grid: grid, state: nil, cqZone: nil, confirmed: confirmed, hasRoute: route, daysPending: nil)
        }
        precondition(NextCreditEngine.usState("AK", country: "Alaska", dxcc: "6") == "AK")
        precondition(NextCreditEngine.usState("HI", country: "Hawaii", dxcc: "110") == "HI")
        precondition(NextCreditEngine.usState("CA", country: "Canada", dxcc: "1") == nil)
        precondition(NextCreditEngine.usState("ZZ", country: "United States", dxcc: "291") == nil)
        let known = c("KNOWN", "France", "20m", "JN18", confirmed: true)
        let first = c("FIRST", "Cameroon", "17m", "JJ11")
        let shared = c("SHARED", "Cameroon", "17m", "JJ11", route: true)
        let other = c("OTHER", "France", "20m", "JN19")
        let staleCopy = c("KNOWN", "France", "20m", "JN18", route: true)
        let contacts = [known, staleCopy, first, first, shared, other]
        let queue = NextCreditEngine.queue(contacts: contacts, weights: .init())
        precondition(!queue.contains { $0.id == known.id || $0.id == staleCopy.id })
        precondition(Set(queue.map(\.id)).count == queue.count)
        precondition(queue.first?.id == shared.id)
        precondition(queue.filter { $0.reasons.contains(where: { $0.contains("Cameroon") && $0.contains("country-band") }) }.count == 1)
        precondition(queue.filter { $0.reasons.contains("New confirmed grid: JJ11") }.count == 1)
        var gridOnly = NextCreditWeights(countryBand: 0, grid: 10, award: 0, likelihood: 0, operational: 0)
        let changed = NextCreditEngine.queue(contacts: contacts, weights: gridOnly)
        precondition(changed.count == 2 && changed.allSatisfy { $0.score == 10 })
        gridOnly.grid = .nan
        precondition(NextCreditEngine.queue(contacts: contacts, weights: gridOnly).isEmpty)
        precondition(NextCreditEngine.queue(contacts: [], weights: .init()).isEmpty)
        let large = (0..<10000).map { c("TEST\($0)", "France", "20m", "G\($0)") }
        let start = Date(); let ranked = NextCreditEngine.queue(contacts: large, weights: .init())
        precondition(ranked.count == 100)
        print("PASS marginal credits, duplicate identities, confirmed exclusion, weights, missing evidence; 10k contacts / 100 suggestions: \(Date().timeIntervalSince(start))s")
    }
}
