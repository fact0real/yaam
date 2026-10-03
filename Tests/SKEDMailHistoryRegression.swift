import Foundation

@main
struct SKEDMailHistoryRegression {
    static func main() throws {
        let zone = TimeZone(identifier: "Asia/Tehran")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        func date(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
        }
        let oldSchedule = SKEDMailSchedule(start: date(3, 10), end: date(5, 20), timeZone: zone)!
        let sameDaysDifferentHours = SKEDMailSchedule(start: date(4, 8), end: date(6, 18), timeZone: zone)!
        let newDays = SKEDMailSchedule(start: date(6, 10), end: date(8, 20), timeZone: zone)!
        precondition(oldSchedule.overlapsDays(sameDaysDifferentHours))
        precondition(!oldSchedule.overlapsDays(newDays))

        let old = EmailHistoryEntry(id: UUID(), date: date(2, 13), callsign: "EP1AAA",
                                    email: "ep1aaa@example.com", subject: "SKED request", status: "Sent",
                                    kind: "SKED", sked: SKEDMailDetails(recipientName: "Ali", senderCallsign: "W1ABC",
                                        destinationKey: "ir", destinationName: "Iran", body: "Hi Ali,\n73!",
                                        bands: ["20m"], mode: "FT4", schedule: oldSchedule))
        let legacy = EmailHistoryEntry(id: UUID(), date: date(1, 13), callsign: "EP2BBB",
                                       email: "ep2bbb@example.com", subject: "Old SKED", status: "Sent", kind: "SKED")
        let failed = EmailHistoryEntry(id: UUID(), date: date(2, 13), callsign: "EP3CCC",
                                       email: "ep3ccc@example.com", subject: "Failed", status: "Failed", kind: "SKED")
        let entries = [old, legacy, failed]
        precondition(SKEDMailHistory.conflicts(for: "ep1aaa", email: nil, schedule: sameDaysDifferentHours, in: entries).count == 1)
        precondition(SKEDMailHistory.conflicts(for: "EP1AAA", email: nil, schedule: newDays, in: entries).isEmpty)
        precondition(SKEDMailHistory.conflicts(for: "EP1AAA", email: nil, schedule: nil, in: entries).count == 1)
        precondition(SKEDMailHistory.conflicts(for: "EP2BBB", email: nil, schedule: newDays, in: entries).count == 1)
        precondition(SKEDMailHistory.conflicts(for: "EP3CCC", email: nil, schedule: newDays, in: entries).isEmpty)
        precondition(SKEDMailHistory.conflicts(for: "OTHER", email: "EP1AAA@EXAMPLE.COM", schedule: sameDaysDifferentHours, in: entries).count == 1)
        let restored = try JSONDecoder().decode(EmailHistoryEntry.self, from: JSONEncoder().encode(old))
        precondition(restored.sked?.body == "Hi Ali,\n73!")
        precondition(restored.sked?.mode == "FT4")
        precondition(restored.sked?.schedule == oldSchedule)
        var earlierPayload = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        var earlierDetails = earlierPayload["sked"] as! [String: Any]
        earlierDetails.removeValue(forKey: "mode")
        earlierPayload["sked"] = earlierDetails
        let earlierData = try JSONSerialization.data(withJSONObject: earlierPayload)
        let earlierEntry = try JSONDecoder().decode(EmailHistoryEntry.self, from: earlierData)
        precondition(earlierEntry.sked?.mode == nil)
        precondition(earlierEntry.sked?.bands == ["20m"])
        let oldJSON = """
        {"id":"00000000-0000-0000-0000-000000000001","date":0,"callsign":"EP9LEG","email":"legacy@example.com","subject":"Old","status":"Sent","kind":"SKED"}
        """
        let decodedLegacy = try JSONDecoder().decode(EmailHistoryEntry.self, from: Data(oldJSON.utf8))
        precondition(decodedLegacy.sked == nil)
        print("SKED mail history regression passed")
    }
}
