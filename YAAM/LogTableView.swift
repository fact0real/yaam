//
//  LogTableView.swift
//  YAAM
//
//  Created by factoreal on 7/30/26.
//

import SwiftUI

// MARK: - High Performance Spreadsheet Table View Component
struct LogTableView: View {
    @EnvironmentObject var appState: AppState
    
    // Cell Editing Inline State Tracks
    @State private var editingCellID: UUID? = nil
    @State private var editingHeader: String? = nil
    @State private var editingText: String = ""
    
    // Resizable Columns State
    @State private var columnWidths: [String: CGFloat] = [:]
    @State private var dragStartWidths: [String: CGFloat] = [:]

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Toolbar & Quick Actions Summary Bar
            HStack(spacing: 10) {
                
                // 1. Internal Database Recent Files Dropdown Menu
                Menu {
                    if appState.recentLogFiles.isEmpty {
                        Text("No recent logs found in database")
                    } else {
                        ForEach(appState.recentLogFiles, id: \.self) { url in
                            Button(action: {
                                appState.loadADIFFile(from: url)
                            }) {
                                HStack {
                                    Image(systemName: "doc.text")
                                    Text(url.lastPathComponent)
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Import New Log...") {
                        appState.importADIFDialog()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundColor(.blue)
                        Text("Database")
                            .fontWeight(.semibold)
                    }
                }
                .menuStyle(.borderlessButton)
                .frame(width: 85)
                
                Divider().frame(height: 14)
                
                // Standalone Cloud Logbook Fetcher (With Native Confirmation Dialog)
                Button(action: { appState.confirmAndFetchCloudLogbook() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "icloud.and.arrow.down.fill")
                            .foregroundColor(.blue)
                        Text("Cloud Logbook")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                }
                .buttonStyle(.plain)
                
                Divider().frame(height: 14)

                // ENRICH DATA / STOP ENRICHING TOGGLE BUTTON
                if appState.isEnriching {
                    Button(action: { appState.stopEnrichment() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.circle.fill")
                                .foregroundColor(.red)
                            Text("Stop Enriching")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                        }
                    }
                    .buttonStyle(.plain)
                } else if !appState.selectedRecordIDs.isEmpty {
                    // Enrich Selected Rows Button (Max 19)
                    Button(action: { appState.enrichSelectedRecords() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars.inverse")
                                .foregroundColor(.orange)
                            Text("Enrich Selected (\(appState.selectedRecordIDs.count))")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { appState.clearSelection() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear row selections")
                } else {
                    Button(action: { appState.enrichLogData() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "wand.and.stars")
                                .foregroundColor(.purple)
                            Text("Enrich Data")
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.qsoRecords.isEmpty)
                }
                
                Divider().frame(height: 14)
                
                // QRZ Re-Authentication Button
                Button(action: { appState.forceQRZReLogin() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "key.fill")
                            .foregroundColor(.green)
                        Text("QRZ Login")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.plain)
                .help("Re-authenticate with QRZ.com to refresh expired session cookies")
                
                Divider().frame(height: 14)
                
                // SMTP Settings Button
                Button(action: { appState.showSMTPSettings = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.gray)
                        Text("SMTP")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.plain)
                
                Divider().frame(height: 14)

                // 2. Toolbar Global Search Input Field
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    TextField("Search log or columns...", text: $appState.searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !appState.searchText.isEmpty {
                        Button(action: { appState.searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                .frame(width: 170)
                
                Divider().frame(height: 14)
                
                // 3. Filters Sheet Trigger
                Button(action: { appState.showFilterSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: appState.filterCriteria.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundColor(appState.filterCriteria.isActive ? .orange : .primary)
                        Text(appState.filterCriteria.isActive ? "Filters Active" : "Filters...")
                            .fontWeight(appState.filterCriteria.isActive ? .bold : .regular)
                    }
                }
                
                if appState.filterCriteria.isActive {
                    Button(action: { appState.filterCriteria.reset() }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { appState.exportFilteredLogAs() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down.fill").foregroundColor(.green)
                            Text("Export (\(appState.filteredRecords.count))")
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                    }
                }
                
                Divider().frame(height: 14)
                
                // 4. Cloud QSL Sync Button (QRZ & LoTW)
                Button(action: { appState.syncConfirmations() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise.icloud")
                            .foregroundColor(appState.isSyncingAPI ? .gray : .cyan)
                        Text("Sync QSLs")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
                .disabled(appState.isSyncingAPI || appState.qsoRecords.isEmpty)
                
                // 5. Statistics Dashboard Sheet Trigger
                Button(action: { appState.showStatsSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(.purple)
                        Text("Statistics")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
                
                Divider().frame(height: 14)
                
                // 6. Analytics Quick Summary
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("📻 QSOs:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(appState.qsoRecords.count)")
                            .font(.caption)
                            .bold()
                    }
                    
                    HStack(spacing: 4) {
                        Text("🌍 DXCC:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(appState.availableCountries.count)")
                            .font(.caption)
                            .bold()
                    }
                }
                
                Spacer()
                
                if appState.isLoading || appState.isSyncingAPI || appState.isEnriching {
                    ProgressView()
                        .scaleEffect(0.6)
                        .padding(.trailing, 4)
                }
                
                Text("Tip: Click checkbox to select up to 19 rows")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()

            // MARK: - Table View Content Rendering
            if appState.isLoading {
                VStack(spacing: 16) {
                    ProgressView("Processing Log File...")
                        .progressViewStyle(.circular)
                    Text("Executing background queue operations...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            } else if appState.qsoRecords.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tablecells")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Log Loaded")
                        .font(.title3)
                        .bold()
                    Text("Use File ➔ Import ADIF Log... (⌘O) or select a recent file from Database.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button("Import ADIF File") {
                        appState.importADIFDialog()
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            } else {
                // MARK: - Strict Top-Anchored Scrollable View
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Fixed Top Header Row
                        headerRowView
                        
                        // Vertical Scrollable Log Rows Area
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(appState.filteredRecords) { record in
                                    rowView(for: record)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                }
                .coordinateSpace(name: "TableScroll")
                .background(Color(NSColor.textBackgroundColor))
            }
            
            Divider()
            
            // MARK: - Bottom Status Bar
            HStack {
                Text(appState.loadedFileName.isEmpty ? "Ready" : "File: \(appState.loadedFileName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !appState.selectedRecordIDs.isEmpty {
                    Text("Selected: \(appState.selectedRecordIDs.count) / 19 Max")
                        .font(.system(.caption, design: .monospaced))
                        .bold()
                        .foregroundColor(.blue)
                        .padding(.trailing, 8)
                }
                
                if appState.filterCriteria.isActive || !appState.searchText.isEmpty {
                    Text("Filtered: \(appState.filteredRecords.count) / Total: \(appState.qsoRecords.count)")
                        .font(.system(.caption, design: .monospaced))
                        .bold()
                        .foregroundColor(.orange)
                } else {
                    Text("QSOs: \(appState.qsoRecords.count)")
                        .font(.system(.caption, design: .monospaced))
                        .bold()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .sheet(isPresented: $appState.showFilterSheet) {
            FilterSheetView().environmentObject(appState)
        }
        .sheet(isPresented: $appState.showStatsSheet) {
            StatisticsView().environmentObject(appState)
        }
        .sheet(isPresented: $appState.showEmailComposer) {
            EmailComposerView().environmentObject(appState)
        }
        .sheet(isPresented: $appState.showSMTPSettings) {
            SMTPSettingsView()
        }
        .sheet(isPresented: $appState.showQRZLoginSheet) {
            QRZLoginView().environmentObject(appState)
        }
    }

    // MARK: - Subviews & Layout Elements

    private var headerRowView: some View {
        HStack(spacing: 0) {
            // 1. Sticky Index Header
            GeometryReader { geo in
                let minX = geo.frame(in: .named("TableScroll")).minX
                let isPinned = minX < 0
                let offset = isPinned ? -minX : 0
                
                HStack(spacing: 4) {
                    Text("#")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .frame(width: 80, height: 28, alignment: .center)
                .background(Color.accentColor)
                .border(Color.black.opacity(0.3), width: 0.5)
                .shadow(color: isPinned ? Color.black.opacity(0.4) : .clear, radius: 3, x: 2, y: 0)
                .offset(x: offset)
            }
            .frame(width: 80, height: 28)
            .zIndex(10)
            
            // 2. Click-to-Sort & Resizable Scrollable Headers
            ForEach(appState.tableHeaders, id: \.self) { header in
                let w = columnWidths[header] ?? defaultColumnWidth(for: header)
                let isSorted = appState.sortHeader == header
                
                HStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Text(header)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if isSorted {
                            Image(systemName: appState.sortAscending ? "arrow.up" : "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.yellow)
                        }
                        
                        Spacer(minLength: 0)
                        
                        Button(action: { appState.deleteColumn(header: header) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 6)
                    .frame(width: max(0, w - 6), height: 28, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        appState.toggleSort(for: header)
                    }
                    
                    Rectangle()
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 6, height: 28)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if dragStartWidths[header] == nil {
                                        dragStartWidths[header] = columnWidths[header] ?? defaultColumnWidth(for: header)
                                    }
                                    if let start = dragStartWidths[header] {
                                        columnWidths[header] = max(40, start + value.translation.width)
                                    }
                                }
                                .onEnded { _ in
                                    dragStartWidths[header] = nil
                                }
                        )
                }
                .frame(width: w, height: 28)
                .background(isSorted ? Color.accentColor.opacity(0.85) : Color.accentColor)
                .border(Color.black.opacity(0.3), width: 0.5)
                .contextMenu {
                    Button("Sort Ascending") {
                        appState.sortHeader = header
                        appState.sortAscending = true
                    }
                    Button("Sort Descending") {
                        appState.sortHeader = header
                        appState.sortAscending = false
                    }
                    Divider()
                    Button("Delete Column '\(header)'") {
                        appState.deleteColumn(header: header)
                    }
                }
            }
        }
    }

    private func rowView(for record: QSORecordModel) -> some View {
        let isSelected = appState.selectedRecordIDs.contains(record.id)
        let statusBgColor = isSelected ? Color.accentColor.opacity(0.35) : (record.isConfirmed ? Color.green.opacity(0.15) : Color.orange.opacity(0.12))
        let call = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        return HStack(spacing: 0) {
            // 1. Sticky Index Cell (With Checkbox Selection + Delete Button)
            GeometryReader { geo in
                let minX = geo.frame(in: .named("TableScroll")).minX
                let isPinned = minX < 0
                let offset = isPinned ? -minX : 0
                
                HStack(spacing: 4) {
                    // Checkbox Button
                    Button(action: { appState.toggleRecordSelection(record.id) }) {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .font(.system(size: 11))
                            .foregroundColor(isSelected ? .accentColor : .gray)
                    }
                    .buttonStyle(.plain)
                    
                    // Delete Button
                    Button(action: { appState.deleteRecord(id: record.id) }) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    
                    Text("\(record.index)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .frame(width: 80, height: 28, alignment: .center)
                .background(statusBgColor)
                .border(Color.gray.opacity(0.2), width: 0.5)
                .shadow(color: isPinned ? Color.black.opacity(0.2) : .clear, radius: 3, x: 2, y: 0)
                .offset(x: offset)
            }
            .frame(width: 80, height: 28)
            .zIndex(10)
            
            // 2. Scrollable Data Cells with Enrichment Formatting
            ForEach(appState.tableHeaders, id: \.self) { header in
                let w = columnWidths[header] ?? defaultColumnWidth(for: header)
                let val = record[header]
                
                ZStack {
                    if editingCellID == record.id && editingHeader == header {
                        TextField("", text: $editingText, onCommit: {
                            appState.updateCell(recordID: record.id, header: header, newValue: editingText)
                            editingCellID = nil
                            editingHeader = nil
                        })
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 4)
                        .background(Color(NSColor.selectedControlColor).opacity(0.3))
                    } else {
                        HStack(spacing: 4) {
                            // Country Flag Renderer
                            if header == "COUNTRY" && !val.isEmpty {
                                Text(countryToFlag(val))
                                    .font(.system(size: 10))
                            }
                            
                            // Interactive QRZ Profile URL Renderer
                            if header == "QRZ_URL" || header == "QRZ" {
                                let targetUrlStr = val.isEmpty ? "https://www.qrz.com/db/\(call)" : val
                                HStack(spacing: 4) {
                                    Image(systemName: "safari.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.blue)
                                    Text(targetUrlStr)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.blue)
                                        .underline()
                                        .lineLimit(1)
                                }
                                .onTapGesture {
                                    if let url = URL(string: "https://www.qrz.com/db/\(call)"), !call.isEmpty {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .help("Click to open \(call) profile on QRZ.com")
                            }
                            // Email Links Renderer
                            else if header == "EMAIL" && !val.isEmpty {
                                Text(val)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.blue)
                                    .underline()
                                    .onTapGesture {
                                        appState.selectedEmailCallsign = record["CALL"]
                                        appState.selectedEmailAddress = val
                                        appState.showEmailComposer = true
                                    }
                                    .help("Click to send an email")
                            }
                            // QRZ Ranks Renderer
                            else if header.hasPrefix("RANK_") && !val.isEmpty {
                                Text(val)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(header == "RANK_QSO" ? .blue : (header == "RANK_BAND" ? .orange : .green))
                                    .padding(.horizontal, 4)
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(4)
                            }
                            // Standard Text Renderer
                            else {
                                Text(val)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 6)
                .frame(width: w, height: 28, alignment: .leading)
                .background(statusBgColor)
                .border(Color.gray.opacity(0.2), width: 0.5)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Prevent normal editing mode if it's an email link or URL link
                    if header != "EMAIL" && header != "QRZ_URL" && header != "QRZ" {
                        editingCellID = record.id
                        editingHeader = header
                        editingText = val
                    }
                }
                .contextMenu {
                    // Selection Options
                    Button(isSelected ? "Deselect Row #\(record.index)" : "Select Row #\(record.index)") {
                        appState.toggleRecordSelection(record.id)
                    }
                    
                    if !call.isEmpty {
                        Button("🪄 Enrich Callsign '\(call)'") {
                            appState.enrichLogData(targetCallsigns: [call])
                        }
                    }
                    
                    if !appState.selectedRecordIDs.isEmpty {
                        Button("🪄 Enrich Selected (\(appState.selectedRecordIDs.count) Rows)") {
                            appState.enrichSelectedRecords()
                        }
                    }
                    
                    Divider()
                    
                    Button("Delete Record #\(record.index)") {
                        appState.deleteRecord(id: record.id)
                    }
                    Button("Delete Column '\(header)'") {
                        appState.deleteColumn(header: header)
                    }
                }
            }
        }
    }

    private func defaultColumnWidth(for header: String) -> CGFloat {
        switch header {
        case "EMAIL": return 150
        case "QRZ_URL", "QRZ": return 180
        case "RANK_QSO", "RANK_BAND", "RANK_DXCC": return 90
        case "QSO_DATE": return 90
        case "TIME_ON", "TIME_OFF": return 75
        case "CALL": return 90
        case "FREQ", "FREQ_RX": return 90
        case "BAND", "MODE", "SUBMODE": return 65
        case "RST_SENT", "RST_RCVD": return 70
        case "NAME": return 140
        case "COUNTRY": return 130
        case "COMMENT": return 180
        default: return 85
        }
    }
}
