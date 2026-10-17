import Foundation

// Behaviour test of the band advisor's use of the DX Cluster (TacticalBandAdvisor.recordClusterSpots and the health
// of a band the station is not listening to). It runs the real advisor with the feed the app gives it: every change of
// the cluster's spot list (DXClusterClient.spots, up to 800 spots, old ones included) is handed over whole
// (AppStateRadioContestFeatures.swift). Each spot must count once, at the last time the cluster reported it, and a
// band heard only through the cluster must be able to earn a recommendation with one receiver.
//
// Build and run from the repository root, with the app's Swift settings:
//   swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
//       -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
//       -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
//       -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
//       -module-name YAAM \
//       Tests/BandAdvisorClusterRegression.swift YAAM/TacticalBandAdvisor.swift YAAM/OperatorModels.swift \
//       YAAM/AmateurBandSettings.swift YAAM/PortableActivity.swift YAAM/DXCCDatabase.swift YAAM/CountryFlagEngine.swift \
//       YAAM/CountryNameNormalizer.swift -o bacl && ./bacl
// No radio, network or cluster: the spots are made here, for invented stations (0A0BC…) and spotters (0Z9ZZ).

// Stand-ins: only the members the advisor and the band plan use (DXSpot is the real one, from OperatorModels.swift).
nonisolated public struct WSJTXLiveDecode: Identifiable, Sendable {
    public var id = UUID()
    public var snr: Int32
    public var receivedAt: Date
}
final class RigControlClient {
    func setFrequencyHz(_ hz: UInt64) {}
    func setMode(_ mode: String, passbandHz: Int) {}
}
nonisolated struct QSORecordModel {
    var fields: [String: String] = [:]
    var isConfirmed = false
    subscript(key: String) -> String { fields[key] ?? "" }
}

private var failures = 0

private func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok {
        print("PASS \(name)")
    } else {
        let more = detail()
        print("FAIL \(name)\(more.isEmpty ? "" : "   [\(more)]")")
        failures += 1
    }
}

/// `count` spots on one band, last reported by the cluster `ageSeconds` ago.
private func spots(_ count: Int, on band: String, kHz: Double, ageSeconds: Double) -> [DXSpot] {
    let at = Date().addingTimeInterval(-ageSeconds)
    return (0..<count).map { n in
        DXSpot(id: "\(band)-\(n)-\(Int(ageSeconds))", callsign: "0A\(n)BC", spotter: "0Z9ZZ", frequencyKHz: kHz + Double(n),
               band: band, mode: "CW", submode: "", comment: "", grid: "", spottedAt: at, lastSeenAt: at, reportCount: 1)
    }
}

@main
struct BandAdvisorClusterRegression {
    static func main() {
        let busy15 = spots(30, on: "15M", kHz: 21_010, ageSeconds: 60)

        let counts = TacticalBandAdvisor()
        counts.setActiveBand("20M")
        for _ in 0..<3 { counts.recordClusterSpots(busy15) }   // the same list published three times
        check("each spot counts once, however many times the cluster's list is handed over",
              counts.bandSnapshots["15M"]?.clusterSpotCount == 30, "\(counts.bandSnapshots["15M"]?.clusterSpotCount ?? -1) spots")
        counts.recordClusterSpots([])
        check("when the cluster's list is emptied, its spots no longer count",
              counts.bandSnapshots["15M"]?.clusterSpotCount == 0, "\(counts.bandSnapshots["15M"]?.clusterSpotCount ?? -1) spots")

        let old = TacticalBandAdvisor()
        old.setActiveBand("20M")
        old.recordClusterSpots(spots(30, on: "15M", kHz: 21_010, ageSeconds: 3 * 3600))
        check("spots the cluster last reported 3 hours ago are not recent activity",
              old.bandSnapshots["15M"]?.clusterSpotCount == 0, "\(old.bandSnapshots["15M"]?.clusterSpotCount ?? -1) spots")

        // One receiver, on 20 m, hearing nothing; 15 m busy on the cluster.
        let one = TacticalBandAdvisor()
        one.setActiveBand("20M")
        one.recordClusterSpots(spots(25, on: "15M", kHz: 21_010, ageSeconds: 120))
        check("with one receiver, a silent band and another busy on the cluster (25 spots in 10 minutes): a QSY is offered",
              one.activeRecommendation?.targetBand == "15M",
              "recommendation: \(one.activeRecommendation?.targetBand ?? "none"), 15 m at \(one.bandSnapshots["15M"]?.healthPercentage ?? -1) %")
        check("that band scores 70 % from the cluster alone (20 spots or more in 10 minutes)",
              one.bandSnapshots["15M"]?.healthPercentage == 70, "\(one.bandSnapshots["15M"]?.healthPercentage ?? -1) %")
        let staleRecommendation = one.activeRecommendation
        one.recordClusterSpots([])
        check("a recommendation is withdrawn when its supporting spots disappear", one.activeRecommendation == nil)
        if let staleRecommendation {
            one.executeQSY(to: staleRecommendation, rigClient: nil)
            check("a withdrawn recommendation cannot retune the station", one.activeBand == "20M")
        }

        let some = TacticalBandAdvisor()
        some.setActiveBand("20M")
        some.recordClusterSpots(spots(12, on: "15M", kHz: 21_010, ageSeconds: 120))
        check("12 spots in 10 minutes are not enough on their own for a QSY (45 %)",
              some.activeRecommendation == nil && some.bandSnapshots["15M"]?.healthPercentage == 45,
              "recommendation: \(some.activeRecommendation?.targetBand ?? "none"), 15 m at \(some.bandSnapshots["15M"]?.healthPercentage ?? -1) %")

        // The band the station is on, hearing nothing although the cluster is busy there, keeps the usual scale: what
        // this station hears there counts more than what others report.
        let here = TacticalBandAdvisor()
        here.setActiveBand("20M")
        here.recordClusterSpots(spots(25, on: "20M", kHz: 14_010, ageSeconds: 120))
        check("the band the station is on is not judged by the cluster alone (25 spots, nothing heard: 30 %)",
              here.bandSnapshots["20M"]?.healthPercentage == 30, "\(here.bandSnapshots["20M"]?.healthPercentage ?? -1) %")

        if failures > 0 {
            print("Band advisor cluster regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("Band advisor cluster regression passed")
    }
}
