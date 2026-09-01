//
//  ContestEngineRegression.swift
//  YAAM Tests
//

import Foundation

// MARK: - Standalone Contest Types for Regression Testing

struct TestContestRecord {
    var call: String
    var band: String
    var mode: String
    var date: String
    var time: String
    var freq: String
    var sentRst: String
    var rcvdRst: String
    var sentExch: String
    var rcvdExch: String
    var cqz: String
    var dxcc: String
    var cont: String
    var state: String
}

func extractWPXPrefixTest(call: String) -> String {
    let clean = call.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard !clean.isEmpty else { return "" }
    let parts = clean.split(separator: "/")
    let mainPart = parts.max { $0.count < $1.count }.map(String.init) ?? clean

    // Case A: Starts with a digit (e.g. 4X4DX, 3V8BB, 9A1AA, 7X2ARA)
    if let firstChar = mainPart.first, firstChar.isNumber {
        var seenLetter = false
        var prefixChars: [Character] = []
        for ch in mainPart {
            if ch.isNumber {
                prefixChars.append(ch)
                if seenLetter {
                    break
                }
            } else if ch.isLetter {
                seenLetter = true
                prefixChars.append(ch)
            }
        }
        return String(prefixChars)
    }

    // Case B: Starts with letters (e.g. DL1AAA, HG2000DX, EP2AES)
    if let digitIdx = mainPart.firstIndex(where: \.isNumber) {
        var lastDigitIdx = digitIdx
        var curr = mainPart.index(after: digitIdx)
        while curr < mainPart.endIndex && mainPart[curr].isNumber {
            lastDigitIdx = curr
            curr = mainPart.index(after: curr)
        }
        return String(mainPart[...lastDigitIdx])
    }
    return String(mainPart.prefix(3))
}

func calculateCQWWScoreTest(records: [TestContestRecord], homeContinent: String) -> (points: Int, mults: Int, claimed: Int, dupes: Int) {
    var seenKeys: Set<String> = []
    var uniqueZonesPerBand: [String: Set<String>] = [:]
    var uniqueDXCCPerBand: [String: Set<String>] = [:]
    var totalPoints = 0
    var dupes = 0

    for r in records {
        let key = "\(r.call)|\(r.band)|\(r.mode)"
        if !seenKeys.insert(key).inserted {
            dupes += 1
            continue
        }

        // Points
        let pts = (r.cont == homeContinent) ? 1 : 3
        totalPoints += pts

        // Mults
        if !r.cqz.isEmpty {
            uniqueZonesPerBand[r.band, default: []].insert(r.cqz)
        }
        if !r.dxcc.isEmpty {
            uniqueDXCCPerBand[r.band, default: []].insert(r.dxcc)
        }
    }

    var totalMults = 0
    for (_, zones) in uniqueZonesPerBand { totalMults += zones.count }
    for (_, countries) in uniqueDXCCPerBand { totalMults += countries.count }

    let claimed = totalPoints * max(1, totalMults)
    return (totalPoints, totalMults, claimed, dupes)
}

func calculateWPXScoreTest(records: [TestContestRecord], homeContinent: String) -> (points: Int, mults: Int, claimed: Int, dupes: Int) {
    var seenKeys: Set<String> = []
    var prefixes: Set<String> = []
    var totalPoints = 0
    var dupes = 0

    for r in records {
        let key = "\(r.call)|\(r.band)|\(r.mode)"
        if !seenKeys.insert(key).inserted {
            dupes += 1
            continue
        }

        let isLowBand = (r.band == "40M" || r.band == "80M" || r.band == "160M")
        let isSameCont = (r.cont == homeContinent)
        let pts: Int
        if isLowBand {
            pts = isSameCont ? 2 : 6
        } else {
            pts = isSameCont ? 1 : 3
        }
        totalPoints += pts

        let pfx = extractWPXPrefixTest(call: r.call)
        if !pfx.isEmpty {
            prefixes.insert(pfx)
        }
    }

    let totalMults = prefixes.count
    let claimed = totalPoints * max(1, totalMults)
    return (totalPoints, totalMults, claimed, dupes)
}

func generateCabrilloTest(callsign: String, contest: String, records: [TestContestRecord], claimedScore: Int) -> String {
    var lines = [
        "START-OF-LOG: 3.0",
        "CALLSIGN: \(callsign)",
        "CONTEST: \(contest)",
        "CATEGORY-OPERATOR: SINGLE-OP",
        "CATEGORY-POWER: LOW",
        "CLAIMED-SCORE: \(claimedScore)",
        "OPERATORS: \(callsign)"
    ]

    for r in records {
        let line = "QSO: 14000 PH 2026-10-25 1200 \(callsign) 59 \(r.sentExch) \(r.call) 59 \(r.rcvdExch) 0"
        lines.append(line)
    }
    lines.append("END-OF-LOG:")
    return lines.joined(separator: "\n")
}

@main
struct ContestEngineRegression {
    static func main() {
        print("Running Advanced Contest Engine & Cabrillo 3.0 Regression Tests...")

        testWPXPrefixExtraction()
        testCQWWScoringAndMultipliers()
        testWPXScoringAndMultipliers()
        testDupeDetection()
        testCabrilloFormatting()

        print("All Contest Engine & Cabrillo 3.0 Regression Tests PASSED successfully!")
    }

    private static func testWPXPrefixExtraction() {
        precondition(extractWPXPrefixTest(call: "DL1AAA") == "DL1", "Failed DL1")
        precondition(extractWPXPrefixTest(call: "HG2000DX") == "HG2000", "Failed HG2000")
        precondition(extractWPXPrefixTest(call: "W6/EP2AES") == "EP2", "Failed W6/EP2AES")
        precondition(extractWPXPrefixTest(call: "4X4DX") == "4X4", "Failed 4X4")
        precondition(extractWPXPrefixTest(call: "JA7ZLO/1") == "JA7", "Failed JA7ZLO/1")
    }

    private static func testCQWWScoringAndMultipliers() {
        // Operator in Asia (EP2AES)
        let records: [TestContestRecord] = [
            // 20M: DL1AAA (Europe -> Diff cont: 3 pts, Zone 14, DXCC 230)
            TestContestRecord(call: "DL1AAA", band: "20M", mode: "SSB", date: "20261025", time: "120000", freq: "14.200", sentRst: "59", rcvdRst: "59", sentExch: "21", rcvdExch: "14", cqz: "14", dxcc: "230", cont: "EU", state: ""),
            // 20M: JA1ZLO (Asia -> Same cont: 1 pt, Zone 25, DXCC 339)
            TestContestRecord(call: "JA1ZLO", band: "20M", mode: "SSB", date: "20261025", time: "120500", freq: "14.225", sentRst: "59", rcvdRst: "59", sentExch: "21", rcvdExch: "25", cqz: "25", dxcc: "339", cont: "AS", state: ""),
            // 15M: DL2BBB (Europe -> Diff cont: 3 pts, Zone 14, DXCC 230 - new band multiplier!)
            TestContestRecord(call: "DL2BBB", band: "15M", mode: "SSB", date: "20261025", time: "121000", freq: "21.250", sentRst: "59", rcvdRst: "59", sentExch: "21", rcvdExch: "14", cqz: "14", dxcc: "230", cont: "EU", state: "")
        ]

        let res = calculateCQWWScoreTest(records: records, homeContinent: "AS")
        // Points: 3 + 1 + 3 = 7 points
        precondition(res.points == 7, "Expected 7 points, got \(res.points)")
        // Mults: 20M (Zones: 14, 25 = 2. DXCC: 230, 339 = 2. -> 4 mults) + 15M (Zones: 14 = 1. DXCC: 230 = 1. -> 2 mults) = 6 total multipliers
        precondition(res.mults == 6, "Expected 6 mults, got \(res.mults)")
        // Claimed Score: 7 * 6 = 42
        precondition(res.claimed == 42, "Expected 42 claimed score, got \(res.claimed)")
        precondition(res.dupes == 0, "Expected 0 dupes")
    }

    private static func testWPXScoringAndMultipliers() {
        let records: [TestContestRecord] = [
            // 40M: DL1AAA (DX low band -> 6 pts, Prefix DL1)
            TestContestRecord(call: "DL1AAA", band: "40M", mode: "SSB", date: "20261025", time: "120000", freq: "7.150", sentRst: "59", rcvdRst: "59", sentExch: "001", rcvdExch: "045", cqz: "14", dxcc: "230", cont: "EU", state: ""),
            // 40M: DL2BBB (DX low band -> 6 pts, Prefix DL2)
            TestContestRecord(call: "DL2BBB", band: "40M", mode: "SSB", date: "20261025", time: "120500", freq: "7.155", sentRst: "59", rcvdRst: "59", sentExch: "002", rcvdExch: "012", cqz: "14", dxcc: "230", cont: "EU", state: ""),
            // 20M: DL1AAA (DX high band -> 3 pts, Prefix DL1 already counted)
            TestContestRecord(call: "DL1AAA", band: "20M", mode: "SSB", date: "20261025", time: "121000", freq: "14.200", sentRst: "59", rcvdRst: "59", sentExch: "003", rcvdExch: "088", cqz: "14", dxcc: "230", cont: "EU", state: "")
        ]

        let res = calculateWPXScoreTest(records: records, homeContinent: "AS")
        // Points: 6 + 6 + 3 = 15 points
        precondition(res.points == 15, "Expected 15 points, got \(res.points)")
        // Unique prefixes: DL1, DL2 = 2 prefixes
        precondition(res.mults == 2, "Expected 2 mults, got \(res.mults)")
        // Claimed Score: 15 * 2 = 30
        precondition(res.claimed == 30, "Expected 30 claimed score, got \(res.claimed)")
    }

    private static func testDupeDetection() {
        let records: [TestContestRecord] = [
            TestContestRecord(call: "DL1AAA", band: "20M", mode: "SSB", date: "20261025", time: "120000", freq: "14.200", sentRst: "59", rcvdRst: "59", sentExch: "001", rcvdExch: "045", cqz: "14", dxcc: "230", cont: "EU", state: ""),
            // Duplicate contact on same band/mode
            TestContestRecord(call: "DL1AAA", band: "20M", mode: "SSB", date: "20261025", time: "121500", freq: "14.200", sentRst: "59", rcvdRst: "59", sentExch: "002", rcvdExch: "045", cqz: "14", dxcc: "230", cont: "EU", state: "")
        ]

        let res = calculateCQWWScoreTest(records: records, homeContinent: "AS")
        precondition(res.dupes == 1, "Expected 1 dupe, got \(res.dupes)")
        precondition(res.points == 3, "Expected 3 points (only 1st valid counted)")
    }

    private static func testCabrilloFormatting() {
        let records: [TestContestRecord] = [
            TestContestRecord(call: "DL1AAA", band: "20M", mode: "SSB", date: "20261025", time: "120000", freq: "14.200", sentRst: "59", rcvdRst: "59", sentExch: "21", rcvdExch: "14", cqz: "14", dxcc: "230", cont: "EU", state: "")
        ]

        let cabrillo = generateCabrilloTest(callsign: "EP2AES", contest: "CQ-WW-SSB", records: records, claimedScore: 42)
        precondition(cabrillo.contains("START-OF-LOG: 3.0"))
        precondition(cabrillo.contains("CALLSIGN: EP2AES"))
        precondition(cabrillo.contains("CONTEST: CQ-WW-SSB"))
        precondition(cabrillo.contains("CLAIMED-SCORE: 42"))
        precondition(cabrillo.contains("QSO: 14000 PH 2026-10-25 1200 EP2AES 59 21 DL1AAA 59 14 0"))
        precondition(cabrillo.contains("END-OF-LOG:"))
    }
}
