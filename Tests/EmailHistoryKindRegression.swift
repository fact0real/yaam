import Foundation

@main
struct EmailHistoryKindRegression {
    static func main() throws {
        let legacy = """
        [{"id":"00000000-0000-0000-0000-000000000001","date":0,"callsign":"EP1AAA","email":"a@example.com","subject":"QSL","status":"Sent"}]
        """
        let decoded = try JSONDecoder().decode([EmailHistoryEntry].self, from: Data(legacy.utf8))
        precondition(decoded[0].kind == nil && decoded[0].countsAsQSL)
        var sked = decoded[0]
        sked.kind = "SKED"
        precondition(!sked.countsAsQSL)
        precondition([sked, decoded[0]].contains(where: \.countsAsQSL))
        precondition(![sked].contains(where: \.countsAsQSL))
        let encoded = try JSONEncoder().encode(sked)
        let restored = try JSONDecoder().decode(EmailHistoryEntry.self, from: encoded)
        precondition(restored.kind == "SKED")
        print("Email history kind regression passed")
    }
}
