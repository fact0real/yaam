//
//  HamClockEnginesRegressionTests.swift
//  YAAM Tests
//
//  Automated Regression Test Suite for HamClock-Inspired Engines:
//  - ShackClockEngine (LST, Solar Time, Stopwatch, Ticker)
//  - SatelliteTrackingEngine (SGP4/Keplerian orbit propagation, Footprint radius, Doppler shift)
//  - AuroralOvalEngine (NOAA OVATION model, Kp & Bz modulation, boundary rings)
//  - HFPointToPointPropagationEngine (VOACAP-style 24-hour DE-to-DX circuit reliability matrix)
//

import Foundation
#if canImport(YAAM)
@testable import YAAM
#endif

@main
struct HamClockEnginesRegressionTests {
    static func main() async {
        print("🚀 Starting HamClock Engines Regression Test Suite...")

        testShackClockCalculations()
        testSatelliteOrbitalPropagationAndDoppler()
        testAuroralOvalGeometryAndStormModulation()
        await testHFPointToPointPropagationMatrix()
        testHamClockRemoteWebServer()
        testDRAPAbsorptionCalculations()
        testAPRSBalloonTrackingEngine()

        print("🎉 ALL HamClock Engine Regression Tests PASSED successfully!")
    }

    // MARK: - 1. Shack Clock Engine Tests

    @MainActor
    private static func testShackClockCalculations() {
        print("🧪 Testing ShackClockEngine (LST, Solar Time, Timers)...")
        let clock = ShackClockEngine.shared

        // Tehran Longitude: 51.389° E
        clock.setStationLongitude(51.389)

        // Test LST calculation for a fixed UTC date: 2026-09-11 12:00:00 UTC
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 9
        comps.day = 11
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        let testDate = cal.date(from: comps)!

        let lst = clock.calculateLST(for: testDate, longitude: 51.389)
        precondition(lst.contains("LST"), "Expected LST format string, got \(lst)")
        print("   ✓ LST for Tehran at 12:00 UTC: \(lst)")

        // Test Solar Time (LMST): at 12:00 UTC, longitude 51.4° is ahead by ~3.42 hours (~15:25 SOL)
        let solar = clock.calculateSolarTime(for: testDate, longitude: 51.389)
        precondition(solar.contains("SOL"), "Expected SOL format string, got \(solar)")
        print("   ✓ Solar time for Tehran at 12:00 UTC: \(solar)")

        // Test Stopwatch Controls
        clock.resetStopwatch()
        precondition(clock.stopwatchElapsed == 0.0, "Expected 0 elapsed seconds")
        clock.toggleStopwatch()
        precondition(clock.isStopwatchRunning == true, "Expected stopwatch running")
        clock.toggleStopwatch()
        precondition(clock.isStopwatchRunning == false, "Expected stopwatch stopped")
    }

    // MARK: - 2. Satellite Tracking Engine Tests

    @MainActor
    private static func testSatelliteOrbitalPropagationAndDoppler() {
        print("🧪 Testing SatelliteTrackingEngine (ISS Orbit, Footprint, Doppler)...")
        let satEngine = SatelliteTrackingEngine.shared

        // Ensure default satellites list contains ISS, AO-91, SO-50, RS-44
        let sats = satEngine.satellites
        precondition(sats.contains(where: { $0.id == "ISS" }), "Missing ISS in satellite catalog")
        precondition(sats.contains(where: { $0.id == "AO-91" }), "Missing AO-91 in satellite catalog")
        precondition(sats.contains(where: { $0.id == "SO-50" }), "Missing SO-50 in satellite catalog")
        precondition(sats.contains(where: { $0.id == "RS-44" }), "Missing RS-44 in satellite catalog")

        // Set Tehran Observer
        let tehranCoord = GeoCoordinate(latitude: 35.6892, longitude: 51.3890)
        satEngine.setObserverCoordinate(tehranCoord)
        satEngine.selectedSatelliteID = "ISS"
        satEngine.calculateCurrentTelemetry()

        guard let telem = satEngine.currentTelemetry else {
            fatalError("Failed to compute ISS telemetry")
        }

        // Validate physical bounds of ISS orbit
        precondition(telem.altitudeKm >= 380.0 && telem.altitudeKm <= 460.0, "Invalid ISS altitude: \(telem.altitudeKm) km")
        precondition(telem.footprintRadiusKm >= 2000.0 && telem.footprintRadiusKm <= 2600.0, "Invalid footprint radius: \(telem.footprintRadiusKm) km")
        precondition(telem.azimuthDeg >= 0.0 && telem.azimuthDeg <= 360.0, "Invalid azimuth: \(telem.azimuthDeg)")
        precondition(telem.elevationDeg >= -90.0 && telem.elevationDeg <= 90.0, "Invalid elevation: \(telem.elevationDeg)")

        // Validate ground track waypoints generated
        precondition(satEngine.groundTrackWaypoints.count >= 60, "Expected at least 60 ground track waypoints, got \(satEngine.groundTrackWaypoints.count)")

        print("   ✓ ISS Sub-satellite point: (\(String(format: "%.2f", telem.coordinate.latitude))°, \(String(format: "%.2f", telem.coordinate.longitude))°)")
        print("   ✓ ISS Altitude: \(String(format: "%.1f", telem.altitudeKm)) km, Footprint: \(String(format: "%.0f", telem.footprintRadiusKm)) km")
        print("   ✓ Doppler shifts: TX \(String(format: "%+.0f", telem.uplinkDopplerHz)) Hz, RX \(String(format: "%+.0f", telem.downlinkDopplerHz)) Hz")
    }

    // MARK: - 3. Auroral Oval Geometry & Storm Modulation Tests

    @MainActor
    private static func testAuroralOvalGeometryAndStormModulation() {
        print("🧪 Testing AuroralOvalEngine (Kp & IMF Bz Modulation)...")

        // Quiet Conditions: Kp = 1.0, Bz = +2.0 nT (Northward IMF)
        let quietBoundary = AuroralOvalEngine.calculateBoundary(kp: 1.0, bz: 2.0)
        precondition(quietBoundary.northernOuterRing.count >= 60, "Expected full northern outer polygon ring")
        precondition(quietBoundary.southernOuterRing.count >= 60, "Expected full southern outer polygon ring")

        // Quiet oval equatorward edge should remain at high latitude (~64° to 67° geomagnetic)
        precondition(quietBoundary.equatorwardEdgeGeomagneticLat >= 62.0, "Quiet oval too low in latitude: \(quietBoundary.equatorwardEdgeGeomagneticLat)")

        // Severe Geomagnetic Storm: Kp = 8.0, Bz = -15.0 nT (Strong Southward IMF)
        let stormBoundary = AuroralOvalEngine.calculateBoundary(kp: 8.0, bz: -15.0)

        // Storm oval should expand equatorward significantly (< 52° geomagnetic latitude)
        precondition(stormBoundary.equatorwardEdgeGeomagneticLat < quietBoundary.equatorwardEdgeGeomagneticLat, "Storm oval did not expand equatorward")
        precondition(stormBoundary.equatorwardEdgeGeomagneticLat <= 52.0, "Storm oval equatorward edge should reach mid-latitudes, got \(stormBoundary.equatorwardEdgeGeomagneticLat)")

        print("   ✓ Quiet oval edge (Kp=1): \(String(format: "%.1f", quietBoundary.equatorwardEdgeGeomagneticLat))° MagLat")
        print("   ✓ Severe Storm oval edge (Kp=8): \(String(format: "%.1f", stormBoundary.equatorwardEdgeGeomagneticLat))° MagLat (Expanded into mid-latitudes for VHF)")
    }

    // MARK: - 4. VOACAP DE-to-DX Propagation Matrix Tests

    @MainActor
    private static func testHFPointToPointPropagationMatrix() async {
        print("🧪 Testing HFPointToPointPropagationEngine (VOACAP DE-to-DX 24h Matrix)...")
        let propEngine = HFPointToPointPropagationEngine.shared

        // Path: Tehran (EP) to Boston (W1)
        let tehran = GeoCoordinate(latitude: 35.6892, longitude: 51.3890)
        let boston = GeoCoordinate(latitude: 42.3601, longitude: -71.0589)

        propEngine.calculateCircuit(
            de: tehran,
            dx: boston,
            dxCallsign: "W1AW",
            sfi: 155.0,
            kp: 2.0
        )

        // Wait for background queue completion
        var attempts = 0
        while propEngine.activeMatrix == nil && attempts < 30 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            attempts += 1
        }

        guard let matrix = propEngine.activeMatrix else {
            fatalError("Failed to compute HF propagation matrix")
        }

        precondition(matrix.bands.count == 11, "Expected 11 bands (160m-6m), got \(matrix.bands.count)")
        precondition(matrix.distanceKm > 9000.0 && matrix.distanceKm < 11000.0, "Expected dist ~9900 km, got \(matrix.distanceKm)")

        // Ensure 24 cells per band
        for band in matrix.bands {
            let cells = matrix.cellsByBand[band] ?? []
            precondition(cells.count == 24, "Expected 24 hour cells for \(band), got \(cells.count)")
        }

        print("   ✓ DE-to-DX Path: \(matrix.dxCallsign), Distance: \(String(format: "%.0f", matrix.distanceKm)) km, SP: \(String(format: "%03.0f", matrix.shortPathBearingDeg))°")
        print("   ✓ Best Band for current hour: \(matrix.bestBandNow)")
    }

    // MARK: - 5. Remote Web Server & Telemetry API Tests

    @MainActor
    private static func testHamClockRemoteWebServer() {
        print("🧪 Testing HamClockRemoteWebServer (JSON API, QR Code, Lifecycle)...")
        let server = HamClockRemoteWebServer.shared

        // Test telemetry JSON generation
        let jsonStr = server.buildTelemetryJSON()
        precondition(!jsonStr.isEmpty && jsonStr != "{}", "Telemetry JSON was empty")

        guard let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            fatalError("Failed to parse telemetry JSON output: \(jsonStr)")
        }

        precondition(dict["utcTime"] != nil, "Missing utcTime in telemetry")
        precondition(dict["deCall"] != nil, "Missing deCall in telemetry")
        precondition(dict["satName"] != nil, "Missing satName in telemetry")
        print("   ✓ Telemetry JSON payload successfully verified (UTC, DE, Satellite)")

        // Test IP resolution
        let ip = HamClockRemoteWebServer.resolveLocalWiFiIP()
        precondition(!ip.isEmpty, "Resolved IP should not be empty")
        print("   ✓ Resolved IP address: \(ip)")

        // Test QR code generator
        let qr = HamClockRemoteWebServer.generateQRCode(from: "http://\(ip):8080")
        precondition(qr != nil, "Failed to generate QR code NSImage")
        print("   ✓ QR Code generation verified for URL http://\(ip):8080")

        // Test server lifecycle
        server.start()
        precondition(server.isRunning, "Expected server.isRunning to be true after start()")
        server.stop()
        precondition(!server.isRunning, "Expected server.isRunning to be false after stop()")
        print("   ✓ Web server start/stop lifecycle verified")
    }

    // MARK: - 6. NOAA D-Region Absorption (D-RAP) Tests

    @MainActor
    private static func testDRAPAbsorptionCalculations() {
        print("🧪 Testing DRAPAbsorptionEngine (Solar Flare HAF & PCA)...")
        let drap = DRAPAbsorptionEngine.shared

        // Test Quiet conditions: 1e-7 W/m2 (B-class)
        let quietSnap = DRAPAbsorptionEngine.calculateDrap(xrayFluxWattsM2: 1e-7, flareClass: "B1.0", protonFlux: 1.0)
        precondition(quietSnap.subsolarHAFMHz < 2.0, "Quiet HAF too high: \(quietSnap.subsolarHAFMHz)")
        precondition(!quietSnap.isBlackoutActive, "Quiet conditions should not trigger blackout")
        print("   ✓ Quiet solar conditions: HAF = \(String(format: "%.2f", quietSnap.subsolarHAFMHz)) MHz, Scale = \(quietSnap.radioBlackoutScale)")

        // Test M1.0 flare: 1e-5 W/m2 -> HAF = 10 * sqrt(0.1) ≈ 3.16 MHz (R1 Minor Fadeout)
        let mSnap = DRAPAbsorptionEngine.calculateDrap(xrayFluxWattsM2: 1e-5, flareClass: "M1.0", protonFlux: 1.0)
        precondition(abs(mSnap.subsolarHAFMHz - 3.16) < 0.1, "Expected M1.0 HAF ~3.16 MHz, got \(mSnap.subsolarHAFMHz)")
        precondition(mSnap.radioBlackoutScale.contains("R1"), "Expected R1 scale for M1 flare, got \(mSnap.radioBlackoutScale)")
        print("   ✓ M1.0 Solar Flare: HAF = \(String(format: "%.2f", mSnap.subsolarHAFMHz)) MHz (\(mSnap.radioBlackoutScale))")

        // Test X1.0 flare: 1e-4 W/m2 -> HAF = 10 * sqrt(1.0) = 10.0 MHz (R3 Strong Blackout)
        let xSnap = DRAPAbsorptionEngine.calculateDrap(xrayFluxWattsM2: 1e-4, flareClass: "X1.0", protonFlux: 5.0)
        precondition(abs(xSnap.subsolarHAFMHz - 10.0) < 0.05, "Expected X1.0 HAF ~10.0 MHz, got \(xSnap.subsolarHAFMHz)")
        precondition(xSnap.radioBlackoutScale.contains("R3"), "Expected R3 scale for X1 flare, got \(xSnap.radioBlackoutScale)")
        precondition(xSnap.isBlackoutActive, "X1 flare must trigger blackout active")
        print("   ✓ X1.0 Major Flare: HAF = \(String(format: "%.1f", xSnap.subsolarHAFMHz)) MHz (\(xSnap.radioBlackoutScale))")

        // Test PCA: 100 pfu proton flux -> 0.15 * 10 = 1.5 dB
        let pcaSnap = DRAPAbsorptionEngine.calculateDrap(xrayFluxWattsM2: 1e-4, flareClass: "X1.0", protonFlux: 100.0)
        precondition(abs(pcaSnap.polarCapAbsorptionDB - 1.5) < 0.05, "Expected PCA ~1.5 dB, got \(pcaSnap.polarCapAbsorptionDB)")
        print("   ✓ Polar Cap Absorption (PCA): \(String(format: "%.1f", pcaSnap.polarCapAbsorptionDB)) dB absorption in polar cap")

        // Test engine live state mutation
        drap.updateFlareTelemetry(flareClass: "X1.0", fluxWattsM2: 1e-4, protonFlux: 100.0)
        precondition(drap.blackoutLevel.rScale == 3, "Expected blackout level R3, got \(drap.blackoutLevel.rScale)")
        precondition(drap.maxHAFMHz == 10.0, "Expected maxHAF 10.0 MHz, got \(drap.maxHAFMHz)")
        print("   ✓ DRAP Engine state updated to \(drap.blackoutLevel.title)")
    }

    // MARK: - 7. APRS High-Altitude Balloon (HAB) Tests

    @MainActor
    private static func testAPRSBalloonTrackingEngine() {
        print("🧪 Testing APRSBalloonTrackingEngine (Balloons, Telemetry, Drift)...")
        let balloonEngine = APRSBalloonTrackingEngine.shared

        precondition(balloonEngine.balloons.count >= 2, "Expected at least 2 default balloons, got \(balloonEngine.balloons.count)")

        guard let first = balloonEngine.selectedBalloon else {
            fatalError("No balloon selected by default")
        }

        precondition(first.callsign == "W3BC-11", "Expected default balloon W3BC-11, got \(first.callsign)")
        precondition(first.altitudeMeters > 20000.0, "Invalid altitude: \(first.altitudeMeters)")
        precondition(first.altitudeFeet > 60000.0, "Invalid altitude in feet: \(first.altitudeFeet)")
        precondition(first.flightPhase == .ascending, "Expected ascending flight phase, got \(first.flightPhase)")
        precondition(!first.gridLocator.isEmpty, "Grid locator should not be empty")

        print("   ✓ Initial Balloon: \(first.callsign) '\(first.name)', Alt: \(first.altitudeFormatted), Status: \(first.flightStatus)")

        // Test adding / updating telemetry packet
        let testCoord = GeoCoordinate(latitude: 38.95, longitude: -76.90)
        balloonEngine.addOrUpdateBalloon(
            callsign: "W3BC-11",
            name: "NASA Jet Stream HAB-4",
            coordinate: testCoord,
            altitudeMeters: 25100.0,
            verticalSpeedMps: 4.5,
            speedKmH: 150.0,
            courseDeg: 85.0,
            tempC: -51.2
        )

        guard let updated = balloonEngine.selectedBalloon else {
            fatalError("Lost selected balloon after update")
        }

        precondition(updated.altitudeMeters == 25100.0, "Altitude did not update")
        precondition(updated.flightTrail.count >= 4, "Flight trail breadcrumbs did not grow")
        precondition(updated.coordinate == testCoord, "Coordinate did not update")
        print("   ✓ Telemetry ingestion verified: updated to \(updated.altitudeFormatted), trail has \(updated.flightTrail.count) fixes")

        // Test balloon selection switch
        balloonEngine.selectBalloon(callsign: "HAB-IRAN-1")
        precondition(balloonEngine.selectedBalloonCallsign == "HAB-IRAN-1", "Selection failed")
        precondition(balloonEngine.selectedBalloon?.callsign == "HAB-IRAN-1", "Selected balloon lookup failed")
        print("   ✓ Balloon selection switched to HAB-IRAN-1 successfully")
    }
}
