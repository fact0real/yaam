//
//  ContentView.swift
//  YAAM
//
//  Created by factoreal on 7/30/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Main User Interface
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    
    @State private var inputPath: String = ""
    @State private var outputPath: String = ""
    @State private var conversionInput: ParsedLogFile?
    @State private var databaseInput: (headers: [String], records: [[String: String]])?
    @State private var databaseStats: (count: Int, firstDate: String?, lastDate: String?) = (0, nil, nil)
    @State private var conversionInputError: String?
    @State private var isReadingConversionInput = false
    @State private var conversionLoadID: UUID?
    
    // Conversion & Output Options
    @State private var selectedExportFormat: ExportLogFormat = .excelCSV
    @State private var cabrilloContestID: String = "CQ-WW-SSB"
    @State private var cabrilloOperatorCategory: String = "SINGLE-OP"
    @State private var cabrilloPowerCategory: String = "HIGH"
    @State private var cabrilloClaimedScore: String = "0"
    
    // Contest / UTC Time Filter Settings
    @State private var enableFilter: Bool = false
    @State private var startDateTime: Date = UTCMinuteKey.normalized(Date())
    @State private var endDateTime: Date = UTCMinuteKey.normalized(Date().addingTimeInterval(7200))

    // Band / Mode Filter Settings
    @State private var selectedBand: String = ADIFConversionFilter.allBands
    @State private var selectedMode: String = ADIFConversionFilter.allModes
    @State private var conversionBands: [String] = [ADIFConversionFilter.allBands] + ADIFConversionFilter.defaultBands
    @State private var conversionModes: [String] = [ADIFConversionFilter.allModes] + ADIFConversionFilter.defaultModes
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Global Tab Navigation Selector
            Picker("", selection: $appState.selectedTab) {
                Text("Log Table").tag(0)
                Text("Operator Desk").tag(5)
                Text("Convert & Export").tag(1)
                Text("Leaderboard").tag(2)
                Text("DX Advisor").tag(3)
                Text("Awards").tag(4)
            }
            .pickerStyle(.segmented)
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))
            .onChange(of: appState.selectedTab) { _, value in
                UserDefaults.standard.set(value, forKey: "selectedTab")
            }
            
            Divider()
            
            // MARK: - Tab Views Routing
            if appState.selectedTab == 0 {
                // Tab 0: ADIFMaster High-Performance Table Grid
                LogTableView()
            } else if appState.selectedTab == 5 {
                OperatorDeskView()
            } else if appState.selectedTab == 1 {
                // Tab 1: Conversion & Database Log Export Tool
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // Section 1: Source Selector (External File vs YAAM Database)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Log Source", systemImage: "tray.full.fill")
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Spacer()

                                Picker("Source", selection: $appState.convertSource) {
                                    Label("External File", systemImage: "doc.text").tag(0)
                                    Label("YAAM Database", systemImage: "cylinder.split.1x2.fill").tag(1)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 280)
                            }

                            if appState.convertSource == 0 {
                                // Row 1A: Supported External Log File Picker
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(spacing: 10) {
                                        TextField("Input ADIF or SmartSDR log path...", text: $inputPath)
                                            .textFieldStyle(.roundedBorder)
                                            .onSubmit {
                                                loadConversionInput(from: URL(fileURLWithPath: inputPath))
                                            }
                                            .onChange(of: inputPath) { _, newPath in
                                                if conversionInput?.sourceURL.path != newPath {
                                                    conversionInput = nil
                                                    conversionInputError = nil
                                                }
                                            }

                                        Button {
                                            selectLogFile()
                                        } label: {
                                            Label("Choose Log", systemImage: "doc.badge.plus")
                                        }
                                        .frame(width: 130)
                                        .disabled(isReadingConversionInput)
                                    }

                                    conversionInputStatus
                                }
                            } else {
                                // Row 1B: YAAM Database Log Selector
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Station Logbook / Scope:")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(.secondary)

                                            Picker("Station Profile", selection: $appState.convertDatabaseProfileID) {
                                                if let activeProfile = appState.activeStationProfile {
                                                    let count = appState.totalDatabaseQSOCount(profileID: activeProfile.id)
                                                    Text("⚡️ Active Station: \(activeProfile.displayTitle) (\(activeProfile.normalizedCallsign.isEmpty ? "No Call" : activeProfile.normalizedCallsign)) - \(count.formatted()) QSOs")
                                                        .tag(Optional(activeProfile.id))
                                                    Divider()
                                                }
                                                Text("🌟 All Station Profiles Combined (Full Database - \(appState.totalDatabaseQSOCount().formatted()) QSOs)")
                                                    .tag(Optional<UUID>.none)
                                                let otherProfiles = appState.stationProfiles.filter { $0.id != appState.activeStationProfileID }
                                                if !otherProfiles.isEmpty {
                                                    Divider()
                                                    ForEach(otherProfiles) { profile in
                                                        let count = appState.totalDatabaseQSOCount(profileID: profile.id)
                                                        Text("\(profile.displayTitle) (\(profile.normalizedCallsign.isEmpty ? "No Call" : profile.normalizedCallsign)) - \(count.formatted()) QSOs")
                                                            .tag(Optional(profile.id))
                                                    }
                                                }
                                            }
                                            .pickerStyle(.menu)
                                        }

                                        Button {
                                            loadDatabaseSource()
                                        } label: {
                                            Label("Refresh", systemImage: "arrow.clockwise")
                                        }
                                        .frame(width: 100)
                                        .padding(.top, 18)
                                        .disabled(isReadingConversionInput)
                                    }

                                    databaseInputStatus
                                }
                                .padding(10)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                                .cornerRadius(8)
                            }
                        }
                        
                        // Section 2: Output File Picker
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Destination File:")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)

                            HStack(spacing: 10) {
                                TextField("Output file path...", text: $outputPath)
                                    .textFieldStyle(.roundedBorder)
                                
                                Button {
                                    selectOutputFile()
                                } label: {
                                    Label("Save To...", systemImage: "folder.badge.plus")
                                }
                                .frame(width: 120)
                            }
                        }
                        
                        // Section 3: Multi-Format Output Options & Settings
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Export Format", systemImage: "square.and.arrow.up.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.primary)

                                Spacer()

                                Picker("Format", selection: $selectedExportFormat) {
                                    ForEach(ExportLogFormat.allCases) { fmt in
                                        Label(fmt.rawValue, systemImage: fmt.icon).tag(fmt)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 250)
                                .onChange(of: selectedExportFormat) { _, newFmt in
                                    updateOutputFileExtension(format: newFmt)
                                }
                            }

                            // Format Description Banner
                            HStack(spacing: 8) {
                                Image(systemName: selectedExportFormat.icon)
                                    .font(.system(size: 14))
                                    .foregroundColor(.accentColor)
                                Text(selectedExportFormat.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                            
                            // Cabrillo Options Panel if selected
                            if selectedExportFormat == .cabrillo {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label("Cabrillo Contest Headers", systemImage: "flag.checkered")
                                        .font(.caption.bold())
                                        .foregroundColor(.orange)

                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("CONTEST ID:")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            TextField("CQ-WW-SSB", text: $cabrilloContestID)
                                                .textFieldStyle(.roundedBorder)
                                        }

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("OPERATOR:")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Picker("", selection: $cabrilloOperatorCategory) {
                                                Text("SINGLE-OP").tag("SINGLE-OP")
                                                Text("MULTI-OP").tag("MULTI-OP")
                                                Text("CHECKLOG").tag("CHECKLOG")
                                            }
                                            .pickerStyle(.menu)
                                        }

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("POWER:")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Picker("", selection: $cabrilloPowerCategory) {
                                                Text("HIGH").tag("HIGH")
                                                Text("LOW").tag("LOW")
                                                Text("QRP").tag("QRP")
                                            }
                                            .pickerStyle(.menu)
                                        }

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("CLAIMED SCORE:")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            TextField("0", text: $cabrilloClaimedScore)
                                                .textFieldStyle(.roundedBorder)
                                        }
                                    }
                                }
                                .padding(10)
                                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.25), lineWidth: 1))
                            }

                            Divider()
                            
                            Toggle(isOn: $enableFilter.animation(.spring(response: 0.35, dampingFraction: 0.75))) {
                                HStack(spacing: 6) {
                                    Image(systemName: "timer")
                                        .foregroundColor(.orange)
                                    Text("Enable UTC Time Filter (Contest Mode)")
                                        .font(.headline)
                                }
                            }
                            .onChange(of: enableFilter) { _, _ in
                                updateOutputPathForFilters()
                            }
                            
                            if enableFilter {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 16) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Label("Start Time (UTC)", systemImage: "play.circle.fill")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundColor(.green)
                                            
                                            DatePicker("", selection: $startDateTime, displayedComponents: [.date, .hourAndMinute])
                                                .labelsHidden()
                                                .datePickerStyle(.compact)
                                                .environment(\.timeZone, UTCMinuteKey.timeZone)
                                        }
                                        .padding(8)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(8)
                                        
                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.accentColor)
                                        
                                        VStack(alignment: .leading, spacing: 6) {
                                            Label("End Time (UTC)", systemImage: "stop.circle.fill")
                                                .font(.caption)
                                                .fontWeight(.bold)
                                                .foregroundColor(.red)
                                            
                                            DatePicker("", selection: $endDateTime, displayedComponents: [.date, .hourAndMinute])
                                                .labelsHidden()
                                                .datePickerStyle(.compact)
                                                .environment(\.timeZone, UTCMinuteKey.timeZone)
                                        }
                                        .padding(8)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(8)
                                    }
                                    
                                    HStack(spacing: 6) {
                                        Image(systemName: "globe")
                                            .foregroundColor(.accentColor)
                                        Text("UTC Range:")
                                            .fontWeight(.medium)
                                        Text("\(UTCMinuteKey.string(from: startDateTime)) ➔ \(UTCMinuteKey.string(from: endDateTime))")
                                            .font(.system(.caption, design: .monospaced))
                                            .fontWeight(.semibold)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                                }
                                .padding(10)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                                .cornerRadius(8)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Label("Band & Mode Filter", systemImage: "slider.horizontal.3")
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    if isBandModeFilterActive {
                                        Button {
                                            selectedBand = ADIFConversionFilter.allBands
                                            selectedMode = ADIFConversionFilter.allModes
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(.secondary)
                                        .help("Clear Band and Mode filters")
                                    }
                                }

                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 16) {
                                        conversionBandPicker
                                        conversionModePicker
                                        Spacer(minLength: 0)
                                    }

                                    VStack(alignment: .leading, spacing: 10) {
                                        conversionBandPicker
                                        conversionModePicker
                                    }
                                }

                                if let matchCount = currentFilteredMatchCount {
                                    HStack(spacing: 6) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Filter matches:")
                                            .fontWeight(.medium)
                                        Text("\(matchCount.matching.formatted()) of \(matchCount.total.formatted()) QSO(s)")
                                            .fontWeight(.semibold)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                                }
                            }
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
                            .cornerRadius(8)
                        }
                        .padding(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        
                        // Section 4: Action Buttons
                        HStack(spacing: 12) {
                            Button(action: { processFile() }) {
                                HStack {
                                    Image(systemName: appState.convertSource == 1 ? "arrow.down.doc.fill" : "gearshape.fill")
                                    Text(appState.convertSource == 1 ? "Export Database Log" : "Process Log")
                                }
                            }
                            .keyboardShortcut(.defaultAction)
                            .disabled(isReadingConversionInput || isOutputEmpty)
                            
                            Button(action: { openOutputFile() }) {
                                HStack {
                                    Image(systemName: "arrow.up.forward.app")
                                    Text("Open Output File")
                                }
                            }
                            .disabled(outputPath.isEmpty || !FileManager.default.fileExists(atPath: outputPath))

                            Button(action: { revealOutputFile() }) {
                                HStack {
                                    Image(systemName: "folder")
                                    Text("Reveal in Finder")
                                }
                            }
                            .disabled(outputPath.isEmpty || !FileManager.default.fileExists(atPath: outputPath))
                            
                            Spacer()
                        }
                        
                        // Section 5: Activity status and separate console window
                        HStack(spacing: 10) {
                            Label("Activity Console", systemImage: "terminal.fill")
                                .font(.callout.weight(.semibold))

                            Text("Detailed export, conversion, and database logs open in a separate window.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)

                            Spacer()

                            Circle()
                                .fill(conversionStatusColor)
                                .frame(width: 7, height: 7)

                            Text(conversionStatusTitle)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button {
                                openWindow(id: YAAMWindowID.console)
                            } label: {
                                Label("Open Console", systemImage: "rectangle.on.rectangle")
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
                    }
                    .padding(16)
                }
                .onAppear {
                    if appState.convertDatabaseProfileID == nil, let activeID = appState.activeStationProfileID {
                        appState.convertDatabaseProfileID = activeID
                    }
                    if appState.convertSource == 1 && databaseInput == nil {
                        loadDatabaseSource()
                    } else if appState.convertSource == 0 && outputPath.isEmpty {
                        updateOutputPathForFilters()
                    }
                }
                .onChange(of: appState.convertSource) { _, newSource in
                    if newSource == 1 {
                        if databaseInput == nil {
                            loadDatabaseSource()
                        } else {
                            updateOutputPathForFilters()
                        }
                    } else {
                        updateOutputPathForFilters()
                    }
                }
                .onChange(of: appState.convertDatabaseProfileID) { _, _ in
                    if appState.convertSource == 1 {
                        loadDatabaseSource()
                    }
                }
            } else if appState.selectedTab == 2 {
                // Tab 2: NEW FULL-PAGE LEADERBOARD VIEW
                LeaderboardView()
            } else if appState.selectedTab == 3 {
                DXAdvisorView()
            } else if appState.selectedTab == 4 {
                QRZAwardsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $appState.showAboutSheet) {
            AboutView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showEmailComposer) {
            EmailComposerView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showQSLCardComposer) {
            QSLCardComposerView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showImportReviewSheet) {
            ImportReviewView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showQRZLoginSheet) {
            QRZLoginView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showFilterSheet) {
            FilterSheetView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showDuplicateReviewSheet) {
            DuplicateReviewView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showQRZIncomingSheet) {
            QRZIncomingRequestsView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showConfirmationReconciliationSheet) {
            ConfirmationReconciliationView()
                .environmentObject(appState)
        }
        .sheet(isPresented: $appState.showLogAssistantSheet) {
            LogAssistantView()
                .environmentObject(appState)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            if appState.isMasterMode {
                try? appState.persistCurrentWorkspace(reason: "Application exit")
            }
        }
        .onChange(of: appState.showStatsSheet) { _, shouldOpen in
            guard shouldOpen else { return }
            appState.showStatsSheet = false
            openWindow(id: YAAMWindowID.statistics)
        }
    }

    // MARK: - Helper Functions
    private func selectLogFile() {
        let panel = NSOpenPanel()
        var types: [UTType] = []
        if let adiType = UTType(filenameExtension: "adi") { types.append(adiType) }
        if let adifType = UTType(filenameExtension: "adif") { types.append(adifType) }
        if let smartSDRType = UTType(filenameExtension: "smartsdrlog") { types.append(smartSDRType) }

        panel.title = "Choose Input Log"
        panel.message = "ADIF and SDR Control SmartSDR logs are supported."
        panel.prompt = "Choose Log"
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            inputPath = url.path
            updateOutputPathForFilters()
            loadConversionInput(from: url)
        }
    }

    private func selectOutputFile() {
        let panel = NSSavePanel()
        let defaultName = proposedOutputFilename()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [selectedExportFormat.utType]
        
        if panel.runModal() == .OK, let url = panel.url {
            outputPath = url.path
            appState.appendLog("Output path set: \(url.lastPathComponent)")
        }
    }

    private func updateOutputFileExtension(format: ExportLogFormat) {
        guard !outputPath.isEmpty else { return }
        let url = URL(fileURLWithPath: outputPath)
        let newExt = format.fileExtension
        outputPath = url.deletingPathExtension().appendingPathExtension(newExt).path
    }

    private func updateOutputPathForFilters() {
        let newFileName = proposedOutputFilename()

        if appState.convertSource == 0 {
            if !inputPath.isEmpty {
                let inputUrl = URL(fileURLWithPath: inputPath)
                let dirUrl = inputUrl.deletingLastPathComponent()
                outputPath = dirUrl.appendingPathComponent(newFileName).path
            } else if outputPath.isEmpty {
                outputPath = defaultExportDirectory().appendingPathComponent(newFileName).path
            } else {
                let dirUrl = URL(fileURLWithPath: outputPath).deletingLastPathComponent()
                outputPath = dirUrl.appendingPathComponent(newFileName).path
            }
        } else {
            let dirUrl = outputPath.isEmpty
                ? defaultExportDirectory()
                : URL(fileURLWithPath: outputPath).deletingLastPathComponent()
            outputPath = dirUrl.appendingPathComponent(newFileName).path
        }
    }

    private func proposedOutputFilename() -> String {
        let ext = selectedExportFormat.fileExtension
        var baseName = "processed_log"

        if appState.convertSource == 0 {
            if !inputPath.isEmpty {
                let inputUrl = URL(fileURLWithPath: inputPath)
                baseName = inputUrl.deletingPathExtension().lastPathComponent
            }
        } else {
            if let profileID = appState.convertDatabaseProfileID,
               let profile = appState.stationProfiles.first(where: { $0.id == profileID }) {
                let call = profile.normalizedCallsign.isEmpty ? profile.name : profile.normalizedCallsign
                baseName = "YAAM_Station_\(fileSafeFilterName(call))"
            } else {
                baseName = "YAAM_Database_All_Stations"
            }
        }

        var filterParts: [String] = []
        if enableFilter { filterParts.append("Contest") }
        if selectedBand != ADIFConversionFilter.allBands { filterParts.append(fileSafeFilterName(selectedBand)) }
        if selectedMode != ADIFConversionFilter.allModes { filterParts.append(fileSafeFilterName(selectedMode)) }
        let suffix = filterParts.isEmpty ? (appState.convertSource == 1 ? "_Export" : "_processed") : "_\(filterParts.joined(separator: "_"))_Slice"

        return "\(baseName)\(suffix).\(ext)"
    }

    private func defaultExportDirectory() -> URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
    }

    private var isOutputEmpty: Bool {
        if appState.convertSource == 0 {
            return inputPath.isEmpty
        } else {
            return (databaseInput?.records.isEmpty ?? true) && databaseStats.count == 0
        }
    }

    private var currentFilteredMatchCount: (matching: Int, total: Int)? {
        let records: [[String: String]]
        if appState.convertSource == 0 {
            guard let conversionInput else { return nil }
            records = conversionInput.records
        } else {
            guard let databaseInput else { return nil }
            records = databaseInput.records
        }

        let total = records.count
        guard total > 0 else { return (0, 0) }

        let normalizedStart = UTCMinuteKey.normalized(startDateTime)
        let normalizedEnd = UTCMinuteKey.normalized(endDateTime)
        let startKey = enableFilter ? UTCMinuteKey.string(from: normalizedStart) : nil
        let endKey = enableFilter ? UTCMinuteKey.string(from: normalizedEnd) : nil
        let conversionFilter = ADIFConversionFilter(
            startUTCKey: startKey,
            endUTCKey: endKey,
            band: selectedBand,
            mode: selectedMode
        )

        let matching = conversionFilter.isActive ? conversionFilter.apply(to: records).count : total
        return (matching, total)
    }

    private func processFile() {
        if appState.convertSource == 0 {
            guard !inputPath.isEmpty else {
                appState.appendLog("Error: Please select an input ADIF or SmartSDR log first.")
                return
            }
            guard !outputPath.isEmpty else {
                appState.appendLog("Error: Please specify the output file path.")
                return
            }

            do {
                let parsed: ParsedLogFile
                if let cached = conversionInput, cached.sourceURL.path == inputPath {
                    parsed = cached
                } else {
                    parsed = try LogFileReader.loadWithSecurityScopedAccess(
                        from: URL(fileURLWithPath: inputPath)
                    )
                    conversionInput = parsed
                }
                refreshConversionFilterOptions(records: parsed.records)
                executeProcessing(
                    headers: parsed.headers,
                    records: parsed.records,
                    originalADIFContent: parsed.originalADIFContent,
                    logTitle: "\(parsed.format.title) log"
                )
            } catch {
                conversionInputError = error.localizedDescription
                appState.appendLog("Error reading file: \(error.localizedDescription)")
            }
        } else {
            guard !outputPath.isEmpty else {
                appState.appendLog("Error: Please specify the output file path.")
                return
            }

            let profileName = appState.convertDatabaseProfileID.flatMap { id in
                appState.stationProfiles.first(where: { $0.id == id })?.displayTitle
            } ?? "Full Database (All Stations)"

            if let cached = databaseInput {
                executeProcessing(
                    headers: cached.headers,
                    records: cached.records,
                    originalADIFContent: nil,
                    logTitle: "YAAM Database (\(profileName))"
                )
            } else {
                do {
                    let (headers, records) = try appState.loadDatabaseQSOsForExport(profileID: appState.convertDatabaseProfileID)
                    databaseInput = (headers, records)
                    refreshConversionFilterOptions(records: records)
                    executeProcessing(
                        headers: headers,
                        records: records,
                        originalADIFContent: nil,
                        logTitle: "YAAM Database (\(profileName))"
                    )
                } catch {
                    conversionInputError = error.localizedDescription
                    appState.appendLog("Database query error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func executeProcessing(
        headers: [String],
        records initialRecords: [[String: String]],
        originalADIFContent: String?,
        logTitle: String
    ) {
        appState.appendLog("Processing \(logTitle)...")
        var records = initialRecords

        if records.isEmpty {
            appState.appendLog("Warning: No active records found in the selected source.")
            return
        }
        
        let normalizedStart = UTCMinuteKey.normalized(startDateTime)
        let normalizedEnd = UTCMinuteKey.normalized(endDateTime)
        if enableFilter, normalizedStart >= normalizedEnd {
            appState.appendLog("Error: UTC filter end time must be later than its start time.")
            return
        }

        let startKey = enableFilter ? UTCMinuteKey.string(from: normalizedStart) : nil
        let endKey = enableFilter ? UTCMinuteKey.string(from: normalizedEnd) : nil
        let conversionFilter = ADIFConversionFilter(
            startUTCKey: startKey,
            endUTCKey: endKey,
            band: selectedBand,
            mode: selectedMode
        )

        if conversionFilter.isActive {
            var filterDescription: [String] = []
            if let startKey, let endKey { filterDescription.append("UTC \(startKey)..<\(endKey)") }
            if selectedBand != ADIFConversionFilter.allBands { filterDescription.append("Band \(selectedBand)") }
            if selectedMode != ADIFConversionFilter.allModes { filterDescription.append("Mode \(selectedMode)") }
            appState.appendLog("Applying conversion filters: \(filterDescription.joined(separator: " | "))")

            let originalCount = records.count
            records = conversionFilter.apply(to: records)
            appState.appendLog("Filter matched \(records.count) of \(originalCount) record(s).")

            if enableFilter {
                records.sort { (r1, r2) -> Bool in
                    let d1 = r1["QSO_DATE"] ?? ""
                    let d2 = r2["QSO_DATE"] ?? ""
                    if d1 != d2 { return d1 < d2 }

                    let t1 = normalizeTime(r1["TIME_ON"] ?? "")
                    let t2 = normalizeTime(r2["TIME_ON"] ?? "")
                    return t1 < t2
                }
            }
        }
        
        if records.isEmpty {
            appState.appendLog("No records matched the active conversion filters.")
            return
        }
        
        appState.appendLog("Processed \(records.count) record(s).")
        let exportHeaders = effectiveExportHeaders(baseHeaders: headers, records: records)

        let dir = URL(fileURLWithPath: outputPath).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        
        let activeCallsign = appState.currentStationCallsign.isEmpty ? "NOCALL" : appState.currentStationCallsign

        switch selectedExportFormat {
        case .excelCSV:
            let csvContent = generateCSV(headers: exportHeaders, records: records)
            let bom = "\u{FEFF}"
            let finalCSV = bom + csvContent
            do {
                try finalCSV.write(toFile: outputPath, atomically: true, encoding: .utf8)
                appState.appendLog("Excel / CSV conversion completed successfully!")
                appState.appendLog("Output saved to: \(outputPath)")
            } catch {
                appState.appendLog("Error saving CSV file: \(error.localizedDescription)")
            }

        case .adif:
            let adifOutput = generateADIF(
                originalContent: originalADIFContent ?? "",
                records: records
            )
            do {
                try adifOutput.write(toFile: outputPath, atomically: true, encoding: .utf8)
                appState.appendLog("ADIF export completed successfully!")
                appState.appendLog("Output saved to: \(outputPath)")
            } catch {
                appState.appendLog("Error saving ADIF file: \(error.localizedDescription)")
            }

        case .cabrillo:
            var options = CabrilloExportOptions(
                contestID: cabrilloContestID.isEmpty ? "CQ-WW-SSB" : cabrilloContestID,
                callsign: activeCallsign,
                categoryOperator: cabrilloOperatorCategory,
                categoryPower: cabrilloPowerCategory,
                claimedScore: Int(cabrilloClaimedScore) ?? 0
            )
            if let station = appState.activeStationProfile {
                options.name = station.name
                options.address = station.qth
                options.country = station.country
            }
            let cabrilloOutput = LogExportEngine.generateCabrillo(records: records, options: options)
            do {
                try cabrilloOutput.write(toFile: outputPath, atomically: true, encoding: .utf8)
                appState.appendLog("Cabrillo 3.0 contest log export completed successfully!")
                appState.appendLog("Output saved to: \(outputPath)")
            } catch {
                appState.appendLog("Error saving Cabrillo file: \(error.localizedDescription)")
            }

        case .json:
            let jsonOutput = LogExportEngine.generateJSON(records: records)
            do {
                try jsonOutput.write(toFile: outputPath, atomically: true, encoding: .utf8)
                appState.appendLog("JSON database export completed successfully!")
                appState.appendLog("Output saved to: \(outputPath)")
            } catch {
                appState.appendLog("Error saving JSON file: \(error.localizedDescription)")
            }

        case .html:
            let htmlOutput = LogExportEngine.generateHTML(
                headers: exportHeaders,
                records: records,
                title: "YAAM Station Logbook Report",
                callsign: activeCallsign
            )
            do {
                try htmlOutput.write(toFile: outputPath, atomically: true, encoding: .utf8)
                appState.appendLog("Interactive HTML report generated successfully!")
                appState.appendLog("Output saved to: \(outputPath)")
            } catch {
                appState.appendLog("Error saving HTML file: \(error.localizedDescription)")
            }

        case .textSummary:
            let srcTitle = appState.convertSource == 1 ? "YAAM Database" : (inputPath.isEmpty ? "External File" : URL(fileURLWithPath: inputPath).lastPathComponent)
            let textOutput = LogExportEngine.generateTextSummary(
                records: records,
                callsign: activeCallsign,
                sourceName: srcTitle
            )
            do {
                try textOutput.write(toFile: outputPath, atomically: true, encoding: .utf8)
                appState.appendLog("Text summary report generated successfully!")
                appState.appendLog("Output saved to: \(outputPath)")
            } catch {
                appState.appendLog("Error saving Text file: \(error.localizedDescription)")
            }
        }
    }

    private func effectiveExportHeaders(baseHeaders: [String], records: [[String: String]]) -> [String] {
        var headerSet = Set(baseHeaders)
        var result = baseHeaders
        let priorityHeaders = ["QSO_DATE", "TIME_ON", "CALL", "FREQ", "BAND", "MODE", "RST_SENT", "RST_RCVD", "NAME", "QTH", "COMMENT"]
        
        for record in records {
            for key in record.keys {
                if !headerSet.contains(key) {
                    headerSet.insert(key)
                    result.append(key)
                }
            }
        }
        
        var finalHeaders: [String] = []
        for key in priorityHeaders {
            if headerSet.contains(key) {
                finalHeaders.append(key)
                headerSet.remove(key)
            }
        }
        for header in result {
            if headerSet.contains(header) {
                finalHeaders.append(header)
                headerSet.remove(header)
            }
        }
        finalHeaders.append(contentsOf: headerSet.sorted())
        return finalHeaders
    }

    private func openOutputFile() {
        guard !outputPath.isEmpty, FileManager.default.fileExists(atPath: outputPath) else {
            appState.appendLog("Error: Output file does not exist or has not been created yet.")
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: outputPath))
        appState.appendLog("Opened output file in default application.")
    }

    private func revealOutputFile() {
        guard !outputPath.isEmpty, FileManager.default.fileExists(atPath: outputPath) else {
            appState.appendLog("Error: Output file does not exist or has not been created yet.")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outputPath)])
        appState.appendLog("Revealed output file in Finder.")
    }

    private func loadConversionInput(from url: URL) {
        guard !url.path.isEmpty else { return }
        let loadID = UUID()
        conversionLoadID = loadID
        isReadingConversionInput = true
        conversionInputError = nil

        Task { @MainActor in
            do {
                let parsed = try await Task.detached(priority: .userInitiated) {
                    try LogFileReader.loadWithSecurityScopedAccess(from: url)
                }.value
                guard conversionLoadID == loadID else { return }

                conversionLoadID = nil
                isReadingConversionInput = false
                conversionInput = parsed
                refreshConversionFilterOptions(records: parsed.records)
                updateOutputPathForFilters()

                var details = "Loaded \(parsed.records.count) \(parsed.format.title) QSO(s) for conversion"
                if parsed.ignoredDeletedRecordCount > 0 {
                    details += "; \(parsed.ignoredDeletedRecordCount) deleted record(s) ignored"
                }
                appState.appendLog(details + ".")
            } catch {
                guard conversionLoadID == loadID else { return }
                conversionLoadID = nil
                isReadingConversionInput = false
                conversionInput = nil
                conversionInputError = error.localizedDescription
                appState.appendLog("Input log failed: \(error.localizedDescription)")
            }
        }
    }

    private func loadDatabaseSource() {
        let loadID = UUID()
        conversionLoadID = loadID
        isReadingConversionInput = true
        conversionInputError = nil
        let targetProfileID = appState.convertDatabaseProfileID

        Task { @MainActor in
            do {
                let (headers, records) = try await Task.detached(priority: .userInitiated) {
                    try await appState.loadDatabaseQSOsForExport(profileID: targetProfileID)
                }.value
                guard conversionLoadID == loadID else { return }

                conversionLoadID = nil
                isReadingConversionInput = false
                databaseInput = (headers, records)
                databaseStats = appState.fetchDatabaseQSOStats(profileID: targetProfileID)
                refreshConversionFilterOptions(records: records)
                updateOutputPathForFilters()

                let profileName = targetProfileID.flatMap { id in
                    appState.stationProfiles.first(where: { $0.id == id })?.displayTitle
                } ?? "All Stations"
                appState.appendLog("Loaded \(records.count) QSO(s) from YAAM Database (\(profileName)).")
            } catch {
                guard conversionLoadID == loadID else { return }
                conversionLoadID = nil
                isReadingConversionInput = false
                databaseInput = nil
                conversionInputError = error.localizedDescription
                appState.appendLog("Database query failed: \(error.localizedDescription)")
            }
        }
    }

    @ViewBuilder
    private var conversionInputStatus: some View {
        if isReadingConversionInput {
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text("Reading input log...")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let parsed = conversionInput {
            HStack(spacing: 8) {
                Label(parsed.format.title, systemImage: parsed.format.systemImage)
                    .foregroundStyle(.blue)
                Divider().frame(height: 12)
                Text("\(parsed.records.count.formatted()) QSOs")
                if parsed.ignoredDeletedRecordCount > 0 {
                    Divider().frame(height: 12)
                    Label(
                        "\(parsed.ignoredDeletedRecordCount.formatted()) deleted skipped",
                        systemImage: "trash.slash"
                    )
                }
                if parsed.validationIssueCount > 0 {
                    Divider().frame(height: 12)
                    Label(
                        "\(parsed.validationIssueCount.formatted()) need review",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        } else if let conversionInputError {
            Label(conversionInputError, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private var databaseInputStatus: some View {
        if isReadingConversionInput {
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text("Querying YAAM database...")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let databaseInput {
            HStack(spacing: 12) {
                Label("Protected SQLite", systemImage: "lock.shield.fill")
                    .foregroundColor(.green)

                Divider().frame(height: 12)

                Label("\(databaseInput.records.count.formatted()) QSOs", systemImage: "tray.full.fill")
                    .foregroundColor(.primary)

                if let firstDate = databaseStats.firstDate, let lastDate = databaseStats.lastDate {
                    Divider().frame(height: 12)
                    Label("\(firstDate) ➔ \(lastDate)", systemImage: "calendar")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Divider().frame(height: 12)

                Text("\(databaseInput.headers.count) fields")
                    .foregroundColor(.secondary)
            }
            .font(.caption.weight(.medium))
        } else if let conversionInputError {
            Label(conversionInputError, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private var conversionStatusTitle: String {
        if isReadingConversionInput { return "Reading Data..." }
        if conversionInputError != nil { return "Source Error" }
        return "Ready to Export"
    }

    private var conversionStatusColor: Color {
        if isReadingConversionInput { return .orange }
        if conversionInputError != nil { return .red }
        return .green
    }

    private var isBandModeFilterActive: Bool {
        selectedBand != ADIFConversionFilter.allBands || selectedMode != ADIFConversionFilter.allModes
    }

    private var conversionBandPicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Band", systemImage: "waveform.path")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Picker("Band", selection: $selectedBand) {
                ForEach(conversionBands, id: \.self) { band in
                    Text(band).tag(band)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 180, maxWidth: 240, alignment: .leading)
            .onChange(of: selectedBand) { _, _ in updateOutputPathForFilters() }
        }
    }

    private var conversionModePicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Mode / Submode", systemImage: "dial.medium")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Picker("Mode / Submode", selection: $selectedMode) {
                ForEach(conversionModes, id: \.self) { mode in
                    Text(mode).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 180, maxWidth: 240, alignment: .leading)
            .onChange(of: selectedMode) { _, _ in updateOutputPathForFilters() }
        }
    }

    private func refreshConversionFilterOptions(records: [[String: String]]) {
        let detectedBands = ADIFConversionFilter.availableBands(in: records)
        let detectedModes = ADIFConversionFilter.availableModes(in: records)

        var bands = detectedBands.isEmpty ? ADIFConversionFilter.defaultBands : detectedBands
        if selectedBand != ADIFConversionFilter.allBands, !bands.contains(selectedBand) { bands.append(selectedBand) }
        conversionBands = [ADIFConversionFilter.allBands] + bands

        var modes = detectedModes.isEmpty ? ADIFConversionFilter.defaultModes : detectedModes
        if selectedMode != ADIFConversionFilter.allModes, !modes.contains(selectedMode) { modes.append(selectedMode) }
        conversionModes = [ADIFConversionFilter.allModes] + modes
    }

    private func fileSafeFilterName(_ value: String) -> String {
        value.map { $0.isLetter || $0.isNumber || $0 == "." ? String($0) : "_" }.joined()
    }
}
