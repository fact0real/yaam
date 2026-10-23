import Foundation

@main struct OutsideNumberBoundsRegression {
    static func main() {
        for value in [Double.nan, .infinity, -.infinity, -5, 1e30, Double(Int.max), Double(UInt64.max)] {
            precondition(ReportTimeBounds.seconds(value) == nil)
            precondition(FrequencyBounds.hertz(kHz: value / 1000) == nil)
        }
        precondition(ReportTimeBounds.seconds(1_792_756_544.75) == 1_792_756_544)
        precondition(ReportTimeBounds.seconds(0) == 0)
        precondition(ReportTimeBounds.seconds(253_402_300_799) != nil)
        precondition(ReportTimeBounds.seconds(253_402_300_800) == nil)
        for raw in [#"{"f":-5,"t_tx":1e30}"#, #"{"f":9223372036854775807,"t_tx":1e23}"#] {
            let json = try! JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
            precondition(ReportTimeBounds.seconds(json["t_tx"] as! Double) == nil)
            precondition(!FrequencyBounds.isUsable(kHz: Double(json["f"] as! Int) / 1000))
        }
        precondition(FrequencyBounds.hertz(kHz: 14_074.0005) == 14_074_000)
        print("PASS finite/bounded Unix dates and VFOs, extreme MQTT JSON numbers, fractional valid values")
    }
}
