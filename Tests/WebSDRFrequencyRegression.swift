import Foundation

@main
struct WebSDRFrequencyRegression {
    static func main() {
        let receiverBands: Set<String> = ["20m", "40m"]
        let selected = try! WebSDRFrequency.resolve("14.074500", receiverBands: receiverBands).get()
        precondition(selected == .init(band: "20m", dialHz: 14_074_500))
        precondition(WebSDRFrequency.formattedMHz(selected.dialHz) == "14.0745")
        precondition(WebSDRFrequency.tuneQuery(selected.dialHz) == "tune=14074.5usb")

        let crossBand = try! WebSDRFrequency.resolve("7,074", receiverBands: receiverBands).get()
        precondition(crossBand == .init(band: "40m", dialHz: 7_074_000))
        precondition(WebSDRFrequency.tuneQuery(crossBand.dialHz) == "tune=7074usb")

        // Persian and Arabic-Indic digits, the Arabic decimal separator and comma, the
        // bidirectional marks U+200E, U+200F and U+061C, and a "MHz" suffix resolve exactly
        // like the same frequency typed with ASCII digits.
        let plain = try! WebSDRFrequency.resolve("14.074", receiverBands: receiverBands).get()
        precondition(plain == .init(band: "20m", dialHz: 14_074_000))
        let equivalents = ["۱۴.۰۷۴", "۱۴٫۰۷۴", "١٤٫٠٧٤", "١٤.٠٧٤", "۱۴,۰۷۴", "14.074 MHz",
                           "14.074mhz", " ۱۴٫۰۷۴ MHz ", "14.074 mHZ",
                           "۱۴\u{060C}۰۷۴", "\u{200F}۱۴٫۰۷۴\u{200F}", "\u{200E}14.074\u{061C}",
                           "۱۴\u{200F}٫\u{200F}۰۷۴", "\u{200F}۱۴٫۰۷۴ MHz\u{200F}",
                           "14.074 MHz \u{200F}"]
        var mismatches = equivalents.filter {
            WebSDRFrequency.resolve($0, receiverBands: receiverBands) != .success(plain)
        }
        // The digits 8 and 9 sit at the top of the digit range of each script.
        let plain098 = try! WebSDRFrequency.resolve("14.098", receiverBands: receiverBands).get()
        precondition(plain098 == .init(band: "20m", dialHz: 14_098_000))
        mismatches += ["۱۴٫۰۹۸", "١٤٫٠٩٨"].filter {
            WebSDRFrequency.resolve($0, receiverBands: receiverBands) != .success(plain098)
        }
        precondition(mismatches.isEmpty, "not resolved like the ASCII spelling: \(mismatches)")

        func rejects(_ input: String, receiver: Set<String> = receiverBands,
                     antenna: Set<String>? = nil) -> Bool {
            if case .failure = WebSDRFrequency.resolve(input, receiverBands: receiver,
                                                        antennaBands: antenna) { return true }
            return false
        }
        precondition(rejects("nan"))
        precondition(rejects("14.0740009"))
        precondition(rejects("144.174"))
        precondition(rejects("10.136"))
        precondition(rejects("7.074", antenna: ["20m"]))
        precondition(rejects("MHz"))
        precondition(rejects("14.074 kHz"))
        precondition(rejects("14.074 MHz MHz"))
        precondition(rejects("14.074MHzMHz"))
        precondition(rejects("MHz 14.074"))
        precondition(rejects("۱۴.۰۷۴۴۴۴۴"))
        precondition(rejects("۱۴\u{060C}۰۷\u{060C}۴"))
        precondition(rejects("\u{200F}MHz\u{200F}"))
        precondition(rejects("۱۴٫۰۷۴ مگاهرتز"))
        let standard = URL(string: "http://example.org/?tune=7074usb&theme=dark")!
        precondition(WebSDRTuningStyle.webSDR.tunedURL(standard, dialHz: 14_074_000)?.absoluteString ==
                     "http://example.org/?theme=dark&tune=14074usb")
        let kiwi = URL(string: "http://example.org:8073/")!
        precondition(WebSDRTuningStyle.kiwiSDR.tunedURL(kiwi, dialHz: 14_074_500)?.absoluteString ==
                     "http://example.org:8073/?f=14074.5usb")
        let frequency = URL(string: "http://example.org/?frequency=14074000&modulation=USB&theme=dark")!
        precondition(WebSDRTuningStyle.frequencyHz.tunedURL(frequency, dialHz: 7_074_000)?.absoluteString ==
                     "http://example.org/?theme=dark&frequency=7074000&modulation=USB")
        print("WebSDR manual frequency regression passed")
    }
}
