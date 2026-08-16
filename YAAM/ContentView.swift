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
    
    @State private var adifPath: String = ""
    @State private var outputPath: String = ""
    
    // Conversion & Output Options
    @State private var convertToCSV: Bool = true
    
    // Contest / UTC Time Filter Settings
    @State private var enableFilter: Bool = false
    @State private var startDateTime: Date = Date()
    @State private var endDateTime: Date = Date().addingTimeInterval(7200)
    
    private var utcFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Top Global Tab Navigation Selector
            Picker("", selection: $appState.selectedTab) {
                Text("Log Table Viewer").tag(0)
                Text("Filter & Convert Tool").tag(1)
                Text("Global Leaderboard").tag(2) // <--- NEW LEADERBOARD TAB
                Text("DX Advisor").tag(3)
            }
            .pickerStyle(.segmented)
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // MARK: - Tab Views Routing
            if appState.selectedTab == 0 {
                // Tab 0: ADIFMaster High-Performance Table Grid
                LogTableView()
            } else if appState.selectedTab == 1 {
                // Tab 1: Conversion & Contest Filter Tool
                VStack(alignment: .leading, spacing: 14) {
                    // Row 1: ADIF File Picker
                    HStack(spacing: 10) {
                        TextField("Input ADIF file path...", text: $adifPath)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("ADIF File") {
                            selectADIFFile()
                        }
                        .frame(width: 100)
                    }
                    
                    // Row 2: Output File Picker
                    HStack(spacing: 10) {
                        TextField("Output file path...", text: $outputPath)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Output File") {
                            selectOutputFile()
                        }
                        .frame(width: 100)
                    }
                    
                    // Row 3: Output Options & Animated UTC Filter Card
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Convert Output to CSV / Excel", isOn: $convertToCSV)
                            .font(.headline)
                            .onChange(of: convertToCSV) { _, newValue in
                                updateOutputFileExtension(isCSV: newValue)
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
                        .onChange(of: enableFilter) { _, isFilterOn in
                            if isFilterOn {
                                convertToCSV = false
                            }
                            updateOutputPathForFilter(isFilterOn: isFilterOn)
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
                                    Text("\(utcFormatter.string(from: startDateTime)) ➔ \(utcFormatter.string(from: endDateTime))")
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
                    }
                    .padding(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    
                    // Row 4: Action Buttons
                    HStack(spacing: 12) {
                        Button(action: { processFile() }) {
                            HStack {
                                Image(systemName: "gearshape.fill")
                                Text("Process Log")
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        
                        Button(action: { openOutputFile() }) {
                            HStack {
                                Image(systemName: "arrow.up.forward.app")
                                Text("Open Output File")
                            }
                        }
                        
                        Spacer()
                    }
                    
                    // Row 5: Terminal Console Log
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Console & Activity Log", systemImage: "terminal.fill")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Circle()
                                .fill(Color.green)
                                .frame(width: 7, height: 7)
                            
                            Text("Ready")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 4)
                        
                        TextEditor(text: .constant(appState.logText))
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 120, maxHeight: .infinity)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                            )
                    }
                }
                .padding(16)
            } else if appState.selectedTab == 2 {
                // Tab 2: NEW FULL-PAGE LEADERBOARD VIEW
                LeaderboardView()
            } else if appState.selectedTab == 3 {
                DXAdvisorView()
            }
        }
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
    }

    // MARK: - Helper Functions
    private func selectADIFFile() {
        let panel = NSOpenPanel()
        var types: [UTType] = [.plainText]
        if let adiType = UTType(filenameExtension: "adi") { types.append(adiType) }
        if let adifType = UTType(filenameExtension: "adif") { types.append(adifType) }
        
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        if panel.runModal() == .OK, let url = panel.url {
            adifPath = url.path
            appState.loadADIFFile(from: url)
            updateOutputPathForFilter(isFilterOn: enableFilter)
        }
    }

    private func selectOutputFile() {
        let panel = NSSavePanel()
        if convertToCSV {
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "processed_log.csv"
        } else {
            var types: [UTType] = [.plainText]
            if let adiType = UTType(filenameExtension: "adi") { types.append(adiType) }
            panel.allowedContentTypes = types
            panel.nameFieldStringValue = "processed_log.adi"
        }
        
        if panel.runModal() == .OK, let url = panel.url {
            outputPath = url.path
            appState.appendLog("Output path set: \(url.lastPathComponent)")
        }
    }

    private func updateOutputFileExtension(isCSV: Bool) {
        guard !outputPath.isEmpty else { return }
        let url = URL(fileURLWithPath: outputPath)
        let newExt = isCSV ? "csv" : "adi"
        outputPath = url.deletingPathExtension().appendingPathExtension(newExt).path
    }

    private func updateOutputPathForFilter(isFilterOn: Bool) {
        guard !adifPath.isEmpty else { return }
        let inputUrl = URL(fileURLWithPath: adifPath)
        let baseName = inputUrl.deletingPathExtension().lastPathComponent
        let dirUrl = inputUrl.deletingLastPathComponent()
        
        let ext = convertToCSV ? "csv" : "adi"
        let suffix = isFilterOn ? "_Contest_Slice" : "_processed"
        
        let newFileName = "\(baseName)\(suffix).\(ext)"
        outputPath = dirUrl.appendingPathComponent(newFileName).path
    }

    private func processFile() {
        guard !adifPath.isEmpty else {
            appState.appendLog("Error: Please select an input ADIF file first.")
            return
        }
        guard !outputPath.isEmpty else {
            appState.appendLog("Error: Please specify the output file path.")
            return
        }

        do {
            let adifContent = try String(contentsOfFile: adifPath, encoding: .utf8)
            executeProcessing(content: adifContent)
        } catch {
            do {
                let adifContent = try String(contentsOfFile: adifPath, encoding: .isoLatin1)
                executeProcessing(content: adifContent)
            } catch {
                appState.appendLog("Error reading file: \(error.localizedDescription)")
            }
        }
    }

    private func executeProcessing(content: String) {
        appState.appendLog("Parsing ADIF structure...")
        var (headers, records) = parseADIF(content: content)
        
        if records.isEmpty {
            appState.appendLog("Warning: No records found in the ADIF file.")
            return
        }
        
        if enableFilter {
            let startKey = utcFormatter.string(from: startDateTime)
            let endKey = utcFormatter.string(from: endDateTime)
            
            appState.appendLog("Applying UTC Contest Filter -> Window: [\(startKey) <= DATETIME < \(endKey)]...")
            
            records = records.filter { record in
                guard let qsoDate = record["QSO_DATE"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let rawTimeOn = record["TIME_ON"]?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return false
                }
                
                let timeOn = normalizeTime(rawTimeOn)
                let recordKey = qsoDate + timeOn
                return recordKey >= startKey && recordKey < endKey
            }
            
            records.sort { (r1, r2) -> Bool in
                let d1 = r1["QSO_DATE"] ?? ""
                let d2 = r2["QSO_DATE"] ?? ""
                if d1 != d2 { return d1 < d2 }
                
                let t1 = normalizeTime(r1["TIME_ON"] ?? "")
                let t2 = normalizeTime(r2["TIME_ON"] ?? "")
                return t1 < t2
            }
        }
        
        if records.isEmpty {
            appState.appendLog("No records matched the specified UTC filter criteria.")
            return
        }
        
        appState.appendLog("Processed \(records.count) record(s).")
        
        if convertToCSV {
            let csvContent = generateCSV(headers: headers, records: records)
            let bom = "\u{FEFF}"
            let finalCSV = bom + csvContent
            
            do {
                try finalCSV.write(toFile: outputPath, atomically: true, encoding: .utf8)
                appState.appendLog("CSV conversion completed successfully!")
                appState.appendLog("Output saved to: \(outputPath)")
            } catch {
                appState.appendLog("Error saving CSV file: \(error.localizedDescription)")
            }
        } else {
            let adifOutput = generateADIF(originalContent: content, records: records)
            
            do {
                try adifOutput.write(toFile: outputPath, atomically: true, encoding: .utf8)
                appState.appendLog("ADIF processing completed successfully!")
                appState.appendLog("Output saved to: \(outputPath)")
            } catch {
                appState.appendLog("Error saving ADIF file: \(error.localizedDescription)")
            }
        }
    }

    private func openOutputFile() {
        guard !outputPath.isEmpty, FileManager.default.fileExists(atPath: outputPath) else {
            appState.appendLog("Error: Output file does not exist or has not been created yet.")
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: outputPath))
        appState.appendLog("Opened output file in default application.")
    }
}
