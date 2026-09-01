//
//  QSLLabelEngine.swift
//  YAAM
//
//  High-Precision Paper QSL Label Layout & PDF Printing Engine
//  Generates pixel-perfect printable label sheets (Avery 5160, Avery 5163, Zweckform 3474/3422)
//  and single thermal labels with customizable QSO confirmation grids and printer calibration.
//

import AppKit
import Foundation
import PDFKit
import SwiftUI

// MARK: - Standard Label Template Definitions

public enum QSLLabelPaperSize: String, CaseIterable, Identifiable, Sendable {
    case usLetter = "US Letter (8.5 x 11 in)"
    case a4 = "A4 (210 x 297 mm)"

    public var id: String { rawValue }

    public var dimensionsPoints: CGSize {
        switch self {
        case .usLetter:
            return CGSize(width: 8.5 * 72.0, height: 11.0 * 72.0) // 612 x 792 pt
        case .a4:
            return CGSize(width: 595.28, height: 841.89) // 210 x 297 mm
        }
    }
}

public struct QSLLabelTemplate: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let paperSize: QSLLabelPaperSize
    public let columns: Int
    public let rows: Int
    public let labelWidthPt: CGFloat
    public let labelHeightPt: CGFloat
    public let marginTopPt: CGFloat
    public let marginLeftPt: CGFloat
    public let horizontalGapPt: CGFloat
    public let verticalGapPt: CGFloat

    public var labelsPerPage: Int { columns * rows }

    public static let standardTemplates: [QSLLabelTemplate] = [
        // Avery 5160 / 8160 (3 cols x 10 rows = 30 labels / Letter)
        QSLLabelTemplate(
            id: "avery_5160",
            name: "Avery 5160 / 8160 (30 labels - 2.625\" x 1\")",
            paperSize: .usLetter,
            columns: 3,
            rows: 10,
            labelWidthPt: 2.625 * 72.0,  // 189 pt
            labelHeightPt: 1.0 * 72.0,   // 72 pt
            marginTopPt: 0.5 * 72.0,     // 36 pt
            marginLeftPt: 0.1875 * 72.0, // 13.5 pt
            horizontalGapPt: 0.125 * 72.0, // 9 pt
            verticalGapPt: 0.0
        ),

        // Avery 5163 / 8163 (2 cols x 5 rows = 10 labels / Letter)
        QSLLabelTemplate(
            id: "avery_5163",
            name: "Avery 5163 / 8163 (10 labels - 4\" x 2\")",
            paperSize: .usLetter,
            columns: 2,
            rows: 5,
            labelWidthPt: 4.0 * 72.0,    // 288 pt
            labelHeightPt: 2.0 * 72.0,   // 144 pt
            marginTopPt: 0.5 * 72.0,     // 36 pt
            marginLeftPt: 0.156 * 72.0,  // 11.2 pt
            horizontalGapPt: 0.1875 * 72.0, // 13.5 pt
            verticalGapPt: 0.0
        ),

        // Zweckform / Herma 3474 (3 cols x 8 rows = 24 labels / A4)
        QSLLabelTemplate(
            id: "zweckform_3474",
            name: "Zweckform 3474 / Herma 4272 (24 labels - 70 x 37mm)",
            paperSize: .a4,
            columns: 3,
            rows: 8,
            labelWidthPt: 70.0 * 2.83465,  // ~198.4 pt
            labelHeightPt: 37.0 * 2.83465, // ~104.9 pt
            marginTopPt: 0.0,
            marginLeftPt: 0.0,
            horizontalGapPt: 0.0,
            verticalGapPt: 0.0
        ),

        // Zweckform 3422 (2 cols x 6 rows = 12 labels / A4)
        QSLLabelTemplate(
            id: "zweckform_3422",
            name: "Zweckform 3422 (12 labels - 105 x 48mm)",
            paperSize: .a4,
            columns: 2,
            rows: 6,
            labelWidthPt: 105.0 * 2.83465, // ~297.6 pt
            labelHeightPt: 48.0 * 2.83465, // ~136.1 pt
            marginTopPt: 4.5 * 2.83465,
            marginLeftPt: 0.0,
            horizontalGapPt: 0.0,
            verticalGapPt: 0.0
        )
    ]
}

// MARK: - Label Customization Configuration

public struct QSLLabelConfig: Sendable {
    public var template: QSLLabelTemplate = QSLLabelTemplate.standardTemplates[0]
    public var startLabelIndex: Int = 0 // 0-based offset to skip used labels on sheet
    public var stationCallsign: String = "EP2AES"
    public var stationGrid: String = "LN35ir"
    public var stationQTH: String = "Tehran, Iran"
    public var qslConfirmationText: String = "PSE QSL" // or "TNX QSL"
    public var includeBorder: Bool = true
    public var includeMyInfo: Bool = true
    public var includeComment: Bool = true
    public var offsetXPoints: CGFloat = 0.0
    public var offsetYPoints: CGFloat = 0.0

    public init() {}
}

// MARK: - PDF & Print Generation Engine

enum QSLLabelEngine {

    // MARK: - Generate Multi-Page Printable PDF

    static func generatePDF(records: [QSORecordModel], config: QSLLabelConfig) -> PDFDocument {
        let pdfData = NSMutableData()
        let pageSize = config.template.paperSize.dimensionsPoints
        var mediaBox = CGRect(origin: .zero, size: pageSize)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return PDFDocument()
        }

        let labelsPerPage = config.template.labelsPerPage
        var currentRecordIndex = 0
        var isFirstPage = true

        while currentRecordIndex < records.count {
            context.beginPage(mediaBox: &mediaBox)

            // Convert to macOS Cocoa Drawing Coordinates
            let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsContext

            let startIndexOnThisPage = isFirstPage ? config.startLabelIndex : 0
            isFirstPage = false

            for labelSlot in startIndexOnThisPage..<labelsPerPage {
                guard currentRecordIndex < records.count else { break }
                let record = records[currentRecordIndex]

                let col = labelSlot % config.template.columns
                let row = labelSlot / config.template.columns

                let x = config.template.marginLeftPt + CGFloat(col) * (config.template.labelWidthPt + config.template.horizontalGapPt) + config.offsetXPoints
                // In flipped/PDF coordinates, Y starts from top
                let yFromTop = config.template.marginTopPt + CGFloat(row) * (config.template.labelHeightPt + config.template.verticalGapPt) + config.offsetYPoints
                let y = pageSize.height - yFromTop - config.template.labelHeightPt

                let labelRect = CGRect(x: x, y: y, width: config.template.labelWidthPt, height: config.template.labelHeightPt)
                drawSingleQSOLabel(record: record, rect: labelRect, config: config, context: nsContext)

                currentRecordIndex += 1
            }

            NSGraphicsContext.restoreGraphicsState()
            context.endPage()
        }

        context.closePDF()
        return PDFDocument(data: pdfData as Data) ?? PDFDocument()
    }

    // MARK: - Draw Single QSL Label Content

    private static func drawSingleQSOLabel(
        record: QSORecordModel,
        rect: CGRect,
        config: QSLLabelConfig,
        context: NSGraphicsContext?
    ) {
        let insetRect = rect.insetBy(dx: 4.0, dy: 3.0)

        // 1. Draw Border if enabled
        if config.includeBorder {
            let borderPath = NSBezierPath(roundedRect: insetRect, xRadius: 3.0, yRadius: 3.0)
            borderPath.lineWidth = 0.6
            NSColor.lightGray.withAlphaComponent(0.6).setStroke()
            borderPath.stroke()
        }

        // 2. Header Row: To Radio <CALL> · PSE QSL / TNX QSL
        let callsign = (record["CALL"]).uppercased()
        let isConfirmed = record.isConfirmed
        let qslText = isConfirmed ? "TNX QSL" : config.qslConfirmationText

        let headerString = NSMutableAttributedString()
        let callAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 9.5),
            .foregroundColor: NSColor.black
        ]
        let qslAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7.5, weight: .semibold),
            .foregroundColor: isConfirmed ? NSColor(red: 0.1, green: 0.5, blue: 0.2, alpha: 1.0) : NSColor.darkGray
        ]

        headerString.append(NSAttributedString(string: "TO RADIO: ", attributes: [
            .font: NSFont.systemFont(ofSize: 7.0, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]))
        headerString.append(NSAttributedString(string: "\(callsign)   ", attributes: callAttrs))
        headerString.append(NSAttributedString(string: qslText, attributes: qslAttrs))

        headerString.draw(at: CGPoint(x: insetRect.minX + 4.0, y: insetRect.maxY - 12.0))

        // 3. Mini Signal Report Table Box
        let tableTop = insetRect.maxY - 14.0
        let tableRect = CGRect(x: insetRect.minX + 3.0, y: insetRect.minY + 12.0, width: insetRect.width - 6.0, height: tableTop - (insetRect.minY + 12.0))

        let tableBox = NSBezierPath(rect: tableRect)
        tableBox.lineWidth = 0.5
        NSColor.lightGray.withAlphaComponent(0.7).setStroke()
        tableBox.stroke()

        // Table Header & Values
        let dateStr = record["QSO_DATE"]
        let rawTime = record["TIME_ON"]
        let timeStr = rawTime.count >= 4 ? "\(rawTime.prefix(2)):\(rawTime.dropFirst(2).prefix(2))" : rawTime
        let bandStr = record["BAND"].isEmpty ? "\(record["FREQ"])MHz" : record["BAND"]
        let modeStr = record["MODE"]
        let rstStr = record["RST_SENT"].isEmpty ? "599" : record["RST_SENT"]

        let colWidth = tableRect.width / 5.0
        let headers = ["DATE", "TIME (Z)", "BAND", "MODE", "RST"]
        let values = [dateStr, String(timeStr), bandStr, modeStr, rstStr]

        let headerFont = NSFont.systemFont(ofSize: 5.5, weight: .bold)
        let valueFont = NSFont.monospacedSystemFont(ofSize: 7.0, weight: .bold)

        for i in 0..<5 {
            let colX = tableRect.minX + CGFloat(i) * colWidth
            // Header
            let hStr = NSAttributedString(string: headers[i], attributes: [
                .font: headerFont,
                .foregroundColor: NSColor.secondaryLabelColor
            ])
            hStr.draw(at: CGPoint(x: colX + 2.0, y: tableRect.maxY - 8.0))

            // Value
            let vStr = NSAttributedString(string: values[i], attributes: [
                .font: valueFont,
                .foregroundColor: NSColor.black
            ])
            vStr.draw(at: CGPoint(x: colX + 2.0, y: tableRect.minY + 2.0))

            // Vertical divider
            if i > 0 {
                let div = NSBezierPath()
                div.move(to: CGPoint(x: colX, y: tableRect.minY))
                div.line(to: CGPoint(x: colX, y: tableRect.maxY))
                div.lineWidth = 0.4
                NSColor.lightGray.withAlphaComponent(0.5).setStroke()
                div.stroke()
            }
        }

        // Horizontal divider between header and values
        let hDiv = NSBezierPath()
        hDiv.move(to: CGPoint(x: tableRect.minX, y: tableRect.maxY - 9.0))
        hDiv.line(to: CGPoint(x: tableRect.maxX, y: tableRect.maxY - 9.0))
        hDiv.lineWidth = 0.4
        NSColor.lightGray.withAlphaComponent(0.5).setStroke()
        hDiv.stroke()

        // 4. Station Footer Row: From EP2AES · Grid: LN35ir · 73!
        let footerText = "DE \(config.stationCallsign) · LOC: \(config.stationGrid) · 73 de YAAM"
        let footerStr = NSAttributedString(string: footerText, attributes: [
            .font: NSFont.systemFont(ofSize: 6.0, weight: .semibold),
            .foregroundColor: NSColor.darkGray
        ])
        footerStr.draw(at: CGPoint(x: insetRect.minX + 4.0, y: insetRect.minY + 2.0))
    }

    // MARK: - Direct macOS Print Operation

    static func printLabels(records: [QSORecordModel], config: QSLLabelConfig) {
        let pdf = generatePDF(records: records, config: config)

        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = config.template.paperSize.dimensionsPoints
        printInfo.orientation = .portrait
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0

        let printOp = pdf.printOperation(for: printInfo, scalingMode: .pageScaleToFit, autoRotate: true)
        printOp?.run()
    }
}
