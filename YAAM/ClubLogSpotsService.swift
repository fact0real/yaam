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
    let reportedAt: Date?
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
        self.reportedAt = Self.reportDate(timeStr, relativeTo: Date())
        self.dxcc = dxcc
        self.spotter = spotter
        self.comment = comment
        self.status = status
    }

    var isDigital: Bool {
        let m = mode.uppercased()
        let c = comment.uppercased()
        return m == "FT8" || m == "FT4" || m == "RTTY" || m == "PSK" || m == "PSK31" || m == "JS8" || m == "DATA" || m == "DIGI" || m == "Q65" || m == "MSK144" || m.contains("FT") || c.contains("FT8") || c.contains("FT4") || c.contains("RTTY") || c.contains("PSK")
    }

    static func reportDate(_ text: String, relativeTo reference: Date) -> Date? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "Z", with: "")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.isLenient = false
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd HH:mm", "HH:mm:ss", "HH:mm", "HHmm"] {
            formatter.dateFormat = format
            guard let parsed = formatter.date(from: raw) else { continue }
            if format.contains("yyyy") { return parsed }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let clock = calendar.dateComponents([.hour, .minute, .second], from: parsed)
            guard var result = calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: clock.second ?? 0, of: reference) else { return nil }
            if result.timeIntervalSince(reference) > 60 { result = result.addingTimeInterval(-86_400) }
            return result
        }
        return nil
    }

    var localTimeStr: String {
        let trimmed = timeStr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy/MM/dd HH:mm",
            "HH:mm:ss",
            "HH:mm",
            "HHmm"
        ]

        let utcFormatter = DateFormatter()
        utcFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        utcFormatter.locale = Locale(identifier: "en_US_POSIX")

        var parsedDate: Date?
        var hadDate = false

        for format in formats {
            utcFormatter.dateFormat = format
            if let d = utcFormatter.date(from: trimmed) {
                parsedDate = d
                hadDate = format.contains("yyyy")
                break
            }
        }

        guard let date = parsedDate else { return trimmed }

        let localFormatter = DateFormatter()
        localFormatter.timeZone = TimeZone.current
        localFormatter.locale = Locale.current

        if hadDate {
            localFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        } else {
            localFormatter.dateFormat = "HH:mm"
        }
        return localFormatter.string(from: date)
    }

    var isVoice: Bool {
        let m = mode.uppercased()
        let c = comment.uppercased()
        return m == "SSB" || m == "USB" || m == "LSB" || m == "AM" || m == "FM" || m == "PHONE" || c.contains("SSB") || c.contains("USB") || c.contains("LSB") || c.contains("PHONE")
    }

    var isCW: Bool {
        let m = mode.uppercased()
        let c = comment.uppercased()
        return m == "CW" || c.contains("CW") || c.contains("CWT")
    }
}

@MainActor
final class ClubLogSpotsService: ObservableObject {
    @Published var spots: [ClubLogSpotModel] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var lastRefreshed: Date? = nil

    private var activeFetcher: ClubLogSpotsFetcher?

    // Both transports use the same parser: the page now has a table for each band.
    func fetchPersonalSpots(credentials: QSLServiceCredentials) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let fetcher = ClubLogSpotsFetcher()
        activeFetcher = fetcher
        let renderedHTML = await fetcher.fetchHTML()
        activeFetcher = nil

        do {
            let html: String
            if let renderedHTML {
                html = renderedHTML
            } else {
                var request = URLRequest(url: URL(string: "https://clublog.org/personal_spots.php")!)
                request.timeoutInterval = 20
                request.setValue(QRZWebKitSession.userAgent, forHTTPHeaderField: "User-Agent")
                let cookieHeader = ClubLogSessionStore.savedCookieHeader()
                if !cookieHeader.isEmpty { request.setValue(cookieHeader, forHTTPHeaderField: "Cookie") }
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw ClubLogSpotsPageError.unrecognized }
                if http.statusCode == 401 { throw ClubLogSpotsPageError.loginRequired }
                guard (200..<300).contains(http.statusCode) else {
                    throw NSError(domain: "ClubLogSpots", code: http.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: "Club Log returned HTTP \(http.statusCode). Please try again later."])
                }
                guard let text = String(data: data, encoding: .utf8) else { throw ClubLogSpotsPageError.unrecognized }
                html = text
            }
            let parsed = try await Task.detached(priority: .userInitiated) {
                try Self.parsePersonalSpotsPage(html)
            }.value
            spots = parsed
            lastRefreshed = Date()
        } catch {
            // Keep the last good snapshot and its timestamp when refresh fails.
            errorMessage = error.localizedDescription
        }
    }

    nonisolated static func parsePersonalSpotsPage(_ html: String) throws -> [ClubLogSpotModel] {
        if html.range(of: #"(?is)<input\b[^>]*type\s*=\s*["']?password\b|<form\b[^>]*(?:loginform|clublogform)"#,
                      options: .regularExpression) != nil {
            throw ClubLogSpotsPageError.loginRequired
        }
        let result = parsePersonalSpotsHTML(html)
        if !result.isEmpty { return result }
        let text = plainText(html).lowercased()
        // A heading alone is not evidence of an empty search; a changed layout must be visible.
        if text.contains("dx spots for needed dxccs") &&
            ["no spots", "no matching spots", "no dx spots"].contains(where: { text.contains($0) }) {
            return []
        }
        throw ClubLogSpotsPageError.unrecognized
    }

    nonisolated private static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "(?is)<(?:script|style)\\b[^>]*>.*?</(?:script|style)>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&#160;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&amp;": "&"]
        for key in entities.keys.sorted() where key != "&amp;" { text = text.replacingOccurrences(of: key, with: entities[key]!) }
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
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
            let cleanCells = rawCells.map(plainText)
            // Anchor the entity to Club Log's DXCC link, rather than assuming a comment cell.
            // Current rows may omit the comment; legacy rows have an empty fourth cell.
            guard let entityIndex = rawCells.indices.first(where: {
                rawCells[$0].range(of: #"(?is)<a\b[^>]*href\s*=\s*["'][^"']*mostwanted2?\.php\?[^"']*dxcc="#,
                                  options: .regularExpression) != nil
            }), entityIndex == 3 || entityIndex == 4, cleanCells.indices.contains(entityIndex + 1) else { continue }

            let spotter = cleanCells[0].uppercased()
            guard let freqKHz = Double(cleanCells[1]), freqKHz.isFinite, freqKHz > 0 else { continue }
            let call = cleanCells[2].uppercased()
            guard call.range(of: #"^[A-Z0-9/]{2,16}$"#, options: .regularExpression) != nil,
                  call.contains(where: { $0.isLetter }), call.contains(where: { $0.isNumber }) else { continue }
            let comment = entityIndex == 4 ? cleanCells[3] : ""
            let entityHTML = rawCells[entityIndex]
            guard let linkRange = entityHTML.range(of: "(?is)<a[^>]*>.*?</a>", options: .regularExpression) else { continue }
            let dxcc = plainText(String(entityHTML[linkRange]))
            var status = "Needed"
            if let smallRange = entityHTML.range(of: "(?is)<small[^>]*>.*?</small>", options: .regularExpression) {
                let value = plainText(String(entityHTML[smallRange]))
                if !value.isEmpty { status = value }
            }
            let timeStr = cleanCells[entityIndex + 1]
            guard ClubLogSpotModel.reportDate(timeStr, relativeTo: Date()) != nil else { continue }

            // Band from Frequency
            let band = bandFromFrequencyKHz(freqKHz)

            // Mode detection
            let mode = detectMode(comment: comment, freqKHz: freqKHz, band: band)

            // Formatted frequency in MHz
            let mhz = freqKHz / 1000.0
            let freqFormatted = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), mhz).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)

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
        guard khz.isFinite, khz > 0 else { return "" }
        let normKHz: Double
        if khz >= 1_000_000 {
            normKHz = khz / 1000.0
        } else if khz < 1000.0 {
            normKHz = khz * 1000.0
        } else {
            normKHz = khz
        }

        switch normKHz {
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
        case 70000...70500: return "4M"
        case 144000...148000: return "2M"
        case 222000...225000: return "1.25M"
        case 430000...450000: return "70CM"
        case 1240000...1300000: return "23CM"
        default:
            return ""
        }
    }

    nonisolated static func detectMode(comment: String, freqKHz: Double, band: String) -> String {
        let cLower = comment.lowercased()

        // 1. Explicit comment mode keywords take top priority
        if cLower.contains("ft8") {
            return "FT8"
        } else if cLower.contains("ft4") {
            return "FT4"
        } else if cLower.contains("rtty") {
            return "RTTY"
        } else if cLower.contains("psk") {
            return "PSK"
        } else if cLower.contains("js8") {
            return "JS8"
        } else if cLower.contains("cw") || cLower.contains("cwt") || cLower.contains("qsx") || cLower.contains("up ") || cLower.hasPrefix("up") || cLower.contains(" up") {
            return "CW"
        } else if cLower.contains("usb") {
            return "USB"
        } else if cLower.contains("lsb") {
            return "LSB"
        } else if cLower.contains("ssb") || cLower.contains("pota") || cLower.contains("phone") {
            return "SSB"
        }

        // 2. Standard Digital Frequency Detection
        let ft8Freqs = [1840.0, 3573.0, 5357.0, 7074.0, 7056.0, 10131.0, 10136.0, 14074.0, 18100.0, 21074.0, 24915.0, 28074.0, 50313.0]
        let ft4Freqs = [3575.0, 7047.5, 10140.0, 14080.0, 18104.0, 21140.0, 24919.0, 28180.0, 50318.0]

        if ft8Freqs.contains(where: { abs(freqKHz - $0) < 1.5 }) {
            return "FT8"
        } else if ft4Freqs.contains(where: { abs(freqKHz - $0) < 1.5 }) {
            return "FT4"
        }

        // 3. Band Frequency Phone / Voice Segments
        if band == "20M" && freqKHz >= 14100 {
            return "SSB"
        } else if band == "15M" && freqKHz >= 21200 {
            return "SSB"
        } else if band == "40M" && freqKHz >= 7100 {
            return "SSB"
        } else if band == "80M" && freqKHz >= 3600 {
            return "SSB"
        } else if band == "10M" && freqKHz >= 28300 {
            return "SSB"
        }

        return "CW"
    }
}

nonisolated enum ClubLogSpotsPageError: LocalizedError {
    case loginRequired, unrecognized

    var errorDescription: String? {
        switch self {
        case .loginRequired:
            return "Club Log sign-in is required. Please click '2FA Authenticator' to sign in again."
        case .unrecognized:
            return "Club Log returned an unrecognized spots page. Please try again or check the page in your browser."
        }
    }
}

// MARK: - Background WebKit Spots Fetcher
@MainActor
final class ClubLogSpotsFetcher: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String?, Never>?
    private var timeoutTask: Task<Void, Never>?

    func fetchHTML() async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
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

        // Capture every band table and classify the rendered page with the HTTP parser.
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
            self?.finish(with: result as? String)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: nil)
    }

    private func finish(with html: String?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        let cont = continuation
        continuation = nil
        cont?.resume(returning: html)
    }
}
