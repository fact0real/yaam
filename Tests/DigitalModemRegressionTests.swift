//
//  DigitalModemRegressionTests.swift
//  YAAM Tests
//
//  Unit & Regression Tests for DigitalModemEngine (RTTY Baudot ITA2, PSK31 Varicode, Macros, Scope)
//

import Foundation
@testable import YAAM

@MainActor
public struct DigitalModemRegressionTests {
    public static func runAllTests() -> Bool {
        var passed = true

        func assertTest(_ condition: Bool, _ name: String) {
            if !condition {
                print("❌ FAIL: \(name)")
                passed = false
            } else {
                print("✅ PASS: \(name)")
            }
        }

        print("--- Starting Digital Modem (RTTY & PSK31) Regression Tests ---")

        // Test 1: Operating Mode baud rates & shifts
        assertTest(DigitalOperatingMode.rtty45_170.baudRate == 45.45, "RTTY 45.45 baud rate is 45.45")
        assertTest(DigitalOperatingMode.rtty45_170.shiftHz == 170.0, "RTTY 170 Hz shift")
        assertTest(DigitalOperatingMode.rtty75_170.baudRate == 75.0, "RTTY 75 baud rate is 75.0")
        assertTest(DigitalOperatingMode.rtty45_850.shiftHz == 850.0, "RTTY 850 Hz shift")
        assertTest(DigitalOperatingMode.psk31.baudRate == 31.25, "PSK31 baud rate is 31.25")
        assertTest(DigitalOperatingMode.rtty45_170.adifMode == "RTTY", "RTTY ADIF mode is RTTY")
        assertTest(DigitalOperatingMode.psk31.adifMode == "PSK31", "PSK31 ADIF mode is PSK31")

        // Test 2: Baudot ITA2 Letters & Figures Encoding/Decoding
        var encState: BaudotCodec.ShiftState = .letters
        let encQSO = BaudotCodec.encode(char: "C", currentState: &encState)
        assertTest(!encQSO.isEmpty, "Encoded letter C")

        var decState: BaudotCodec.ShiftState = .letters
        if let code = encQSO.last {
            let decC = BaudotCodec.decode(code: code, state: &decState, unshiftOnSpace: true)
            assertTest(decC == "C", "Decoded letter C correctly")
        }

        // Test Figures: Number "5"
        let enc5 = BaudotCodec.encode(char: "5", currentState: &encState)
        assertTest(enc5.contains(BaudotCodec.codeFIGS), "Shifted to FIGS for number 5")
        if let code5 = enc5.last {
            decState = .figures
            let dec5 = BaudotCodec.decode(code: code5, state: &decState, unshiftOnSpace: true)
            assertTest(dec5 == "5", "Decoded number 5 correctly")
        }

        // Test UOS (Unshift-On-Space)
        decState = .figures
        _ = BaudotCodec.decode(code: BaudotCodec.codeSpace, state: &decState, unshiftOnSpace: true)
        assertTest(decState == .letters, "UOS reset state from FIGS to LTRS on Space")

        // Test 3: Varicode (PSK31) Codec
        let variE = VaricodeCodec.encode(char: "e")
        assertTest(variE == "1100", "Varicode for 'e' is 11 terminated by 00")
        let variA = VaricodeCodec.encode(char: "a")
        assertTest(variA.hasSuffix("00"), "Varicode for 'a' has delimiter 00")

        let decE = VaricodeCodec.varicodeToAscii["11"]
        assertTest(decE == "e", "Decoded Varicode 11 to 'e'")

        // Test 4: Macro Template Expansion
        let engine = DigitalModemEngine.shared
        engine.myCallsign = "EP2YAAM"
        engine.targetCallsign = "W1AW"
        engine.targetReportSent = "599"
        engine.myGrid = "LL35"
        engine.targetSerial = 42

        let expCQ = engine.expandMacroTemplate("CQ CQ DE {MYCALL} K")
        assertTest(expCQ == "CQ CQ DE EP2YAAM K", "Expanded CQ macro with MYCALL")

        let expExch = engine.expandMacroTemplate("{CALL} {SENTRST} {SERIAL}")
        assertTest(expExch == "W1AW 599 042", "Expanded Exchange macro with CALL, SENTRST, SERIAL")

        // Test 5: Frequency & Tone Calculation
        engine.setCenterFrequency(1500.0)
        engine.operatingMode = .rtty45_170
        engine.afcEnabled = false
        engine.reversePolarity = false
        assertTest(abs(engine.effectiveMarkFrequency - 1415.0) < 0.1, "Mark frequency is 1415 Hz (1500 - 85)")
        assertTest(abs(engine.effectiveSpaceFrequency - 1585.0) < 0.1, "Space frequency is 1585 Hz (1500 + 85)")

        // Test Reverse Polarity
        engine.reversePolarity = true
        assertTest(abs(engine.effectiveMarkFrequency - 1585.0) < 0.1, "Reversed Mark frequency is 1585 Hz")
        assertTest(abs(engine.effectiveSpaceFrequency - 1415.0) < 0.1, "Reversed Space frequency is 1415 Hz")

        // Test 6: Target DX Selection & DXCC Resolution
        engine.selectTargetCallsign("JA1ABC")
        assertTest(engine.targetCountryName == "Japan", "Resolved JA1ABC country to Japan")
        assertTest(engine.targetCountryFlag == "🇯🇵", "Resolved JA1ABC flag to 🇯🇵")
        assertTest(engine.targetContinent == "AS", "Resolved JA1ABC continent to AS")

        // Test 7: Hellschreiber Engine & Font Specs
        let hell = HellschreiberEngine.shared
        assertTest(hell.centerFrequencyHz == 980.0, "Feld Hell standard carrier frequency is 980 Hz")
        let colA = HellFont.getColumns(for: "A")
        assertTest(colA.count == 7, "Hellschreiber glyph 'A' has exactly 7 pixel columns")
        hell.slantCorrectionPct = 2.5
        assertTest(hell.slantCorrectionPct == 2.5, "Slant calibration percentage set correctly")
        hell.tapeContrast = 1.8
        assertTest(hell.tapeContrast == 1.8, "Tape contrast set correctly")

        // Test 8: Olivia MFSK & Contestia Configurations & Walsh-Hadamard Math
        let olivia = OliviaMFSKEngine.shared
        assertTest(OliviaConfiguration.olivia16_500.toneCount == 16, "Olivia 16/500 has 16 tones")
        assertTest(OliviaConfiguration.olivia16_500.bandwidthHz == 500.0, "Olivia 16/500 bandwidth is 500 Hz")
        assertTest(OliviaConfiguration.olivia8_250.toneCount == 8, "Olivia 8/250 has 8 tones")
        assertTest(OliviaConfiguration.olivia8_250.bandwidthHz == 250.0, "Olivia 8/250 bandwidth is 250 Hz")
        assertTest(OliviaConfiguration.contestia8_250.isContestia == true, "Contestia 8/250 identified as Contestia")
        olivia.config = .olivia16_500
        assertTest(abs(olivia.config.toneSpacingHz - (500.0 / 16.0)) < 0.01, "Olivia 16/500 tone spacing is 31.25 Hz")
        let tone0 = olivia.toneFrequency(at: 0)
        let tone15 = olivia.toneFrequency(at: 15)
        let diffTones: Double = tone15 - tone0
        assertTest(abs(diffTones - (15.0 * 31.25)) < 0.1, "Olivia tone spread spans correct subcarrier range")

        // Test 9: JS8 / JS8Call 8-GFSK Submodes & Station Roster
        assertTest(JS8Speed.normal.frameSeconds == 15.0, "JS8 Normal slot is 15 seconds")
        assertTest(JS8Speed.fast.frameSeconds == 10.0, "JS8 Fast slot is 10 seconds")
        assertTest(JS8Speed.turbo.frameSeconds == 6.0, "JS8 Turbo slot is 6 seconds")
        assertTest(JS8Speed.slow.frameSeconds == 30.0, "JS8 Slow slot is 30 seconds")
        
        let stEntry = JS8StationEntry(callsign: "DL1ABC", grid: "JO42", snrDb: -6, countryFlag: "🇩🇪", countryName: "Germany", audioFreqHz: 1500)
        assertTest(stEntry.callsign == "DL1ABC" && stEntry.snrDb == -6, "JS8 Station Roster entry constructed")

        // Test 10: SSTV Modes & VIS Header Codes
        assertTest(SSTVMode.robot36.visCode == 8, "Robot 36 VIS code is 8")
        assertTest(SSTVMode.martinM1.visCode == 44, "Martin M1 VIS code is 44")
        assertTest(SSTVMode.scottieS1.visCode == 60, "Scottie S1 VIS code is 60")
        assertTest(SSTVMode.robot36.width == 320 && SSTVMode.robot36.height == 240, "Robot 36 resolution is 320x240")
        assertTest(SSTVMode.martinM1.width == 320 && SSTVMode.martinM1.height == 256, "Martin M1 resolution is 320x256")
        assertTest(SSTVMode.martinM1.durationSeconds == 114.0, "Martin M1 duration is 114 seconds")

        print("--- Digital Modem Regression Tests Completed: \(passed ? "ALL PASSED" : "FAILED") ---")
        return passed
    }
}

MainActor.assumeIsolated {
    let success = DigitalModemRegressionTests.runAllTests()
    exit(success ? 0 : 1)
}
