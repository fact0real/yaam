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

struct QSLCardStationInfo {
    let callsign: String
    let grid: String
    let radio: String
    let antenna: String
    let powerWatts: Int
}

enum QSLCardRenderer {
    private static let templateResourceName = "EP2AES_QSL_Card_HQ"
    private static let fallbackTemplateURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("EP2AES_QSL_Card_HQ.pdf")

    static func render(record: QSORecordModel, station: QSLCardStationInfo) -> NSImage {
        let page = templatePage()
        let size = page?.bounds(for: .mediaBox).size ?? CGSize(width: 1600, height: 1000)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        if let page, let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            page.draw(with: .mediaBox, to: context)
            context.restoreGState()
        } else {
            drawFallbackTemplate(in: CGRect(origin: .zero, size: size), station: station)
        }

        drawStationFlag(in: CGRect(origin: .zero, size: size))
        drawQSOFields(record: record, in: CGRect(origin: .zero, size: size))
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
        let bundledURL = Bundle.main.url(forResource: templateResourceName, withExtension: "pdf")
        let templateUrl = bundledURL ?? (FileManager.default.fileExists(atPath: fallbackTemplateURL.path) ? fallbackTemplateURL : nil)
        
        guard let templateUrl, let templateDoc = PDFDocument(url: templateUrl) else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        let frontPage = templateDoc.page(at: 0)
        let backPage = templateDoc.pageCount > 1 ? templateDoc.page(at: 1) : nil
        let pageSize = (backPage ?? frontPage)?.bounds(for: .mediaBox).size ?? CGSize(width: 780, height: 482)
        let frontImage = renderPDFPage(page: frontPage, size: pageSize)
        let backImage = renderPDFPage(page: backPage, size: pageSize) { rect in
            if backPage == nil {
                drawFallbackTemplate(in: rect, station: station)
            }
            drawStationFlag(in: rect)
            drawQSOFields(record: record, in: rect)
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

    private static func templatePage() -> PDFPage? {
        let bundledURL = Bundle.main.url(forResource: templateResourceName, withExtension: "pdf")
        let url = bundledURL ?? (FileManager.default.fileExists(atPath: fallbackTemplateURL.path) ? fallbackTemplateURL : nil)
        guard let url, let document = PDFDocument(url: url) else { return nil }
        let templatePageIndex = document.pageCount > 1 ? 1 : 0
        return document.page(at: templatePageIndex)
    }

    fileprivate static func drawQSOFields(record: QSORecordModel, in rect: CGRect) {
        let qso = QSLCardQSO(record: record)
        let height = rect.height
        let rowY: CGFloat = 0.500

        // Callsign (Higher position)
        draw(qso.callDisplay, x: 0.030, y: 0.535, width: 0.175, height: 0.050, in: rect, size: (height * 0.038) + 4, weight: .bold)
        
        // Name (Below callsign)
        draw(qso.name, x: 0.030, y: 0.495, width: 0.175, height: 0.030, in: rect, size: (height * 0.020) + 2, weight: .medium, color: .darkGray)

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

        // Station Details (Shifted right and +3 size bigger)
        let infoFontSize = (height * 0.020) + 6
        draw("ICOM-7300", x: 0.170, y: 0.345, width: 0.250, height: 0.040, in: rect, size: infoFontSize, weight: .bold, alignment: .left)
        draw("Fan Dipole @7m", x: 0.100, y: 0.305, width: 0.300, height: 0.040, in: rect, size: infoFontSize, weight: .bold, alignment: .left)
        draw("25W", x: 0.480, y: 0.305, width: 0.150, height: 0.040, in: rect, size: infoFontSize, weight: .bold, alignment: .left)
    }

    fileprivate static func drawStationFlag(in rect: CGRect) {
        draw("🇮🇷", x: 0.215, y: 0.870, width: 0.070, height: 0.080, in: rect, size: rect.height * 0.066, weight: .regular)
    }

    fileprivate static func drawFallbackTemplate(in rect: CGRect, station: QSLCardStationInfo) {
        NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.95, alpha: 1).setFill()
        NSBezierPath(rect: rect).fill()
        NSColor.black.setStroke()
        let border = NSBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.035, dy: rect.height * 0.045), xRadius: 10, yRadius: 10)
        border.lineWidth = 3
        border.stroke()

        draw("AMATEUR RADIO STATION", x: 0.08, y: 0.09, width: 0.40, height: 0.06, in: rect, size: rect.height * 0.028, weight: .bold, alignment: .left)
        draw(station.callsign.uppercased(), x: 0.08, y: 0.15, width: 0.40, height: 0.10, in: rect, size: rect.height * 0.07, weight: .heavy, alignment: .left)
        draw("CONFIRMING OUR QSO", x: 0.18, y: 0.45, width: 0.64, height: 0.06, in: rect, size: rect.height * 0.032, weight: .bold)
        draw("TO RADIO        DATE        UTC TIME        FREQUENCY        MODE        SIGNAL RST", x: 0.12, y: 0.535, width: 0.78, height: 0.035, in: rect, size: rect.height * 0.018)
        draw("QTH: Tehran, Iran     GRID: \(station.grid.uppercased())     CQ ZONE: 21     ITU ZONE: 40", x: 0.16, y: 0.675, width: 0.68, height: 0.04, in: rect, size: rect.height * 0.02)
        draw("THANK YOU FOR THE QSO!     73 PSE QSL TNX", x: 0.20, y: 0.88, width: 0.60, height: 0.05, in: rect, size: rect.height * 0.026, weight: .bold)
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

struct QSLCardComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    @AppStorage("stationGrid") private var stationGrid = ""
    @AppStorage("radioModel") private var radioModel = ""
    @AppStorage("radioPowerWatts") private var radioPowerWatts = 100
    @AppStorage("antennaDescription") private var antennaDescription = ""

    @State private var previewImage: NSImage?
    @State private var statusMessage = ""

    private var station: QSLCardStationInfo {
        let profile = appState.activeStationProfile
        let call = appState.currentStationCallsign == "DEFAULT" ? "NOCALL" : appState.currentStationCallsign

        return QSLCardStationInfo(
            callsign: call,
            grid: profile?.normalizedGrid ?? stationGrid,
            radio: profile?.radioModel ?? radioModel,
            antenna: profile?.antennaDescription ?? antennaDescription,
            powerWatts: profile?.powerWatts ?? radioPowerWatts
        )
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
        .frame(width: 980, height: 720)
        .onAppear(perform: renderPreview)
        .onChange(of: appState.selectedQSLCardQSO?.id) { _, _ in renderPreview() }
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

class QSLBackPage: PDFPage {
    let originalPage: PDFPage
    let record: QSORecordModel
    let station: QSLCardStationInfo
    
    init(originalPage: PDFPage, record: QSORecordModel, station: QSLCardStationInfo) {
        self.originalPage = originalPage
        self.record = record
        self.station = station
        super.init()
    }
    
    override func bounds(for box: PDFDisplayBox) -> NSRect {
        originalPage.bounds(for: box)
    }
    
    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        // Draw the original template page
        originalPage.draw(with: box, to: context)
        
        // Draw QSO fields on top
        let previousContext = NSGraphicsContext.current
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        
        QSLCardRenderer.drawQSOFields(record: record, in: originalPage.bounds(for: box))
        QSLCardRenderer.drawStationFlag(in: originalPage.bounds(for: box))
        
        NSGraphicsContext.current = previousContext
    }
}

class QSLFallbackBackPage: PDFPage {
    let station: QSLCardStationInfo
    let record: QSORecordModel
    
    init(station: QSLCardStationInfo, record: QSORecordModel) {
        self.station = station
        self.record = record
        super.init()
    }
    
    override func bounds(for box: PDFDisplayBox) -> NSRect {
        return NSRect(x: 0, y: 0, width: 1600, height: 1000)
    }
    
    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        let previousContext = NSGraphicsContext.current
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        
        let rect = bounds(for: box)
        QSLCardRenderer.drawFallbackTemplate(in: rect, station: station)
        QSLCardRenderer.drawStationFlag(in: rect)
        QSLCardRenderer.drawQSOFields(record: record, in: rect)
        
        NSGraphicsContext.current = previousContext
    }
}
