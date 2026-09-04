//
//  DigitalContestCabrilloExportView.swift
//  YAAM
//
//  Gold Standard Cabrillo 3.0 Export Sheet for Digital Contests on macOS.
//  Provides real-time interactive log preview, robot pre-flight audit,
//  configurable contest categories, and native NSSavePanel export.
//

import SwiftUI
import AppKit

public struct DigitalContestCabrilloExportView: View {
    @ObservedObject var engine: DigitalContestEngine
    @Environment(\.dismiss) private var dismiss

    @State private var options: DigitalCabrilloExportOptions
    @State private var selectedTab: Int = 0
    @State private var copiedToClipboard: Bool = false

    public init(engine: DigitalContestEngine, defaultCall: String = "", defaultGrid: String = "") {
        self.engine = engine

        let initialCall = defaultCall.isEmpty ? engine.myStationCall : defaultCall
        let initialGrid = defaultGrid.isEmpty ? engine.myStationGrid : defaultGrid

        _options = State(initialValue: DigitalCabrilloExportOptions(
            contestType: engine.contestType,
            callsign: initialCall,
            grid: initialGrid,
            operatorCategory: "SINGLE-OP",
            assistedCategory: "ASSISTED",
            bandCategory: "ALL",
            powerCategory: "LOW",
            stationCategory: "FIXED",
            transmitterCategory: "ONE",
            overlayCategory: "NONE",
            operatorName: "",
            address: "",
            city: "",
            stateProvince: "",
            postalCode: "",
            country: "",
            email: "",
            club: "",
            operators: initialCall,
            soapbox: ""
        ))
    }

    private var generatedLog: String {
        DigitalContestCabrilloService.generateCabrillo(engine: engine, options: options)
    }

    private var issues: [CabrilloIssue] {
        DigitalContestCabrilloService.validate(engine: engine, options: options)
    }

    private var errorCount: Int {
        issues.filter { $0.isError }.count
    }

    private var warningCount: Int {
        issues.filter { !$0.isError }.count
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()

            // Main Split: Config Form & Live Preview
            HSplitView {
                // Left: Configuration & Pre-Flight
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $selectedTab) {
                        Text("Contest Category").tag(0)
                        Text("Station Identity").tag(1)
                        Text("Pre-Flight Audit (\(issues.count))").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)

                    if selectedTab == 0 {
                        categoryConfigForm
                    } else if selectedTab == 1 {
                        stationIdentityForm
                    } else {
                        preFlightAuditView
                    }

                    Spacer()

                    // Mini Audit Summary at bottom of left panel
                    miniAuditFooter
                }
                .frame(minWidth: 360, idealWidth: 380, maxWidth: 420)
                .background(Color(nsColor: .windowBackgroundColor))

                // Right: Live Cabrillo 3.0 Preview
                VStack(spacing: 0) {
                    previewToolbar
                    Divider()
                    previewEditor
                    Divider()
                    actionFooter
                }
                .frame(minWidth: 500, idealWidth: 580)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .frame(minWidth: 920, idealWidth: 1020, minHeight: 620, idealHeight: 700)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 20))
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Official Cabrillo 3.0 Contest Log Exporter")
                        .font(.headline)
                    Text(options.contestType.shortCode)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow.opacity(0.2))
                        .foregroundStyle(.yellow)
                        .cornerRadius(4)
                }

                Text("Generates compliant .log files for CQ WW Digi, ARRL Digi, and international contest robots")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .controlSize(.regular)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Category Config Form

    private var categoryConfigForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Contest Type Selection
                VStack(alignment: .leading, spacing: 4) {
                    Text("Contest").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Picker("", selection: $options.contestType) {
                        ForEach(DigitalContestType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .labelsHidden()
                }

                Divider()

                // Operator & Assisted
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Operator Category").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            Picker("", selection: $options.operatorCategory) {
                                Text("SINGLE-OP (Single Operator)").tag("SINGLE-OP")
                                Text("MULTI-OP (Multi Operator)").tag("MULTI-OP")
                                Text("CHECKLOG (Log for cross-checking)").tag("CHECKLOG")
                            }
                            .labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Assisted Category").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            Picker("", selection: $options.assistedCategory) {
                                Text("ASSISTED (With DX Cluster/RBN)").tag("ASSISTED")
                                Text("NON-ASSISTED (Single unassisted)").tag("NON-ASSISTED")
                            }
                            .labelsHidden()
                        }
                    }

                    GridRow {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Power Category").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            Picker("", selection: $options.powerCategory) {
                                Text("LOW (≤ 100 Watts)").tag("LOW")
                                Text("HIGH (> 100 Watts)").tag("HIGH")
                                Text("QRP (≤ 5 Watts)").tag("QRP")
                            }
                            .labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Band Category").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            Picker("", selection: $options.bandCategory) {
                                Text("ALL (All Bands)").tag("ALL")
                                Text("160M").tag("160M")
                                Text("80M").tag("80M")
                                Text("40M").tag("40M")
                                Text("20M").tag("20M")
                                Text("15M").tag("15M")
                                Text("10M").tag("10M")
                                Text("6M").tag("6M")
                            }
                            .labelsHidden()
                        }
                    }

                    GridRow {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Transmitter").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            Picker("", selection: $options.transmitterCategory) {
                                Text("ONE (Single TX)").tag("ONE")
                                Text("TWO (Two Transmitters)").tag("TWO")
                                Text("MULTI (Unlimited)").tag("MULTI")
                            }
                            .labelsHidden()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Station Location").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            Picker("", selection: $options.stationCategory) {
                                Text("FIXED (Home station)").tag("FIXED")
                                Text("PORTABLE").tag("PORTABLE")
                                Text("MOBILE").tag("MOBILE")
                                Text("ROVER").tag("ROVER")
                            }
                            .labelsHidden()
                        }
                    }
                }

                Divider()

                // Overlay Category
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overlay Category (Optional)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Picker("", selection: $options.overlayCategory) {
                        Text("NONE").tag("NONE")
                        Text("CLASSIC (One radio, no assistance)").tag("CLASSIC")
                        Text("ROOKIE (Licensed < 3 years)").tag("ROOKIE")
                        Text("TB-WIRES (Tribander / Single Wire)").tag("TB-WIRES")
                        Text("YOUTH (Under 26 years)").tag("YOUTH")
                    }
                    .labelsHidden()
                }
            }
            .padding(14)
        }
    }

    // MARK: - Station Identity Form

    private var stationIdentityForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Station Callsign & Grid
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Callsign *").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        TextField("e.g. EP2LMA", text: $options.callsign)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Grid Locator *").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        TextField("e.g. KM32", text: $options.grid)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }
                }

                // Operator Name & Email
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Operator Name").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        TextField("First & Last Name", text: $options.operatorName)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email Address").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        TextField("operator@domain.com", text: $options.email)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                // Street Address & City
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Street Address").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        TextField("Street / PO Box", text: $options.address)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("City").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        TextField("City / Town", text: $options.city)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                // State / Postal Code / Country
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("State / Province").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        TextField("State", text: $options.stateProvince)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Postal Code").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        TextField("Postal / Zip", text: $options.postalCode)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Country").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        TextField("Country", text: $options.country)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                // Club & Operators
                VStack(alignment: .leading, spacing: 4) {
                    Text("Club Name (For Club Competition)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    TextField("Affiliated Club Name", text: $options.club)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Operators (Comma or space separated)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    TextField("e.g. EP2LMA", text: $options.operators)
                        .textFieldStyle(.roundedBorder)
                }

                // Soapbox
                VStack(alignment: .leading, spacing: 4) {
                    Text("Soapbox / Operator Comments").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    TextEditor(text: $options.soapbox)
                        .font(.system(size: 11))
                        .frame(height: 60)
                        .border(Color.secondary.opacity(0.2), width: 1)
                }
            }
            .padding(14)
        }
    }

    // MARK: - Pre-Flight Audit View

    private var preFlightAuditView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if issues.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("100% Robot Compliant")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Text("All required Cabrillo 3.0 tags, header formats, and QSO lines pass validation.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                } else {
                    ForEach(issues) { issue in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: issue.iconName)
                                .foregroundStyle(issue.badgeColor)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(issue.isError ? "Error: Robot Rejection Risk" : "Notice / Warning")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(issue.badgeColor)
                                Text(issue.message)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.primary)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .background(issue.badgeColor.opacity(0.08))
                        .cornerRadius(6)
                    }
                }
            }
            .padding(14)
        }
    }

    // MARK: - Mini Audit Footer

    private var miniAuditFooter: some View {
        HStack(spacing: 8) {
            if errorCount == 0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Cabrillo 3.0 Valid")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text("\(errorCount) Error(s) need attention")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }

            if warningCount > 0 {
                Text("(\(warningCount) warnings)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()

            Button("View Audit") {
                selectedTab = 2
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Preview Toolbar

    private var previewToolbar: some View {
        HStack(spacing: 12) {
            Text("Cabrillo 3.0 Output Preview")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)

            Spacer()

            // Badges
            HStack(spacing: 6) {
                Text("QSOs: \(engine.totalQSOs)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .cornerRadius(4)

                Text("Score: \(engine.claimedScore.formatted())")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.yellow.opacity(0.15))
                    .foregroundStyle(.yellow)
                    .cornerRadius(4)

                Text("Mults: \(engine.totalMultipliers)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Preview Editor

    private var previewEditor: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(generatedLog)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(nsColor: .textColor))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(14)
        }
    }

    // MARK: - Action Footer

    private var actionFooter: some View {
        HStack(spacing: 12) {
            // Copy to clipboard
            Button {
                copyToClipboard()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: copiedToClipboard ? "checkmark" : "doc.on.doc")
                    Text(copiedToClipboard ? "Copied to Clipboard!" : "Copy to Clipboard")
                }
                .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Spacer()

            // Export to File Button
            Button {
                exportToFile()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up.fill")
                    Text("Export Cabrillo Log (.log)...")
                }
                .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.regular)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Actions

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(generatedLog, forType: .string)
        withAnimation {
            copiedToClipboard = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                copiedToClipboard = false
            }
        }
    }

    private func exportToFile() {
        let cleanCall = options.callsign.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let fileName = (cleanCall.isEmpty ? "CONTEST" : cleanCall) + ".log"
        DigitalContestCabrilloService.exportLogToFile(cabrilloContent: generatedLog, defaultFileName: fileName)
    }
}
