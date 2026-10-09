//
//  GregorianDateRegression.swift
//  YAAM Tests
//
//  Dates and times that are kept in the log or handed to other programs are Gregorian with ASCII
//  digits, whatever calendar and digits the Mac is set to (YAAM/GregorianDate.swift). Dates shown on
//  screen keep following the Mac's settings.
//
//  Run it with the Mac's settings given as launch arguments, for example (from the checkout):
//
//    swiftc -parse-as-library Tests/GregorianDateRegression.swift YAAM/GregorianDate.swift \
//        YAAM/RankEnrichment.swift YAAM/ShackClockEngine.swift YAAM/TodayActivityComparison.swift -o gdr
//    TZ=Asia/Tehran ./gdr -Part behaviour -AppleLocale fa_IR -ExpectCalendar persian -ExpectDigits arabext
//    TZ=Asia/Tehran ./gdr -Part behaviour -AppleLocale en_IR@calendar=persian -ExpectCalendar persian -ExpectDigits latn
//    ./gdr -Part source          (reads YAAM/*.swift from the current directory)
//
//  -Part behaviour runs the code that can be compiled alone. -Part source reads the sites that cannot
//  (AppState, the views, the servers) and checks that they use GregorianDate. Without -Part both run.
//  -ExpectCalendar and -ExpectDigits only make the test stop if the setting was not applied.
//

import Foundation

@main
@MainActor
struct GregorianDateRegression {
    static var checks = 0
    static var failures = 0

    static func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        checks += 1
        if ok {
            print("PASS \(name)")
        } else {
            failures += 1
            print("DIFFERS \(name)\(detail().isEmpty ? "" : ": " + detail())")
        }
    }

    static func info(_ text: String) { print("INFO \(text)") }

    /// A byte-for-byte search. `String.contains` can find ASCII digits in text with the digits of another script
    /// when the text comes from a formatter, so it is not used for checks on digits.
    static func hasText(_ text: String, _ needle: String) -> Bool {
        let haystack = Array(text.utf8), wanted = Array(needle.utf8)
        guard haystack.count >= wanted.count else { return false }
        for start in 0...(haystack.count - wanted.count) where Array(haystack[start..<(start + wanted.count)]) == wanted { return true }
        return false
    }

    // 8 October 2026, 12:05:09 UTC (15:35:09 in Tehran)
    static let instant = Date(timeIntervalSince1970: 1_791_461_109)
    static let utc = TimeZone(secondsFromGMT: 0)!

    static func main() {
        let defaults = UserDefaults.standard
        let part = defaults.string(forKey: "Part") ?? "all"
        print("GregorianDateRegression, part: \(part)")
        if part != "source" { reportSetting() }
        if part == "all" || part == "behaviour" { behaviour() }
        if part == "all" || part == "source" { sources() }
        print("GregorianDateRegression: \(checks) checks, \(failures) differ")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - The Mac's settings of this run

    static func reportSetting() {
        let digits = Locale.current.numberingSystem.identifier
        print("setting: locale \(Locale.current.identifier), calendar \(Calendar.current.identifier), digits \(digits), time zone \(TimeZone.current.identifier)")
        let defaults = UserDefaults.standard
        if let want = defaults.string(forKey: "ExpectCalendar") {
            check("\(Calendar.current.identifier)" == want, "setting applied: Calendar.current is \(want)", "it is \(Calendar.current.identifier)")
        }
        if let want = defaults.string(forKey: "ExpectDigits") {
            check(digits == want, "setting applied: the Mac's digits are \(want)", "they are \(digits)")
        }
        let plain = DateFormatter()
        plain.timeZone = utc
        plain.dateFormat = "yyyyMMdd"
        info("a DateFormatter with only dateFormat yyyyMMdd gives \(plain.string(from: instant)) for 8 October 2026 in this setting")
    }

    // MARK: - Code that can be compiled alone

    /// The date and time of `instant` in the Mac's time zone, written without Calendar.current or the Mac's locale.
    static func localASCII() -> (date: String, time: String, day: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: instant)
        let y = c.year ?? 0, mo = c.month ?? 0, d = c.day ?? 0
        return (String(format: "%04d%02d%02d", y, mo, d),
                String(format: "%02d%02d%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0),
                String(format: "%04d-%02d-%02d", y, mo, d))
    }

    static func behaviour() {
        let local = localASCII()
        let inTehran = TimeZone.current.identifier == "Asia/Tehran"

        // The shared formatter, with the formats and time zones the changed sites use.
        let utcZone: TimeZone? = utc
        let formats: [(use: String, format: String, expected: String)] = [
            ("QSO_DATE filter, today in UTC", "yyyyMMdd", "20261008"),
            ("rate matrix: QSO_DATE and TIME_ON", "yyyyMMdd HHmmss", "20261008 120509"),
            ("LoTW and QRZ since-date", "yyyy-MM-dd", "2026-10-08"),
            ("cluster line time", "HHmm", "1205"),
            ("calendar file, all day", "yyyyMMdd", "20261008"),
            ("calendar file, with time", "yyyyMMdd'T'HHmmss'Z'", "20261008T120509Z"),
        ]
        for item in formats {
            let text = GregorianDate.formatter(item.format, timeZone: utcZone).string(from: instant)
            check(text == item.expected, "UTC \(item.use): \(item.format) gives \(item.expected)", "got \(text)")
        }
        let parsed = GregorianDate.formatter("yyyyMMdd HHmmss", timeZone: utcZone).date(from: "20261008 120509")
        check(parsed == instant, "UTC: 20261008 120509 is read back as the same instant", "got \(String(describing: parsed?.timeIntervalSince1970))")

        // Local time zone: the formatter keeps the Mac's time zone, as before.
        let localDate = GregorianDate.formatter("yyyyMMdd").string(from: instant)
        let localTime = GregorianDate.formatter("HHmmss").string(from: instant)
        check(localDate == local.date, "local: yyyyMMdd gives \(local.date)", "got \(localDate)")
        check(localTime == local.time, "local: HHmmss gives \(local.time)", "got \(localTime)")
        if inTehran {
            check(localDate == "20261008" && localTime == "153509", "local (Asia/Tehran): 20261008 153509")
        }
        check(GregorianDate.formatter("HH").timeZone.identifier == TimeZone.current.identifier, "local: the time zone is the Mac's, not changed")
        let given = TimeZone(identifier: "Pacific/Auckland")!
        check(GregorianDate.formatter("HH", timeZone: given).timeZone.identifier == given.identifier, "a given time zone is kept")
        check(GregorianDate.formatter("HHmmss", timeZone: given).string(from: instant) == "010509", "a given time zone is used: Pacific/Auckland 010509 on 9 October")

        // Calendar arithmetic.
        let calendar = GregorianDate.localCalendar
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        check(calendar.identifier == .gregorian, "localCalendar is Gregorian")
        let partsText = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        check(partsText == local.day, "localCalendar: the Mac's day of 8 October 2026, 12:05 UTC is \(local.day) in the Gregorian calendar", "got \(partsText)")
        if inTehran {
            check(partsText == "2026-10-08", "localCalendar (Asia/Tehran): 2026-10-08")
        }
        check(calendar.timeZone.identifier == Calendar.current.timeZone.identifier, "localCalendar keeps the time zone of Calendar.current")
        check(calendar.component(.hour, from: instant) == Calendar.current.component(.hour, from: instant), "localCalendar and Calendar.current give the same hour")
        let current = Calendar.current.dateComponents([.year, .month, .day], from: instant)
        info("Calendar.current gives \(current.year ?? 0)-\(current.month ?? 0)-\(current.day ?? 0) for the same instant")

        // Real code from YAAM/RankEnrichment.swift: the day key kept with the daily request count.
        check(QRZRankDailyQuota.dayKey(for: instant) == local.day, "RankEnrichment: day key of 8 October 2026 is \(local.day)", "got \(QRZRankDailyQuota.dayKey(for: instant))")
        let stored = "{\"dayKey\":\"\(local.day)\",\"attemptedRequests\":5,\"successfulRequests\":3}"
        if var quota = try? JSONDecoder().decode(QRZRankDailyQuota.self, from: Data(stored.utf8)) {
            quota.resetIfNeeded(date: instant)
            check(quota.attemptedRequests == 5 && quota.successfulRequests == 3, "RankEnrichment: a count stored under \(local.day) is the same day, not reset", "attempted \(quota.attemptedRequests), successful \(quota.successfulRequests)")
            quota.recordAttempt(date: instant)
            check(quota.attemptedRequests == 6, "RankEnrichment: the next attempt adds to the stored count", "attempted \(quota.attemptedRequests)")
        } else {
            check(false, "RankEnrichment: the stored count can be read")
        }
        // A count written by an earlier version under the Mac's own calendar is not recognised as today's: it restarts once.
        let earlier = "{\"dayKey\":\"1405-07-16\",\"attemptedRequests\":5,\"successfulRequests\":3}"
        if var quota = try? JSONDecoder().decode(QRZRankDailyQuota.self, from: Data(earlier.utf8)) {
            quota.resetIfNeeded(date: instant)
            info("a count stored under the Persian-calendar day 1405-07-16 by an earlier version reads attempted \(quota.attemptedRequests) after the next check (5 before it)")
        }
        let fresh = QRZRankDailyQuota(date: instant)
        let quotaEncoder = JSONEncoder()
        quotaEncoder.outputFormatting = [.sortedKeys]
        let encoded = (try? quotaEncoder.encode(fresh)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        check(hasText(encoded, "\"dayKey\":\"\(local.day)\""), "RankEnrichment: a new count is stored under \(local.day)", "got \(encoded)")

        // A formatter that is only shown on screen (YAAM/ShackClockEngine.swift, not changed) keeps following the Mac.
        let clock = ShackClockEngine.shared
        let shown = clock.localDateFormatted
        let mac = DateFormatter()
        mac.locale = Locale.current
        mac.timeZone = TimeZone.current
        mac.dateFormat = "EEE, dd MMM yyyy"
        check(shown == mac.string(from: clock.currentDate).uppercased(), "SCREEN: the shack clock date is written with the Mac's calendar and digits")
        let gregorian = GregorianDate.formatter("EEE, dd MMM yyyy").string(from: clock.currentDate).uppercased()
        if Calendar.current.identifier == .gregorian && Locale.current.numberingSystem.identifier == "latn" {
            info("this setting is Gregorian with Latin digits, so the screen text and the Gregorian text are the same kind")
        } else {
            check(shown != gregorian, "SCREEN: the shack clock date is not the Gregorian ASCII text in this setting", "both read \(shown)")
        }
        info("shack clock date on screen: \(shown); the same day, Gregorian ASCII: \(gregorian)")

        // Things that did not depend on the setting before and must not start to.
        let iso = ISO8601DateFormatter()
        check(iso.string(from: instant) == "2026-10-08T12:05:09Z", "control: ISO8601DateFormatter writes 2026-10-08T12:05:09Z")
        check(iso.date(from: "2026-10-08T12:05:09Z") == instant, "control: ISO8601DateFormatter reads it back")
        struct Wrapper: Codable { var when: Date }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = (try? encoder.encode(Wrapper(when: instant))).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        check(hasText(json, "2026-10-08T12:05:09Z"), "control: JSON dates (.iso8601) are 2026-10-08T12:05:09Z", "got \(json)")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        check((try? decoder.decode(Wrapper.self, from: Data(json.utf8)))?.when == instant, "control: JSON dates (.iso8601) are read back")
        check(instant.formatted(.iso8601.year().month().day()) == "2026-10-08", "control: Date.formatted(.iso8601) gives 2026-10-08")
        check(String(format: "%.6f %03d %+d", 14.074, 7, 3) == "14.074000 007 +3", "control: String(format:) writes ASCII digits")
        info("a Date written into a string with \\(date) reads \(instant) in this setting")
        let posix = DateFormatter()
        posix.locale = Locale(identifier: "en_US_POSIX")
        posix.timeZone = utc
        posix.dateFormat = "yyyyMMdd HHmmss"
        check(posix.string(from: instant) == "20261008 120509", "control: the en_US_POSIX formatters already in YAAM give 20261008 120509")

        // Calendar.current calls that are not changed: same result in every calendar.
        let gregorianLocal = GregorianDate.localCalendar
        check(Calendar.current.startOfDay(for: instant) == gregorianLocal.startOfDay(for: instant), "control: startOfDay is the same in both calendars")
        check(Calendar.current.component(.minute, from: instant) == gregorianLocal.component(.minute, from: instant), "control: the minute is the same in both calendars")
        var viaCurrent = TodayActivityComparisonCounter(now: instant, calendar: .current)
        var viaGregorian = TodayActivityComparisonCounter(now: instant, calendar: gregorianLocal)
        for step in 0..<400 {
            let when = instant.addingTimeInterval(-Double(step) * 1_800)
            viaCurrent.include(when)
            viaGregorian.include(when)
        }
        check(viaCurrent.result.todayCount == viaGregorian.result.todayCount && viaCurrent.result.previousDayCounts == viaGregorian.result.previousDayCounts, "control: the today-versus-previous-days counter gives the same counts in both calendars")
    }

    // MARK: - Sites that cannot be compiled alone

    struct Site {
        let name: String
        let file: String
        let anchor: String      // text of the line the window is cut around (first line that contains it)
        let before: Int
        let after: Int
        let expected: [String]  // each must appear in the window
        var forbidden = ["DateFormatter()", "Calendar.current"]   // none may appear in the window
        var count = 1           // how many lines in the file contain the anchor (all are checked)
        var folder = "YAAM"     // the folder of the file
    }

    static func sources() {
        let utcZone = "timeZone: TimeZone(secondsFromGMT: 0)"
        let sites: [Site] = [
            Site(name: "AppState.adifDateFormatter (QSO dates, checked-on marks, QSLSDATE)",
                 file: "AppState.swift", anchor: "static let adifDateFormatter", before: 0, after: 1,
                 expected: ["GregorianDate.formatter(\"yyyyMMdd\")"]),
            Site(name: "AppState date filter compared with QSO_DATE",
                 file: "AppState.swift", anchor: "let startStr = formatter.string(from: filterCriteria.startDate)", before: 4, after: 0,
                 expected: ["GregorianDate.formatter(\"yyyyMMdd\", \(utcZone))"]),
            Site(name: "AppState today in UTC compared with QSO_DATE",
                 file: "AppState.swift", anchor: "private static let todayUTCFormatter", before: 0, after: 2,
                 expected: ["GregorianDate.formatter(\"yyyyMMdd\", \(utcZone))"]),
            Site(name: "AppState since-date sent to LoTW and QRZ",
                 file: "AppState.swift", anchor: "let lotwSinceDateString", before: 4, after: 0,
                 expected: ["GregorianDate.formatter(\"yyyy-MM-dd\", \(utcZone))"]),
            Site(name: "ContestRateMatrixEngine reads QSO_DATE and TIME_ON",
                 file: "ContestRateMatrixEngine.swift", anchor: "private static let adifDateFormatter", before: 0, after: 2,
                 expected: ["GregorianDate.formatter(\"yyyyMMdd HHmmss\", \(utcZone))"]),
            Site(name: "LeaderboardView today in UTC compared with QSO_DATE",
                 file: "LeaderboardView.swift", anchor: "let todayUTC", before: 0, after: 4,
                 expected: ["GregorianDate.formatter(\"yyyyMMdd\", \(utcZone))"]),
            Site(name: "LeaderboardView today local compared with QSO_DATE",
                 file: "LeaderboardView.swift", anchor: "let todayLocal", before: 0, after: 4,
                 expected: ["GregorianDate.formatter(\"yyyyMMdd\", timeZone: TimeZone.current)"]),
            Site(name: "LocalClusterServer time in the cluster line",
                 file: "LocalClusterServer.swift", anchor: "let timeStr = formatter.string(from: spot.lastSeenAt)", before: 3, after: 0,
                 expected: ["GregorianDate.formatter(\"HHmm\", \(utcZone))"]),
            Site(name: "MacCalendarService dates in the calendar file",
                 file: "MacCalendarService.swift", anchor: "let startStr = dateFormatter.string(from: startDate)", before: 6, after: 0,
                 expected: ["GregorianDate.formatter(", "isAllDay ? \"yyyyMMdd\" : \"yyyyMMdd'T'HHmmss'Z'\"", utcZone]),
            Site(name: "ContestRateMatrixRegressionTests writes QSO_DATE and TIME_ON for the rate matrix",
                 file: "ContestRateMatrixRegressionTests.swift", anchor: "let d1 = formatter.string(from: now.addingTimeInterval(-120))", before: 4, after: 0,
                 expected: ["GregorianDate.formatter(\"yyyyMMdd HHmmss\", \(utcZone))"], folder: "Tests"),
        ]
        var cache: [String: [String]] = [:]
        for site in sites {
            let path = "\(site.folder)/\(site.file)"
            if cache[path] == nil {
                let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                cache[path] = text.components(separatedBy: "\n")
            }
            let lines = cache[path] ?? []
            let found = lines.indices.filter { lines[$0].contains(site.anchor) }
            guard found.count >= site.count else {
                check(false, "\(site.name): site found in \(path)", "text found \(found.count) times, expected \(site.count): \(site.anchor)")
                continue
            }
            for index in found.prefix(site.count) {
                let lower = max(0, index - site.before)
                let upper = min(lines.count - 1, index + site.after)
                let window = lines[lower...upper].map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
                let missing = site.expected.filter { !window.contains($0) }
                let plain = site.forbidden.contains { window.contains($0) }
                check(missing.isEmpty && !plain, "\(site.name) uses GregorianDate (\(path):\(index + 1))",
                      "the site reads: \(window.prefix(160))")
            }
        }
    }
}
