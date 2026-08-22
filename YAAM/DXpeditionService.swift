//
//  DXpeditionService.swift
//  YAAM
//

import Foundation
import PDFKit
import UserNotifications

nonisolated struct DXpeditionEntry: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let callsign: String
    let entity: String
    let start: String
    let end: String
    let sources: [String]
    let sourceURLs: [String]
    let details: String
    let bulletin: String
    let lastReportedAt: Date?

    init(
        id: String,
        callsign: String,
        entity: String,
        start: String,
        end: String,
        sources: [String] = ["DXPing"],
        sourceURLs: [String] = [],
        details: String = "",
        bulletin: String = "",
        lastReportedAt: Date? = nil
    ) {
        self.id = id
        self.callsign = callsign
        self.entity = entity
        self.start = start
        self.end = end
        self.sources = sources
        self.sourceURLs = sourceURLs
        self.details = details
        self.bulletin = bulletin
        self.lastReportedAt = lastReportedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, callsign, entity, start, end, sources, sourceURLs, details, bulletin, lastReportedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        callsign = try container.decode(String.self, forKey: .callsign)
        entity = try container.decode(String.self, forKey: .entity)
        start = try container.decode(String.self, forKey: .start)
        end = try container.decode(String.self, forKey: .end)
        sources = try container.decodeIfPresent([String].self, forKey: .sources) ?? ["DXPing"]
        sourceURLs = try container.decodeIfPresent([String].self, forKey: .sourceURLs) ?? []
        details = try container.decodeIfPresent(String.self, forKey: .details) ?? ""
        bulletin = try container.decodeIfPresent(String.self, forKey: .bulletin) ?? ""
        lastReportedAt = try container.decodeIfPresent(Date.self, forKey: .lastReportedAt)
    }

    var isActive: Bool {
        let today = Calendar.utc.startOfDay(for: Date())
        let startDate = DXpeditionService.date(fromDisplayValue: start)
        let endDate = DXpeditionService.date(fromDisplayValue: end)

        if let startDate, let endDate {
            return today >= startDate && today <= endDate
        }
        if let startDate {
            return Calendar.utc.dateComponents([.day], from: startDate, to: today).day.map { (0...14).contains($0) } ?? false
        }
        if let endDate {
            return today <= endDate
        }
        return false
    }

    var scheduleText: String {
        switch (start.isEmpty, end.isEmpty) {
        case (false, false): return start == end ? start : "\(start) to \(end)"
        case (false, true): return "From \(start)"
        case (true, false): return "Until \(end)"
        case (true, true): return "Schedule not published"
        }
    }

    var sourceSummary: String {
        sources.map { source in
            sources.count == 1 &&
                (source == "425 DX News" || source == "DX-World Weekly") &&
                !bulletin.isEmpty
                ? "\(source) #\(bulletin)"
                : source
        }.joined(separator: " · ")
    }

    var primarySourceURL: URL? {
        sourceURLs.compactMap(URL.init(string:)).first
    }
}

nonisolated struct DXpeditionCache: Codable, Sendable {
    let entries: [DXpeditionEntry]
    let updatedAt: Date
}

nonisolated struct DXpeditionFetchResult: Sendable {
    let entries: [DXpeditionEntry]
    let successfulSources: [String]
    let failedSources: [String]
    let bulletinNotes: [String]
}

private nonisolated struct DXpeditionSourcePayload: Sendable {
    let name: String
    let entries: [DXpeditionEntry]
    let bulletinNote: String
    let error: String?
}

private nonisolated struct DXWorldFeedItem: Sendable {
    let title: String
    let link: String
    let publishedAt: Date?
    let description: String
}

private nonisolated final class DXWorldFeedParser: NSObject, XMLParserDelegate {
    private(set) var items: [DXWorldFeedItem] = []
    private var currentElement = ""
    private var title = ""
    private var link = ""
    private var published = ""
    private var itemDescription = ""
    private var isInsideItem = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName.lowercased()
        if currentElement == "item" {
            isInsideItem = true
            title = ""
            link = ""
            published = ""
            itemDescription = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard isInsideItem else { return }
        switch currentElement {
        case "title": title += string
        case "link": link += string
        case "pubdate": published += string
        case "description": itemDescription += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard isInsideItem, let value = String(data: CDATABlock, encoding: .utf8) else { return }
        switch currentElement {
        case "title": title += value
        case "description": itemDescription += value
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName.lowercased() == "item" {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            items.append(
                DXWorldFeedItem(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    link: link.trimmingCharacters(in: .whitespacesAndNewlines),
                    publishedAt: formatter.date(from: published.trimmingCharacters(in: .whitespacesAndNewlines)),
                    description: itemDescription
                )
            )
            isInsideItem = false
        }
        currentElement = ""
    }
}

private nonisolated extension Calendar {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

nonisolated enum DXpeditionService {
    static let dxpingURL = URL(string: "https://dxping.com/dxpeditions.php")!
    static let fourTwentyFiveCalendarURL = URL(string: "https://www.425dxn.org/index.php?op=wcal")!
    static let fourTwentyFiveBulletinURL = URL(string: "https://www.425dxn.org/index.php?op=wbull")!
    static let dxWorldFeedURL = URL(string: "https://www.dx-world.net/category/dx-news/feed/")!
    static let dxWorldCategoryURL = URL(string: "https://www.dx-world.net/category/dx-news/")!

    static func fetchAll(version: String) async -> DXpeditionFetchResult {
        async let dxping = fetchSource(name: "DXPing", url: dxpingURL, version: version) { data in
            parseDXPing(decodeText(data))
        }
        async let fourTwentyFive = fetch425(version: version)
        async let dxWorld = fetchDXWorld(version: version)

        let payloads = await [dxping, fourTwentyFive, dxWorld]
        let successful = payloads.filter { $0.error == nil }.map(\.name)
        let failed = payloads.compactMap { $0.error == nil ? nil : $0.name }
        let notes = payloads.map(\.bulletinNote).filter { !$0.isEmpty }
        let merged = merge(payloads.flatMap(\.entries)).filter(isRelevant)

        return DXpeditionFetchResult(
            entries: merged,
            successfulSources: successful,
            failedSources: failed,
            bulletinNotes: notes
        )
    }

    static func parseDXPing(_ html: String) -> [DXpeditionEntry] {
        rows(in: html).compactMap { row -> DXpeditionEntry? in
            let cells = textCells(in: row)
            guard cells.count >= 4 else { return nil }
            let call = normalizedCallsign(cells[0])
            guard isPlausibleCallsign(call),
                  date(fromDisplayValue: cells[2]) != nil,
                  date(fromDisplayValue: cells[3]) != nil
            else { return nil }

            return DXpeditionEntry(
                id: stableID(call: call, start: cells[2], end: cells[3]),
                callsign: call,
                entity: cells[1],
                start: cells[2],
                end: cells[3],
                sources: ["DXPing"],
                sourceURLs: [dxpingURL.absoluteString]
            )
        }
    }

    static func parse425Calendar(_ html: String, referenceDate: Date = Date()) -> [DXpeditionEntry] {
        rows(in: html).flatMap { row -> [DXpeditionEntry] in
            let cells = htmlCells(in: row)
            guard cells.count >= 3 else { return [] }

            let period = plainText(cells[0])
            let operationHTML = cells[1]
            let operationTitle = firstCapture(in: operationHTML, pattern: #"(?is)<b[^>]*>(.*?)</b>"#).map(plainText) ?? plainText(operationHTML)
            let details = firstCapture(in: operationHTML, pattern: #"(?is)<code[^>]*>(.*?)</code>"#).map(plainText) ?? ""
            let bulletin = plainText(cells[2]).replacingOccurrences(of: #"[^0-9]"#, with: "", options: .regularExpression)
            guard let separator = operationTitle.firstIndex(of: ":") else { return [] }

            let callsignText = String(operationTitle[..<separator])
            let entity = String(operationTitle[operationTitle.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let callsigns = extractCallsigns(from: callsignText)
            guard !callsigns.isEmpty else { return [] }

            let detailDates = dateRange(in: details, referenceDate: referenceDate)
            let periodDates = parse425Period(period, referenceDate: referenceDate)
            let dates = detailDates.start.isEmpty && detailDates.end.isEmpty ? periodDates : detailDates

            return callsigns.map { call in
                DXpeditionEntry(
                    id: stableID(call: call, start: dates.start, end: dates.end),
                    callsign: call,
                    entity: entity.isEmpty ? "Announced operation" : entity,
                    start: dates.start,
                    end: dates.end,
                    sources: ["425 DX News"],
                    sourceURLs: [fourTwentyFiveCalendarURL.absoluteString, fourTwentyFiveBulletinURL.absoluteString],
                    details: details,
                    bulletin: bulletin
                )
            }
        }
    }

    static func parse425Bulletin(
        _ text: String,
        bulletin: String,
        sourceURLs: [String],
        referenceDate: Date
    ) -> [DXpeditionEntry] {
        var normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{000C}", with: "\n\n")
        if let goodToKnow = normalized.range(of: "**** GOOD TO KNOW", options: .caseInsensitive) {
            normalized = String(normalized[..<goodToKnow.lowerBound])
        }

        var blocks: [(prefix: String, lines: [String])] = []
        var currentPrefix = ""
        var currentLines: [String] = []
        for line in normalized.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let header = fourTwentyFiveOperationHeader(trimmed) {
                if !currentLines.isEmpty {
                    blocks.append((currentPrefix, currentLines))
                }
                currentPrefix = header.prefix
                currentLines = [header.opening]
            } else if !currentLines.isEmpty {
                currentLines.append(trimmed)
            }
        }
        if !currentLines.isEmpty {
            blocks.append((currentPrefix, currentLines))
        }

        var entries: [DXpeditionEntry] = []
        for block in blocks {
            let details = block.lines.joined(separator: " ")
                .replacingOccurrences(of: #"-\s+"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let callsigns = unique(
                bulletinCallsigns(in: details, excludingPrefix: block.prefix) +
                    fourTwentyFiveListedCallsigns(in: details, excludingPrefix: block.prefix)
            )
            guard !callsigns.isEmpty else { continue }

            let dates = dateRange(in: details, referenceDate: referenceDate)
            let storedDetails = String(details.prefix(900))
            entries.append(contentsOf: callsigns.map { call in
                DXpeditionEntry(
                    id: stableID(call: call, start: dates.start, end: dates.end),
                    callsign: call,
                    entity: fourTwentyFiveEntity(for: call, in: details, prefix: block.prefix),
                    start: dates.start,
                    end: dates.end,
                    sources: ["425 DX News"],
                    sourceURLs: sourceURLs,
                    details: storedDetails,
                    bulletin: bulletin,
                    lastReportedAt: referenceDate
                )
            })
        }
        return merge(entries)
    }

    static func latest425Bulletin(in html: String, relativeTo pageURL: URL) -> (url: URL, issue: String)? {
        let pattern = #"(?i)href\s*=\s*[\"']([^\"']*wbullpdf\.php\?[^\"']*query=(\d+)[^\"']*)[\"']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let candidates: [(url: URL, issue: String, issueNumber: Int)] = regex.matches(
            in: html,
            range: NSRange(html.startIndex..., in: html)
        ).compactMap { match -> (url: URL, issue: String, issueNumber: Int)? in
            guard let rawURL = capture(match, 1, in: html),
                  let issue = capture(match, 2, in: html),
                  let issueNumber = Int(issue)
            else { return nil }
            let decodedURL = rawURL
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&#038;", with: "&")
            guard let url = URL(string: decodedURL, relativeTo: pageURL)?.absoluteURL else { return nil }
            return (url: url, issue: issue, issueNumber: issueNumber)
        }
        guard let latest = candidates.max(by: { $0.issueNumber < $1.issueNumber }) else { return nil }
        return (latest.url, latest.issue)
    }

    static func parseDXWorldFeed(_ data: Data) -> (
        entries: [DXpeditionEntry],
        bulletin: String,
        bulletinPageURL: String,
        bulletinPublishedAt: Date?
    ) {
        let delegate = DXWorldFeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return ([], "", "", nil) }

        var bulletin = ""
        var bulletinPageURL = ""
        var bulletinPublishedAt: Date?
        var entries: [DXpeditionEntry] = []
        for item in delegate.items {
            let title = plainText(item.title)
            let description = plainText(item.description)
            if title.localizedCaseInsensitiveContains("Weekly Bulletin") {
                let issue = firstCapture(in: "\(title) \(description)", pattern: #"(?i)(?:issue\s*)?#\s*(\d+)"#) ?? ""
                bulletin = issue.isEmpty ? "DX-World weekly bulletin" : "DX-World weekly #\(issue)"
                bulletinPageURL = item.link
                bulletinPublishedAt = item.publishedAt
                continue
            }

            guard let split = splitOperationTitle(title) else { continue }
            let callsigns = extractCallsigns(from: split.callsigns)
            guard !callsigns.isEmpty else { continue }
            let dates = dateRange(in: description, referenceDate: item.publishedAt ?? Date())

            entries.append(contentsOf: callsigns.map { call in
                DXpeditionEntry(
                    id: stableID(call: call, start: dates.start, end: dates.end),
                    callsign: call,
                    entity: split.entity,
                    start: dates.start,
                    end: dates.end,
                    sources: ["DX-World"],
                    sourceURLs: [item.link.isEmpty ? dxWorldCategoryURL.absoluteString : item.link],
                    details: description,
                    lastReportedAt: item.publishedAt
                )
            })
        }
        return (entries, bulletin, bulletinPageURL, bulletinPublishedAt)
    }

    static func parseDXWorldBulletin(
        _ text: String,
        bulletin: String,
        sourceURLs: [String],
        referenceDate: Date
    ) -> [DXpeditionEntry] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{000C}", with: "\n\n")

        var blocks: [[String]] = []
        var currentBlock: [String] = []
        for line in normalized.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if bulletinOperationHeader(trimmed) != nil {
                if !currentBlock.isEmpty { blocks.append(currentBlock) }
                currentBlock = [trimmed]
            } else if !currentBlock.isEmpty {
                currentBlock.append(trimmed)
            }
        }
        if !currentBlock.isEmpty { blocks.append(currentBlock) }

        var entries: [DXpeditionEntry] = []
        for block in blocks {
            guard let firstLine = block.first,
                  let header = bulletinOperationHeader(firstLine)
            else { continue }

            let details = block.joined(separator: " ")
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let callsigns = bulletinCallsigns(in: details, excludingPrefix: header.prefix)
            guard !callsigns.isEmpty else { continue }
            let dates = dateRange(in: details, referenceDate: referenceDate)
            let storedDetails = String(details.prefix(900))

            entries.append(contentsOf: callsigns.map { call in
                DXpeditionEntry(
                    id: stableID(call: call, start: dates.start, end: dates.end),
                    callsign: call,
                    entity: header.entity,
                    start: dates.start,
                    end: dates.end,
                    sources: ["DX-World Weekly"],
                    sourceURLs: sourceURLs,
                    details: storedDetails,
                    bulletin: bulletin,
                    lastReportedAt: referenceDate
                )
            })
        }
        return merge(entries)
    }

    static func dxWorldBulletinPDFURL(in html: String, relativeTo pageURL: URL) -> URL? {
        guard let rawLink = firstCapture(
            in: html,
            pattern: #"(?i)href\s*=\s*[\"']([^\"']+\.pdf(?:\?[^\"']*)?)[\"']"#
        ) else { return nil }
        let decoded = rawLink
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#038;", with: "&")
        return URL(string: decoded, relativeTo: pageURL)?.absoluteURL
    }

    static func date(fromDisplayValue value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy MMMdd"
        return formatter.date(from: value)
    }

    private static func fetch425(version: String) async -> DXpeditionSourcePayload {
        async let calendarData = optionalData(from: fourTwentyFiveCalendarURL, version: version)
        async let bulletinListData = optionalData(from: fourTwentyFiveBulletinURL, version: version)
        let (calendarResult, bulletinListResult) = await (calendarData, bulletinListData)

        var entries: [DXpeditionEntry] = []
        var issueNumbers: [Int] = []
        if let calendarResult {
            let calendarEntries = parse425Calendar(decodeText(calendarResult))
            entries.append(contentsOf: calendarEntries)
            issueNumbers.append(contentsOf: calendarEntries.compactMap { Int($0.bulletin) })
        }

        if let bulletinListResult,
           let latest = latest425Bulletin(
               in: decodeText(bulletinListResult),
               relativeTo: fourTwentyFiveBulletinURL
           ),
           let pdfData = await optionalData(from: latest.url, version: version),
           let text = pdfText(from: pdfData) {
            let publication = bulletinPublicationDate(in: text) ?? Date()
            entries.append(contentsOf: parse425Bulletin(
                text,
                bulletin: latest.issue,
                sourceURLs: [latest.url.absoluteString, fourTwentyFiveBulletinURL.absoluteString],
                referenceDate: publication
            ))
            if let issue = Int(latest.issue) { issueNumbers.append(issue) }
        }

        guard !entries.isEmpty else {
            return DXpeditionSourcePayload(
                name: "425 DX News",
                entries: [],
                bulletinNote: "",
                error: "No operations parsed"
            )
        }
        let bulletinNote = issueNumbers.max().map { "425 DX News #\($0)" } ?? ""
        return DXpeditionSourcePayload(
            name: "425 DX News",
            entries: merge(entries),
            bulletinNote: bulletinNote,
            error: nil
        )
    }

    private static func fetchDXWorld(version: String) async -> DXpeditionSourcePayload {
        do {
            let data = try await fetchData(from: dxWorldFeedURL, version: version)
            let parsed = parseDXWorldFeed(data)
            var entries = parsed.entries

            if let pageURL = URL(string: parsed.bulletinPageURL) {
                do {
                    let pageData = try await fetchData(from: pageURL, version: version)
                    let pageHTML = decodeText(pageData)
                    if let pdfURL = dxWorldBulletinPDFURL(in: pageHTML, relativeTo: pageURL) {
                        let pdfData = try await fetchData(from: pdfURL, version: version)
                        if let text = pdfText(from: pdfData) {
                            let issue = firstCapture(in: parsed.bulletin, pattern: #"#(\d+)"#) ?? ""
                            let bulletinEntries = parseDXWorldBulletin(
                                text,
                                bulletin: issue,
                                sourceURLs: [pdfURL.absoluteString, pageURL.absoluteString],
                                referenceDate: parsed.bulletinPublishedAt ?? Date()
                            )
                            entries.append(contentsOf: bulletinEntries)
                        }
                    }
                } catch {
                    // Current DX News remains usable when the optional weekly PDF is unavailable.
                }
            }

            guard !entries.isEmpty else {
                return DXpeditionSourcePayload(name: "DX-World", entries: [], bulletinNote: parsed.bulletin, error: "No operations parsed")
            }
            return DXpeditionSourcePayload(name: "DX-World", entries: merge(entries), bulletinNote: parsed.bulletin, error: nil)
        } catch {
            return DXpeditionSourcePayload(name: "DX-World", entries: [], bulletinNote: "", error: error.localizedDescription)
        }
    }

    private static func fetchSource(
        name: String,
        url: URL,
        version: String,
        parser: (Data) -> [DXpeditionEntry]
    ) async -> DXpeditionSourcePayload {
        do {
            let data = try await fetchData(from: url, version: version)
            let entries = parser(data)
            guard !entries.isEmpty else {
                return DXpeditionSourcePayload(name: name, entries: [], bulletinNote: "", error: "No operations parsed")
            }
            let bulletinNote: String
            if name == "425 DX News", let latest = entries.compactMap({ Int($0.bulletin) }).max() {
                bulletinNote = "425 DX News #\(latest)"
            } else {
                bulletinNote = ""
            }
            return DXpeditionSourcePayload(name: name, entries: entries, bulletinNote: bulletinNote, error: nil)
        } catch {
            return DXpeditionSourcePayload(name: name, entries: [], bulletinNote: "", error: error.localizedDescription)
        }
    }

    private static func fetchData(from url: URL, version: String) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("YAAM/\(version) (+https://github.com/fact0real/yaam)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/rss+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func optionalData(from url: URL, version: String) async -> Data? {
        try? await fetchData(from: url, version: version)
    }

    private static func pdfText(from data: Data) -> String? {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else { return nil }
        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n\n")
        return text.isEmpty ? nil : text
    }

    private static func bulletinPublicationDate(in text: String) -> Date? {
        let range = dateRange(in: String(text.prefix(240)), referenceDate: Date())
        return date(fromDisplayValue: range.start)
    }

    private static func merge(_ entries: [DXpeditionEntry]) -> [DXpeditionEntry] {
        var merged: [String: DXpeditionEntry] = [:]

        for entry in entries {
            let key = entry.callsign.uppercased()
            guard let existing = merged[key] else {
                merged[key] = entry
                continue
            }

            let preferred = preferredEntry(existing, entry)
            let alternate = preferred == existing ? entry : existing
            let sources = unique(preferred.sources + alternate.sources)
            let urls = unique(preferred.sourceURLs + alternate.sourceURLs)
            let details = unique([preferred.details, alternate.details].filter { !$0.isEmpty }).joined(separator: " · ")
            let bulletin = preferred.bulletin.isEmpty ? alternate.bulletin : preferred.bulletin
            let reported = [preferred.lastReportedAt, alternate.lastReportedAt].compactMap { $0 }.max()

            merged[key] = DXpeditionEntry(
                id: stableID(call: preferred.callsign, start: preferred.start, end: preferred.end),
                callsign: preferred.callsign,
                entity: preferred.entity.count >= alternate.entity.count ? preferred.entity : alternate.entity,
                start: preferred.start,
                end: preferred.end,
                sources: sources,
                sourceURLs: urls,
                details: details,
                bulletin: bulletin,
                lastReportedAt: reported
            )
        }

        return merged.values.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            let left = date(fromDisplayValue: lhs.start) ?? date(fromDisplayValue: lhs.end) ?? .distantFuture
            let right = date(fromDisplayValue: rhs.start) ?? date(fromDisplayValue: rhs.end) ?? .distantFuture
            if left != right { return left < right }
            return lhs.callsign < rhs.callsign
        }
    }

    private static func preferredEntry(_ first: DXpeditionEntry, _ second: DXpeditionEntry) -> DXpeditionEntry {
        let firstHasDates = !first.start.isEmpty || !first.end.isEmpty
        let secondHasDates = !second.start.isEmpty || !second.end.isEmpty
        if firstHasDates != secondHasDates { return firstHasDates ? first : second }
        if first.isActive != second.isActive { return first.isActive ? first : second }

        let firstDate = date(fromDisplayValue: first.start) ?? date(fromDisplayValue: first.end) ?? .distantFuture
        let secondDate = date(fromDisplayValue: second.start) ?? date(fromDisplayValue: second.end) ?? .distantFuture
        if firstDate != secondDate { return firstDate < secondDate ? first : second }
        return first.details.count >= second.details.count ? first : second
    }

    private static func isRelevant(_ entry: DXpeditionEntry) -> Bool {
        let cutoff = Calendar.utc.date(byAdding: .day, value: -2, to: Calendar.utc.startOfDay(for: Date())) ?? Date()
        if let endDate = date(fromDisplayValue: entry.end) { return endDate >= cutoff }
        if let startDate = date(fromDisplayValue: entry.start) { return startDate >= cutoff }
        if let reported = entry.lastReportedAt {
            return reported >= (Calendar.utc.date(byAdding: .day, value: -90, to: Date()) ?? .distantPast)
        }
        return true
    }

    private static func dateRange(in text: String, referenceDate: Date) -> (start: String, end: String) {
        let normalized = plainText(text)
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
        let month = monthPattern
        let separator = #"(?:-|to|until|through|and)"#

        let patterns: [(String, (NSTextCheckingResult, String) -> (Int, Int, Int, Int, Int?)?)] = [
            (#"(?i)\b(\#(month))\s+(\d{1,2})\s*\#(separator)\s*(\#(month))\s+(\d{1,2})(?:,?\s+(\d{4}))?"#, { match, value in
                guard let m1 = capture(match, 1, in: value).flatMap(monthNumber),
                      let d1 = capture(match, 2, in: value).flatMap(Int.init),
                      let m2 = capture(match, 3, in: value).flatMap(monthNumber),
                      let d2 = capture(match, 4, in: value).flatMap(Int.init)
                else { return nil }
                return (m1, d1, m2, d2, capture(match, 5, in: value).flatMap(Int.init))
            }),
            (#"(?i)\b(\d{1,2})\s+(\#(month))\s*\#(separator)\s*(\d{1,2})\s+(\#(month))(?:,?\s+(\d{4}))?"#, { match, value in
                guard let d1 = capture(match, 1, in: value).flatMap(Int.init),
                      let m1 = capture(match, 2, in: value).flatMap(monthNumber),
                      let d2 = capture(match, 3, in: value).flatMap(Int.init),
                      let m2 = capture(match, 4, in: value).flatMap(monthNumber)
                else { return nil }
                return (m1, d1, m2, d2, capture(match, 5, in: value).flatMap(Int.init))
            }),
            (#"(?i)\b(\#(month))\s+(\d{1,2})\s*\#(separator)\s*(\d{1,2})(?:,?\s+(\d{4}))?"#, { match, value in
                guard let m = capture(match, 1, in: value).flatMap(monthNumber),
                      let d1 = capture(match, 2, in: value).flatMap(Int.init),
                      let d2 = capture(match, 3, in: value).flatMap(Int.init)
                else { return nil }
                return (m, d1, m, d2, capture(match, 4, in: value).flatMap(Int.init))
            }),
            (#"(?i)\b(\d{1,2})\s*\#(separator)\s*(\d{1,2})\s+(\#(month))(?:,?\s+(\d{4}))?"#, { match, value in
                guard let d1 = capture(match, 1, in: value).flatMap(Int.init),
                      let d2 = capture(match, 2, in: value).flatMap(Int.init),
                      let m = capture(match, 3, in: value).flatMap(monthNumber)
                else { return nil }
                return (m, d1, m, d2, capture(match, 4, in: value).flatMap(Int.init))
            })
        ]

        for (pattern, values) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
                  let result = values(match, normalized)
            else { continue }
            return makeRange(month1: result.0, day1: result.1, month2: result.2, day2: result.3, year: result.4, referenceDate: referenceDate)
        }

        let singlePatterns = [
            #"(?i)\b(\#(month))\s+(\d{1,2})(?:,?\s+(\d{4}))?"#,
            #"(?i)\b(\d{1,2})\s+(\#(month))(?:,?\s+(\d{4}))?"#
        ]
        for (index, pattern) in singlePatterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized))
            else { continue }
            let monthValue = capture(match, index == 0 ? 1 : 2, in: normalized).flatMap(monthNumber)
            let dayValue = capture(match, index == 0 ? 2 : 1, in: normalized).flatMap(Int.init)
            let yearValue = capture(match, 3, in: normalized).flatMap(Int.init)
            guard let monthValue, let dayValue else { continue }
            let range = makeRange(
                month1: monthValue,
                day1: dayValue,
                month2: monthValue,
                day2: dayValue,
                year: yearValue,
                referenceDate: referenceDate
            )
            guard let matchedRange = Range(match.range(at: 0), in: normalized) else { return range }
            let leadingContext = String(normalized[..<matchedRange.lowerBound].suffix(40))
            if leadingContext.range(of: #"(?i)(?:until|till|through)\s*$"#, options: .regularExpression) != nil {
                return ("", range.end)
            }
            if leadingContext.range(of: #"(?i)(?:from|starting(?:\s+on)?|beginning(?:\s+on)?)\s*$"#, options: .regularExpression) != nil {
                return (range.start, "")
            }
            return range
        }
        return ("", "")
    }

    private static func parse425Period(_ period: String, referenceDate: Date) -> (start: String, end: String) {
        let pattern = #"(?i)(till\s+)?(\d{1,2})/(\d{1,2})(?:\s*-\s*(\d{1,2})/(\d{1,2}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: period, range: NSRange(period.startIndex..., in: period)),
              let day1 = capture(match, 2, in: period).flatMap(Int.init),
              let month1 = capture(match, 3, in: period).flatMap(Int.init)
        else { return dateRange(in: period, referenceDate: referenceDate) }

        let isUntil = capture(match, 1, in: period) != nil
        let day2 = capture(match, 4, in: period).flatMap(Int.init)
        let month2 = capture(match, 5, in: period).flatMap(Int.init)
        if isUntil {
            let result = makeRange(month1: month1, day1: day1, month2: month1, day2: day1, year: nil, referenceDate: referenceDate)
            return ("", result.end)
        }
        return makeRange(month1: month1, day1: day1, month2: month2 ?? month1, day2: day2 ?? day1, year: nil, referenceDate: referenceDate)
    }

    private static func makeRange(month1: Int, day1: Int, month2: Int, day2: Int, year: Int?, referenceDate: Date) -> (start: String, end: String) {
        let referenceYear = Calendar.utc.component(.year, from: referenceDate)
        var startYear = year ?? referenceYear
        var endYear = startYear
        if month2 < month1 { endYear += 1 }

        guard var startDate = Calendar.utc.date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: startYear, month: month1, day: day1)),
              var endDate = Calendar.utc.date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: endYear, month: month2, day: day2))
        else { return ("", "") }

        if year == nil,
           let threshold = Calendar.utc.date(byAdding: .day, value: -150, to: referenceDate),
           endDate < threshold {
            startYear += 1
            endYear += 1
            startDate = Calendar.utc.date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: startYear, month: month1, day: day1)) ?? startDate
            endDate = Calendar.utc.date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: endYear, month: month2, day: day2)) ?? endDate
        }
        return (displayDate(startDate), displayDate(endDate))
    }

    private static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy MMMdd"
        return formatter.string(from: date)
    }

    private static func splitOperationTitle(_ title: String) -> (callsigns: String, entity: String)? {
        for separator in [" – ", " — ", " - "] {
            if let range = title.range(of: separator) {
                let callsigns = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let entity = String(title[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !callsigns.isEmpty, !entity.isEmpty else { continue }
                return (callsigns, entity)
            }
        }
        return nil
    }

    private static func extractCallsigns(from value: String) -> [String] {
        value
            .uppercased()
            .components(separatedBy: CharacterSet(charactersIn: ",;&+"))
            .flatMap { $0.components(separatedBy: .whitespacesAndNewlines) }
            .map(normalizedCallsign)
            .filter(isPlausibleCallsign)
            .reduce(into: [String]()) { result, call in
                if !result.contains(call) { result.append(call) }
            }
    }

    private static func fourTwentyFiveOperationHeader(_ line: String) -> (prefix: String, opening: String)? {
        let pattern = #"(?i)^([A-Z0-9]{1,8})\s*-\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let prefix = capture(match, 1, in: line),
              let opening = capture(match, 2, in: line)
        else { return nil }
        return (prefix.uppercased(), opening)
    }

    private static func fourTwentyFiveListedCallsigns(in text: String, excludingPrefix prefix: String) -> [String] {
        let clausePatterns = [
            #"(?is)\b(?:special\s+(?:event\s+)?)?callsigns?\s+(.{1,500}?)\s+will\s+be\s+(?:active|activated|used)\b"#,
            #"(?is)\bactive\s+from\s+.{2,120}?\s+will\s+be\s+(.{1,250}?)(?=\.\s|$)"#,
            #"(?is)\b(?:special\s+)?callsigns?[^:]{0,140}:\s*(.{1,500}?)(?=\.\s|$)"#
        ]
        guard let tokenRegex = try? NSRegularExpression(
            pattern: #"(?i)\b[A-Z0-9]+(?:/[A-Z0-9]+)*\b"#
        ) else { return [] }

        var callsigns: [String] = []
        for pattern in clausePatterns {
            guard let clauseRegex = try? NSRegularExpression(pattern: pattern) else { continue }
            for clauseMatch in clauseRegex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let clause = capture(clauseMatch, 1, in: text) else { continue }
                for tokenMatch in tokenRegex.matches(in: clause, range: NSRange(clause.startIndex..., in: clause)) {
                    guard let range = Range(tokenMatch.range(at: 0), in: clause) else { continue }
                    let call = normalizedCallsign(String(clause[range]))
                    guard call != prefix,
                          isPlausibleCallsign(call),
                          !["FT4", "FT8", "MSK144", "RTTY"].contains(call),
                          !callsigns.contains(call)
                    else { continue }
                    callsigns.append(call)
                }
            }
        }
        return callsigns
    }

    private static func fourTwentyFiveEntity(for callsign: String, in text: String, prefix: String) -> String {
        let escapedCall = NSRegularExpression.escapedPattern(for: callsign)
        if let parenthetical = firstCapture(
            in: text,
            pattern: #"(?i)\b\#(escapedCall)\b\s*\(([^)]+)\)"#
        )?.trimmingCharacters(in: .whitespacesAndNewlines),
           !parenthetical.localizedCaseInsensitiveContains("call"),
           parenthetical.range(of: #"^[A-Z]{2}-\d+$"#, options: .regularExpression) == nil {
            return parenthetical
        }

        let callSpecific = #"(?i)\b\#(escapedCall)\b\s+from\s+(.{2,90}?)(?=\s+(?:on|between|during|for|from)\b|[.;])"#
        let generic = #"(?i)\bfrom\s+(.{2,90}?)(?=\s+(?:on|between|during|for|from)\b|[.;])"#
        for pattern in [callSpecific, generic] {
            guard let candidate = firstCapture(in: text, pattern: pattern)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  candidate.first?.isLetter == true
            else { continue }
            return candidate
        }
        return "425 DX News operation (\(prefix))"
    }

    private static func bulletinOperationHeader(_ firstLine: String) -> (prefix: String, entity: String)? {
        guard let comma = firstLine.firstIndex(of: ",") else { return nil }
        let prefix = normalizedCallsign(String(firstLine[..<comma]))
        guard isPlausibleCallsign(prefix), prefix.count <= 8 else { return nil }

        let remainder = firstLine[firstLine.index(after: comma)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let punctuation = CharacterSet(charactersIn: ",:;.")
        var entityParts: [String] = []

        for rawPart in remainder.split(whereSeparator: { $0.isWhitespace }) {
            let part = String(rawPart).trimmingCharacters(in: punctuation)
            guard !part.isEmpty else { continue }
            if !entityParts.isEmpty, isPlausibleCallsign(normalizedCallsign(part)) { break }

            let letters = part.filter { $0.isLetter }
            if letters.isEmpty {
                guard !entityParts.isEmpty else { break }
                entityParts.append(part)
                continue
            }
            guard letters == letters.uppercased() else { break }
            entityParts.append(part)
        }

        let entity = entityParts.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(punctuation))
        guard !entity.isEmpty else { return nil }
        return (prefix, entity)
    }

    private static func bulletinCallsigns(in text: String, excludingPrefix prefix: String) -> [String] {
        let patterns = [
            #"(?i)\bas\s+([A-Z0-9]+(?:/[A-Z0-9]+)*)\s+and\s+(?:as\s+)?([A-Z0-9]+(?:/[A-Z0-9]+)*)\b"#,
            #"(?i)\bas\s+([A-Z0-9]+(?:/[A-Z0-9]+)*)\b"#,
            #"(?i)\blook\s+for\s+([A-Z0-9]+(?:/[A-Z0-9]+)*)\b"#,
            #"(?i)\b(?:call\s*sign|callsign)\s+([A-Z0-9]+(?:/[A-Z0-9]+)*)\b"#,
            #"(?i)\b([A-Z0-9]+(?:/[A-Z0-9]+)*)\s+(?:call\s*sign|callsign)\b"#,
            #"\b([A-Z0-9]+(?:/[A-Z0-9]+)*)\s+and(?:\s+[A-Za-z'-]+,?)?\s+([A-Z0-9]+(?:/[A-Z0-9]+)*)\s+are\s+(?:active|operating)\b"#,
            #"(?i)\b([A-Z0-9]+(?:/[A-Z0-9]+)*)\s+(?:is|are)\s+(?:again\s+)?(?:active|operating)\b(?![^.;]{0,120}\bas\s+[A-Z0-9])"#,
            #"(?i)\b([A-Z0-9]+(?:/[A-Z0-9]+)*)\s+will\s+be\s+(?:used|active|activated)\b(?![^.;]{0,120}\bas\s+[A-Z0-9])"#,
            #"(?i)\b(?:using|under)(?:\s+the)?(?:\s+special)?(?:\s+call\s*sign|\s+callsign)?\s+([A-Z0-9]+(?:/[A-Z0-9]+)*)\b"#,
            #"(?i)\b([A-Z0-9]+(?:/[A-Z0-9]+)*)\s+DXpedition\b"#
        ]

        var callsigns: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                for index in 1..<match.numberOfRanges {
                    guard let raw = capture(match, index, in: text) else { continue }
                    let call = normalizedCallsign(raw)
                    let components = call.split(separator: "/").map(String.init)
                    guard call != prefix,
                          isPlausibleCallsign(call),
                          !components.contains(where: { ["CALL", "HOME"].contains($0) }),
                          !callsigns.contains(call)
                    else { continue }
                    callsigns.append(call)
                }
            }
        }
        return callsigns
    }

    private static func normalizedCallsign(_ value: String) -> String {
        value.uppercased().trimmingCharacters(in: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/")).inverted)
    }

    private static func isPlausibleCallsign(_ value: String) -> Bool {
        guard value.range(
            of: #"^(?=.{2,18}$)(?=.*[A-Z])(?=.*\d)[A-Z0-9]+(?:/[A-Z0-9]+)*$"#,
            options: .regularExpression
        ) != nil else { return false }
        if value.range(of: #"^(?:AF|AN|AS|EU|NA|OC|SA)\d{3}$"#, options: .regularExpression) != nil {
            return false
        }
        if value.range(of: #"^[A-R]{2}\d{2}[A-X]{0,2}$"#, options: .regularExpression) != nil {
            return false
        }
        if value.range(of: #"^(?:WWW|COM|NET|ORG)(?:/|$)"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }

    private static func rows(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<tr[^>]*>(.*?)</tr>"#) else { return [] }
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { match in
            Range(match.range(at: 1), in: html).map { String(html[$0]) }
        }
    }

    private static func htmlCells(in row: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<td[^>]*>(.*?)</td>"#) else { return [] }
        return regex.matches(in: row, range: NSRange(row.startIndex..., in: row)).compactMap { match in
            Range(match.range(at: 1), in: row).map { String(row[$0]) }
        }
    }

    private static func textCells(in row: String) -> [String] {
        htmlCells(in: row).map(plainText)
    }

    private static func plainText(_ value: String) -> String {
        var text = value
        let namedEntities = [
            "&nbsp;": " ", "&#160;": " ", "&amp;": "&", "&#038;": "&",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&ndash;": "–",
            "&mdash;": "—", "&#8211;": "–", "&#8212;": "—", "&#8217;": "'"
        ]
        for (entity, replacement) in namedEntities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: "", options: .regularExpression)
        text = decodeNumericEntities(text)
        return text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeNumericEntities(_ value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else { return value }
        var result = value
        for match in regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).reversed() {
            guard let wholeRange = Range(match.range(at: 0), in: result),
                  let valueRange = Range(match.range(at: 1), in: result)
            else { continue }
            let raw = String(result[valueRange])
            let number = raw.lowercased().hasPrefix("x") ? UInt32(raw.dropFirst(), radix: 16) : UInt32(raw, radix: 10)
            guard let number, let scalar = UnicodeScalar(number) else { continue }
            result.replaceSubrange(wholeRange, with: String(Character(scalar)))
        }
        return result
    }

    private static func firstCapture(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value))
        else { return nil }
        return capture(match, 1, in: value)
    }

    private static func capture(_ match: NSTextCheckingResult, _ index: Int, in value: String) -> String? {
        guard index < match.numberOfRanges, match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: value)
        else { return nil }
        return String(value[range])
    }

    private static var monthPattern: String {
        "Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?"
    }

    private static func monthNumber(_ value: String) -> Int? {
        let prefix = String(value.lowercased().prefix(3))
        return ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"].firstIndex(of: prefix).map { $0 + 1 }
    }

    private static func stableID(call: String, start: String, end: String) -> String {
        "\(call)|\(start)|\(end)"
    }

    private static func unique(_ values: [String]) -> [String] {
        values.reduce(into: [String]()) { result, value in
            if !value.isEmpty && !result.contains(value) { result.append(value) }
        }
    }

    private static func decodeText(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }
}

extension AppState {
    private static let dxpeditionCacheKey = "dxpeditionCache.v2"
    private static let legacyDXpeditionCacheKey = "dxpeditionCache.v1"

    func loadDXpeditionCache() {
        let defaults = UserDefaults.standard
        let data = defaults.data(forKey: Self.dxpeditionCacheKey) ?? defaults.data(forKey: Self.legacyDXpeditionCacheKey)
        guard let data, let cache = try? JSONDecoder().decode(DXpeditionCache.self, from: data) else { return }
        dxpeditionEntries = cache.entries
        dxpeditionLastUpdated = cache.updatedAt
        dxpeditionStatus = "Showing the last saved multi-source DXpedition list."
    }

    func fetchDXpeditions(force: Bool = false) {
        guard !isFetchingDXpeditions else { return }
        if !force, let updated = dxpeditionLastUpdated,
           Date().timeIntervalSince(updated) < 60 * 60 * 3,
           !dxpeditionEntries.isEmpty { return }

        isFetchingDXpeditions = true
        dxpeditionStatus = "Refreshing DX-World, 425 DX News, and DXPing..."
        let version = currentVersion

        Task { [weak self] in
            let result = await DXpeditionService.fetchAll(version: version)
            guard let self else { return }
            self.isFetchingDXpeditions = false

            guard !result.entries.isEmpty else {
                self.dxpeditionStatus = self.dxpeditionEntries.isEmpty
                    ? "The DXpedition sources responded without a usable operation list."
                    : "The sources are temporarily unavailable. Showing the last saved list."
                return
            }

            let now = Date()
            self.dxpeditionEntries = result.entries
            self.dxpeditionLastUpdated = now
            let sourceText = result.successfulSources.joined(separator: ", ")
            let bulletinText = result.bulletinNotes.isEmpty ? "" : " · \(result.bulletinNotes.joined(separator: " · "))"
            let partialText = result.failedSources.isEmpty ? "" : " · Unavailable: \(result.failedSources.joined(separator: ", "))"
            self.dxpeditionStatus = "Loaded \(result.entries.count) operations from \(sourceText)\(bulletinText)\(partialText)."
            self.scheduleDXpeditionOpportunityNotifications()

            if let data = try? JSONEncoder().encode(DXpeditionCache(entries: result.entries, updatedAt: now)) {
                UserDefaults.standard.set(data, forKey: Self.dxpeditionCacheKey)
            }
        }
    }

    func scheduleDXpeditionOpportunityNotifications() {
        guard UserDefaults.standard.bool(forKey: "dxpeditionSpotNotifications") else { return }

        let notified = Set(UserDefaults.standard.stringArray(forKey: "dxpeditionSpotNotificationIDs") ?? [])
        let opportunities = dxpeditionEntries.compactMap { entry -> (DXpeditionEntry, DXSpot)? in
            guard let spot = dxClusterClient.spots.first(where: { $0.callsign.uppercased() == entry.callsign.uppercased() }),
                  !notified.contains(entry.id)
            else { return nil }
            return (entry, spot)
        }
        guard !opportunities.isEmpty else { return }

        for (entry, spot) in opportunities.prefix(3) {
            let content = UNMutableNotificationContent()
            content.title = "DXpedition on air: \(entry.callsign)"
            let frequency = String(format: "%.3f", spot.frequencyMHz)
            content.body = "\(entry.entity) spotted on \(spot.band) at \(frequency) MHz."
            content.sound = .default
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "dxpedition.\(entry.id)", content: content, trigger: nil)
            )
        }
        let rememberedIDs = Array(Array(notified.union(opportunities.map { $0.0.id })).suffix(120))
        UserDefaults.standard.set(rememberedIDs, forKey: "dxpeditionSpotNotificationIDs")
    }
}
