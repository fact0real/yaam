import SwiftUI

struct NextCreditView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let review: (UUID) -> Void
    @AppStorage("nextCreditCountryBand") private var countryBand = 5.0
    @AppStorage("nextCreditGrid") private var grid = 3.0
    @AppStorage("nextCreditAward") private var award = 4.0
    @AppStorage("nextCreditLikelihood") private var likelihood = 2.0
    @AppStorage("nextCreditOperational") private var operational = 1.0
    @State private var suggestions: [NextCreditSuggestion] = []
    @State private var isLoading = true
    private var weights: NextCreditWeights {
        NextCreditWeights(countryBand: countryBand, grid: grid, award: award, likelihood: likelihood, operational: operational)
    }
    private var requestKey: String {
        "\(appState.activeStationProfileID?.uuidString ?? "")|\(appState.qsoRecordsRevision)|\(weights)"
    }
    var body: some View {
        NextCreditContent(suggestions: suggestions, isLoading: isLoading,
            countryBand: $countryBand, grid: $grid, award: $award, likelihood: $likelihood, operational: $operational,
            done: { dismiss() }, review: review)
        .task(id: requestKey) {
            isLoading = true; suggestions = []
            let records = appState.qsoRecords
            let currentWeights = weights
            let work = Task.detached(priority: .userInitiated) {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "yyyyMMdd"
                let now = Date()
                let contacts = records.map { record in
                    let country = ConfirmationOpportunityIndex.normalizedCountry(for: record)
                    let state = record["STATE"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    let zone = Int(record["CQZ"]).flatMap { (1...40).contains($0) ? String($0) : nil }
                    let days = formatter.date(from: record["QSO_DATE"]).map { max(0, Int(now.timeIntervalSince($0) / 86400)) }
                    return NextCreditContact(id: record.id, identity: QSOIdentity.exactKey(fields: record.fields),
                        call: record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                        country: country, band: ConfirmationOpportunityIndex.normalizedBand(for: record),
                        grid: ConfirmationOpportunityIndex.fourCharacterGrid(for: record),
                        state: NextCreditEngine.usState(state, country: country, dxcc: record["DXCC"]),
                        cqZone: zone, confirmed: record.isConfirmed,
                        hasRoute: !record["EMAIL"].isEmpty || !record["QSL_VIA"].isEmpty,
                        daysPending: days)
                }
                return NextCreditEngine.queue(contacts: contacts, weights: currentWeights)
            }
            let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled else { return }
            suggestions = result; isLoading = false
        }
    }
}
