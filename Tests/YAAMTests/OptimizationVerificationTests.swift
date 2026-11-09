import Foundation

struct EmailHistoryEntry: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let callsign: String
    let email: String
    let subject: String
    let status: String
    let kind: String?
    
    var countsAsQSL: Bool {
        if status.lowercased() != "sent" { return false }
        let k = (kind ?? "").uppercased()
        if k == "SKED" { return false }
        return true
    }
}

final class MockAppState {
    var emailHistory: [EmailHistoryEntry] = [] {
        didSet { rebuildEmailHistoryIndices() }
    }
    var emailHistoryByCallsign: [String: EmailHistoryEntry] = [:]
    var emailHistoryQSLByCallsign: [String: EmailHistoryEntry] = [:]
    
    func rebuildEmailHistoryIndices() {
        var map: [String: EmailHistoryEntry] = [:]
        var qslMap: [String: EmailHistoryEntry] = [:]
        for entry in emailHistory {
            let norm = entry.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !norm.isEmpty else { continue }
            if map[norm] == nil {
                map[norm] = entry
            }
            if entry.countsAsQSL && qslMap[norm] == nil {
                qslMap[norm] = entry
            }
        }
        emailHistoryByCallsign = map
        emailHistoryQSLByCallsign = qslMap
    }
    
    func isQSLSent(call: String, qslSent: String, emailSentDate: String?) -> Bool {
        if qslSent.uppercased() == "Y" { return true }
        if let emailSent = emailSentDate, !emailSent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        let clean = call.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !clean.isEmpty, emailHistoryQSLByCallsign[clean] != nil { return true }
        return false
    }
    
    func batchRecordEmailHistory(items: [(callsign: String, email: String, subject: String, status: String, kind: String?)]) {
        let now = Date()
        var newEntries: [EmailHistoryEntry] = []
        for item in items {
            newEntries.append(EmailHistoryEntry(
                id: UUID(),
                date: now,
                callsign: item.callsign,
                email: item.email,
                subject: item.subject,
                status: item.status,
                kind: item.kind
            ))
        }
        var combined = newEntries + emailHistory
        combined.sort { $0.date > $1.date }
        emailHistory = Array(combined.prefix(500))
    }
}

var passed = 0
func assertTest(_ condition: Bool, _ desc: String) {
    if condition {
        passed += 1
        print("  ✅ PASS: \(desc)")
    } else {
        print("  ❌ FAIL: \(desc)")
        exit(1)
    }
}

print("==================================================================")
print("🧪 Running Optimization Verification Tests")
print("==================================================================")

let state = MockAppState()

// 1. Initial state
assertTest(state.emailHistoryQSLByCallsign.isEmpty, "Initial QSL map is empty")

// 2. Batch recording items
state.batchRecordEmailHistory(items: [
    (callsign: "EP2AES", email: "ep2aes@amsat.org", subject: "QSL", status: "Sent", kind: "QSL"),
    (callsign: "UR4QFP", email: "ur4qfp@ukr.net", subject: "QSL", status: "Sent", kind: "QSL"),
    (callsign: "W1AW", email: "w1aw@arrl.org", subject: "SKED", status: "Sent", kind: "SKED"),
    (callsign: "DL1ABC", email: "dl1abc@darc.de", subject: "QSL", status: "Failed", kind: "QSL")
])

assertTest(state.emailHistory.count == 4, "4 items inserted in batch")
assertTest(state.emailHistoryByCallsign["EP2AES"] != nil, "EP2AES found in general email history")
assertTest(state.emailHistoryQSLByCallsign["EP2AES"] != nil, "EP2AES found in QSL email history ($O(1) index)")
assertTest(state.emailHistoryQSLByCallsign["UR4QFP"] != nil, "UR4QFP found in QSL email history")
assertTest(state.emailHistoryQSLByCallsign["W1AW"] == nil, "SKED email correctly excluded from QSL map")
assertTest(state.emailHistoryQSLByCallsign["DL1ABC"] == nil, "Failed email correctly excluded from QSL map")

// 3. Fast isQSLSent evaluation
assertTest(state.isQSLSent(call: "EP2AES", qslSent: "N", emailSentDate: nil) == true, "EP2AES recognized as sent via QSL map ($O(1))")
assertTest(state.isQSLSent(call: "W1AW", qslSent: "N", emailSentDate: nil) == false, "W1AW recognized as not sent for QSL")
assertTest(state.isQSLSent(call: "OTHER", qslSent: "Y", emailSentDate: nil) == true, "QSL_SENT=Y recognized as sent")
assertTest(state.isQSLSent(call: "OTHER2", qslSent: "N", emailSentDate: "20261109") == true, "APP_YAAM_EMAIL_SENT_DATE recognized as sent")

// 4. Performance benchmark: 100,000 lookups
let start = CFAbsoluteTimeGetCurrent()
for _ in 0..<100_000 {
    _ = state.isQSLSent(call: "EP2AES", qslSent: "N", emailSentDate: nil)
    _ = state.isQSLSent(call: "UNKNOWN", qslSent: "N", emailSentDate: nil)
}
let duration = CFAbsoluteTimeGetCurrent() - start
assertTest(duration < 0.2, "200,000 O(1) lookups took \(String(format: "%.3f", duration))s (< 200ms)")

print("==================================================================")
print("📊 All \(passed) Optimization Tests Passed!")
print("==================================================================")
