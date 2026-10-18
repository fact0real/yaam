// swiftc -parse-as-library Tests/RankHistoryRegression.swift YAAM/RankHistory.swift YAAM/QRZRankAPIContract.swift YAAM/QRZRankService.swift -o /tmp/yaam-rank-history-test && /tmp/yaam-rank-history-test
import Foundation

@main enum RankHistoryRegression {
    static func main() throws {
        let now = ISO8601DateFormatter().date(from: "2026-10-18T12:00:00Z")!
        precondition(RankHistoryCalendar.date(for: "2026-02-30") == nil)
        precondition(RankHistoryCalendar.date(for: "2026-10-9") == nil)
        func snapshot(_ day: String, _ call: String, _ rank: Int) -> QRZRankHistorySnapshot {
            QRZRankHistorySnapshot(date: RankHistoryCalendar.date(for: day)!, response:
                QRZRankResponse(bid: nil, callsign: call, country_iso: "ir", country_name: nil,
                                rank_band: nil, rank_countries: nil, rank_qso: String(rank),
                                score_band: nil, score_countries: nil, score_qso: nil))
        }
        let oct8 = snapshot("2026-10-08", "EP2AES", 10_000)
        let oct17 = snapshot("2026-10-17", "EP2AES", 9_500)
        let oct18 = snapshot("2026-10-18", "EP2AES", 9_000)
        func series(_ records: [QRZRankHistorySnapshot], now date: Date? = nil) -> [RankTrendSeries] {
            RankHistoryAnalysis.series(snapshots: records, owner: "EP2AES", tracked: ["EP2LMA"], metric: .qso, now: date ?? now)
        }
        let gap = series([oct8, oct18])
        precondition(gap[0].latestMovement == nil, "Ten-day change must not be called today's change")
        precondition(RankHistoryCalendar.timeline(points: gap[0].points, now: now).count == 11, "Missing days retain calendar width")
        precondition(RankChartMode.dailyChange.value(for: gap[0].points[1], in: gap[0].points, baseline: 10_000) == nil)
        precondition(RankChartMode.actualRank.value(for: gap[0].points[1], in: gap[0].points, baseline: 10_000) == -9_000)
        precondition(RankChartMode.sinceBaseline.value(for: gap[0].points[1], in: gap[0].points, baseline: 10_000) == 1_000)
        let owner = series([oct18, oct8, oct17, oct17])[0]
        precondition(owner.points.count == 3 && owner.latestMovement == 500, "Order and duplicate input must not change daily results")
        precondition(series([oct17, oct18], now: now.addingTimeInterval(86400))[0].latestMovement == nil, "Stale observations are not today's movement")
        let rival8 = snapshot("2026-10-08", "EP2LMA", 11_000)
        let rival17 = snapshot("2026-10-17", "EP2LMA", 10_500)
        let rival18 = snapshot("2026-10-18", "EP2LMA", 10_600)
        let consecutive = series([oct17, oct18, rival17, rival18])
        precondition(consecutive[1].latestMovement == -100)
        precondition(consecutive[1].latestGap == 1600 && consecutive[1].latestGapMovement == 600)
        precondition(series([oct8, oct18, rival8, rival18])[1].latestGapMovement == nil)
        precondition(series([oct17, rival17, rival18])[1].latestGap == nil, "Never show an older matched gap as the latest gap")
        precondition(series([oct17, oct18, rival17])[1].latestGap == nil, "A stale rival must not be compared with an older owner observation as if current")
        let invalid = series([snapshot("2026-10-18", "EP2AES", 0)])[0]
        precondition(invalid.points.isEmpty)
        let encoded = try JSONEncoder().encode([oct8, oct17])
        let decoded = try JSONDecoder().decode([QRZRankHistorySnapshot].self, from: encoded)
        precondition(decoded.map(\.day) == ["2026-10-08", "2026-10-17"])
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("yaam-rank-test-\(UUID().uuidString)/history.json")
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        RankHistoryCache.save(try JSONEncoder().encode([oct8]), to: cache)
        RankHistoryCache.save(encoded, to: cache)
        let deadline = Date().addingTimeInterval(3)
        while RankHistoryCache.load(from: cache).count != 2 && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        precondition(RankHistoryCache.load(from: cache).map(\.day) == decoded.map(\.day), "Queued writes must preserve save order")
        try Data("truncated".utf8).write(to: cache)
        precondition(RankHistoryCache.load(from: cache).isEmpty, "A corrupt file must allow preference recovery")
        let legacy = Data("[{\"date\":813456000,\"callsign\":\"EP2AES\",\"qsoRank\":10000}]".utf8)
        let old = try JSONDecoder().decode([QRZRankHistorySnapshot].self, from: legacy)
        precondition(old.count == 1 && old[0].qsoRank == 10000 && old[0].recordedDay != nil)
        precondition(RankHistoryCalendar.timeline(points: [RankTrendPoint(date: now.addingTimeInterval(-200 * 86400), label: "", rank: 1)], now: now).count == 90)
        let body = Data("""
        {"time_zone":"UTC","watchlist":["EP2AES"],"snapshots":[{"observed_at":"2026-10-18T00:15:30.123456Z","data":{"callsign":"EP2AES","rank_qso":9056}}]}
        """.utf8)
        let envelope = try JSONDecoder().decode(QRZRankHistoryEnvelope.self, from: body)
        let fetched = try envelope.validatedSnapshots(expected: ["EP2AES"], now: now)
        precondition(fetched[0].day == "2026-10-18" && fetched[0].qsoRank == 9056)
        do { _ = try envelope.validatedSnapshots(expected: ["G0JHC"], now: now); preconditionFailure("Mismatched watchlist accepted") } catch {}
        do { _ = try envelope.validatedSnapshots(expected: ["EP2AES"], now: now.addingTimeInterval(-86400)); preconditionFailure("Future observation accepted") } catch {}
        let request = try QRZRankAPIContract.makeRankHistoryRequest(callsigns: [" ep2aes ", "EP2AES", "G0JHC"], token: "qrz_test-only", userAgent: "test")
        precondition(request.httpMethod == "PUT" && request.url?.path == "/api/v1/rank-history")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer qrz_test-only")
        precondition(request.url?.query == nil)
        let sent = try JSONDecoder().decode([String: [String]].self, from: request.httpBody!)
        precondition(sent["callsigns"] == ["EP2AES", "G0JHC"])
        let read = try QRZRankAPIContract.makeRankHistoryRequest(token: "qrz_test-only", userAgent: "test")
        precondition(read.httpMethod == "GET" && read.httpBody == nil)
        do { _ = try QRZRankAPIContract.makeRankHistoryRequest(callsigns: ["../secret"], token: "test", userAgent: "test"); preconditionFailure("Invalid call accepted") } catch {}
        do { _ = try QRZRankAPIContract.makeRankHistoryRequest(token: "", userAgent: "test"); preconditionFailure("Empty token accepted") } catch {}
        print("Rank history regression passed: gaps, calendar, daily deltas, stale comparisons, migration and API boundaries")
    }
}
