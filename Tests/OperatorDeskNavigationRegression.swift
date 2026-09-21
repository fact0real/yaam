import Foundation

// Run with OperatorDeskNavigation.swift; no radio, account, or AppState startup required.
@main
struct OperatorDeskNavigationRegression {
    static func main() {
        // Previously persisted deep links must keep the same meaning after regrouping.
        let legacyDestinations: [OperatorDeskDestination] = [
            .quickLog, .dxCluster, .logSources, .radioBridge, .contest, .qslHub,
            .awards, .portable, .cloudCompanion, .calendar, .clubLogSpots, .sixMeter,
            .globeGrids, .bandmap, .cwKeyer, .clubs, .tci, .on4kst, .cwHardware,
            .qslLabels, .callRoster, .dxNews, .shackClock, .digitalSuite, .emulator, .multiRigFT8
        ]
        for (section, expected) in legacyDestinations.enumerated() {
            precondition(OperatorDeskDestination.resolve(legacySection: section) == expected,
                         "Saved section \(section) no longer opens \(expected)")
        }
        for (section, expected) in [OperatorDeskDestination.cwKeyer, .cwAcademy, .cwReference, .cwDecoder, .cwPileup].enumerated() {
            precondition(OperatorDeskDestination.resolve(legacySection: 14, cwSection: section) == expected)
        }

        // Every capability must be reachable exactly once, including former nested workspaces.
        let destinations = OperatorDeskGroup.allCases.flatMap(\.destinations)
        precondition(Set(destinations).count == destinations.count, "Duplicate navigation destination")
        precondition(Set(destinations) == Set(OperatorDeskDestination.allCases), "Unreachable tool")
        for destination in destinations {
            precondition(destination.group.destinations.contains(destination))
            precondition(OperatorDeskDestination.resolve(legacySection: destination.legacySection,
                                                        cwSection: destination.cwSection) == destination)
            precondition(destination.group.restoredDestination(destination.rawValue) == destination)
        }

        // Corrupt, removed, or cross-group preferences must never land on an unrelated tool.
        precondition(OperatorDeskDestination.resolve(legacySection: 30) == .quickLog)
        precondition(OperatorDeskDestination.resolve(legacySection: -1) == .quickLog)
        precondition(OperatorDeskDestination.resolve(legacySection: 14, cwSection: 99) == .cwKeyer)
        precondition(OperatorDeskGroup.cw.restoredDestination("deleted-tool") == .cwKeyer)
        precondition(OperatorDeskGroup.qslData.restoredDestination("emulator") == .qslHub)
        precondition(OperatorDeskGroup.radioDigital.restoredDestination(nil) == .radioBridge)

        // The finder must still recognize names users learned before the reorganization.
        precondition(OperatorDeskDestination.logSources.matches("sync center"))
        precondition(OperatorDeskDestination.cloudCompanion.matches("connected station"))
        precondition(OperatorDeskDestination.cwHardware.matches("winkeyer"))
        precondition(OperatorDeskDestination.qslLabels.matches("qsl label designer"))
        precondition(OperatorDeskDestination.ft8.matches("native FT8"))
        precondition(OperatorDeskDestination.sixMeter.matches("6m Band"))
        precondition(OperatorDeskDestination.clubs.matches("Clubs"))
        precondition(OperatorDeskDestination.multiRigFT8.matches("Multi-Rig Cluster"))
        precondition(OperatorDeskDestination.digitalSuite.matches("Digital Modes Suite"))
        precondition(!OperatorDeskDestination.ft8.matches("zzzz no match"))
        precondition(destinations.allSatisfy { $0.matches("  ") })
        print("Operator Desk regression passed: 26 legacy routes, CW shortcuts, \(destinations.count) unique tools, restoration, and search aliases.")
    }
}
