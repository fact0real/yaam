//
//  RankEnrichment.swift
//  YAAM
//

import Foundation

nonisolated struct QRZRankDailyQuota: Codable, Equatable, Sendable {
    static let maximumRequests = 1_440

    private(set) var dayKey: String
    private(set) var attemptedRequests: Int
    private(set) var successfulRequests: Int

    init(
        date: Date = Date(),
        calendar: Calendar = .current,
        attemptedRequests: Int = 0,
        successfulRequests: Int = 0
    ) {
        dayKey = Self.dayKey(for: date, calendar: calendar)
        self.attemptedRequests = max(0, min(Self.maximumRequests, attemptedRequests))
        self.successfulRequests = max(0, min(self.attemptedRequests, successfulRequests))
    }

    var remainingRequests: Int {
        max(0, Self.maximumRequests - attemptedRequests)
    }

    mutating func resetIfNeeded(date: Date = Date(), calendar: Calendar = .current) {
        guard dayKey != Self.dayKey(for: date, calendar: calendar) else { return }
        dayKey = Self.dayKey(for: date, calendar: calendar)
        attemptedRequests = 0
        successfulRequests = 0
    }

    mutating func reserveRequest(date: Date = Date(), calendar: Calendar = .current) -> Bool {
        resetIfNeeded(date: date, calendar: calendar)
        guard attemptedRequests < Self.maximumRequests else { return false }
        attemptedRequests += 1
        return true
    }

    mutating func recordSuccess() {
        successfulRequests = min(attemptedRequests, successfulRequests + 1)
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }
}

nonisolated enum QRZRankBackfillPlanner {
    private static let rankFields = ["RANK_QSO", "RANK_BAND", "RANK_DXCC"]

    private struct CallsignSummary {
        var knownRankFields = Set<String>()
        var wasCheckedToday = false
        var latestQSOKey = ""
    }

    static func candidateCallsigns<Record>(
        from records: [Record],
        checkedDay: String,
        limit: Int,
        value: (Record, String) -> String
    ) -> [String] {
        guard limit > 0 else { return [] }

        var summaries: [String: CallsignSummary] = [:]
        for record in records {
            let callsign = value(record, "CALL")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard !callsign.isEmpty else { continue }

            var summary = summaries[callsign, default: CallsignSummary()]
            for field in rankFields where !value(record, field).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                summary.knownRankFields.insert(field)
            }
            if value(record, "APP_YAAM_RANK_CHECKED").trimmingCharacters(in: .whitespacesAndNewlines) == checkedDay {
                summary.wasCheckedToday = true
            }
            let qsoKey = value(record, "QSO_DATE") + value(record, "TIME_ON")
            if qsoKey > summary.latestQSOKey {
                summary.latestQSOKey = qsoKey
            }
            summaries[callsign] = summary
        }

        return summaries
            .filter { _, summary in
                !summary.wasCheckedToday && summary.knownRankFields.count < rankFields.count
            }
            .sorted { lhs, rhs in
                if lhs.value.latestQSOKey != rhs.value.latestQSOKey {
                    return lhs.value.latestQSOKey > rhs.value.latestQSOKey
                }
                return lhs.key < rhs.key
            }
            .prefix(limit)
            .map(\.key)
    }
}
