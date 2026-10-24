import Foundation

extension QSORecordModel: QSLGraylistRecord {}

extension AppState {
    func refreshQSLGraylist() {
        guard let profileID = activeStationProfileID, isMasterMode,
              loadedWorkspaceProfileID == profileID else {
            qslGraylist.reset(profileID: activeStationProfileID)
            return
        }
        qslGraylist.schedule(records: qsoRecords, profileID: profileID)
    }

    func openQSLGraylistContacts(_ entry: QSLGraylistEntry) {
        guard qslGraylist.hasWorkspace, !qslGraylist.isLoading,
              qslGraylist.index.entry(for: entry.callsign) == entry else { return }
        // Use the normal log table, with exact record selection for this callsign.
        filterCriteria = FilterCriteria()
        searchText = entry.callsign
        logSearchMode = .callsign
        selectedRecordIDs = entry.recordIDs
        selectedTab = 0
    }
}
