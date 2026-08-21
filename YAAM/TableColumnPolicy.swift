//
//  TableColumnPolicy.swift
//  YAAM
//

import Foundation

/// Keeps operational metadata in the protected logbook without crowding the working table.
nonisolated enum TableColumnPolicy {
    private static let databaseOnlyColumns: Set<String> = [
        "STATION", "STATION_CALLSIGN", "OPERATOR", "QRZ",
        "LAT", "LON", "LATITUDE", "LONGITUDE", "FREQ_RX",
        "LOTW_QSL_RCVD", "LOTW_QSLRDATE", "LOTW_QSL_SENT", "LOTW_QSLSDATE",
        "QRZLOG_QSL_RCVD", "QRZLOG_QSLRDATE", "QSL_RCVD", "QSLRDATE", "QSL_SENT", "QSLSDATE",
        "QSL_VIA", "QSO_DATE_OFF", "TIME_OFF", "APP_YAAM_ENRICHED"
    ]

    static func normalized(_ header: String) -> String {
        header.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    static func isDatabaseOnly(_ header: String) -> Bool {
        let field = normalized(header)
        return databaseOnlyColumns.contains(field) ||
            field.hasPrefix("MY_") ||
            field.hasPrefix("APP_") ||
            field.hasPrefix("LOTW_") ||
            field.hasPrefix("QRZLOG_") ||
            field.hasPrefix("QRZCOM_") ||
            field.hasPrefix("EQSL_")
    }

    static func isHiddenByDefault(_ header: String, isMostlyEmpty: Bool) -> Bool {
        let field = normalized(header)
        if field == "EMAIL" || field == "QRZ_URL" || field.hasPrefix("RANK_") {
            return false
        }
        return isDatabaseOnly(field) ||
            ["COMMENT", "QTH", "TX_PWR", "TX_POWER", "SUBMODE", "IOTA", "STATE", "CQZ", "ITUZ", "DXCC", "CNTY", "DISTANCE"].contains(field) ||
            isMostlyEmpty
    }

    static func isLowPriority(_ header: String) -> Bool {
        isDatabaseOnly(header) || ["QRZ"].contains(normalized(header))
    }
}
