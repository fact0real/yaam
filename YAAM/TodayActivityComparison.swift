import Foundation

struct TodayActivityComparison: Sendable {
    let todayCount: Int
    let previousDayCounts: [Int]

    var previousDailyAverage: Double {
        guard !previousDayCounts.isEmpty else { return 0 }
        return Double(previousDayCounts.reduce(0, +)) / Double(previousDayCounts.count)
    }

    var differenceFromAverage: Double {
        Double(todayCount) - previousDailyAverage
    }
}

/// Counts today's contacts and the previous seven calendar days up to the same local clock time.
/// Calendar dates are used so daylight saving changes do not shift the comparison hour.
struct TodayActivityComparisonCounter {
    private let windows: [DateInterval]
    private var counts: [Int]

    init(now: Date, calendar: Calendar, previousDays: Int = 7) {
        let startOfToday = calendar.startOfDay(for: now)
        let clock = calendar.dateComponents([.hour, .minute, .second], from: now)
        var intervals = [DateInterval(start: startOfToday, end: now.addingTimeInterval(1))]

        for offset in 1...max(1, previousDays) {
            guard let start = calendar.date(byAdding: .day, value: -offset, to: startOfToday),
                  let endOfDay = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
            let sameClockTime = calendar.date(
                bySettingHour: clock.hour ?? 0,
                minute: clock.minute ?? 0,
                second: clock.second ?? 0,
                of: start,
                matchingPolicy: .nextTime,
                repeatedTimePolicy: .first,
                direction: .forward
            ) ?? endOfDay
            intervals.append(DateInterval(start: start, end: min(sameClockTime.addingTimeInterval(1), endOfDay)))
        }

        windows = intervals
        counts = Array(repeating: 0, count: intervals.count)
    }

    mutating func include(_ date: Date) {
        for index in windows.indices where windows[index].contains(date) {
            counts[index] += 1
            break
        }
    }

    var result: TodayActivityComparison {
        TodayActivityComparison(todayCount: counts.first ?? 0, previousDayCounts: Array(counts.dropFirst()))
    }
}
