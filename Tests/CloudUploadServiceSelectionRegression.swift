import Foundation

@main
struct CloudUploadServiceSelectionRegression {
    static func main() {
        let enabled = ["QRZ", "Club Log", "eQSL", "Wavelog", "LoTW"]

        let onlyQRZ = CloudUploadServiceSelection.select(
            enabled: enabled, vaultUnlocked: true, configured: ["QRZ"]
        )
        precondition(onlyQRZ.services == ["QRZ"] && !onlyQRZ.needsConfigurationCheck)

        let unavailable = CloudUploadServiceSelection.select(
            enabled: enabled, vaultUnlocked: true, configured: []
        )
        precondition(unavailable.services.isEmpty && !unavailable.needsConfigurationCheck)

        // A locked Keychain cannot establish absence. Defer the decision until unlock.
        let locked = CloudUploadServiceSelection.select(
            enabled: enabled, vaultUnlocked: false, configured: []
        )
        precondition(locked.services == enabled && locked.needsConfigurationCheck)
        let afterUnlock = CloudUploadServiceSelection.select(
            enabled: locked.services, vaultUnlocked: true, configured: ["QRZ"]
        )
        precondition(afterUnlock.services == ["QRZ"] && !afterUnlock.needsConfigurationCheck)

        let merged = CloudUploadServiceSelection.mergedUncheckedServices(
            existingPending: ["QRZ"],
            existingUnchecked: [],
            incoming: ["QRZ", "Club Log"]
        )
        precondition(merged == ["Club Log"], "An existing QRZ retry must not be dropped on unlock")

        print("Cloud upload service selection regression passed")
    }
}
