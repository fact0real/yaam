//
//  WSJTXTwoWayRegressionTests.swift
//  YAAM Tests
//
//  Test suite for bi-directional WSJT-X / JTDX UDP Protocol.
//  Validates Reply (Type 4), Halt TX (Type 7), Set Location (Type 9),
//  Clear (Type 3), Free Text (Type 8), and message token extraction.
//

import Foundation

// Standalone stub for AmateurBandPlan when running test suite independently
nonisolated enum AmateurBandPlan {
    static func formattedMHz(_ mhz: Double) -> String { String(format: "%.3f", mhz) }
    static func band(forMHz mhz: Double) -> String? { "20m" }
}

@main
struct WSJTXTwoWayRegressionTests {
    static func main() {
        print("🚀 Starting WSJT-X / JTDX Two-Way Protocol Regression Test Suite...")
        testReplyPacketEncoding()
        testHaltTxPacketEncoding()
        testSetLocationPacketEncoding()
        testClearPacketEncoding()
        testFreeTextPacketEncoding()
        testHighlightCallsignPacketEncoding()
        testMessageTokenParsing()
        testLiveDecodeHelpers()
        print("🎉 ALL WSJT-X / JTDX Two-Way Protocol Tests PASSED successfully!")
    }

    private static func testReplyPacketEncoding() {
        print("🧪 Testing Reply (Type 4) packet binary encoding...")
        let clientID = "WSJT-X"
        let timeMillis: UInt32 = 37200000 // 10:20:00 UTC
        let snr: Int32 = -8
        let deltaTime: Double = 0.25
        let deltaFreq: UInt32 = 1420
        let mode = "~" // FT8 mode symbol
        let message = "CQ DL1ABC JO31"

        let data = WSJTXPacketEncoder.encodeReply(
            clientID: clientID,
            timeMillis: timeMillis,
            snr: snr,
            deltaTimeSec: deltaTime,
            deltaFrequencyHz: deltaFreq,
            mode: mode,
            message: message,
            lowConfidence: false,
            modifiers: 0
        )

        var cursor = DataCursor(data: data)
        let magic = cursor.readUInt32()
        precondition(magic == WSJTXPacketEncoder.magic, "Magic mismatch: \(String(describing: magic))")

        let schema = cursor.readUInt32()
        precondition(schema == WSJTXPacketEncoder.schemaVersion, "Schema mismatch: \(String(describing: schema))")

        let type = cursor.readUInt32()
        precondition(type == 4, "Expected packet type 4 (Reply), got \(String(describing: type))")

        let id = cursor.readString()
        precondition(id == clientID, "Client ID mismatch: \(String(describing: id))")

        let time = cursor.readUInt32()
        precondition(time == timeMillis, "Time mismatch: \(String(describing: time))")

        let parsedSnr = cursor.readInt32()
        precondition(parsedSnr == snr, "SNR mismatch: \(String(describing: parsedSnr))")

        let parsedDT = cursor.readDouble()
        precondition(abs((parsedDT ?? 0) - deltaTime) < 0.001, "DeltaTime mismatch: \(String(describing: parsedDT))")

        let parsedDF = cursor.readUInt32()
        precondition(parsedDF == deltaFreq, "DeltaFrequency mismatch: \(String(describing: parsedDF))")

        let parsedMode = cursor.readString()
        precondition(parsedMode == mode, "Mode mismatch: \(String(describing: parsedMode))")

        let parsedMsg = cursor.readString()
        precondition(parsedMsg == message, "Message mismatch: \(String(describing: parsedMsg))")

        let lowConf = cursor.readBool()
        precondition(lowConf == false, "LowConfidence mismatch: \(String(describing: lowConf))")

        let modifiers = cursor.readUInt8()
        precondition(modifiers == 0, "Modifiers mismatch: \(String(describing: modifiers))")

        print("  ✓ Reply (Type 4) binary encoding verified.")
    }

    private static func testHaltTxPacketEncoding() {
        print("🧪 Testing Halt TX (Type 7) packet encoding...")
        let clientID = "JTDX"
        let data = WSJTXPacketEncoder.encodeHaltTx(clientID: clientID, autoTxOnly: false)

        var cursor = DataCursor(data: data)
        precondition(cursor.readUInt32() == WSJTXPacketEncoder.magic)
        precondition(cursor.readUInt32() == 2)
        precondition(cursor.readUInt32() == 7, "Expected packet type 7 (Halt TX)")
        precondition(cursor.readString() == clientID)
        precondition(cursor.readBool() == false, "Expected autoTxOnly = false")

        print("  ✓ Halt TX (Type 7) encoding verified.")
    }

    private static func testSetLocationPacketEncoding() {
        print("🧪 Testing Set Location (Type 9) packet encoding...")
        let clientID = "WSJT-X"
        let grid = "KM32"
        let data = WSJTXPacketEncoder.encodeSetLocation(clientID: clientID, location: grid)

        var cursor = DataCursor(data: data)
        precondition(cursor.readUInt32() == WSJTXPacketEncoder.magic)
        precondition(cursor.readUInt32() == 2)
        precondition(cursor.readUInt32() == 9, "Expected packet type 9 (Location)")
        precondition(cursor.readString() == clientID)
        precondition(cursor.readString() == grid)

        print("  ✓ Set Location (Type 9) encoding verified.")
    }

    private static func testClearPacketEncoding() {
        print("🧪 Testing Clear (Type 3) packet encoding...")
        let data = WSJTXPacketEncoder.encodeClear(clientID: "WSJT-X", window: 2)

        var cursor = DataCursor(data: data)
        precondition(cursor.readUInt32() == WSJTXPacketEncoder.magic)
        precondition(cursor.readUInt32() == 2)
        precondition(cursor.readUInt32() == 3, "Expected packet type 3 (Clear)")
        precondition(cursor.readString() == "WSJT-X")
        precondition(cursor.readUInt8() == 2)

        print("  ✓ Clear (Type 3) encoding verified.")
    }

    private static func testFreeTextPacketEncoding() {
        print("🧪 Testing Free Text (Type 8) packet encoding...")
        let text = "73 DE EP2LMA"
        let data = WSJTXPacketEncoder.encodeFreeText(clientID: "WSJT-X", text: text, sendImmediately: true)

        var cursor = DataCursor(data: data)
        precondition(cursor.readUInt32() == WSJTXPacketEncoder.magic)
        precondition(cursor.readUInt32() == 2)
        precondition(cursor.readUInt32() == 8, "Expected packet type 8 (Free Text)")
        precondition(cursor.readString() == "WSJT-X")
        precondition(cursor.readString() == text)
        precondition(cursor.readBool() == true)

        print("  ✓ Free Text (Type 8) encoding verified.")
    }

    private static func testHighlightCallsignPacketEncoding() {
        print("🧪 Testing Highlight Callsign (Type 13) packet encoding...")
        let call = "EP2LMA"
        let data = WSJTXPacketEncoder.encodeHighlightCallsign(
            clientID: "WSJT-X",
            callsign: call,
            bgRGB: (255, 255, 0),
            fgRGB: (0, 0, 0),
            highlightLast: true
        )

        var cursor = DataCursor(data: data)
        precondition(cursor.readUInt32() == WSJTXPacketEncoder.magic)
        precondition(cursor.readUInt32() == 2)
        precondition(cursor.readUInt32() == 13, "Expected packet type 13 (Highlight)")
        precondition(cursor.readString() == "WSJT-X")
        precondition(cursor.readString() == call)

        print("  ✓ Highlight Callsign (Type 13) encoding verified.")
    }

    private static func testMessageTokenParsing() {
        print("🧪 Testing WSJT-X Message Token Extraction...")

        // 1. Standard CQ: CQ DL1ABC JO31
        let r1 = WSJTXPacketParser.parseMessageTokens("CQ DL1ABC JO31")
        precondition(r1.caller == "DL1ABC", "Expected caller DL1ABC, got \(r1.caller)")
        precondition(r1.grid == "JO31", "Expected grid JO31, got \(r1.grid)")

        // 2. Directed CQ: CQ DX W1AW FN31
        let r2 = WSJTXPacketParser.parseMessageTokens("CQ DX W1AW FN31")
        precondition(r2.caller == "W1AW", "Expected caller W1AW, got \(r2.caller)")
        precondition(r2.grid == "FN31", "Expected grid FN31, got \(r2.grid)")

        // 3. Contest CQ: CQ TEST EP2LMA KM32
        let r3 = WSJTXPacketParser.parseMessageTokens("CQ TEST EP2LMA KM32")
        precondition(r3.caller == "EP2LMA", "Expected caller EP2LMA, got \(r3.caller)")
        precondition(r3.grid == "KM32", "Expected grid KM32, got \(r3.grid)")

        // 4. Direct call with grid: EP2LMA DL1ABC JO31
        let r4 = WSJTXPacketParser.parseMessageTokens("EP2LMA DL1ABC JO31")
        precondition(r4.target == "EP2LMA", "Expected target EP2LMA, got \(r4.target)")
        precondition(r4.caller == "DL1ABC", "Expected caller DL1ABC, got \(r4.caller)")
        precondition(r4.grid == "JO31", "Expected grid JO31, got \(r4.grid)")

        // 5. Direct call with report: EP2LMA DL1ABC -12
        let r5 = WSJTXPacketParser.parseMessageTokens("EP2LMA DL1ABC -12")
        precondition(r5.target == "EP2LMA", "Expected target EP2LMA, got \(r5.target)")
        precondition(r5.caller == "DL1ABC", "Expected caller DL1ABC, got \(r5.caller)")
        precondition(r5.report == "-12", "Expected report -12, got \(r5.report)")

        // 6. Direct call with R-report: EP2LMA DL1ABC R-08
        let r6 = WSJTXPacketParser.parseMessageTokens("EP2LMA DL1ABC R-08")
        precondition(r6.report == "R-08", "Expected report R-08, got \(r6.report)")

        // 7. Direct call with 73: EP2LMA DL1ABC 73
        let r7 = WSJTXPacketParser.parseMessageTokens("EP2LMA DL1ABC 73")
        precondition(r7.caller == "DL1ABC", "Expected caller DL1ABC, got \(r7.caller)")
        precondition(r7.report == "73", "Expected report 73, got \(r7.report)")

        print("  ✓ Message token parsing verified.")
    }

    private static func testLiveDecodeHelpers() {
        print("🧪 Testing WSJTXLiveDecode computed helpers...")

        let decCQ = WSJTXLiveDecode(
            sourceID: "WSJT-X",
            isNew: true,
            timeMillis: 36000000, // 10:00:00 UTC
            snr: -8,
            deltaTimeSec: 0.2,
            deltaFrequencyHz: 1420,
            mode: "FT8",
            message: "CQ DL1ABC JO31",
            lowConfidence: false,
            offAir: false,
            callerCallsign: "DL1ABC",
            targetCallsign: "",
            grid: "JO31",
            report: ""
        )

        precondition(decCQ.isCQ == true, "decCQ should be CQ")
        precondition(decCQ.timeUTCString == "10:00:00", "Expected 10:00:00, got \(decCQ.timeUTCString)")
        precondition(decCQ.snrFormatted == "-8 dB", "Expected -8 dB, got \(decCQ.snrFormatted)")
        precondition(decCQ.deltaFrequencyFormatted == "1420 Hz", "Expected 1420 Hz, got \(decCQ.deltaFrequencyFormatted)")
        precondition(decCQ.deltaTimeFormatted == "+0.2s", "Expected +0.2s, got \(decCQ.deltaTimeFormatted)")

        let decDirected = WSJTXLiveDecode(
            sourceID: "WSJT-X",
            isNew: true,
            timeMillis: 36015000,
            snr: 4,
            deltaTimeSec: -0.1,
            deltaFrequencyHz: 1420,
            mode: "FT8",
            message: "EP2LMA DL1ABC -10",
            lowConfidence: false,
            offAir: false,
            callerCallsign: "DL1ABC",
            targetCallsign: "EP2LMA",
            grid: "",
            report: "-10"
        )

        precondition(decDirected.isCQ == false, "decDirected should NOT be CQ")
        precondition(decDirected.isDirectedToMe(myCall: "EP2LMA") == true, "decDirected should be directed to EP2LMA")
        precondition(decDirected.isDirectedToMe(myCall: "W1AW") == false, "decDirected should NOT be directed to W1AW")
        precondition(decDirected.snrFormatted == "+4 dB", "Expected +4 dB, got \(decDirected.snrFormatted)")

        print("  ✓ WSJTXLiveDecode helpers verified.")
    }
}
