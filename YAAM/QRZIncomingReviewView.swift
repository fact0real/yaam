import SwiftUI

struct QRZIncomingReviewView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let request: QRZIncomingConfirmation
    var onRequestDetails: (() -> Void)? = nil
    @State private var review = IncomingContactReview()
    @State private var status = ""
    @State private var submitting = false
    @State private var stationID: UUID?

    private var candidates: [QSORecordModel] { stationID == appState.activeStationProfileID ? appState.incomingCandidates(request) : [] }
    private var savedRecord: QSORecordModel? { stationID == appState.activeStationProfileID ? appState.incomingRecoveryRecord(request) : nil }
    private var hasUnsavedChanges: Bool {
        guard let record = savedRecord else { return true }
        return !review.matchesSavedContact(record.fields)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Review QRZ Incoming · \(request.callsign)").font(.title2.bold()); Spacer(); Button("Close") { dismiss() } }
            Text("Incoming may be an unrecorded contact or inconsistent data. Call/date candidates are not confirmed matches. QRZ form defaults are not evidence.").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("1. Compare with your local log").font(.headline)
                    if candidates.isEmpty { Text("No call/date candidate in this station's open log.") }
                    ForEach(candidates) { record in
                        HStack {
                            Text("\(record["QSO_DATE"]) · \(record["TIME_ON"]) UTC · \(record["BAND"]) · \(record["MODE"]) \(record["SUBMODE"]) · \(record["STATION_CALLSIGN"])").font(.callout.monospaced())
                            Spacer()
                            Button("Use local details") { use(record) }
                        }
                    }
                    Text("For an inconsistent existing QSO, correct that record in the log editor, then review it here. Only create a separate record for a genuinely different contact.").font(.caption).foregroundStyle(.secondary)
                    Text("2. Complete actual contact details").font(.headline)
                    IncomingReviewFields(review: $review)
                    if !candidates.isEmpty {
                        Toggle("I checked the candidates; this is a separate contact", isOn: $review.separateContact)
                    }
                    Toggle("I checked my QRZ log: this exact contact is already recorded there", isOn: Binding(
                        get: { review.qrzAlreadyLogged == true },
                        set: { review.qrzAlreadyLogged = $0; review.verified = false }
                    ))
                    Text("Leave unchecked unless the date, UTC time, band and mode match an entry in your QRZ log. An Incoming request alone does not prove this.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("3. Verify before saving").font(.headline)
                    Toggle("I compared my log/notes or the operator's reply and verified these actual details", isOn: $review.verified)
                    if let problem = review.problem { Text(problem).font(.caption).foregroundStyle(.secondary) }
                    Text("Saving records the verified contact locally and queues the remaining LoTW, QRZ and Club Log uploads. The QSL Hub can send queued work; Send saved contact runs this contact now. Service acceptance is separate from QSL confirmation.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let record = savedRecord {
                        Text("Saved locally · destination progress").font(.headline)
                        ForEach(QSLProvider.allCases.filter { QSLSyncAll.incomingRecoveryProviders.contains($0) }) { provider in
                            LabeledContent(provider.title, value: appState.incomingRecoveryStatus(record, provider: provider))
                                .font(.callout).textSelection(.enabled)
                        }
                    }
                }
            }
            Text(status).font(.callout).textSelection(.enabled)
            HStack {
                Button("Request details…") { onRequestDetails?() }
                Spacer()
                Button("Save locally & queue all three") { save() }.buttonStyle(.borderedProminent)
                    .disabled(review.problem != nil || stationID != appState.activeStationProfileID || submitting || appState.isIncomingRecoveryBusy)
                Button(submitting ? "Sending…" : "Send saved contact") { send() }
                    .disabled(savedRecord == nil || hasUnsavedChanges || stationID != appState.activeStationProfileID || submitting || appState.isIncomingRecoveryBusy)
            }
        }.padding(20).frame(minWidth: 700, minHeight: 460)
        .onAppear {
            stationID = appState.activeStationProfileID
            if let record = savedRecord {
                use(record)
                review.evidence = record["APP_YAAM_INCOMING_EVIDENCE"]
            } else if let data = UserDefaults.standard.data(forKey: draftKey), let draft = try? JSONDecoder().decode(IncomingContactReview.self, from: data) {
                review = draft; review.verified = false
            } else {
                review.call = request.callsign; review.date = QSOIdentity.normalizedDate(request.qsoDate); review.station = appState.currentStationCallsign
            }
        }
        .onDisappear {
            var draft = review; draft.verified = false
            if let data = try? JSONEncoder().encode(draft) { UserDefaults.standard.set(data, forKey: draftKey) }
        }
        .onChange(of: review.separateContact) { _, _ in review.verified = false }
        .onChange(of: review.fields) { _, _ in review.verified = false }
        .onChange(of: review.evidence) { _, _ in review.verified = false }
    }
    private var draftKey: String { "incomingReviewDraft.v1." + (stationID?.uuidString ?? "none") + "." + (request.qsoID.isEmpty ? request.id : request.qsoID) }
    private func use(_ record: QSORecordModel) {
        review.call = record["CALL"]
        review.date = record["QSO_DATE"]; review.time = record["TIME_ON"]; review.band = record["BAND"]
        review.mode = record["SUBMODE"].isEmpty ? record["MODE"] : record["SUBMODE"]
        review.station = record["STATION_CALLSIGN"].isEmpty ? appState.currentStationCallsign : record["STATION_CALLSIGN"]
        review.qrzAlreadyLogged = record["APP_YAAM_QRZ_VERIFIED_PRESENT"] == "Y"
        review.evidence = "Local log record \(record.id)"; review.verified = false
    }
    private func save() {
        do {
            guard stationID == appState.activeStationProfileID else { return }
            _ = try appState.saveIncomingReview(review, request: request)
            status = "Saved locally with durable upload intents. Review destination progress below; blocked services need attention in the QSL Hub."
        } catch { status = error.localizedDescription }
    }
    private func send() {
        guard stationID == appState.activeStationProfileID, appState.isOwnStationLogOpen,
              let record = savedRecord, !hasUnsavedChanges else {
            status = "The station or contact changed. Review and save again."; return
        }
        let profileID = stationID
        submitting = true
        Task { @MainActor in
            defer { submitting = false }
            guard appState.activeStationProfileID == profileID, appState.isOwnStationLogOpen,
                  !appState.isIncomingRecoveryBusy, appState.incomingRecoveryRecord(request)?.fields == record.fields else {
                status = "The station, contact or sync state changed. Reopen the case and try again."; return
            }
            _ = await appState.processQSLQueue(providers: QSLSyncAll.incomingRecoveryProviders, qsoIDs: [record.id])
            guard appState.activeStationProfileID == profileID else { status = "The active station changed; reopen the original recovery case."; return }
            status = appState.qslHubStatus
        }
    }
}

struct IncomingReviewFields: View {
    @Binding var review: IncomingContactReview
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow { Text("Worked callsign"); TextField("Actual worked callsign", text: $review.call) }
            GridRow { Text("UTC date"); TextField("YYYYMMDD", text: $review.date) }
            GridRow { Text("UTC time"); TextField("HHMM or HHMMSS — no default", text: $review.time) }
            GridRow { Text("Band"); TextField("Actual ADIF band", text: $review.band) }
            GridRow { Text("Mode"); TextField("Actual mode (e.g. SSB, FT8)", text: $review.mode) }
            GridRow { Text("Station callsign"); TextField("Callsign used for this contact", text: $review.station) }
            GridRow { Text("Evidence/source"); TextField("Local notes/log or operator reply", text: $review.evidence) }
        }.textFieldStyle(.roundedBorder)
    }
}
