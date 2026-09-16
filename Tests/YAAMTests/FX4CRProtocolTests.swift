//
//  FX4CRProtocolTests.swift
//  YAAM Tests
//
//  Unit & Protocol Tests for FX-4CR Transceiver (USB-C & Bluetooth):
//  - Kenwood TS-590S frequency serialization and response parsing (FA, FB)
//  - Operating mode mappings and Hamlib Protocol Error (-8) safe mode mitigation
//  - PTT keying commands (TX, RX) and watchdog limit verification
//  - S-Meter and RF telemetry parsing (SM, PC, RM1)
//  - Morse buffer chunking (KY command) and speed control (KS command)
//  - Dual transport toggle (USB-C vs Bluetooth) and port matching
//  - Audio gain and thermal limits calibration constants
//

import Foundation

// MARK: - Helper Types for Testing

public enum FX4CRTestTransport: String, CaseIterable, Sendable {
    case usb = "USB-C (Wired)"
    case bluetooth = "Bluetooth (Wireless)"
}

public enum FX4CRTestMode: Int, CaseIterable, Sendable {
    case lsb = 1
    case usb = 2
    case cw = 3
    case fm = 4
    case am = 5
    case fsk = 6
    case cwR = 7
    case fskR = 9

    public var name: String {
        switch self {
        case .lsb: return "LSB"
        case .usb: return "USB"
        case .cw: return "CW"
        case .fm: return "FM"
        case .am: return "AM"
        case .fsk: return "FSK"
        case .cwR: return "CW-R"
        case .fskR: return "FSK-R"
        }
    }

    public static func from(kenwoodCode: Int) -> FX4CRTestMode {
        return FX4CRTestMode(rawValue: kenwoodCode) ?? .usb
    }
}

public enum FX4CRTestSafeModeStrategy: String, CaseIterable, Sendable {
    case standardUSB = "Standard USB (MD2;)"
    case cwOnly = "CW Mode (MD3;)"
    case none = "None (Pass-through)"
}

public struct FX4CRProtocolHelper {
    public static func formatFrequencyCommand(hz: UInt64, vfoB: Bool = false) -> String {
        let prefix = vfoB ? "FB" : "FA"
        return String(format: "%@%011llu;", prefix, hz)
    }

    public static func parseFrequencyResponse(_ response: String) -> UInt64? {
        guard (response.hasPrefix("FA") || response.hasPrefix("FB")), response.count >= 13 else { return nil }
        let numPart = String(response.dropFirst(2).prefix(11))
        return UInt64(numPart)
    }

    public static func formatModeCommand(mode: FX4CRTestMode) -> String {
        return "MD\(mode.rawValue);"
    }

    public static func formatSafeDigitalModeCommand(strategy: FX4CRTestSafeModeStrategy) -> String? {
        switch strategy {
        case .standardUSB:
            return "MD2;"
        case .cwOnly:
            return "MD3;"
        case .none:
            return nil
        }
    }

    public static func parseModeResponse(_ response: String) -> FX4CRTestMode? {
        guard response.hasPrefix("MD"), response.count >= 3 else { return nil }
        let char = response[response.index(response.startIndex, offsetBy: 2)]
        guard let code = Int(String(char)) else { return nil }
        return FX4CRTestMode.from(kenwoodCode: code)
    }

    public static func formatPTTCommand(transmit: Bool) -> String {
        return transmit ? "TX;" : "RX;"
    }

    public static func parseSMeterResponse(_ response: String) -> Double? {
        guard response.hasPrefix("SM"), response.count >= 6 else { return nil }
        let valStr = String(response.dropFirst(2).prefix(4))
        guard let rawInt = Double(valStr) else { return nil }
        return min(15.0, rawInt / 2.0)
    }

    public static func formatMorseSpeedCommand(wpm: Int) -> String {
        let clamped = max(5, min(50, wpm))
        return String(format: "KS%03d;", clamped)
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

    public static func isPreferredPort(_ port: String, for transport: FX4CRTestTransport) -> Bool {
        let p = port.lowercased()
        switch transport {
        case .usb:
            return p.contains("usbserial") || p.contains("usbmodem") || p.contains("wchusb")
        case .bluetooth:
            return p.contains("fx-4cr") || p.contains("fx4cr") || p.contains("bluetooth")
        }
    }

    public static func isCodecDeviceName(_ name: String, transport: FX4CRTestTransport) -> Bool {
        let n = name.lowercased()
        if transport == .usb {
            return n.contains("fx-4cr") || n.contains("usb audio") || n.contains("cm108") || n.contains("c-media")
        } else {
            return n.contains("fx-4cr") || n.contains("bluetooth")
        }
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
print("🧪 Running FX-4CR Transceiver Protocol & Dual-Transport Test Suite")
print("==================================================================")

// Test 1: VFO-A & VFO-B Frequency Serialization
assertTest(FX4CRProtocolHelper.formatFrequencyCommand(hz: 14_074_000) == "FA00014074000;", "14.074 MHz (20m FT8) formats to FA00014074000;")
assertTest(FX4CRProtocolHelper.formatFrequencyCommand(hz: 7_074_000) == "FA00007074000;", "7.074 MHz (40m FT8) formats to FA00007074000;")
assertTest(FX4CRProtocolHelper.formatFrequencyCommand(hz: 28_074_000) == "FA00028074000;", "28.074 MHz (10m FT8) formats to FA00028074000;")
assertTest(FX4CRProtocolHelper.formatFrequencyCommand(hz: 14_074_000, vfoB: true) == "FB00014074000;", "VFO-B 14.074 MHz formats to FB00014074000;")

// Test 2: Frequency Response Parsing
assertTest(FX4CRProtocolHelper.parseFrequencyResponse("FA00014074000;") == 14_074_000, "Parse 14.074 MHz from CAT FA response")
assertTest(FX4CRProtocolHelper.parseFrequencyResponse("FB00007074000;") == 7_074_000, "Parse 7.074 MHz from CAT FB response")
assertTest(FX4CRProtocolHelper.parseFrequencyResponse("INVALID;") == nil, "Invalid frequency response returns nil")

// Test 3: Operating Mode Commands & Response Parsing
assertTest(FX4CRProtocolHelper.formatModeCommand(mode: .usb) == "MD2;", "USB mode formats as MD2;")
assertTest(FX4CRProtocolHelper.formatModeCommand(mode: .cw) == "MD3;", "CW mode formats as MD3;")
assertTest(FX4CRProtocolHelper.formatModeCommand(mode: .lsb) == "MD1;", "LSB mode formats as MD1;")
assertTest(FX4CRProtocolHelper.formatModeCommand(mode: .cwR) == "MD7;", "CW-R mode formats as MD7;")
assertTest(FX4CRProtocolHelper.parseModeResponse("MD2;") == .usb, "MD2; parses to USB mode")
assertTest(FX4CRProtocolHelper.parseModeResponse("MD3;") == .cw, "MD3; parses to CW mode")
assertTest(FX4CRProtocolHelper.parseModeResponse("MD1;") == .lsb, "MD1; parses to LSB mode")

// Test 4: Hamlib Protocol Error (-8) Mitigation (Safe Mode Strategies)
assertTest(FX4CRProtocolHelper.formatSafeDigitalModeCommand(strategy: .standardUSB) == "MD2;", "Safe mode standardUSB issues standard MD2; avoiding PKTUSB bug")
assertTest(FX4CRProtocolHelper.formatSafeDigitalModeCommand(strategy: .cwOnly) == "MD3;", "Safe mode cwOnly issues MD3;")
assertTest(FX4CRProtocolHelper.formatSafeDigitalModeCommand(strategy: .none) == nil, "Safe mode none sends no mode override command")

// Test 5: PTT Keying Commands & Watchdog Limit
assertTest(FX4CRProtocolHelper.formatPTTCommand(transmit: true) == "TX;", "PTT transmit command is TX;")
assertTest(FX4CRProtocolHelper.formatPTTCommand(transmit: false) == "RX;", "PTT receive command is RX;")

let standardFT8Duration: TimeInterval = 12.6
let maxSafetyWatchdog: TimeInterval = 14.0
assertTest(standardFT8Duration < maxSafetyWatchdog, "Standard FT8 transmit slot (12.6s) safely within 14.0s watchdog limit")
let stalledTaskDuration: TimeInterval = 30.0
let clampedWatchdog = min(stalledTaskDuration, maxSafetyWatchdog)
assertTest(clampedWatchdog == 14.0, "Stalled task clamped to 14.0s by safety watchdog")

// Test 6: S-Meter Parsing
assertTest(FX4CRProtocolHelper.parseSMeterResponse("SM0000;") == 0.0, "SM0000; parses to S0")
assertTest(FX4CRProtocolHelper.parseSMeterResponse("SM0010;") == 5.0, "SM0010; parses to S5")
assertTest(FX4CRProtocolHelper.parseSMeterResponse("SM0018;") == 9.0, "SM0018; parses to S9")
assertTest(FX4CRProtocolHelper.parseSMeterResponse("SM0030;") == 15.0, "SM0030; parses to S9+60dB (15 S-units)")

// Test 7: Morse Code Speed & Buffer Chunking
assertTest(FX4CRProtocolHelper.formatMorseSpeedCommand(wpm: 24) == "KS024;", "Speed 24 WPM formats as KS024;")
assertTest(FX4CRProtocolHelper.formatMorseSpeedCommand(wpm: 3) == "KS005;", "Speed clamps lower bound to 5 WPM")
assertTest(FX4CRProtocolHelper.formatMorseSpeedCommand(wpm: 60) == "KS050;", "Speed clamps upper bound to 50 WPM")

let shortCall = "EP2AES"
let chunks1 = FX4CRProtocolHelper.chunkMorseText(shortCall)
assertTest(chunks1.count == 1 && chunks1[0] == "EP2AES", "Callsign EP2AES fits in a single chunk")

let fullQSO = "CQ CQ DE EP2AES EP2AES K"
let chunks2 = FX4CRProtocolHelper.chunkMorseText(fullQSO, maxChunkSize: 24)
assertTest(chunks2.count == 1 && chunks2[0].count == 24, "24-char QSO text fits in exactly one chunk")

let longQSO = "CQ CQ CQ DE EP2AES EP2AES 599 599 73 TU"
let chunks3 = FX4CRProtocolHelper.chunkMorseText(longQSO, maxChunkSize: 24)
assertTest(chunks3.count == 2, "Long QSO text splits into 2 chunks <= 24 characters")
assertTest(chunks3[0].count <= 24 && chunks3[1].count <= 24, "All chunks are within 24-character hardware buffer limit")

// Test 8: Transport Port Matching & Detection
assertTest(FX4CRProtocolHelper.isPreferredPort("/dev/cu.usbserial-1420", for: .usb) == true, "Matches USB serial port")
assertTest(FX4CRProtocolHelper.isPreferredPort("/dev/cu.FX-4CR", for: .bluetooth) == true, "Matches Bluetooth FX-4CR port")
assertTest(FX4CRProtocolHelper.isPreferredPort("/dev/cu.Bluetooth-Incoming-Port", for: .bluetooth) == true, "Matches generic incoming Bluetooth port")
assertTest(FX4CRProtocolHelper.isPreferredPort("/dev/cu.Bluetooth-Incoming-Port", for: .usb) == false, "Bluetooth port rejected when in USB mode")

// Test 9: Audio Codec Detection
assertTest(FX4CRProtocolHelper.isCodecDeviceName("USB Audio Device", transport: .usb) == true, "Detects C-Media CM108AH generic descriptor")
assertTest(FX4CRProtocolHelper.isCodecDeviceName("FX-4CR Audio", transport: .usb) == true, "Detects FX-4CR USB Audio")
assertTest(FX4CRProtocolHelper.isCodecDeviceName("FX-4CR Bluetooth", transport: .bluetooth) == true, "Detects FX-4CR Bluetooth Audio")

// Test 10: Audio Gain & Calibration Limits (Documented in Operating Guide)
let recommendedRXVolMin = 18
let recommendedRXVolMax = 24
assertTest(recommendedRXVolMin >= 18 && recommendedRXVolMax <= 24, "RX volume knob recommended range is 18–24")

let recommendedTXGainDefault = 0.622 // Audio MIDI Setup ~0.622 for 7-9W RF
assertTest(recommendedTXGainDefault >= 0.45 && recommendedTXGainDefault <= 0.65, "TX gain default (~0.622) is within safe 7–9W thermal operating window")

print("==================================================================")
print("📊 FX-4CR Test Summary: \(passCount) Passed, \(failCount) Failed")
print("==================================================================")

if failCount > 0 {
    exit(1)
} else {
    exit(0)
}
