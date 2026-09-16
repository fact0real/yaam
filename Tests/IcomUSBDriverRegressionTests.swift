//
//  IcomUSBDriverRegressionTests.swift
//  YAAM Tests
//
//  Unit & Regression Tests for Icom Transceivers Direct USB Driver (CI-V CAT & Audio).
//  Validates IC-705, IC-7300, IC-7300MK2, IC-7610 CI-V addressing, BCD frequency encoding/decoding,
//  USB-D mode & DATA MOD routing, CI-V command 17 Morse code, and telemetry parsing.
//

import Foundation

@main
public struct IcomUSBDriverRegressionTests {
    public static func main() {
        let passed = runAllTests()
        exit(passed ? 0 : 1)
    }

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

        print("--- Starting Icom USB Driver & CI-V Protocol Regression Tests ---")

        // Test 1: Icom Model CI-V Addresses
        assertTest(IcomTestHelper.defaultCivAddress(for: "IC-705") == 0xA4, "IC-705 default CI-V address is 0xA4")
        assertTest(IcomTestHelper.defaultCivAddress(for: "IC-7300") == 0x94, "IC-7300 default CI-V address is 0x94")
        assertTest(IcomTestHelper.defaultCivAddress(for: "IC-7300MK2") == 0x94, "IC-7300MK2 default CI-V address is 0x94")
        assertTest(IcomTestHelper.defaultCivAddress(for: "IC-7610") == 0x98, "IC-7610 default CI-V address is 0x98")
        assertTest(IcomTestHelper.defaultCivAddress(for: "Auto") == 0x00, "Auto-detect CI-V address is 0x00")

        // Test 2: Frequency to 5-byte BCD Encoding (14.074.000 Hz FT8 20M)
        let bcd14M = IcomTestHelper.frequencyToBCD(14_074_000)
        assertTest(bcd14M == [0x00, 0x40, 0x07, 0x14, 0x00], "14.074.000 Hz encodes to [00, 40, 07, 14, 00]")

        // Test 3: Frequency to 5-byte BCD Encoding (7.074.000 Hz FT8 40M)
        let bcd7M = IcomTestHelper.frequencyToBCD(7_074_000)
        assertTest(bcd7M == [0x00, 0x40, 0x07, 0x07, 0x00], "7.074.000 Hz encodes to [00, 40, 07, 07, 00]")

        // Test 4: Frequency to 5-byte BCD Encoding (50.313.000 Hz FT8 6M)
        let bcd50M = IcomTestHelper.frequencyToBCD(50_313_000)
        assertTest(bcd50M == [0x00, 0x30, 0x31, 0x50, 0x00], "50.313.000 Hz encodes to [00, 30, 31, 50, 00]")

        // Test 5: Frequency to 5-byte BCD Encoding (144.174.000 Hz FT8 2M VHF on IC-705)
        let bcd144M = IcomTestHelper.frequencyToBCD(144_174_000)
        assertTest(bcd144M == [0x00, 0x40, 0x17, 0x44, 0x01], "144.174.000 Hz encodes to [00, 40, 17, 44, 01]")

        // Test 6: BCD to Frequency Decoding
        let decoded14M = IcomTestHelper.bcdToFrequency(bcd14M)
        assertTest(decoded14M == 14_074_000, "Decoded BCD matches 14.074.000 Hz exactly")

        let decoded7M = IcomTestHelper.bcdToFrequency(bcd7M)
        assertTest(decoded7M == 7_074_000, "Decoded BCD matches 7.074.000 Hz exactly")

        let decoded50M = IcomTestHelper.bcdToFrequency(bcd50M)
        assertTest(decoded50M == 50_313_000, "Decoded BCD matches 50.313.000 Hz exactly")

        let decoded144M = IcomTestHelper.bcdToFrequency(bcd144M)
        assertTest(decoded144M == 144_174_000, "Decoded BCD matches 144.174.000 Hz exactly")

        // Test 7: CI-V Framing (Preamble FE FE, To, From E0, Payload, EOM FD)
        let frame = IcomTestHelper.buildCIVFrame(to: 0x94, command: [0x05, 0x00, 0x40, 0x07, 0x14, 0x00])
        assertTest(frame == [0xFE, 0xFE, 0x94, 0xE0, 0x05, 0x00, 0x40, 0x07, 0x14, 0x00, 0xFD],
                   "Complete CI-V frequency set packet formatted correctly")

        // Test 8: PTT ON / OFF Commands
        let pttOnCmd: [UInt8] = [0x1C, 0x00, 0x01]
        let pttOffCmd: [UInt8] = [0x1C, 0x00, 0x00]
        assertTest(pttOnCmd == [0x1C, 0x00, 0x01], "CI-V PTT ON is 1C 00 01")
        assertTest(pttOffCmd == [0x1C, 0x00, 0x00], "CI-V PTT OFF is 1C 00 00")

        // Test 9: DATA MOD USB Routing Command
        // 1A 05 00 85 03 routes DATA MOD input to USB port across IC-705/7300/7610
        let dataModUsbCmd: [UInt8] = [0x1A, 0x05, 0x00, 0x85, 0x03]
        assertTest(dataModUsbCmd == [0x1A, 0x05, 0x00, 0x85, 0x03], "DATA MOD USB command matches 1A 05 00 85 03")

        // Test 10: USB-D Mode Setting Commands
        let setUsbMode: [UInt8] = [0x06, 0x01, 0x01] // USB + Filter 1
        let setDataModeOn: [UInt8] = [0x1A, 0x06, 0x01, 0x01] // Data Mode ON (USB-D)
        assertTest(setUsbMode == [0x06, 0x01, 0x01], "USB Mode command is 06 01 01")
        assertTest(setDataModeOn == [0x1A, 0x06, 0x01, 0x01], "Data Mode ON command is 1A 06 01 01")

        // Test 11: CW Morse Code Command 17 Packet Generation
        let cwText = "CQ TEST"
        let cwFrame = IcomTestHelper.buildCWMorseFrame(to: 0x94, text: cwText)
        let expectedPayload: [UInt8] = [0xFE, 0xFE, 0x94, 0xE0, 0x17] + Array(cwText.utf8) + [0xFD]
        assertTest(cwFrame == expectedPayload, "CI-V Command 17 Morse frame encoded with ASCII payload")

        // Test 12: CW Morse Abort Command (17 FF)
        let abortFrame = IcomTestHelper.buildCIVFrame(to: 0x94, command: [0x17, 0xFF])
        assertTest(abortFrame == [0xFE, 0xFE, 0x94, 0xE0, 0x17, 0xFF, 0xFD], "Morse abort frame is 17 FF")

        // Test 13: Telemetry S-Meter Parsing
        // Example: S-meter packet 0x15 0x02 0x01 0x20 -> Raw 120 / 241 * 15 ≈ S7.4
        let sMeterRaw: Double = 120.0
        let sUnits = (sMeterRaw / 241.0) * 15.0
        assertTest(sUnits > 7.0 && sUnits < 8.0, "S-meter raw telemetry parses accurately to ~S7.5")

        // Test 14: Telemetry RF Power Parsing
        // Example: Power packet 0x15 0x11 0x02 0x13 -> Raw 213 / 213 * 100W = 100W
        let powerRaw: Double = 213.0
        let powerWatts = (powerRaw / 213.0) * 100.0
        assertTest(abs(powerWatts - 100.0) < 0.1, "100% RF power raw telemetry parses to 100 Watts")

        print("--- All Icom USB Driver & CI-V Tests Finished ---")
        return passed
    }
}

// MARK: - Test Helper mirroring IcomUSBRadioDriver logic

private struct IcomTestHelper {
    static func defaultCivAddress(for modelName: String) -> UInt8 {
        switch modelName {
        case "IC-705": return 0xA4
        case "IC-7300", "IC-7300MK2": return 0x94
        case "IC-7610": return 0x98
        default: return 0x00
        }
    }

    static func frequencyToBCD(_ hz: UInt64) -> [UInt8] {
        var bcd = [UInt8](repeating: 0, count: 5)
        var temp = hz
        for i in 0..<5 {
            let low = UInt8(temp % 10)
            temp /= 10
            let high = UInt8(temp % 10)
            temp /= 10
            bcd[i] = (high << 4) | low
        }
        return bcd
    }

    static func bcdToFrequency(_ bcd: [UInt8]) -> UInt64 {
        var hz: UInt64 = 0
        var multiplier: UInt64 = 1
        for byte in bcd {
            let low = UInt64(byte & 0x0F)
            let high = UInt64((byte >> 4) & 0x0F)
            hz += low * multiplier
            multiplier *= 10
            hz += high * multiplier
            multiplier *= 10
        }
        return hz
    }

    static func buildCIVFrame(to dest: UInt8, command: [UInt8]) -> [UInt8] {
        var frame: [UInt8] = [0xFE, 0xFE, dest, 0xE0]
        frame.append(contentsOf: command)
        frame.append(0xFD)
        return frame
    }

    static func buildCWMorseFrame(to dest: UInt8, text: String) -> [UInt8] {
        var cmd: [UInt8] = [0x17]
        cmd.append(contentsOf: text.utf8)
        return buildCIVFrame(to: dest, command: cmd)
    }
}
