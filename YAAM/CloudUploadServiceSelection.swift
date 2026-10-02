import Foundation

nonisolated struct CloudUploadServiceSelection {
    let services: [String]
    let needsConfigurationCheck: Bool

    static func select(
        enabled: [String],
        vaultUnlocked: Bool,
        configured: [String]
    ) -> CloudUploadServiceSelection {
        guard vaultUnlocked else {
            return .init(services: enabled, needsConfigurationCheck: true)
        }
        let available = Set(configured)
        return .init(
            services: enabled.filter { available.contains($0) },
            needsConfigurationCheck: false
        )
    }

    /// Re-queuing a QSO while locked must not reclassify earlier pending uploads as unconfigured.
    static func mergedUncheckedServices(
        existingPending: [String],
        existingUnchecked: [String],
        incoming: [String]
    ) -> [String] {
        let alreadyPending = Set(existingPending)
        var seen = Set<String>()
        return (existingUnchecked + incoming.filter { !alreadyPending.contains($0) })
            .filter { seen.insert($0).inserted }
    }
}
