// swiftc -parse-as-library Tests/RankGrowthRegression.swift YAAM/{RankGrowthAnalysis,RankHistory,QRZRankAPIContract,QRZRankService}.swift -o /tmp/yaam-rank-growth && /tmp/yaam-rank-growth
import Foundation

@main enum RankGrowthRegression {
    static func main() {
        let now = RankHistoryCalendar.date(for: "2026-10-18")!
        func p(_ day: String, _ rank: Int) -> RankTrendPoint {
            RankTrendPoint(date: RankHistoryCalendar.date(for: day)!, label: day, rank: rank)
        }
        func series(_ call: String, _ own: Bool, _ points: [RankTrendPoint]) -> RankTrendSeries {
            RankTrendSeries(callsign: call, countryIso: nil, isOwner: own, latestRank: points.last?.rank,
                latestGap: nil, latestMovement: nil, latestGapMovement: nil, points: points)
        }
        let own = series("OWNER", true, [p("2026-09-01", 20000), p("2026-10-12", 10000), p("2026-10-17", 9500), p("2026-10-18", 9000)])
        let rival = series("RIVAL", false, [p("2026-10-01", 100000), p("2026-10-12", 25000), p("2026-10-18", 24900)])
        let pairs = RankGrowthAnalysis.comparisons(series: [own, rival], period: .week, now: now)
        precondition(pairs[0].dates.count == 2 && pairs[0].gain == 900 && pairs[0].gap == 15900)
        precondition(pairs[0].owner.first?.rank == 10000 && pairs[0].rival.first?.rank == 25000, "Never compare mismatched baselines")
        precondition(RankGrowthAnalysis.percent(9000, baseline: 10000) == 10)
        precondition(RankGrowthAnalysis.percent(11000, baseline: 10000) == -10)
        precondition(RankGrowthAnalysis.points(own.points, period: .month, now: now).count == 3)
        precondition(RankGrowthAnalysis.points(own.points, period: .all, now: now).count == 4)
        precondition(RankGrowthAnalysis.segmentIDs(pairs[0].owner) == [0, 1], "A missing day breaks the line")
        precondition(RankGrowthAnalysis.segmentIDs([p("2026-10-17", 5), p("2026-10-18", 4)]) == [0, 0])
        let one = RankGrowthAnalysis.comparisons(series: [own, series("NEW", false, [p("2026-10-18", 500)])], period: .month, now: now)[0]
        precondition(one.gain == nil && one.gap == -8500, "One point has a position but no invented growth")
        precondition(RankGrowthAnalysis.improvement([]) == nil && RankGrowthAnalysis.improvement([p("2026-10-18", 5)]) == nil)
        precondition(RankGrowthAnalysis.points([p("2026-10-19", 1), p("2026-10-18", 0)], period: .all, now: now).isEmpty)
        precondition(RankGrowthAnalysis.comparisons(series: [rival], period: .all, now: now).isEmpty)
        let stale = RankGrowthAnalysis.comparisons(series: [own, series("STALE", false, [p("2026-10-12", 11000), p("2026-10-17", 10800)])], period: .week, now: now)[0]
        precondition(stale.dates.last == RankHistoryCalendar.date(for: "2026-10-17") && stale.gain == 300, "Use shared endpoints, not a newer owner observation")
        let intraday = RankTrendPoint(date: now.addingTimeInterval(3600), label: "late", rank: 8)
        let deduped = RankGrowthAnalysis.points([intraday, p("2026-10-18", 10)], period: .week, now: now)
        precondition(deduped.count == 1 && deduped[0].rank == 8 && deduped[0].date == now, "Normalize UTC days and retain the latest observation")
        print("PASS: periods, matched baselines/endpoints, normalized change, missing-day breaks, sparse/stale/future data")
    }
}
