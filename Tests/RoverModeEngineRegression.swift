//
//  RoverModeEngineRegression.swift
//  YAAM Tests
//
//  Regression tests for Tactical Rover Mode:
//  - Session duration and countdown calculation
//  - 4-way compass Maidenhead grid stepping across square and field boundaries
//  - Great-Circle telemetry from home station
//  - Activation, extension, and safe deactivation
//

import Foundation
@testable import YAAM

@main
@MainActor
struct RoverModeEngineRegression {
    static func main() async {
        print("🚀 Starting Tactical Rover Mode Regression Test Suite...")
        testGridSteppingMath()
        testFieldBoundaryWrapping()
        testRoverSessionDurations()
        await testRoverActivationAndState()
        await testRoverTelemetryCalculation()
        print("🎉 ALL Tactical Rover Mode Tests PASSED successfully!")
    }

    // MARK: - 1. Grid Stepping Math
    private static func testGridSteppingMath() {
        print("🧪 Testing 4-Way Compass Grid Stepping (North, South, East, West)...")

        let origin = "LL46"

        // North: latIndex + 1 -> LL47
        let north = RoverModeEngine.calculateSteppedGrid(from: origin, dLon: 0, dLat: 1)
        assert(north == "LL47", "Expected LL47, got \(String(describing: north))")

        // South: latIndex - 1 -> LL45
        let south = RoverModeEngine.calculateSteppedGrid(from: origin, dLon: 0, dLat: -1)
        assert(south == "LL45", "Expected LL45, got \(String(describing: south))")

        // East: lonIndex + 1 -> LL56
        let east = RoverModeEngine.calculateSteppedGrid(from: origin, dLon: 1, dLat: 0)
        assert(east == "LL56", "Expected LL56, got \(String(describing: east))")

        // West: lonIndex - 1 -> LL36
        let west = RoverModeEngine.calculateSteppedGrid(from: origin, dLon: -1, dLat: 0)
        assert(west == "LL36", "Expected LL36, got \(String(describing: west))")

        // 6-character grid preserves subsquares:
        let origin6 = "LL46wr"
        let north6 = RoverModeEngine.calculateSteppedGrid(from: origin6, dLon: 0, dLat: 1)
        assert(north6 == "LL47wr", "Expected LL47wr, got \(String(describing: north6))")

        print("  ✓ 4-Way Compass Stepping verified.")
    }

    // MARK: - 2. Field Boundary Wrapping
    private static func testFieldBoundaryWrapping() {
        print("🧪 Testing Field Boundary Transitions (e.g. square 9 to square 0 next field)...")

        // Stepping East from LM95 -> LN05 (Field L to M)
        let eastFrom9 = RoverModeEngine.calculateSteppedGrid(from: "LM95", dLon: 1, dLat: 0)
        assert(eastFrom9 == "MM05", "Expected MM05, got \(String(describing: eastFrom9))")

        // Stepping North from LM99 -> LN90
        let northFrom9 = RoverModeEngine.calculateSteppedGrid(from: "LM99", dLon: 0, dLat: 1)
        assert(northFrom9 == "LN90", "Expected LN90, got \(String(describing: northFrom9))")

        print("  ✓ Field Boundary Transitions verified.")
    }

    // MARK: - 3. Rover Session Durations
    private static func testRoverSessionDurations() {
        print("🧪 Testing Rover Session Durations & Expiration...")

        let now = Date()
        let session1h = RoverSession(
            targetGrid: "LL46",
            startTime: now,
            duration: .oneHour
        )
        assert(!session1h.isExpired, "Session should not be expired immediately")
        assert(session1h.remainingSeconds > 3590 && session1h.remainingSeconds <= 3600,
               "1h session should have ~3600s remaining")

        let pastSession = RoverSession(
            targetGrid: "LL46",
            startTime: now.addingTimeInterval(-7200),
            duration: .oneHour,
            expirationDate: now.addingTimeInterval(-3600)
        )
        assert(pastSession.isExpired, "Session in past should be expired")
        assert(pastSession.remainingSeconds == 0, "Expired session remaining seconds must be 0")

        print("  ✓ Session Durations & Expiration verified.")
    }

    // MARK: - 4. Rover Activation & Engine State
    private static func testRoverActivationAndState() async {
        print("🧪 Testing RoverModeEngine Lifecycle (Activate, Extend, Deactivate)...")

        await MainActor.run {
            let engine = RoverModeEngine.shared

            // Deactivate any pre-existing
            engine.deactivate()
            assert(!engine.isRoverActive, "Rover should be inactive initially")

            // Test activation
            let success = engine.activate(
                grid: "LL46",
                label: "Kish Island POTA",
                duration: .oneHour,
                stampInOutgoingQSOs: true
            )
            assert(success, "Activation of LL46 must succeed")
            assert(engine.isRoverActive, "isRoverActive must be true")
            assert(engine.activeSession?.targetGrid == "LL46", "Target grid must be LL46")
            assert(engine.activeSession?.stampInOutgoingQSOs == true, "stampInOutgoingQSOs must be true")

            // Test effective grid provider
            let effGrid = engine.effectiveGrid(homeGrid: "LM35")
            assert(effGrid == "LL46", "Effective grid during rover must be LL46, got \(effGrid)")

            // Test grid stepping while active
            engine.stepNorth()
            assert(engine.activeSession?.targetGrid == "LL47", "Target grid after stepNorth should be LL47")

            // Test extend
            let beforeExp = engine.activeSession?.expirationDate
            engine.extendDuration(seconds: 3600)
            let afterExp = engine.activeSession?.expirationDate
            if let b = beforeExp, let a = afterExp {
                assert(a.timeIntervalSince(b) >= 3599, "Session must be extended by ~1h")
            }

            // Test deactivation
            engine.deactivate()
            assert(!engine.isRoverActive, "isRoverActive must be false after deactivation")
            assert(engine.activeSession == nil, "activeSession must be nil after deactivation")

            let homeFallback = engine.effectiveGrid(homeGrid: "LM35")
            assert(homeFallback == "LM35", "Effective grid after deactivation must return to LM35")
        }

        print("  ✓ Engine Lifecycle verified.")
    }

    // MARK: - 5. Rover Telemetry Calculation
    private static func testRoverTelemetryCalculation() async {
        print("🧪 Testing Rover Telemetry (Distance & Bearing from Home)...")

        await MainActor.run {
            let engine = RoverModeEngine.shared
            // From Tehran (LM35) to Kish Island (LL46)
            let tel = engine.telemetry(homeGrid: "LM35", roverGridOverride: "LL46")
            assert(tel != nil, "Telemetry must be calculable for LM35 -> LL46")

            guard let t = tel else { fatalError("Telemetry was nil") }
            // Distance Tehran to Kish Island is roughly ~1000 - 1100 km
            assert(t.distanceKm >= 950 && t.distanceKm <= 1200,
                   "Distance Tehran-Kish expected ~1050km, got \(t.distanceKm) km")

            // Direction from Tehran to Kish is roughly South-South-East (bearing around 165°-175°)
            assert(t.bearingDegrees >= 150 && t.bearingDegrees <= 190,
                   "Bearing Tehran-Kish expected ~170°, got \(t.bearingDegrees)°")

            assert(!t.daylightSummary.isEmpty, "Daylight summary must not be empty")
        }

        print("  ✓ Rover Telemetry verified.")
    }
}
