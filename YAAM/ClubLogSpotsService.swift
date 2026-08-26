//
//  ClubLogSpotsService.swift
//  YAAM
//

import Foundation
import Combine
import WebKit

nonisolated struct ClubLogSpotModel: Identifiable, Sendable {
    let id: UUID
    let callsign: String
    let frequency: String
    let band: String
    let mode: String
    let timeStr: String
    let dxcc: String
    let spotter: String
    let comment: String
    let status: String

    init(
        id: UUID = UUID(),
        callsign: String,
        frequency: String,
        band: String,
        mode: String,
        timeStr: String,
        dxcc: String,
        spotter: String,
        comment: String,
        status: String
    ) {
        self.id = id
        self.callsign = callsign
        self.frequency = frequency
        self.band = band
        self.mode = mode
        self.timeStr = timeStr
        self.dxcc = dxcc
        self.spotter = spotter
        self.comment = comment
        self.status = status
    }
}

@MainActor
final class ClubLogSpotsService: ObservableObject {
    @Published var spots: [ClubLogSpotModel] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var lastRefreshed: Date? = nil

    private var activeFetcher: ClubLogSpotsFetcher?

    // JavaScript extractor tailored specifically to Club Log's personal_spots.php table structure
    static let domSpotsExtractorJS: String = """
    (function() {
        var tables = Array.from(document.querySelectorAll('table'));
        var allRows = [];

        for (var t = 0; t < tables.length; t++) {
            var table = tables[t];
            var rows = Array.from(table.querySelectorAll('tr'));
            if (rows.length === 0) continue;

            for (var r = 0; r < rows.length; r++) {
                var cells = Array.from(rows[r].querySelectorAll('td'));
                if (cells.length < 6) continue;

                // Cell 0: Spotter
                var spotter = (cells[0].innerText || '').trim();

                // Cell 1: Frequency in kHz (e.g. 21010.3)
                var freqKHzStr = (cells[1].innerText || '').trim();
                var freqKHz = parseFloat(freqKHzStr);
                if (isNaN(freqKHz) || freqKHz <= 0) continue;

                // Cell 2: DX Callsign
                var call = (cells[2].innerText || '').trim().replace(/^[^A-Z0-9]+|[^A-Z0-9\\/]+$/gi, '').toUpperCase();
                if (!call || call.length > 16 || !/[A-Z]/.test(call)) continue;

                // Cell 3: Comment
                var comment = (cells[3].innerText || '').trim();
                if (comment === '&nbsp;') comment = '';

                // Cell 4: DXCC Entity and Status
                var dxcc = '';
                var aTag = cells[4].querySelector('a');
                if (aTag) {
                    dxcc = (aTag.innerText || '').trim();
                } else {
                    dxcc = (cells[4].innerText || '').trim();
                }

                var status = 'Needed';
                var smallTag = cells[4].querySelector('small');
                if (smallTag) {
                    var sText = (smallTag.innerText || '').trim();
                    if (sText) status = sText;
                }

                // Cell 5: Time (UTC)
                var time = (cells[5].innerText || '').trim();

                // Determine Band from Frequency in kHz
                var band = '';
                if (freqKHz >= 1800 && freqKHz <= 2000) band = '160M';
                else if (freqKHz >= 3500 && freqKHz <= 4000) band = '80M';
                else if (freqKHz >= 5300 && freqKHz <= 5500) band = '60M';
                else if (freqKHz >= 7000 && freqKHz <= 7300) band = '40M';
                else if (freqKHz >= 10100 && freqKHz <= 10150) band = '30M';
                else if (freqKHz >= 14000 && freqKHz <= 14350) band = '20M';
                else if (freqKHz >= 18068 && freqKHz <= 18168) band = '17M';
                else if (freqKHz >= 21000 && freqKHz <= 21450) band = '15M';
                else if (freqKHz >= 24890 && freqKHz <= 24990) band = '12M';
                else if (freqKHz >= 28000 && freqKHz <= 29700) band = '10M';
                else if (freqKHz >= 50000 && freqKHz <= 54000) band = '6M';
                else if (freqKHz >= 144000 && freqKHz <= 148000) band = '2M';
                else if (freqKHz >= 430000 && freqKHz <= 450000) band = '70CM';

                // Determine Mode from Comment or Frequency
                var mode = 'CW';
                var cLower = comment.toLowerCase();
                if (cLower.includes('ft8') || Math.abs(freqKHz - 14074) < 1.0 || Math.abs(freqKHz - 21074) < 1.0 || Math.abs(freqKHz - 7074) < 1.0 || Math.abs(freqKHz - 7056) < 1.0 || Math.abs(freqKHz - 3573) < 1.0 || Math.abs(freqKHz - 10131) < 1.0 || Math.abs(freqKHz - 10136) < 1.0 || Math.abs(freqKHz - 24915) < 1.0 || Math.abs(freqKHz - 28074) < 1.0 || Math.abs(freqKHz - 18100) < 1.0) {
                    mode = 'FT8';
                } else if (cLower.includes('ft4')) {
                    mode = 'FT4';
                } else if (cLower.includes('ssb') || cLower.includes('usb') || cLower.includes('lsb') || cLower.includes('pota')) {
                    mode = 'SSB';
                } else if (cLower.includes('rtty')) {
                    mode = 'RTTY';
                } else if (cLower.includes('cw') || cLower.includes('cwt') || cLower.includes('qsx') || cLower.includes('up')) {
                    mode = 'CW';
                } else if (band === '20M' && freqKHz >= 14100) {
                    mode = 'SSB';
                } else if (band === '15M' && freqKHz >= 21200) {
                    mode = 'SSB';
                } else if (band === '40M' && freqKHz >= 7100) {
                    mode = 'SSB';
                }

                // Format MHz frequency (e.g. 21.0103)
                var freqMHz = (freqKHz / 1000.0).toFixed(4).replace(/\\.?0+$/, '');

                allRows.push({
                    call: call,
                    freq: freqMHz,
                    band: band,
                    mode: mode,
                    time: time,
                    dxcc: dxcc,
                    spotter: spotter,
                    comment: comment,
                    status: status
                });
            }
            if (allRows.length > 0) break;
        }
        return JSON.stringify(allRows);
    })();
    """

    func fetchPersonalSpots(credentials: QSLServiceCredentials) async {
        isLoading = true
        errorMessage = nil

        // 1. WebKit-based background extractor (shares live WebKit cookies)
        let fetcher = ClubLogSpotsFetcher()
        self.activeFetcher = fetcher
        let webKitSpots = await fetcher.fetchSpots()
        self.activeFetcher = nil

        if let webKitSpots = webKitSpots, !webKitSpots.isEmpty {
            self.spots = webKitSpots
            self.lastRefreshed = Date()
            self.errorMessage = nil
            self.isLoading = false
            return
        }

        // 2. Fallback to HTTP URLSession fetch
        do {
            var spotsReq = URLRequest(url: URL(string: "https://clublog.org/personal_spots.php")!)
            spotsReq.httpMethod = "GET"
            spotsReq.setValue(QRZWebKitSession.userAgent, forHTTPHeaderField: "User-Agent")
            let cookieHeader = ClubLogSessionStore.savedCookieHeader()
            if !cookieHeader.isEmpty {
                spotsReq.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }

            let (spotsData, _) = try await URLSession.shared.data(for: spotsReq)
            guard let html = String(data: spotsData, encoding: .utf8) else {
                throw NSError(domain: "ClubLogSpots", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to read response from Club Log"])
            }

            let parsedSpots = Self.parsePersonalSpotsHTML(html)
            if !parsedSpots.isEmpty {
                self.spots = parsedSpots
                self.lastRefreshed = Date()
                self.errorMessage = nil
            } else if html.lowercased().contains("loginform.php") || html.lowercased().contains("login.php") || html.contains("Password") || html.contains("Sign in") {
                self.spots = []
                if !cookieHeader.isEmpty {
                    self.errorMessage = "Club Log session expired. Please click '2FA Authenticator' to sign in."
                } else {
                    self.errorMessage = "Club Log 2FA login required. Please click '2FA Authenticator' above to sign in."
                }
            } else {
                self.spots = []
                self.lastRefreshed = Date()
                self.errorMessage = nil
            }
        } catch {
            self.errorMessage = "Error fetching Club Log spots: \(error.localizedDescription)"
        }

        isLoading = false
    }

    nonisolated static func parseSpotsFromJSON(_ jsonString: String) -> [ClubLogSpotModel] {
        guard let data = jsonString.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return []
        }

        return jsonArray.compactMap { dict -> ClubLogSpotModel? in
            let call = (dict["call"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !call.isEmpty && call.count <= 16 && call.contains(where: { $0.isLetter }) else { return nil }

            let freq = dict["freq"] ?? ""
            let band = (dict["band"] ?? "").uppercased()
            let mode = (dict["mode"] ?? "").uppercased()
            let time = dict["time"] ?? ""
            let dxcc = dict["dxcc"] ?? ""
            let spotter = (dict["spotter"] ?? "").uppercased()
            let comment = dict["comment"] ?? ""
            let status = dict["status"] ?? "Needed"

            return ClubLogSpotModel(
                callsign: call,
                frequency: freq,
                band: band,
                mode: mode,
                timeStr: time,
                dxcc: dxcc,
                spotter: spotter,
                comment: comment,
                status: status
            )
        }
    }

    nonisolated static func parsePersonalSpotsHTML(_ html: String) -> [ClubLogSpotModel] {
        var results: [ClubLogSpotModel] = []

        let rowPattern = "(?is)<tr[^>]*>(.*?)</tr>"
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern) else { return [] }
        let cellRegex = try? NSRegularExpression(pattern: "(?is)<td[^>]*>(.*?)</td>")

        let nsHTML = html as NSString
        let matches = rowRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let rowContent = nsHTML.substring(with: match.range(at: 1))

            guard let cellRegex = cellRegex else { continue }
            let cellMatches = cellRegex.matches(in: rowContent, range: NSRange(location: 0, length: (rowContent as NSString).length))

            // Need at least 6 cells (Club Log row has 7 cells)
            guard cellMatches.count >= 6 else { continue }

            let rawCells = cellMatches.map { (rowContent as NSString).substring(with: $0.range(at: 1)) }
            let cleanCells = rawCells.map {
                $0.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                  .replacingOccurrences(of: "&nbsp;", with: "")
                  .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // Cell 0: Spotter (e.g. AC2PB)
            let spotter = cleanCells[0].uppercased()

            // Cell 1: Freq in kHz (e.g. 21010.3)
            let freqKHzStr = cleanCells[1]
            guard let freqKHz = Double(freqKHzStr), freqKHz > 0 else { continue }

            // Cell 2: DX Callsign (e.g. RI1FJL)
            let rawCall = cleanCells[2].uppercased()
            let call = rawCall.trimmingCharacters(in: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/")).inverted)
            guard !call.isEmpty && call.count <= 16 && call.contains(where: { $0.isLetter }) else { continue }

            // Cell 3: Comment (e.g. cw spasibo gl)
            let comment = cleanCells[3]

            // Cell 4: DXCC Entity & Status
            var dxcc = cleanCells[4]
            if let aRange = rawCells[4].range(of: "(?is)<a[^>]*>(.*?)</a>", options: .regularExpression) {
                let aSnippet = String(rawCells[4][aRange])
                dxcc = aSnippet.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            var status = "Needed"
            if rawCells[4].lowercased().contains("most-wanted") || rawCells[4].lowercased().contains("lotw") {
                if let smallRange = rawCells[4].range(of: "(?is)<small[^>]*>(.*?)</small>", options: .regularExpression) {
                    let smallSnippet = String(rawCells[4][smallRange])
                    let cleanStatus = smallSnippet.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleanStatus.isEmpty {
                        status = cleanStatus
                    }
                }
            }

            // Cell 5: Time (e.g. 2026-08-26 19:48)
            let timeStr = cleanCells[5]

            // Band from Frequency
            let band = bandFromFrequencyKHz(freqKHz)

            // Mode detection
            let mode = detectMode(comment: comment, freqKHz: freqKHz, band: band)

            // Formatted frequency in MHz
            let mhz = freqKHz / 1000.0
            let freqFormatted = String(format: "%.4f", mhz).trimmingCharacters(in: CharacterSet(charactersIn: "0")).trimmingCharacters(in: CharacterSet(charactersIn: "."))

            let spot = ClubLogSpotModel(
                callsign: call,
                frequency: freqFormatted,
                band: band,
                mode: mode,
                timeStr: timeStr,
                dxcc: dxcc,
                spotter: spotter,
                comment: comment,
                status: status
            )
            results.append(spot)
        }

        return results
    }

    nonisolated static func bandFromFrequencyKHz(_ khz: Double) -> String {
        switch khz {
        case 1800...2000: return "160M"
        case 3500...4000: return "80M"
        case 5300...5500: return "60M"
        case 7000...7300: return "40M"
        case 10100...10150: return "30M"
        case 14000...14350: return "20M"
        case 18068...18168: return "17M"
        case 21000...21450: return "15M"
        case 24890...24990: return "12M"
        case 28000...29700: return "10M"
        case 50000...54000: return "6M"
        case 144000...148000: return "2M"
        case 430000...450000: return "70CM"
        default:
            if khz < 1000 {
                return bandFromFrequencyKHz(khz * 1000)
            }
            return ""
        }
    }

    nonisolated static func detectMode(comment: String, freqKHz: Double, band: String) -> String {
        let cLower = comment.lowercased()
        let ft8Freqs = [1840.0, 3573.0, 5357.0, 7074.0, 7056.0, 10131.0, 10136.0, 14074.0, 18100.0, 21074.0, 24915.0, 28074.0, 50313.0]

        if cLower.contains("ft8") || ft8Freqs.contains(where: { abs(freqKHz - $0) < 1.5 }) {
            return "FT8"
        } else if cLower.contains("ft4") {
            return "FT4"
        } else if cLower.contains("ssb") || cLower.contains("usb") || cLower.contains("lsb") || cLower.contains("pota") {
            return "SSB"
        } else if cLower.contains("rtty") {
            return "RTTY"
        } else if cLower.contains("cw") || cLower.contains("cwt") || cLower.contains("qsx") || cLower.contains("up") {
            return "CW"
        } else if band == "20M" && freqKHz >= 14100 {
            return "SSB"
        } else if band == "15M" && freqKHz >= 21200 {
            return "SSB"
        } else if band == "40M" && freqKHz >= 7100 {
            return "SSB"
        }

        return "CW"
    }
}

// MARK: - Background WebKit Spots Fetcher
@MainActor
final class ClubLogSpotsFetcher: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<[ClubLogSpotModel]?, Never>?
    private var timeoutTask: Task<Void, Never>?

    func fetchSpots() async -> [ClubLogSpotModel]? {
        await withCheckedContinuation { cont in
            self.continuation = cont
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            let wv = WKWebView(frame: .zero, configuration: config)
            wv.customUserAgent = QRZWebKitSession.userAgent
            wv.navigationDelegate = self
            self.webView = wv

            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                if !Task.isCancelled {
                    self.finish(with: nil)
                }
            }

            ClubLogSessionStore.restoreToWebKit {
                guard let url = URL(string: "https://clublog.org/personal_spots.php") else {
                    self.finish(with: nil)
                    return
                }
                var req = URLRequest(url: url)
                let header = ClubLogSessionStore.savedCookieHeader()
                if !header.isEmpty {
                    req.setValue(header, forHTTPHeaderField: "Cookie")
                }
                wv.load(req)
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let currentURL = (webView.url?.absoluteString ?? "").lowercased()
        if currentURL.contains("loginform.php") || currentURL.contains("login.php") {
            finish(with: nil)
            return
        }

        let js = ClubLogSpotsService.domSpotsExtractorJS
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self else { return }
            if let jsonString = result as? String, !jsonString.isEmpty && jsonString != "[]" {
                let spots = ClubLogSpotsService.parseSpotsFromJSON(jsonString)
                self.finish(with: spots)
            } else {
                self.finish(with: [])
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: nil)
    }

    private func finish(with spots: [ClubLogSpotModel]?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        let cont = continuation
        continuation = nil
        cont?.resume(returning: spots)
    }
}
