//
//  LogFileReader.swift
//  YAAM
//

import Foundation

nonisolated enum LogSourceFormat: String, Sendable {
    case adif
    case smartSDR

    var title: String {
        switch self {
        case .adif: return "ADIF"
        case .smartSDR: return "SDR Control"
        }
    }

    var detail: String {
        switch self {
        case .adif: return "ADIF log"
        case .smartSDR: return "SmartSDR log"
        }
    }

    var systemImage: String {
        switch self {
        case .adif: return "doc.text"
        case .smartSDR: return "radio"
        }
    }
}

nonisolated struct ParsedLogFile: Sendable {
    let sourceURL: URL
    let format: LogSourceFormat
    let headers: [String]
    let records: [[String: String]]
    let originalADIFContent: String?
    let ignoredDeletedRecordCount: Int
    let validationIssueCount: Int
}

nonisolated enum LogFileReaderError: LocalizedError {
    case unsupportedFormat(String)
    case unreadableADIFText
    case noQSORecords(LogSourceFormat)
    case invalidSmartSDRRoot

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let fileName):
            return "\(fileName) is not a supported ADIF or SmartSDR log file."
        case .unreadableADIFText:
            return "The ADIF file is not valid UTF-8 or ISO Latin-1 text."
        case .noQSORecords(let format):
            return "No active QSO records were found in the \(format.detail)."
        case .invalidSmartSDRRoot:
            return "The SmartSDR log is not the expected SDR Control property-list format."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unsupportedFormat:
            return "Choose an .adi, .adif, or .smartsdrlog file."
        case .unreadableADIFText:
            return "Export the log again as ADIF text and retry."
        case .noQSORecords:
            return "Verify that the source contains contacts that have not been marked as deleted."
        case .invalidSmartSDRRoot:
            return "Select SmartSDR.smartsdrlog created by SDR Control for Mac."
        }
    }
}

nonisolated enum LogFileReader {
    static let supportedFilenameExtensions = ["adi", "adif", "smartsdrlog"]

    static func loadWithSecurityScopedAccess(from url: URL) throws -> ParsedLogFile {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
        }
        return try load(from: url)
    }

    static func load(from url: URL) throws -> ParsedLogFile {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let fileExtension = url.pathExtension.lowercased()

        if fileExtension == "smartsdrlog" || hasBinaryPlistHeader(data) {
            return try parseSmartSDR(data: data, sourceURL: url)
        }

        guard fileExtension == "adi" || fileExtension == "adif" || looksLikeADIF(data) else {
            throw LogFileReaderError.unsupportedFormat(url.lastPathComponent)
        }

        return try parseADIFLog(data: data, sourceURL: url)
    }

    private static func parseADIFLog(data: Data, sourceURL: URL) throws -> ParsedLogFile {
        guard let content = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            throw LogFileReaderError.unreadableADIFText
        }

        let parsed = parseADIF(content: content)
        guard !parsed.records.isEmpty else {
            throw LogFileReaderError.noQSORecords(.adif)
        }

        return ParsedLogFile(
            sourceURL: sourceURL,
            format: .adif,
            headers: parsed.headers,
            records: parsed.records,
            originalADIFContent: content,
            ignoredDeletedRecordCount: 0,
            validationIssueCount: parsed.records.filter { !isImportable($0) }.count
        )
    }

    private static func parseSmartSDR(data: Data, sourceURL: URL) throws -> ParsedLogFile {
        let propertyList: Any
        do {
            propertyList = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
        } catch {
            throw LogFileReaderError.invalidSmartSDRRoot
        }
        guard let entries = propertyList as? [Any] else {
            throw LogFileReaderError.invalidSmartSDRRoot
        }

        var records: [[String: String]] = []
        records.reserveCapacity(entries.count)
        var deletedCount = 0
        var validationIssueCount = 0
        var normalizedKeyCache: [String: String] = [:]

        for value in entries {
            guard let entry = value as? [String: Any] else {
                validationIssueCount += 1
                continue
            }
            if isDeleted(entry["Deleted"] ?? entry["DELETED"]) {
                deletedCount += 1
                continue
            }

            var record: [String: String] = [:]
            record.reserveCapacity(entry.count + 3)
            for (sourceKey, sourceValue) in entry {
                let key: String
                if let cached = normalizedKeyCache[sourceKey] {
                    key = cached
                } else {
                    let normalized = normalizedSmartSDRKey(sourceKey)
                    normalizedKeyCache[sourceKey] = normalized
                    key = normalized
                }
                guard key != "DELETED", !key.isEmpty else { continue }
                let normalizedValue = normalizedSmartSDRValue(sourceValue, key: key)
                if !normalizedValue.isEmpty {
                    record[key] = normalizedValue
                }
            }

            if let comment = record["COMMENT"] {
                for (key, value) in embeddedADIFFields(in: comment) where record[key] == nil {
                    record[key] = value
                }
            }
            normalizeSmartSDRConfirmations(in: &record)
            if (record["BAND"] ?? "").isEmpty {
                let inferredBand = ADIFConversionFilter.resolvedBand(for: record)
                if !inferredBand.isEmpty { record["BAND"] = inferredBand }
            }

            record["APP_SDR_CONTROL_IMPORTED"] = "Y"
            if !isImportable(record) { validationIssueCount += 1 }
            if !record.isEmpty { records.append(record) }
        }

        guard !records.isEmpty else {
            throw LogFileReaderError.noQSORecords(.smartSDR)
        }

        return ParsedLogFile(
            sourceURL: sourceURL,
            format: .smartSDR,
            headers: orderedHeaders(for: records),
            records: records,
            originalADIFContent: nil,
            ignoredDeletedRecordCount: deletedCount,
            validationIssueCount: validationIssueCount
        )
    }

    private static func normalizedSmartSDRKey(_ sourceKey: String) -> String {
        let upper = sourceKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        switch upper {
        case "UNIQUEID", "UNIQUE_ID":
            return "APP_SDR_CONTROL_ID"
        case "LOTWCONFIRMED", "LOTW_QSL_RECEIVED", "LOTWQSLRCVD", "LOTW_QSL_RCVD":
            return "LOTW_QSL_RCVD"
        case "QRZCONFIRMED", "QRZ_QSL_RECEIVED", "QRZQSLRCVD", "QRZLOG_QSL_RCVD":
            return "QRZLOG_QSL_RCVD"
        case "QSLRECEIVED", "QSL_RECEIVED", "QSLRCVD":
            return "QSL_RCVD"
        case "CONFIRMED", "ISCONFIRMED", "QSO_CONFIRMED":
            return "APP_SDR_CONTROL_CONFIRMED"
        default:
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
            return upper.unicodeScalars.map { allowed.contains($0) ? String($0) : "_" }.joined()
        }
    }

    private static func normalizedSmartSDRValue(_ value: Any, key: String) -> String {
        if let date = value as? Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            switch key {
            case "QSO_DATE", "QSLRDATE", "QSLSDATE":
                return String(format: "%04d%02d%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
            case "TIME_ON", "TIME_OFF":
                return String(format: "%02d%02d%02d", components.hour ?? 0, components.minute ?? 0, components.second ?? 0)
            default:
                break
            }
        }

        let rawValue = stringValue(value)
        switch key {
        case "QSO_DATE", "QSLRDATE", "QSLSDATE":
            let digits = rawValue.filter(\.isNumber)
            return digits.count >= 8 ? String(digits.prefix(8)) : digits
        case "TIME_ON", "TIME_OFF":
            let digits = rawValue.filter(\.isNumber)
            if digits.count >= 6 { return String(digits.prefix(6)) }
            if digits.count == 5 { return "0" + digits }
            if digits.count == 4 { return digits + "00" }
            return digits
        case "CALL", "STATION_CALLSIGN", "OPERATOR", "BAND", "BAND_RX", "MODE", "SUBMODE", "CONT":
            return rawValue.uppercased()
        case "FREQ", "FREQ_RX":
            return rawValue.replacingOccurrences(of: ",", with: ".")
        default:
            return rawValue
        }
    }

    private static func stringValue(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber:
            return number.stringValue
        case let date as Date:
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter.string(from: date)
        default:
            return ""
        }
    }

    private static func isDeleted(_ value: Any?) -> Bool {
        ["1", "Y", "YES", "TRUE"].contains(stringValue(value).uppercased())
    }

    private static func isImportable(_ record: [String: String]) -> Bool {
        let call = record["CALL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let date = record["QSO_DATE"]?.filter(\.isNumber) ?? ""
        return !call.isEmpty && date.count == 8
    }

    private static func normalizeSmartSDRConfirmations(in record: inout [String: String]) {
        let isAffirmative: (String?) -> Bool = { value in
            ["1", "Y", "YES", "TRUE", "V", "C", "CONFIRMED", "VERIFIED"].contains(
                (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            )
        }
        let hasLoTW = isAffirmative(record["LOTW_QSL_RCVD"])
        let hasQRZ = isAffirmative(record["QRZLOG_QSL_RCVD"])
        let isConfirmed = hasLoTW || hasQRZ || isAffirmative(record["QSL_RCVD"]) || isAffirmative(record["APP_SDR_CONTROL_CONFIRMED"])
        if isConfirmed { record["QSL_RCVD"] = "Y" }
        if hasLoTW { record["LOTW_QSL_RCVD"] = "Y" }
        if hasQRZ { record["QRZLOG_QSL_RCVD"] = "Y" }
    }

    private static func embeddedADIFFields(in comment: String) -> [String: String] {
        var result: [String: String] = [:]
        var remainder = comment[...]

        while let open = remainder.firstIndex(of: "[") {
            let afterOpen = remainder.index(after: open)
            guard let close = remainder[afterOpen...].firstIndex(of: "]") else { break }
            let token = remainder[afterOpen..<close]
            if let separator = token.firstIndex(of: "=") {
                let rawKey = String(token[..<separator])
                let rawValue = String(token[token.index(after: separator)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let key = normalizedSmartSDRKey(rawKey)
                if !key.isEmpty, !rawValue.isEmpty {
                    result[key] = rawValue
                }
            }
            remainder = remainder[remainder.index(after: close)...]
        }

        return result
    }

    private static func orderedHeaders(for records: [[String: String]]) -> [String] {
        let preferred = [
            "QSO_DATE", "TIME_ON", "TIME_OFF", "CALL", "FREQ", "FREQ_RX", "BAND", "BAND_RX",
            "MODE", "SUBMODE", "RST_SENT", "RST_RCVD", "NAME", "QTH", "COUNTRY", "CONT",
            "DXCC", "CQZ", "ITUZ", "GRIDSQUARE", "MY_GRIDSQUARE", "LAT", "LON", "COMMENT",
            "OPERATOR", "STATION_CALLSIGN", "APP_SDR_CONTROL_ID", "APP_SDR_CONTROL_IMPORTED"
        ]
        var allHeaders = Set<String>()
        for record in records {
            allHeaders.formUnion(record.keys)
        }
        return preferred.filter(allHeaders.contains) + allHeaders.subtracting(preferred).sorted()
    }

    private static func hasBinaryPlistHeader(_ data: Data) -> Bool {
        data.starts(with: Data("bplist00".utf8))
    }

    private static func looksLikeADIF(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(8_192), encoding: .utf8)
            ?? String(data: data.prefix(8_192), encoding: .isoLatin1) else {
            return false
        }
        let upper = prefix.uppercased()
        return upper.contains("<EOH>") || upper.contains("<EOR>") || upper.contains("<CALL:")
    }
}
