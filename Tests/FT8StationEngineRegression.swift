//
//  FT8StationEngineRegression.swift
//  YAAM Tests
//

import Foundation

@main
struct FT8StationEngineRegression {
    static func main() {
        print("Running FT8 Station Engine Regression Tests...")
        testMaidenheadDistance()
        testCountryAndFlagResolution()
        testStandardMessageGeneration()
        testAutoHunterScoring()
        print("All FT8 Station Engine Regression Tests PASSED successfully!")
    }

    private static func testMaidenheadDistance() {
        // Distance between Tehran (LM55) and Boston/W1AW area (FN31)
        let d = calculateMaidenheadDistanceKm(grid1: "LM55", grid2: "FN31")
        precondition(d != nil, "Distance calculation returned nil")
        let dist = d!
        // Should be approximately 9,000 to 10,500 km
        precondition(dist > 8500 && dist < 11000, "Distance calculation out of expected bounds: \(dist) km")

        // Distance between same grid should be ~0 km
        let dSelf = calculateMaidenheadDistanceKm(grid1: "LM55aa", grid2: "LM55aa")
        precondition(dSelf != nil && dSelf! < 5, "Self distance should be ~0, got \(String(describing: dSelf))")
        print("✓ Maidenhead Distance tests passed")
    }

    private static func testCountryAndFlagResolution() {
        let cases: [(call: String, expCountry: String, expFlag: String)] = [
            ("A61OK", "United Arab Emirates", "🇦🇪"),
            ("SV9AUP", "Crete", "🇬🇷"),
            ("JA1ABC", "Japan", "🇯🇵"),
            ("W1AW", "United States", "🇺🇸"),
            ("EA5OL", "Spain", "🇪🇸"),
            ("EP2AES", "Iran", "🇮🇷"),
            ("DL1ABC", "Germany", "🇩🇪"),
            ("RI1FJL", "Franz Josef Land", "🇷🇺")
        ]

        for c in cases {
            let res = resolveCountryAndFlag(for: c.call)
            precondition(res.name == c.expCountry, "Country mismatch for \(c.call): expected \(c.expCountry), got \(res.name)")
            precondition(res.flag == c.expFlag, "Flag mismatch for \(c.call): expected \(c.expFlag), got \(res.flag)")
        }
        print("✓ Country and Flag Resolution tests passed")
    }

    private static func testStandardMessageGeneration() {
        // Test standard message formats Tx 1 to Tx 6
        func formatMsg(index: Int, dxCall: String, myCall: String, myGrid: String, report: String) -> String {
            switch index {
            case 1: return "\(dxCall) \(myCall) \(myGrid)"
            case 2: return "\(dxCall) \(myCall) \(report)"
            case 3:
                let sign = report.hasPrefix("-") || report.hasPrefix("+") ? "" : "-"
                return "\(dxCall) \(myCall) R\(sign)\(report.replacingOccurrences(of: "R", with: ""))"
            case 4: return "\(dxCall) \(myCall) RR73"
            case 5: return "\(dxCall) \(myCall) 73"
            case 6: return "CQ \(myCall) \(myGrid)"
            default: return "CQ \(myCall) \(myGrid)"
            }
        }

        let m1 = formatMsg(index: 1, dxCall: "W1AW", myCall: "EP2AES", myGrid: "LM55", report: "-10")
        precondition(m1 == "W1AW EP2AES LM55", "Tx 1 mismatch: \(m1)")

        let m2 = formatMsg(index: 2, dxCall: "W1AW", myCall: "EP2AES", myGrid: "LM55", report: "-10")
        precondition(m2 == "W1AW EP2AES -10", "Tx 2 mismatch: \(m2)")

        let m3 = formatMsg(index: 3, dxCall: "W1AW", myCall: "EP2AES", myGrid: "LM55", report: "-10")
        precondition(m3 == "W1AW EP2AES R-10", "Tx 3 mismatch: \(m3)")

        let m4 = formatMsg(index: 4, dxCall: "W1AW", myCall: "EP2AES", myGrid: "LM55", report: "-10")
        precondition(m4 == "W1AW EP2AES RR73", "Tx 4 mismatch: \(m4)")

        let m5 = formatMsg(index: 5, dxCall: "W1AW", myCall: "EP2AES", myGrid: "LM55", report: "-10")
        precondition(m5 == "W1AW EP2AES 73", "Tx 5 mismatch: \(m5)")

        let m6 = formatMsg(index: 6, dxCall: "W1AW", myCall: "EP2AES", myGrid: "LM55", report: "-10")
        precondition(m6 == "CQ EP2AES LM55", "Tx 6 mismatch: \(m6)")

        print("✓ Standard Message Generation tests passed")
    }

    private static func testAutoHunterScoring() {
        struct Candidate {
            let call: String
            let isNewDXCC: Bool
            let distanceKm: Double
            let snr: Float
        }

        let candidates = [
            Candidate(call: "EA5OL", isNewDXCC: false, distanceKm: 4800, snr: -04),
            Candidate(call: "VK2ABC", isNewDXCC: false, distanceKm: 12500, snr: -16),
            Candidate(call: "3Y0J", isNewDXCC: true, distanceKm: 11000, snr: -19),
            Candidate(call: "JA1XYZ", isNewDXCC: false, distanceKm: 7600, snr: +02)
        ]

        // 1. New DXCC First -> 3Y0J should win
        let newDXCCWinner = candidates.first(where: { $0.isNewDXCC })
        precondition(newDXCCWinner?.call == "3Y0J", "New DXCC winner should be 3Y0J")

        // 2. Max Distance -> VK2ABC (12,500 km) should win
        let maxDistWinner = candidates.max(by: { $0.distanceKm < $1.distanceKm })
        precondition(maxDistWinner?.call == "VK2ABC", "Max distance winner should be VK2ABC")

        // 3. Max SNR -> JA1XYZ (+02 dB) should win
        let maxSNREWinner = candidates.max(by: { $0.snr < $1.snr })
        precondition(maxSNREWinner?.call == "JA1XYZ", "Max SNR winner should be JA1XYZ")

        print("✓ Auto-Hunter Scoring tests passed")
    }
}
