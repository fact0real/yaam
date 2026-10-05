import SwiftUI

private enum IncomingDeliveryState: Equatable {
    case ready
    case sending
    case sent
    case failed(String)
}

private struct IncomingRecipientDraft: Identifiable {
    let group: QRZIncomingBulkRecipient
    var id: String { group.id }
    var name: String
    var email: String = ""
    var isLookingUp = false
    var delivery: IncomingDeliveryState = .ready
}

struct QRZIncomingBulkEmailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("qrzIncomingBulkSubject") private var subjectTemplate = QRZIncomingBulkMail.defaultSubject
    @AppStorage("qrzIncomingBulkBody") private var bodyTemplate = QRZIncomingBulkMail.defaultBody

    @State private var recipients: [IncomingRecipientDraft]
    @State private var previewCallsign: String
    @State private var isPrepared = false
    @State private var lookupTask: Task<Void, Never>?
    @State private var isLookingUp = false
    @State private var includePreviouslyEmailed = false
    @State private var isSending = false
    @State private var stopAfterCurrent = false
    @State private var showSendConfirmation = false
    @State private var completed = 0
    @State private var totalToSend = 0
    @State private var notice = ""

    init(requests: [QRZIncomingConfirmation]) {
        let groups = QRZIncomingBulkMail.group(requests.map {
            .init(id: $0.id, callsign: $0.callsign, qsoDate: $0.qsoDate)
        })
        _recipients = State(initialValue: groups.map { .init(group: $0, name: $0.callsign) })
        _previewCallsign = State(initialValue: groups.first?.callsign ?? "")
    }

    private var myCallsign: String {
        let call = appState.currentStationCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return call == "DEFAULT" ? "" : call
    }

    private var previewRecipient: IncomingRecipientDraft? {
        recipients.first { $0.id == previewCallsign } ?? recipients.first
    }

    private var readyCount: Int {
        recipients.filter { recipient in
            QRZIncomingBulkMail.isUsableEmail(recipient.email) &&
            recipient.delivery != .sent &&
            (includePreviouslyEmailed || previousIncomingEmail(for: recipient.id) == nil)
        }.count
    }

    private var missingCount: Int {
        recipients.filter { !QRZIncomingBulkMail.isUsableEmail($0.email) }.count
    }

    private var previousCount: Int {
        recipients.filter { previousIncomingEmail(for: $0.id) != nil }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Email QRZ Incoming requests", systemImage: "envelope.stack.fill")
                        .font(.title3.bold())
                    Text("Each callsign receives one separate message covering its selected QRZ requests. Review the recipient and personalized preview before sending.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(recipients.count) operators · \(recipients.reduce(0) { $0 + $1.group.requestIDs.count }) requests")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)

            Divider()

            HStack(alignment: .top, spacing: 16) {
                recipientList
                    .frame(width: 340)
                Divider()
                editorAndPreview
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 14)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                if !notice.isEmpty {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(notice.hasPrefix("Error") ? .red : .secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 10) {
                    Text("\(readyCount) ready · \(missingCount) missing email")
                        .font(.caption.weight(.medium))
                    if isSending {
                        ProgressView(value: Double(completed), total: Double(max(totalToSend, 1)))
                            .frame(width: 145)
                        Text("\(completed)/\(totalToSend)")
                            .font(.caption.monospacedDigit())
                        Button("Stop after current") { stopAfterCurrent = true }
                            .disabled(stopAfterCurrent)
                    }
                    Spacer()
                    Button("Close") { dismiss() }
                        .disabled(isSending)
                    Button("Send \(readyCount) personalized emails") {
                        showSendConfirmation = true
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSending || readyCount == 0 || myCallsign.isEmpty)
                }
            }
            .padding(.top, 12)
        }
        .padding(18)
        .frame(minWidth: 860, idealWidth: 1080, minHeight: 590, idealHeight: 740)
        .resizablePresentation(minWidth: 860, minHeight: 590)
        .interactiveDismissDisabled(isSending)
        .confirmationDialog("Send separate personalized emails?",
                            isPresented: $showSendConfirmation) {
            Button("Send \(readyCount) emails") { startSend() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("YAAM will send one message per callsign through your configured SMTP account. Requests from the same callsign are combined in one message.")
        }
        .onAppear(perform: prepareRecipients)
        .onDisappear { lookupTask?.cancel() }
    }

    private var recipientList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recipients").font(.headline)
                Spacer()
                if isLookingUp {
                    ProgressView().controlSize(.small)
                    Button("Stop lookup") {
                        lookupTask?.cancel()
                        isLookingUp = false
                    }
                    .font(.caption)
                } else if missingCount > 0 {
                    Button("Find missing emails") { startLookup() }
                        .font(.caption)
                        .disabled(isSending)
                }
            }
            if previousCount > 0 {
                Toggle("Include \(previousCount) previously emailed", isOn: $includePreviouslyEmailed)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .disabled(isSending)
                Text("Previously contacted operators are skipped unless you enable this option.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
            ScrollView {
                LazyVStack(spacing: 7) {
                    ForEach($recipients) { $recipient in
                        let previous = previousIncomingEmail(for: recipient.id)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Button {
                                    previewCallsign = recipient.id
                                } label: {
                                    Text(recipient.id)
                                        .font(.subheadline.bold().monospaced())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(previewCallsign == recipient.id ? .blue : .primary)
                                Spacer()
                                Text("\(recipient.group.requestIDs.count) request\(recipient.group.requestIDs.count == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(recipient.group.qsoDates.isEmpty ? "QSO date not reported" : recipient.group.qsoDates.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 5) {
                                TextField("Email address", text: $recipient.email)
                                    .textFieldStyle(.roundedBorder)
                                    .disabled(isSending || recipient.delivery == .sent)
                                if recipient.isLookingUp { ProgressView().controlSize(.small) }
                            }
                            TextField("Operator name", text: $recipient.name)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption)
                                .disabled(isSending || recipient.delivery == .sent)
                            if let previous {
                                Text("Emailed \(previous.date.formatted(date: .abbreviated, time: .shortened))")
                                    .foregroundStyle(.orange)
                                    .font(.caption2)
                            }
                            switch recipient.delivery {
                            case .sending:
                                Text("Sending…").foregroundStyle(.blue).font(.caption2)
                            case .sent:
                                Text("Sent successfully").foregroundStyle(.green).font(.caption2)
                            case .failed(let error):
                                Text("Failed: \(error)").foregroundStyle(.red).font(.caption2)
                                    .fixedSize(horizontal: false, vertical: true)
                            case .ready:
                                if !recipient.email.isEmpty && !QRZIncomingBulkMail.isUsableEmail(recipient.email) {
                                    Text("Check this email address").foregroundStyle(.orange).font(.caption2)
                                }
                            }
                        }
                        .padding(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(previewCallsign == recipient.id ? Color.blue.opacity(0.09) : Color.secondary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
        }
    }

    private var editorAndPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shared template").font(.headline)
            Text("Fields: {name}, {callsign}, {qso_dates}, {request_count}, {my_callsign}. Changes are saved for your next batch.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("Subject", text: $subjectTemplate)
                .textFieldStyle(.roundedBorder)
                .disabled(isSending)
            TextEditor(text: $bodyTemplate)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 175, maxHeight: 240)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.25)))
                .disabled(isSending)
            HStack {
                Text("Personalized preview").font(.headline)
                Spacer()
                if let recipient = previewRecipient {
                    Text(recipient.id).font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            if let recipient = previewRecipient {
                Text("To: \(recipient.email.isEmpty ? "Email needed" : recipient.email)")
                    .font(.caption)
                    .foregroundStyle(QRZIncomingBulkMail.isUsableEmail(recipient.email) ? Color.secondary : Color.orange)
                Text(render(subjectTemplate, for: recipient))
                    .font(.subheadline.bold())
                    .textSelection(.enabled)
                ScrollView {
                    Text(render(bodyTemplate, for: recipient))
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(9)
                }
                .frame(maxHeight: .infinity)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            } else {
                ContentUnavailableView("No recipients", systemImage: "envelope")
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func render(_ template: String, for recipient: IncomingRecipientDraft) -> String {
        QRZIncomingBulkMail.render(template, recipient: recipient.group,
                                   name: recipient.name, myCallsign: myCallsign)
    }

    private func previousIncomingEmail(for call: String) -> EmailHistoryEntry? {
        appState.emailHistory.first {
            $0.callsign.caseInsensitiveCompare(call) == .orderedSame &&
            $0.kind == QRZIncomingBulkMail.historyKind && $0.status == "Sent"
        }
    }

    private func prepareRecipients() {
        guard !isPrepared else { return }
        isPrepared = true
        for index in recipients.indices {
            let call = recipients[index].id
            recipients[index].name = appState.resolveFirstName(for: call)
            if let stored = appState.qsoRecords.lazy
                .filter({ $0["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == call })
                .map({ $0["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: QRZIncomingBulkMail.isUsableEmail) {
                recipients[index].email = stored
            }
        }
        startLookup()
    }

    private func startLookup() {
        lookupTask?.cancel()
        guard recipients.contains(where: { !QRZIncomingBulkMail.isUsableEmail($0.email) }) else { return }
        isLookingUp = true
        lookupTask = Task { @MainActor in
            for index in recipients.indices {
                if Task.isCancelled || isSending { break }
                guard !QRZIncomingBulkMail.isUsableEmail(recipients[index].email) else { continue }
                recipients[index].isLookingUp = true
                let call = recipients[index].id
                let contact = await appState.fetchContactInfo(
                    for: call, allowQRZWebKitFallback: true, allowCredentialPrompt: false)
                guard !Task.isCancelled else {
                    recipients[index].isLookingUp = false
                    break
                }
                if !QRZIncomingBulkMail.isUsableEmail(recipients[index].email),
                   let fetched = contact.email, QRZIncomingBulkMail.isUsableEmail(fetched) {
                    recipients[index].email = fetched.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if recipients[index].name == call,
                   let fetchedName = contact.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !fetchedName.isEmpty {
                    recipients[index].name = appState.formatFirstName(from: fetchedName, fallbackCallsign: call)
                }
                recipients[index].isLookingUp = false
            }
            isLookingUp = false
        }
    }

    private func startSend() {
        guard !isSending else { return }
        guard !myCallsign.isEmpty else {
            notice = "Error: Set the active station callsign before sending."
            return
        }
        guard appState.isSMTPConfigured else {
            notice = "Error: Configure SMTP in Settings → Email before sending."
            return
        }
        let subject = subjectTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = bodyTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty, !body.isEmpty else {
            notice = "Error: Enter a subject and message."
            return
        }
        lookupTask?.cancel()
        isLookingUp = false

        let candidates: [(index: Int, call: String, email: String, subject: String, body: String)] =
            recipients.indices.compactMap { index in
                let recipient = recipients[index]
                guard recipient.delivery != .sent,
                      QRZIncomingBulkMail.isUsableEmail(recipient.email),
                      includePreviouslyEmailed || previousIncomingEmail(for: recipient.id) == nil else { return nil }
                return (index, recipient.id, recipient.email.trimmingCharacters(in: .whitespacesAndNewlines),
                        render(subject, for: recipient), render(body, for: recipient))
            }
        guard !candidates.isEmpty else {
            notice = "Error: No recipients are ready. Add missing addresses or review previously emailed contacts."
            return
        }
        guard candidates.allSatisfy({ candidate in
            !candidate.subject.contains("\n") && !candidate.subject.contains("\r") &&
            !QRZIncomingBulkMail.hasUnresolvedFields(candidate.subject) &&
            !QRZIncomingBulkMail.hasUnresolvedFields(candidate.body)
        }) else {
            notice = "Error: The template has an unknown field or an invalid subject. Review the preview."
            return
        }

        isSending = true
        stopAfterCurrent = false
        completed = 0
        totalToSend = candidates.count
        notice = "Sending separate messages through the configured SMTP account…"
        Task { @MainActor in
            var sent = 0
            var failed = 0
            for candidate in candidates {
                if stopAfterCurrent { break }
                recipients[candidate.index].delivery = .sending
                let result: (Bool, String) = await withCheckedContinuation { continuation in
                    appState.sendEmail(to: candidate.email, subject: candidate.subject,
                                       body: candidate.body, callsign: candidate.call,
                                       historyKind: QRZIncomingBulkMail.historyKind,
                                       playSound: false) { success, message in
                        continuation.resume(returning: (success, message))
                    }
                }
                if result.0 {
                    recipients[candidate.index].delivery = .sent
                    sent += 1
                    if result.1.hasPrefix("HISTORY SAVE FAILED") {
                        notice = result.1
                    }
                } else {
                    recipients[candidate.index].delivery = .failed(result.1)
                    failed += 1
                }
                completed += 1
                if !stopAfterCurrent && completed < totalToSend {
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            isSending = false
            appState.playActivitySound(failed == 0 ? .success : .failure)
            if !notice.hasPrefix("HISTORY SAVE FAILED") {
                notice = "\(sent) sent · \(failed) failed\(stopAfterCurrent ? " · stopped after the current message" : ""). Review the results before closing."
            }
        }
    }
}
