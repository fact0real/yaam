import Foundation
@testable import YAAM

@main
struct DXpeditionSourceRegression {
    static func main() {
        test425CalendarParsing()
        test425BulletinParsing()
        test425BulletinLinkParsing()
        testDXWorldFeedParsing()
        testDXWorldBulletinParsing()
        testDXWorldBulletinLinkParsing()
        testNG3KParsing()
        testGenericRSSParsing()
        print("DXpedition source regression tests passed.")
    }

    private static func test425BulletinParsing() {
        let text = """
        15 August 2026 A.R.I. DX Bulletin
        No 1841
        3B - Alex, SQ9UM will be active as 3B8/SQ9UM from Mauritius (AF-049) on
        14-17 August, and as 3B9/SQ9UM from Rodrigues (AF-017) on 18-20 August.
        9M - Active from East Malaysia will be 9M26MS (Sabah) and 9M26MQ (Sarawak).
        CE0Z - Moises, CE3VTZ and Felipe, XQ7IR will be active as XR0Z from
        Alexander Selkirk Island (SA-101) for approximately 10 days in October.
        F - Fabien, F4GYM will be active as F4GYM/p from Ile du Pilier (EU-064)
        on 19-22 August. He will operate FT8 and FT4.
        A4 - Special event station A43KD will be active on 26-28 August from
        Dhofar Governorate (WWL LK77FA). See https://www.qrz.com/db/A43KD.
        G - James, M0GQC will be active as GB100TL from Lundy Island (EU-120)
        on 28-30 August.
        J3 - Graham, MM8IJU and Eric, GM5RDX will be active again as J38LD and
        J38DX, respectively, from Grenada (NA-024) on 1-12 September.
        SP - Special callsigns 3Z100PKP, HF100PKP, SN100PKP, SO100PKP,
        SP100PKP, and SQ100PKP will be active on 1-30 September.
        V5 - Gunter, DK2WH will be active again as V51WH and V55Y from Namibia
        between 25 August and 10 October.
        **** GOOD TO KNOW ... ****
        VP0SG 2027 ---> This planning note must not become a current operation.
        """
        let referenceDate = ISO8601DateFormatter().date(from: "2026-08-15T00:00:00Z")!
        let entries = DXpeditionService.parse425Bulletin(
            text,
            bulletin: "1841",
            sourceURLs: ["https://www.425dxn.org/wbullpdf.php?op=wbullpdf&query=1841"],
            referenceDate: referenceDate
        )
        let byCall = Dictionary(uniqueKeysWithValues: entries.map { ($0.callsign, $0) })

        precondition(byCall["3B8/SQ9UM"]?.entity == "Mauritius (AF-049)")
        precondition(byCall["3B9/SQ9UM"]?.entity == "Rodrigues (AF-017)")
        precondition(byCall["9M26MS"]?.entity == "Sabah")
        precondition(byCall["XR0Z"]?.entity == "Alexander Selkirk Island (SA-101)")
        precondition(byCall["F4GYM/P"]?.start == "2026 Aug19")
        precondition(byCall["F4GYM/P"]?.end == "2026 Aug22")
        precondition(byCall["V51WH"]?.end == "2026 Oct10")
        precondition(byCall["V55Y"]?.bulletin == "1841")
        precondition(byCall["A43KD"] != nil)
        precondition(byCall["GB100TL"] != nil)
        precondition(byCall["J38LD"] != nil)
        precondition(byCall["J38DX"] != nil)
        precondition(byCall["3Z100PKP"] != nil)
        precondition(byCall["SQ100PKP"] != nil)
        precondition(byCall["F4GYM/P"]?.modes?.contains("FT8") == true)
        precondition(byCall["F4GYM/P"]?.modes?.contains("FT4") == true)
        precondition(byCall["F4GYM/P"]?.iota == "EU-064")
        precondition(byCall["3B8/SQ9UM"]?.iota == "AF-049")
        precondition(byCall["3B9/SQ9UM"]?.iota == "AF-017")
        precondition(byCall["XR0Z"]?.iota == "SA-101")
        precondition(byCall["XR0Z"]?.operators?.contains(where: { $0.contains("CE3VTZ") }) == true)
        precondition(byCall["XR0Z"]?.operators?.contains(where: { $0.contains("XQ7IR") }) == true)
        precondition(byCall["A43KD"]?.grid == "LK77FA")
        precondition(byCall["FT8"] == nil)
        precondition(byCall["AF016"] == nil)
        precondition(byCall["ZS6AJG"] == nil)
        precondition(byCall["LK77FA"] == nil)
        precondition(byCall["COM/DB/A43KD"] == nil)
        precondition(byCall["M0GQC"] == nil)
        precondition(byCall["GM5RDX"] == nil)
        precondition(byCall["VP0SG"] == nil)
    }

    private static func test425BulletinLinkParsing() {
        let pageURL = URL(string: "https://www.425dxn.org/index.php?op=wbull")!
        let html = """
        <a href="wbullpdf.php?op=wbullpdf&amp;query=1841">425-1841.pdf</a>
        <a href="/wbullpdf.php?op=wbullpdf&amp;query=1842">425-1842.pdf</a>
        """
        let result = DXpeditionService.latest425Bulletin(in: html, relativeTo: pageURL)
        precondition(result?.issue == "1842")
        precondition(result?.url.absoluteString == "https://www.425dxn.org/wbullpdf.php?op=wbullpdf&query=1842")
    }

    private static func test425CalendarParsing() {
        let html = """
        <table>
          <tr>
            <td>22/08-31/08</td>
            <td><b>CY9C: St Paul Island (NA-094)</b><code>CY9C will be active on 22-31 August 2026. QSL via LoTW.</code></td>
            <td>1842</td>
          </tr>
        </table>
        """
        let referenceDate = ISO8601DateFormatter().date(from: "2026-08-22T00:00:00Z")!
        let entries = DXpeditionService.parse425Calendar(html, referenceDate: referenceDate)

        precondition(entries.count == 1)
        let entry = entries[0]
        precondition(entry.callsign == "CY9C")
        precondition(entry.entity == "St Paul Island (NA-094)")
        precondition(entry.start == "2026 Aug22")
        precondition(entry.end == "2026 Aug31")
        precondition(entry.bulletin == "1842")
        precondition(entry.iota == "NA-094")
        precondition(entry.qslInfo?.contains("LoTW") == true)
        precondition(entry.sources == ["425 DX News"])
        precondition(entry.sourceURLs.contains("https://www.425dxn.org/index.php?op=wcal"))
    }

    private static func testDXWorldFeedParsing() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <item>
              <title><![CDATA[CY9C - St Paul Island]]></title>
              <link>https://www.dx-world.net/cy9c-st-paul-island/</link>
              <pubDate>Fri, 21 Aug 2026 12:00:00 +0000</pubDate>
              <description><![CDATA[The team will be active August 22-31, 2026.]]></description>
            </item>
            <item>
              <title><![CDATA[DX-World Weekly Bulletin #181]]></title>
              <link>https://www.dx-world.net/dx-world-weekly-bulletin-181/</link>
              <pubDate>Fri, 21 Aug 2026 10:00:00 +0000</pubDate>
              <description><![CDATA[Issue #181]]></description>
            </item>
          </channel>
        </rss>
        """
        let parsed = DXpeditionService.parseDXWorldFeed(Data(xml.utf8))

        precondition(parsed.entries.count == 1)
        let entry = parsed.entries[0]
        precondition(entry.callsign == "CY9C")
        precondition(entry.entity == "St Paul Island")
        precondition(entry.start == "2026 Aug22")
        precondition(entry.end == "2026 Aug31")
        precondition(entry.sources == ["DX-World"])
        precondition(entry.primarySourceURL?.absoluteString == "https://www.dx-world.net/cy9c-st-paul-island/")
        precondition(parsed.bulletin == "DX-World weekly #181")
        precondition(parsed.bulletinPageURL == "https://www.dx-world.net/dx-world-weekly-bulletin-181/")
        precondition(!parsed.newsArticles.isEmpty)
        precondition(parsed.newsArticles.first?.title.contains("CY9C") == true)
    }

    private static func testDXWorldBulletinParsing() {
        let text = """
        DX-World Weekly Bulletin #181

        A5, BHUTAN Feng BA7LVG and Taka KJ2XXK are active as A50QO until August 25.
        Activity is on the HF bands. QSL via LoTW.

        C6, BAHAMAS Philippe, EA4NF is active as C6AUB during August 22-31.
        He operates on 6 metres.

        OJ0, MARKET REEF Henri OJ0JR and Anne OJ0YL are active until August 24.
        QSL via their home calls.

        J3, GRENADA Graham is active as J38DX and as J38LD from September 1 until September 12.
        """
        let referenceDate = ISO8601DateFormatter().date(from: "2026-08-22T00:00:00Z")!
        let entries = DXpeditionService.parseDXWorldBulletin(
            text,
            bulletin: "181",
            sourceURLs: ["https://www.dx-world.net/wp-content/uploads/2026/08/DX_181.pdf"],
            referenceDate: referenceDate
        )
        let byCall = Dictionary(uniqueKeysWithValues: entries.map { ($0.callsign, $0) })

        precondition(byCall["A50QO"]?.entity == "BHUTAN")
        precondition(byCall["A50QO"]?.start == "")
        precondition(byCall["A50QO"]?.end == "2026 Aug25")
        precondition(byCall["A50QO"]?.qslInfo?.contains("LoTW") == true)
        precondition(byCall["C6AUB"]?.start == "2026 Aug22")
        precondition(byCall["C6AUB"]?.end == "2026 Aug31")
        precondition(byCall["C6AUB"]?.bands?.contains("6m") == true)
        precondition(byCall["OJ0JR"]?.end == "2026 Aug24")
        precondition(byCall["OJ0YL"]?.end == "2026 Aug24")
        precondition(byCall["J38DX"]?.start == "2026 Sep01")
        precondition(byCall["J38LD"]?.end == "2026 Sep12")
        precondition(byCall["A50QO"]?.sources == ["DX-World Weekly"])
        precondition(byCall["A50QO"]?.bulletin == "181")
    }

    private static func testDXWorldBulletinLinkParsing() {
        let pageURL = URL(string: "https://www.dx-world.net/dx-world-weekly-bulletin-181/")!
        let html = """
        <a href="/wp-content/uploads/2026/08/DX_181.pdf?download=1">Download the bulletin</a>
        """
        let result = DXpeditionService.dxWorldBulletinPDFURL(in: html, relativeTo: pageURL)
        precondition(result?.absoluteString == "https://www.dx-world.net/wp-content/uploads/2026/08/DX_181.pdf?download=1")
    }

    private static func testNG3KParsing() {
        let html = """
        <tr class="adxoitem" bgcolor="#FFDAB9"><td class="date">2026 Sep01</td><td class="date">2026 Sep19</td><td class="cty">Nepal</td><td><span class="call">9N</span><br><span class="spots"> <a href="http://www.dxwatch.com/dxsd1.php?f=0&amp;t=dx&amp;c=9N/OM0GA">[spots]</a></span></td><td class="qsl">LoTW</td><td class="rep"><a href="http://www.dailydx.com">TDDX</a><br>20260902</td><td class="info">By OM0GA as 9N/OM0GA fm Kirtipur; 40-10m; QSL via Club Log OQRS</td></tr>
        <tr class="adxoitem" bgcolor="#FFDAB9"><td class="date">2026 Sep04</td><td class="date">2026 Sep11</td><td class="cty">Vietnam</td><td><span class="call"><a href="https://www.qrz.com/db/3W9C">3W9C</a></span><br><span class="spots"><a href="http://www.dxwatch.com/dxsd1.php?f=0&amp;t=dx&amp;c=3W9C">[spots]</a></span></td><td class="qsl">LoTW</td><td class="rep"><a href="http://dx-world.net/">DXW.Net</a><br>20260728</td><td class="info">By SP5APW fm Hon Son I (IOTA AS-128); focus on 6m, some 20 15 10m; 100w; VDA; QSL via Club Log OQRS or SP5APW</td></tr>
        """
        let entries = DXpeditionService.parseNG3K(html)
        let byCall = Dictionary(uniqueKeysWithValues: entries.map { ($0.callsign, $0) })

        precondition(byCall["9N/OM0GA"] != nil, "9N/OM0GA should be parsed from spot link / info")
        precondition(byCall["9N/OM0GA"]?.entity == "Nepal")
        precondition(byCall["9N/OM0GA"]?.start == "2026 Sep01")
        precondition(byCall["9N/OM0GA"]?.end == "2026 Sep19")
        precondition(byCall["9N/OM0GA"]?.sources.contains("NG3K") == true)
        precondition(byCall["9N/OM0GA"]?.qslInfo?.contains("LoTW") == true)
        precondition(byCall["9N/OM0GA"]?.bands?.contains("40m") == true)

        precondition(byCall["3W9C"] != nil, "3W9C should be parsed")
        precondition(byCall["3W9C"]?.entity == "Vietnam")
        precondition(byCall["3W9C"]?.iota == "AS-128")
        precondition(byCall["3W9C"]?.bands?.contains("6m") == true)
    }

    private static func testGenericRSSParsing() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <item>
              <title>Amateur Radio Supports Relief Operations</title>
              <link>http://www.arrl.org/news/view/amateur-radio-supports-relief</link>
              <pubDate>Mon, 10 Aug 2026 09:52:00 -0500</pubDate>
              <description>&lt;p&gt;Hams operated on 20m and 40m FT8 to provide emergency communications.&lt;/p&gt;</description>
            </item>
            <item>
              <title>Newsline Report 2549</title>
              <link>https://www.arnewsline.org/news/2026/9/4/report</link>
              <pubDate>Fri, 04 Sep 2026 16:41:03 +0000</pubDate>
              <description>&lt;p&gt;&lt;a href="https://www.arnewsline.org/s/report2549.mp3"&gt;AUDIO&lt;/a&gt;&lt;/p&gt;</description>
            </item>
          </channel>
        </rss>
        """
        let articles = DXpeditionService.parseRSSFeed(Data(xml.utf8), defaultSource: "ARRL News", defaultCategory: "ARRL News")
        precondition(articles.count == 2)
        precondition(articles[0].source == "ARRL News")
        precondition(articles[0].title.contains("Relief Operations"))
        precondition(articles[0].bands.contains("20m"))
        precondition(articles[0].modes.contains("FT8"))
        precondition(articles[1].audioURL == "https://www.arnewsline.org/s/report2549.mp3")
    }
}
