// Run with: swiftc -parse-as-library Tests/TodayActivityComparisonRegression.swift YAAM/TodayActivityComparison.swift -o /tmp/yaam-today-test && /tmp/yaam-today-test
import Foundation

@main
enum TodayActivityComparisonRegression {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tehran")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10, minute: 15))!
        var counter = TodayActivityComparisonCounter(now: now, calendar: calendar)

        counter.include(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9, minute: 0))!)
        counter.include(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 10, minute: 10))!)
        counter.include(calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 10, minute: 14))!)
        counter.include(calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 8, minute: 0))!)
        counter.include(calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 10, minute: 16))!)
        counter.include(calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 8, minute: 0))!)

        let result = counter.result
        precondition(result.todayCount == 2)
        precondition(result.previousDayCounts.count == 7)
        precondition(result.previousDayCounts.reduce(0, +) == 2)
        precondition(abs(result.previousDailyAverage - 2.0 / 7.0) < 0.0001)

        // The previous day's matching hour must remain local across a DST transition.
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let dstNow = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 10, minute: 15))!
        var dstCounter = TodayActivityComparisonCounter(now: dstNow, calendar: calendar)
        dstCounter.include(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 10, minute: 14))!)
        dstCounter.include(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 10, minute: 16))!)
        precondition(dstCounter.result.previousDayCounts.first == 1)
        print("Today activity comparison regression passed")
    }
}
