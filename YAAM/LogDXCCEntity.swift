import Foundation

/// Read-time entity resolution. Imported ADIF fields and confirmation evidence are never changed.
nonisolated enum LogDXCCEntity {
    enum Source: Sendable { case code, country, callsign, excluded, unresolved }
    struct Resolution: Sendable {
        let entity: DXCCEntityCatalog.Entity?
        let source: Source
        var issue: String? = nil
    }

    static func resolve(_ fields: [String: String]) -> Resolution {
        let rawCode = (fields["DXCC"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let country = canonicalCountryName(fields["COUNTRY"] ?? "")
        let call = (fields["CALL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if CallsignEntityRule.isOutsideAnyEntity(call) {
            return Resolution(entity: nil, source: .excluded,
                issue: !rawCode.isEmpty && rawCode != "0" ? "Mobile contact outside any DXCC entity has a conflicting DXCC code." : nil)
        }
        if !rawCode.isEmpty {
            guard rawCode.allSatisfy({ $0.isASCII && $0.isNumber }), let code = Int(rawCode) else {
                return Resolution(entity: nil, source: .unresolved, issue: "Invalid recorded DXCC code; review the original record.")
            }
            if code == 0 { return Resolution(entity: nil, source: .excluded) }
            guard let entity = DXCCEntityCatalog.byCode[code] else {
                return Resolution(entity: nil, source: .unresolved, issue: "Unknown recorded DXCC code; review the original record.")
            }
            let namedCodes = DXCCEntityCatalog.codesByName[CountryNameNormalizer.canonicalKey(country)]
            let disagrees = namedCodes.map { !$0.contains(code) } == true
            return Resolution(entity: entity, source: .code,
                issue: disagrees ? "Recorded country and DXCC code disagree; statistics use the recorded code." :
                    (entity.isDeleted ? "Recorded code identifies a deleted DXCC entity; historical credit is kept separate." : nil))
        }
        if let named = DXCCEntityCatalog.entity(named: country) {
            return Resolution(entity: named, source: .country)
        }
        let key = CountryNameNormalizer.canonicalKey(country)
        let genericRussia = ["russia", "russian federation", "russian fed"].contains(key)
        let genericUK = ["united kingdom", "uk", "great britain"].contains(key)
        let placeholder = ["", "unknown", "n a", "na", "not known", "not available", "unavailable"].contains(key)
        if placeholder || genericRussia || genericUK, let code = prefixes.code(for: call),
           let entity = DXCCEntityCatalog.byCode[code] {
            if genericRussia && ![15, 54, 61, 126].contains(code) || genericUK && ![106, 114, 122, 223, 265, 279, 294].contains(code) {
                return Resolution(entity: nil, source: .unresolved, issue: "Country and operating callsign disagree; the DXCC entity needs review.")
            }
            return Resolution(entity: entity, source: .callsign)
        }
        return Resolution(entity: nil, source: .unresolved, issue: "DXCC entity could not be identified from the recorded country or operating callsign.")
    }

    static func countryLabel(_ fields: [String: String]) -> String {
        if let entity = resolve(fields).entity { return entity.name }
        let country = canonicalCountryName(fields["COUNTRY"] ?? "")
        if ["russia", "russian federation", "russian fed"].contains(CountryNameNormalizer.canonicalKey(country)) {
            return "Russia (DXCC unresolved)"
        }
        return country.isEmpty ? "Unknown" : country
    }

    /// A fixed, bundled lookup keeps statistics deterministic during CTY service loading or updates.
    /// Exact operating-call exceptions take precedence over prefix rules; WAE-only entries are excluded.
    private struct PrefixIndex: Sendable {
        var exact: [String: Int] = [:]
        var byPrefix: [String: Int] = [:]
        var maximumLength = 0

        init(_ data: String) {
            let overrides = try! NSRegularExpression(pattern: #"\([^)]*\)|\[[^\]]*\]|<[^>]*>|~[^~]*~"#)
            var pendingCode: Int?
            var currentCode: Int?
            var inEntity = false
            for rawLine in data.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.hasPrefix("# ADIF ") { pendingCode = Int(line.dropFirst(7)); continue }
                if line.isEmpty || line.hasPrefix("#") { continue }
                if !inEntity {
                    let columns = line.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                    guard columns.count >= 8 else { continue }
                    currentCode = columns[7].hasPrefix("*") ? nil : pendingCode
                    pendingCode = nil
                    inEntity = true
                    continue
                }
                if let code = currentCode, DXCCEntityCatalog.byCode[code] != nil {
                    for token in line.replacingOccurrences(of: ";", with: "").split(separator: ",") {
                        let text = token.trimmingCharacters(in: .whitespaces)
                        let clean = overrides.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "").uppercased()
                        if clean.hasPrefix("=") { exact[String(clean.dropFirst())] = code }
                        else if !clean.isEmpty {
                            byPrefix[clean] = code
                            maximumLength = max(maximumLength, clean.count)
                        }
                    }
                }
                if line.contains(";") { inEntity = false; currentCode = nil }
            }
        }

        func code(for call: String) -> Int? {
            guard !call.isEmpty, call.range(of: #"^[A-Z0-9]+(?:/[A-Z0-9]+)*$"#, options: .regularExpression) != nil,
                  !CallsignEntityRule.isOutsideAnyEntity(call) else { return nil }
            if let code = exact[call] { return code }
            let operatingCall = CallsignEntityRule.withoutTrailingIndicators(call)
            let parts = operatingCall.components(separatedBy: "/")
            guard parts.count <= 2 else { return nil }
            var target = parts[0]
            if parts.count == 2, parts[0].count > parts[1].count,
               !CallsignEntityRule.operatingIndicators.contains(parts[1]) {
                // A numeric district suffix is ambiguous without a full exact-call rule.
                guard parts[1].contains(where: \.isLetter) else { return nil }
                target = parts[1]
            }
            guard maximumLength > 0 else { return nil }
            for length in stride(from: min(target.count, maximumLength), through: 1, by: -1) {
                if let code = byPrefix[String(target.prefix(length))] { return code }
            }
            return nil
        }
    }

    private static let prefixes: PrefixIndex = {
        let url = Bundle.main.url(forResource: "cty_wt", withExtension: "dat")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/cty_wt.dat")
        return PrefixIndex((try? String(contentsOf: url, encoding: .utf8)) ?? "")
    }()
}

nonisolated struct DXCCStatisticsSummary: Sendable {
    struct Issue: Identifiable, Sendable {
        let id: UUID
        let reason: String
    }
    var workedCodes = Set<Int>()
    var confirmedCodes = Set<Int>()
    var qrzConfirmedCodes = Set<Int>()
    var inferredCount = 0
    var unresolvedCount = 0
    var issues: [Issue] = []

    init(records: [QSORecordModel]) {
        for record in records {
            let resolution = LogDXCCEntity.resolve(record.fields)
            if let issue = resolution.issue { issues.append(Issue(id: record.id, reason: issue)) }
            guard let entity = resolution.entity else {
                if resolution.source == .unresolved { unresolvedCount += 1 }
                continue
            }
            workedCodes.insert(entity.code)
            if resolution.source != .code { inferredCount += 1 }
            if record.isConfirmed { confirmedCodes.insert(entity.code) }
            if ["QRZLOG_QSL_RCVD", "QRZCOM_QSL_RCVD", "APP_QRZLOG_STATUS"].contains(where: {
                ["Y", "V", "C", "CONFIRMED", "VERIFIED"].contains(record[$0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
            }) { qrzConfirmedCodes.insert(entity.code) }
        }
    }
}
