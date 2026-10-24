import Foundation

nonisolated enum FT8TransmissionTiming {
    /// The same deadline applies to every CAT/audio path. Check again after setup or suspension.
    static func canStart(slot: Date, now: Date) -> Bool {
        now.timeIntervalSince(slot) < 0.10
    }
}
