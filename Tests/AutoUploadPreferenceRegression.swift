import Foundation

// No transport or Keychain is used by this test.
struct QSORecordModel {
    enum Destination { case hamqth, hrdlog }
    func toADIFRecordString(for destination: Destination) -> String { "<CALL:6>EA3JIC<EOR>" }
}
enum CredentialVault {
    enum Key { case hamqthPassword, hrdlogCode }
    static func value(for key: Key) -> String { "" }
}
@main struct AutoUploadPreferenceRegression {
    @MainActor static func main() async {
        let name="YAAM-upload-preference-test-" + UUID().uuidString
        let defaults=UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let ham=HamQTHUploadClient(defaults: defaults), hrd=HRDLogClient(defaults: defaults)
        precondition(!ham.autoUploadEnabled && !hrd.autoUploadEnabled)
        defaults.set(true, forKey:"hamqthAutoUploadEnabled")
        defaults.set(true, forKey:"hrdlogAutoUploadEnabled")
        precondition(ham.autoUploadEnabled && hrd.autoUploadEnabled, "An existing client must see an enabled preference")
        let pending=Task { @MainActor in
            let first=await ham.uploadSingleQSO(record:QSORecordModel())
            let second=await hrd.uploadSingleQSO(record:QSORecordModel())
            return first || second
        }
        defaults.set(false, forKey:"hamqthAutoUploadEnabled")
        defaults.set(false, forKey:"hrdlogAutoUploadEnabled")
        let sent=await pending.value
        precondition(!sent && ham.lastError==nil && hrd.lastError==nil, "Disabling before dispatch must stop a queued upload before credentials/transport")
        print("Live auto-upload preference and queued-task cancellation checks passed; nothing uploaded")
    }
}
