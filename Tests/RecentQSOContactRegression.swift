// swiftc -parse-as-library Tests/RecentQSOContactRegression.swift YAAM/RecentQSOContact.swift -o /tmp/yaam-recent-qso-test
import Foundation

@main struct RecentQSOContactRegression {
    static func main() {
        let fields = ["QSO_DATE": "20261018", "TIME_ON": "205930", "CALL": "K2TY"]
        guard let contact = RecentQSOContact.latest(in: [fields]) else { fatalError("Valid UTC contact rejected") }
        assert(contact.isRecent(at: contact.timestamp))
        assert(contact.isRecent(at: contact.timestamp.addingTimeInterval(899.999)))
        assert(contact.isRecent(at: contact.timestamp.addingTimeInterval(900)))
        assert(!contact.isRecent(at: contact.timestamp.addingTimeInterval(900.001)))
        assert(!contact.isRecent(at: contact.timestamp.addingTimeInterval(-0.001)))
        assert(RecentQSOContact.latest(in: []) == nil)
        let newer = ["QSO_DATE": "20261018", "TIME_ON": "210000", "CALL": "G0JHC"]
        assert(RecentQSOContact.latest(in: [newer, fields])?.fields["CALL"] == "G0JHC")
        assert(RecentQSOContact.latest(in: [fields, newer])?.fields["CALL"] == "G0JHC")
        let midnight = RecentQSOContact.timestamp(["QSO_DATE": "20261019", "TIME_ON": "000000"])!
        let previousDay = RecentQSOContact.latest(in: [["QSO_DATE": "20261018", "TIME_ON": "235900"]])!
        assert(previousDay.isRecent(at: midnight.addingTimeInterval(14 * 60)))
        assert(!previousDay.isRecent(at: midnight.addingTimeInterval(14 * 60 + 1)))
        assert(RecentQSOContact.timestamp(["QSO_DATE": "20261018", "TIME_ON": "2059"]) != nil)
        for (day, time) in [("20260230", "120000"), ("20261018", "240000"), ("20261018", "206000"),
                            ("20261018", "205960"), ("20261018", ""), ("20261018", "20:59"), ("bad", "205930")] {
            assert(RecentQSOContact.timestamp(["QSO_DATE": day, "TIME_ON": time]) == nil)
        }
        print("Recent QSO UTC parsing, newest selection, midnight, future and 15-minute boundary checks passed")
    }
}
