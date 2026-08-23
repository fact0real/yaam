import Foundation

struct QSORecordModel: Sendable {
    let id: UUID
    var index: Int
    var fields: [String: String]

    init(index: Int, id: UUID = UUID(), fields: [String: String]) {
        self.index = index
        self.id = id
        self.fields = fields
    }

    subscript(_ key: String) -> String {
        fields[key] ?? fields[key.uppercased()] ?? ""
    }

    var uniqueKey: String {
        QSOIdentity.exactKey(fields: fields)
    }
}

struct MergeSummary: Sendable {
    let added: Int
    let updated: Int
    let skipped: Int
}

enum ImportReviewAnalyzer {
    static func mergeUpdate(
        incoming: [String: String],
        into existing: [String: String]
    ) -> [String: String] {
        var merged = existing
        for (key, value) in incoming {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if (merged[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !trimmed.isEmpty {
                merged[key] = value
            }
        }
        return merged
    }
}

@main
enum SDRControlMergeRegression {
    static func main() {
        let originalID = UUID()
        let sparse = QSORecordModel(
            index: 1,
            id: originalID,
            fields: exactFields(name: "", email: "", confirmed: false)
        )
        let rich = QSORecordModel(
            index: 2,
            fields: exactFields(name: "Alice Example", email: "alice@example.test", confirmed: true)
        )

        let consolidated = SDRControlMergeEngine.merge(
            localRecords: [sparse, rich],
            incomingFields: []
        )
        precondition(consolidated.records.count == 1)
        precondition(consolidated.removedDuplicates == 1)
        precondition(consolidated.records[0].id == originalID)
        precondition(consolidated.records[0]["NAME"] == "Alice Example")
        precondition(consolidated.records[0]["EMAIL"] == "alice@example.test")
        precondition(consolidated.records[0]["LOTW_QSL_RCVD"] == "Y")

        var complementary = exactFields(name: "", email: "second@example.test", confirmed: false)
        complementary["GRIDSQUARE"] = "JN61WL"
        let incomingOnly = SDRControlMergeEngine.merge(
            localRecords: [],
            incomingFields: [
                exactFields(name: "Second Operator", email: "", confirmed: true),
                complementary
            ]
        )
        precondition(incomingOnly.records.count == 1)
        precondition(incomingOnly.summary.added == 1)
        precondition(incomingOnly.summary.updated == 1)
        precondition(incomingOnly.records[0]["NAME"] == "Second Operator")
        precondition(incomingOnly.records[0]["EMAIL"] == "second@example.test")
        precondition(incomingOnly.records[0]["GRIDSQUARE"] == "JN61WL")

        var later = exactFields(name: "Later QSO", email: "", confirmed: false)
        later["TIME_ON"] = "120500"
        let distinctTimes = SDRControlMergeEngine.merge(
            localRecords: [],
            incomingFields: [exactFields(name: "First QSO", email: "", confirmed: false), later]
        )
        precondition(distinctTimes.records.count == 2)
        precondition(distinctTimes.summary.added == 2)

        print("SDR-Control duplicate merge regression passed.")
    }

    private static func exactFields(
        name: String,
        email: String,
        confirmed: Bool
    ) -> [String: String] {
        [
            "CALL": "IZ0ZZZ",
            "QSO_DATE": "20260823",
            "TIME_ON": "120000",
            "BAND": "20M",
            "MODE": "MFSK",
            "SUBMODE": "FT8",
            "FREQ": "14.074",
            "NAME": name,
            "EMAIL": email,
            "LOTW_QSL_RCVD": confirmed ? "Y" : "N"
        ]
    }
}
