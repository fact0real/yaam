//
//  QSLCardView.swift
//  YAAM
//
//  Created by Codex on 8/16/26.
//

import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

enum QSLCardRenderer {
    static func render(record: QSORecordModel, station: QSLCardStationInfo) -> NSImage {
        let size = CGSize(width: 1600, height: 1000)
        let image = NSImage(size: size)
        image.lockFocus()
        let rect = CGRect(origin: .zero, size: size)
        drawFallbackTemplate(in: rect, station: station)
        drawStationFlag(in: rect, station: station)
        drawQSOFields(record: record, station: station, in: rect)
        image.unlockFocus()

        return image
    }

    static func exportPNG(record: QSORecordModel, station: QSLCardStationInfo, to url: URL) throws {
        let image = render(record: record, station: station)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }

        try data.write(to: url, options: .atomic)
    }

    static func exportPDF(record: QSORecordModel, station: QSLCardStationInfo, to url: URL) throws {
        let pageSize = CGSize(width: 780, height: 488)
        let frontImage = renderPDFPage(page: nil, size: pageSize) { rect in
            drawFront(in: rect, station: station)
        }
        let backImage = renderPDFPage(page: nil, size: pageSize) { rect in
            drawFallbackTemplate(in: rect, station: station)
            drawStationFlag(in: rect, station: station)
            drawQSOFields(record: record, station: station, in: rect)
        }

        guard writeCompressedPDF(images: [frontImage, backImage], pageSize: pageSize, to: url) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    static func defaultFileName(for record: QSORecordModel, stationCallsign: String) -> String {
        let myCall = cleanFileComponent(stationCallsign.isEmpty ? "QSL" : stationCallsign.uppercased())
        let theirCall = cleanFileComponent(record["CALL"].isEmpty ? "CONTACT" : record["CALL"].uppercased())
        let date = cleanFileComponent(record["QSO_DATE"].isEmpty ? "DATE" : record["QSO_DATE"])
        return "\(myCall)_QSL_\(theirCall)_\(date).png"
    }

    fileprivate static func drawQSOFields(record: QSORecordModel, station: QSLCardStationInfo, in rect: CGRect) {
        let qso = QSLCardQSO(record: record)
        let height = rect.height
        let rowY: CGFloat = 0.500

        // Callsign (Higher position)
        draw(qso.callDisplay, x: 0.030, y: rowY, width: 0.175, height: 0.050, in: rect, size: (height * 0.038) + 4, weight: .bold)
        
        // Name (Below callsign)
        draw(qso.name, x: 0.030, y: 0.455, width: 0.175, height: 0.030, in: rect, size: (height * 0.020) + 2, weight: .medium, color: .darkGray)

        // Date
        draw(qso.date, x: 0.210, y: rowY, width: 0.150, height: 0.052, in: rect, size: (height * 0.030) + 2, weight: .bold)

        // UTC Time
        draw(qso.time, x: 0.360, y: rowY, width: 0.150, height: 0.052, in: rect, size: (height * 0.030) + 2, weight: .bold)

        // Frequency
        draw(qso.frequency, x: 0.505, y: rowY, width: 0.110, height: 0.052, in: rect, size: (height * 0.030) + 2, weight: .bold)

        // Mode
        draw(qso.mode, x: 0.695, y: rowY, width: 0.090, height: 0.052, in: rect, size: (height * 0.030) + 2, weight: .bold)

        // Signal RST
        draw(qso.rst, x: 0.820, y: rowY, width: 0.115, height: 0.060, in: rect, size: (height * 0.030) + 2, weight: .bold)

        // Station Details (Dynamically populated from Station Profile)
        let infoFontSize = (height * 0.020) + 6
        let radioClean = station.radio.trimmingCharacters(in: .whitespacesAndNewlines)
        let radioText = radioClean.isEmpty ? "" : "RADIO: \(radioClean)"

        let antennaClean = station.antenna.trimmingCharacters(in: .whitespacesAndNewlines)
        let antennaBase = antennaClean
        let antennaText = !antennaBase.isEmpty && station.antennaHeightMeters > 0 ? "ANT: \(antennaBase) @\(station.antennaHeightMeters)m" : antennaBase

        let powerText = station.powerWatts > 0 ? "POWER: \(station.powerWatts) W" : ""

        draw(radioText, x: 0.170, y: 0.345, width: 0.250, height: 0.040, in: rect, size: infoFontSize, weight: .bold, alignment: .left)
        draw(antennaText, x: 0.100, y: 0.305, width: 0.300, height: 0.040, in: rect, size: infoFontSize, weight: .bold, alignment: .left)
        draw(powerText, x: 0.480, y: 0.305, width: 0.150, height: 0.040, in: rect, size: infoFontSize, weight: .bold, alignment: .left)
    }

    fileprivate static func drawStationFlag(in rect: CGRect, station: QSLCardStationInfo) {
        draw(station.flag, x: 0.80, y: 0.78, width: 0.10, height: 0.10, in: rect, size: rect.height * 0.066)
    }

    private static func drawBackground(in rect: CGRect) {
        NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.95, alpha: 1).setFill()
        NSBezierPath(rect: rect).fill()
        NSColor.black.setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.035, dy: rect.height * 0.045), xRadius: 10, yRadius: 10)
        border.lineWidth = 3
        border.stroke()
    }

    private static func drawFront(in rect: CGRect, station: QSLCardStationInfo) {
        drawBackground(in: rect)
        draw("AMATEUR RADIO STATION", x: 0.08, y: 0.72, width: 0.84, height: 0.06, in: rect, size: rect.height * 0.035, weight: .bold)
        draw(station.callsign.uppercased(), x: 0.08, y: 0.50, width: 0.84, height: 0.16, in: rect, size: rect.height * 0.12, weight: .heavy)
        draw(station.locationLine, x: 0.08, y: 0.34, width: 0.84, height: 0.06, in: rect, size: rect.height * 0.025)
        draw("73 · THANK YOU FOR THE QSO", x: 0.08, y: 0.16, width: 0.84, height: 0.06, in: rect, size: rect.height * 0.03, weight: .bold)
        drawStationFlag(in: rect, station: station)
    }

    fileprivate static func drawFallbackTemplate(in rect: CGRect, station: QSLCardStationInfo) {
        drawBackground(in: rect)
        draw("AMATEUR RADIO STATION", x: 0.08, y: 0.86, width: 0.64, height: 0.05, in: rect, size: rect.height * 0.028, weight: .bold, alignment: .left)
        draw(station.callsign.uppercased(), x: 0.08, y: 0.75, width: 0.64, height: 0.10, in: rect, size: rect.height * 0.07, weight: .heavy, alignment: .left)
        draw(station.locationLine, x: 0.08, y: 0.68, width: 0.84, height: 0.05, in: rect, size: rect.height * 0.022, alignment: .left)
        let columns: [(String, CGFloat, CGFloat)] = [
            ("TO RADIO", 0.03, 0.175), ("DATE", 0.21, 0.15), ("UTC TIME", 0.36, 0.15),
            ("MHz", 0.505, 0.11), ("MODE", 0.695, 0.09), ("RST", 0.82, 0.115)
        ]
        for (title, x, width) in columns {
            draw(title, x: x, y: 0.58, width: width, height: 0.04, in: rect, size: rect.height * 0.022, weight: .bold)
        }
        draw("CONFIRMING OUR QSO · 73 PSE QSL TNX", x: 0.08, y: 0.12, width: 0.84, height: 0.06, in: rect, size: rect.height * 0.028, weight: .bold)
    }

    private static func draw(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        in rect: CGRect,
        size: CGFloat? = nil,
        weight: NSFont.Weight = .regular,
        color: NSColor = .black,
        alignment: NSTextAlignment = .center
    ) {
        guard !text.isEmpty else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail

        let fontSize = max(9, size ?? rect.height * 0.021)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        let target = CGRect(
            x: rect.minX + rect.width * x,
            y: rect.minY + rect.height * y,
            width: rect.width * width,
            height: rect.height * height
        )
        NSString(string: text).draw(in: target, withAttributes: attributes)
    }

    static func cleanFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }.reduce("") { $0 + String($1) }
    }

    private static func renderPDFPage(
        page: PDFPage?,
        size: CGSize,
        dpi: CGFloat = 110,
        overlay: ((CGRect) -> Void)? = nil
    ) -> NSImage {
        let scale = dpi / 72
        let image = NSImage(size: CGSize(width: size.width * scale, height: size.height * scale))
        let rect = CGRect(origin: .zero, size: size)

        image.lockFocus()
        NSColor.white.setFill()
        CGRect(origin: .zero, size: image.size).fill()

        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.scaleBy(x: scale, y: scale)
            context.interpolationQuality = .high
            page?.draw(with: .mediaBox, to: context)
            overlay?(rect)
            context.restoreGState()
        }

        image.unlockFocus()
        return image
    }

    private static func writeCompressedPDF(images: [NSImage], pageSize: CGSize, to url: URL) -> Bool {
        struct PDFImagePage {
            let data: Data
            let width: Int
            let height: Int
        }

        let jpegPages = images.compactMap { image -> PDFImagePage? in
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.78]) else {
                return nil
            }
            return PDFImagePage(data: jpegData, width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }

        guard jpegPages.count == images.count else {
            return false
        }

        let objectCount = 2 + (jpegPages.count * 3)
        var pdfData = Data()
        var offsets = Array(repeating: 0, count: objectCount + 1)

        func append(_ string: String) {
            pdfData.append(Data(string.utf8))
        }

        func beginObject(_ number: Int) {
            offsets[number] = pdfData.count
            append("\(number) 0 obj\n")
        }

        append("%PDF-1.4\n% YAAM compact QSL PDF\n")

        beginObject(1)
        append("<< /Type /Catalog /Pages 2 0 R >>\nendobj\n")

        let pageObjectNumbers = (0..<jpegPages.count).map { 3 + ($0 * 3) }
        beginObject(2)
        append("<< /Type /Pages /Count \(jpegPages.count) /Kids [\(pageObjectNumbers.map { "\($0) 0 R" }.joined(separator: " "))] >>\nendobj\n")

        for (index, page) in jpegPages.enumerated() {
            let pageObject = 3 + (index * 3)
            let contentObject = pageObject + 1
            let imageObject = pageObject + 2
            let imageName = "Im\(index + 1)"
            let content = "q\n\(pageSize.width) 0 0 \(pageSize.height) 0 0 cm\n/\(imageName) Do\nQ\n"

            beginObject(pageObject)
            append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(pageSize.width) \(pageSize.height)] /Resources << /XObject << /\(imageName) \(imageObject) 0 R >> >> /Contents \(contentObject) 0 R >>\nendobj\n")

            beginObject(contentObject)
            append("<< /Length \(content.utf8.count) >>\nstream\n")
            append(content)
            append("endstream\nendobj\n")

            beginObject(imageObject)
            append("<< /Type /XObject /Subtype /Image /Width \(page.width) /Height \(page.height) /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length \(page.data.count) >>\nstream\n")
            pdfData.append(page.data)
            append("\nendstream\nendobj\n")
        }

        let xrefOffset = pdfData.count
        append("xref\n0 \(objectCount + 1)\n")
        append("0000000000 65535 f \n")
        for objectNumber in 1...objectCount {
            append(String(format: "%010d 00000 n \n", offsets[objectNumber]))
        }
        append("trailer\n<< /Size \(objectCount + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n")

        do {
            try pdfData.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

private struct QSLCardQSO {
    let call: String
    let date: String
    let time: String
    let frequency: String
    let mode: String
    let rst: String
    let band: String
    let name: String
    let qth: String
    let country: String
    let theirGrid: String
    let comment: String

    var callDisplay: String {
        let flag = countryFlag
        return flag.isEmpty ? call : "\(flag) \(call)"
    }

    var countryFlag: String {
        guard !country.isEmpty else { return "" }
        let flag = countryToFlag(country)
        return flag == "🌐" ? "" : flag
    }

    var locationSummary: String {
        [qth, country].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var detailLine: String {
        let namePart = name.isEmpty ? "" : name
        let locationPart = locationSummary.isEmpty ? "" : locationSummary
        let gridPart = theirGrid.isEmpty ? "" : "GRID \(theirGrid)"
        let bandPart = band.isEmpty ? "" : "BAND \(band)"
        return [namePart, locationPart, gridPart, bandPart].filter { !$0.isEmpty }.joined(separator: "  |  ")
    }

    init(record: QSORecordModel) {
        call = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        date = Self.formattedDate(record["QSO_DATE"])
        time = Self.formattedTime(record["TIME_ON"].isEmpty ? record["TIME_OFF"] : record["TIME_ON"])
        frequency = Self.frequency(record["FREQ"])
        mode = record["MODE"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        band = record["BAND"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        name = record["NAME"].trimmingCharacters(in: .whitespacesAndNewlines)
        qth = record["QTH"].trimmingCharacters(in: .whitespacesAndNewlines)
        country = record["COUNTRY"].trimmingCharacters(in: .whitespacesAndNewlines)
        theirGrid = record["GRIDSQUARE"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        comment = record["COMMENT"].trimmingCharacters(in: .whitespacesAndNewlines)

        let sent = record["RST_SENT"].trimmingCharacters(in: .whitespacesAndNewlines)
        let received = record["RST_RCVD"].trimmingCharacters(in: .whitespacesAndNewlines)
        rst = [sent, received].filter { !$0.isEmpty }.joined(separator: "/")
    }

    private static func formattedDate(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count == 8 else { return clean }
        return "\(clean.prefix(4))-\(clean.dropFirst(4).prefix(2))-\(clean.suffix(2))"
    }

    private static func formattedTime(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = clean.filter { $0.isNumber }
        guard digits.count >= 4 else { return clean }
        let hours = digits.prefix(2)
        let minutes = digits.dropFirst(2).prefix(2)
        return "\(hours):\(minutes)"
    }

    private static func frequency(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "MHz", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let freqDouble = Double(clean) else { return clean }
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: freqDouble)) ?? clean
    }
}

#if !STANDALONE_PRIVACY_TEST
struct QSLCardComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @State private var previewImage: NSImage?
    @State private var statusMessage = ""

    private var station: QSLCardStationInfo {
        let profile = appState.activeStationProfile
        let call = appState.currentStationCallsign == "DEFAULT" ? "NOCALL" : appState.currentStationCallsign

        return QSLCardStationInfo(callsign: call, profile: profile)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("QSL Card Preview", systemImage: "postcard")
                    .font(.headline)
                Spacer()
                Button("Close") { dismiss() }
            }

            if let record = appState.selectedQSLCardQSO {
                let qso = QSLCardQSO(record: record)

                HStack(spacing: 10) {
                    Text(qso.callDisplay)
                        .font(.title3.bold())
                    Text("\(qso.date)  \(qso.time) UTC")
                        .foregroundColor(.secondary)
                    Text("\(record["BAND"]) / \(record["MODE"])")
                        .foregroundColor(.blue)
                }

                if let previewImage {
                    Image(nsImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 520)
                        .background(Color(NSColor.textBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                } else {
                    ProgressView("Rendering QSL card...")
                        .frame(maxWidth: .infinity, minHeight: 320)
                }

                HStack {
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if !record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: {
                            dismiss()
                            appState.openQSLCardEmailComposer(for: record)
                        }) {
                            Label("Email QSL Card", systemImage: "envelope.badge")
                        }
                    }

                    Button(action: { exportPDF(record: record) }) {
                        Label("Export PDF (2 Pages)", systemImage: "doc.richtext")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: { export(record: record) }) {
                        Label("Export PNG (Back Only)", systemImage: "photo")
                    }
                }
            } else {
                Text("No QSO selected.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .padding(18)
        .frame(
            minWidth: 840,
            idealWidth: 1080,
            maxWidth: .infinity,
            minHeight: 620,
            idealHeight: 780,
            maxHeight: .infinity
        )
        .resizablePresentation(minWidth: 840, minHeight: 620)
        .onAppear(perform: renderPreview)
        .onChange(of: appState.selectedQSLCardQSO?.id) { _, _ in renderPreview() }
        .onChange(of: appState.activeStationProfile) { _, _ in renderPreview() }
        .onChange(of: appState.currentStationCallsign) { _, _ in renderPreview() }
    }

    private func renderPreview() {
        guard let record = appState.selectedQSLCardQSO else {
            previewImage = nil
            return
        }

        previewImage = QSLCardRenderer.render(record: record, station: station)
    }

    private func export(record: QSORecordModel) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = QSLCardRenderer.defaultFileName(for: record, stationCallsign: station.callsign)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try QSLCardRenderer.exportPNG(record: record, station: station, to: url)
            statusMessage = "Saved: \(url.lastPathComponent)"
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func exportPDF(record: QSORecordModel) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let baseName = QSLCardRenderer.defaultFileName(for: record, stationCallsign: station.callsign)
        let pdfName = baseName.replacingOccurrences(of: ".png", with: ".pdf")
        panel.nameFieldStringValue = pdfName

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try QSLCardRenderer.exportPDF(record: record, station: station, to: url)
            statusMessage = "Saved PDF: \(url.lastPathComponent)"
        } catch {
            statusMessage = "PDF Export failed: \(error.localizedDescription)"
        }
    }
}
#endif
