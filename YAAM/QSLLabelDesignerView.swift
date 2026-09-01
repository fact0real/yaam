//
//  QSLLabelDesignerView.swift
//  YAAM
//
//  Interactive QSL Label Designer & Print Preview Console
//  Visual sheet layout preview, template customization, printer alignment calibration,
//  and 1-click macOS printing / high-resolution PDF export.
//

import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

public struct QSLLabelDesignerView: View {
    @EnvironmentObject private var appState: AppState
    @State private var config = QSLLabelConfig()
    @State private var selectedTemplateIndex: Int = 0
    @State private var currentPage: Int = 1
    @State private var pdfDocument: PDFDocument? = nil
    @State private var actionStatus: String = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()

            // Main Split: Controls Sidebar + Live PDF Sheet Preview
            HSplitView {
                // Left: Customizer & Template Configuration
                customizerSidebar
                    .frame(minWidth: 320, maxWidth: 400)

                // Right: High-Resolution Live Sheet Preview
                sheetPreviewPane
                    .frame(minWidth: 450)
            }
        }
        .onAppear {
            config.stationCallsign = appState.activeStationProfile?.callsign ?? "EP2AES"
            config.stationGrid = appState.activeStationProfile?.grid ?? "LN35ir"
            regeneratePreview()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "printer.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
                Text("QSL Label Designer & Print Engine")
                    .font(.headline.bold())
            }

            Spacer()

            Text("\(appState.qsoRecords.count) QSOs in Log")
                .font(.caption)
                .foregroundColor(.secondary)

            Button {
                printLabelsNow()
            } label: {
                Label("Print Labels (⌘P)", systemImage: "printer")
            }
            .buttonStyle(.borderedProminent)

            Button {
                exportPDFToDisk()
            } label: {
                Label("Export PDF", systemImage: "arrow.down.doc.fill")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Left: Customizer Sidebar

    private var customizerSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 1. Template Selection
                VStack(alignment: .leading, spacing: 6) {
                    Text("Label Sheet Template")
                        .font(.subheadline.bold())

                    Picker("Template:", selection: $selectedTemplateIndex) {
                        ForEach(0..<QSLLabelTemplate.standardTemplates.count, id: \.self) { idx in
                            Text(QSLLabelTemplate.standardTemplates[idx].name).tag(idx)
                        }
                    }
                    .onChange(of: selectedTemplateIndex) { _, newIdx in
                        config.template = QSLLabelTemplate.standardTemplates[newIdx]
                        regeneratePreview()
                    }

                    Text("Paper: \(config.template.paperSize.rawValue) · \(config.template.labelsPerPage) labels/sheet")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Divider()

                // 2. Sheet Start Position (Skip used labels)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Start at Label Position:")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("#\(config.startLabelIndex + 1)")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundColor(.blue)
                    }

                    Stepper("Skip already-used labels on physical sheet", value: $config.startLabelIndex, in: 0...(config.template.labelsPerPage - 1))
                        .onChange(of: config.startLabelIndex) { _, _ in
                            regeneratePreview()
                        }

                    Text("Useful when printing on a partially used sheet of labels.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Divider()

                // 3. Label Content & Formatting
                VStack(alignment: .leading, spacing: 10) {
                    Text("Label Content Options")
                        .font(.subheadline.bold())

                    Picker("QSL Status:", selection: $config.qslConfirmationText) {
                        Text("PSE QSL (Please confirm)").tag("PSE QSL")
                        Text("TNX QSL (Thanks for confirm)").tag("TNX QSL")
                        Text("73 TNX (Greeting only)").tag("73 TNX")
                    }
                    .onChange(of: config.qslConfirmationText) { _, _ in
                        regeneratePreview()
                    }

                    Toggle("Draw Rounded Border around each label", isOn: $config.includeBorder)
                        .onChange(of: config.includeBorder) { _, _ in
                            regeneratePreview()
                        }

                    Toggle("Include Station Call & Grid in footer", isOn: $config.includeMyInfo)
                        .onChange(of: config.includeMyInfo) { _, _ in
                            regeneratePreview()
                        }
                }

                Divider()

                // 4. Printer Alignment Calibration
                VStack(alignment: .leading, spacing: 10) {
                    Text("Printer Alignment Offsets (pt)")
                        .font(.subheadline.bold())

                    HStack(spacing: 12) {
                        Text("Offset X:")
                            .font(.caption)
                        Slider(value: $config.offsetXPoints, in: -20...20, step: 0.5)
                            .onChange(of: config.offsetXPoints) { _, _ in
                                regeneratePreview()
                            }
                        Text("\(String(format: "%.1f", config.offsetXPoints)) pt")
                            .font(.caption.monospacedDigit())
                            .frame(width: 45)
                    }

                    HStack(spacing: 12) {
                        Text("Offset Y:")
                            .font(.caption)
                        Slider(value: $config.offsetYPoints, in: -20...20, step: 0.5)
                            .onChange(of: config.offsetYPoints) { _, _ in
                                regeneratePreview()
                            }
                        Text("\(String(format: "%.1f", config.offsetYPoints)) pt")
                            .font(.caption.monospacedDigit())
                            .frame(width: 45)
                    }
                }

                Spacer()
            }
            .padding(14)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Right: High-Resolution Live Sheet Preview

    private var sheetPreviewPane: some View {
        VStack(spacing: 0) {
            // Preview Toolbar
            HStack {
                Text("Page Preview")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                Spacer()

                if let doc = pdfDocument, doc.pageCount > 1 {
                    HStack(spacing: 6) {
                        Button {
                            currentPage = max(1, currentPage - 1)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(currentPage <= 1)

                        Text("Page \(currentPage) of \(doc.pageCount)")
                            .font(.caption.monospacedDigit())

                        Button {
                            currentPage = min(doc.pageCount, currentPage + 1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(currentPage >= doc.pageCount)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Interactive PDF View Container
            PDFKitRepresentedView(document: pdfDocument, currentPage: currentPage)
                .background(Color(red: 0.85, green: 0.87, blue: 0.90))
        }
    }

    // MARK: - Actions

    private func regeneratePreview() {
        let sample = Array(appState.qsoRecords.prefix(60))
        let doc = QSLLabelEngine.generatePDF(records: sample.isEmpty ? generatePlaceholderRecords() : sample, config: config)
        self.pdfDocument = doc
    }

    private func printLabelsNow() {
        let records = appState.qsoRecords
        QSLLabelEngine.printLabels(records: records.isEmpty ? generatePlaceholderRecords() : records, config: config)
    }

    private func exportPDFToDisk() {
        let records = appState.qsoRecords
        let doc = QSLLabelEngine.generatePDF(records: records.isEmpty ? generatePlaceholderRecords() : records, config: config)

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "YAAM_QSL_Labels_\(config.stationCallsign).pdf"

        if savePanel.runModal() == .OK, let url = savePanel.url {
            doc.write(to: url)
        }
    }

    private func generatePlaceholderRecords() -> [QSORecordModel] {
        var dummy: [QSORecordModel] = []
        let calls = ["W1AW", "DL1ABC", "JA1ZLO", "SV1DH", "G4FOC", "PY2XB", "VK3ZZ", "ZL1AA", "IK0FTA", "F5IN"]
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
        view.backgroundColor = NSColor(red: 0.85, green: 0.87, blue: 0.90, alpha: 1.0)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = document
        if let doc = document, currentPage > 0, currentPage <= doc.pageCount, let page = doc.page(at: currentPage - 1) {
            nsView.go(to: page)
        }
    }
}
