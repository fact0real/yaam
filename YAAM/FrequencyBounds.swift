//
//  FrequencyBounds.swift
//  YAAM
//
//  Spot frequencies come from outside (the DX cluster, WSJT-X on the network, the POTA and SOTA services), and YAAM
//  turns them into whole hertz with UInt64(kHz * 1000) in several places. That conversion stops the app on infinity,
//  NaN, a negative value or a value too large for UInt64. A spot is checked once, where it comes in (Y-001).
//
//  Platform: pure Swift, no AppKit.
//

nonisolated enum FrequencyBounds {
    /// The top of the radio spectrum, for practical purposes (300 GHz); amateur allocations reach 250 GHz.
    static let maximumKHz = 300_000_000.0

    /// Whether `kHz` is a frequency YAAM can tune: a finite number above 0 and up to 300 GHz.
    static func isUsable(kHz: Double) -> Bool {
        kHz.isFinite && kHz >= 0.001 && kHz <= maximumKHz
    }
    /// Safe conversion at the final radio boundary, including archived or restored values.
    static func hertz(kHz: Double) -> UInt64? {
        guard isUsable(kHz: kHz) else { return nil }
        return UInt64(kHz * 1000)
    }
}


/// External report dates must be finite Unix seconds within Foundation's civil calendar range.
nonisolated enum ReportTimeBounds {
    static func seconds(_ value: Double) -> Int? {
        guard value.isFinite, value >= 0, value <= 253_402_300_799 else { return nil }
        return Int(exactly: value.rounded(.down))
    }
}
