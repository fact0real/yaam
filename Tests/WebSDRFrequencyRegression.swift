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
        print("WebSDR manual frequency regression passed")
    }
}
