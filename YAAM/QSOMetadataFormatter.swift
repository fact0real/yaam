//
//  QSOMetadataFormatter.swift
//  YAAM
//
//  Intelligent ADIF comment and metadata parser for modern, high-density station logging.
//

import SwiftUI

struct ParsedQSOMetadata: Sendable {
    var iota: String?
    var state: String?
    var grid: String?
    var pota: String?
    var sota: String?
    var contestExchange: String?
    var cleanComment: String
    
    var hasBadges: Bool {
        iota != nil || state != nil || grid != nil || pota != nil || sota != nil || contestExchange != nil
    }
}

enum QSOMetadataFormatter {
    /// Parses raw comments and record fields into clean, human-readable structured metadata.
    static func parse(record: QSORecordModel) -> ParsedQSOMetadata {
        var iota: String? = record["IOTA"].isEmpty ? nil : record["IOTA"]
        var state: String? = record["STATE"].isEmpty ? nil : record["STATE"]
        var grid: String? = record["GRID"].isEmpty ? nil : record["GRID"]
        var pota: String? = record["POTA_REF"].isEmpty ? nil : record["POTA_REF"]
        var sota: String? = record["SOTA_REF"].isEmpty ? nil : record["SOTA_REF"]
        var contestExchange: String? = record["SRX_STRING"].isEmpty ? nil : record["SRX_STRING"]
        
        let rawComment = record["COMMENT"]
        var working = rawComment
        
        // Regex pattern to extract bracketed key=value tags: e.g. [IOTA=EU-177] or [MY_GRIDSQUARE=LM55]
        let pattern = #"\[([A-Z0-9_]+)=([^\]]+)\]"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = working as NSString
            let matches = regex.matches(in: working, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                guard match.numberOfRanges >= 3 else { continue }
                let key = nsString.substring(with: match.range(at: 1)).uppercased()
                let value = nsString.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                
                switch key {
                case "IOTA":
                    if iota == nil { iota = value }
                case "STATE", "US_STATE":
                    if state == nil { state = value }
                case "GRIDSQUARE", "GRID":
                    if grid == nil { grid = value }
                case "POTA", "POTA_REF":
                    if pota == nil { pota = value }
                case "SOTA", "SOTA_REF":
                    if sota == nil { sota = value }
                case "SRX", "EXCHANGE", "CONTEST_EXCHANGE":
                    if contestExchange == nil { contestExchange = value }
                case "MY_GRIDSQUARE":
                    // Operator's own grid - do not overwrite station grid, but can fallback if grid is empty
                    if grid == nil && !value.isEmpty {
                        grid = value
                    }
                default:
                    break
                }
            }
            
            // Remove all [KEY=VALUE] tokens from the comment to get clean readable text
            working = regex.stringByReplacingMatches(
                in: working,
                options: [],
                range: NSRange(location: 0, length: nsString.length),
                withTemplate: ""
            )
        }
        
        let cleaned = working.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return ParsedQSOMetadata(
            iota: iota,
            state: state,
            grid: grid,
            pota: pota,
            sota: sota,
            contestExchange: contestExchange,
            cleanComment: cleaned
        )
    }
    
    /// Formats frequency and band into a crisp band tag and rounded MHz string
    static func formatFrequency(freqRaw: String, bandRaw: String) -> (band: String, freq: String) {
        var band = bandRaw.uppercased()
        var freq = ""
        
        if let mhz = Double(freqRaw), mhz > 0 {
            // Format cleanly to 3-4 decimal places (e.g. 21.076 MHz)
            freq = String(format: "%.3f MHz", mhz)
            if band.isEmpty {
                band = AmateurBandPlan.band(forMHz: mhz) ?? "HF"
            }
        } else if !freqRaw.isEmpty {
            freq = freqRaw
        }
        
        if band.isEmpty {
            band = "HF"
        }
        
        return (band, freq)
    }
    
    /// Standard band theme color
    static func bandColor(_ band: String) -> Color {
        let b = band.lowercased()
        if b.contains("160m") { return .indigo }
        if b.contains("80m") { return .purple }
        if b.contains("60m") { return .blue.opacity(0.8) }
        if b.contains("40m") { return .blue }
        if b.contains("30m") { return .teal }
        if b.contains("20m") { return .green }
        if b.contains("17m") { return .mint }
        if b.contains("15m") { return .orange }
        if b.contains("12m") { return .yellow }
        if b.contains("10m") { return .red }
        if b.contains("6m") { return .pink }
        if b.contains("2m") { return .cyan }
        if b.contains("70cm") { return .purple }
        return .secondary
    }
}
