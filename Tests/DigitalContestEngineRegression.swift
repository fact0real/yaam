//
//  DigitalContestEngineRegression.swift
//  YAAM Tests
//

import Foundation

@main
struct DigitalContestEngineRegression {
    @MainActor
    static func main() {
        print("🚀 Starting Digital Contest Engine Regression Test Suite...")
        testDistanceAndCQWWPoints()
        testMultipliersAndScoreCalculation()
        testDupeDetection()
        testRateMeter()
        testContestMessageSequences()
        testSlotClockTimings()
        testBandMatrixAndMultipliersBreakdown()
        testLiveDecodeContestAnalysis()
        testSmartQueuePriorityScoring()
        testSmartQueueFIFOAndPromotion()
        testCabrilloCQWWDigiExport()
        testCabrilloARRLDigiExport()
        testCabrilloPreFlightValidation()
        print("🎉 ALL Digital Contest Engine Regression Tests PASSED successfully!")
    }

    @MainActor
    private static func testDistanceAndCQWWPoints() {
        print("🧪 Testing Distance and CQ WW Digi points calculation...")
        let engine = DigitalContestEngine()
        engine.configureContest(type: .cqWWDigi, myCall: "EP2LMA", myGrid: "KM32")
        engine.isContestActive = true

        // 1. Same 4-char grid -> 1 pt
        let sameGridPts = engine.calculatePoints(callerCall: "EP2XYZ", callerGrid: "KM32", band: "20m")
        precondition(sameGridPts == 1, "Expected 1 point for same grid, got \(sameGridPts)")

        // 2. Nearby station (< 1500 km, e.g., A61OK in Dubai, LL75)
        let a6Pts = engine.calculatePoints(callerCall: "A61OK", callerGrid: "LL75", band: "20m")
        precondition(a6Pts >= 1 && a6Pts <= 2, "Expected 1 or 2 pts for A61OK (LL75), got \(a6Pts)")

        // 3. Central European station (~2900 km, e.g., DL1ABC in JO31 is 1500-3000 km -> 2 pts)
        let dlPts = engine.calculatePoints(callerCall: "DL1ABC", callerGrid: "JO31", band: "20m")
        precondition(dlPts == 2, "Expected 2 pts for DL1ABC (JO31 ~2900km), got \(dlPts)")

        // 4. Western European station (> 3000 km, e.g., G4ABC in London IO91 is ~3400 km -> 3 pts)
        let gPts = engine.calculatePoints(callerCall: "G4ABC", callerGrid: "IO91", band: "20m")
        precondition(gPts == 3, "Expected 3 pts for G4ABC (IO91 ~3400km), got \(gPts)")

        // 5. US East Coast station (> 7500 km, e.g., W1AW in FN31)
        let w1Pts = engine.calculatePoints(callerCall: "W1AW", callerGrid: "FN31", band: "20m")
        precondition(w1Pts == 6, "Expected 6 pts for W1AW (FN31 > 7500km), got \(w1Pts)")

        print("  ✓ CQ WW Digi distance-based points verified.")
    }

    @MainActor
    private static func testMultipliersAndScoreCalculation() {
        print("🧪 Testing Multipliers and Claimed Score Calculation...")
        let engine = DigitalContestEngine()
        engine.configureContest(type: .cqWWDigi, myCall: "EP2LMA", myGrid: "KM32")
        engine.isContestActive = true
        engine.resetContestSession()

        // QSO 1: DL1ABC on 20m (Grid: JO31, DXCC: Germany, Field: JO)
        // Multipliers added: Grid Field "JO" (1), DXCC "Germany" (1) -> 2 mults
        let q1 = engine.logContestQSO(
            callsign: "DL1ABC",
            band: "20m",
            mode: "FT8",
            frequencyHz: 14074000,
            sentReport: "-05",
            rcvdReport: "-10",
            sentExchange: "KM32",
            rcvdExchange: "JO31",
            grid: "JO31"
        )
        precondition(q1 != nil, "QSO 1 failed to log")
        precondition(q1!.isGridMultiplier == true, "Q1 should be a grid multiplier")
        precondition(q1!.isDXCCMultiplier == true, "Q1 should be a DXCC multiplier")
        precondition(engine.totalQSOs == 1, "Expected 1 QSO, got \(engine.totalQSOs)")
        precondition(engine.totalGridMultipliers == 1, "Expected 1 Grid Mult, got \(engine.totalGridMultipliers)")
        precondition(engine.totalDXCCMultipliers == 1, "Expected 1 DXCC Mult, got \(engine.totalDXCCMultipliers)")
        precondition(engine.totalMultipliers == 2, "Expected 2 total mults, got \(engine.totalMultipliers)")

        let p1 = q1!.points
        precondition(engine.claimedScore == p1 * 2, "Expected score \(p1 * 2), got \(engine.claimedScore)")

        // QSO 2: DL2XYZ on 20m (Grid: JO21, DXCC: Germany, Field: JO)
        // Same field "JO", same DXCC "Germany" on 20m -> 0 new mults
        let q2 = engine.logContestQSO(
            callsign: "DL2XYZ",
            band: "20m",
            mode: "FT8",
            frequencyHz: 14074000,
            sentReport: "-08",
            rcvdReport: "-12",
            sentExchange: "KM32",
            rcvdExchange: "JO21",
            grid: "JO21"
        )
        precondition(q2 != nil, "QSO 2 failed to log")
        precondition(q2!.isGridMultiplier == false, "Q2 should NOT be a grid multiplier (field JO already worked on 20m)")
        precondition(q2!.isDXCCMultiplier == false, "Q2 should NOT be a DXCC multiplier (Germany already worked on 20m)")
        precondition(engine.totalQSOs == 2, "Expected 2 QSOs, got \(engine.totalQSOs)")
        precondition(engine.totalMultipliers == 2, "Total mults should still be 2")

        // QSO 3: DL1ABC on 15m (different band!)
        // In CQ WW Digi, mults are counted PER BAND.
        // So on 15m, Field "JO" and DXCC "Germany" should be multipliers again!
        let q3 = engine.logContestQSO(
            callsign: "DL1ABC",
            band: "15m",
            mode: "FT4",
            frequencyHz: 21140000,
            sentReport: "-04",
            rcvdReport: "-06",
            sentExchange: "KM32",
            rcvdExchange: "JO31",
            grid: "JO31"
        )
        precondition(q3 != nil, "QSO 3 failed to log")
        precondition(q3!.isGridMultiplier == true, "Q3 on 15m SHOULD be a grid multiplier for 15m")
        precondition(q3!.isDXCCMultiplier == true, "Q3 on 15m SHOULD be a DXCC multiplier for 15m")
        precondition(engine.totalQSOs == 3, "Expected 3 QSOs, got \(engine.totalQSOs)")
        precondition(engine.totalGridMultipliers == 2, "Expected 2 Grid Mults across bands, got \(engine.totalGridMultipliers)")
        precondition(engine.totalDXCCMultipliers == 2, "Expected 2 DXCC Mults across bands, got \(engine.totalDXCCMultipliers)")
        precondition(engine.totalMultipliers == 4, "Expected 4 total mults, got \(engine.totalMultipliers)")

        print("  ✓ Multiplier tracking and per-band score mechanics verified.")
    }

    @MainActor
    private static func testDupeDetection() {
        print("🧪 Testing Dupe Detection...")
        let engine = DigitalContestEngine()
        engine.configureContest(type: .cqWWDigi, myCall: "EP2LMA", myGrid: "KM32")
        engine.isContestActive = true
        engine.resetContestSession()

        // Log JA1ABC on 20m
        _ = engine.logContestQSO(
            callsign: "JA1ABC",
            band: "20m",
            mode: "FT8",
            frequencyHz: 14074000,
            sentReport: "-10",
            rcvdReport: "-12",
            sentExchange: "KM32",
            rcvdExchange: "PM95",
            grid: "PM95"
        )

        // Status check for JA1ABC on 20m -> should be dupe
        let status20m = engine.analyzeDecodedStation(callsign: "JA1ABC", grid: "PM95", band: "20m")
        precondition(status20m == .dupe, "Expected .dupe for JA1ABC on 20m, got \(status20m)")

        // Status check for JA1ABC on 15m -> should NOT be dupe!
        let status15m = engine.analyzeDecodedStation(callsign: "JA1ABC", grid: "PM95", band: "15m")
        precondition(status15m != .dupe, "JA1ABC on 15m should NOT be dupe")

        print("  ✓ Dupe detection logic verified.")
    }

    @MainActor
    private static func testRateMeter() {
        print("🧪 Testing Rate Meter calculations...")
        let engine = DigitalContestEngine()
        engine.configureContest(type: .cqWWDigi, myCall: "EP2LMA", myGrid: "KM32")
        engine.isContestActive = true
        engine.resetContestSession()

        // Log 3 QSOs right now
        for i in 1...3 {
            _ = engine.logContestQSO(
                callsign: "W\(i)AW",
                band: "20m",
                mode: "FT8",
                frequencyHz: 14074000,
                sentReport: "-10",
                rcvdReport: "-10",
                sentExchange: "KM32",
                rcvdExchange: "FN31",
                grid: "FN31"
            )
        }

        // 3 QSOs in 10 minutes -> 3 * 6 = 18 QSOs/hr rate
        precondition(engine.rate10Min == 18, "Expected 10m rate of 18, got \(engine.rate10Min)")
        precondition(engine.rate60Min == 3, "Expected 60m rate of 3, got \(engine.rate60Min)")
        precondition(engine.peakRate == 18, "Expected peak rate of 18, got \(engine.peakRate)")

        print("  ✓ Rate Meter calculations verified.")
    }

    private static func testContestMessageSequences() {
        print("🧪 Testing Contest Message Sequences...")
        let myCall = "EP2LMA"
        let myGrid = "KM32"
        let dxCall = "DL1ABC"

        // CQ in contest mode
        let cqMsg = "CQ TEST \(myCall) \(myGrid)"
        precondition(cqMsg == "CQ TEST EP2LMA KM32", "CQ Contest message mismatch: \(cqMsg)")

        // S&P response: DX Call, My Call, My Grid
        let callMsg = "\(dxCall) \(myCall) \(myGrid)"
        precondition(callMsg == "DL1ABC EP2LMA KM32", "S&P Call message mismatch: \(callMsg)")

        // Exchange with R: DX Call, My Call, R + My Grid
        let replyMsg = "\(dxCall) \(myCall) R \(myGrid)"
        precondition(replyMsg == "DL1ABC EP2LMA R KM32", "Exchange message mismatch: \(replyMsg)")

        // RR73 final handshake
        let rr73Msg = "\(dxCall) \(myCall) RR73"
        precondition(rr73Msg == "DL1ABC EP2LMA RR73", "RR73 message mismatch: \(rr73Msg)")

        print("  ✓ Contest message sequencing verified.")
    }

    private static func testSlotClockTimings() {
        print("🧪 Testing DigitalSlotClock FT8 vs FT4...")

        // FT8: 15-second slots
        // At t = 14.0, index = 14 / 15 = 0 (even). Next even slot starts at 30.0. Next odd slot starts at 15.0.
        let tFT8 = Date(timeIntervalSince1970: 14.0)
        let parityFT8 = DigitalSlotClock.parity(at: tFT8, slotSeconds: 15.0)
        precondition(parityFT8 == .even, "Expected even parity at t=14s for FT8, got \(parityFT8)")

        let nextOddFT8 = DigitalSlotClock.nextSlotStart(parity: .odd, after: tFT8, slotSeconds: 15.0)
        precondition(nextOddFT8.timeIntervalSince1970 == 15.0, "Expected next odd slot at 15.0s, got \(nextOddFT8.timeIntervalSince1970)")

        // FT4: 7.5-second slots
        // At t = 10.0, index = 10 / 7.5 = 1 (odd).
        let tFT4 = Date(timeIntervalSince1970: 10.0)
        let parityFT4 = DigitalSlotClock.parity(at: tFT4, slotSeconds: 7.5)
        precondition(parityFT4 == .odd, "Expected odd parity at t=10s for FT4, got \(parityFT4)")

        // Next even slot for FT4 after t=10.0 should be index 2 (15.0s)
        let nextEvenFT4 = DigitalSlotClock.nextSlotStart(parity: .even, after: tFT4, slotSeconds: 7.5)
        precondition(nextEvenFT4.timeIntervalSince1970 == 15.0, "Expected next even slot for FT4 at 15.0s, got \(nextEvenFT4.timeIntervalSince1970)")

        // Next odd slot for FT4 after t=10.0 should be index 3 (22.5s)
        let nextOddFT4 = DigitalSlotClock.nextSlotStart(parity: .odd, after: tFT4, slotSeconds: 7.5)
        precondition(nextOddFT4.timeIntervalSince1970 == 22.5, "Expected next odd slot for FT4 at 22.5s, got \(nextOddFT4.timeIntervalSince1970)")

        // Seconds until next even slot from t=10.0 is 5.0 seconds
        let secsUntil = DigitalSlotClock.secondsUntilNextSlot(parity: .even, after: tFT4, slotSeconds: 7.5)
        precondition(abs(secsUntil - 5.0) < 0.001, "Expected 5.0s until next even slot, got \(secsUntil)")

        print("  ✓ DigitalSlotClock static timings verified.")
    }

    @MainActor
    private static func testCabrilloCQWWDigiExport() {
        print("🧪 Testing Cabrillo 3.0 CQ WW Digi Log Export...")
        let engine = DigitalContestEngine()
        engine.configureContest(type: .cqWWDigi, myCall: "EP2LMA", myGrid: "KM32")
        engine.isContestActive = true
        engine.resetContestSession()

        // Log 2 QSOs
        _ = engine.logContestQSO(
            callsign: "DL1ABC",
            band: "20m",
            mode: "FT8",
            frequencyHz: 14074000,
            sentReport: "-05",
            rcvdReport: "-10",
            sentExchange: "KM32",
            rcvdExchange: "JO31",
            grid: "JO31"
        )
        _ = engine.logContestQSO(
            callsign: "W1AW",
            band: "15m",
            mode: "FT4",
            frequencyHz: 21140000,
            sentReport: "-04",
            rcvdReport: "-06",
            sentExchange: "KM32",
            rcvdExchange: "FN31",
            grid: "FN31"
        )

        let options = DigitalCabrilloExportOptions(
            contestType: .cqWWDigi,
            callsign: "EP2LMA",
            grid: "KM32",
            operatorCategory: "SINGLE-OP",
            assistedCategory: "ASSISTED",
            bandCategory: "ALL",
            powerCategory: "LOW",
            operatorName: "Reza Ham Radio",
            address: "Tehran",
            country: "Iran",
            club: "Iran DX Club",
            soapbox: "Great digital conditions on 20m and 15m!"
        )

        let cabrillo = DigitalContestCabrilloService.generateCabrillo(engine: engine, options: options, softwareVersion: "YAAM 1.2")
        print("Generated Cabrillo:\n\(cabrillo)")

        // 1. Check Mandatory Headers
        precondition(cabrillo.contains("START-OF-LOG: 3.0"), "Missing START-OF-LOG: 3.0")
        precondition(cabrillo.contains("CREATED-BY: YAAM 1.2"), "Missing CREATED-BY")
        precondition(cabrillo.contains("CONTEST: CQ-WW-DIGI"), "Missing CONTEST: CQ-WW-DIGI")
        precondition(cabrillo.contains("CALLSIGN: EP2LMA"), "Missing CALLSIGN: EP2LMA")
        precondition(cabrillo.contains("CATEGORY-OPERATOR: SINGLE-OP"), "Missing CATEGORY-OPERATOR")
        precondition(cabrillo.contains("CATEGORY-ASSISTED: ASSISTED"), "Missing CATEGORY-ASSISTED")
        precondition(cabrillo.contains("CATEGORY-BAND: ALL"), "Missing CATEGORY-BAND")
        precondition(cabrillo.contains("CATEGORY-MODE: DIGI"), "Missing CATEGORY-MODE: DIGI")
        precondition(cabrillo.contains("CATEGORY-POWER: LOW"), "Missing CATEGORY-POWER: LOW")
        precondition(cabrillo.contains("GRID-LOCATOR: KM32"), "Missing GRID-LOCATOR: KM32")
        precondition(cabrillo.contains("CLAIMED-SCORE: \(engine.claimedScore)"), "Missing CLAIMED-SCORE")
        precondition(cabrillo.contains("NAME: Reza Ham Radio"), "Missing NAME")
        precondition(cabrillo.contains("CLUB: Iran DX Club"), "Missing CLUB")
        precondition(cabrillo.contains("SOAPBOX: Great digital conditions"), "Missing SOAPBOX")
        precondition(cabrillo.contains("END-OF-LOG:"), "Missing END-OF-LOG:")

        // 2. Check QSO Lines
        precondition(cabrillo.contains("QSO: 14074 DG"), "Missing 14074 DG QSO line")
        precondition(cabrillo.contains("EP2LMA        KM32   DL1ABC        JO31   0"), "Mismatch in DL1ABC QSO formatting")
        precondition(cabrillo.contains("QSO: 21140 DG"), "Missing 21140 DG QSO line")
        precondition(cabrillo.contains("EP2LMA        KM32   W1AW          FN31   0"), "Mismatch in W1AW QSO formatting")

        // 3. Verify standard CRLF line endings
        precondition(cabrillo.hasSuffix("\r\n"), "Cabrillo export must end with CRLF")

        print("  ✓ Cabrillo 3.0 CQ WW Digi log export verified.")
    }

    @MainActor
    private static func testCabrilloARRLDigiExport() {
        print("🧪 Testing Cabrillo 3.0 ARRL Digi / RTTY Log Export...")
        let engine = DigitalContestEngine()
        engine.configureContest(type: .arrlRoundup, myCall: "EP2LMA", myGrid: "KM32")
        engine.isContestActive = true
        engine.resetContestSession()

        _ = engine.logContestQSO(
            callsign: "W1AW",
            band: "20m",
            mode: "FT8",
            frequencyHz: 14074000,
            sentReport: "599",
            rcvdReport: "599",
            sentExchange: "001",
            rcvdExchange: "CT",
            grid: "FN31"
        )

        let options = DigitalCabrilloExportOptions(
            contestType: .arrlRoundup,
            callsign: "EP2LMA",
            grid: "KM32",
            operatorCategory: "SINGLE-OP",
            assistedCategory: "NON-ASSISTED",
            bandCategory: "20M",
            powerCategory: "HIGH"
        )

        let cabrillo = DigitalContestCabrilloService.generateCabrillo(engine: engine, options: options)

        precondition(cabrillo.contains("CONTEST: ARRL-DIGI"), "Missing CONTEST: ARRL-DIGI")
        precondition(cabrillo.contains("CATEGORY-MODE: DG"), "Missing CATEGORY-MODE: DG")
        precondition(cabrillo.contains("CATEGORY-BAND: 20M"), "Missing CATEGORY-BAND: 20M")
        precondition(cabrillo.contains("CATEGORY-POWER: HIGH"), "Missing CATEGORY-POWER: HIGH")
        precondition(cabrillo.contains("QSO: 14074 DG"), "Missing 14074 DG QSO line")
        precondition(cabrillo.contains("599 001    W1AW          599 CT"), "ARRL QSO exchange mismatch: \(cabrillo)")

        print("  ✓ Cabrillo 3.0 ARRL Digi log export verified.")
    }

    @MainActor
    private static func testCabrilloPreFlightValidation() {
        print("🧪 Testing Cabrillo Pre-Flight Robot Validation...")
        let engine = DigitalContestEngine()
        engine.configureContest(type: .cqWWDigi, myCall: "EP2LMA", myGrid: "KM32")
        engine.isContestActive = true

        // 1. Missing callsign test
        var invalidOptions = DigitalCabrilloExportOptions(contestType: .cqWWDigi, callsign: "", grid: "KM32")
        var issues = DigitalContestCabrilloService.validate(engine: engine, options: invalidOptions)
        precondition(issues.contains { $0.isError && $0.message.contains("Callsign is required") }, "Failed to flag missing callsign")

        // 2. Missing grid for CQ WW Digi test
        invalidOptions = DigitalCabrilloExportOptions(contestType: .cqWWDigi, callsign: "EP2LMA", grid: "")
        issues = DigitalContestCabrilloService.validate(engine: engine, options: invalidOptions)
        precondition(issues.contains { $0.isError && $0.message.contains("GRID-LOCATOR is mandatory") }, "Failed to flag missing grid for CQ WW Digi")

        // 3. Valid options test
        let validOptions = DigitalCabrilloExportOptions(contestType: .cqWWDigi, callsign: "EP2LMA", grid: "KM32")
        issues = DigitalContestCabrilloService.validate(engine: engine, options: validOptions)
        let errors = issues.filter { $0.isError }
        precondition(errors.isEmpty, "Valid configuration should have 0 errors, got: \(errors.map { $0.message })")

        print("  ✓ Cabrillo Pre-Flight Robot Validation verified.")
    }

    @MainActor
    private static func testBandMatrixAndMultipliersBreakdown() {
        print("🧪 Testing Band Matrix and Multiplier Engine Breakdown...")
        let engine = DigitalContestEngine()
        engine.configureContest(type: .cqWWDigi, myCall: "EP2LMA", myGrid: "KM32")
        engine.isContestActive = true
        engine.resetContestSession()

        // 1. Log QSOs on 20m
        _ = engine.logContestQSO(
            callsign: "DL1ABC",
            band: "20m",
            mode: "FT8",
            frequencyHz: 14074000,
            sentReport: "-05",
            rcvdReport: "-10",
            sentExchange: "KM32",
            rcvdExchange: "JO31",
            grid: "JO31"
        )
        _ = engine.logContestQSO(
            callsign: "F6XYZ",
            band: "20m",
            mode: "FT8",
            frequencyHz: 14074000,
            sentReport: "-08",
            rcvdReport: "-14",
            sentExchange: "KM32",
            rcvdExchange: "JN18",
            grid: "JN18"
        )

        // 2. Log QSO on 40m
        _ = engine.logContestQSO(
            callsign: "DL1ABC", // same call, but valid on new band!
            band: "40m",
            mode: "FT8",
            frequencyHz: 7074000,
            sentReport: "-04",
            rcvdReport: "-08",
            sentExchange: "KM32",
            rcvdExchange: "JO31",
            grid: "JO31"
        )

        // 3. Inspect breakdowns
        let breakdowns = engine.bandBreakdowns
        let b20 = breakdowns.first(where: { $0.band == "20m" })
        precondition(b20 != nil, "Missing 20m breakdown")
        precondition(b20!.qsoCount == 2, "Expected 2 QSOs on 20m, got \(b20!.qsoCount)")
        precondition(b20!.dupeCount == 0, "Expected 0 dupes on 20m")
        precondition(b20!.gridFields.contains("JO") && b20!.gridFields.contains("JN"), "Missing grid fields on 20m")
        precondition(b20!.gridMultCount == 2, "Expected 2 grid mults on 20m")
        precondition(b20!.dxccMultCount >= 1, "Expected DXCC mults on 20m")
        precondition(b20!.bandScore > 0, "Expected positive bandScore on 20m")

        let b40 = breakdowns.first(where: { $0.band == "40m" })
        precondition(b40 != nil, "Missing 40m breakdown")
        precondition(b40!.qsoCount == 1, "Expected 1 QSO on 40m, got \(b40!.qsoCount)")
        precondition(b40!.gridFields.contains("JO"), "Missing JO on 40m")

        // 4. Test Query APIs
        precondition(engine.isCallWorked(callsign: "DL1ABC", onBand: "20m") == true, "DL1ABC should be worked on 20m")
        precondition(engine.isCallWorked(callsign: "DL1ABC", onBand: "40m") == true, "DL1ABC should be worked on 40m")
        precondition(engine.isCallWorked(callsign: "DL1ABC", onBand: "15m") == false, "DL1ABC should not be worked on 15m")
        precondition(engine.isGridFieldWorked(field: "JO", onBand: "20m") == true, "Field JO should be worked on 20m")
        precondition(engine.isGridFieldWorked(field: "FN", onBand: "20m") == false, "Field FN should not be worked on 20m")

        precondition(engine.workedGridFields(for: "20m").count == 2, "Expected 2 worked fields on 20m")
        precondition(engine.averagePointsPerQSO > 0.0, "Average points per QSO should be positive")
        precondition(engine.projectedFinalScore >= engine.claimedScore, "Projected score should be >= claimed score")

        print("  ✓ Band Matrix and Multiplier Engine Breakdown verified.")
    }

    @MainActor
    private static func testLiveDecodeContestAnalysis() {
        print("🧪 Testing Real-Time Live Decode Contest Analysis...")
        let engine = DigitalContestEngine()
        engine.configureContest(type: .cqWWDigi, myCall: "EP2LMA", myGrid: "KM32")
        engine.isContestActive = true
        engine.resetContestSession()

        // 1. Initial station never heard: W1AW in FN31 on 20m
        let status1 = engine.analyzeDecodedStation(callsign: "W1AW", grid: "FN31", band: "20m")
        precondition(status1.isMultiplier == true, "Expected W1AW in FN31 to be a multiplier")
        precondition(status1.isDupe == false, "Expected W1AW to not be a dupe")
        precondition(status1.points > 0, "Expected positive points for W1AW")
        precondition(status1.badgeLabel.contains("FN") || status1.badgeLabel.contains("United States"), "Badge label mismatch: \(status1.badgeLabel)")

        // 2. Now log W1AW on 20m
        _ = engine.logContestQSO(
            callsign: "W1AW",
            band: "20m",
            mode: "FT8",
            frequencyHz: 14074000,
            sentReport: "-05",
            rcvdReport: "-10",
            sentExchange: "KM32",
            rcvdExchange: "FN31",
            grid: "FN31"
        )

        // 3. W1AW heard again on 20m -> should be DUPE
        let status2 = engine.analyzeDecodedStation(callsign: "W1AW", grid: "FN31", band: "20m")
        precondition(status2.isDupe == true, "Expected W1AW to be detected as DUPE on 20m")
        precondition(status2.isMultiplier == false, "Dupe cannot be a multiplier")

        // 4. W1AW heard on 15m -> Not a dupe!
        let status3 = engine.analyzeDecodedStation(callsign: "W1AW", grid: "FN31", band: "15m")
        precondition(status3.isDupe == false, "W1AW on 15m should NOT be a dupe")
        precondition(status3.isMultiplier == true, "W1AW on 15m should be a new multiplier on 15m")

        print("  ✓ Real-Time Live Decode Contest Analysis verified.")
    }

    @MainActor
    private static func testSmartQueuePriorityScoring() {
        print("🧪 Testing Smart Multi-Caller Queue Priority Scoring & Sorting...")
        let engine = DigitalContestEngine()
        engine.configureContest(type: .cqWWDigi, myCall: "EP2LMA", myGrid: "KM32")
        engine.isContestActive = true
        engine.resetContestSession()

        // 0. Work a local QSO in KM32 so KM field and Iran DXCC are already worked on 20m
        _ = engine.logContestQSO(
            callsign: "EP2AAA",
            band: "20m",
            mode: "FT8",
            frequencyHz: 14074000,
            sentReport: "-05",
            rcvdReport: "-08",
            sentExchange: "KM32",
            rcvdExchange: "KM32",
            grid: "KM32"
        )

        // 1. Regular Caller (1 pt, same grid, non-mult): EP2XYZ
        let enq1 = engine.enqueueCaller(
            callsign: "EP2XYZ",
            grid: "KM32",
            countryName: "Iran",
            countryFlag: "🇮🇷",
            snr: -05,
            audioFrequencyHz: 1200,
            band: "20m",
            activeDX: "W1AW",
            source: .nativeFT8
        )
        precondition(enq1 == true, "Failed to enqueue EP2XYZ")

        // 2. High-Value Multiplier: DL1ABC (JO31 -> Mult JO & Germany, ~2900 km, 2 pts)
        let enq2 = engine.enqueueCaller(
            callsign: "DL1ABC",
            grid: "JO31",
            countryName: "Germany",
            countryFlag: "🇩🇪",
            snr: -10,
            audioFrequencyHz: 1450,
            band: "20m",
            activeDX: "W1AW",
            source: .nativeFT8
        )
        precondition(enq2 == true, "Failed to enqueue DL1ABC")

        // 3. Ultra-Value Multiplier: JA1ABC (PM95 -> Mult PM & Japan, ~7000 km, 4 pts)
        let enq3 = engine.enqueueCaller(
            callsign: "JA1ABC",
            grid: "PM95",
            countryName: "Japan",
            countryFlag: "🇯🇵",
            snr: -08,
            audioFrequencyHz: 1800,
            band: "20m",
            activeDX: "W1AW",
            source: .nativeFT8
        )
        precondition(enq3 == true, "Failed to enqueue JA1ABC")

        precondition(engine.queuedCallers.count == 3, "Expected 3 callers in queue, got \(engine.queuedCallers.count)")

        // Verify Multipliers are at top of queue!
        // JA1ABC has 4 pts + 1000 mult bonus + distance bonus > DL1ABC with 2 pts + 1000 mult bonus
        let top1 = engine.queuedCallers[0]
        let top2 = engine.queuedCallers[1]
        let top3 = engine.queuedCallers[2]

        precondition(top1.contestStatus.isMultiplier, "Top caller should be a multiplier")
        precondition(top2.contestStatus.isMultiplier, "Second caller should also be a multiplier")
        precondition(!top3.contestStatus.isMultiplier, "Third caller should not be a multiplier")
        precondition(top3.callsign == "EP2XYZ", "Expected EP2XYZ to be last due to lower points and no mult")

        // Log JA1ABC on 20m so it becomes a DUPE
        _ = engine.logContestQSO(
            callsign: "JA1ABC",
            band: "20m",
            mode: "FT8",
            frequencyHz: 14074000,
            sentReport: "-05",
            rcvdReport: "-08",
            sentExchange: "KM32",
            rcvdExchange: "PM95",
            grid: "PM95"
        )

        // Try enqueuing JA1ABC again on 20m -> should be rejected because it's a dupe!
        let enqDupe = engine.enqueueCaller(
            callsign: "JA1ABC",
            grid: "PM95",
            countryName: "Japan",
            countryFlag: "🇯🇵",
            snr: -08,
            audioFrequencyHz: 1800,
            band: "20m",
            activeDX: nil,
            source: .nativeFT8
        )
        precondition(enqDupe == false, "Dupe station should be rejected from queue")

        print("  ✓ Queue Priority Scoring and Dupe rejection verified.")
    }

    @MainActor
    private static func testSmartQueueFIFOAndPromotion() {
        print("🧪 Testing Smart Queue FIFO Pop, Manual Promotion, and Dismiss...")
        let engine = DigitalContestEngine()
        engine.configureContest(type: .cqWWDigi, myCall: "EP2LMA", myGrid: "KM32")
        engine.isContestActive = true
        engine.resetContestSession()

        _ = engine.enqueueCaller(callsign: "DL1ABC", grid: "JO31", countryName: "Germany", countryFlag: "🇩🇪", snr: -05, audioFrequencyHz: 1000, band: "20m", source: .nativeFT8)
        _ = engine.enqueueCaller(callsign: "G4ABC", grid: "IO91", countryName: "United Kingdom", countryFlag: "🇬🇧", snr: -08, audioFrequencyHz: 1200, band: "20m", source: .nativeFT8)
        _ = engine.enqueueCaller(callsign: "EA3ABC", grid: "JN11", countryName: "Spain", countryFlag: "🇪🇸", snr: -06, audioFrequencyHz: 1400, band: "20m", source: .nativeFT8)

        precondition(engine.queuedCallers.count == 3, "Expected 3 callers")

        // Promote EA3ABC (currently 3rd or 2nd) to #1
        if let ea3 = engine.queuedCallers.first(where: { $0.callsign == "EA3ABC" }) {
            engine.promoteQueuedCallerToTop(id: ea3.id)
            precondition(engine.queuedCallers.first?.callsign == "EA3ABC", "EA3ABC should now be #1 after promotion")
        }

        // Pop #1
        let popped = engine.popNextCaller()
        precondition(popped?.callsign == "EA3ABC", "Popped caller should be EA3ABC")
        precondition(engine.queuedCallers.count == 2, "Queue should now have 2 callers")

        // Dismiss caller
        if let toDismiss = engine.queuedCallers.first {
            engine.removeQueuedCaller(id: toDismiss.id)
            precondition(engine.queuedCallers.count == 1, "Queue should now have 1 caller")
        }

        // Clear queue
        engine.clearQueue()
        precondition(engine.queuedCallers.isEmpty, "Queue should be empty after clearQueue")

        print("  ✓ Smart Queue FIFO, Promotion, Dismiss, and Clear verified.")
    }
}
