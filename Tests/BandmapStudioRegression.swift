//
//  BandmapStudioRegression.swift
//  YAAM Tests
//
//  Regression test suite for Bandmap Engine, IARU Region allocations,
//  License privilege filtering, Split tracking, and Heatmap activity calculations.
//

import Foundation
import SwiftUI

// Lightweight stubs for independent test runner execution
nonisolated enum AmateurBandPlan {
    static func formattedMHz(_ mhz: Double) -> String { String(format: "%.3f", mhz) }
    static func band(forMHz mhz: Double) -> String? {
        if mhz >= 3.5 && mhz <= 4.0 { return "80m" }
        if mhz >= 7.0 && mhz <= 7.3 { return "40m" }
        if mhz >= 14.0 && mhz <= 14.35 { return "20m" }
        return "20m"
    }
}

public struct QSORecordModel: Sendable {
    public var callsign: String = ""
    public var band: String = ""
    public var mode: String = ""
    public var isConfirmed: Bool = false

    public init(callsign: String = "", band: String = "", mode: String = "", isConfirmed: Bool = false) {
        self.callsign = callsign
        self.band = band
        self.mode = mode
        self.isConfirmed = isConfirmed
    }

    public subscript(key: String) -> String {
        switch key.uppercased() {
        case "CALL": return callsign
        case "BAND": return band
        case "MODE": return mode
        default: return ""
        }
    }
}

@main
struct BandmapStudioRegression {
    @MainActor
    static func main() {
        print("🚀 Starting Bandmap Studio & Spectrum Engine Regression Tests...")

        testIARURegionBandLimits()
        testLicensePrivilegeFiltering()
        testSplitTrackingAndOffset()
        testActivityHeatmapDensity()
        testSpotAgingAndTemporalDecay()
        testWSJTXSpotIngestion()

        print("🎉 ALL Bandmap Studio & Spectrum Engine Tests PASSED successfully!")
    }

    // MARK: - 1. IARU Region Band Limits
    @MainActor
    private static func testIARURegionBandLimits() {
        print("🧪 Testing IARU Region 1, 2, and 3 Band Allocations...")

        let engine = BandmapEngine.shared

        // 40M: Region 1 is 7.0 - 7.2 MHz, Region 2 is 7.0 - 7.3 MHz
        let r1_40m = engine.bandRangeKHz(for: "40M", region: .region1)
        let r2_40m = engine.bandRangeKHz(for: "40M", region: .region2)
        assert(r1_40m == 7000.0...7200.0, "Region 1 40m should be 7000-7200 kHz, got \(r1_40m)")
        assert(r2_40m == 7000.0...7300.0, "Region 2 40m should be 7000-7300 kHz, got \(r2_40m)")

        // 80M: Region 1 is 3.5 - 3.8 MHz, Region 2 is 3.5 - 4.0 MHz
        let r1_80m = engine.bandRangeKHz(for: "80M", region: .region1)
        let r2_80m = engine.bandRangeKHz(for: "80M", region: .region2)
        assert(r1_80m == 3500.0...3800.0, "Region 1 80m should be 3500-3800 kHz, got \(r1_80m)")
        assert(r2_80m == 3500.0...4000.0, "Region 2 80m should be 3500-4000 kHz, got \(r2_80m)")

        print("   ✅ IARU Region 1 (EP/EU) vs Region 2 (US) band bounds verified.")
    }

    // MARK: - 2. License Class Privilege Filtering
    @MainActor
    private static func testLicensePrivilegeFiltering() {
        print("🧪 Testing License Class Privilege Sub-Band Restrictions...")

        let engine = BandmapEngine.shared

        // In Region 2, 20m 14.101 - 14.225 is Extra-class exclusive
        let segmentsExtra = engine.bandPlanSegments(for: "20M", region: .region2, license: .extra)
        let extraPermitted = segmentsExtra.allSatisfy { $0.isPermitted(for: .extra) }
        assert(extraPermitted, "Extra class should have access to all segments")

        let segmentsGeneral = engine.bandPlanSegments(for: "20M", region: .region2, license: .general)
        let restrictedFound = segmentsGeneral.contains { !$0.isPermitted(for: .general) }
        assert(restrictedFound, "General class should have at least one restricted segment on 20M Region 2")

        print("   ✅ License privilege filtering correctly marks restricted sub-bands.")
    }

    // MARK: - 3. Dual VFO & Split Tracking
    @MainActor
    private static func testSplitTrackingAndOffset() {
        print("🧪 Testing Dual VFO and Split Offset Calculation...")

        let engine = BandmapEngine.shared
        engine.vfoAKHz = 14074.0
        engine.setSplit(active: true, offsetKHz: 2.5)

        assert(engine.isSplitActive, "Split mode should be active")
        assert(abs(engine.vfoBKHz - 14076.5) < 0.001, "VFO-B should be 14076.5 kHz, got \(engine.vfoBKHz)")
        assert(abs(engine.splitOffsetKHz - 2.5) < 0.001, "Split offset should be +2.5 kHz, got \(engine.splitOffsetKHz)")

        // Turn split off
        engine.setSplit(active: false)
        assert(!engine.isSplitActive, "Split mode should be disabled")

        print("   ✅ Dual VFO split offset math and state switching verified.")
    }

    // MARK: - 4. Activity Heatmap Density
    @MainActor
    private static func testActivityHeatmapDensity() {
        print("🧪 Testing Activity Heatmap Density Calculation...")

        let engine = BandmapEngine.shared
        engine.clearAllSpots()

        // Inject spots on 20M around 14074 kHz
        engine.addSpot(callsign: "W1AW", frequencyKHz: 14074.0, band: "20M", mode: "FT8")
        engine.addSpot(callsign: "JA1ZLO", frequencyKHz: 14075.0, band: "20M", mode: "FT8")
        engine.addSpot(callsign: "DL2026", frequencyKHz: 14076.0, band: "20M", mode: "FT8")

        let bins = engine.activityDensity(band: "20M", stepKHz: 25.0)
        assert(!bins.isEmpty, "Bins should not be empty for 20M")

        // The 14075 bin should have highest density
        let activeBin = bins.first { $0.freq == 14075.0 }
        assert(activeBin != nil && activeBin!.density > 0.0, "Bin 14075 should reflect spot concentration")

        print("   ✅ Activity heatmap ribbon bins computed accurately.")
    }

    // MARK: - 5. Temporal Spot Aging & Decay
    @MainActor
    private static func testSpotAgingAndTemporalDecay() {
        print("🧪 Testing Spot Age, Freshness (<120s), and Decay...")

        let freshSpot = BandmapSpot(
            callsign: "TEST1",
            frequencyKHz: 14010.0,
            band: "20M",
            mode: "CW",
            timestamp: Date()
        )
        assert(freshSpot.isFresh, "Newly created spot should be fresh")
        assert(freshSpot.opacity >= 0.99, "Fresh spot opacity should be ~1.0")

        let oldDate = Date().addingTimeInterval(-900) // 15 minutes ago
        let agedSpot = BandmapSpot(
            callsign: "TEST2",
            frequencyKHz: 14020.0,
            band: "20M",
            mode: "CW",
            timestamp: oldDate
        )
        assert(!agedSpot.isFresh, "15m spot should not be fresh")
        assert(agedSpot.ageMinutes >= 14, "Spot age should be ~15m")
        assert(agedSpot.opacity < 0.9, "Aged spot should have decayed opacity")

        print("   ✅ Temporal spot decay opacity and freshness verified.")
    }

    // MARK: - 6. WSJT-X / DX Cluster Spot Ingestion
    @MainActor
    private static func testWSJTXSpotIngestion() {
        print("🧪 Testing Real-Time Spot Ingestion & Prefix Resolution...")

        let engine = BandmapEngine.shared
        engine.addSpot(
            callsign: "EP2LMA",
            frequencyKHz: 14074.25,
            band: "20M",
            mode: "FT8",
            comment: "Grid: LL65",
            source: "WSJT-X",
            snr: -12
        )

        let found = engine.spots.first { $0.callsign == "EP2LMA" }
        assert(found != nil, "EP2LMA spot should be present in BandmapEngine")
        assert(found?.dxccPrefix == "EP2", "Prefix should be resolved as EP2, got \(String(describing: found?.dxccPrefix))")
        assert(found?.snr == -12, "SNR should be preserved as -12 dB")
        assert(found?.source == "WSJT-X", "Source should be WSJT-X")

        print("   ✅ Live spot ingestion and DXCC prefix mapping verified.")
    }
}
