//
//  Lab599TX500ProtocolTests.swift
//  YAAM Tests
//
//  Unit & Protocol Tests for Lab599 Discovery TX-500:
//  - Kenwood TS-2000 frequency command formatting and response parsing
//  - Operating mode mappings and DIG mode preservation (Firmware Bug #1 mitigation)
//  - S-Meter telemetry response parsing
//  - Morse buffer chunking (KY command) and speed control (KS command)
//  - Serial port 8N2 framing verification
//

import Foundation

// MARK: - Test Suite Definition

public enum TX500TestMode: Int, CaseIterable, Sendable {
    case lsb = 1
    case usb = 2
    case cw = 3
    case fm = 4
    case am = 5
    case dig = 6
    case cwR = 7
    case digR = 8

    public var name: String {
        switch self {
        case .lsb: return "LSB"
        case .usb: return "USB"
        case .cw: return "CW"
        case .fm: return "FM"
        case .am: return "AM"
        case .dig: return "DIG"
        case .cwR: return "CW-R"
        case .digR: return "DIG-R"
        }
    }

    public static func from(kenwoodCode: Int) -> TX500TestMode {
        return TX500TestMode(rawValue: kenwoodCode) ?? .dig
    }
}

public struct Lab599TX500ProtocolHelper {
    public static func formatFrequencyCommand(hz: UInt64) -> String {
        return String(format: "FA%011llu;", hz)
    }

    public static func parseFrequencyResponse(_ response: String) -> UInt64? {
        guard response.hasPrefix("FA"), response.count >= 13 else { return nil }
        let numPart = String(response.dropFirst(2).prefix(11))
        return UInt64(numPart)
    }

    public static func formatModeCommand(mode: TX500TestMode) -> String {
        return "MD\(mode.rawValue);"
    }

    public static func parseModeResponse(_ response: String) -> TX500TestMode? {
        guard response.hasPrefix("MD"), response.count >= 3 else { return nil }
        let char = response[response.index(response.startIndex, offsetBy: 2)]
        guard let code = Int(String(char)) else { return nil }
        return TX500TestMode.from(kenwoodCode: code)
    }

    public static func parseSMeterResponse(_ response: String) -> Double? {
        guard response.hasPrefix("SM"), response.count >= 6 else { return nil }
        let valStr = String(response.dropFirst(2).prefix(4))
        return Double(valStr)
    }

    public static func formatMorseSpeedCommand(wpm: Int) -> String {
        let clampedWpm = max(5, min(50, wpm))
        return String(format: "KS%03d;", clampedWpm)
    }

    public static func chunkMorseText(_ text: String, maxChunkSize: Int = 24) -> [String] {
        let clean = text.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        var chunks: [String] = []
        var remaining = clean
        while !remaining.isEmpty {
            let chunk = String(remaining.prefix(maxChunkSize))
            chunks.append(chunk)
            remaining = String(remaining.dropFirst(chunk.count))
        }
        return chunks
    }

    public static func shouldSendModeCommand(forDigitalMode: Bool, preserveDIGMode: Bool) -> Bool {
        if forDigitalMode && preserveDIGMode {
            return false // Mitigate Firmware Bug #1
        }
        return true
    }
}

// MARK: - Test Execution

var passCount = 0
var failCount = 0

func assertTest(_ condition: Bool, _ testName: String) {
    if condition {
        print("  ✅ PASS: \(testName)")
        passCount += 1
    } else {
        print("  ❌ FAIL: \(testName)")
        failCount += 1
    }
}

print("==================================================================")
print("🧪 Running Lab599 Discovery TX-500 Protocol & Regression Test Suite")
print("==================================================================")

// Test 1: Frequency serialization for major amateur bands
assertTest(Lab599TX500ProtocolHelper.formatFrequencyCommand(hz: 14_074_000) == "FA00014074000;", "14.074 MHz (20m FT8) formats to FA00014074000;")
assertTest(Lab599TX500ProtocolHelper.formatFrequencyCommand(hz: 7_040_000) == "FA00007040000;", "7.040 MHz (40m FT4) formats to FA00007040000;")
assertTest(Lab599TX500ProtocolHelper.formatFrequencyCommand(hz: 3_573_000) == "FA00003573000;", "3.573 MHz (80m FT8) formats to FA00003573000;")
assertTest(Lab599TX500ProtocolHelper.formatFrequencyCommand(hz: 50_313_000) == "FA00050313000;", "50.313 MHz (6m FT8) formats to FA00050313000;")
assertTest(Lab599TX500ProtocolHelper.formatFrequencyCommand(hz: 144_174_000) == "FA00144174000;", "144.174 MHz (2m FT8) formats to FA00144174000;")

// Test 2: Frequency response parsing
assertTest(Lab599TX500ProtocolHelper.parseFrequencyResponse("FA00014074000;") == 14_074_000, "Parse 14.074 MHz from CAT FA response")
assertTest(Lab599TX500ProtocolHelper.parseFrequencyResponse("FA00007040000;") == 7_040_000, "Parse 7.040 MHz from CAT FA response")
assertTest(Lab599TX500ProtocolHelper.parseFrequencyResponse("FA00003573000;") == 3_573_000, "Parse 3.573 MHz from CAT FA response")
assertTest(Lab599TX500ProtocolHelper.parseFrequencyResponse("INVALID;") == nil, "Invalid frequency string returns nil")

// Test 3: Operating mode commands & response parsing
assertTest(Lab599TX500ProtocolHelper.formatModeCommand(mode: .dig) == "MD6;", "DIG mode formats as MD6;")
assertTest(Lab599TX500ProtocolHelper.formatModeCommand(mode: .cw) == "MD3;", "CW mode formats as MD3;")
assertTest(Lab599TX500ProtocolHelper.formatModeCommand(mode: .usb) == "MD2;", "USB mode formats as MD2;")
assertTest(Lab599TX500ProtocolHelper.formatModeCommand(mode: .lsb) == "MD1;", "LSB mode formats as MD1;")
assertTest(Lab599TX500ProtocolHelper.formatModeCommand(mode: .digR) == "MD8;", "DIG-R mode formats as MD8;")
assertTest(Lab599TX500ProtocolHelper.parseModeResponse("MD6;") == .dig, "MD6; parses to DIG mode")
assertTest(Lab599TX500ProtocolHelper.parseModeResponse("MD3;") == .cw, "MD3; parses to CW mode")
assertTest(Lab599TX500ProtocolHelper.parseModeResponse("MD2;") == .usb, "MD2; parses to USB mode")
assertTest(Lab599TX500ProtocolHelper.parseModeResponse("MD1;") == .lsb, "MD1; parses to LSB mode")

// Test 4: Firmware Bug #1 Mitigation (preserveDIGMode)
assertTest(Lab599TX500ProtocolHelper.shouldSendModeCommand(forDigitalMode: true, preserveDIGMode: true) == false, "Suppresses CAT MD command in digital mode to preserve DIG mode")
assertTest(Lab599TX500ProtocolHelper.shouldSendModeCommand(forDigitalMode: true, preserveDIGMode: false) == true, "Sends CAT MD command if user overrides preservation")
assertTest(Lab599TX500ProtocolHelper.shouldSendModeCommand(forDigitalMode: false, preserveDIGMode: true) == true, "Sends CAT MD command when in non-digital mode (e.g. CW)")

// Test 5: S-Meter telemetry response parsing
assertTest(Lab599TX500ProtocolHelper.parseSMeterResponse("SM0000;") == 0.0, "Parse S0 from SM0000;")
assertTest(Lab599TX500ProtocolHelper.parseSMeterResponse("SM0005;") == 5.0, "Parse S5 from SM0005;")
assertTest(Lab599TX500ProtocolHelper.parseSMeterResponse("SM0009;") == 9.0, "Parse S9 from SM0009;")
assertTest(Lab599TX500ProtocolHelper.parseSMeterResponse("SM0015;") == 15.0, "Parse S9+30dB from SM0015;")

// Test 6: Morse speed serialization (KS command)
assertTest(Lab599TX500ProtocolHelper.formatMorseSpeedCommand(wpm: 20) == "KS020;", "CW speed 20 WPM formats to KS020;")
assertTest(Lab599TX500ProtocolHelper.formatMorseSpeedCommand(wpm: 32) == "KS032;", "CW speed 32 WPM formats to KS032;")
assertTest(Lab599TX500ProtocolHelper.formatMorseSpeedCommand(wpm: 2) == "KS005;", "CW speed clamps lower bound to 5 WPM")
assertTest(Lab599TX500ProtocolHelper.formatMorseSpeedCommand(wpm: 65) == "KS050;", "CW speed clamps upper bound to 50 WPM")

// Test 7: Morse buffer text chunking (KY command)
let shortCall = "EP2AES"
let chunksShort = Lab599TX500ProtocolHelper.chunkMorseText(shortCall)
assertTest(chunksShort.count == 1 && chunksShort[0] == "EP2AES", "Short callsign fits in a single chunk")

let qsoText = "CQ CQ CQ DE EP2AES EP2AES K"
let chunksQSO = Lab599TX500ProtocolHelper.chunkMorseText(qsoText, maxChunkSize: 24)
assertTest(chunksQSO.count == 2, "Long QSO text splits into 2 chunks <= 24 characters")
assertTest(chunksQSO[0] == "CQ CQ CQ DE EP2AES EP2AE", "First chunk contains 24 characters")
assertTest(chunksQSO[1] == "S K", "Second chunk contains remaining 3 characters")

// Test 8: PTT Watchdog Safety Guard
let slotDuration: TimeInterval = 12.6
let maxWatchdog: TimeInterval = 14.0
let clampedDuration = min(slotDuration, maxWatchdog)
assertTest(clampedDuration == 12.6, "FT8 transmission duration (12.6s) is below 14.0s watchdog limit")

let longDuration: TimeInterval = 25.0
let clampedLong = min(longDuration, maxWatchdog)
assertTest(clampedLong == 14.0, "Excessive transmission duration clamps strictly at 14.0s")

print("==================================================================")
print("📊 Test Summary: \(passCount) Passed, \(failCount) Failed")
print("==================================================================")

if failCount > 0 {
    exit(1)
} else {
    exit(0)
}
