import Foundation

@main
struct SKEDPlanningRegression {
    static func main() {
        precondition(SKEDMailTemplate.bands.count == 11)
        precondition(SKEDMailTemplate.bands.first == "160m")
        precondition(SKEDMailTemplate.bands.last == "6m")
        let activity = SKEDCountryBandActivity.make(entries: [
            .init(countryISO: "IR", band: "20m", confirmed: true),
            .init(countryISO: "ir", band: "40m", confirmed: false),
            .init(countryISO: "ir", band: "4m", confirmed: true),
            .init(countryISO: "ir", band: "", confirmed: false),
            .init(countryISO: "US", band: "15m", confirmed: true)
        ], countryISO: "ir")
        precondition(activity.qsoCount == 4)
        precondition(activity.worked == ["20m", "40m"])
        precondition(activity.confirmed == ["20m"])

        let bands: Set<String> = ["17m", "20m", "40m"]
        let message = SKEDMailTemplate.render(
            SKEDMailTemplate.defaultBody, callsign: "EP1AAA", name: "Alex Example",
            bands: bands, stationCallsign: "W1ABC", stationGrid: "FN42", stationQTH: "Boston")
        precondition(message.contains("Hi Alex (EP1AAA),"))
        precondition(message.contains("40m, 20m, and 17m"))
        precondition(message.contains("W1ABC in Boston (grid FN42)"))
        precondition(message.contains("current propagation"))
        precondition(message.contains("antenna's resonance"))
        precondition(!message.contains("I hope you're doing well!"))
        precondition(!message.contains("{time_window}"))
        precondition(SKEDMailTemplate.fourCharacterGrid("fn42ab") == "FN42")
        precondition(SKEDMailTemplate.fourCharacterGrid("fn3") == "")
        precondition(SKEDMailTemplate.signature(name: "Alex Smith", callsign: "W1ABC") == "73,\nAlex Smith\nW1ABC")
        var tehranCalendar = Calendar(identifier: .gregorian)
        tehranCalendar.timeZone = TimeZone(identifier: "Asia/Tehran")!
        let start = tehranCalendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 19, minute: 30))!
        let end = start.addingTimeInterval(90 * 60)
        let utcWindow = SKEDMailTemplate.utcWindow(start: start, end: end)
        precondition(utcWindow.contains("2026-10-03 16:00 UTC"))
        precondition(utcWindow.contains("2026-10-03 17:30 UTC"))
        precondition(!utcWindow.contains("GMT"))
        let crossingMidnight = tehranCalendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 2))!
        let crossingWindow = SKEDMailTemplate.utcWindow(start: crossingMidnight,
                                                        end: crossingMidnight.addingTimeInterval(2 * 3600))
        precondition(crossingWindow.contains("2026-10-02 22:30 UTC"))
        precondition(crossingWindow.contains("2026-10-03 00:30 UTC"))
        let scheduled = SKEDMailTemplate.render(
            SKEDMailTemplate.defaultBody, callsign: "EP1AAA", name: "Alex Example",
            bands: ["20m"], stationCallsign: "W1ABC", stationGrid: "FN42",
            stationQTH: "Boston", stationName: "Taylor", timeWindowUTC: utcWindow)
        precondition(scheduled.contains("2026-10-03 16:00 UTC"))
        precondition(!scheduled.contains("{time_window}"))
        let secondMessage = SKEDMailTemplate.render(
            SKEDMailTemplate.defaultBody, callsign: "EP2BBB", name: "Samira Example",
            bands: ["15m"], stationCallsign: "W1ABC", stationGrid: "FN42", stationQTH: "Boston")
        precondition(secondMessage.contains("Hi Samira (EP2BBB),"))
        precondition(secondMessage.contains("on 15m."))
        precondition(!secondMessage.contains("EP1AAA"))
        precondition(SKEDMailTemplate.safeSubject("Hello\r\nBcc: hidden") == "Hello Bcc: hidden")
        print("SKED planning regression passed")
    }
}
