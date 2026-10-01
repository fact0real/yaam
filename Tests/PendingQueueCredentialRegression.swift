import Foundation

// Standalone: swiftc -parse-as-library Tests/PendingQueueCredentialRegression.swift YAAM/KeychainStore.swift -o /tmp/pqcr && /tmp/pqcr
// (verbatim copy of PendingCloudUploadItem AFTER the fix, ZeroClickCloudUploadDaemon.swift:33-83 minus qrzKeyOverride)
struct PendingCloudUploadItem: Codable, Identifiable, Equatable {
    let id: UUID
    var recordFields: [String: String]
    let stationID: String?
    let stationLocation: String?
    var pendingServices: [String]
    var attemptCount: Int
    var lastAttemptDate: Date?
    var lastErrorMessage: String?
    var pausedServices: [String]?
    let enqueuedAt: Date
}

@main
struct PendingQueueCredentialRegression {
    static func main() throws {
        let secret = "FAKE-TEST-KEY-1234"
        let sid = UUID()
        // 1. Legacy file (pre-fix) still decodes; the key is ignored.
        let legacy = """
        [{"id":"\(UUID())","recordFields":{"CALL":"K1ABC"},"stationID":"\(sid)","stationLocation":null,
          "qrzKeyOverride":"\(secret)","pendingServices":["QRZ"],"attemptCount":2,
          "enqueuedAt":"2026-09-20T10:00:00Z"}]
        """.data(using: .utf8)!
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let items = try dec.decode([PendingCloudUploadItem].self, from: legacy)
        precondition(items.count == 1 && items[0].attemptCount == 2 && items[0].pendingServices == ["QRZ"])
        precondition(items[0].pausedServices == nil, "Older queue files must decode without pausedServices")
        // scrub trigger used by loadPendingQueueFromDisk
        precondition(legacy.range(of: Data("qrzKeyOverride".utf8)) != nil)

        // 2. Re-encoded queue never contains the key or the field name.
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        let out = try enc.encode(items)
        let text = String(decoding: out, as: UTF8.self)
        precondition(!text.contains(secret) && !text.contains("qrzKeyOverride"))
        let again = try dec.decode([PendingCloudUploadItem].self, from: out)
        precondition(again == items)

        // 3. Resolution at retry time: profile key > global key > empty; rotation is honoured; deleted profile -> global.
        var vault: [UUID: String] = [sid: "PROFILE-KEY"]
        var global = "GLOBAL-KEY"
        func resolve(_ s: String?) -> String {
            CredentialVault.qrzLogbookKey(stationID: s, stationKey: { vault[$0] ?? "" }, globalKey: { global })
        }
        precondition(resolve(sid.uuidString) == "PROFILE-KEY")
        vault[sid] = " ROTATED "; precondition(resolve(sid.uuidString) == "ROTATED")
        vault[sid] = nil; precondition(resolve(sid.uuidString) == "GLOBAL-KEY")
        precondition(resolve(nil) == "GLOBAL-KEY" && resolve("not-a-uuid") == "GLOBAL-KEY" && resolve("") == "GLOBAL-KEY")
        global = ""; precondition(resolve(sid.uuidString).isEmpty)   // never falls back to the QRZ *password*
        print("PendingQueueCredentialRegression passed")
    }
}
