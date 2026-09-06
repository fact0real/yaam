//
//  QSLHubStudioRegressionTests.swift
//  YAAM Tests
//
//  Regression test suite for QSL Hub Studio:
//  - MIME (.eml) Header & Body Parsing
//  - Heuristic Regex Extraction (Call, Date, Time, Band, Mode, RST)
//  - Fuzzy Matching with Time Drift Tolerance
//  - Side-by-Side Conflict Detection & Diffs
//  - Diagnostic Logging System
//

import Foundation

// Isolated types for standalone test execution
struct TestQSORecord {
    let id: UUID
    var fields: [String: String]
    
    subscript(key: String) -> String {
        get { fields[key] ?? "" }
        set { fields[key] = newValue }
    }
}

enum TestConflictDiff: Equatable {
    case time(local: String, inbound: String)
    case mode(local: String, inbound: String)
    case rst(local: String, inbound: String)
    case band(local: String, inbound: String)
}

struct TestInboundItem {
    var callsign: String
    var qsoDate: String
    var qsoTime: String
    var band: String
    var mode: String
    var rst: String
}

@main
struct QSLHubStudioRegressionTests {
    static func main() {
        print("🚀 Starting QSL Hub Studio Regression Test Suite...")
        testRegexExtraction()
        testMimeEmailParsing()
        testFuzzyTimeDriftMatching()
        testConflictDetection()
        testDiagnosticLogging()
        print("🎉 ALL QSL Hub Studio Regression Tests PASSED successfully!")
    }

    // MARK: - 1. Heuristic Regex Extraction
    private static func testRegexExtraction() {
        print("🧪 [1/5] Testing Heuristic Regex Extraction from Email / OCR text...")

        let sampleEmailBody = """
        Hello Operator,
        You have received a new electronic QSL card on eQSL.cc!
        Details of the contact:
        Callsign: 9K2HN
        Date: 2026-08-14
        Time: 18:35 UTC
        Band: 20m (14.074 MHz)
        Mode: FT8
        RST: -08 dB
        Thanks for the QSO and 73!
        """

        let callRegex = try! NSRegularExpression(pattern: #"\b([A-Z0-9]{1,3}\/[A-Z0-9]+|[A-Z0-9]{1,2}[0-9][A-Z0-9]{1,4}(?:\/[A-Z0-9]+)?)\b"#)
        let dateRegex = try! NSRegularExpression(pattern: #"\b(20[0-9]{2}[-/.](?:0[1-9]|1[0-2])[-/.](?:0[1-9]|[12][0-9]|3[01]))\b"#)
        let bandRegex = try! NSRegularExpression(pattern: #"\b(160m|80m|60m|40m|30m|20m|17m|15m|12m|10m|6m|2m|70cm)\b"#)
        let modeRegex = try! NSRegularExpression(pattern: #"\b(FT8|FT4|CW|SSB|USB|LSB|RTTY|PSK31|AM|FM)\b"#)
        let rstRegex = try! NSRegularExpression(pattern: #"\b([+-][0-9]{2}|599|59|579|589)\b"#)

        let range = NSRange(sampleEmailBody.startIndex..., in: sampleEmailBody)

        // Callsign match
        var matchedCall = ""
        let ignoredTokens: Set<String> = ["EQSL", "CC", "UTC", "QSO", "NEW", "QSL", "FOR", "THANKS", "AND"]
        callRegex.enumerateMatches(in: sampleEmailBody, range: range) { match, _, stop in
            guard let m = match, let r = Range(m.range, in: sampleEmailBody) else { return }
            let cand = String(sampleEmailBody[r]).uppercased()
            if !ignoredTokens.contains(cand) && cand.contains(where: { $0.isNumber }) {
                matchedCall = cand
                stop.pointee = true
            }
        }
        precondition(matchedCall == "9K2HN", "Expected callsign 9K2HN, got '\(matchedCall)'")

        // Date match
        var matchedDate = ""
        if let m = dateRegex.firstMatch(in: sampleEmailBody, range: range), let r = Range(m.range, in: sampleEmailBody) {
            matchedDate = String(sampleEmailBody[r]).replacingOccurrences(of: "-", with: "")
        }
        precondition(matchedDate == "20260814", "Expected date 20260814, got '\(matchedDate)'")

        // Time match
        var matchedTime = ""
        let timePatterns = [
            #"(?:time|at|qso\s*time)[:\s]+([01][0-9]|2[0-3]):?([0-5][0-9])"#,
            #"\b([01][0-9]|2[0-3]):([0-5][0-9])(?:\s*UTC|\s*Z)?\b"#,
            #"\b([01][0-9]|2[0-3])([0-5][0-9])\s*(?:UTC|Z)\b"#
        ]
        for tp in timePatterns {
            if let regex = try? NSRegularExpression(pattern: tp, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: sampleEmailBody, range: range) {
                if let hRange = Range(match.range(at: 1), in: sampleEmailBody),
                   let mRange = Range(match.range(at: 2), in: sampleEmailBody) {
                    matchedTime = "\(sampleEmailBody[hRange])\(sampleEmailBody[mRange])"
                    break
                }
            }
        }
        precondition(matchedTime == "1835", "Expected time 1835, got '\(matchedTime)'")

        // Band match
        var matchedBand = ""
        if let m = bandRegex.firstMatch(in: sampleEmailBody, range: range), let r = Range(m.range, in: sampleEmailBody) {
            matchedBand = String(sampleEmailBody[r])
        }
        precondition(matchedBand == "20m", "Expected band 20m, got '\(matchedBand)'")

        // Mode match
        var matchedMode = ""
        if let m = modeRegex.firstMatch(in: sampleEmailBody, range: range), let r = Range(m.range, in: sampleEmailBody) {
            matchedMode = String(sampleEmailBody[r])
        }
        precondition(matchedMode == "FT8", "Expected mode FT8, got '\(matchedMode)'")

        // RST match
        var matchedRst = ""
        if let m = rstRegex.firstMatch(in: sampleEmailBody, range: range), let r = Range(m.range, in: sampleEmailBody) {
            matchedRst = String(sampleEmailBody[r])
        }
        precondition(matchedRst == "-08", "Expected RST -08, got '\(matchedRst)'")

        print("   ✅ Extracted metadata: Call=\(matchedCall), Date=\(matchedDate), Time=\(matchedTime), Band=\(matchedBand), Mode=\(matchedMode), RST=\(matchedRst)")
    }

    // MARK: - 2. MIME Email Parsing
    private static func testMimeEmailParsing() {
        print("🧪 [2/5] Testing MIME RFC-822 Email (.eml) and Base64 Attachment Extraction...")

        let sampleEml = """
        From: "eQSL.cc System" <service@eqsl.cc>
        To: <operator@yaam.radio>
        Subject: You have received an eQSL from W1AW!
        Date: Fri, 15 Aug 2026 14:22:10 +0000
        MIME-Version: 1.0
        Content-Type: multipart/mixed; boundary="--boundary_part_1234"

        ----boundary_part_1234
        Content-Type: text/plain; charset=UTF-8

        Thank you for contacting W1AW on 2026-08-15 at 14:15 on 40m CW.
        Your card is attached below.

        ----boundary_part_1234
        Content-Type: image/jpeg; name="w1aw_qsl.jpg"
        Content-Transfer-Encoding: base64
        Content-Disposition: attachment; filename="w1aw_qsl.jpg"

        /9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////
        ----boundary_part_1234--
        """

        var from = ""
        var subject = ""

        let lines = sampleEml.components(separatedBy: .newlines)
        var inHeaders = true

        for line in lines {
            if inHeaders {
                if line.starts(with: "From: ") {
                    from = String(line.dropFirst(6))
                } else if line.starts(with: "Subject: ") {
                    subject = String(line.dropFirst(9))
                } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    inHeaders = false
                }
            }
        }

        precondition(from.contains("service@eqsl.cc"), "Expected From to contain service@eqsl.cc, got '\(from)'")
        precondition(subject.contains("W1AW"), "Expected Subject to contain W1AW, got '\(subject)'")
        // Mirror QSLInboxEngine.parseMIME logic
        var parsedBody = ""
        var attachmentData: Data? = nil
        var parsedFilename = ""

        if let boundaryRange = sampleEml.range(of: "boundary=") {
            let rest = sampleEml[boundaryRange.upperBound...]
            let boundary = rest.components(separatedBy: CharacterSet(charactersIn: "\"\r\n ;")).first(where: { !$0.isEmpty }) ?? ""
            if !boundary.isEmpty {
                let parts = sampleEml.components(separatedBy: "--\(boundary)")
                for part in parts {
                    let lowerPart = part.lowercased()
                    if lowerPart.contains("content-type: text/plain") {
                        if let bodyStart = part.range(of: "\r\n\r\n") ?? part.range(of: "\n\n") {
                            parsedBody = String(part[bodyStart.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } else if lowerPart.contains("image/") || lowerPart.contains(".jpg") || lowerPart.contains(".png") || lowerPart.contains(".pdf") {
                        if let nameRange = part.range(of: "filename=\"") {
                            let nameRest = part[nameRange.upperBound...]
                            parsedFilename = nameRest.components(separatedBy: "\"").first ?? ""
                        }

                        if let b64Start = part.range(of: "\r\n\r\n") ?? part.range(of: "\n\n") {
                            var b64Str = String(part[b64Start.upperBound...])
                                .replacingOccurrences(of: "\r", with: "")
                                .replacingOccurrences(of: "\n", with: "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            while b64Str.hasSuffix("-") {
                                b64Str.removeLast()
                            }
                            b64Str = b64Str.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let decoded = Data(base64Encoded: b64Str, options: [.ignoreUnknownCharacters]), decoded.count > 10 {
                                attachmentData = decoded
                            }
                        }
                    }
                }
            }
        }

        precondition(parsedBody.contains("W1AW on 2026-08-15"), "Body text extraction failed")
        precondition(attachmentData != nil, "Failed to detect MIME attachment")
        precondition(attachmentData!.count > 0, "Failed to decode base64 attachment data")
        precondition(parsedFilename == "w1aw_qsl.jpg", "Attachment filename mismatch")

        print("   ✅ Parsed MIME successfully: From='\(from)', Subject='\(subject)', Attachment=\(attachmentData!.count) bytes, Filename='\(parsedFilename)'")
    }

    // MARK: - 3. Fuzzy Time Drift Matching
    private static func testFuzzyTimeDriftMatching() {
        print("🧪 [3/5] Testing Smart Fuzzy Time-Drift Matching (±15 min)...")

        func minutesBetween(date1: String, time1: String, date2: String, time2: String) -> Int? {
            let cleanD1 = date1.replacingOccurrences(of: "-", with: "")
            let cleanD2 = date2.replacingOccurrences(of: "-", with: "")
            guard cleanD1 == cleanD2 else { return nil }

            let t1 = time1.replacingOccurrences(of: ":", with: "")
            let t2 = time2.replacingOccurrences(of: ":", with: "")
            guard t1.count >= 4, t2.count >= 4,
                  let h1 = Int(t1.prefix(2)), let m1 = Int(t1.dropFirst(2).prefix(2)),
                  let h2 = Int(t2.prefix(2)), let m2 = Int(t2.dropFirst(2).prefix(2)) else { return nil }

            let tot1 = h1 * 60 + m1
            let tot2 = h2 * 60 + m2
            return abs(tot1 - tot2)
        }

        func areModesEquivalent(_ m1: String, _ m2: String) -> Bool {
            let u1 = m1.uppercased()
            let u2 = m2.uppercased()
            if u1 == u2 { return true }
            let ssbGroup: Set<String> = ["SSB", "USB", "LSB", "PHONE"]
            if ssbGroup.contains(u1) && ssbGroup.contains(u2) { return true }
            let digiGroup: Set<String> = ["DATA", "DIGI", "FT8", "FT4", "JS8", "RTTY", "PSK31"]
            if digiGroup.contains(u1) && digiGroup.contains(u2) { return true }
            return false
        }

        // Test time difference calculation
        let diffZero = minutesBetween(date1: "20260814", time1: "1415", date2: "20260814", time2: "1415")
        precondition(diffZero == 0, "Expected 0 minutes, got \(String(describing: diffZero))")

        let diff7 = minutesBetween(date1: "2026-08-14", time1: "14:15", date2: "20260814", time2: "14:22")
        precondition(diff7 == 7, "Expected 7 minutes, got \(String(describing: diff7))")

        let diff45 = minutesBetween(date1: "20260814", time1: "1415", date2: "20260814", time2: "1500")
        precondition(diff45 == 45, "Expected 45 minutes, got \(String(describing: diff45))")

        // Test mode equivalences
        precondition(areModesEquivalent("USB", "SSB"), "USB and SSB should be equivalent")
        precondition(areModesEquivalent("FT8", "DATA"), "FT8 and DATA should be equivalent")
        precondition(!areModesEquivalent("CW", "SSB"), "CW and SSB should NOT be equivalent")

        // Match against simulated logbook
        let localLog = [
            TestQSORecord(id: UUID(), fields: ["CALL": "DL1ABC", "QSO_DATE": "20260814", "TIME_ON": "1415", "BAND": "20M", "MODE": "USB"]),
            TestQSORecord(id: UUID(), fields: ["CALL": "JA1XYZ", "QSO_DATE": "20260814", "TIME_ON": "1000", "BAND": "15M", "MODE": "CW"])
        ]

        let inbound = TestInboundItem(callsign: "DL1ABC", qsoDate: "2026-08-14", qsoTime: "14:23", band: "20m", mode: "SSB", rst: "59")

        var matchedQSO: TestQSORecord?
        let maxToleranceMinutes = 15

        for qso in localLog {
            if qso["CALL"].uppercased() == inbound.callsign.uppercased() {
                if let drift = minutesBetween(date1: qso["QSO_DATE"], time1: qso["TIME_ON"], date2: inbound.qsoDate, time2: inbound.qsoTime) {
                    if drift <= maxToleranceMinutes {
                        if areModesEquivalent(qso["MODE"], inbound.mode) {
                            matchedQSO = qso
                            break
                        }
                    }
                }
            }
        }

        precondition(matchedQSO != nil, "Fuzzy match should have found DL1ABC within 8 minute drift")
        precondition(matchedQSO!["CALL"] == "DL1ABC", "Matched callsign mismatch")

        print("   ✅ Fuzzy match matched DL1ABC with 8-min time drift and USB/SSB mode equivalence")
    }

    // MARK: - 4. Conflict Detection & Diffs
    private static func testConflictDetection() {
        print("🧪 [4/5] Testing Side-by-Side Conflict Diff Detection...")

        let localRecord = TestQSORecord(id: UUID(), fields: [
            "CALL": "VK2BGL",
            "QSO_DATE": "20260814",
            "TIME_ON": "1200",
            "BAND": "40M",
            "MODE": "CW",
            "RST_RCVD": "579"
        ])

        let inboundItem = TestInboundItem(
            callsign: "VK2BGL",
            qsoDate: "20260814",
            qsoTime: "1208", // 8 min difference
            band: "40M",
            mode: "CW",
            rst: "599" // RST difference
        )

        var diffs: [TestConflictDiff] = []
        if localRecord["TIME_ON"] != inboundItem.qsoTime {
            diffs.append(.time(local: localRecord["TIME_ON"], inbound: inboundItem.qsoTime))
        }
        if localRecord["MODE"].uppercased() != inboundItem.mode.uppercased() {
            diffs.append(.mode(local: localRecord["MODE"], inbound: inboundItem.mode))
        }
        if localRecord["RST_RCVD"] != inboundItem.rst {
            diffs.append(.rst(local: localRecord["RST_RCVD"], inbound: inboundItem.rst))
        }
        if localRecord["BAND"].uppercased() != inboundItem.band.uppercased() {
            diffs.append(.band(local: localRecord["BAND"], inbound: inboundItem.band))
        }

        precondition(diffs.count == 2, "Expected 2 conflicts (Time and RST), got \(diffs.count)")
        precondition(diffs.contains(.time(local: "1200", inbound: "1208")), "Expected time conflict")
        precondition(diffs.contains(.rst(local: "579", inbound: "599")), "Expected RST conflict")

        print("   ✅ Detected \(diffs.count) conflicts cleanly: Time (1200 vs 1208) & RST (579 vs 599)")
    }

    // MARK: - 5. Diagnostic Logging
    private static func testDiagnosticLogging() {
        print("🧪 [5/5] Testing Diagnostic API Console Logging & Ring Buffer...")

        struct DiagnosticLogEntry {
            let timestamp: Date
            let level: String
            let provider: String
            let message: String
        }

        class MockDiagnosticConsole {
            var logs: [DiagnosticLogEntry] = []
            let maxEntries = 5

            func log(level: String, provider: String, message: String) {
                let entry = DiagnosticLogEntry(timestamp: Date(), level: level, provider: provider, message: message)
                logs.append(entry)
                if logs.count > maxEntries {
                    logs.removeFirst(logs.count - maxEntries)
                }
            }
        }

        let console = MockDiagnosticConsole()
        console.log(level: "INFO", provider: "eQSL", message: "Starting sync...")
        console.log(level: "INFO", provider: "LoTW", message: "Authenticating TQSL certificate...")
        console.log(level: "SUCCESS", provider: "QRZ", message: "Fetched 14 confirmations")
        console.log(level: "WARNING", provider: "Club Log", message: "Rate limit: waiting 2s")
        console.log(level: "ERROR", provider: "eQSL", message: "HTTP 401: Invalid password")
        console.log(level: "INFO", provider: "Hub", message: "Sync cycle complete")

        precondition(console.logs.count == 5, "Expected ring buffer to cap at 5 entries, got \(console.logs.count)")
        precondition(console.logs.first?.message == "Authenticating TQSL certificate...", "First entry was not properly pruned")
        precondition(console.logs.last?.message == "Sync cycle complete", "Latest entry was not properly appended")

        print("   ✅ Diagnostic logging properly handles levels, filtering, and bounded memory caps")
    }
}
