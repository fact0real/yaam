//
//  PortableActivity.swift
//  YAAM
//

import Foundation

nonisolated enum PortableOperatingRole: String, CaseIterable, Identifiable, Sendable {
    case none
    case hunter
    case activator

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Standard"
        case .hunter: return "Hunter / Chaser"
        case .activator: return "Activator"
        }
    }
}

nonisolated enum PortableProgram: String, CaseIterable, Identifiable, Sendable {
    case pota = "POTA"
    case sota = "SOTA"
    case iota = "IOTA"
    case vucc = "VUCC"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .pota: return "tree.fill"
        case .sota: return "mountain.2.fill"
        case .iota: return "water.waves"
        case .vucc: return "square.grid.3x3.fill"
        }
    }
}

nonisolated struct PortableActivitySummary: Identifiable, Equatable, Sendable {
    var id: String { "\(program.rawValue)|\(reference)|\(date)" }
    var program: PortableProgram
    var reference: String
    var date: String
    var qsoCount: Int
    var confirmedCount: Int
    var uniqueCallsigns: Int
    var bands: [String]
    var isActivationReady: Bool
}

nonisolated enum PortableActivityEngine {
    static func summaries(records: [QSORecordModel]) -> [PortableActivitySummary] {
        struct Bucket {
            var program: PortableProgram
            var reference: String
            var date: String
            var count = 0
            var confirmed = 0
            var callsigns = Set<String>()
            var bands = Set<String>()
        }

        var buckets: [String: Bucket] = [:]
        for record in records {
            let date = record["QSO_DATE"]
            let references: [(PortableProgram, String)] = [
                (.pota, mineReference(record, direct: "MY_POTA_REF", program: "POTA")),
                (.sota, mineReference(record, direct: "MY_SOTA_REF", program: "SOTA")),
                (.iota, record["MY_IOTA"]),
                (.vucc, record["MY_VUCC_GRIDS"])
            ]
            for (program, rawReference) in references {
                for reference in splitReferences(rawReference) {
                    let key = "\(program.rawValue)|\(reference)|\(date)"
                    var bucket = buckets[key] ?? Bucket(program: program, reference: reference, date: date)
                    bucket.count += 1
                    if record.isConfirmed { bucket.confirmed += 1 }
                    if !record["CALL"].isEmpty { bucket.callsigns.insert(record["CALL"].uppercased()) }
                    if !record["BAND"].isEmpty { bucket.bands.insert(record["BAND"].lowercased()) }
                    buckets[key] = bucket
                }
            }
        }

        return buckets.values.map { bucket in
            PortableActivitySummary(
                program: bucket.program,
                reference: bucket.reference,
                date: bucket.date,
                qsoCount: bucket.count,
                confirmedCount: bucket.confirmed,
                uniqueCallsigns: bucket.callsigns.count,
                bands: bucket.bands.sorted(by: bandSort),
                isActivationReady: bucket.program == .pota ? bucket.count >= 10 : bucket.count > 0
            )
        }.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            if $0.program.rawValue != $1.program.rawValue { return $0.program.rawValue < $1.program.rawValue }
            return $0.reference < $1.reference
        }
    }

    static func records(for summary: PortableActivitySummary, from records: [QSORecordModel]) -> [QSORecordModel] {
        records.filter { record in
            guard record["QSO_DATE"] == summary.date else { return false }
            let value: String
            switch summary.program {
            case .pota: value = mineReference(record, direct: "MY_POTA_REF", program: "POTA")
            case .sota: value = mineReference(record, direct: "MY_SOTA_REF", program: "SOTA")
            case .iota: value = record["MY_IOTA"]
            case .vucc: value = record["MY_VUCC_GRIDS"]
            }
            return splitReferences(value).contains(summary.reference)
        }
    }

    static func normalizedReference(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func mineReference(_ record: QSORecordModel, direct: String, program: String) -> String {
        if !record[direct].isEmpty { return record[direct] }
        return record["MY_SIG"].uppercased() == program ? record["MY_SIG_INFO"] : ""
    }

    private static func splitReferences(_ value: String) -> Set<String> {
        Set(value.uppercased()
            .components(separatedBy: CharacterSet(charactersIn: ",; "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }

    private static func bandSort(_ lhs: String, _ rhs: String) -> Bool {
        func meters(_ value: String) -> Double {
            if value.hasSuffix("cm") { return (Double(value.dropLast(2)) ?? 0) / 100 }
            return Double(value.dropLast()) ?? 0
        }
        return meters(lhs) > meters(rhs)
    }
}
