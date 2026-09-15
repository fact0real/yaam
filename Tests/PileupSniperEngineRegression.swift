//
//  PileupSniperEngineRegression.swift
//  YAAM Tests
//
//  Comprehensive regression test suite for Pileup Sniper & Split QSX Frequency Hunter:
//  - Comment NLP parsing (UP, DN, QSX, WKD, SIMPLEX)
//  - Multi-station hit point aggregation with time decay
//  - Stepping UP / DOWN progression modeling
//  - Clustering sweet spot calculation with QRM avoidance offset
//  - Bandmap Engine VFO-B arming and split activation
//  - Call Intelligence Engine report integration
//

import Foundation
import SwiftUI
#if canImport(YAAM)
@testable import YAAM
#endif

@main
struct PileupSniperEngineRegression {
    static func main() async {
        print("🚀 Starting Pileup Sniper & Split QSX Hunter Regression Test Suite...")

        testQSXCommentParserVariations()
        testSteppingUpPatternRecognition()
        testSteppingDownPatternRecognition()
        testClusteringSweetSpot()
        testWideSpreadHunting()
        await testBandmapIntegration()
        await testCallIntelligenceReportIntegration()

        print("🎉 ALL Pileup Sniper & Split QSX Tests PASSED successfully!")
    }

    // MARK: - 1. Comment Parser Tests
    private static func testQSXCommentParserVariations() {
        print("🧪 Testing QSXCommentParser regex and shorthand variations...")
        let baseKHz = 14020.0

        // Test UP 5
        let p1 = QSXCommentParser.parse(comment: "UP 5", dxBaseFreqKHz: baseKHz)
        assert(p1.isSplit, "Expected isSplit true for 'UP 5'")
        assert(p1.exactFrequencyKHz == 14025.0, "Expected 14025.0, got \(String(describing: p1.exactFrequencyKHz))")

        // Test UP 5-10
        let p2 = QSXCommentParser.parse(comment: "UP 5-10", dxBaseFreqKHz: baseKHz)
        assert(p2.isSplit, "Expected isSplit true for 'UP 5-10'")
        assert(p2.lowOffsetKHz == 5.0 && p2.highOffsetKHz == 10.0, "Expected 5..10 range")

        // Test UP 2 TO 8
        let p3 = QSXCommentParser.parse(comment: "599+ up 2 to 8 khz", dxBaseFreqKHz: baseKHz)
        assert(p3.isSplit, "Expected isSplit true for 'up 2 to 8 khz'")
        assert(p3.lowOffsetKHz == 2.0 && p3.highOffsetKHz == 8.0, "Expected 2..8 range")

        // Test UP 2/5
        let p4 = QSXCommentParser.parse(comment: "up 2/5", dxBaseFreqKHz: baseKHz)
        assert(p4.isSplit, "Expected isSplit true for 'up 2/5'")
        assert(p4.lowOffsetKHz == 2.0 && p4.highOffsetKHz == 5.0, "Expected 2..5 range")

        // Test DN 2
        let p5 = QSXCommentParser.parse(comment: "listening down 2", dxBaseFreqKHz: baseKHz)
        assert(p5.isSplit, "Expected isSplit true for 'down 2'")
        assert(p5.exactFrequencyKHz == 14018.0, "Expected 14018.0, got \(String(describing: p5.exactFrequencyKHz))")

        // Test QSX direct kHz
        let p6 = QSXCommentParser.parse(comment: "qsx 14025.4 loud", dxBaseFreqKHz: baseKHz)
        assert(p6.isSplit, "Expected isSplit true for 'qsx 14025.4'")
        assert(p6.exactFrequencyKHz == 14025.4, "Expected 14025.4, got \(String(describing: p6.exactFrequencyKHz))")

        // Test QSX MHz notation
        let p7 = QSXCommentParser.parse(comment: "QSX 14.026", dxBaseFreqKHz: baseKHz)
        assert(p7.isSplit, "Expected isSplit true for 'QSX 14.026'")
        assert(p7.exactFrequencyKHz == 14026.0, "Expected 14026.0, got \(String(describing: p7.exactFrequencyKHz))")

        // Test WKD shorthand
        let p8 = QSXCommentParser.parse(comment: "wkd +3.5 1st call", dxBaseFreqKHz: baseKHz)
        assert(p8.isSplit, "Expected isSplit true for 'wkd +3.5'")
        assert(p8.exactFrequencyKHz == 14023.5, "Expected 14023.5, got \(String(describing: p8.exactFrequencyKHz))")

        // Test SIMPLEX reset
        let p9 = QSXCommentParser.parse(comment: "now simplex!!", dxBaseFreqKHz: baseKHz)
        assert(!p9.isSplit && p9.isSimplex, "Expected isSimplex true for 'now simplex'")

        print("   ✓ All 9 comment syntax variations correctly parsed.")
    }

    // MARK: - 2. Stepping UP Pattern Recognition
    private static func testSteppingUpPatternRecognition() {
        print("🧪 Testing Stepping UP trajectory prediction...")
        let baseKHz = 14020.0
        let now = Date()

        let spots = [
            makeSpot(call: "3B8/W1AW", freq: baseKHz, comment: "wkd +1.5", date: now.addingTimeInterval(-600)),
            makeSpot(call: "3B8/W1AW", freq: baseKHz, comment: "wkd +3.0", date: now.addingTimeInterval(-300)),
            makeSpot(call: "3B8/W1AW", freq: baseKHz, comment: "wkd +4.5", date: now.addingTimeInterval(-60))
        ]

        let solution = PileupSniperEngine.analyze(
            dxCallsign: "3B8/W1AW",
            dxRxFrequencyKHz: baseKHz,
            clusterSpots: spots
        )

        assert(solution != nil, "Expected non-nil solution")
        let sol = solution!
        assert(sol.isSplit, "Expected split active")
        assert(sol.pattern == .steppingUp, "Expected pattern .steppingUp, got \(sol.pattern)")
        assert(sol.recommendedTxKHz > 14024.5, "Expected target above 14024.5, got \(sol.recommendedTxKHz)")
        assert(sol.confidence >= 0.75, "Expected high confidence, got \(sol.confidence)")

        print("   ✓ Stepping UP trajectory verified: Target \(sol.frequencyFormattedMHz) (\(sol.offsetSignFormatted)), Advice: '\(sol.tacticalAdvice)'")
    }

    // MARK: - 3. Stepping DOWN Pattern Recognition
    private static func testSteppingDownPatternRecognition() {
        print("🧪 Testing Stepping DOWN trajectory prediction...")
        let baseKHz = 14020.0
        let now = Date()

        let spots = [
            makeSpot(call: "FT4JA", freq: baseKHz, comment: "wkd +8.0", date: now.addingTimeInterval(-600)),
            makeSpot(call: "FT4JA", freq: baseKHz, comment: "wkd +6.0", date: now.addingTimeInterval(-300)),
            makeSpot(call: "FT4JA", freq: baseKHz, comment: "wkd +4.0", date: now.addingTimeInterval(-60))
        ]

        let solution = PileupSniperEngine.analyze(
            dxCallsign: "FT4JA",
            dxRxFrequencyKHz: baseKHz,
            clusterSpots: spots
        )

        assert(solution != nil, "Expected non-nil solution")
        let sol = solution!
        assert(sol.pattern == .steppingDown, "Expected pattern .steppingDown, got \(sol.pattern)")
        assert(sol.recommendedTxKHz < 14024.0, "Expected target below 14024.0, got \(sol.recommendedTxKHz)")

        print("   ✓ Stepping DOWN trajectory verified: Target \(sol.frequencyFormattedMHz) (\(sol.offsetSignFormatted))")
    }

    // MARK: - 4. Clustering Sweet Spot
    private static func testClusteringSweetSpot() {
        print("🧪 Testing Clustering Sweet Spot detection...")
        let baseKHz = 14020.0
        let now = Date()

        let spots = [
            makeSpot(call: "VK9XY", freq: baseKHz, comment: "wkd 14025.2", date: now.addingTimeInterval(-400)),
            makeSpot(call: "VK9XY", freq: baseKHz, comment: "wkd 14025.3", date: now.addingTimeInterval(-200)),
            makeSpot(call: "VK9XY", freq: baseKHz, comment: "wkd 14025.1", date: now.addingTimeInterval(-50))
        ]

        let solution = PileupSniperEngine.analyze(
            dxCallsign: "VK9XY",
            dxRxFrequencyKHz: baseKHz,
            clusterSpots: spots
        )

        assert(solution != nil, "Expected non-nil solution")
        let sol = solution!
        assert(sol.pattern == .clusteringCenter, "Expected pattern .clusteringCenter, got \(sol.pattern)")
        assert(abs(sol.recommendedTxKHz - 14025.35) < 0.2, "Expected target near ~14025.35 kHz (+150Hz), got \(sol.recommendedTxKHz)")

        print("   ✓ Sweet Spot cluster verified: Target \(sol.frequencyFormattedMHz), positioned +150Hz to dodge co-channel QRM.")
    }

    // MARK: - 5. Wide Spread Hunting
    private static func testWideSpreadHunting() {
        print("🧪 Testing Wide Spread Hunting estimation...")
        let baseKHz = 14020.0

        let spots = [
            makeSpot(call: "VP8PJ", freq: baseKHz, comment: "up 5-10", date: Date())
        ]

        let solution = PileupSniperEngine.analyze(
            dxCallsign: "VP8PJ",
            dxRxFrequencyKHz: baseKHz,
            clusterSpots: spots
        )

        assert(solution != nil, "Expected non-nil solution")
        let sol = solution!
        assert(sol.pattern == .wideSpread, "Expected pattern .wideSpread, got \(sol.pattern)")
        assert(sol.recommendedTxKHz >= 14027.0 && sol.recommendedTxKHz <= 14030.0, "Expected target in upper 65% of spread, got \(sol.recommendedTxKHz)")

        print("   ✓ Wide spread verified: Listening \(sol.splitRangeKHz?.description ?? "") -> Sniper recommendation: \(sol.frequencyFormattedMHz)")
    }

    // MARK: - 6. Bandmap Engine Integration
    @MainActor
    private static func testBandmapIntegration() async {
        print("🧪 Testing BandmapEngine VFO-B arming and split activation...")
        let bandmap = BandmapEngine.shared
        bandmap.vfoAKHz = 14020.0
        bandmap.isSplitActive = false

        let solution = PileupSniperSolution(
            dxCallsign: "KH1/KH7Z",
            dxRxFrequencyKHz: 14020.0,
            isSplit: true,
            splitRangeKHz: 14025.0...14030.0,
            splitSpreadOffsetKHz: 5.0...10.0,
            recommendedTxKHz: 14026.5,
            recommendedOffsetKHz: 6.5,
            confidence: 0.90,
            pattern: .steppingUp,
            recentHits: [],
            tacticalAdvice: "Target 14026.5 kHz",
            summaryTag: "UP 5–10k"
        )

        bandmap.applySniperSolution(solution)

        assert(bandmap.isSplitActive, "Bandmap should be in split mode")
        assert(bandmap.vfoBKHz == 14026.5, "VFO-B should be 14026.5, got \(bandmap.vfoBKHz)")
        assert(bandmap.vfoAKHz == 14020.0, "VFO-A (RX) must remain untouched at 14020.0")
        assert(bandmap.splitOffsetKHz == 6.5, "Split offset should be 6.5 kHz")

        print("   ✓ Bandmap VFO-B successfully armed to 14026.5 kHz with VFO-A preserved at 14020.0 kHz.")
    }

    // MARK: - 7. Call Intelligence Report Integration
    @MainActor
    private static func testCallIntelligenceReportIntegration() async {
        print("🧪 Testing CallIntelligenceEngine report integration...")
        let spots = [
            makeSpot(call: "ZL7/G3TXF", freq: 14022.0, comment: "UP 5", date: Date())
        ]

        let report = CallIntelligenceEngine.analyze(
            callsign: "ZL7/G3TXF",
            band: "20m",
            mode: "CW",
            records: [],
            homeCoordinate: nil,
            lookupResult: nil,
            clusterSpots: spots
        )

        guard let sniper = report.pileupSniper else {
            fatalError("Expected non-nil pileupSniper in CallIntelligenceReport")
        }

        assert(sniper.isSplit, "Expected isSplit true in report")
        assert(sniper.recommendedTxKHz == 14027.0, "Expected recommended 14027.0 (14022 + 5), got \(sniper.recommendedTxKHz)")

        print("   ✓ CallIntelligenceReport successfully integrated with PileupSniper: \(sniper.summaryTag)")
    }

    // MARK: - Helpers
    private static func makeSpot(call: String, freq: Double, comment: String, date: Date) -> DXSpot {
        DXSpot(
            id: UUID().uuidString,
            callsign: call,
            spotter: "W3LPL",
            frequencyKHz: freq,
            band: "20m",
            mode: "CW",
            submode: "",
            comment: comment,
            grid: "FN20",
            spottedAt: date,
            lastSeenAt: date,
            reportCount: 1
        )
    }
}
