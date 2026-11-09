import Foundation

/// The sheet's identity and payload travel together, so SwiftUI cannot reuse an empty draft.
struct QRZIncomingEmailBatch: Identifiable {
    let id = UUID()
    let requests: [QRZIncomingConfirmation]
    let emails: [String: String]
    let profileID: UUID?

    init?(requests: [QRZIncomingConfirmation], selectedIDs: Set<String>,
          states: [String: QRZIncomingEmailStatus], profileID: UUID?) {
        var emails: [String: String] = [:]
        let eligible = requests.filter { request in
            guard selectedIDs.contains(request.id),
                  let call = QRZIncomingEmailEvidence.normalizedCall(request.callsign),
                  let email = states[call]?.email, QRZIncomingBulkMail.isUsableEmail(email) else { return false }
            emails[call] = email.trimmingCharacters(in: .whitespacesAndNewlines)
            return true
        }
        guard !eligible.isEmpty else { return nil }
        self.requests = eligible
        self.emails = emails
        self.profileID = profileID
    }
}
