// Exercises the production parser; network/session dependencies are inert stand-ins.
// swiftc -parse-as-library Tests/ClubLogPersonalSpotsRegression.swift YAAM/ClubLogSpotsService.swift -o /tmp/yaam-clublog-regression
import Foundation
import WebKit

struct QSLServiceCredentials {}
@MainActor enum ClubLogSessionStore {
    static func savedCookieHeader() -> String { "" }
    static func restoreToWebKit(completion: (() -> Void)? = nil) { completion?() }
}
enum QRZWebKitSession { static let userAgent = "YAAM regression" }

@main struct ClubLogPersonalSpotsRegression {
    static func main() throws {
        // Reconstructed from the authenticated page observed on 19 October 2026.
        // Multiple band tables and absent/empty comments are intentional.
        let html = """
        <h2>DX Spots for Needed DXCCs</h2>
        <h3>160M</h3><table><tr>
          <td>NA6JD</td><td>1840.0</td><td>NV1U/HR9</td>
          <td><a href='mostwanted2.php?dxcc=80'>HONDURAS</a></td>
          <td>2026-10-19 03:06</td><td><a href='propagation.php?formdest=80'>Prop.</a></td>
        </tr></table>
        <h3>80M</h3><table><tr>
          <td>DL1RWN</td><td>3573.6</td><td>W9HT/VP9</td><td>ft8 -14</td>
          <td><a href='mostwanted2.php?dxcc=64'>BERMUDA</a></td>
          <td>2026-10-19 03:52</td><td><a href='propagation.php?formdest=64'>Prop.</a></td>
        </tr></table>
        <h3>17M</h3><table><tr>
          <td>EA8DOX</td><td>18072.0</td><td>H49A</td><td>cqing qsx up1</td>
          <td><a href='mostwanted2.php?dxcc=185'>SOLOMON ISLANDS</a><br><small><font>Most-Wanted #84</font></small></td>
          <td>2026-10-19 03:43</td><td>Prop.</td>
        </tr></table>
        <h3>6M</h3><table><tr>
          <td>PY2MR</td><td>50313.0</td><td>TG9AJR</td><td>ft8 ek44 &amp; CQ</td>
          <td><a href='mostwanted2.php?dxcc=76'>GUATEMALA</a><small>LoTW</small></td>
          <td>2026-10-19 00:55</td><td>Prop.</td>
        </tr></table>
        """
        let spots = try ClubLogSpotsService.parsePersonalSpotsPage(html)
        precondition(spots.count == 4, "Every band table must be included")
        precondition(spots.map(\.band) == ["160M", "80M", "17M", "6M"])
        precondition(spots[0].comment.isEmpty && spots[0].dxcc == "HONDURAS")
        precondition(spots[0].timeStr == "2026-10-19 03:06" && spots[0].frequency == "1.84")
        precondition(spots[1].mode == "FT8" && spots[1].frequency == "3.5736")
        precondition(spots[2].mode == "CW" && spots[2].status == "Most-Wanted #84")
        precondition(spots[3].status == "LoTW" && spots[3].comment == "ft8 ek44 & CQ")
        precondition(spots[3].isDigital && !spots[3].isVoice)
        let legacy = html.replacingOccurrences(of: "<td><a href='mostwanted2.php?dxcc=80'>", with: "<td>&nbsp;</td><td><a href='mostwanted2.php?dxcc=80'>")
        let legacySpots = try ClubLogSpotsService.parsePersonalSpotsPage(legacy)
        precondition(legacySpots.count == 4)
        let bogus = "<table><tr><td>Report</td><td>1840</td><td>Summary</td><td>text</td><td>other</td><td>now</td></tr></table>"
        precondition(ClubLogSpotsService.parsePersonalSpotsHTML(bogus).isEmpty)
        for frequency in ["nan", "inf", "-1840", "1840junk"] {
            precondition(ClubLogSpotsService.parsePersonalSpotsHTML(html.replacingOccurrences(of: "1840.0", with: frequency)).count == 3)
        }
        precondition(ClubLogSpotsService.parsePersonalSpotsHTML(html.replacingOccurrences(of: "2026-10-19 03:06", with: "Prop.")).count == 3)
        do {
            _ = try ClubLogSpotsService.parsePersonalSpotsPage("<form id='clublogform'><input type='password'></form>" + html)
            preconditionFailure("A login page must never publish cached table rows")
        } catch ClubLogSpotsPageError.loginRequired {}
        for page in ["<h2>DX Spots for Needed DXCCs</h2><p>Loading...</p>", "Service unavailable", bogus] {
            do { _ = try ClubLogSpotsService.parsePersonalSpotsPage(page); preconditionFailure("Unexpected page accepted") }
            catch ClubLogSpotsPageError.unrecognized {}
        }
        let empty = try ClubLogSpotsService.parsePersonalSpotsPage("<h2>DX Spots for Needed DXCCs</h2><p>No spots found.</p>")
        precondition(empty.isEmpty)
        print("Club Log Personal Spots regression passed: all bands, optional comments, legacy rows, status, time, frequency, login, empty and unexpected pages.")
    }
}
