//
//  LogExportEngine.swift
//  YAAM
//
//  Created by YAAM Engine.
//

import Foundation
import UniformTypeIdentifiers

public enum ExportLogFormat: String, CaseIterable, Identifiable, Sendable {
    case excelCSV = "Excel / CSV (.csv)"
    case cabrillo = "Cabrillo 3.0 (.cbr / .log)"
    case adif = "ADIF 3.1.4 (.adi)"
    case json = "JSON Database (.json)"
    case html = "HTML Report (.html)"
    case textSummary = "Text Summary (.txt)"

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .excelCSV: return "csv"
        case .cabrillo: return "log"
        case .adif: return "adi"
        case .json: return "json"
        case .html: return "html"
        case .textSummary: return "txt"
        }
    }

    public var icon: String {
        switch self {
        case .excelCSV: return "tablecells.badge.ellipsis"
        case .cabrillo: return "flag.checkered.circle.fill"
        case .adif: return "doc.text.fill"
        case .json: return "curlybraces"
        case .html: return "safari.fill"
        case .textSummary: return "doc.plaintext"
        }
    }

    public var title: String {
        switch self {
        case .excelCSV: return "Excel / CSV Spreadsheet"
        case .cabrillo: return "Cabrillo 3.0 Contest Log"
        case .adif: return "ADIF 3.1.4 Logbook"
        case .json: return "JSON Database Array"
        case .html: return "Interactive HTML Table Report"
        case .textSummary: return "Text Summary & Matrix"
        }
    }

    public var description: String {
        switch self {
        case .excelCSV:
            return "Formatted spreadsheet with UTF-8 BOM, perfect for Microsoft Excel, Apple Numbers, and Google Sheets."
        case .cabrillo:
            return "Official contest log submission format (Cabrillo 3.0) for CQ WW, ARRL, IARU, and international contests."
        case .adif:
            return "Standard amateur radio interchange format (ADIF 3.1.4) supported by all loggers (LoTW, QRZ, eQSL, Club Log)."
        case .json:
            return "Structured JSON array of QSO objects for developers, web applications, and database backups."
        case .html:
            return "Self-contained interactive HTML page with dark/light styling, station metadata, and QSO statistics."
        case .textSummary:
            return "Clean human-readable ASCII text summary with band and mode breakdown matrix."
        }
    }

    public var utType: UTType {
        switch self {
        case .excelCSV:
            return .commaSeparatedText
        case .cabrillo:
            return UTType(filenameExtension: "log") ?? .plainText
        case .adif:
            return UTType(filenameExtension: "adi") ?? .plainText
        case .json:
            return .json
        case .html:
            return .html
        case .textSummary:
            return .plainText
        }
    }
}

public struct CabrilloExportOptions: Sendable {
    public var contestID: String
    public var callsign: String
    public var categoryOperator: String
    public var categoryPower: String
    public var categoryBand: String
    public var categoryMode: String
    public var categoryAssisted: String
    public var categoryStation: String
    public var categoryTransmitter: String
    public var categoryOverlay: String
    public var claimedScore: Int
    public var operators: String
    public var club: String
    public var soapbox: String
    public var name: String
    public var address: String
    public var country: String

    public init(
        contestID: String = "CQ-WW-SSB",
        callsign: String = "",
        categoryOperator: String = "SINGLE-OP",
        categoryPower: String = "HIGH",
        categoryBand: String = "ALL",
        categoryMode: String = "MIXED",
        categoryAssisted: String = "NON-ASSISTED",
        categoryStation: String = "FIXED",
        categoryTransmitter: String = "ONE",
        categoryOverlay: String = "CLASSIC",
        claimedScore: Int = 0,
        operators: String = "",
        club: String = "",
        soapbox: String = "",
        name: String = "",
        address: String = "",
        country: String = ""
    ) {
        self.contestID = contestID
        self.callsign = callsign
        self.categoryOperator = categoryOperator
        self.categoryPower = categoryPower
        self.categoryBand = categoryBand
        self.categoryMode = categoryMode
        self.categoryAssisted = categoryAssisted
        self.categoryStation = categoryStation
        self.categoryTransmitter = categoryTransmitter
        self.categoryOverlay = categoryOverlay
        self.claimedScore = claimedScore
        self.operators = operators
        self.club = club
        self.soapbox = soapbox
        self.name = name
        self.address = address
        self.country = country
    }
}

public enum LogExportEngine {
    // MARK: - JSON Exporter
    public static func generateJSON(records: [[String: String]]) -> String {
        var cleanRecords: [[String: String]] = []
        for record in records {
            var row: [String: String] = [:]
            for (k, v) in record where !v.isEmpty {
                row[k] = v
            }
            cleanRecords.append(row)
        }

        let payload: [String: Any] = [
            "generator": "YAAM - Yet Another ADIF Manager",
            "version": "2.0",
            "exported_at_utc": ISO8601DateFormatter().string(from: Date()),
            "total_qsos": cleanRecords.count,
            "qsos": cleanRecords
        ]

        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{\n  \"error\": \"Failed to serialize JSON\"\n}\n"
    }

    // MARK: - Cabrillo 3.0 Exporter
    public static func generateCabrillo(records: [[String: String]], options: CabrilloExportOptions) -> String {
        let call = options.callsign.isEmpty ? "NOCALL" : options.callsign.uppercased()
        var lines = [
            "START-OF-LOG: 3.0",
            "CREATED-BY: YAAM - Yet Another ADIF Manager",
            "CALLSIGN: \(call)",
            "CONTEST: \(options.contestID)",
            "CATEGORY-ASSISTED: \(options.categoryAssisted)",
            "CATEGORY-BAND: \(options.categoryBand)",
            "CATEGORY-MODE: \(options.categoryMode)",
            "CATEGORY-OPERATOR: \(options.categoryOperator)",
            "CATEGORY-POWER: \(options.categoryPower)",
            "CATEGORY-STATION: \(options.categoryStation)",
            "CATEGORY-TRANSMITTER: \(options.categoryTransmitter)",
            "CATEGORY-OVERLAY: \(options.categoryOverlay)",
            "CLAIMED-SCORE: \(options.claimedScore)",
            "OPERATORS: \(options.operators.isEmpty ? call : options.operators)"
        ]

        if !options.club.isEmpty { lines.append("CLUB: \(options.club)") }
        if !options.name.isEmpty { lines.append("NAME: \(options.name)") }
        if !options.address.isEmpty { lines.append("ADDRESS: \(options.address)") }
        if !options.country.isEmpty { lines.append("ADDRESS-COUNTRY: \(options.country)") }
        if !options.soapbox.isEmpty { lines.append("SOAPBOX: \(options.soapbox)") }

        for r in records {
            let dateStr = r["QSO_DATE"] ?? ""
            let timeStr = normalizeTime(r["TIME_ON"] ?? "000000")
            let formattedDate = formatDateForCabrillo(dateStr)
            let formattedTime = String(timeStr.prefix(4))

            let freq = cabrilloFrequency(freqStr: r["FREQ"] ?? "", band: r["BAND"] ?? "")
            let mode = cabrilloMode(modeStr: r["MODE"] ?? "SSB")
            let sentRST = r["RST_SENT"]?.isEmpty == false ? r["RST_SENT"]! : "59"
            let rcvdRST = r["RST_RCVD"]?.isEmpty == false ? r["RST_RCVD"]! : "59"
            let sentEx = r["STX_STRING"]?.isEmpty == false ? r["STX_STRING"]! : (r["STX"]?.isEmpty == false ? r["STX"]! : "001")
            let rcvdEx = r["SRX_STRING"]?.isEmpty == false ? r["SRX_STRING"]! : (r["SRX"]?.isEmpty == false ? r["SRX"]! : "001")
            let dxCall = r["CALL"] ?? "NOCALL"

            let line = [
                "QSO:",
                pad(freq, to: 5, rightAligned: true),
                pad(mode, to: 2),
                formattedDate,
                formattedTime,
                pad(call, to: 13),
                pad(sentRST, to: 3),
                pad(sentEx, to: 10),
                pad(dxCall, to: 13),
                pad(rcvdRST, to: 3),
                pad(rcvdEx, to: 10),
                "0"
            ].joined(separator: " ")
            lines.append(line)
        }

        lines.append("END-OF-LOG:")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: - HTML Report Exporter
    public static func generateHTML(
        headers: [String],
        records: [[String: String]],
        title: String = "YAAM Logbook Report",
        callsign: String = ""
    ) -> String {
        let utcNow = ISO8601DateFormatter().string(from: Date())
        var bandCounts: [String: Int] = [:]
        var modeCounts: [String: Int] = [:]
        for r in records {
            let b = (r["BAND"] ?? "Unknown").uppercased()
            let m = (r["MODE"] ?? "Unknown").uppercased()
            bandCounts[b, default: 0] += 1
            modeCounts[m, default: 0] += 1
        }

        let sortedBands = bandCounts.keys.sorted()
        let sortedModes = modeCounts.keys.sorted()

        var html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(escapeHTML(title)) - \(escapeHTML(callsign))</title>
            <style>
                :root {
                    --bg: #0f172a;
                    --card-bg: #1e293b;
                    --border: #334155;
                    --text: #f8fafc;
                    --text-muted: #94a3b8;
                    --accent: #38bdf8;
                    --accent-bg: rgba(56, 189, 248, 0.15);
                    --green: #4ade80;
                }
                body {
                    margin: 0;
                    padding: 24px;
                    background-color: var(--bg);
                    color: var(--text);
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
                }
                .container { max-width: 1400px; margin: 0 auto; }
                .header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    padding: 20px 24px;
                    background: var(--card-bg);
                    border: 1px solid var(--border);
                    border-radius: 12px;
                    margin-bottom: 20px;
                }
                .header h1 { margin: 0; font-size: 24px; color: var(--accent); }
                .stats-grid {
                    display: grid;
                    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                    gap: 16px;
                    margin-bottom: 24px;
                }
                .stat-card {
                    background: var(--card-bg);
                    border: 1px solid var(--border);
                    padding: 16px;
                    border-radius: 10px;
                }
                .stat-card .val { font-size: 28px; font-weight: bold; color: var(--text); }
                .stat-card .lbl { font-size: 13px; color: var(--text-muted); margin-top: 4px; }
                .table-container {
                    overflow-x: auto;
                    background: var(--card-bg);
                    border: 1px solid var(--border);
                    border-radius: 12px;
                }
                table {
                    width: 100%;
                    border-collapse: collapse;
                    font-size: 13px;
                }
                th {
                    background: #182234;
                    color: var(--accent);
                    text-align: left;
                    padding: 12px 14px;
                    border-bottom: 1px solid var(--border);
                    font-weight: 600;
                    position: sticky;
                    top: 0;
                }
                td {
                    padding: 10px 14px;
                    border-bottom: 1px solid var(--border);
                    white-space: nowrap;
                }
                tr:hover { background-color: rgba(56, 189, 248, 0.04); }
                .call { font-family: monospace; font-weight: bold; color: var(--green); }
                .pill {
                    display: inline-block;
                    padding: 2px 8px;
                    border-radius: 4px;
                    font-size: 11px;
                    font-weight: 600;
                    background: var(--accent-bg);
                    color: var(--accent);
                }
                .footer {
                    margin-top: 24px;
                    text-align: center;
                    font-size: 12px;
                    color: var(--text-muted);
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <div>
                        <h1>\(escapeHTML(title))</h1>
                        <div style="color: var(--text-muted); font-size: 13px; margin-top: 4px;">Station: <strong>\(callsign.isEmpty ? "All Stations" : escapeHTML(callsign))</strong></div>
                    </div>
                    <div style="text-align: right; color: var(--text-muted); font-size: 12px;">
                        Generated: \(utcNow)<br>
                        Engine: YAAM 2.0
                    </div>
                </div>

                <div class="stats-grid">
                    <div class="stat-card">
                        <div class="val">\(records.count)</div>
                        <div class="lbl">Total QSOs</div>
                    </div>
                    <div class="stat-card">
                        <div class="val">\(sortedBands.count)</div>
                        <div class="lbl">Active Bands (\(sortedBands.joined(separator: ", ")))</div>
                    </div>
                    <div class="stat-card">
                        <div class="val">\(sortedModes.count)</div>
                        <div class="lbl">Active Modes (\(sortedModes.joined(separator: ", ")))</div>
                    </div>
                </div>

                <div class="table-container">
                    <table>
                        <thead>
                            <tr>
                                <th>#</th>
        """

        for h in headers {
            html += "<th>\(escapeHTML(h))</th>\n"
        }
        html += "</tr>\n</thead>\n<tbody>\n"

        for (idx, r) in records.enumerated() {
            html += "<tr>\n<td>\(idx + 1)</td>\n"
            for h in headers {
                let v = r[h] ?? ""
                if h == "CALL" {
                    html += "<td class=\"call\">\(escapeHTML(v))</td>\n"
                } else if h == "BAND" || h == "MODE" {
                    html += "<td><span class=\"pill\">\(escapeHTML(v))</span></td>\n"
                } else {
                    html += "<td>\(escapeHTML(v))</td>\n"
                }
            }
            html += "</tr>\n"
        }

        html += """
                        </tbody>
                    </table>
                </div>

                <div class="footer">
                    Exported by YAAM (Yet Another ADIF Manager) &bull; Designed for macOS Amateur Radio Operators
                </div>
            </div>
        </body>
        </html>
        """
        return html
    }

    // MARK: - Text Summary Exporter
    public static func generateTextSummary(records: [[String: String]], callsign: String, sourceName: String) -> String {
        let utcNow = ISO8601DateFormatter().string(from: Date())
        var lines: [String] = []

        lines.append("================================================================================")
        lines.append("                         YAAM LOGBOOK SUMMARY REPORT                            ")
        lines.append("================================================================================")
        lines.append("Station Callsign : \(callsign.isEmpty ? "N/A" : callsign)")
        lines.append("Source           : \(sourceName)")
        lines.append("Total QSOs       : \(records.count)")
        lines.append("Generated UTC    : \(utcNow)")
        lines.append("--------------------------------------------------------------------------------")

        var bandCounts: [String: Int] = [:]
        var modeCounts: [String: Int] = [:]
        var dxccCount = Set<String>()

        for r in records {
            let b = (r["BAND"] ?? "Unknown").uppercased()
            let m = (r["MODE"] ?? "Unknown").uppercased()
            bandCounts[b, default: 0] += 1
            modeCounts[m, default: 0] += 1
            if let dx = r["DXCC"], !dx.isEmpty { dxccCount.insert(dx) }
        }

        lines.append("BAND BREAKDOWN:")
        for b in bandCounts.keys.sorted() {
            lines.append("  - \(pad(b, to: 8)): \(bandCounts[b]!) QSOs")
        }

        lines.append("\nMODE BREAKDOWN:")
        for m in modeCounts.keys.sorted() {
            lines.append("  - \(pad(m, to: 8)): \(modeCounts[m]!) QSOs")
        }

        lines.append("\nUNIQUE DXCC ENTITIES: \(dxccCount.count)")
        lines.append("================================================================================\n")
        lines.append(pad("#", to: 5) + pad("DATE", to: 11) + pad("TIME", to: 7) + pad("CALLSIGN", to: 14) + pad("BAND", to: 8) + pad("MODE", to: 8) + pad("RST S", to: 7) + pad("RST R", to: 7) + "NAME / QTH")
        lines.append("--------------------------------------------------------------------------------")

        for (idx, r) in records.enumerated() {
            let num = pad("\(idx + 1)", to: 5)
            let date = pad(r["QSO_DATE"] ?? "", to: 11)
            let time = pad(String((r["TIME_ON"] ?? "").prefix(4)), to: 7)
            let call = pad(r["CALL"] ?? "", to: 14)
            let band = pad(r["BAND"] ?? "", to: 8)
            let mode = pad(r["MODE"] ?? "", to: 8)
            let sent = pad(r["RST_SENT"] ?? "59", to: 7)
            let rcvd = pad(r["RST_RCVD"] ?? "59", to: 7)
            let nameQth = [r["NAME"] ?? "", r["QTH"] ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")

            lines.append(num + date + time + call + band + mode + sent + rcvd + nameQth)
        }

        lines.append("================================================================================")
        lines.append("End of Summary Report (\(records.count) QSOs).")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: - Private Helpers
    private static func normalizeTime(_ timeStr: String) -> String {
        let digits = timeStr.filter { $0.isNumber }
        if digits.count == 4 {
            return digits + "00"
        } else if digits.count < 6 {
            return digits.padding(toLength: 6, withPad: "0", startingAt: 0)
        }
        return String(digits.prefix(6))
    }

    private static func pad(_ string: String, to length: Int, rightAligned: Bool = false) -> String {
        if string.count >= length { return String(string.prefix(length)) }
        let spaces = String(repeating: " ", count: length - string.count)
        return rightAligned ? spaces + string : string + spaces
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func formatDateForCabrillo(_ dateStr: String) -> String {
        let clean = dateStr.filter { $0.isNumber }
        if clean.count >= 8 {
            let y = String(clean.prefix(4))
            let m = String(clean.dropFirst(4).prefix(2))
            let d = String(clean.dropFirst(6).prefix(2))
            return "\(y)-\(m)-\(d)"
        }
        return "2026-01-01"
    }

    private static func cabrilloFrequency(freqStr: String, band: String) -> String {
        if let mhz = Double(freqStr.trimmingCharacters(in: .whitespacesAndNewlines)), mhz > 0 {
            if mhz >= 1_000 {
                let ghz = mhz / 1_000
                if ghz >= 10 { return "\(Int(ghz.rounded()))G" }
                return String(format: "%.1fG", ghz)
            }
            return String(Int((mhz * 1_000).rounded()))
        }
        switch band.uppercased() {
        case "160M": return "1850"
        case "80M": return "3550"
        case "40M": return "7050"
        case "20M": return "14050"
        case "15M": return "21050"
        case "10M": return "28050"
        case "6M": return "50050"
        default: return "14000"
        }
    }

    private static func cabrilloMode(modeStr: String) -> String {
        let m = modeStr.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch m {
        case "CW": return "CW"
        case "SSB", "USB", "LSB", "AM", "FM": return "PH"
        case "RTTY", "FT8", "FT4", "PSK31", "PSK", "DATA", "DIGI": return "RY"
        default: return "PH"
        }
    }
}
