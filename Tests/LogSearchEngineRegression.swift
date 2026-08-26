import Foundation

@main
struct LogSearchEngineRegression {
    static func main() {
        let marian = LogSearchEngine.makeDocument(
            fields: [
                "CALL": "SP6FCQ",
                "NAME": "Marian (Mario) Kremis",
                "MODE": "FT8",
                "GRIDSQUARE": "JO70"
            ],
            country: "Poland",
            continent: "EU",
            countryFlag: ""
        )

        precondition(LogSearchEngine.matches(marian, query: "sp6fcq", mode: .callsign))
        precondition(!LogSearchEngine.matches(marian, query: "SP6", mode: .callsign))
        precondition(LogSearchEngine.matches(marian, query: "SP6FCQ, A41SS", mode: .callsign))
        precondition(LogSearchEngine.matches(marian, query: "Marian Kremis", mode: .name))
        precondition(LogSearchEngine.matches(marian, query: "Kremis Marian", mode: .name))
        precondition(LogSearchEngine.matches(marian, query: "Goran Holmdahl; Marian Kremis", mode: .name))
        precondition(!LogSearchEngine.matches(marian, query: "Marian Holmdahl", mode: .name))
        precondition(LogSearchEngine.matches(marian, query: "Poland FT8", mode: .quick))

        let goran = LogSearchEngine.makeDocument(
            fields: [
                "CALL": "SM6CWP",
                "NAME": "G\\u{00F6}ran \\"George\\" Holmdahl",
                "MODE": "FT8"
            ],
            country: "Sweden",
            continent: "EU",
            countryFlag: ""
        )

        precondition(LogSearchEngine.matches(goran, query: "Goran Holmdahl", mode: .name))

        // Test Club Log Personal Spots with the exact HTML structure provided by user
        let clubLogHTML = """
        <table cellspacing="0" cellpadding="0" width="100%" style="font-size:9pt;">
            <tr>
                <td style='font-family:monospace;'>AC2PB</td>
                <td>21010.3</td>
                <td style='font-family:monospace;font-weight:bold;'>RI1FJL</td>
                <td>cw spasibo gl</td>
                <td>
                    <a style='color:black;' href='mostwanted2.php?dxcc=61'>FRANZ JOSEF LAND</a>
                    <br>
                    <small>
                        <font color='orange'>Most-Wanted #44</font>
                    </small>
                </td>
                <td>2026-08-26 19:48</td>
                <td>
                    <a href='propagation.php?formdest=61'>Prop.</a>
                </td>
            </tr>
            <tr>
                <td style='font-family:monospace;'>NK2Y</td>
                <td>14047.0</td>
                <td style='font-family:monospace;font-weight:bold;'>NP2X</td>
                <td>cwt cw                    fk77</td>
                <td>
                    <a style='color:black;' href='mostwanted2.php?dxcc=285'>US VIRGIN ISLANDS</a>
                    &nbsp;
                    <small>
                        <font color='blue'>LoTW</font>
                    </small>
                </td>
                <td>2026-08-26 19:45</td>
                <td>
                    <a href='propagation.php?formdest=285'>Prop.</a>
                </td>
            </tr>
            <tr>
                <td style='font-family:monospace;'>SP5EBH</td>
                <td>14074.0</td>
                <td style='font-family:monospace;font-weight:bold;'>RI1FJL</td>
                <td>ko02md &lt;&gt;lr90</td>
                <td>
                    <a style='color:black;' href='mostwanted2.php?dxcc=61'>FRANZ JOSEF LAND</a>
                    <br>
                    <small>
                        <font color='orange'>Most-Wanted #44</font>
                    </small>
                </td>
                <td>2026-08-26 19:40</td>
                <td>
                    <a href='propagation.php?formdest=61'>Prop.</a>
                </td>
            </tr>
        </table>
        """

        let spots = ClubLogSpotsService.parsePersonalSpotsHTML(clubLogHTML)
        precondition(spots.count == 3, "Expected 3 spots parsed, got \(spots.count)")

        // Spot 0: RI1FJL
        let s0 = spots[0]
        precondition(s0.callsign == "RI1FJL", "Expected RI1FJL, got \(s0.callsign)")
        precondition(s0.spotter == "AC2PB", "Expected AC2PB, got \(s0.spotter)")
        precondition(s0.frequency == "21.0103", "Expected 21.0103, got \(s0.frequency)")
        precondition(s0.band == "15M", "Expected 15M, got \(s0.band)")
        precondition(s0.mode == "CW", "Expected CW, got \(s0.mode)")
        precondition(s0.dxcc == "FRANZ JOSEF LAND", "Expected FRANZ JOSEF LAND, got \(s0.dxcc)")
        precondition(s0.status == "Most-Wanted #44", "Expected Most-Wanted #44, got \(s0.status)")
        precondition(s0.timeStr == "2026-08-26 19:48", "Expected time, got \(s0.timeStr)")

        // Spot 1: NP2X
        let s1 = spots[1]
        precondition(s1.callsign == "NP2X", "Expected NP2X, got \(s1.callsign)")
        precondition(s1.spotter == "NK2Y", "Expected NK2Y, got \(s1.spotter)")
        precondition(s1.frequency == "14.047", "Expected 14.047, got \(s1.frequency)")
        precondition(s1.band == "20M", "Expected 20M, got \(s1.band)")
        precondition(s1.mode == "CW", "Expected CW, got \(s1.mode)")
        precondition(s1.dxcc == "US VIRGIN ISLANDS", "Expected US VIRGIN ISLANDS, got \(s1.dxcc)")
        precondition(s1.status == "LoTW", "Expected LoTW, got \(s1.status)")

        // Spot 2: RI1FJL FT8
        let s2 = spots[2]
        precondition(s2.callsign == "RI1FJL", "Expected RI1FJL, got \(s2.callsign)")
        precondition(s2.frequency == "14.074", "Expected 14.074, got \(s2.frequency)")
        precondition(s2.band == "20M", "Expected 20M, got \(s2.band)")
        precondition(s2.mode == "FT8", "Expected FT8, got \(s2.mode)")

        print("All Club Log exact table parsing regression checks passed successfully!")
    }
}
