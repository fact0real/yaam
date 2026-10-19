import Foundation
@main struct QRZEmailTemplateRegression {
    static func main() {
        for raw in [nil, "", "0", "-12", "N/A", "unknown 100", "#0", "12.5"] as [String?] {
            precondition(QSLMailPolicy.rank(raw) == nil, "Invalid rank was presented: \(raw ?? "nil")")
        }
        precondition(QSLMailPolicy.rank(" #12,345 ") == "#12,345")
        let absent = QSLMailPolicy.rankParagraph(qso: nil, band: nil, dxcc: nil)
        precondition(!absent.contains("#"))
        let partial = QSLMailPolicy.rankParagraph(qso: "123", band: "N/A", dxcc: nil)
        precondition(partial.contains("#123") && !partial.contains("Bands World Rank"))
        precondition(QSLMailPolicy.requiresCard(template: "QRZ Rank Congratulations & QSL"))
        precondition(QSLMailPolicy.requiresCard(template: "QSL Card Delivery"))
        precondition(!QSLMailPolicy.requiresCard(template: "QRZ Incoming Details"))
        precondition(QSLMailPolicy.rankSubject(hasRanks: true, bandMention: " on 17M", station: "TEST").contains("QRZ Rank Congratulations"))
        precondition(!QSLMailPolicy.rankSubject(hasRanks: false, bandMention: "", station: "TEST").contains("Congratulations"))
        print("QSL mail policy: passed")
    }
}
