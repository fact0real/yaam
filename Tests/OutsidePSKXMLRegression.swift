import Foundation

nonisolated struct GeoCoordinate { var latitude: Double; var longitude: Double }
nonisolated enum GeodesicMath {
    static func distanceKm(from: GeoCoordinate, to: GeoCoordinate) -> Double { 0 }
    static func initialBearing(from: GeoCoordinate, to: GeoCoordinate) -> Double { 0 }
    static func compassCardinal(for value: Double) -> String { "N" }
}
nonisolated enum TransmitIdentity { static let callsignNotSetLabel = "Not set" }
nonisolated func flagFromCallsignPrefix(_ value: String) -> String? { nil }

@main struct OutsidePSKXMLRegression {
    static func main() {
        let service = OnTheAirMonitorService()
        let values = ["nan", "inf", "-inf", "1e30", "-5", "9223372036854775807", "", "not-a-number", "1792756544.75"]
        let xml = "<receptionReports>" + values.map {
            "<receptionReport senderCallsign=\"TEST\" receiverCallsign=\"RXTEST\" frequency=\"14074000\" flowStartSeconds=\"\($0)\" mode=\"FT8\" />"
        }.joined() + "</receptionReports>"
        let spots = service.parseFixture(Data(xml.utf8))
        precondition(spots.count == 1 && spots[0].id.hasSuffix("1792756544"))
        precondition(spots[0].timestamp.timeIntervalSince1970 == 1_792_756_544.75)
        print("PASS real On-Air XML parser discards malformed/oversized dates and preserves the valid report in the same feed")
    }
}
