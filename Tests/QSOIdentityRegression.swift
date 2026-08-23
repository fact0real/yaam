import Foundation

@main
struct QSOIdentityRegression {
    static func main() {
        let base = fields(time: "19:05", band: "20 meters", mode: "MFSK", submode: "FT8")
        let equivalent = fields(time: "190500", band: "20M", mode: "FT8", submode: "")
        let laterContact = fields(time: "190501", band: "20M", mode: "FT8", submode: "")

        precondition(QSOIdentity.exactKey(fields: base) == QSOIdentity.exactKey(fields: equivalent))
        precondition(QSOIdentity.exactKey(fields: base) != QSOIdentity.exactKey(fields: laterContact))
        precondition(QSOIdentity.relaxedKey(fields: base) == QSOIdentity.relaxedKey(fields: laterContact))
        precondition(QSOIdentity.secondsFromMidnight(base) == 19 * 3_600 + 5 * 60)

        var inferred = equivalent
        inferred["BAND"] = ""
        inferred["FREQ"] = "14.074 MHz"
        precondition(QSOIdentity.resolvedBand(inferred) == "20M")

        var hertz = equivalent
        hertz["BAND"] = ""
        hertz["FREQ"] = "18100000"
        precondition(QSOIdentity.resolvedBand(hertz) == "17M")

        print("QSO identity regression tests passed.")
    }

    private static func fields(
        time: String,
        band: String,
        mode: String,
        submode: String
    ) -> [String: String] {
        [
            "CALL": " ep2aes ",
            "QSO_DATE": "2026-08-23",
            "TIME_ON": time,
            "BAND": band,
            "MODE": mode,
            "SUBMODE": submode
        ]
    }
}
