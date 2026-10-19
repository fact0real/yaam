import Foundation

nonisolated struct NextCreditWeights: Equatable, Sendable {
    var countryBand: Double = 5
    var grid: Double = 3
    var award: Double = 4
    var likelihood: Double = 2
    var operational: Double = 1
}

nonisolated struct NextCreditContact: Sendable {
    let id: UUID
    let identity: String
    let call: String
    let country: String
    let band: String
    let grid: String?
    let state: String?
    let cqZone: String?
    let confirmed: Bool
    let hasRoute: Bool
    let daysPending: Int?
}

nonisolated struct NextCreditSuggestion: Identifiable, Sendable {
    let contact: NextCreditContact
    var id: UUID { contact.id }
    let score: Double
    let reasons: [String]
    let likelihood: String
}

nonisolated enum NextCreditEngine {
    private static let usStateCodes = Set("AL AK AZ AR CA CO CT DE FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY".split(separator: " ").map(String.init))

    static func usState(_ raw: String, country: String, dxcc: String) -> String? {
        let state = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let eligible = ["291", "6", "110"].contains(dxcc) || ["United States", "Alaska", "Hawaii"].contains(country)
        return eligible && usStateCodes.contains(state) ? state : nil
    }

    private static func credits(_ c: NextCreditContact) -> Set<String> {
        var keys = Set<String>()
        if !c.country.isEmpty {
            keys.insert("award:country:" + c.country)
            if !c.band.isEmpty { keys.insert("band:" + c.country + ":" + c.band) }
        }
        if let grid = c.grid { keys.insert("grid:" + grid) }
        if let state = c.state { keys.insert("award:state:" + state) }
        if let zone = c.cqZone { keys.insert("award:zone:" + zone) }
        return keys
    }

    /// Greedy marginal credit: once a recommendation accounts for a credit, subsequent
    /// recommendations cannot claim it again. Likelihood is a disclosed heuristic, never a probability.
    static func queue(contacts: [NextCreditContact], weights: NextCreditWeights, limit: Int = 100) -> [NextCreditSuggestion] {
        var covered = Set<String>()
        var previouslyConfirmedCalls = Set<String>()
        for c in contacts where c.confirmed {
            covered.formUnion(credits(c)); previouslyConfirmedCalls.insert(c.call)
        }
        var seen = Set<String>()
        let candidates = contacts.filter { !$0.confirmed && !$0.call.isEmpty && seen.insert($0.identity).inserted }
            .map { ($0, credits($0)) }
        var used = Set<UUID>()
        var result: [NextCreditSuggestion] = []
        func weight(_ value: Double) -> Double { value.isFinite ? max(0, min(10, value)) : 0 }
        let bandWeight = weight(weights.countryBand)
        let gridWeight = weight(weights.grid)
        let awardWeight = weight(weights.award)
        let operationalWeight = weight(weights.operational)
        let baseScores = candidates.map { c, _ -> Double in
            let evidence = previouslyConfirmedCalls.contains(c.call) ? 1.0 : c.hasRoute ? 0.5 : 0
            let age = c.daysPending.map { $0 >= 30 ? min(1, Double($0) / 180) : 0 } ?? 0
            return weight(weights.likelihood) * evidence + operationalWeight * ((c.hasRoute ? 1 : 0) + age)
        }
        for _ in 0..<max(0, min(limit, candidates.count)) {
            if Task.isCancelled { return [] }
            var winner: Int?
            var bestScore = -Double.infinity
            for i in candidates.indices where !used.contains(candidates[i].0.id) {
                let (c, keys) = candidates[i]
                var score = baseScores[i]
                for key in keys where !covered.contains(key) {
                    score += key.hasPrefix("band:") ? bandWeight : key.hasPrefix("grid:") ? gridWeight : awardWeight
                }
                if score > bestScore || (score == bestScore && winner.map { (c.call, c.identity) < (candidates[$0].0.call, candidates[$0].0.identity) } == true) {
                    winner = i; bestScore = score
                }
            }
            guard let winner, bestScore > 0 else { break }
            let (c, keys) = candidates[winner]
            let marginal = keys.subtracting(covered)
            var reasons: [String] = []
            if marginal.contains(where: { $0.hasPrefix("band:") }) {
                reasons.append("New confirmed country-band: \(c.country) · \(c.band)")
            }
            if marginal.contains(where: { $0.hasPrefix("grid:") }) { reasons.append("New confirmed grid: \(c.grid ?? "")") }
            for award in marginal.filter({ $0.hasPrefix("award:") }).sorted() {
                reasons.append(award.replacingOccurrences(of: "award:country:", with: "New DXCC country: ")
                    .replacingOccurrences(of: "award:state:", with: "New US state: ")
                    .replacingOccurrences(of: "award:zone:", with: "New CQ zone: "))
            }
            let likelihood = previouslyConfirmedCalls.contains(c.call)
                ? "Prior confirmation from this callsign; no response probability is known."
                : c.hasRoute ? "A follow-up route is recorded; response likelihood is unknown."
                : "No follow-up route recorded; response likelihood is unknown."
            if c.hasRoute { reasons.append("Recorded follow-up route") }
            if let days = c.daysPending, days >= 30 { reasons.append("Pending \(days) days") }
            if reasons.isEmpty { reasons.append("No additional credit beyond earlier suggestions") }
            result.append(NextCreditSuggestion(contact: c, score: bestScore, reasons: reasons, likelihood: likelihood))
            used.insert(c.id); covered.formUnion(marginal)
        }
        return result
    }
}
