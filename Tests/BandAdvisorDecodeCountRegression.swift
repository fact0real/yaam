import Foundation

// Behaviour test of the band advisor's decode count (TacticalBandAdvisor.recordDecodes). It runs the real advisor
// with the feed the app gives it: WSJTXListener publishes the whole list of the last 10 minutes twice per new decode
// (WSJTXListener.swift, insert and then the filtered list), and each publication reaches the advisor twice, directly
// and through DigitalCallRosterEngine.processDecodes (AppStateRadioContestFeatures.swift). Each decode must count
// once, at the time it was received.
//
// Build and run from the repository root, with the app's Swift settings:
//   swiftc -parse-as-library -swift-version 5 -default-isolation MainActor \
//       -enable-upcoming-feature NonisolatedNonsendingByDefault -enable-upcoming-feature InferIsolatedConformances \
//       -enable-upcoming-feature DisableOutwardActorInference -enable-upcoming-feature GlobalActorIsolatedTypesUsability \
//       -enable-upcoming-feature InferSendableFromCaptures -enable-upcoming-feature MemberImportVisibility \
//       -module-name YAAM \
//       Tests/BandAdvisorDecodeCountRegression.swift YAAM/TacticalBandAdvisor.swift YAAM/OperatorModels.swift \
//       YAAM/AmateurBandSettings.swift YAAM/PortableActivity.swift YAAM/DXCCDatabase.swift YAAM/CountryFlagEngine.swift \
//       YAAM/CountryNameNormalizer.swift -o badc && ./badc
// No radio, network or cluster: the decodes are made here.

// Stand-ins: only the members the advisor and the band plan use. The real WSJTXLiveDecode (WSJTXListener.swift) is a
// struct with these fields among others; each decode gets its own id when it is received.
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

/// Feeds the decodes one by one as the app does: the whole list, four times per new decode.
@MainActor private func feedAsTheApp(_ advisor: TacticalBandAdvisor, _ decodes: [WSJTXLiveDecode], band: String,
                                     list: inout [WSJTXLiveDecode]) {
    for d in decodes {
        list.insert(d, at: 0)
        for _ in 0..<2 { advisor.recordDecodes(list, onBand: band) }   // the insert's publication, by both paths
        for _ in 0..<2 { advisor.recordDecodes(list, onBand: band) }   // the filtered list's publication, by both paths
    }
}

@main
struct BandAdvisorDecodeCountRegression {
    static func main() {
        // 20 m, quiet and fading: 2 decodes per 15 s cycle over the last 2 minutes (16 decodes, 8 per minute); the
        // first cycle at -3 dB, the rest at -20 dB.
        let now = Date()
        var decodes: [WSJTXLiveDecode] = []
        for cycle in 0..<8 {
            for slot in 0..<2 {
                let age = 112.0 - Double(cycle) * 15.0 - Double(slot)
                decodes.append(WSJTXLiveDecode(snr: cycle == 0 ? -3 : -20, receivedAt: now.addingTimeInterval(-age)))
            }
        }
        let advisor = TacticalBandAdvisor()
        advisor.setActiveBand("20M")
        var list: [WSJTXLiveDecode] = []
        feedAsTheApp(advisor, decodes, band: "20M", list: &list)
        let s20 = advisor.bandSnapshots["20M"]
        check("16 decodes in 2 minutes count as 8 per minute, not once per time the list arrives",
              s20?.decodesPerMinute == 8.0, "\(s20?.decodesPerMinute ?? -1) per minute")
        check("the average SNR is that of the 16 decodes (-17.875 dB), each counted once",
              abs((s20?.averageSNR ?? 0) - (-17.875)) < 0.001, "\(s20?.averageSNR ?? 0) dB")
        check("a quiet, fading band scores as such (18 + 14 = 32 %), below the 45 % under which a QSY can be offered",
              s20?.healthPercentage == 32, "\(s20?.healthPercentage ?? -1) %")

        // After a QSY to 15 m, the listener still holds the 20 m decodes of the last 10 minutes and publishes them with
        // the next 15 m decode: they are not 15 m decodes.
        advisor.setActiveBand("15M")
        feedAsTheApp(advisor, [WSJTXLiveDecode(snr: -10, receivedAt: Date())], band: "15M", list: &list)
        let s15 = advisor.bandSnapshots["15M"]
        check("after a band change, the decodes of the previous band in the list are not counted on the new one",
              s15?.decodesPerMinute == 0.5, "\(s15?.decodesPerMinute ?? -1) per minute on 15 m")

        // A decode received 11 minutes ago is outside the advisor's 10-minute window, whenever it arrives.
        let fresh = TacticalBandAdvisor()
        fresh.setActiveBand("40M")
        fresh.recordDecodes([WSJTXLiveDecode(snr: -5, receivedAt: Date().addingTimeInterval(-660))], onBand: "40M")
        check("a decode received more than 10 minutes ago is not counted as a recent one",
              (fresh.bandSnapshots["40M"]?.decodesPerMinute ?? -1) == 0.0,
              "\(fresh.bandSnapshots["40M"]?.decodesPerMinute ?? -1) per minute")

        // A decode received 3 minutes ago is inside the 10-minute window but outside the 2 minutes the rate is taken
        // over, also when it reaches the advisor only now.
        let late = TacticalBandAdvisor()
        late.setActiveBand("40M")
        late.recordDecodes([WSJTXLiveDecode(snr: -5, receivedAt: Date().addingTimeInterval(-180))], onBand: "40M")
        check("a decode received 3 minutes ago counts at the time it was received, not when it reached the advisor",
              (late.bandSnapshots["40M"]?.decodesPerMinute ?? -1) == 0.0,
              "\(late.bandSnapshots["40M"]?.decodesPerMinute ?? -1) per minute")

        if failures > 0 {
            print("Band advisor decode count regression FAILED: \(failures) check(s)")
            exit(1)
        }
        print("Band advisor decode count regression passed")
    }
}
