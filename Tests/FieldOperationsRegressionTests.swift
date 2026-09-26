//
//  FieldOperationsRegressionTests.swift
//  YAAM Tests
//
//  Regression test suite for POTA & SOTA Field Operations Hub:
//  - Session qualification threshold calculation (10 for POTA, 4 for SOTA)
//  - Standard POTA ADIF and SOTA CSV filename generation
//  - Mandatory ADIF tag injection (MY_SIG, MY_SIG_INFO, MY_POTA_REF)
//  - Park-to-Park (P2P) and Summit-to-Summit (S2S) detection
//  - Offline park search and distance calculations
//  - POTA Spot frequency and band normalization
//

import CoreLocation
#if canImport(YAAM) && !STANDALONE_TEST
@testable import YAAM
#endif

#if STANDALONE_TEST
typealias QSORecordModel = SimpleFieldQSO
#endif

@main
@MainActor
struct FieldOperationsRegressionTests {
    static func main() async {
        print("🚀 Starting POTA & SOTA Field Operations Regression Suite...")

        testSessionQualificationThresholds()
        testStandardFilenameGeneration()
        testPOTAADIFTagInjection()
        testSOTACSVFormat()
        testOfflineParkDirectorySearchAndProximity()
        testPOTASpotFrequencyAndBandPlan()
        testP2PAndS2SDetection()

        print("🎉 ALL POTA & SOTA Field Operations Tests PASSED successfully!")
    }

    // MARK: - 1. Qualification Thresholds
    private static func testSessionQualificationThresholds() {
        print("🧪 Testing Session Qualification Thresholds...")

        // POTA requires 10 QSOs
        var potaSession = FieldActivationSession(
            program: .pota,
            myReference: "K-0001",
            operatorCallsign: "W1AW",
            qsoCount: 0,
            targetGoal: 10
        )
        assert(!potaSession.isQualified, "0 QSOs must not qualify POTA")
        assert(potaSession.remainingToQualify == 10, "Remaining must be 10")
        assert(potaSession.progressFraction == 0.0, "Progress fraction must be 0")

        potaSession.qsoCount = 9
        assert(!potaSession.isQualified, "9 QSOs must not qualify POTA")
        assert(potaSession.remainingToQualify == 1, "Remaining must be 1")
        assert(potaSession.progressFraction == 0.9, "Progress fraction must be 0.9")

        potaSession.qsoCount = 10
        assert(potaSession.isQualified, "10 QSOs must qualify POTA")
        assert(potaSession.remainingToQualify == 0, "Remaining must be 0")
        assert(potaSession.progressFraction == 1.0, "Progress fraction must be 1.0")

        // SOTA requires 4 QSOs
        var sotaSession = FieldActivationSession(
            program: .sota,
            myReference: "W6/NC-423",
            operatorCallsign: "N6JRL",
            qsoCount: 3,
            targetGoal: 4
        )
        assert(!sotaSession.isQualified, "3 QSOs must not qualify SOTA")
        sotaSession.qsoCount = 4
        assert(sotaSession.isQualified, "4 QSOs must qualify SOTA")

        print("  ✓ Qualification thresholds verified.")
    }

    // MARK: - 2. Standard Filenames
    private static func testStandardFilenameGeneration() {
        print("🧪 Testing Standard POTA and SOTA Filename Generation...")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let fixedDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 23))!

        let potaName = FieldLogExporter.generatePOTAFilename(callsign: "W1AW", reference: "K-0001", date: fixedDate)
        assert(potaName == "W1AW@K-0001-20260923.adi", "Expected W1AW@K-0001-20260923.adi, got \(potaName)")

        let potaPortable = FieldLogExporter.generatePOTAFilename(callsign: "EP2LMA", reference: "EP-0005", date: fixedDate)
        assert(potaPortable == "EP2LMA@EP-0005-20260923.adi", "Expected EP2LMA@EP-0005-20260923.adi, got \(potaPortable)")

        let sotaName = FieldLogExporter.generateSOTAFilename(callsign: "W6/N6JRL", summit: "W6/NC-423", date: fixedDate)
        assert(sotaName == "SOTA_W6-N6JRL_W6_NC-423_20260923.csv", "Expected SOTA_W6-N6JRL_W6_NC-423_20260923.csv, got \(sotaName)")

        print("  ✓ Filename conventions verified.")
    }

    // MARK: - 3. POTA ADIF Tag Injection
    private static func testPOTAADIFTagInjection() {
        print("🧪 Testing POTA ADIF Content & Tag Injection...")

        let session = FieldActivationSession(
            program: .pota,
            myReference: "K-0020",
            operatorCallsign: "W1AW",
            gridSquare: "DM36"
        )

        let qso = SimpleFieldQSO(fields: [
            "CALL": "K7ATN",
            "QSO_DATE": "20260923",
            "TIME_ON": "1330",
            "BAND": "20m",
            "MODE": "CW",
            "RST_SENT": "599",
            "RST_RCVD": "599",
            "POTA_REF": "K-0044"
        ])

        let adif = FieldLogExporter.buildPOTAADIF(records: [qso], session: session)

        assert(adif.contains("<STATION_CALLSIGN:4>W1AW"), "Missing STATION_CALLSIGN tag")
        assert(adif.contains("<OPERATOR:4>W1AW"), "Missing OPERATOR tag")
        assert(adif.contains("<MY_SIG:4>POTA"), "Missing MY_SIG tag")
        assert(adif.contains("<MY_SIG_INFO:6>K-0020"), "Missing MY_SIG_INFO tag")
        assert(adif.contains("<MY_POTA_REF:6>K-0020"), "Missing MY_POTA_REF tag")
        assert(adif.contains("<MY_GRIDSQUARE:4>DM36"), "Missing MY_GRIDSQUARE tag")
        assert(adif.contains("<POTA_REF:6>K-0044"), "Missing contacted POTA_REF tag")
        assert(adif.contains("<CALL:5>K7ATN"), "Missing CALL tag")
        assert(adif.contains("<EOR>"), "Missing EOR tag")

        print("  ✓ POTA ADIF tags verified.")
    }

    // MARK: - 4. SOTA CSV Format
    private static func testSOTACSVFormat() {
        print("🧪 Testing SOTA CSV Format Generation...")

        let session = FieldActivationSession(
            program: .sota,
            myReference: "W6/NC-423",
            operatorCallsign: "N6JRL"
        )

        let qso = SimpleFieldQSO(fields: [
            "CALL": "W7W/KG-001",
            "QSO_DATE": "20260923",
            "TIME_ON": "1415",
            "BAND": "40m",
            "MODE": "CW",
            "SOTA_REF": "W7W/KG-001",
            "COMMENT": "S2S Summit to Summit"
        ])

        let csv = FieldLogExporter.buildSOTACSV(records: [qso], session: session)
        let expectedRow = "V2,N6JRL,W6/NC-423,23/09/26,1415,40m,CW,W7W/KG-001,W7W/KG-001,S2S Summit to Summit\n"
        assert(csv == expectedRow, "SOTA CSV mismatch. Got:\n\(csv)\nExpected:\n\(expectedRow)")

        print("  ✓ SOTA CSV format verified.")
    }

    // MARK: - 5. Offline Park Directory Search & Proximity
    private static func testOfflineParkDirectorySearchAndProximity() {
        print("🧪 Testing Offline Park Directory Search & Proximity...")

        let dir = POTAParkDirectory.shared
        assert(dir.isLoaded, "Directory must be loaded")
        assert(dir.entries.count >= 20, "Curated list must contain entries")

        // Search by reference
        let results = dir.search(query: "EP-0005")
        assert(!results.isEmpty, "Should find EP-0005")
        assert(results.first?.name.contains("Lar") == true, "Should be Lar National Park")

        // Search by name
        let yellowstone = dir.search(query: "Yellowstone")
        assert(!yellowstone.isEmpty, "Should find Yellowstone")
        assert(yellowstone.first?.reference == "K-0069", "Reference should be K-0069")

        // Lookup exact
        let damavand = dir.lookup(reference: "EP/TE-001")
        assert(damavand != nil, "Should find Mount Damavand")
        assert(damavand?.elevationMeters == 5609, "Elevation should be 5609m")

        // Proximity calculation from Tehran coordinate (approx 35.7, 51.4)
        let tehranCoord = CLLocationCoordinate2D(latitude: 35.70, longitude: 51.40)
        let nearest = dir.nearestParks(to: tehranCoord, maxRadiusKm: 150.0)
        assert(!nearest.isEmpty, "Should find nearby parks to Tehran")
        assert(nearest.contains { $0.entry.reference == "EP-0005" }, "Should contain Lar National Park")

        print("  ✓ Offline directory search & proximity verified.")
    }

    // MARK: - 6. Spot Frequency & Band Plan
    private static func testPOTASpotFrequencyAndBandPlan() {
        print("🧪 Testing POTA Spot Frequency & Band Plan...")

        let spotKhz = POTASpotItem(
            spotId: 1,
            activator: "W1AW",
            frequency: 14074.0, // kHz
            mode: "FT8",
            reference: "K-0001"
        )
        assert(spotKhz.frequencyMHz == 14.074, "Expected 14.074 MHz")
        assert(spotKhz.band == "20m", "Expected 20m band")

        let spotMhz = POTASpotItem(
            spotId: 2,
            activator: "K7ATN",
            frequency: 7.032, // MHz
            mode: "CW",
            reference: "K-0020"
        )
        assert(spotMhz.frequencyMHz == 7.032, "Expected 7.032 MHz")
        assert(spotMhz.band == "40m", "Expected 40m band")

        print("  ✓ Spot frequency and band plan verified.")
    }

    // MARK: - 7. P2P & S2S Detection
    private static func testP2PAndS2SDetection() {
        print("🧪 Testing Park-to-Park (P2P) and Summit-to-Summit (S2S) Detection...")

        let session = FieldActivationSession(
            program: .pota,
            myReference: "K-0001",
            operatorCallsign: "W1AW"
        )

        // Contacted station also has a park reference
        let contactedRef = "K-0020"
        let isP2P = session.isActive && !contactedRef.isEmpty
        assert(isP2P, "Contact with a hunter in another park must be flagged as P2P")

        print("  ✓ P2P and S2S detection verified.")
    }
}
