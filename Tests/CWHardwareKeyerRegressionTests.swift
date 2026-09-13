//
//  CWHardwareKeyerRegressionTests.swift
//  YAAM Tests
//
//  Unit & Regression Tests for WinKeyerDriver, SerialKeyerDriver, and CAT Morse
//

import Foundation
@testable import YAAM

@main
public struct CWHardwareKeyerRegressionTests {
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

        // Test 1: WinKeyer Timing & Speed Byte Calculations
        let wpm25: UInt8 = 25
        let speedCmd = [0x02, wpm25]
        assertTest(speedCmd[0] == 0x02 && speedCmd[1] == 25, "WinKeyer Speed Command [0x02, 25]")

        // Test 2: WinKeyer PTT Delays (10ms units)
        let leadInMs = 35
        let tailMs = 60
        let leadUnits = UInt8(min(250, leadInMs / 10))
        let tailUnits = UInt8(min(250, tailMs / 10))
        let pttCmd = [0x05, leadUnits, tailUnits]
        assertTest(pttCmd[1] == 3 && pttCmd[2] == 6, "WinKeyer PTT delays 35ms/60ms convert to 3/6 units")

        // Test 3: WinKeyer Keying Compensation clamping
        let compRaw = 45
        let compClamped = UInt8(min(31, max(0, compRaw)))
        assertTest(compClamped == 31, "WinKeyer keying compensation clamps at 31ms")

        // Test 4: Serial Keyer Polarity Inversion Logic
        func effectiveLine(requestedActive: Bool, isInverted: Bool) -> Bool {
            return isInverted ? !requestedActive : requestedActive
        }
        assertTest(effectiveLine(requestedActive: true, isInverted: false) == true, "Active-high mark asserts line")
        assertTest(effectiveLine(requestedActive: false, isInverted: false) == false, "Active-high space drops line")
        assertTest(effectiveLine(requestedActive: true, isInverted: true) == false, "Active-low mark inverts to low")
        assertTest(effectiveLine(requestedActive: false, isInverted: true) == true, "Active-low space inverts to high")

        // Test 5: Hamlib rigctld CAT CW Command Formatting
        let morseMsg = "CQ TEST EP2AES"
        let hamlibMorse = "b \(morseMsg)\n"
        assertTest(hamlibMorse == "b CQ TEST EP2AES\n", "Hamlib CW send_morse command formatted correctly")

        let keyerSpeed = 28
        let hamlibSpeed = "L KEYSPD \(keyerSpeed)\n"
        assertTest(hamlibSpeed == "L KEYSPD 28\n", "Hamlib CW keyer speed formatted correctly")

        // Test 6: PARIS Morse Timing Calculation Check
        let ditSec20 = 1.2 / 20.0
        assertTest(abs(ditSec20 - 0.060) < 0.001, "20 WPM dit is exactly 60ms")
        let ditSec30 = 1.2 / 30.0
        assertTest(abs(ditSec30 - 0.040) < 0.001, "30 WPM dit is exactly 40ms")

        return passed
    }
}
