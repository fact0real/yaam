import Foundation

/// A logged UTC contact, independent of the Station table's filters and display timezone.
nonisolated struct RecentQSOContact: Equatable, Sendable {
    let fields: [String: String]
    let timestamp: Date
    var expiresAt: Date { timestamp.addingTimeInterval(15 * 60) }

    func isRecent(at now: Date) -> Bool {
        timestamp <= now && now <= expiresAt
    }

    static func latest(in records: [[String: String]]) -> Self? {
        var latest: Self?
        for fields in records {
            guard let date = timestamp(fields), latest == nil || date > latest!.timestamp else { continue }
            latest = Self(fields: fields, timestamp: date)
        }
        return latest
    }

    static func timestamp(_ fields: [String: String]) -> Date? {
        let day = fields["QSO_DATE", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        let time = fields["TIME_ON", default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        guard day.count == 8, day.allSatisfy(\.isNumber),
              [4, 6].contains(time.count), time.allSatisfy(\.isNumber),
              let year = Int(day.prefix(4)), let month = Int(day.dropFirst(4).prefix(2)),
              let date = Int(day.suffix(2)), let hour = Int(time.prefix(2)),
              let minute = Int(time.dropFirst(2).prefix(2)) else { return nil }
        let second = time.count == 6 ? Int(time.suffix(2))! : 0
        guard (1...12).contains(month), (1...31).contains(date),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: date, hour: hour, minute: minute, second: second)
        guard let result = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: result) == components else { return nil }
        return result
    }
}
