// swiftc -parse-as-library Tests/IncomingContactReviewRegression.swift YAAM/IncomingContactReview.swift YAAM/QSOIdentity.swift -o /tmp/yaam-incoming-review && /tmp/yaam-incoming-review
import Foundation

@main
struct IncomingContactReviewRegression {
    static func main() throws {
        var review = IncomingContactReview()
        precondition(review.time.isEmpty && review.band.isEmpty && review.mode.isEmpty)
        precondition(review.problem != nil)
        review.call = "w1aw"; review.station = "EP2AES"; review.date = "20261020"
        review.time = "1435"; review.band = "20m"; review.mode = "FT8"; review.evidence = "Operator reply checked against notebook"
        precondition(review.problem != nil, "No upload readiness before explicit verification")
        review.verified = true
        precondition(review.problem == nil)
        for time in ["", "240000", "126000", "125960", "120", "12:35", "１２３４"] {
            var bad = review; bad.time = time; precondition(bad.problem != nil, time)
        }
        for date in ["20260229", "20261301", "20260431", "", "2026-10-20"] {
            var bad = review; bad.date = date; precondition(bad.problem != nil, date)
        }
        var leap = review; leap.date = "20240229"; precondition(leap.problem == nil)
        var noBand = review; noBand.band = ""; precondition(noBand.problem != nil)
        var noMode = review; noMode.mode = ""; precondition(noMode.problem != nil)
        var noEvidence = review; noEvidence.evidence = "  "; precondition(noEvidence.problem != nil)
        var selfContact = review; selfContact.call = review.station; precondition(selfContact.problem != nil)
        var ft4 = review; ft4.mode = "FT4"
        precondition(ft4.fields["MODE"] == "MFSK" && ft4.fields["SUBMODE"] == "FT4")
        var fields = review.fields; fields["TIME_ON"] = "143500"
        precondition(QSOIdentity.exactKey(fields: fields) == QSOIdentity.exactKey(fields: review.fields))
        fields["MODE"] = "SSB"
        precondition(QSOIdentity.exactKey(fields: fields) != QSOIdentity.exactKey(fields: review.fields), "Call/date alone cannot prove a match")
        let roundtrip = try JSONDecoder().decode(IncomingContactReview.self, from: JSONEncoder().encode(review))
        precondition(roundtrip == review)
        var savedFields = review.fields
        savedFields["BAND"] = "20m"; savedFields["MODE"] = "ft8"; savedFields["TIME_ON"] = "143500"
        savedFields["APP_YAAM_INCOMING_EVIDENCE"] = review.evidence
        precondition(review.matchesSavedContact(savedFields), "Legacy spelling and equivalent timestamp precision must not prevent resuming a saved contact")
        var dirty = review; dirty.mode = "CW"; precondition(!dirty.matchesSavedContact(savedFields))
        dirty = review; dirty.time = "14:35"; precondition(!dirty.matchesSavedContact(savedFields))
        dirty = review; dirty.evidence = "Different reply"; precondition(!dirty.matchesSavedContact(savedFields))
        dirty = review; dirty.qrzAlreadyLogged = true; precondition(!dirty.matchesSavedContact(savedFields))
        var knownQRZ = review; knownQRZ.qrzAlreadyLogged = true
        precondition(knownQRZ.fields["APP_YAAM_QRZ_VERIFIED_PRESENT"] == "Y")
        precondition(knownQRZ.fields["QRZLOG_QSL_RCVD"] == nil)
        var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(review)) as! [String: Any]
        legacyJSON.removeValue(forKey: "qrzAlreadyLogged")
        let legacyDraft = try JSONDecoder().decode(IncomingContactReview.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
        precondition(legacyDraft.qrzAlreadyLogged == nil && legacyDraft.fields["APP_YAAM_QRZ_VERIFIED_PRESENT"] == nil)
        precondition(review.fields.keys.allSatisfy { !$0.contains("QSL") && !$0.contains("UPLOAD") })
        print("Incoming contact review regression passed")
    }
}
