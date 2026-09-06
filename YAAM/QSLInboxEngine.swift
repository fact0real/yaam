//
//  QSLInboxEngine.swift
//  YAAM
//
//  Inbound QSL Processing, Email & File Parser (.eml, PDF, Images, ADIF),
//  Offline Vision OCR, Fuzzy QSO Matching with Time Drift Tolerance,
//  and Side-by-Side Conflict Resolution.
//

import AppKit
import Combine
import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import Vision

// MARK: - Inbound Item Models

public enum QSLInboundSource: String, Codable, Sendable {
    case email = "Email (.eml)"
    case image = "Card Image"
    case pdf = "PDF Document"
    case adif = "ADIF Import"
    case eqsl = "eQSL.cc Download"
}

public enum QSLInboundStatus: String, Codable, Sendable {
    case pending = "Pending Match"
    case matched = "Matched"
    case conflict = "Conflict (Diffs Found)"
    case archived = "Archived"
    case rejected = "Rejected"

    public var color: Color {
        switch self {
        case .pending: return .blue
        case .matched: return .green
        case .conflict: return .orange
        case .archived: return .secondary
        case .rejected: return .red
        }
    }
}

public struct QSLConflictDiff: Identifiable, Equatable, Sendable {
    public var id: String { fieldName }
    public let fieldName: String
    public let localValue: String
    public let inboundValue: String
}

public struct QSLInboundItem: Identifiable, Sendable {
    public let id: UUID
    public let source: QSLInboundSource
    public let filename: String
    public let fromAddress: String
    public let subject: String
    public let rawBody: String
    public let receivedAt: Date

    // Extracted QSO Metadata
    public var callsign: String
    public var qsoDate: String // YYYYMMDD or YYYY-MM-DD
    public var qsoTime: String // HHMM or HH:MM
    public var band: String
    public var mode: String
    public var rst: String

    // Attachments & Media
    public var mediaFileURL: URL?
    public var mediaData: Data?

    // Matching Status
    public var status: QSLInboundStatus
    public var matchConfidence: Int // 0 - 100
    public var matchedQSOID: UUID?
    public var conflictDiffs: [QSLConflictDiff]

    public init(
        id: UUID = UUID(),
        source: QSLInboundSource,
        filename: String,
        fromAddress: String = "",
        subject: String = "",
        rawBody: String = "",
        receivedAt: Date = Date(),
        callsign: String = "",
        qsoDate: String = "",
        qsoTime: String = "",
        band: String = "",
        mode: String = "",
        rst: String = "",
        mediaFileURL: URL? = nil,
        mediaData: Data? = nil,
        status: QSLInboundStatus = .pending,
        matchConfidence: Int = 0,
        matchedQSOID: UUID? = nil,
        conflictDiffs: [QSLConflictDiff] = []
    ) {
        self.id = id
        self.source = source
        self.filename = filename
        self.fromAddress = fromAddress
        self.subject = subject
        self.rawBody = rawBody
        self.receivedAt = receivedAt
        self.callsign = callsign.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.qsoDate = qsoDate
        self.qsoTime = qsoTime
        self.band = band.uppercased()
        self.mode = mode.uppercased()
        self.rst = rst
        self.mediaFileURL = mediaFileURL
        self.mediaData = mediaData
        self.status = status
        self.matchConfidence = matchConfidence
        self.matchedQSOID = matchedQSOID
        self.conflictDiffs = conflictDiffs
    }
}

// MARK: - QSL Inbox Engine

@MainActor
public final class QSLInboxEngine: ObservableObject {
    public static let shared = QSLInboxEngine()

    @Published public var inboundItems: [QSLInboundItem] = []
    @Published public var isProcessingDrop: Bool = false
    @Published public var lastMessage: String = "Drag and drop .eml, images, or PDFs to import QSLs"
    @Published public var selectedItemForResolution: QSLInboundItem? = nil

    private let fileManager = FileManager.default

    public init() {
        createMediaStorageDirectoryIfNeeded()
    }

    // MARK: - Local Media Archive Directory

    public var mediaArchiveDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let yaamDir = appSupport.appendingPathComponent("YAAM", isDirectory: true)
        return yaamDir.appendingPathComponent("QSL_Media", isDirectory: true)
    }

    public func createMediaStorageDirectoryIfNeeded() {
        let dir = mediaArchiveDirectoryURL
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Ingestion Handlers (File Drop & URL Processing)

    func processDroppedFiles(_ urls: [URL], existingQSOs: [QSORecordModel]) async {
        isProcessingDrop = true
        lastMessage = "Processing \(urls.count) dropped file(s)..."

        for url in urls {
            let ext = url.pathExtension.lowercased()
            do {
                if ext == "eml" {
                    try await processEMLFile(at: url, existingQSOs: existingQSOs)
                } else if ["jpg", "jpeg", "png", "webp", "heic"].contains(ext) {
                    try await processImageFile(at: url, existingQSOs: existingQSOs)
                } else if ext == "pdf" {
                    try await processPDFFile(at: url, existingQSOs: existingQSOs)
                } else if ["adi", "adif"].contains(ext) {
                    try await processADIFFile(at: url, existingQSOs: existingQSOs)
                } else {
                    lastMessage = "Unsupported format: .\(ext)"
                }
            } catch {
                lastMessage = "Failed to process \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }

        isProcessingDrop = false
    }

    // MARK: - EML Email Parsing

    func processEMLFile(at url: URL, existingQSOs: [QSORecordModel]) async throws {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw NSError(domain: "QSLInbox", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unreadable email text"])
        }

        // 1. Extract Headers (From, Subject, Date)
        var from = ""
        var subject = ""
        var emailDate = ""

        content.enumerateLines { line, stop in
            if line.lowercased().hasPrefix("from: ") && from.isEmpty {
                from = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.lowercased().hasPrefix("subject: ") && subject.isEmpty {
                subject = String(line.dropFirst(9)).trimmingCharacters(in: .whitespaces)
            } else if line.lowercased().hasPrefix("date: ") && emailDate.isEmpty {
                emailDate = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            }
            if !from.isEmpty && !subject.isEmpty && !emailDate.isEmpty {
                stop = true
            }
        }

        // 2. Extract embedded attachments & plain body
        let (extractedBody, extractedAttachmentData, attachmentName) = parseMIME(content: content, rawData: data)

        // 3. Extract Amateur Metadata from Subject + Body
        let combinedText = "\(subject)\n\(extractedBody)\n\(from)"
        let metadata = extractQSOMetadata(fromText: combinedText, filename: url.lastPathComponent)

        // 4. Save attachment if present
        var localMediaURL: URL? = nil
        if let attData = extractedAttachmentData, !attData.isEmpty {
            let filename = attachmentName.isEmpty ? "\(metadata.callsign.isEmpty ? "QSL" : metadata.callsign)_\(UUID().uuidString.prefix(6)).jpg" : attachmentName
            localMediaURL = saveMediaFile(data: attData, preferredName: filename)
        }

        var inbound = QSLInboundItem(
            source: .email,
            filename: url.lastPathComponent,
            fromAddress: from,
            subject: subject,
            rawBody: extractedBody,
            callsign: metadata.callsign,
            qsoDate: metadata.date,
            qsoTime: metadata.time,
            band: metadata.band,
            mode: metadata.mode,
            rst: metadata.rst,
            mediaFileURL: localMediaURL,
            mediaData: extractedAttachmentData
        )

        // 5. Fuzzy Match against Logbook
        evaluateFuzzyMatch(item: &inbound, existingQSOs: existingQSOs)

        inboundItems.insert(inbound, at: 0)
        lastMessage = "Imported email: \(subject.isEmpty ? url.lastPathComponent : subject)"
    }

    // MARK: - Direct Image Processing & Vision OCR

    func processImageFile(at url: URL, existingQSOs: [QSORecordModel]) async throws {
        let data = try Data(contentsOf: url)
        let ocrText = await performVisionOCR(on: data)
        let metadata = extractQSOMetadata(fromText: ocrText, filename: url.lastPathComponent)

        let savedURL = saveMediaFile(data: data, preferredName: url.lastPathComponent)

        var inbound = QSLInboundItem(
            source: .image,
            filename: url.lastPathComponent,
            rawBody: ocrText,
            callsign: metadata.callsign,
            qsoDate: metadata.date,
            qsoTime: metadata.time,
            band: metadata.band,
            mode: metadata.mode,
            rst: metadata.rst,
            mediaFileURL: savedURL,
            mediaData: data
        )

        evaluateFuzzyMatch(item: &inbound, existingQSOs: existingQSOs)
        inboundItems.insert(inbound, at: 0)
        lastMessage = "Imported card image: \(url.lastPathComponent)"
    }

    // MARK: - PDF Processing

    func processPDFFile(at url: URL, existingQSOs: [QSORecordModel]) async throws {
        let data = try Data(contentsOf: url)
        var extractedText = ""

        if let pdfDoc = PDFDocument(url: url) {
            for i in 0..<pdfDoc.pageCount {
                if let page = pdfDoc.page(at: i), let pageString = page.string {
                    extractedText.append(pageString)
                    extractedText.append("\n")
                }
            }
        }

        let metadata = extractQSOMetadata(fromText: extractedText, filename: url.lastPathComponent)
        let savedURL = saveMediaFile(data: data, preferredName: url.lastPathComponent)

        var inbound = QSLInboundItem(
            source: .pdf,
            filename: url.lastPathComponent,
            rawBody: extractedText,
            callsign: metadata.callsign,
            qsoDate: metadata.date,
            qsoTime: metadata.time,
            band: metadata.band,
            mode: metadata.mode,
            rst: metadata.rst,
            mediaFileURL: savedURL,
            mediaData: data
        )

        evaluateFuzzyMatch(item: &inbound, existingQSOs: existingQSOs)
        inboundItems.insert(inbound, at: 0)
        lastMessage = "Imported PDF QSL: \(url.lastPathComponent)"
    }

    // MARK: - ADIF File Processing

    func processADIFFile(at url: URL, existingQSOs: [QSORecordModel]) async throws {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return }

        let records = parseADIFText(text)
        for rec in records {
            let call = rec["CALL"] ?? ""
            let date = rec["QSO_DATE"] ?? ""
            let time = rec["TIME_ON"] ?? ""
            let band = rec["BAND"] ?? ""
            let mode = rec["MODE"] ?? ""
            let rst = rec["RST_RCVD"] ?? rec["RST_SENT"] ?? ""

            var inbound = QSLInboundItem(
                source: .adif,
                filename: url.lastPathComponent,
                callsign: call,
                qsoDate: date,
                qsoTime: time,
                band: band,
                mode: mode,
                rst: rst
            )

            evaluateFuzzyMatch(item: &inbound, existingQSOs: existingQSOs)
            inboundItems.insert(inbound, at: 0)
        }
        lastMessage = "Imported \(records.count) record(s) from \(url.lastPathComponent)"
    }

    // MARK: - Vision OCR Text Recognition

    public func performVisionOCR(on data: Data) async -> String {
        guard let image = NSImage(data: data), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ""
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest { req, error in
                    guard error == nil, let observations = req.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: "")
                        return
                    }

                    let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                    continuation.resume(returning: text)
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
            }
        }
    }

    // MARK: - Heuristic & Regex Metadata Extraction

    public struct ExtractedMetadata {
        public var callsign: String = ""
        public var date: String = ""
        public var time: String = ""
        public var band: String = ""
        public var mode: String = ""
        public var rst: String = ""
    }

    public func extractQSOMetadata(fromText text: String, filename: String = "") -> ExtractedMetadata {
        var meta = ExtractedMetadata()
        let combined = "\(filename)\n\(text)"

        // 1. Callsign extraction:
        // Look for patterns like "from W1AW", "call: EP2LMA", "QSO with JA1ZLO", or standard callsign format
        let callsignRegexes = [
            #"(?:eQSL|QSL|from|with|call|station|callsign)[:\s]+([A-Z0-9]{1,3}\/[A-Z0-9]+|[A-Z0-9]{1,2}[0-9][A-Z0-9]{1,4}(?:\/[A-Z0-9]+)?)"#,
            #"\b([A-Z]{1,2}[0-9][A-Z]{1,4}(?:\/[A-Z0-9]+)?)\b"#
        ]

        for pattern in callsignRegexes {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)) {
                let range = Range(match.range(at: 1), in: combined)
                if let range {
                    let candidate = String(combined[range]).uppercased()
                    // Filter out common english words that look like calls (e.g. "QSL", "FROM", "DATE")
                    if !["QSL", "FROM", "DATE", "TIME", "BAND", "MODE", "INFO", "USER", "CARD", "EQSL"].contains(candidate) {
                        meta.callsign = candidate
                        break
                    }
                }
            }
        }

        // 2. Date extraction (YYYY-MM-DD or YYYYMMDD or DD/MM/YYYY):
        let datePatterns = [
            #"\b(20[0-9]{2})[-/.](0[1-9]|1[0-2])[-/.](0[1-9]|[12][0-9]|3[01])\b"#, // 2026-09-05
            #"\b(0[1-9]|[12][0-9]|3[01])[-/.](0[1-9]|1[0-2])[-/.](20[0-9]{2})\b"#, // 05/09/2026
            #"\b(20[0-9]{2})(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])\b"#           // 20260905
        ]

        for p in datePatterns {
            if let regex = try? NSRegularExpression(pattern: p),
               let match = regex.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)) {
                if let fullRange = Range(match.range(at: 0), in: combined) {
                    let raw = String(combined[fullRange]).replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "/", with: "").replacingOccurrences(of: ".", with: "")
                    if raw.count == 8 {
                        meta.date = raw
                        break
                    }
                }
            }
        }

        // 3. Time extraction (HH:MM or HHMM with context/colon):
        let timePatterns = [
            #"(?:time|at|qso\s*time)[:\s]+([01][0-9]|2[0-3]):?([0-5][0-9])"#,
            #"\b([01][0-9]|2[0-3]):([0-5][0-9])(?:\s*UTC|\s*Z)?\b"#,
            #"\b([01][0-9]|2[0-3])([0-5][0-9])\s*(?:UTC|Z)\b"#
        ]
        for tp in timePatterns {
            if let regex = try? NSRegularExpression(pattern: tp, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)) {
                if let hRange = Range(match.range(at: 1), in: combined),
                   let mRange = Range(match.range(at: 2), in: combined) {
                    meta.time = "\(combined[hRange])\(combined[mRange])"
                    break
                }
            }
        }

        // 4. Band extraction:
        let bandPattern = #"\b(160M|80M|60M|40M|30M|20M|17M|15M|12M|10M|6M|2M|70CM)\b"#
        if let regex = try? NSRegularExpression(pattern: bandPattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)) {
            if let range = Range(match.range(at: 1), in: combined) {
                meta.band = String(combined[range]).uppercased()
            }
        }

        // 5. Mode extraction:
        let modePattern = #"\b(FT8|FT4|CW|SSB|USB|LSB|RTTY|PSK31|JS8|FM|AM)\b"#
        if let regex = try? NSRegularExpression(pattern: modePattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)) {
            if let range = Range(match.range(at: 1), in: combined) {
                meta.mode = String(combined[range]).uppercased()
            }
        }

        // 6. RST report:
        let rstPattern = #"\b([+-][0-9]{2}|599|59|579|559)\b"#
        if let regex = try? NSRegularExpression(pattern: rstPattern),
           let match = regex.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)) {
            if let range = Range(match.range(at: 1), in: combined) {
                meta.rst = String(combined[range])
            }
        }

        return meta
    }

    // MARK: - Smart Fuzzy Matching with Time Drift Tolerance

    func evaluateFuzzyMatch(
        item: inout QSLInboundItem,
        existingQSOs: [QSORecordModel],
        timeToleranceMinutes: Double = 15.0
    ) {
        guard !item.callsign.isEmpty else {
            item.status = .pending
            item.matchConfidence = 0
            return
        }

        let cleanTargetCall = item.callsign.uppercased()
        let cleanBase = cleanTargetCall.components(separatedBy: "/").first { $0.count >= 3 } ?? cleanTargetCall

        // Filter potential candidates by callsign
        let candidates = existingQSOs.filter { qso in
            let localCall = qso["CALL"].uppercased()
            let localBase = localCall.components(separatedBy: "/").first { $0.count >= 3 } ?? localCall
            return localCall == cleanTargetCall || localBase == cleanBase
        }

        guard !candidates.isEmpty else {
            item.status = .pending
            item.matchConfidence = 0
            return
        }

        var bestMatch: QSORecordModel? = nil
        var bestScore: Int = 0
        var detectedDiffs: [QSLConflictDiff] = []

        for qso in candidates {
            var score = 40 // Base callsign match

            // Band match
            let localBand = qso["BAND"].uppercased()
            if !item.band.isEmpty {
                if localBand == item.band {
                    score += 25
                } else if localBand.contains(item.band) || item.band.contains(localBand) {
                    score += 15
                }
            } else {
                score += 10
            }

            // Mode match
            let localMode = qso["MODE"].uppercased()
            if !item.mode.isEmpty {
                if localMode == item.mode {
                    score += 15
                } else if isEquivalentMode(localMode, item.mode) {
                    score += 12
                }
            } else {
                score += 5
            }

            // Date & Time match with drift tolerance
            let localDate = qso["QSO_DATE"].replacingOccurrences(of: "-", with: "")
            let inboundDate = item.qsoDate.replacingOccurrences(of: "-", with: "")

            if !inboundDate.isEmpty && localDate == inboundDate {
                score += 10
            }

            // Time difference evaluation
            let timeDiffMinutes = calculateTimeDifferenceMinutes(local: qso["TIME_ON"], inbound: item.qsoTime)
            if let diff = timeDiffMinutes {
                if diff <= 2.0 {
                    score += 15
                } else if diff <= timeToleranceMinutes {
                    score += 10
                } else if diff <= timeToleranceMinutes * 2.0 {
                    score += 5
                }
            }

            if score > bestScore {
                bestScore = score
                bestMatch = qso

                // Detect subtle differences
                detectedDiffs.removeAll()
                if !item.mode.isEmpty && localMode != item.mode && !isEquivalentMode(localMode, item.mode) {
                    detectedDiffs.append(QSLConflictDiff(fieldName: "MODE", localValue: localMode, inboundValue: item.mode))
                }
                if let diff = timeDiffMinutes, diff > 3.0 && diff <= timeToleranceMinutes * 2.0 {
                    detectedDiffs.append(QSLConflictDiff(
                        fieldName: "TIME_ON",
                        localValue: qso["TIME_ON"],
                        inboundValue: "\(item.qsoTime) (Δ \(Int(diff))m)"
                    ))
                }
                if !item.rst.isEmpty && !qso["RST_RCVD"].isEmpty && qso["RST_RCVD"] != item.rst {
                    detectedDiffs.append(QSLConflictDiff(fieldName: "RST_RCVD", localValue: qso["RST_RCVD"], inboundValue: item.rst))
                }
            }
        }

        item.matchConfidence = min(100, bestScore)
        if let matched = bestMatch, bestScore >= 60 {
            item.matchedQSOID = matched.id
            if detectedDiffs.isEmpty {
                item.status = .matched
            } else {
                item.status = .conflict
                item.conflictDiffs = detectedDiffs
            }
        } else {
            item.status = .pending
        }
    }

    private func isEquivalentMode(_ a: String, _ b: String) -> Bool {
        let digi = ["FT8", "FT4", "JS8", "RTTY", "DATA"]
        let phone = ["SSB", "USB", "LSB"]
        if digi.contains(a) && digi.contains(b) { return true }
        if phone.contains(a) && phone.contains(b) { return true }
        return false
    }

    private func calculateTimeDifferenceMinutes(local: String, inbound: String) -> Double? {
        let cleanLocal = local.replacingOccurrences(of: ":", with: "")
        let cleanInbound = inbound.replacingOccurrences(of: ":", with: "")

        guard cleanLocal.count >= 4, cleanInbound.count >= 4 else { return nil }

        guard let localH = Int(cleanLocal.prefix(2)),
              let localM = Int(cleanLocal.dropFirst(2).prefix(2)),
              let inH = Int(cleanInbound.prefix(2)),
              let inM = Int(cleanInbound.dropFirst(2).prefix(2)) else {
            return nil
        }

        let localTotalMinutes = localH * 60 + localM
        let inTotalMinutes = inH * 60 + inM

        let diff = abs(localTotalMinutes - inTotalMinutes)
        // Handle midnight wraparound (e.g. 23:55 to 00:05)
        return Double(min(diff, 1440 - diff))
    }

    // MARK: - Save Card Media File

    public func saveMediaFile(data: Data, preferredName: String) -> URL {
        createMediaStorageDirectoryIfNeeded()
        let safeName = preferredName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        let dest = mediaArchiveDirectoryURL.appendingPathComponent(safeName)
        try? data.write(to: dest)
        return dest
    }

    // MARK: - MIME Parser Helper

    private func parseMIME(content: String, rawData: Data) -> (body: String, attachment: Data?, filename: String) {
        var body = ""
        var attachmentData: Data? = nil
        var filename = ""

        // Check if multipart with boundary
        if let boundaryRange = content.range(of: "boundary=\"") ?? content.range(of: "boundary=") {
            let rest = content[boundaryRange.upperBound...]
            let boundary = rest.components(separatedBy: CharacterSet(charactersIn: "\"\r\n ;")).first ?? ""
            if !boundary.isEmpty {
                let parts = content.components(separatedBy: "--\(boundary)")
                for part in parts {
                    let lowerPart = part.lowercased()
                    if lowerPart.contains("content-type: text/plain") {
                        if let bodyStart = part.range(of: "\r\n\r\n") ?? part.range(of: "\n\n") {
                            body = String(part[bodyStart.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } else if lowerPart.contains("image/") || lowerPart.contains(".jpg") || lowerPart.contains(".png") || lowerPart.contains(".pdf") {
                        // Extract filename
                        if let nameRange = part.range(of: "filename=\"") {
                            let nameRest = part[nameRange.upperBound...]
                            filename = nameRest.components(separatedBy: "\"").first ?? ""
                        }

                        // Extract base64
                        if let b64Start = part.range(of: "\r\n\r\n") ?? part.range(of: "\n\n") {
                            var b64Str = String(part[b64Start.upperBound...])
                                .replacingOccurrences(of: "\r", with: "")
                                .replacingOccurrences(of: "\n", with: "")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            while b64Str.hasSuffix("-") {
                                b64Str.removeLast()
                            }
                            b64Str = b64Str.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let decoded = Data(base64Encoded: b64Str, options: [.ignoreUnknownCharacters]), decoded.count > 50 {
                                attachmentData = decoded
                            }
                        }
                    }
                }
            }
        }

        if body.isEmpty {
            // Fallback: take header-free text
            if let headerEnd = content.range(of: "\r\n\r\n") ?? content.range(of: "\n\n") {
                body = String(content[headerEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                body = content
            }
        }

        return (body, attachmentData, filename)
    }

    // MARK: - Basic ADIF Parser Helper

    private func parseADIFText(_ text: String) -> [[String: String]] {
        var records: [[String: String]] = []
        let upper = text.uppercased()
        guard let eohRange = upper.range(of: "<EOH>") else {
            return []
        }

        let body = text[eohRange.upperBound...]
        let rawRecords = body.components(separatedBy: "<EOR>")

        for raw in rawRecords {
            var record: [String: String] = [:]
            let tags = raw.components(separatedBy: "<")
            for tag in tags where tag.contains(":") && tag.contains(">") {
                let parts = tag.components(separatedBy: ">")
                guard parts.count >= 2 else { continue }
                let tagHeader = parts[0]
                let tagValue = parts[1]
                let tagHeaderParts = tagHeader.components(separatedBy: ":")
                let fieldName = tagHeaderParts[0].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).uppercased()
                if let len = Int(tagHeaderParts[1]) {
                    record[fieldName] = String(tagValue.prefix(len)).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                }
            }
            if !record.isEmpty {
                records.append(record)
            }
        }
        return records
    }
}
