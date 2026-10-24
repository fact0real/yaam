import Foundation
import Combine

@MainActor final class SKEDMessagingModel: ObservableObject {
    @Published private(set) var status: SKEDMessagingStatus?
    @Published private(set) var messages: [SKEDPrivateMessage] = []
    @Published private(set) var blockedCalls: [String] = []
    @Published private(set) var nextBefore: String?
    @Published private(set) var working = false
    @Published private(set) var error: String?
    @Published private(set) var notice: String?
    @Published private(set) var pending: SKEDMessageDraft?
    @Published var recipient: String
    @Published var text = ""

    private let service: SKEDMessagingService
    private let tokenProvider: () -> String
    private var generation = UUID()
    private var accountToken = ""
    private var pendingSince: ContinuousClock.Instant?

    init(recipient: String = "", userAgent: String, tokenProvider: @escaping () -> String) {
        self.recipient = recipient
        self.tokenProvider = tokenProvider
        service = SKEDMessagingService(userAgent: userAgent)
    }

    #if MESSAGING_REGRESSION
    init(service: SKEDMessagingService, tokenProvider: @escaping () -> String) {
        self.recipient = "G0JHC"
        self.tokenProvider = tokenProvider
        self.service = service
    }

    func preview(status: SKEDMessagingStatus?, messages: [SKEDPrivateMessage] = [], error: String? = nil,
                 working: Bool = false, pending: SKEDMessageDraft? = nil, blocks: [String] = []) {
        self.status = status
        self.messages = messages
        self.error = error
        self.working = working
        self.pending = pending
        self.blockedCalls = blocks
        self.text = pending?.body ?? ""
    }
    #endif

    var owner: String? { status?.verifiedCallsign }
    var enabled: Bool { status?.enabled == true }
    var canSend: Bool {
        enabled && !working && (pending != nil ||
            (SKEDMessagingContract.validCallsign(recipient.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) &&
             SKEDMessagingContract.validBody(text)))
    }

    func close() {
        generation = UUID()
        status = nil
        messages = []
        blockedCalls = []
        nextBefore = nil
        pending = nil
        pendingSince = nil
        text = ""
        accountToken = ""
        error = nil
        notice = nil
        working = false
    }

    private func begin() -> (UUID, String)? {
        guard !working else { return nil }
        let token = tokenProvider()
        if accountToken != token {
            close()
            accountToken = token
        }
        working = true
        error = nil
        notice = nil
        return (generation, token)
    }

    private func current(_ id: UUID, token: String) -> Bool {
        guard generation == id else { return false }
        guard tokenProvider() == token else { close(); return false }
        return !Task.isCancelled
    }

    private func fail(_ failure: Error) {
        guard !(failure is CancellationError) else { return }
        error = failure.localizedDescription
        if let value = failure as? SKEDMessagingError,
           [.unauthorized, .identityRequired, .optInRequired].contains(value) {
            messages = []
            blockedCalls = []
            status = nil
            nextBefore = nil
            pending = nil
            pendingSince = nil
            text = ""
        }
    }

    func refresh(older: Bool = false) async {
        guard let (id, token) = begin() else { return }
        defer { if generation == id { working = false } }
        do {
            let fresh = try await service.status(token: token)
            guard current(id, token: token) else { return }
            status = fresh
            guard fresh.enabled, let owner = fresh.verifiedCallsign else {
                messages = []; blockedCalls = []; nextBefore = nil
                return
            }
            let page = try await service.messages(token: token, owner: owner, before: older ? nextBefore : nil)
            let blocks = try await service.blocks(token: token)
            guard current(id, token: token), self.owner == owner else { return }
            let combined = older ? messages + page.messages : page.messages
            var seen = Set<String>()
            messages = Array(combined.filter { seen.insert($0.id).inserted }.prefix(500))
            blockedCalls = blocks
            nextBefore = messages.count < 500 ? page.nextBefore : nil
            if let pending, messages.contains(where: { $0.clientID == pending.clientID && $0.sender == owner }) {
                self.pending = nil
                pendingSince = nil
                text = ""
                notice = "Delivery confirmed by the server."
            }
        } catch {
            guard current(id, token: token) else { return }
            fail(error)
        }
    }

    func setEnabled(_ value: Bool) async {
        guard let expectedOwner = owner else { return }
        guard let (id, token) = begin() else { return }
        guard owner == expectedOwner else { working = false; return }
        do {
            let result = try await service.setEnabled(value, token: token)
            guard current(id, token: token) else { return }
            status = result
            if !value { messages = []; blockedCalls = []; nextBefore = nil; pending = nil; pendingSince = nil; text = "" }
            working = false
            if value { await refresh() }
        } catch {
            guard current(id, token: token) else { return }
            fail(error)
        }
        if generation == id { working = false }
    }

    func send() async {
        guard enabled, let owner, let (id, token) = begin() else { return }
        defer { if generation == id { working = false } }
        // begin() may clear identity if the token changed while the sheet was open.
        guard self.owner == owner, enabled else { return }
        do {
            if let pendingSince, pendingSince.duration(to: .now) >= .seconds(86400) {
                throw SKEDMessagingError.conflict
            }
            let draft = try pending ?? SKEDMessageDraft(recipient: recipient, body: text)
            guard draft.recipient != owner else { throw SKEDMessagingError.invalidInput }
            if pending == nil { pendingSince = .now }
            pending = draft
            let sent = try await service.send(draft, token: token, owner: owner)
            guard current(id, token: token) else { return }
            messages.removeAll { $0.id == sent.id }
            messages.insert(sent, at: 0)
            messages = Array(messages.prefix(500))
            pending = nil
            pendingSince = nil
            text = ""
            notice = "Delivered to the server. This is not a read receipt."
        } catch {
            guard current(id, token: token) else { return }
            fail(error)
        }
    }

    func editDraft() { pending = nil; pendingSince = nil; notice = nil; error = nil }

    func setBlocked(_ call: String, blocked: Bool) async {
        guard let (id, token) = begin() else { return }
        defer { if generation == id { working = false } }
        guard owner != nil else { return }
        do {
            try await service.block(call, blocked: blocked, token: token)
            let calls = try await service.blocks(token: token)
            guard current(id, token: token) else { return }
            blockedCalls = calls
            notice = blocked ? "\(call) blocked. New messages in either direction are refused." : "\(call) unblocked."
        } catch {
            guard current(id, token: token) else { return }
            fail(error)
        }
    }

    func report(_ message: SKEDPrivateMessage, reason: String) async {
        guard let (id, token) = begin() else { return }
        defer { if generation == id { working = false } }
        guard owner != nil else { return }
        do {
            try await service.report(message, reason: reason, token: token)
            guard current(id, token: token) else { return }
            notice = "Report recorded for the service operator. Use Block to stop further messages."
        } catch {
            guard current(id, token: token) else { return }
            fail(error)
        }
    }
}
