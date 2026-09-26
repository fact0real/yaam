//
//  FieldLogExporter.swift
//  YAAM
//
//  Official POTA & SOTA Log Exporter
//  Generates compliant ADIF files following the strict POTA naming convention:
//  [CALL]@[MY_POTA_REF]-[YYYYMMDD].adi
//  Also generates SOTA CSV v2 format for direct upload to sota.org.uk.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

public enum FieldLogExportFormat: String, CaseIterable, Identifiable {
    case potaADIF = "POTA Standard ADIF (.adi)"
    case sotaCSV = "SOTA Database CSV v2 (.csv)"
    case standardADIF = "Standard ADIF (.adi)"

    public var id: String { rawValue }
}

// MARK: - Field QSL Record Protocol
public protocol FieldQSORecord {
    var fields: [String: String] { get }
    subscript(key: String) -> String { get }
}

#if !STANDALONE_TEST
extension QSORecordModel: FieldQSORecord {}
#endif

public enum FieldLogExporter {

    // MARK: - Standard Filename Generation
    public static func generatePOTAFilename(callsign: String, reference: String, date: Date = Date()) -> String {
        let cleanCall = callsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanRef = reference.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let comp = calendar.dateComponents([.year, .month, .day], from: date)
        let dateStr = String(format: "%04d%02d%02d", comp.year ?? 0, comp.month ?? 0, comp.day ?? 0)

        return "\(cleanCall)@\(cleanRef)-\(dateStr).adi"
    }

    public static func generateSOTAFilename(callsign: String, summit: String, date: Date = Date()) -> String {
        let cleanCall = callsign.uppercased().replacingOccurrences(of: "/", with: "-")
        let cleanSummit = summit.uppercased().replacingOccurrences(of: "/", with: "_")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let comp = calendar.dateComponents([.year, .month, .day], from: date)
        let dateStr = String(format: "%04d%02d%02d", comp.year ?? 0, comp.month ?? 0, comp.day ?? 0)

        return "SOTA_\(cleanCall)_\(cleanSummit)_\(dateStr).csv"
    }

    // MARK: - Generate ADIF Content
    public static func buildPOTAADIF(records: [any FieldQSORecord], session: FieldActivationSession) -> String {
        var adif = "ADIF Export from YAAM Field Operations Hub\n"
        adif += "<ADIF_VER:5>3.1.4\n"
        adif += "<PROGRAMID:4>YAAM\n"
        adif += "<PROGRAMVERSION:3>2.4\n"
        adif += "<EOH>\n\n"

        for record in records {
            var fields = record.fields

            // Enforce mandatory POTA tags
            fields["STATION_CALLSIGN"] = session.operatorCallsign
            fields["OPERATOR"] = session.operatorCallsign
            fields["MY_SIG"] = "POTA"
            fields["MY_SIG_INFO"] = session.myReference
            fields["MY_POTA_REF"] = session.myReference

            if !session.gridSquare.isEmpty {
                fields["MY_GRIDSQUARE"] = session.gridSquare
            }

            var recordStr = ""
            for (key, val) in fields.sorted(by: { $0.key < $1.key }) {
                guard !val.isEmpty else { continue }
                recordStr += "<\(key):\(val.utf8.count)>\(val) "
            }
            recordStr += "<EOR>\n"
            adif += recordStr
        }

        return adif
    }

    // MARK: - Generate SOTA CSV Content (v2 specification)
    // Spec: V2,MyCallsign,MySummit,Date,Time,Band,Mode,HisCallsign,HisSummit,Notes
    public static func buildSOTACSV(records: [any FieldQSORecord], session: FieldActivationSession) -> String {
        var csv = ""

        for record in records {
            let myCall = session.operatorCallsign
            let mySummit = session.myReference

            // Date formatting DD/MM/YY
            let rawDate = record["QSO_DATE"] // YYYYMMDD
            var formattedDate = rawDate
            if rawDate.count == 8 {
                let y = rawDate.prefix(4).suffix(2)
                let m = rawDate.dropFirst(4).prefix(2)
                let d = rawDate.suffix(2)
                formattedDate = "\(d)/\(m)/\(y)"
            }

            // Time formatting HHMM
            let rawTime = record["TIME_ON"].prefix(4)
            let time = String(rawTime)

            let band = record["BAND"].lowercased()
            let mode = record["MODE"].uppercased()
            let hisCall = record["CALL"].uppercased()
            let hisSummit = record["SOTA_REF"]
            let comment = record["COMMENT"].replacingOccurrences(of: ",", with: " ")

            let row = "V2,\(myCall),\(mySummit),\(formattedDate),\(time),\(band),\(mode),\(hisCall),\(hisSummit),\(comment)\n"
            csv += row
        }

        return csv
    }

    // MARK: - Save File to Disk via NSSavePanel
    @MainActor
    public static func promptSaveFile(filename: String, content: String) {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = filename
        savePanel.prompt = "Export Log"

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            savePanel.beginSheetModal(for: window) { response in
                if response == .OK, let targetURL = savePanel.url {
                    do {
                        try content.write(to: targetURL, atomically: true, encoding: .utf8)
                        NSWorkspace.shared.activateFileViewerSelecting([targetURL])
                    } catch {
                        let alert = NSAlert()
                        alert.messageText = "Export Failed"
                        alert.informativeText = error.localizedDescription
                        alert.runModal()
                    }
                }
            }
        } else {
            let response = savePanel.runModal()
            if response == .OK, let targetURL = savePanel.url {
                try? content.write(to: targetURL, atomically: true, encoding: .utf8)
                NSWorkspace.shared.activateFileViewerSelecting([targetURL])
            }
        }
    }
}
