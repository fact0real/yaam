import SwiftUI

private struct GraylistEmailDraft: Identifiable {
    let recipient: QSLGraylistMailRecipient
    var id: String { recipient.id }
    var email: String
    var subject: String
    var body: String
    var selected = true
    var sent = false
    var status = "Ready"
}

struct QSLGraylistEmailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let profileID: UUID
    let recipients: [QSLGraylistMailRecipient]
    @State private var drafts: [GraylistEmailDraft] = []
    @State private var previewCall = ""
    @State private var prepared = false
    @State private var sending = false
    @State private var stopRequested = false
    @State private var lookingUp = false
    @State private var lookupTask: Task<Void, Never>?
    @State private var notice = ""

    private var workspaceIsCurrent: Bool {
        appState.activeStationProfileID == profileID && appState.loadedWorkspaceProfileID == profileID &&
            appState.isMasterMode && appState.qslGraylist.hasWorkspace
    }
    private var readyCount: Int {
        drafts.filter { $0.selected && !$0.sent && QSLGraylistMail.isUsableEmail($0.email) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Request QSL confirmations", systemImage: "envelope.stack")
                        .font(.title2.bold())
                    Text("One separate email per operator, with your distinct QSO details. Edit each message below.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }.disabled(sending)
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack {
                    recipientSummary
                    Spacer()
                    lookupButton
                }
                VStack(alignment: .leading) { recipientSummary; lookupButton }
            }
            HStack {
                Button("Select all") { for index in drafts.indices where !drafts[index].sent { drafts[index].selected = true } }
                Button("Not previously emailed") {
                    for index in drafts.indices { drafts[index].selected = !drafts[index].sent && previousEmail(drafts[index].id) == nil }
                }
                Button("Clear selection") { for index in drafts.indices { drafts[index].selected = false } }
                Spacer()
            }
            .controlSize(.small)
            .disabled(sending)
            HSplitView {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach($drafts) { $draft in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Toggle("", isOn: $draft.selected).labelsHidden()
                                        .disabled(sending || draft.sent)
                                    Button(draft.id) { previewCall = draft.id }
                                        .font(.body.monospaced().bold()).buttonStyle(.plain)
                                    Spacer()
                                    Text("\(draft.recipient.records.count) QSOs").font(.caption2)
                                }
                                TextField("Email address", text: $draft.email)
                                    .textFieldStyle(.roundedBorder).disabled(sending || draft.sent)
                                Text(draft.status).font(.caption2).foregroundStyle(.secondary)
                                if let history = previousEmail(draft.id) {
                                    Text("Previous email: \(appState.formattedEmailHistoryDate(history.date)) · \(history.subject)")
                                        .font(.caption2).foregroundStyle(.orange)
                                }
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6)
                                .fill(previewCall == draft.id ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
                        }
                    }.padding(.trailing, 8)
                }.frame(minWidth: 240, idealWidth: 290, maxWidth: 340)
                if let index = drafts.firstIndex(where: { $0.id == previewCall }) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Message to \(drafts[index].id)").font(.headline)
                        TextField("Subject", text: $drafts[index].subject).textFieldStyle(.roundedBorder)
                        TextEditor(text: $drafts[index].body).font(.body)
                            .border(Color.secondary.opacity(0.2))
                    }
                    .padding(.leading, 10)
                    .disabled(sending || drafts[index].sent)
                    .frame(minWidth: 330)
                }
            }
            Divider()
            if !workspaceIsCurrent {
                Text("The active station or workspace changed. Close this window and reopen it from QSL Graylist.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if !notice.isEmpty { Text(notice).font(.caption).textSelection(.enabled) }
            HStack {
                Text("Previously emailed operators start unchecked.")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if sending {
                    ProgressView().controlSize(.small)
                    Button("Stop after current") { stopRequested = true }.disabled(stopRequested)
                } else {
                    Button("Send \(readyCount) emails") { startSend() }
                        .buttonStyle(.borderedProminent)
                        .disabled(readyCount == 0 || !workspaceIsCurrent || lookingUp || appState.qslGraylist.isLoading)
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 700, idealWidth: 1000, minHeight: 460, idealHeight: 680)
        .resizablePresentation(minWidth: 700, minHeight: 460)
        .interactiveDismissDisabled(sending)
        .onAppear(perform: prepare)
        .onDisappear { lookupTask?.cancel() }
    }

    private var recipientSummary: some View {
        Text("\(drafts.count) operators · \(readyCount) ready · \(drafts.filter { !QSLGraylistMail.isUsableEmail($0.email) }.count) missing email")
            .font(.caption.monospacedDigit())
    }

    private var lookupButton: some View {
        HStack {
            if lookingUp {
                ProgressView().controlSize(.small)
                Button("Stop lookup") { lookupTask?.cancel() }
            } else {
                Button("Find missing emails") { findMissingEmails() }
                    .disabled(sending || !workspaceIsCurrent || !drafts.contains { !QSLGraylistMail.isUsableEmail($0.email) })
            }
        }
    }

    private func previousEmail(_ call: String) -> EmailHistoryEntry? {
        appState.emailHistory.first { QSLGraylistIndex.clean($0.callsign) == call && $0.countsAsQSL }
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        drafts = recipients.map { recipient in
            let message = appState.confirmationRequestMessage(callsign: recipient.id,
                templateName: "LoTW/QRZ Confirmation Request", qsos: recipient.records)
            return GraylistEmailDraft(recipient: recipient, email: recipient.email,
                                      subject: message.subject, body: message.body,
                                      selected: previousEmail(recipient.id) == nil)
        }
        previewCall = drafts.first?.id ?? ""
    }

    private func findMissingEmails() {
        guard !lookingUp, !sending, workspaceIsCurrent else { return }
        lookingUp = true
        lookupTask = Task { @MainActor in
            defer { lookingUp = false }
            for index in drafts.indices {
                guard !Task.isCancelled, workspaceIsCurrent else { break }
                guard !QSLGraylistMail.isUsableEmail(drafts[index].email) else { continue }
                drafts[index].status = "Looking up email…"
                let contact = await appState.fetchContactInfo(for: drafts[index].id,
                    allowQRZWebKitFallback: true, allowCredentialPrompt: false)
                guard !Task.isCancelled, workspaceIsCurrent else {
                    drafts[index].status = "Lookup stopped"
                    break
                }
                if let email = contact.email, QSLGraylistMail.isUsableEmail(email),
                   !QSLGraylistMail.isUsableEmail(drafts[index].email) {
                    drafts[index].email = email.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                drafts[index].status = QSLGraylistMail.isUsableEmail(drafts[index].email) ? "Ready" : "Email not found — enter manually"
            }
        }
    }

    private func startSend() {
        guard !sending, !lookingUp, workspaceIsCurrent else { return }
        let stationCall = appState.currentStationCallsign.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stationCall.isEmpty, stationCall.uppercased() != "DEFAULT" else {
            notice = "Set the active station callsign before sending."
            return
        }
        guard appState.isSMTPConfigured else {
            notice = "Configure SMTP in Settings → Email before sending."
            return
        }
        let candidates = drafts.indices.filter { drafts[$0].selected && !drafts[$0].sent && QSLGraylistMail.isUsableEmail(drafts[$0].email) }
        guard !candidates.isEmpty else { return }
        guard candidates.allSatisfy({ !drafts[$0].subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !drafts[$0].subject.contains("\n") && !drafts[$0].subject.contains("\r") &&
            !drafts[$0].body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            notice = "Each selected message needs a subject and body. Subjects must be a single line."
            return
        }
        sending = true
        stopRequested = false
        notice = "Sending…"
        Task { @MainActor in
            var sent = 0
            var failed = 0
            var skipped = 0
            var historyFailure = false
            for index in candidates {
                guard !stopRequested, workspaceIsCurrent else { break }
                // Wait for a real evidence update, then revalidate before every delivery.
                while appState.qslGraylist.isLoading && workspaceIsCurrent && !stopRequested {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard !stopRequested, workspaceIsCurrent else { break }
                guard appState.qslGraylist.index.entry(for: drafts[index].id) == drafts[index].recipient.entry else {
                    drafts[index].status = "Skipped — QSL history changed; reopen to review"
                    skipped += 1
                    continue
                }
                drafts[index].status = "Sending…"
                let result: (Bool, String) = await withCheckedContinuation { continuation in
                    appState.sendEmail(to: drafts[index].email.trimmingCharacters(in: .whitespacesAndNewlines),
                        subject: drafts[index].subject, body: drafts[index].body,
                        callsign: drafts[index].id, historyKind: QSLGraylistMail.historyKind, playSound: false) {
                            continuation.resume(returning: ($0, $1))
                        }
                }
                drafts[index].sent = result.0
                drafts[index].status = result.0 ? "Sent" : result.1
                if result.0 { sent += 1 } else { failed += 1 }
                if result.1.hasPrefix("HISTORY SAVE FAILED") {
                    historyFailure = true
                    drafts[index].status = result.1
                    break
                }
                if index != candidates.last, !stopRequested { try? await Task.sleep(for: .seconds(1)) }
            }
            sending = false
            notice = "\(sent) sent · \(failed) failed · \(skipped) skipped" +
                (historyFailure ? ". Delivery stopped because email history could not be saved. Check your sent mailbox before retrying." :
                    (stopRequested || !workspaceIsCurrent ? " · stopped" : ""))
        }
    }
}
