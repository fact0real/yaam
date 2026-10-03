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
        precondition(SKEDStateLogMatch.matches(destinationISO: "us", stateCode: "CA", stateName: "California",
                                               loggedISO: "US", loggedState: " ca "))
        precondition(!SKEDStateLogMatch.matches(destinationISO: "us", stateCode: "CA", stateName: "California",
                                                loggedISO: "US", loggedState: "NY"))
        precondition(SKEDStateLogMatch.matches(destinationISO: "us", stateCode: "PR", stateName: "Puerto Rico",
                                               loggedISO: "PR", loggedState: "Puerto Rico"))

        let operators = SKEDOperatorBandActivity.grouped(entries: [
            .init(callsign: " xw1yc ", band: "15M", confirmed: true),
            .init(callsign: "XW1YC", band: "20m", confirmed: false),
            .init(callsign: "XW1YC", band: "", confirmed: false),
            .init(callsign: "XW1OS", band: "40m", confirmed: false),
            .init(callsign: "XW1OS", band: "2m", confirmed: true)
        ])
        precondition(operators["XW1YC"]?.qsoCount == 3)
        precondition(operators["XW1YC"]?.worked == ["15m", "20m"])
        precondition(operators["XW1YC"]?.confirmed == ["15m"])
        precondition(operators["XW1YC"]?.bandSummary == "Confirmed 15m · Worked 20m")
        precondition(operators["XW1OS"]?.bandSummary == "Confirmed 2m · Worked 40m")
        precondition(operators["XW1AA"] == nil)

        let bands: Set<String> = ["17m", "20m", "40m"]
        let message = SKEDMailTemplate.render(
            SKEDMailTemplate.defaultBody, callsign: "EP1AAA", name: "Alex Example",
            bands: bands, stationCallsign: "W1ABC", stationGrid: "FN42", stationQTH: "Boston")
        precondition(message.contains("Hi Alex (EP1AAA),"))
        precondition(message.contains("40m, 20m, and 17m"))
        precondition(message.contains("W1ABC in Boston (grid FN42)"))
        precondition(message.contains("current propagation"))
        precondition(message.contains("antenna's resonance"))
        precondition(message.contains("using FT8 or FT4"))
        precondition(SKEDMailTemplate.defaultSubject.contains("{mode}"))
        let ft4 = SKEDMailTemplate.render("Let's use {mode} on {bands}.", callsign: "EP1AAA",
            name: "Alex Example", bands: ["20m"], stationCallsign: "W1ABC",
            stationGrid: "FN42", stationQTH: "Boston", mode: .ft4)
        precondition(ft4 == "Let's use FT4 on 20m.")
        precondition(SKEDMailTemplate.unresolvedFields("{mode} {bands}").isEmpty)
        precondition(!message.contains("I hope you're doing well!"))
        precondition(!message.contains("{time_window}"))
        precondition(SKEDMailTemplate.fourCharacterGrid("fn42ab") == "FN42")
        precondition(SKEDMailTemplate.fourCharacterGrid("fn3") == "")
        precondition(SKEDMailTemplate.signature(name: "Alex Smith", callsign: "W1ABC") == "73,\nAlex Smith\nW1ABC")
        var tehranCalendar = Calendar(identifier: .gregorian)
        tehranCalendar.timeZone = TimeZone(identifier: "Asia/Tehran")!
        let start = tehranCalendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 19, minute: 30))!
        let end = start.addingTimeInterval(90 * 60)
        let utcWindow = SKEDMailTemplate.utcWindow(start: start, end: end, timeZone: tehranCalendar.timeZone)
        precondition(utcWindow.contains("on 2026-10-03"))
        precondition(utcWindow.contains("each day from 16:00 to 17:30 UTC"))
        precondition(!utcWindow.contains("GMT"))
        let crossingMidnight = tehranCalendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 2))!
        let crossingWindow = SKEDMailTemplate.utcWindow(start: crossingMidnight,
                                                        end: crossingMidnight.addingTimeInterval(2 * 3600),
                                                        timeZone: tehranCalendar.timeZone)
        precondition(crossingWindow.contains("2026-10-02 22:30–2026-10-03 00:30 UTC"))
        let dailyStart = tehranCalendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 10))!
        let dailyEnd = tehranCalendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 20))!
        let dailyWindow = SKEDMailTemplate.utcWindow(start: dailyStart, end: dailyEnd,
                                                     timeZone: tehranCalendar.timeZone)
        precondition(dailyWindow.contains("on any day from 2026-10-03 through 2026-10-05"))
        precondition(dailyWindow.contains("each day from 06:30 to 16:30 UTC"))
        precondition(!dailyWindow.contains("between"))
        precondition(!SKEDMailTemplate.isValidDailyWindow(start: dailyStart,
                                                         end: tehranCalendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!,
                                                         timeZone: tehranCalendar.timeZone))
        let scheduled = SKEDMailTemplate.render(
            SKEDMailTemplate.defaultBody, callsign: "EP1AAA", name: "Alex Example",
            bands: ["20m"], stationCallsign: "W1ABC", stationGrid: "FN42",
            stationQTH: "Boston", stationName: "Taylor", timeWindowUTC: utcWindow)
        precondition(scheduled.contains("each day from 16:00 to 17:30 UTC"))
        precondition(!scheduled.contains("{time_window}"))
        let secondMessage = SKEDMailTemplate.render(
            SKEDMailTemplate.defaultBody, callsign: "EP2BBB", name: "Samira Example",
            bands: ["15m"], stationCallsign: "W1ABC", stationGrid: "FN42", stationQTH: "Boston")
        precondition(secondMessage.contains("Hi Samira (EP2BBB),"))
        precondition(secondMessage.contains("on 15m, using FT8 or FT4."))
        precondition(!secondMessage.contains("EP1AAA"))
        let mixedFields = SKEDMailTemplate.render("Hi {GREETING}, {CALLSIGN} / {MY_CALL} / {BANDS} / {BAND}",
            callsign: "EP2BBB", name: "SMITH, JOHN", bands: ["20m"], stationCallsign: "W1ABC",
            stationGrid: "FN42", stationQTH: "Boston")
        precondition(mixedFields == "Hi JOHN, EP2BBB / W1ABC / 20m / {BAND}")
        precondition(SKEDMailTemplate.unresolvedFields(mixedFields) == ["BAND"])
        precondition(SKEDMailTemplate.greetingName("Dr. Ali Smith") == "Ali")
        precondition(SKEDMailTemplate.greetingName("SMITH, JOHN") == "JOHN")
        precondition(SKEDMailTemplate.greetingName("J. Robert Smith") == "Robert")
        precondition(SKEDMailTemplate.greetingName("Doe, Jr.", callsign: "EP1AAA") == "EP1AAA")
        precondition(SKEDMailTemplate.greetingName("رضایی، علی") == "علی")
        precondition(SKEDMailTemplate.unresolvedFields("{BAND2} {foo-bar}") == ["BAND2", "foo-bar"])
        let noRescan = SKEDMailTemplate.render("{name}", callsign: "EP2BBB", name: "{my_call}",
            bands: [], stationCallsign: "W1ABC", stationGrid: "", stationQTH: "")
        precondition(noRescan == "{my_call}")
        precondition(SKEDMailTemplate.safeSubject("Hello\r\nBcc: hidden") == "Hello Bcc: hidden")
        print("SKED planning regression passed")
    }
}
