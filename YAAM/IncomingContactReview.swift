import Foundation

/// Incoming supplies a request, not verified QSO data. No time, band or mode defaults.
nonisolated struct IncomingContactReview: Codable, Equatable, Sendable {
    var call = ""
    var date = ""
    var time = ""
    var band = ""
    var mode = ""
    var station = ""
    var evidence = ""
    var verified = false
    var separateContact = false
    init() {}

    static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
    var fields: [String: String] {
        var values = ["CALL": Self.clean(call), "QSO_DATE": date, "TIME_ON": time,
                      "BAND": Self.clean(band), "MODE": Self.clean(mode), "STATION_CALLSIGN": Self.clean(station)]
        let parents = ["FT4": "MFSK", "JS8": "MFSK", "USB": "SSB", "LSB": "SSB", "PSK31": "PSK"]
        if let parent = parents[Self.clean(mode)] { values["MODE"] = parent; values["SUBMODE"] = Self.clean(mode) }
        return values
    }
    var problem: String? {
        for value in [call, station] {
            let call = Self.clean(value)
            if call.range(of: #"^[A-Z0-9/]{3,20}$"#, options: .regularExpression) == nil ||
                !call.contains(where: { $0.isLetter }) || !call.contains(where: { $0.isNumber }) {
                return "Enter the actual worked and station callsigns."
            }
        }
        if Self.clean(call) == Self.clean(station) { return "A station cannot log itself."
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        formatter.isLenient = false
        guard date.count == 8, date.allSatisfy({ $0.isASCII && $0.isNumber }),
              let day = formatter.date(from: date), formatter.string(from: day) == date else {
            return "Enter a real UTC date as YYYYMMDD."
        }
        guard [4, 6].contains(time.count), time.allSatisfy({ $0.isASCII && $0.isNumber }),
              let hour = Int(time.prefix(2)), hour < 24,
              let minute = Int(time.dropFirst(2).prefix(2)), minute < 60,
              time.count == 4 || (Int(time.suffix(2)) ?? 60) < 60 else {
            return "Enter the actual UTC time as HHMM or HHMMSS; unknown time cannot be sent."
        }
        let bands: Set<String> = ["2190M", "630M", "560M", "160M", "80M", "60M", "40M", "30M", "20M", "17M", "15M", "12M", "10M", "8M", "6M", "5M", "4M", "2M", "1.25M", "70CM", "33CM", "23CM", "13CM", "9CM", "6CM", "3CM", "1.25CM", "6MM", "4MM", "2.5MM", "2MM", "1MM", "SUBMM"]
        guard bands.contains(Self.clean(band)) else { return "Enter the actual ADIF band, for example 20M."
        }
        let modes: Set<String> = ["AM", "ARDOP", "ATV", "C4FM", "CHIP", "CLO", "CONTESTI", "CW", "DIGITALVOICE", "DOMINO", "DSTAR", "FAX", "FM", "FSK441", "FT4", "FT8", "HELL", "ISCAT", "JS8", "JT4", "JT6M", "JT9", "JT44", "JT65", "LSB", "MFSK", "MSK144", "MT63", "OLIVIA", "OPERA", "PAC", "PAX", "PKT", "PSK", "PSK31", "PSK2K", "Q15", "Q65", "QRA64", "ROS", "RTTY", "RTTYM", "SSB", "SSTV", "T10", "THOR", "THRB", "TOR", "USB", "V4", "VOI", "WINMOR", "WSPR"]
        guard modes.contains(Self.clean(mode)) else {
            return "Enter the actual ADIF mode, for example SSB or FT8."
        }
        guard !evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Record the source of the actual details: local notes, log or operator reply."
        }
        guard verified else { return "Review the local candidates and explicitly verify these actual contact details."
        }
        return nil
    }
    func detailsRequest(myCall: String) -> String {
        "Hello \(Self.clean(call)),\n\nI am reviewing your QRZ Incoming request for \(date.isEmpty ? "an unspecified date" : date). It may be missing from my log or have inconsistent details. Could you send the actual UTC date and time, band/frequency, mode and the callsign/location you worked? I will compare them with my own records before logging or submitting anything.\n\n73, \(myCall)"
    }
}
