//
//  QSLLabelDesignerView.swift
//  YAAM
//
//  Interactive QSL Label Designer & Print Studio
//  Visual sheet layout preview, template customization, interactive peel-off skip matrix,
//  printer alignment calibration, and 1-click macOS printing / high-resolution PDF export.
//

import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

public struct QSLLabelDesignerView: View {
    @EnvironmentObject private var appState: AppState

    @State private var config = QSLLabelConfig()
    @State private var selectedTemplateIndex: Int = 0
    @State private var qsoSourceSelection: QSOSourceMode = .recent
    @State private var currentPage: Int = 1
    @State private var pdfDocument: PDFDocument? = nil
    @State private var actionStatus: String = ""
    @State private var activeSidebarTab: Int = 0 // 0: Template & Source, 1: Sheet Layout & Skip, 2: Style & Calibration

    enum QSOSourceMode: String, CaseIterable, Identifiable {
        case recent = "Recent QSOs (Up to 30)"
        case unconfirmed = "Unconfirmed / Need QSL"
        case allLog = "All QSOs in Log"
        case previewSample = "Sample Test QSOs"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .recent: return "clock.arrow.circlepath"
            case .unconfirmed: return "envelope.badge"
            case .allLog: return "books.vertical.fill"
            case .previewSample: return "sparkles"
            }
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()

            // Main Split: Controls Studio Sidebar + High-Res Sheet Preview
            HSplitView {
                // Left: Studio Controls
                studioSidebar
                    .frame(minWidth: 360, maxWidth: 440)

                // Right: High-Resolution Live Sheet Preview
                sheetPreviewPane
                    .frame(minWidth: 480)
            }
        }
        .onAppear {
            config.stationCallsign = appState.activeStationProfile?.normalizedCallsign ?? ""
            config.stationGrid = appState.activeStationProfile?.normalizedGrid ?? ""
            config.stationQTH = appState.activeStationProfile?.qth ?? ""
            regeneratePreview()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "printer.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 15, weight: .bold))
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("QSL Card Label Studio")
                            .font(.system(size: 13, weight: .bold))
                        Text("Avery & European Standard Sheets")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    Text("Print peel-and-stick adhesive labels for postcard QSL cards via Bureau or Direct")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Filter status badge
            let printCount = selectedRecords.count
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("\(printCount) Label\(printCount == 1 ? "" : "s") queued")
                    .font(.caption.bold().monospacedDigit())
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.blue.opacity(0.1), in: Capsule())

            // Print button
            Button {
                printLabelsNow()
            } label: {
                Label("Print Sheet (⌘P)", systemImage: "printer")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.borderedProminent)

            // Export PDF button
            Button {
                exportPDFToDisk()
            } label: {
                Label("Export PDF", systemImage: "arrow.down.doc.fill")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Left: Studio Controls Sidebar

    private var studioSidebar: some View {
        VStack(spacing: 0) {
            // Segmented Studio Navigation
            Picker("Section", selection: $activeSidebarTab) {
                Text("Template & Source").tag(0)
                Text("Sheet Skip Matrix").tag(1)
                Text("Style & Align").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch activeSidebarTab {
                    case 0:
                        templateAndSourceSection
                    case 1:
                        sheetSkipMatrixSection
                    default:
                        styleAndCalibrationSection
                    }
                }
                .padding(14)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Section 1: Template & QSO Source

    private var templateAndSourceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. Template Picker
            VStack(alignment: .leading, spacing: 8) {
                Label("Adhesive Label Template", systemImage: "square.grid.3x3.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)

                ForEach(0..<QSLLabelTemplate.standardTemplates.count, id: \.self) { idx in
                    let tmpl = QSLLabelTemplate.standardTemplates[idx]
                    Button {
                        selectedTemplateIndex = idx
                        config.template = tmpl
                        if config.startLabelIndex >= tmpl.labelsPerPage {
                            config.startLabelIndex = 0
                        }
                        regeneratePreview()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selectedTemplateIndex == idx ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(selectedTemplateIndex == idx ? .blue : .secondary)
                                .font(.system(size: 13))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(tmpl.name)
                                    .font(.system(size: 11.5, weight: selectedTemplateIndex == idx ? .bold : .medium))
                                    .foregroundColor(.primary)
                                Text("\(tmpl.paperSize.rawValue) • \(tmpl.columns) cols × \(tmpl.rows) rows (\(tmpl.labelsPerPage) labels/sheet)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedTemplateIndex == idx ? Color.blue.opacity(0.1) : Color(NSColor.windowBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(selectedTemplateIndex == idx ? Color.blue.opacity(0.4) : Color.secondary.opacity(0.12), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // 2. QSO Source Selector
            VStack(alignment: .leading, spacing: 8) {
                Label("QSO Source to Print", systemImage: "tray.full.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)

                Picker("Source", selection: $qsoSourceSelection) {
                    ForEach(QSOSourceMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: qsoSourceSelection) { _, _ in
                    regeneratePreview()
                }

                Text(sourceExplanationText)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private var sourceExplanationText: String {
        switch qsoSourceSelection {
        case .recent:
            return "Prints up to the 30 most recent QSOs currently in your logbook."
        case .unconfirmed:
            return "Prints QSOs where paper QSL has not yet been received or sent (filters log for pending cards)."
        case .allLog:
            return "Prints every QSO in your logbook across multiple sheets in sequential order."
        case .previewSample:
            return "Generates 10 placeholder contacts with DX stations (W1AW, DL1ABC, JA1ZLO) for testing paper alignment."
        }
    }

    // MARK: - Section 2: Sheet Skip Matrix (Interactive Mini Grid)

    private var sheetSkipMatrixSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Start Position (Skip Used Labels)", systemImage: "hand.tap.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                Text("Tap any cell on the sheet grid below to start printing from that position. This allows you to safely reuse expensive label sheets that were partially used in a previous print job.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Interactive Visual Grid
            let tmpl = config.template
            VStack(spacing: 4) {
                ForEach(0..<tmpl.rows, id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(0..<tmpl.columns, id: \.self) { col in
                            let labelIndex = row * tmpl.columns + col
                            let isSkipped = labelIndex < config.startLabelIndex
                            let isStart = labelIndex == config.startLabelIndex

                            Button {
                                config.startLabelIndex = labelIndex
                                regeneratePreview()
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(
                                            isStart ? Color.blue :
                                            (isSkipped ? Color.secondary.opacity(0.15) : Color.blue.opacity(0.12))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .stroke(isStart ? Color.blue : Color.secondary.opacity(0.2), lineWidth: 1)
                                        )

                                    VStack(spacing: 1) {
                                        Text("#\(labelIndex + 1)")
                                            .font(.system(size: 9.5, weight: isStart ? .black : .medium, design: .monospaced))
                                            .foregroundColor(isStart ? .white : (isSkipped ? .secondary : .primary))

                                        if isStart {
                                            Text("START")
                                                .font(.system(size: 6.5, weight: .black))
                                                .foregroundColor(.white)
                                        } else if isSkipped {
                                            Text("SKIP")
                                                .font(.system(size: 6.5, weight: .semibold))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .frame(height: tmpl.rows > 8 ? 26 : 34)
                            }
                            .buttonStyle(.plain)
                            .help("Start printing at label #\(labelIndex + 1)")
                        }
                    }
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))

            HStack {
                Button("Reset to #1 (Top Left)") {
                    config.startLabelIndex = 0
                    regeneratePreview()
                }
                .font(.caption)
                .buttonStyle(.bordered)

                Spacer()

                Text("Skipping \(config.startLabelIndex) label\(config.startLabelIndex == 1 ? "" : "s")")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundColor(config.startLabelIndex > 0 ? .orange : .secondary)
            }
        }
    }

    // MARK: - Section 3: Style & Fine Calibration

    private var styleAndCalibrationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Label Content Options
            VStack(alignment: .leading, spacing: 8) {
                Label("Content & Text Format", systemImage: "text.alignleft")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)

                Picker("QSL Courtesy Tag:", selection: $config.qslConfirmationText) {
                    Text("PSE QSL (Please confirm & reply)").tag("PSE QSL")
                    Text("TNX QSL (Thanks for confirming)").tag("TNX QSL")
                    Text("73 TNX (Greetings & thanks)").tag("73 TNX")
                }
                .onChange(of: config.qslConfirmationText) { _, _ in regeneratePreview() }

                Toggle("Draw thin rounded border around each label", isOn: $config.includeBorder)
                    .onChange(of: config.includeBorder) { _, _ in regeneratePreview() }

                Toggle("Include My Station Callsign & Grid Square in footer", isOn: $config.includeMyInfo)
                    .onChange(of: config.includeMyInfo) { _, _ in regeneratePreview() }
            }

            Divider()

            // Printer Alignment Calibration
            VStack(alignment: .leading, spacing: 8) {
                Label("Printer Hardware Alignment Offsets", systemImage: "ruler.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                Text("Adjust micro-offsets if your laser/inkjet printer feeder shifts the paper slightly.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Text("Horizontal (X):")
                            .font(.system(size: 11))
                            .frame(width: 95, alignment: .leading)
                        Slider(value: $config.offsetXPoints, in: -25...25, step: 0.5)
                            .onChange(of: config.offsetXPoints) { _, _ in regeneratePreview() }
                        Text("\(String(format: "%+.1f pt", config.offsetXPoints))")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .frame(width: 55, alignment: .trailing)
                    }

                    HStack(spacing: 10) {
                        Text("Vertical (Y):")
                            .font(.system(size: 11))
                            .frame(width: 95, alignment: .leading)
                        Slider(value: $config.offsetYPoints, in: -25...25, step: 0.5)
                            .onChange(of: config.offsetYPoints) { _, _ in regeneratePreview() }
                        Text("\(String(format: "%+.1f pt", config.offsetYPoints))")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .frame(width: 55, alignment: .trailing)
                    }
                }
                .padding(10)
                .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Right: High-Resolution Live Sheet Preview

    private var sheetPreviewPane: some View {
        VStack(spacing: 0) {
            // Preview Toolbar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "eye.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Live Sheet Print Preview")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let doc = pdfDocument, doc.pageCount > 1 {
                    HStack(spacing: 8) {
                        Button {
                            currentPage = max(1, currentPage - 1)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(currentPage <= 1)

                        Text("Sheet \(currentPage) of \(doc.pageCount)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))

                        Button {
                            currentPage = min(doc.pageCount, currentPage + 1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(currentPage >= doc.pageCount)
                    }
                }

                Text("100% Scale")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Interactive PDF View Container with paper shadow
            ZStack {
                Color(red: 0.82, green: 0.84, blue: 0.87)
                    .edgesIgnoringSafeArea(.all)

                PDFKitRepresentedView(document: pdfDocument, currentPage: currentPage)
                    .padding(16)
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
            }
        }
    }

    // MARK: - Data Selection & Actions

    private var selectedRecords: [QSORecordModel] {
        switch qsoSourceSelection {
        case .recent:
            let recs = appState.qsoRecords
            return recs.isEmpty ? generatePlaceholderRecords() : Array(recs.prefix(30))
        case .unconfirmed:
            let recs = appState.qsoRecords.filter { rec in
                let rcvd = (rec.fields["QSL_RCVD"] ?? "").uppercased()
                let sent = (rec.fields["QSL_SENT"] ?? "").uppercased()
                return rcvd != "Y" || sent != "Y"
            }
            return recs.isEmpty ? generatePlaceholderRecords() : recs
        case .allLog:
            let recs = appState.qsoRecords
            return recs.isEmpty ? generatePlaceholderRecords() : recs
        case .previewSample:
            return generatePlaceholderRecords()
        }
    }

    private func regeneratePreview() {
        let recs = selectedRecords
        let doc = QSLLabelEngine.generatePDF(records: recs, config: config)
        self.pdfDocument = doc
        if currentPage > doc.pageCount {
            currentPage = max(1, doc.pageCount)
        }
    }

    private func printLabelsNow() {
        let recs = selectedRecords
        QSLLabelEngine.printLabels(records: recs, config: config)
    }

    private func exportPDFToDisk() {
        let recs = selectedRecords
        let doc = QSLLabelEngine.generatePDF(records: recs, config: config)

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "YAAM_QSL_Labels_\(config.stationCallsign).pdf"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            doc.write(to: url)
        }
    }

    private func generatePlaceholderRecords() -> [QSORecordModel] {
        var dummy: [QSORecordModel] = []
        let calls = ["W1AW", "DL1ABC", "JA1ZLO", "SV1DH", "G4FOC", "PY2XB", "VK3ZZ", "ZL1AA", "IK0FTA", "F5IN", "HB9BZA", "OH2BH"]
        for (i, call) in calls.enumerated() {
            let rec = QSORecordModel(index: i + 1, fields: [
                "CALL": call,
                "QSO_DATE": "20260901",
                "TIME_ON": "123000",
                "BAND": "20M",
                "MODE": "FT8",
                "RST_SENT": "-08",
                "RST_RCVD": "-12",
                "QSL_RCVD": i % 2 == 0 ? "Y" : "N"
            ])
            dummy.append(rec)
        }
        return dummy
    }
}

// MARK: - PDFKit NSViewRepresentable for macOS

struct PDFKitRepresentedView: NSViewRepresentable {
    let document: PDFDocument?
    let currentPage: Int

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.backgroundColor = NSColor(red: 0.82, green: 0.84, blue: 0.87, alpha: 1.0)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = document
        if let doc = document, currentPage > 0, currentPage <= doc.pageCount, let page = doc.page(at: currentPage - 1) {
            nsView.go(to: page)
        }
    }
}
