import Foundation

@main
struct FT8OperatingSupportRegression {
    static func main() {
        precondition(FT8MessageIdentity.sender(in: "CQ DX K1ABC FN42") == "K1ABC")
        precondition(FT8MessageIdentity.sender(in: "CQ SV2AOB KN10") == "SV2AOB")
        precondition(FT8MessageIdentity.sender(in: "W1AW <G7ABC> -10") == "G7ABC")
        precondition(FT8MessageIdentity.sender(in: "W1AW <...> -10") == nil)
        precondition(FT8MessageIdentity.sender(in: "<...> LZ936BA RR73") == "LZ936BA")
        precondition(FT8MessageIdentity.sender(in: "CQ UA9XL/M") == "UA9XL/M")
        precondition(FT8MessageIdentity.callsign("RR73") == nil)
        precondition(DXCCDatabase.resolve(callsign: "SV2AOB").entityName == "Greece")
        precondition(DXCCDatabase.resolve(callsign: "SV2RSG/A").entityName == "Mount Athos")

        let start = Date(timeIntervalSince1970: 1_000)
        var guardState = FT8SWRTripGuard()
        func trip(_ value: Double, sample: Double, enabled: Bool = true, power: Double = 20, elapsed: Double? = nil) -> Bool {
            guardState.shouldStop(enabled: enabled, startedAt: start, power: power, swr: value,
                                  sampledAt: start.addingTimeInterval(sample), now: start.addingTimeInterval(elapsed ?? sample))
        }
        precondition(!trip(4, sample: -1), "Old telemetry must not trip the new transmission")
        precondition(!trip(4, sample: 0.1))
        precondition(!trip(4, sample: 0.1), "One meter sample must not count twice")
        precondition(trip(4, sample: 0.3), "Two fresh high readings must trip")
        precondition(!trip(4, sample: 0.5, enabled: false))
        precondition(!trip(4, sample: 0.7, power: 0))
        precondition(!trip(4, sample: 0.8, elapsed: 4), "Stale telemetry must be rejected")
        precondition(!trip(2.5, sample: 5), "Threshold is strictly above 2.5")
        precondition(!trip(.nan, sample: 5.1))
        precondition(!trip(3, sample: 5.2))
        precondition(!trip(2, sample: 5.3))
        precondition(!trip(3, sample: 5.4), "A safe reading breaks the consecutive streak")
        precondition(trip(3, sample: 5.5))

        var row = [Float](repeating: 0.9, count: 481)
        for i in 130...160 { row[i] = 0.1 }
        let rows = Array(repeating: row, count: 20)
        let suggestion = FT8QuietFrequencyAdvisor.suggest(rows: rows, minimumHz: 200, binHz: 6, bandwidthHz: 50, occupied: [])
        precondition(suggestion != nil && (1000...1100).contains(suggestion!))
        precondition(FT8QuietFrequencyAdvisor.suggest(rows: rows, minimumHz: 200, binHz: 6, bandwidthHz: 50, occupied: [Float(suggestion!)]) == nil)
        precondition(FT8QuietFrequencyAdvisor.suggest(rows: [], minimumHz: 200, binHz: 6, bandwidthHz: 50, occupied: []) == nil)
        precondition(FT8QuietFrequencyAdvisor.suggest(rows: Array(repeating: [Float](repeating: 0.9, count: 481), count: 20), minimumHz: 200, binHz: 6, bandwidthHz: 50, occupied: []) == nil)
        print("FT8 identity, DXCC, fresh SWR telemetry and quiet-frequency regressions passed")
    }
}
