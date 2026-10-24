import SwiftUI

struct SKEDMessagingView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: SKEDMessagingModel
    @State private var confirmNewDraft = false
    @State private var credentialRevision = ""
    private var autoConnect = true
    private var credentialRevisionProvider: () -> String = { "" }

    init(recipient: String = "", userAgent: String, tokenProvider: @escaping () -> String,
         credentialRevisionProvider: @escaping () -> String = { "" }) {
        _model = StateObject(wrappedValue: SKEDMessagingModel(recipient: recipient, userAgent: userAgent, tokenProvider: tokenProvider))
        self.credentialRevisionProvider = credentialRevisionProvider
    }

    #if MESSAGING_REGRESSION
    init(model: SKEDMessagingModel) {
        _model = StateObject(wrappedValue: model)
        autoConnect = false
    }
    #endif

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("SKED Messages", systemImage: "bubble.left.and.bubble.right")
                    .font(.title2.weight(.semibold))
                Spacer()
                if model.working { ProgressView().controlSize(.small) }
                Button("Refresh") { Task { await model.refresh() } }.disabled(model.working)
                Button("Close") { model.close(); dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    privacy
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange).textSelection(.enabled)
                    }
                    if let notice = model.notice {
                        Label(notice, systemImage: "info.circle").foregroundStyle(.secondary)
                    }
                    if let status = model.status {
                        if let owner = status.verifiedCallsign {
                            HStack {
                                Label("Verified identity: \(owner)", systemImage: "person.crop.circle.badge.checkmark")
                                Spacer()
                                Button(status.enabled ? "Disable messaging" : "Enable messaging") {
                                    Task { await model.setEnabled(!status.enabled) }
                                }.disabled(model.working)
                            }
                            if status.enabled {
                                composer
                                inbox(owner: owner)
                                if !model.blockedCalls.isEmpty {
                                    GroupBox("Blocked callsigns") {
                                        VStack(alignment: .leading) {
                                            ForEach(model.blockedCalls, id: \.self) { call in
                                                HStack {
                                                    Text(call).monospaced()
                                                    Spacer()
                                                    Button("Unblock") { Task { await model.setBlocked(call, blocked: false) } }
                                                        .disabled(model.working)
                                                }
                                            }
                                        }.padding(6)
                                    }
                                }
                            } else {
                                Text("Messaging is off. Enable it to allow other verified members to send you private messages.")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Label(SKEDMessagingError.identityRequired.localizedDescription, systemImage: "person.crop.circle.badge.questionmark")
                                .foregroundStyle(.secondary)
                        }
                    } else if !model.working && model.error == nil {
                        ContentUnavailableView("Connect to messaging", systemImage: "bubble.left.and.bubble.right",
                            description: Text("Refresh to check service availability and your verified identity."))
                    }
                }.padding().frame(maxWidth: 1000).frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 640, idealWidth: 850, minHeight: 420, idealHeight: 680)
        .task {
            credentialRevision = credentialRevisionProvider()
            if autoConnect { await model.refresh() }
        }
        .onDisappear { model.close() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let revision = credentialRevisionProvider()
            if autoConnect && revision != credentialRevision {
                credentialRevision = revision
                model.close()
            }
        }
        .confirmationDialog("Start a new send request?", isPresented: $confirmNewDraft) {
            Button("Edit as a new request") { model.editDraft() }
        } message: {
            Text("The earlier message may already have reached the server. Refresh or retry it first to avoid sending the same text twice.")
        }
    }

    private var privacy: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Label("Private coordination for your next contact", systemImage: "lock.bubble")
                    .font(.headline)
                Text("Plain text only. Messages expire after 30 days. The service encrypts stored text and uses HTTPS; the server operator can access it. Messages are not end-to-end encrypted.")
                Text("Only the recipient and your note are sent. Your logbook, email address and radio controls are not shared. Use Refresh to check for new messages.")
                    .foregroundStyle(.secondary)
            }.font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(6)
        }
    }

    private var composer: some View {
        GroupBox("New message") {
            VStack(alignment: .leading, spacing: 10) {
                Button("Test with myself") { model.prepareSelfTest() }
                    .disabled(model.working || model.pending != nil)
                TextField("Recipient callsign", text: $model.recipient)
                    .textFieldStyle(.roundedBorder).disabled(model.pending != nil || model.working)
                    .accessibilityLabel("Recipient callsign")
                TextEditor(text: $model.text).font(.body).frame(height: 100)
                    .border(Color(nsColor: .separatorColor)).disabled(model.pending != nil || model.working)
                    .accessibilityLabel("Plain text message")
                HStack {
                    Text("\(model.text.unicodeScalars.count) / 2,000 characters").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if model.pending != nil {
                        Button("Edit draft…") { confirmNewDraft = true }.disabled(model.working)
                    }
                    Button(model.pending == nil ? "Send message" : "Retry same message") { Task { await model.send() } }
                        .buttonStyle(.borderedProminent).disabled(!model.canSend)
                }
            }.padding(6)
        }
    }

    private func inbox(owner: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent messages").font(.headline)
            if model.messages.isEmpty {
                Text("No messages loaded. Refresh to check for new messages.").foregroundStyle(.secondary)
            }
            ForEach(model.messages) { message in
                SKEDPrivateMessageCard(message: message, owner: owner, working: model.working,
                    isBlocked: model.blockedCalls.contains(message.sender == owner ? message.recipient : message.sender),
                    reply: { if model.pending == nil { model.recipient = message.sender == owner ? message.recipient : message.sender } },
                    block: { call, blocked in Task { await model.setBlocked(call, blocked: blocked) } },
                    report: { reason in Task { await model.report(message, reason: reason) } })
            }
            if model.nextBefore != nil {
                Button("Load older messages") { Task { await model.refresh(older: true) } }.disabled(model.working)
            }
        }
    }
}

struct SKEDPrivateMessageCard: View {
    let message: SKEDPrivateMessage
    let owner: String
    let working: Bool
    let isBlocked: Bool
    let reply: () -> Void
    let block: (String, Bool) -> Void
    let report: (String) -> Void
    private var peer: String { message.sender == owner ? message.recipient : message.sender }
    private var isSelfMessage: Bool { message.sender == owner && message.recipient == owner }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack { identity; Spacer(); timestamp }
                    VStack(alignment: .leading, spacing: 4) { identity; timestamp }
                }
                // Verbatim Text prevents Markdown interpretation and automatic link previews.
                Text(verbatim: message.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Button("Reply") { reply() }
                    if !isSelfMessage {
                        Button(isBlocked ? "Unblock \(peer)" : "Block \(peer)") { block(peer, !isBlocked) }
                    }
                    if message.recipient == owner && !isSelfMessage {
                        Menu("Report") {
                            Button("Spam") { report("spam") }
                            Button("Abuse") { report("abuse") }
                            Button("Impersonation") { report("impersonation") }
                        }.menuStyle(.borderlessButton).fixedSize()
                    }
                    Spacer()
                }.disabled(working).controlSize(.small)
            }.padding(6)
        }
    }

    private var identity: some View {
        Label(isSelfMessage ? "\(owner) · Note to self" : "\(message.sender) → \(message.recipient)", systemImage: isSelfMessage ? "arrow.triangle.2.circlepath" : message.sender == owner ? "arrow.up.right" : "arrow.down.left")
            .font(.headline).monospaced()
    }
    private var timestamp: some View {
        Text(message.createdAt.replacingOccurrences(of: "T", with: " ").prefix(19) + " UTC")
            .font(.caption).foregroundStyle(.secondary)
    }
}
