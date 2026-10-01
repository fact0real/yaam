import Foundation

extension AppState {
    var operatorDeskDestination: OperatorDeskDestination {
        .resolve(legacySection: operatorDeskSection, cwSection: cwWorkstationSection)
    }

    func openOperatorDesk(_ destination: OperatorDeskDestination) {
        if destination.legacySection == 14 {
            cwWorkstationSection = destination.cwSection
        }
        operatorDeskSection = destination.legacySection
        selectedTab = 5
        rememberOperatorDeskDestination()
    }

    func openOperatorDeskGroup(_ group: OperatorDeskGroup) {
        let saved = UserDefaults.standard.string(forKey: "operatorDesk.last.\(group.rawValue)")
        openOperatorDesk(group.restoredDestination(saved))
    }

    func rememberOperatorDeskDestination() {
        let destination = operatorDeskDestination
        UserDefaults.standard.set(destination.rawValue, forKey: "operatorDesk.last.\(destination.group.rawValue)")
    }

    func openHamTracker(callsign: String? = nil) {
        if let callsign, !callsign.isEmpty {
            HamTrackerEngine.shared.setTarget(callsign)
            HamTrackerEngine.shared.startMonitoring()
        }
        openOperatorDesk(.hamTracker)
    }
}
