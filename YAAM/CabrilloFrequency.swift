import Foundation

/// Frequency field of a Cabrillo 3.0 QSO: line (wwrof.org, "Cabrillo QSO Data"): the frequency in kHz below
/// 50 MHz, and a band designator from 50 MHz up (50, 70, 144, 222, 432, 902, 1.2G, 2.3G ... 241G).
/// Pure Foundation, so it can be tested standalone:
///   swiftc -parse-as-library Tests/CabrilloFrequencyRegression.swift YAAM/CabrilloFrequency.swift -o /tmp/cf && /tmp/cf
nonisolated enum CabrilloFrequency {
    private static let designators: [(ClosedRange<Double>, String)] = [
        (50.0...54.0, "50"), (69.9...71.0, "70"), (144.0...148.0, "144"), (219.0...225.0, "222"),
        (420.0...450.0, "432"), (902.0...928.0, "902"), (1_240.0...1_300.0, "1.2G"), (2_300.0...2_450.0, "2.3G"),
        (3_300.0...3_500.0, "3.4G"), (5_650.0...5_925.0, "5.7G"), (10_000.0...10_500.0, "10G"),
        (24_000.0...24_250.0, "24G"), (47_000.0...47_200.0, "47G"), (75_500.0...81_000.0, "75G"),
        (119_980.0...123_000.0, "122G"), (134_000.0...149_000.0, "134G"), (241_000.0...250_000.0, "241G")
    ]

    private static let bandDesignators: [String: String] = [
        "6M": "50", "4M": "70", "2M": "144", "1.25M": "222", "70CM": "432", "33CM": "902",
        "23CM": "1.2G", "13CM": "2.3G", "9CM": "3.4G", "6CM": "5.7G", "3CM": "10G", "1.25CM": "24G",
        "6MM": "47G", "4MM": "75G", "2.5MM": "122G", "2MM": "134G", "1MM": "241G"
    ]

    /// `mhz` is the QSO frequency in MHz.
    static func field(mhz: Double) -> String {
        guard mhz.isFinite, mhz > 0, mhz <= 250_000 else { return "0" }
        if mhz < 50 { return String(Int((mhz * 1_000).rounded())) }
        if let designator = designators.first(where: { $0.0.contains(mhz) })?.1 { return designator }
        return mhz >= 1_000 ? "\(Int(mhz / 1_000))G" : String(Int(mhz))
    }

    /// Designator for an ADIF BAND from 6 m up, used when a QSO has no frequency.
    static func designator(forBand band: String) -> String? {
        bandDesignators[band.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]
    }
}
