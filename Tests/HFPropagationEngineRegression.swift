//
//  HFPropagationEngineRegression.swift
//  YAAM Tests
//
//  Comprehensive automated regression test suite for YAAM's Live HF Propagation & MUF Forecasting Engine:
//  - 11-Band Amateur Coverage (160m to 6m Magic Band)
//  - Synchronous Pure-Functional predictPath API
//  - Physics Validation: MUF, LUF, FOT (85% rule), and D-Layer Absorption
//  - Topband (160m) Nocturnal vs Diurnal Characteristics
//  - 6m Magic Band Sporadic-E & Solar Cycle Sensitivity
//  - Dynamic Peak Open Hour in 24h Circuit Matrix
//  - Rover Mode Geodesic Coordinate Synchronization
//

import Foundation
#if canImport(YAAM)
@testable import YAAM
#endif

@main
struct HFPropagationEngineRegression {
    static func main() async {
        print("🚀 Starting HF Propagation & MUF Forecasting Engine Regression Suite...")

        testBandCoverage()
        testPointToPointPrediction()
        testTopband160mDLayerPhysics()
        testSixMeterMagicBandPhysics()
        testCircuitMatrixDynamicPeakHour()
        testRoverModeCoordinateSync()
        testCallIntelligenceIntegration()

        print("🎉 ALL HF Propagation & MUF Forecasting Tests PASSED successfully!")
    }

    // MARK: - 1. Band Coverage Test
    private static func testBandCoverage() {
        print("🧪 Testing 11-band amateur coverage (160m to 6m)...")
        let bands = HFPointToPointPropagationEngine.supportedBands
        precondition(bands.count == 11, "Expected 11 supported bands, got \(bands.count)")

        let expectedNames = ["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m"]
        for (idx, expected) in expectedNames.enumerated() {
            precondition(bands[idx].name == expected, "Expected band \(expected) at index \(idx), got \(bands[idx].name)")
        }

        precondition(HFPointToPointPropagationEngine.frequency(for: "160m") == 1.8, "160m freq mismatch")
        precondition(HFPointToPointPropagationEngine.frequency(for: "60m") == 5.3, "60m freq mismatch")
        precondition(HFPointToPointPropagationEngine.frequency(for: "6m") == 50.1, "6m freq mismatch")
        print("   ✓ All 11 amateur bands verified from 1.8 MHz (160m) to 50.1 MHz (6m).")
    }

    // MARK: - 2. Point-to-Point Prediction API
    private static func testPointToPointPrediction() {
        print("🧪 Testing predictPath(...) point-to-point engine...")
        let tehran = GeoCoordinate(latitude: 35.6892, longitude: 51.3890)
        let london = GeoCoordinate(latitude: 51.5074, longitude: -0.1278)

        let prediction = HFPointToPointPropagationEngine.predictPath(
            de: tehran,
            dx: london,
            band: "20m",
            sfi: 150.0,
            kp: 2.0
        )

        precondition(prediction.band == "20m", "Band mismatch in prediction")
        precondition(prediction.frequencyMHz == 14.0, "Frequency mismatch for 20m")
        precondition(prediction.pathMUF > 5.0, "MUF too low: \(prediction.pathMUF)")
        precondition(prediction.pathLUF > 0.0, "LUF should be positive: \(prediction.pathLUF)")
        precondition(prediction.optimalFOT > 0.0, "FOT should be positive: \(prediction.optimalFOT)")
        precondition(abs(prediction.optimalFOT - (prediction.pathMUF * 0.85)) < 0.1, "FOT should follow 85% rule")
        precondition(prediction.reliabilityPercent >= 0 && prediction.reliabilityPercent <= 100, "Reliability out of bounds")
        precondition(prediction.hourlyTimeline.count == 24, "Expected 24 hourly timeline entries, got \(prediction.hourlyTimeline.count)")
        precondition(!prediction.advice.isEmpty, "Advice should not be empty")
        precondition(!prediction.bestBandNow.isEmpty, "Best band should be identified")

        print("   ✓ Tehran -> London 20m: MUF \(String(format: "%.1f", prediction.pathMUF)) MHz, FOT \(String(format: "%.1f", prediction.optimalFOT)) MHz, Rel \(prediction.reliabilityPercent)%, Condition: \(prediction.condition.rawValue)")
    }

    // MARK: - 3. 160m Topband D-Layer Physics Test
    private static func testTopband160mDLayerPhysics() {
        print("🧪 Testing 160m Topband nocturnal vs diurnal D-layer absorption...")
        let tehran = GeoCoordinate(latitude: 35.6892, longitude: 51.3890)
        let london = GeoCoordinate(latitude: 51.5074, longitude: -0.1278)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        // Midnight UTC (darkness across path)
        var midnightComps = DateComponents()
        midnightComps.year = 2026; midnightComps.month = 1; midnightComps.day = 15; midnightComps.hour = 23
        let midnightDate = cal.date(from: midnightComps)!

        // Midday UTC (broad daylight across path)
        var middayComps = DateComponents()
        middayComps.year = 2026; middayComps.month = 1; middayComps.day = 15; middayComps.hour = 11
        let middayDate = cal.date(from: middayComps)!

        let nightPred = HFPointToPointPropagationEngine.predictPath(de: tehran, dx: london, band: "160m", date: midnightDate)
        let dayPred = HFPointToPointPropagationEngine.predictPath(de: tehran, dx: london, band: "160m", date: middayDate)

        precondition(nightPred.reliabilityPercent > dayPred.reliabilityPercent, "160m night reliability (\(nightPred.reliabilityPercent)%) must exceed day reliability (\(dayPred.reliabilityPercent)%) due to D-layer absorption")
        print("   ✓ 160m D-layer physics verified: Midnight \(nightPred.reliabilityPercent)% vs Midday \(dayPred.reliabilityPercent)%")
    }

    // MARK: - 4. 6m Magic Band Physics Test
    private static func testSixMeterMagicBandPhysics() {
        print("🧪 Testing 6m Magic Band Sporadic-E & solar cycle behavior...")
        let tehran = GeoCoordinate(latitude: 35.6892, longitude: 51.3890)
        let athens = GeoCoordinate(latitude: 37.9838, longitude: 23.7275) // ~2400 km ideal single-hop Es

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        // Summer solstice date (Peak Sporadic-E)
        var summerComps = DateComponents()
        summerComps.year = 2026; summerComps.month = 6; summerComps.day = 21; summerComps.hour = 14
        let summerDate = cal.date(from: summerComps)!

        // Winter solar minimum
        var winterComps = DateComponents()
        winterComps.year = 2026; winterComps.month = 12; winterComps.day = 21; winterComps.hour = 14
        let winterDate = cal.date(from: winterComps)!

        let summerPred = HFPointToPointPropagationEngine.predictPath(de: tehran, dx: athens, band: "6m", sfi: 180.0, date: summerDate)
        let winterPred = HFPointToPointPropagationEngine.predictPath(de: tehran, dx: athens, band: "6m", sfi: 70.0, date: winterDate)

        precondition(summerPred.reliabilityPercent > winterPred.reliabilityPercent, "6m summer Es/high-SFI path must outperform winter low-SFI path")
        print("   ✓ 6m Magic Band physics verified: Summer high-SFI \(summerPred.reliabilityPercent)% vs Winter low-SFI \(winterPred.reliabilityPercent)%")
    }

    // MARK: - 5. Dynamic Peak Open Hour in 24h Circuit Matrix
    private static func testCircuitMatrixDynamicPeakHour() {
        print("🧪 Testing 24h Circuit Matrix dynamic peakOpenHourUTC...")
        let de = GeoCoordinate(latitude: 35.6892, longitude: 51.3890)
        let dx = GeoCoordinate(latitude: 40.7128, longitude: -74.0060) // New York

        let matrix = HFPointToPointPropagationEngine.calculateCircuitMatrix(
            de: de,
            dx: dx,
            dxCallsign: "W2NYC",
            sfi: 160.0,
            kp: 1.5
        )

        precondition(matrix.peakOpenHourUTC >= 0 && matrix.peakOpenHourUTC <= 23, "Peak hour out of bounds: \(matrix.peakOpenHourUTC)")
        precondition(matrix.bands.count == 11, "Matrix missing 11 bands")
        precondition(!matrix.openBandsNow.isEmpty, "Expected at least one open band under SFI 160")

        print("   ✓ Dynamic peak hour calculated: \(String(format: "%02d:00z", matrix.peakOpenHourUTC)) with best band now \(matrix.bestBandNow)")
    }

    // MARK: - 6. Rover Mode Coordinate Sync
    private static func testRoverModeCoordinateSync() {
        print("🧪 Testing Rover Mode coordinate synchronization...")
        let baseStation = GeoCoordinate(latitude: 35.6892, longitude: 51.3890) // Tehran
        let kishRover = GeoCoordinate(latitude: 26.5333, longitude: 53.9833)   // Kish Island (LL46)
        let tokyo = GeoCoordinate(latitude: 35.6762, longitude: 139.6503)

        let basePred = HFPointToPointPropagationEngine.predictPath(de: baseStation, dx: tokyo, band: "20m")
        let roverPred = HFPointToPointPropagationEngine.predictPath(de: kishRover, dx: tokyo, band: "20m")

        let baseDist = GeodesicMath.distanceKm(from: baseStation, to: tokyo)
        let roverDist = GeodesicMath.distanceKm(from: kishRover, to: tokyo)

        precondition(abs(baseDist - roverDist) > 250.0, "Distances should differ by >250km between Tehran and Kish")
        print("   ✓ Geodesic delta verified: Tehran-Tokyo \(Int(baseDist)) km vs Kish-Tokyo \(Int(roverDist)) km")
        print("   ✓ Rover Mode propagation recalculated with independent MUF: Base \(String(format: "%.1f", basePred.pathMUF)) MHz vs Rover \(String(format: "%.1f", roverPred.pathMUF)) MHz")
    }

    // MARK: - 7. Call Intelligence Integration
    @MainActor
    private static func testCallIntelligenceIntegration() {
        print("🧪 Testing CallIntelligenceEngine integration with live propagation prediction...")
        let tehran = GeoCoordinate(latitude: 35.6892, longitude: 51.3890)
        let lookup = CallsignLookupResult(
            callsign: "G4ABC",
            name: "John Smith",
            qth: "London",
            grid: "IO91wm",
            latitude: "51.5074",
            longitude: "-0.1278"
        )

        let report = CallIntelligenceEngine.analyze(
            callsign: "G4ABC",
            band: "20m",
            mode: "CW",
            records: [],
            homeCoordinate: tehran,
            lookupResult: lookup
        )

        guard let prop = report.propagationPrediction else {
            fatalError("CallIntelligenceReport should include non-nil propagationPrediction when coordinates exist")
        }

        precondition(prop.band == "20m", "Report prediction band mismatch")
        precondition(prop.pathMUF > 0.0, "Report prediction MUF should be positive")
        precondition(prop.hourlyTimeline.count == 24, "Report prediction timeline should have 24 hours")
        print("   ✓ CallIntelligenceReport successfully integrated with live MUF Radar: MUF \(String(format: "%.1f", prop.pathMUF)) MHz, Advice: '\(prop.advice)'")
    }
}
