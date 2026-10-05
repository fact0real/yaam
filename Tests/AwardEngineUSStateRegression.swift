import Foundation
#if STANDALONE_AWARDS
// Run alone:  swiftc -D STANDALONE_AWARDS -parse-as-library Tests/AwardEngineUSStateRegression.swift YAAM/AwardEngine.swift YAAM/GridLocator.swift -o /tmp/aws && /tmp/aws
// QSORecordModel lives in AppState.swift, which does not build on its own. This stand-in has
// only the members AwardEngine reads (fields, subscript, isConfirmed, uniqueKey).
nonisolated struct QSORecordModel: Sendable {
    var fields: [String: String]
    init(fields: [String: String]) { self.fields = fields }
    subscript(key: String) -> String { fields[key] ?? "" }
    var isConfirmed: Bool { fields["LOTW_QSL_RCVD"] == "Y" }
    var uniqueKey: String { (fields["CALL"] ?? "") + (fields["QSO_DATE"] ?? "") + (fields["TIME_ON"] ?? "") }
}
#else
@testable import YAAM
#endif

@main
struct AwardEngineUSStateRegression {
    static func main() {
        testStateNeedsUSEntity()
        testMissingDXCCStillCounts()
        testEngineWASIgnoresForeignStates()
        print("AwardEngine US state regression tests passed.")
    }

    private static func counts(_ state: String, dxcc: String) -> Bool {
        AwardEngine.countsAsUSState(["STATE": state, "DXCC": dxcc])
    }

    private static func testStateNeedsUSEntity() {
        precondition(counts("CA", dxcc: "291"), "California with DXCC 291 (USA) counts")
        precondition(!counts("CA", dxcc: "281"), "CA with DXCC 281 (Spain) does not count")
        precondition(!counts("MT", dxcc: "108"), "MT with DXCC 108 (Brazil) does not count")
        precondition(!counts("ON", dxcc: "1"), "ON with DXCC 1 (Canada) does not count")
        precondition(!counts("TX", dxcc: "281"), "TX with DXCC 281 (Spain) does not count")
        precondition(counts("HI", dxcc: "110"), "Hawaii has its own DXCC entity (110) and counts")
        precondition(counts("AK", dxcc: "6"), "Alaska has its own DXCC entity (6) and counts")
        precondition(counts(" tx ", dxcc: " 291 "), "case and surrounding spaces are ignored")
        precondition(!counts("", dxcc: "291"), "a US QSO without STATE does not count")
    }

    private static func testMissingDXCCStillCounts() {
        // The FT8, digital-mode and multi-rig QSO builders (AppStateRadioContestFeatures,
        // MultiRigFT8Hub) write no DXCC, so their QSOs have none. "0" and "UNKNOWN" also mean
        // "no entity" (AwardEngine.cleanEntity, the Awards hub). The quick-log DXCC box is free
        // text, so a value that is not a number ("ABC", "USA") is treated as unknown too.
        precondition(AwardEngine.countsAsUSState(["STATE": "TX"]), "TX without a DXCC field counts")
        precondition(counts("TX", dxcc: ""), "TX with an empty DXCC counts")
        precondition(counts("TX", dxcc: "0"), "TX with DXCC 0 (no entity) counts")
        precondition(counts("TX", dxcc: "UNKNOWN"), "TX with DXCC UNKNOWN counts")
        precondition(counts("TX", dxcc: "unknown"), "TX with DXCC unknown (lower case) counts")
        precondition(counts("TX", dxcc: "ABC"), "TX with a non-numeric DXCC (ABC) counts")
        precondition(counts("TX", dxcc: "USA"), "TX with a non-numeric DXCC (USA) counts")
        precondition(!counts("ZZ", dxcc: ""), "an unknown state code does not count, whatever the DXCC")
        precondition(!counts("ZZ", dxcc: "0"), "an unknown state code does not count with DXCC 0 either")
        precondition(!counts("ZZ", dxcc: "ABC"), "an unknown state code does not count with a non-numeric DXCC either")
    }

    private static func testEngineWASIgnoresForeignStates() {
        // CALL is only a label here: WAS reads STATE and DXCC.
        func qso(_ state: String, dxcc: String, confirmed: Bool = true) -> QSORecordModel {
            var fields = ["CALL": "K1ABC", "STATE": state, "DXCC": dxcc, "BAND": "20m"]
            if confirmed { fields["LOTW_QSL_RCVD"] = "Y" }
            return QSORecordModel(fields: fields)
        }
        func was(_ records: [QSORecordModel]) -> AwardProgress {
            guard let item = AwardEngine.evaluate(records: records, claims: []).first(where: { $0.id == "was-mixed" }) else {
                preconditionFailure("was-mixed award missing")
            }
            return item
        }

        let foreign = [
            qso("CA", dxcc: "281"),
            qso("MT", dxcc: "108"),
            qso("PA", dxcc: "108"),
            qso("ON", dxcc: "1")
        ]
        let none = was(foreign)
        precondition(none.worked == 0 && none.confirmed == 0,
                     "4 non-US QSOs must give WAS worked 0 / confirmed 0, got \(none.worked) / \(none.confirmed)")

        let us = foreign + [
            qso("CA", dxcc: "291"),
            qso("HI", dxcc: "110"),
            qso("AK", dxcc: "6"),
            qso("TX", dxcc: ""),
            qso("NY", dxcc: "291", confirmed: false)
        ]
        let some = was(us)
        precondition(some.confirmed == 4, "only the 4 confirmed US QSOs count, got confirmed \(some.confirmed)")
        precondition(some.worked == 5, "the unconfirmed NY QSO is worked only, got worked \(some.worked)")

        // DXCC 0, UNKNOWN or a value that is not a number mean "unknown entity", so these four
        // US QSOs keep counting, as before.
        let unknownEntity = was([qso("OH", dxcc: "0"), qso("OR", dxcc: "UNKNOWN"),
                                 qso("TX", dxcc: "ABC"), qso("FL", dxcc: "USA")])
        precondition(unknownEntity.worked == 4 && unknownEntity.confirmed == 4,
                     "OH/0, OR/UNKNOWN, TX/ABC and FL/USA count, got \(unknownEntity.worked) / \(unknownEntity.confirmed)")
    }
}
