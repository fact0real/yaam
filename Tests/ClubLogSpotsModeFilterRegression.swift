//
//  ClubLogSpotsModeFilterRegression.swift
//  YAAM Tests
//

import Foundation

// Local mirror for standalone regression testing
struct SpotModelTest {
    let callsign: String
    let frequency: String
    let band: String
    let mode: String
    let timeStr: String
    let dxcc: String
    let spotter: String
    let comment: String
    let status: String

    var isDigital: Bool {
        let m = mode.uppercased()
        let c = comment.uppercased()
        return m == "FT8" || m == "FT4" || m == "RTTY" || m == "PSK" || m == "PSK31" || m == "JS8" || m == "DATA" || m == "DIGI" || m == "Q65" || m == "MSK144" || m.contains("FT") || c.contains("FT8") || c.contains("FT4") || c.contains("RTTY") || c.contains("PSK")
    }

    var isVoice: Bool {
        let m = mode.uppercased()
        let c = comment.uppercased()
        return m == "SSB" || m == "USB" || m == "LSB" || m == "AM" || m == "FM" || m == "PHONE" || c.contains("SSB") || c.contains("USB") || c.contains("LSB") || c.contains("PHONE")
    }

    var isCW: Bool {
        let m = mode.uppercased()
        let c = comment.uppercased()
        return m == "CW" || c.contains("CW") || c.contains("CWT")
    }
}

func detectModeTest(comment: String, freqKHz: Double, band: String) -> String {
    let cLower = comment.lowercased()

    // 1. Explicit comment mode keywords take top priority
    if cLower.contains("ft8") {
        return "FT8"
    } else if cLower.contains("ft4") {
        return "FT4"
    } else if cLower.contains("rtty") {
        return "RTTY"
    } else if cLower.contains("psk") {
        return "PSK"
    } else if cLower.contains("js8") {
        return "JS8"
    } else if cLower.contains("cw") || cLower.contains("cwt") || cLower.contains("qsx") || cLower.contains("up ") || cLower.hasPrefix("up") || cLower.contains(" up") {
        return "CW"
    } else if cLower.contains("usb") {
        return "USB"
    } else if cLower.contains("lsb") {
        return "LSB"
    } else if cLower.contains("ssb") || cLower.contains("pota") || cLower.contains("phone") {
        return "SSB"
    }

    // 2. Standard Digital Frequency Detection
    let ft8Freqs = [1840.0, 3573.0, 5357.0, 7074.0, 7056.0, 10131.0, 10136.0, 14074.0, 18100.0, 21074.0, 24915.0, 28074.0, 50313.0]
    let ft4Freqs = [3575.0, 7047.5, 10140.0, 14080.0, 18104.0, 21140.0, 24919.0, 28180.0, 50318.0]

    if ft8Freqs.contains(where: { abs(freqKHz - $0) < 1.5 }) {
        return "FT8"
    } else if ft4Freqs.contains(where: { abs(freqKHz - $0) < 1.5 }) {
        return "FT4"
    }

    // 3. Band Frequency Phone / Voice Segments
    if band == "20M" && freqKHz >= 14100 {
        return "SSB"
    } else if band == "15M" && freqKHz >= 21200 {
        return "SSB"
    } else if band == "40M" && freqKHz >= 7100 {
        return "SSB"
    } else if band == "80M" && freqKHz >= 3600 {
        return "SSB"
    } else if band == "10M" && freqKHz >= 28300 {
        return "SSB"
    }

    return "CW"
}

@main
struct ClubLogSpotsModeFilterRegression {
    static func main() {
        print("Running ClubLog Spots Mode Filter Regression Tests...")
        testModeDetection()
        testHelperProperties()
        testFilterLogic()
        print("All ClubLog Spots Mode Filter Regression Tests PASSED successfully!")
    }

    private static func testModeDetection() {
        // FT8 by frequency & comment
        precondition(detectModeTest(comment: "ft8 -12 db", freqKHz: 14074.0, band: "20M") == "FT8")
        precondition(detectModeTest(comment: "cq", freqKHz: 7074.0, band: "40M") == "FT8")
        precondition(detectModeTest(comment: "ft8 10 multistream", freqKHz: 24911.0, band: "12M") == "FT8")

        // FT4 by frequency & comment
        precondition(detectModeTest(comment: "ft4", freqKHz: 7047.5, band: "40M") == "FT4")
        precondition(detectModeTest(comment: "cq", freqKHz: 14080.0, band: "20M") == "FT4")

        // CW
        precondition(detectModeTest(comment: "cq up 1", freqKHz: 10137.3, band: "30M") == "CW")
        precondition(detectModeTest(comment: "cwt test", freqKHz: 14025.0, band: "20M") == "CW")

        // SSB / Phone / USB / LSB
        precondition(detectModeTest(comment: "qrp station w/ wire call: kg67", freqKHz: 7153.0, band: "40M") == "SSB")
        precondition(detectModeTest(comment: "pota k-1234", freqKHz: 14225.0, band: "20M") == "SSB")
        precondition(detectModeTest(comment: "loud usb", freqKHz: 28400.0, band: "10M") == "USB")
        precondition(detectModeTest(comment: "lsb 59", freqKHz: 3750.0, band: "80M") == "LSB")
        precondition(detectModeTest(comment: "", freqKHz: 14250.0, band: "20M") == "SSB")
    }

    private static func testHelperProperties() {
        let ft8Spot = SpotModelTest(callsign: "RI1FJL", frequency: "14.074", band: "20M", mode: "FT8", timeStr: "05:11", dxcc: "FRANZ JOSEF LAND", spotter: "JM1CMA", comment: "ft8", status: "Needed")
        precondition(ft8Spot.isDigital == true)
        precondition(ft8Spot.isVoice == false)
        precondition(ft8Spot.isCW == false)

        let ft4Spot = SpotModelTest(callsign: "RI1FJL", frequency: "7.0475", band: "40M", mode: "FT4", timeStr: "05:01", dxcc: "FRANZ JOSEF LAND", spotter: "AB5WL", comment: "ft4", status: "Needed")
        precondition(ft4Spot.isDigital == true)
        precondition(ft4Spot.isVoice == false)
        precondition(ft4Spot.isCW == false)

        let cwSpot = SpotModelTest(callsign: "P29YY", frequency: "24.911", band: "12M", mode: "CW", timeStr: "04:56", dxcc: "PAPUA NEW GUINEA", spotter: "SV1QEW", comment: "cq", status: "Needed")
        precondition(cwSpot.isCW == true)
        precondition(cwSpot.isDigital == false)
        precondition(cwSpot.isVoice == false)

        let ssbSpot = SpotModelTest(callsign: "C91CCY", frequency: "7.153", band: "40M", mode: "SSB", timeStr: "04:32", dxcc: "MOZAMBIQUE", spotter: "K1QD", comment: "qrp station", status: "Needed")
        precondition(ssbSpot.isVoice == true)
        precondition(ssbSpot.isDigital == false)
        precondition(ssbSpot.isCW == false)
    }

    private static func testFilterLogic() {
        let spots = [
            SpotModelTest(callsign: "RI1FJL", frequency: "14.074", band: "20M", mode: "FT8", timeStr: "05:11", dxcc: "FRANZ JOSEF LAND", spotter: "JM1CMA", comment: "ft8", status: "Needed"),
            SpotModelTest(callsign: "RI1FJL", frequency: "7.0475", band: "40M", mode: "FT4", timeStr: "05:01", dxcc: "FRANZ JOSEF LAND", spotter: "AB5WL", comment: "ft4", status: "Needed"),
            SpotModelTest(callsign: "P29YY", frequency: "24.911", band: "12M", mode: "CW", timeStr: "04:56", dxcc: "PAPUA NEW GUINEA", spotter: "SV1QEW", comment: "cq", status: "Needed"),
            SpotModelTest(callsign: "C91CCY", frequency: "7.153", band: "40M", mode: "SSB", timeStr: "04:32", dxcc: "MOZAMBIQUE", spotter: "K1QD", comment: "qrp station", status: "Needed")
        ]

        // Filter: All
        let all = spots.filter { _ in true }
        precondition(all.count == 4)

        // Filter: Digital
        let digi = spots.filter { $0.isDigital }
        precondition(digi.count == 2)
        precondition(digi.contains(where: { $0.mode == "FT8" }))
        precondition(digi.contains(where: { $0.mode == "FT4" }))

        // Filter: CW
        let cw = spots.filter { $0.isCW }
        precondition(cw.count == 1)
        precondition(cw.first?.callsign == "P29YY")

        // Filter: Phone
        let phone = spots.filter { $0.isVoice }
        precondition(phone.count == 1)
        precondition(phone.first?.callsign == "C91CCY")

        // Filter: FT8 specific
        let ft8Only = spots.filter { $0.mode.uppercased() == "FT8" }
        precondition(ft8Only.count == 1)
    }
}
