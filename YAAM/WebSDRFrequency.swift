import Foundation

/// The dial ranges offered by YAAM's FT8 WebSDR band selector. A receiver's
/// advertised band list is checked separately; it does not guarantee that every
/// frequency within a band is covered by that receiver's hardware.
enum WebSDRFrequency {
    struct Selection: Equatable {
        let band: String
        let dialHz: Int
    }

    private static let ranges: [(band: String, mhz: ClosedRange<Double>)] = [
        ("80m", 3.5...4.0), ("40m", 7.0...7.3),
        ("30m", 10.1...10.15), ("20m", 14.0...14.35),
        ("17m", 18.068...18.168), ("15m", 21.0...21.45),
        ("10m", 28.0...29.7)
    ]

    static func resolve(_ text: String, receiverBands: Set<String>,
                        antennaBands: Set<String>? = nil) -> Result<Selection, Error> {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let mhz = Double(input), mhz.isFinite, mhz > 0,
              input.filter({ $0 == "." }).count <= 1,
              let dialHz = Int(exactly: (mhz * 1_000_000).rounded()),
              abs(Double(dialHz) / 1_000_000 - mhz) < 0.0000001 else {
            return .failure(.invalid)
        }
        guard let band = ranges.first(where: { $0.mhz.contains(mhz) })?.band else {
            return .failure(.outsideBands)
        }
        guard receiverBands.contains(band) else {
            return .failure(.receiverDoesNotList(band))
        }
        if let antennaBands, !antennaBands.contains(band) {
            return .failure(.antennaDoesNotList(band))
        }
        return .success(.init(band: band, dialHz: dialHz))
    }

    static func formattedMHz(_ dialHz: Int) -> String {
        trimmedDecimal(Double(dialHz) / 1_000_000, places: 6)
    }

    static func tuneQuery(_ dialHz: Int) -> String {
        "tune=\(trimmedDecimal(Double(dialHz) / 1_000, places: 3))usb"
    }

    private static func trimmedDecimal(_ value: Double, places: Int) -> String {
        var text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value)
        while text.last == "0" { text.removeLast() }
        if text.last == "." { text.removeLast() }
        return text
    }

    enum Error: LocalizedError, Equatable {
        case invalid
        case outsideBands
        case receiverDoesNotList(String)
        case antennaDoesNotList(String)

        var errorDescription: String? {
            switch self {
            case .invalid: "Enter a frequency in MHz, with up to six decimal places."
            case .outsideBands: "Choose a frequency within an available FT8 band (80–10 m)."
            case .receiverDoesNotList(let band): "This receiver does not list \(band). Choose another receiver or frequency."
            case .antennaDoesNotList(let band): "The selected Utah antenna does not list \(band). Choose another antenna or frequency."
            }
        }
    }
}
