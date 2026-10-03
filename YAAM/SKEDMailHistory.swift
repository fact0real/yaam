import Foundation

/// Calendar days are the days the operator selected in YAAM's local-time picker.
/// The UTC description is the exact wording included in the delivered email.
struct SKEDMailSchedule: Codable, Hashable, Sendable {
    let firstDay: String
    let lastDay: String
    let timeZoneID: String
    let localStart: String
    let localEnd: String
    let utcDescription: String

    init?(start: Date, end: Date, timeZone: TimeZone = .current) {
        guard SKEDMailTemplate.isValidDailyWindow(start: start, end: end, timeZone: timeZone) else { return nil }
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.calendar = Calendar(identifier: .gregorian)
        dayFormatter.timeZone = timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let clockFormatter = DateFormatter()
        clockFormatter.locale = Locale(identifier: "en_US_POSIX")
        clockFormatter.calendar = Calendar(identifier: .gregorian)
        clockFormatter.timeZone = timeZone
        clockFormatter.dateFormat = "HH:mm"
        firstDay = dayFormatter.string(from: start)
        lastDay = dayFormatter.string(from: end)
        timeZoneID = timeZone.identifier
        localStart = clockFormatter.string(from: start)
        localEnd = clockFormatter.string(from: end)
        utcDescription = SKEDMailTemplate.utcWindow(start: start, end: end, timeZone: timeZone)
    }

    var shortDescription: String {
        let days = firstDay == lastDay ? firstDay : "\(firstDay)–\(lastDay)"
        return "\(days) · \(localStart)–\(localEnd) \(timeZoneID)"
    }

    func overlapsDays(_ other: Self) -> Bool {
        guard let left = coveredCalendarDays, let right = other.coveredCalendarDays else { return true }
        return left.start < right.end && right.start < left.end
    }

    private var coveredCalendarDays: DateInterval? {
        guard let zone = TimeZone(identifier: timeZoneID) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        func day(_ value: String) -> Date? {
            let parts = value.split(separator: "-")
            guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
                  let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
            let components = DateComponents(year: year, month: month, day: day)
            guard let date = calendar.date(from: components),
                  calendar.dateComponents([.year, .month, .day], from: date) == components else { return nil }
            return date
        }
        guard let first = day(firstDay), let last = day(lastDay), first <= last,
              let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: last) else { return nil }
        return DateInterval(start: first, end: exclusiveEnd)
    }
}

struct SKEDMailDetails: Codable, Hashable, Sendable {
    let recipientName: String?
    let senderCallsign: String
    let destinationKey: String
    let destinationName: String
    let body: String
    let bands: [String]
    var mode: String? = nil
    let schedule: SKEDMailSchedule?
}

enum SKEDMailHistory {
    static func successfulEntries(_ entries: [EmailHistoryEntry]) -> [EmailHistoryEntry] {
        entries.filter { $0.kind?.uppercased() == "SKED" && $0.status == "Sent" }
            .sorted { $0.date > $1.date }
    }

    static func entries(for callsign: String, email: String?, in entries: [EmailHistoryEntry]) -> [EmailHistoryEntry] {
        let call = callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let address = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return successfulEntries(entries).filter {
            $0.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == call ||
                (!address.isEmpty && $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == address)
        }
    }

    /// A send with no recorded dates, including legacy SKED mail, needs explicit review.
    static func conflicts(for callsign: String, email: String?, schedule: SKEDMailSchedule?,
                          in entries: [EmailHistoryEntry]) -> [EmailHistoryEntry] {
        self.entries(for: callsign, email: email, in: entries).filter { previous in
            guard let schedule, let earlier = previous.sked?.schedule else { return true }
            return schedule.overlapsDays(earlier)
        }
    }
}
