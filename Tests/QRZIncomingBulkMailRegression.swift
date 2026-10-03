import Foundation

@main
struct QRZIncomingBulkMailRegression {
    static func main() {
        let grouped = QRZIncomingBulkMail.group([
            .init(id: "a", callsign: "K1ABC", qsoDate: "20261003"),
            .init(id: "b", callsign: "k1abc", qsoDate: "2026-10-02"),
            .init(id: "c", callsign: "W1XYZ", qsoDate: "")
        ])
        precondition(grouped.count == 2)
        precondition(grouped[0].requestIDs == ["a", "b"])
        precondition(grouped[0].qsoDates == ["2026-10-02", "2026-10-03"])
        let body = QRZIncomingBulkMail.render(QRZIncomingBulkMail.defaultBody,
                                              recipient: grouped[0], name: "Alex", myCallsign: "EP2AES")
        precondition(body.contains("Hi Alex (K1ABC)"))
        precondition(body.contains("2026-10-02, 2026-10-03"))
        precondition(body.contains("Best 73,\nEP2AES"))
        precondition(!QRZIncomingBulkMail.hasUnresolvedFields(body))
        let otherBody = QRZIncomingBulkMail.render(QRZIncomingBulkMail.defaultBody,
                                                   recipient: grouped[1], name: "Pat", myCallsign: "EP2AES")
        precondition(otherBody.contains("Hi Pat (W1XYZ)"))
        precondition(!otherBody.contains("2026-10-02"))
        precondition(QRZIncomingBulkMail.hasUnresolvedFields("Hello {unknown}"))
        precondition(QRZIncomingBulkMail.isUsableEmail("operator@example.com"))
        precondition(!QRZIncomingBulkMail.isUsableEmail("a@example.com;b@example.com"))
        print("QRZ Incoming bulk mail regression passed")
    }
}
