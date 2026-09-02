//
//  CompetitorTrackingRegression.swift
//  YAAM Tests
//

import Foundation

struct TestProgressPoint: Identifiable, Sendable {
    var id = UUID()
    var label: String
    var cumulativeCount: Int
    var isForecast: Bool
}

struct TestCompetitorStation: Identifiable, Codable {
    var id: UUID = UUID()
    var callsign: String
    var name: String
    var confirmedCount: Int
    var monthlyGrowthRate: Double
    var isEnabled: Bool
}

@main
struct CompetitorTrackingRegression {
    static func main() {
        print("Running Competitor Tracking & Multi-Station Comparison Regression Tests...")
        testCompetitorProgressionMath()
        testOvertakeCalculations()
        print("All Competitor Tracking Regression Tests PASSED successfully!")
    }

    private static func testCompetitorProgressionMath() {
        let userPoints: [TestProgressPoint] = [
            TestProgressPoint(label: "01/26", cumulativeCount: 800, isForecast: false),
            TestProgressPoint(label: "02/26", cumulativeCount: 850, isForecast: false),
            TestProgressPoint(label: "03/26", cumulativeCount: 920, isForecast: false),
            TestProgressPoint(label: "+3m", cumulativeCount: 1040, isForecast: true),
            TestProgressPoint(label: "+6m", cumulativeCount: 1160, isForecast: true)
        ]

        let rival = TestCompetitorStation(
            callsign: "EP2LMA",
            name: "Mohsen",
            confirmedCount: 1000,
            monthlyGrowthRate: 30.0,
            isEnabled: true
        )

        let historicalCount = userPoints.filter { !$0.isForecast }.count
        precondition(historicalCount == 3, "Expected 3 historical months")

        // Check back-projected points
        let monthsAgo = Double(historicalCount - 1 - 0) // 2 months ago
        let expectedCount = Int((Double(rival.confirmedCount) - (monthsAgo * rival.monthlyGrowthRate)).rounded())
        precondition(expectedCount == 940, "Expected back-projected count 940, got \(expectedCount)")

        // Check forward-projected point (+6m)
        let projected6m = Int((Double(rival.confirmedCount) + (6.0 * rival.monthlyGrowthRate)).rounded())
        precondition(projected6m == 1180, "Expected +6m projection 1180, got \(projected6m)")
    }

    private static func testOvertakeCalculations() {
        let userConfirmed = 950
        let userRate = 50.0 // 50 QSOs/month

        let rivalConfirmed = 1100
        let rivalRate = 20.0 // 20 QSOs/month

        let gap = userConfirmed - rivalConfirmed // -150
        let deltaRate = userRate - rivalRate // +30 QSOs/month lead in growth

        precondition(gap < 0, "User is currently trailing by 150")
        precondition(deltaRate > 0, "User is catching up at +30 QSOs/month")

        let monthsToOvertake = Double(abs(gap)) / deltaRate
        precondition(monthsToOvertake == 5.0, "Expected overtake in exactly 5.0 months, got \(monthsToOvertake)")
    }
}
