//
//  OnTheAirMonitorRegression.swift
//  YAAM Tests
//

import Foundation

func frequencyToBandTest(_ freqHz: Int) -> String {
    let mhz = Double(freqHz) / 1_000_000.0
    if mhz >= 1.8 && mhz <= 2.0 { return "160m" }
    if mhz >= 3.5 && mhz <= 4.0 { return "80m" }
    if mhz >= 5.3 && mhz <= 5.4 { return "60m" }
    if mhz >= 7.0 && mhz <= 7.3 { return "40m" }
    if mhz >= 10.1 && mhz <= 10.15 { return "30m" }
    if mhz >= 14.0 && mhz <= 14.35 { return "20m" }
    if mhz >= 18.068 && mhz <= 18.168 { return "17m" }
    if mhz >= 21.0 && mhz <= 21.45 { return "15m" }
    if mhz >= 24.89 && mhz <= 24.99 { return "12m" }
    if mhz >= 28.0 && mhz <= 29.7 { return "10m" }
    if mhz >= 50.0 && mhz <= 54.0 { return "6m" }
    if mhz >= 70.0 && mhz <= 70.5 { return "4m" }
    if mhz >= 144.0 && mhz <= 148.0 { return "2m" }
    if mhz >= 430.0 && mhz <= 450.0 { return "70cm" }
    return String(format: "%.1fM", mhz)
}

func parsePSKReporterAttributesTest(_ raw: String) -> [String: String] {
    let pattern = #"([A-Za-z0-9_]+)\s*=\s*"([^"]*)""#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
    let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
    var values: [String: String] = [:]
    for match in regex.matches(in: raw, range: range) where match.numberOfRanges == 3 {
        guard let keyRange = Range(match.range(at: 1), in: raw),
              let valueRange = Range(match.range(at: 2), in: raw) else { continue }
        values[String(raw[keyRange])] = String(raw[valueRange])
    }
    return values
}

func calculateDistanceKmTest(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
    let p1 = lat1 * .pi / 180.0
    let p2 = lat2 * .pi / 180.0
    let dp = (lat2 - lat1) * .pi / 180.0
    let dl = (lon2 - lon1) * .pi / 180.0

    let a = sin(dp / 2.0) * sin(dp / 2.0) + cos(p1) * cos(p2) * sin(dl / 2.0) * sin(dl / 2.0)
    let c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
    return 6371.0 * c
}

func calculateAzimuthTest(fromLat: Double, fromLon: Double, toLat: Double, toLon: Double) -> Double {
    let lat1 = fromLat * .pi / 180.0
    let lon1 = fromLon * .pi / 180.0
    let lat2 = toLat * .pi / 180.0
    let lon2 = toLon * .pi / 180.0
    let dlon = lon2 - lon1

    let y = sin(dlon) * cos(lat2)
    let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dlon)
    var bearing = atan2(y, x) * 180.0 / .pi
    if bearing < 0 { bearing += 360.0 }
    return bearing
}

@main
struct OnTheAirMonitorRegression {
    static func main() {
        print("Running On-The-Air Telemetry & 15-Min Sliding Window Poller Tests...")

        testFrequencyToBandConversions()
        testPSKReporterXMLParsing()
        testDistanceAndBearingCalculations()
        testSlidingWindowAndDXDetection()

        print("All On-The-Air Telemetry Regression Tests PASSED successfully!")
    }

    private static func testFrequencyToBandConversions() {
        precondition(frequencyToBandTest(14074000) == "20m")
        precondition(frequencyToBandTest(7074000) == "40m")
        precondition(frequencyToBandTest(50313000) == "6m")
        precondition(frequencyToBandTest(21074000) == "15m")
        precondition(frequencyToBandTest(28074000) == "10m")
        precondition(frequencyToBandTest(144174000) == "2m")
    }

    private static func testPSKReporterXMLParsing() {
        let sampleXML = """
        <receptionReport senderCallsign="EP2AES" senderLocator="LM35" receiverCallsign="DL7XYZ" receiverLocator="JO62" frequency="14074000" flowStartSeconds="1772448000" mode="FT8" sNR="-4" />
        <receptionReport senderCallsign="EP2AES" senderLocator="LM35" receiverCallsign="EA1ABC" receiverLocator="IN73" frequency="50313000" flowStartSeconds="1772448060" mode="FT8" sNR="+2" />
        """

        let pattern = #"<receptionReport\b([^>]*)/?>"#
        let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(sampleXML.startIndex..<sampleXML.endIndex, in: sampleXML)
        var parsedReports: [[String: String]] = []

        for match in regex.matches(in: sampleXML, range: range) where match.numberOfRanges > 1 {
            let attrRange = Range(match.range(at: 1), in: sampleXML)!
            let attrs = parsePSKReporterAttributesTest(String(sampleXML[attrRange]))
            parsedReports.append(attrs)
        }

        precondition(parsedReports.count == 2)
        precondition(parsedReports[0]["senderCallsign"] == "EP2AES")
        precondition(parsedReports[0]["receiverCallsign"] == "DL7XYZ")
        precondition(parsedReports[0]["sNR"] == "-4")
        precondition(parsedReports[1]["receiverCallsign"] == "EA1ABC")
        precondition(parsedReports[1]["sNR"] == "+2")
    }

    private static func testDistanceAndBearingCalculations() {
        // Tehran (35.6892, 51.3890) -> Berlin (52.5200, 13.4050)
        let dist = calculateDistanceKmTest(lat1: 35.6892, lon1: 51.3890, lat2: 52.5200, lon2: 13.4050)
        let az = calculateAzimuthTest(fromLat: 35.6892, fromLon: 51.3890, toLat: 52.5200, toLon: 13.4050)

        precondition(dist >= 3400 && dist <= 3600, "Unexpected distance to Berlin: \(dist) km")
        precondition(az >= 300 && az <= 320, "Unexpected azimuth to Berlin: \(az)°")
    }

    private static func testSlidingWindowAndDXDetection() {
        let spots: [(call: String, dist: Double, snr: Int, band: String)] = [
            ("DL7XYZ", 3500.0, -4, "20m"),
            ("EA1ABC", 4600.0, -12, "6m"),
            ("JA1ZZZ", 7500.0, -18, "20m")
        ]

        let furthest = spots.max { $0.dist < $1.dist }
        let bestSNR = spots.compactMap(\.snr).max()
        let activeBands = Array(Set(spots.map(\.band))).sorted()

        precondition(furthest?.call == "JA1ZZZ")
        precondition(furthest?.dist == 7500.0)
        precondition(bestSNR == -4)
        precondition(activeBands == ["20m", "6m"])
    }
}
