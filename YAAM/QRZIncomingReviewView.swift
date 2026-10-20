import SwiftUI

struct QRZIncomingReviewView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let request: QRZIncomingConfirmation
    var onRequestDetails: (() -> Void)? = nil
    @State private var review = IncomingContactReview()
    @State private var status = ""
    @State private var savedID: UUID?
    @State private var savedFields: [String: String]?
    @State private var stationID: UUID?

    private var candidates: [QSORecordModel] { appState.incomingCandidates(request) }
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
                    Text("3. Verify before saving").font(.headline)
                    Toggle("I compared my log/notes or the operator's reply and verified these actual details", isOn: $review.verified)
                    if let problem = review.problem { Text(problem).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Text(status).font(.callout).textSelection(.enabled)
            HStack {
                Button("Request details…") { onRequestDetails?() }
                Spacer()
                Button("Save verified contact") { save() }.disabled(review.problem != nil || stationID != appState.activeStationProfileID)
                Button("Prepare LoTW / QRZ / Club Log") { prepare() }.buttonStyle(.borderedProminent)
                    .disabled(savedID == nil || review.problem != nil)
            }
        }.padding(20).frame(minWidth: 720, minHeight: 540)
        .onAppear {
            stationID = appState.activeStationProfileID
            if let data = UserDefaults.standard.data(forKey: draftKey), let draft = try? JSONDecoder().decode(IncomingContactReview.self, from: data) {
                review = draft; review.verified = false
            } else {
                review.call = request.callsign; review.date = QSOIdentity.normalizedDate(request.qsoDate); review.station = appState.currentStationCallsign
            }
        }
        .onDisappear {
            var draft = review; draft.verified = false
            if let data = try? JSONEncoder().encode(draft) { UserDefaults.standard.set(data, forKey: draftKey) }
        }
        .onChange(of: review.separateContact) { _, _ in review.verified = false; savedID = nil }
        .onChange(of: review.fields) { _, _ in review.verified = false; savedID = nil; savedFields = nil }
        .onChange(of: review.evidence) { _, _ in review.verified = false; savedID = nil; savedFields = nil }
    }
    private var draftKey: String { "incomingReviewDraft.v1." + (stationID?.uuidString ?? "none") + "." + (request.qsoID.isEmpty ? request.id : request.qsoID) }
    private func use(_ record: QSORecordModel) {
        review.date = record["QSO_DATE"]; review.time = record["TIME_ON"]; review.band = record["BAND"]
        review.mode = record["SUBMODE"].isEmpty ? record["MODE"] : record["SUBMODE"]
        review.station = record["STATION_CALLSIGN"].isEmpty ? appState.currentStationCallsign : record["STATION_CALLSIGN"]
        review.evidence = "Local log record \(record.id)"; review.verified = false
    }
    private func save() {
        do {
            guard stationID == appState.activeStationProfileID else { return }
            let record = try appState.saveIncomingReview(review, request: request)
            savedID = record.id; savedFields = record.fields
            status = "Verified contact saved or linked to the existing record. Incoming does not mark it confirmed. Prepare the three destinations when ready."
        } catch { status = error.localizedDescription }
    }
    private func prepare() {
        guard stationID == appState.activeStationProfileID, appState.isOwnStationLogOpen,
              let record = appState.qsoRecords.first(where: { $0.id == savedID }), record.fields == savedFields,
              review.problem == nil else { status = "The station or contact changed. Review and save again."; savedID = nil; return }
        appState.enqueueQSL(records: [record], providers: [.lotw, .qrz, .clubLog], retryStopped: false)
        status = appState.qslHubStatus + ". Follow each destination in the QSL Hub; submission is separate from confirmation."
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
