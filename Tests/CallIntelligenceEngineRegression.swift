//
//  CallIntelligenceEngineRegression.swift
//  YAAM Tests
//
//  Regression test suite for Call Intelligence Engine:
//  - ATNO (All-Time New One) determination
//  - New DXCC entity and unconfirmed DXCC detection
//  - Band and Mode slot need computation
//  - Band Matrix row generation
//  - LoTW and QSL confirmation likelihood
//  - Solar illumination and Great-Circle direction telemetry
//

import Foundation
@testable import YAAM

@main
@MainActor
struct CallIntelligenceEngineRegression {
    static func main() async {
        print("🚀 Starting Call Intelligence Engine Regression Test Suite...")
        testATNOAndNewDXCC()
        testBandAndModeNeeds()
        testBandMatrixSlots()
        testSolarAndBearingTelemetry()
        testLoTWAndQSLLikelihood()
        print("🎉 ALL Call Intelligence Engine Tests PASSED successfully!")
    }

    // MARK: - 1. ATNO and New DXCC Determination
    private static func testATNOAndNewDXCC() {
        print("🧪 Testing ATNO and New DXCC Determination...")

        let records: [QSORecordModel] = [
            QSORecordModel(index: 1, fields: [
                "CALL": "JA1ABC", "BAND": "20m", "MODE": "CW", "DXCC": "339", "QSL_RCVD": "Y"
            ]),
            QSORecordModel(index: 2, fields: [
                "CALL": "DL1ABC", "BAND": "40m", "MODE": "SSB", "DXCC": "230", "QSL_RCVD": "N"
            ])
        ]

        let homeCoord = GeoCoordinate(latitude: 35.6892, longitude: 51.3890) // Tehran

        // Case A: Completely new entity (e.g. VK3XYZ - Australia)
        let vkReport = CallIntelligenceEngine.analyze(
            callsign: "VK3XYZ",
            band: "20m",
            mode: "CW",
            records: records,
            homeCoordinate: homeCoord,
            lookupResult: nil
        )

        assert(vkReport.isATNO, "VK3XYZ should be ATNO")
        assert(vkReport.isNewDXCC, "Australia should be New DXCC")
        assert(vkReport.badges.contains(where: { $0.type == .newDXCC }), "Must have NEW_DXCC badge")

        // Case B: Existing callsign (JA1ABC)
        let jaReport = CallIntelligenceEngine.analyze(
            callsign: "JA1ABC",
            band: "20m",
            mode: "CW",
            records: records,
            homeCoordinate: homeCoord,
            lookupResult: nil
        )

        assert(!jaReport.isATNO, "JA1ABC is already worked, should not be ATNO")
        assert(!jaReport.isNewDXCC, "Japan is already worked, should not be New DXCC")
        assert(jaReport.isDXCCConfirmed, "Japan is confirmed")

        // Case C: Unconfirmed entity (DL1ABC worked on 40m without confirmation)
        let dlReport = CallIntelligenceEngine.analyze(
            callsign: "DL2XYZ",
            band: "40m",
            mode: "SSB",
            records: records,
            homeCoordinate: homeCoord,
            lookupResult: nil
        )

        assert(dlReport.isATNO, "DL2XYZ is ATNO for this call")
        assert(!dlReport.isNewDXCC, "Germany is not New DXCC")
        assert(dlReport.isDXCCUnconfirmed, "Germany is worked but unconfirmed")
        assert(dlReport.badges.contains(where: { $0.type == .unconfirmedDXCC }), "Must have UNCONFIRMED DXCC badge")

        print("  ✓ ATNO and DXCC logic verified.")
    }

    // MARK: - 2. Band and Mode Needs
    private static func testBandAndModeNeeds() {
        print("🧪 Testing Band and Mode Needs Calculation...")

        let records: [QSORecordModel] = [
            QSORecordModel(index: 1, fields: [
                "CALL": "JA1ABC", "BAND": "20m", "MODE": "CW", "DXCC": "339", "QSL_RCVD": "Y"
            ])
        ]

        let homeCoord = GeoCoordinate(latitude: 35.6892, longitude: 51.3890)

        // JA on 20m CW -> worked and confirmed
        let reportSame = CallIntelligenceEngine.analyze(
            callsign: "JA2DEF",
            band: "20m",
            mode: "CW",
            records: records,
            homeCoordinate: homeCoord,
            lookupResult: nil
        )
        assert(!reportSame.isNewOnBand, "Japan is already worked on 20m")
        assert(!reportSame.isNewOnMode, "Japan is already worked on CW")

        // JA on 15m CW -> New Band for Japan!
        let reportNewBand = CallIntelligenceEngine.analyze(
            callsign: "JA2DEF",
            band: "15m",
            mode: "CW",
            records: records,
            homeCoordinate: homeCoord,
            lookupResult: nil
        )
        assert(reportNewBand.isNewOnBand, "Japan should be New on 15m")
        assert(reportNewBand.badges.contains(where: { $0.type == .newBand }), "Must contain NEW_BAND badge")

        // JA on 20m SSB -> New Mode for Japan!
        let reportNewMode = CallIntelligenceEngine.analyze(
            callsign: "JA2DEF",
            band: "20m",
            mode: "SSB",
            records: records,
            homeCoordinate: homeCoord,
            lookupResult: nil
        )
        assert(reportNewMode.isNewOnMode, "Japan should be New on SSB")
        assert(reportNewMode.badges.contains(where: { $0.type == .newMode }), "Must contain NEW_MODE badge")

        print("  ✓ Band and Mode needs verified.")
    }

    // MARK: - 3. Band Matrix Slots
    private static func testBandMatrixSlots() {
        print("🧪 Testing Band Matrix Rows...")

        let records: [QSORecordModel] = [
            QSORecordModel(index: 1, fields: [
                "CALL": "W1AW", "BAND": "20m", "MODE": "CW", "DXCC": "291", "QSL_RCVD": "Y"
            ]),
            QSORecordModel(index: 2, fields: [
                "CALL": "W1AW", "BAND": "40m", "MODE": "SSB", "DXCC": "291", "QSL_RCVD": "N"
            ])
        ]

        let report = CallIntelligenceEngine.analyze(
            callsign: "W1AW",
            band: "20m",
            mode: "CW",
            records: records,
            homeCoordinate: nil,
            lookupResult: nil
        )

        let row20m = report.bandRows.first { $0.band == "20m" }
        assert(row20m != nil, "Row for 20m must exist")
        assert(row20m?.isCurrent == true, "20m must be marked current")
        assert(row20m?.cwStatus == .confirmed, "20m CW must be confirmed")

        let row40m = report.bandRows.first { $0.band == "40m" }
        assert(row40m?.ssbStatus == .worked, "40m SSB must be worked (unconfirmed)")

        let row10m = report.bandRows.first { $0.band == "10m" }
        assert(row10m?.cwStatus == .unworked, "10m CW must be unworked")

        print("  ✓ Band Matrix rows verified.")
    }

    // MARK: - 4. Solar and Bearing Telemetry
    private static func testSolarAndBearingTelemetry() {
        print("🧪 Testing Solar Illumination and Bearing Telemetry...")

        let home = GeoCoordinate(latitude: 35.6892, longitude: 51.3890) // Tehran (LM35)
        let lookup = CallsignLookupResult(
            callsign: "EP2KISH",
            name: "Kish Station",
            grid: "LL46"
        )

        let report = CallIntelligenceEngine.analyze(
            callsign: "EP2KISH",
            band: "20m",
            mode: "SSB",
            records: [],
            homeCoordinate: home,
            lookupResult: lookup
        )

        assert(report.distanceKm != nil, "Distance must be calculated")
        assert(report.shortPathBearingDeg != nil, "Short path bearing must be calculated")
        assert(report.targetIllumination != nil, "Illumination state must be resolved")

        if let dist = report.distanceKm {
            // Distance Tehran to Kish is approx 1010-1025 km
            assert(dist > 950 && dist < 1100, "Distance Tehran-Kish expected ~1018 km, got \(dist)")
        }

        if let sp = report.shortPathBearingDeg {
            // Bearing Tehran (LM35) to LL46 is SSW (~193°)
            assert(sp > 185 && sp < 205, "Bearing expected SSW (~193°), got \(sp)")
        }

        print("  ✓ Solar and Bearing telemetry verified.")
    }

    // MARK: - 5. LoTW and QSL Likelihood
    private static func testLoTWAndQSLLikelihood() {
        print("🧪 Testing LoTW & QSL Likelihood Scoring...")

        let report = CallIntelligenceEngine.analyze(
            callsign: "W1AW",
            band: "20m",
            mode: "CW",
            records: [],
            homeCoordinate: nil,
            lookupResult: nil
        )

        assert(!report.recommendedQSLRoute.isEmpty, "Recommended route must not be empty")
        print("  ✓ QSL Likelihood verified.")
    }
}
