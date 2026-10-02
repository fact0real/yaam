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
