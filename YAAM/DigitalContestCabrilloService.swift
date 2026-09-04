//
//  DigitalContestCabrilloService.swift
//  YAAM
//
//  Official Cabrillo 3.0 Export Engine for Digital Contests.
//  Fully compliant with CQ WW Digi DX Contest, ARRL Digi / RTTY Roundup,
//  and international robot log checking specifications (cqww.com, arrl.org).
//

import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Digital Cabrillo Export Options

public struct DigitalCabrilloExportOptions: Codable, Sendable, Equatable {
    public var contestType: DigitalContestType
    public var callsign: String
    public var grid: String
    public var operatorCategory: String // SINGLE-OP, MULTI-OP, CHECKLOG
    public var assistedCategory: String // ASSISTED, NON-ASSISTED
    public var bandCategory: String // ALL, 160M, 80M, 40M, 20M, 15M, 10M, 6M
    public var powerCategory: String // HIGH, LOW, QRP
    public var stationCategory: String // FIXED, PORTABLE, MOBILE, ROVER
    public var transmitterCategory: String // ONE, TWO, MULTI, UNLIMITED
    public var overlayCategory: String // NONE, CLASSIC, ROOKIE, TB-WIRES, YOUTH
    public var operatorName: String
    public var address: String
    public var city: String
    public var stateProvince: String
    public var postalCode: String
    public var country: String
    public var email: String
    public var club: String
    public var operators: String
    public var soapbox: String

    public init(
        contestType: DigitalContestType = .cqWWDigi,
        callsign: String = "",
        grid: String = "",
        operatorCategory: String = "SINGLE-OP",
        assistedCategory: String = "ASSISTED",
        bandCategory: String = "ALL",
        powerCategory: String = "LOW",
        stationCategory: String = "FIXED",
        transmitterCategory: String = "ONE",
        overlayCategory: String = "NONE",
        operatorName: String = "",
        address: String = "",
        city: String = "",
        stateProvince: String = "",
        postalCode: String = "",
        country: String = "",
        email: String = "",
        club: String = "",
        operators: String = "",
        soapbox: String = ""
    ) {
        self.contestType = contestType
        self.callsign = callsign.uppercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        self.grid = grid.uppercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        self.operatorCategory = operatorCategory
        self.assistedCategory = assistedCategory
        self.bandCategory = bandCategory
        self.powerCategory = powerCategory
        self.stationCategory = stationCategory
        self.transmitterCategory = transmitterCategory
        self.overlayCategory = overlayCategory
        self.operatorName = operatorName
        self.address = address
        self.city = city
        self.stateProvince = stateProvince
        self.postalCode = postalCode
        self.country = country
        self.email = email
        self.club = club
        self.operators = operators.isEmpty ? callsign : operators
        self.soapbox = soapbox
    }
}

// MARK: - Robot Pre-Flight Validation

public struct CabrilloIssue: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public let isError: Bool // true = error (robot rejection risk), false = warning
    public let message: String
    public let callsign: String?

    public var iconName: String {
        isError ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
    }

    public var badgeColor: Color {
        isError ? .red : .orange
    }
}

// MARK: - Cabrillo 3.0 Export Engine

@MainActor
public enum DigitalContestCabrilloService {

    // Standard UTC Date Formatters (POSIX)
    nonisolated private static let utcDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    nonisolated private static let utcTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "HHmm"
        return df
    }()

    // MARK: - Validation

    public static func validate(
        engine: DigitalContestEngine,
        options: DigitalCabrilloExportOptions
    ) -> [CabrilloIssue] {
        var issues: [CabrilloIssue] = []

        // 1. Callsign Check
        if options.callsign.isEmpty {
            issues.append(CabrilloIssue(isError: true, message: "Station Callsign is required for Cabrillo submission.", callsign: nil))
        }

        // 2. Grid check for CQ WW Digi
        if options.contestType == .cqWWDigi {
            if options.grid.isEmpty {
                issues.append(CabrilloIssue(isError: true, message: "GRID-LOCATOR is mandatory for CQ WW Digi contest logs.", callsign: nil))
            } else if options.grid.count < 4 {
                issues.append(CabrilloIssue(isError: true, message: "GRID-LOCATOR must be at least 4 characters (e.g. KM32).", callsign: nil))
            }
        }

        // 3. QSOs presence
        if engine.qsoLog.isEmpty {
            issues.append(CabrilloIssue(isError: false, message: "Contest log is currently empty (0 QSOs logged).", callsign: nil))
        }

        // 4. Per-QSO audits
        for qso in engine.qsoLog {
            if qso.callsign.isEmpty {
                issues.append(CabrilloIssue(isError: true, message: "Found QSO with empty callsign.", callsign: nil))
            }

            if options.contestType == .cqWWDigi {
                let g = qso.grid?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
                if g.isEmpty {
                    issues.append(CabrilloIssue(isError: true, message: "Missing 4-char grid locator for contact \(qso.callsign).", callsign: qso.callsign))
                }
            } else if options.contestType == .arrlRoundup {
                let exch = qso.rcvdExchange.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if exch.isEmpty {
                    issues.append(CabrilloIssue(isError: true, message: "Missing exchange (serial/state) for contact \(qso.callsign).", callsign: qso.callsign))
                }
            }

            if qso.frequencyHz == 0 {
                issues.append(CabrilloIssue(isError: false, message: "QSO frequency was 0 for \(qso.callsign). Standard band default will be exported.", callsign: qso.callsign))
            }
        }

        return issues
    }

    // MARK: - Generation

    public static func generateCabrillo(
        engine: DigitalContestEngine,
        options: DigitalCabrilloExportOptions,
        softwareVersion: String = "YAAM 1.2"
    ) -> String {
        var lines: [String] = []

        // 1. Mandatory Headers (Cabrillo 3.0 Standard)
        lines.append("START-OF-LOG: 3.0")
        lines.append("CREATED-BY: \(softwareVersion)")
        lines.append("CONTEST: \(options.contestType.shortCode)")
        lines.append("CALLSIGN: \(options.callsign.uppercased())")
        lines.append("CATEGORY-OPERATOR: \(options.operatorCategory)")
        lines.append("CATEGORY-ASSISTED: \(options.assistedCategory)")
        lines.append("CATEGORY-BAND: \(options.bandCategory)")

        // Mode designation in Cabrillo 3.0
        switch options.contestType {
        case .cqWWDigi:
            lines.append("CATEGORY-MODE: DIGI")
        case .arrlRoundup, .generalContest:
            lines.append("CATEGORY-MODE: DG")
        }

        lines.append("CATEGORY-POWER: \(options.powerCategory)")
        lines.append("CATEGORY-STATION: \(options.stationCategory)")
        lines.append("CATEGORY-TRANSMITTER: \(options.transmitterCategory)")

        if options.overlayCategory != "NONE" && !options.overlayCategory.isEmpty {
            lines.append("CATEGORY-OVERLAY: \(options.overlayCategory)")
        }

        // Claimed Score
        lines.append("CLAIMED-SCORE: \(engine.claimedScore)")

        // Grid Locator (Required by CQ WW Digi)
        if !options.grid.isEmpty {
            lines.append("GRID-LOCATOR: \(options.grid.uppercased())")
        }

        // Operators
        let ops = options.operators.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        lines.append("OPERATORS: \(ops.isEmpty ? options.callsign.uppercased() : ops.uppercased())")

        // Station Metadata
        if !options.operatorName.isEmpty { lines.append("NAME: \(options.operatorName)") }
        if !options.address.isEmpty { lines.append("ADDRESS: \(options.address)") }
        if !options.city.isEmpty { lines.append("ADDRESS-CITY: \(options.city)") }
        if !options.stateProvince.isEmpty { lines.append("ADDRESS-STATE-PROVINCE: \(options.stateProvince)") }
        if !options.postalCode.isEmpty { lines.append("ADDRESS-POSTALCODE: \(options.postalCode)") }
        if !options.country.isEmpty { lines.append("ADDRESS-COUNTRY: \(options.country)") }
        if !options.email.isEmpty { lines.append("EMAIL: \(options.email)") }
        if !options.club.isEmpty { lines.append("CLUB: \(options.club)") }

        if !options.soapbox.isEmpty {
            for soapLine in options.soapbox.components(separatedBy: CharacterSet.newlines) {
                let trimmed = soapLine.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    lines.append("SOAPBOX: \(trimmed)")
                }
            }
        }

        // 2. QSO Records in Chronological Order (oldest first)
        let chronologicalQSOs = engine.qsoLog.reversed()

        for qso in chronologicalQSOs {
            let freqKHz = formatFrequencyKHz(frequencyHz: qso.frequencyHz, band: qso.band)
            let dateStr = utcDateFormatter.string(from: qso.timestamp)
            let timeStr = utcTimeFormatter.string(from: qso.timestamp)
            let sentCall = options.callsign.uppercased()
            let rcvdCall = qso.callsign.uppercased()

            switch options.contestType {
            case .cqWWDigi:
                // CQ WW Digi format:
                // QSO:  freq  mo date       time call          grid   call          grid   t
                // QSO: 14080 DG 2026-08-29 1205 EP2LMA       KM32   DL1ABC        JO31   0
                let sentGrid = String((options.grid.isEmpty ? engine.myStationGrid : options.grid).prefix(6)).uppercased()
                let rcvdGrid = String((qso.grid ?? qso.rcvdExchange).prefix(6)).uppercased()

                let qsoLine = [
                    "QSO:",
                    pad(freqKHz, to: 5, rightAligned: true),
                    "DG",
                    dateStr,
                    timeStr,
                    pad(sentCall, to: 13),
                    pad(sentGrid, to: 6),
                    pad(rcvdCall, to: 13),
                    pad(rcvdGrid, to: 6),
                    "0"
                ].joined(separator: " ")
                lines.append(qsoLine)

            case .arrlRoundup, .generalContest:
                // ARRL Digi / RTTY Roundup format:
                // QSO:  freq  mo date       time call          rst exch   call          rst exch
                // QSO: 14074 DG 2026-01-03 1800 EP2LMA       599  001   W1AW          599  CT
                let sentRST = normalizeRST(qso.sentReport)
                let rcvdRST = normalizeRST(qso.rcvdReport)
                let sentExch = qso.sentExchange.isEmpty ? (options.grid.isEmpty ? "001" : options.grid) : qso.sentExchange
                let rcvdExch = qso.rcvdExchange.isEmpty ? (qso.grid ?? "001") : qso.rcvdExchange

                let qsoLine = [
                    "QSO:",
                    pad(freqKHz, to: 5, rightAligned: true),
                    "DG",
                    dateStr,
                    timeStr,
                    pad(sentCall, to: 13),
                    pad(sentRST, to: 3),
                    pad(sentExch, to: 6),
                    pad(rcvdCall, to: 13),
                    pad(rcvdRST, to: 3),
                    pad(rcvdExch, to: 6)
                ].joined(separator: " ")
                lines.append(qsoLine)
            }
        }

        // 3. Mandatory Footer
        lines.append("END-OF-LOG:")

        // RFC / Cabrillo standard CRLF line endings
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: - Helpers

    public static func formatFrequencyKHz(frequencyHz: UInt64, band: String) -> String {
        if frequencyHz > 0 {
            let khz = Int(frequencyHz / 1000)
            return String(khz)
        }
        let b = band.lowercased().replacingOccurrences(of: "m", with: "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        switch b {
        case "160": return "1840"
        case "80": return "3573"
        case "40": return "7074"
        case "20": return "14074"
        case "15": return "21074"
        case "10": return "28074"
        case "6": return "50313"
        default: return "14074"
        }
    }

    private static func normalizeRST(_ report: String) -> String {
        let clean = report.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if clean.isEmpty { return "599" }
        // If it's dB like -08 or +02, map to standard 599 for Cabrillo or keep clean
        if clean.hasPrefix("-") || clean.hasPrefix("+") {
            return "599"
        }
        if clean.count <= 3 {
            return clean
        }
        return String(clean.prefix(3))
    }

    private static func pad(_ string: String, to length: Int, rightAligned: Bool = false) -> String {
        let clean = string.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let clipped = String(clean.prefix(length))
        let padCount = max(0, length - clipped.count)
        let padding = String(repeating: " ", count: padCount)
        return rightAligned ? padding + clipped : clipped + padding
    }

    // MARK: - Native File Export Helper

    @MainActor
    public static func exportLogToFile(
        cabrilloContent: String,
        defaultFileName: String
    ) {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        let logType = UTType(filenameExtension: "log") ?? .plainText
        let cbrType = UTType(filenameExtension: "cbr") ?? .plainText
        savePanel.allowedContentTypes = [logType, cbrType, .plainText]
        savePanel.nameFieldStringValue = defaultFileName

        if savePanel.runModal() == .OK, let targetURL = savePanel.url {
            do {
                try cabrilloContent.write(to: targetURL, atomically: true, encoding: .utf8)
                NSWorkspace.shared.activateFileViewerSelecting([targetURL])
            } catch {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = "Unable to save Cabrillo log: \(error.localizedDescription)"
                alert.alertStyle = .critical
                alert.runModal()
            }
        }
    }
}
