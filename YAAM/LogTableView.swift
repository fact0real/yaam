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
    
    @State private var editingCellID: UUID? = nil
    @State private var editingHeader: String? = nil
    @State private var editingText: String = ""
    
    @State private var columnWidths: [String: CGFloat] = [:]
    @State private var dragStartWidths: [String: CGFloat] = [:]
    @State private var explicitlyShownColumns: Set<String> = []
    @State private var showFullConfirmationSyncPrompt = false

    private let compactCenteredColumns: Set<String> = [
        "TIME",
        "TIME_ON",
        "CALL",
        "FREQ",
        "BAND",
        "BAND_RX",
        "MODE",
        "CONT",
        "RST_SENT",
        "RST_RCVD",
        ConfirmationCreditColumn.countryBand,
        ConfirmationCreditColumn.grid
    ]

    private let preferredColumnOrder = [
        "QSO_DATE", "TIME_ON", "CALL", "FREQ", "BAND", "MODE", "RST_SENT", "RST_RCVD",
        "NAME", "QTH", "CONT", "COUNTRY", ConfirmationCreditColumn.countryBand,
        ConfirmationCreditColumn.grid, "DXCC", "CQZ", "ITUZ"
    ]

    private var utilityColumnWidth: CGFloat {
        appState.filterCriteria.isActive ? 82 : 48
    }

    var body: some View {
        let visibleRecords = appState.filteredRecords

        VStack(spacing: 0) {
            // MARK: - Toolbar & Quick Actions Summary Bar
            HStack(spacing: 10) {
                
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
                        appState.importLogDialog()
                    }
                    Divider()
                    Button {
                        appState.prepareDuplicateReview()
                    } label: {
                        Label("Review Duplicate QSOs...", systemImage: "doc.on.doc")
                    }
                    .disabled(appState.qsoRecords.isEmpty || appState.isAnalyzingDuplicates)
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

                Menu {
                    ForEach(appState.stationProfiles) { profile in
                        Button {
                            activateStation(profile)
                        } label: {
                            Label(
                                profile.displayTitle,
                                systemImage: profile.id == appState.activeStationProfileID ? "checkmark" : "antenna.radiowaves.left.and.right"
                            )
                        }
                    }
                    Divider()
                    SettingsLink {
                        Label("Manage Stations", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.green)
                        Text(appState.currentStationCallsign)
                            .font(.caption.monospaced().weight(.semibold))
                    }
                }
                .menuStyle(.borderlessButton)
                .frame(width: 108)
                .help("Active station profile")

                Divider().frame(height: 14)
                
                Menu {
                    Button {
                        appState.confirmAndFetchCloudLogbook()
                    } label: {
                        Label("Download LoTW Cloud Logbook...", systemImage: "icloud.and.arrow.down.fill")
                    }

                    Divider()

                    if appState.isEnriching {
                        Button {
                            appState.stopEnrichment()
                        } label: {
                            Label("Stop Enriching", systemImage: "stop.circle.fill")
                        }
                    } else if !appState.selectedRecordIDs.isEmpty {
                        Button {
                            appState.enrichSelectedRecords()
                        } label: {
                            Label("Enrich Selected (\(appState.selectedRecordIDs.count))", systemImage: "wand.and.stars.inverse")
                        }
                        Button {
                            appState.clearSelection()
                        } label: {
                            Label("Clear Row Selection", systemImage: "xmark.circle")
                        }
                    } else {
                        Button {
                            appState.enrichLogData()
                        } label: {
                            Label("Enrich Today's QSOs", systemImage: "wand.and.stars")
                        }
                        Button {
                            appState.backfillMissingQRZEmailsNow()
                        } label: {
                            Label("Backfill Missing QRZ Names & Emails", systemImage: "person.text.rectangle")
                        }
                    }

                    let rankCandidateCount = appState.dailyRankBackfillCandidateCount
                    Button {
                        appState.fetchDailyQRZRankBackfill()
                    } label: {
                        Label("Daily Rank Backfill (\(rankCandidateCount))", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .disabled(appState.isEnriching || rankCandidateCount == 0 || appState.dailyRankRequestsRemaining == 0)

                    Divider()

                    let qslCount = appState.recentConfirmedQSLBatchCandidateCount()
                    let reminderCount = appState.recentUnconfirmedReminderBatchRecipientCount()
                    Button {
                        appState.sendRecentConfirmedQSLCardsBatch()
                    } label: {
                        Label("Send Recent QSL Cards (\(qslCount))", systemImage: "rectangle.stack.badge.person.crop")
                    }
                    .disabled(qslCount == 0 || appState.isSendingBatchMail)

                    Button {
                        appState.sendRecentUnconfirmedReminderBatch()
                    } label: {
                        Label("Remind Recent Unconfirmed (\(reminderCount))", systemImage: "bell.badge")
                    }
                    .disabled(reminderCount == 0 || appState.isSendingBatchMail)

                    Divider()

                    Button {
                        appState.forceQRZReLogin()
                    } label: {
                        Label("QRZ Login", systemImage: "key.fill")
                    }

                    Button {
                        appState.showQRZIncomingSheet = true
                    } label: {
                        Label("QRZ Incoming Requests", systemImage: "tray.and.arrow.down")
                    }

                    Button {
                        appState.showConfirmationReconciliationSheet = true
                    } label: {
                        Label("Confirmation Reconciliation", systemImage: "checklist")
                    }

                    Button {
                        appState.showLogAssistantSheet = true
                    } label: {
                        Label("Log Assistant", systemImage: "bubble.left.and.text.bubble.right")
                    }
                } label: {
                    HStack(spacing: 5) {
                        if appState.isEnriching || appState.isSendingBatchMail {
                            ProgressView()
                                .scaleEffect(0.55)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "ellipsis.circle")
                        }
                        Text("Tools")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
                .menuStyle(.borderlessButton)
                .disabled(appState.isEnriching || appState.isSendingBatchMail)
                .help("Cloud logbook, enrichment, rank backfill, batch mail, and QRZ login")
                
                Divider().frame(height: 14)
                
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

                Menu {
                    Section("Hidden by default") {
                        let hiddenCandidates = appState.tableHeaders.filter { isHiddenByDefault($0) }
                        if hiddenCandidates.isEmpty {
                            Text("No hidden columns")
                        } else {
                            ForEach(hiddenCandidates, id: \.self) { header in
                                Toggle(header, isOn: Binding(
                                    get: { explicitlyShownColumns.contains(header) },
                                    set: { isOn in
                                        if isOn {
                                            explicitlyShownColumns.insert(header)
                                        } else {
                                            explicitlyShownColumns.remove(header)
                                        }
                                        persistColumnVisibility()
                                    }
                                ))
                            }
                        }
                    }

                    Divider()

                    Button("Show All Columns") {
                        explicitlyShownColumns = Set(appState.tableHeaders.filter { isHiddenByDefault($0) })
                        persistColumnVisibility()
                    }

                    Button("Reset Default Columns") {
                        explicitlyShownColumns.removeAll()
                        persistColumnVisibility()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "tablecolumns")
                        Text("Columns")
                            .font(.caption)
                        if hiddenColumnCount > 0 {
                            Text("\(hiddenColumnCount)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .menuStyle(.borderlessButton)

                Divider().frame(height: 14)
                
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
                
                Button {
                    appState.syncConfirmations()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise.icloud")
                            .foregroundColor(appState.isSyncingAPI ? .gray : .cyan)
                        Text("Sync QSLs")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(appState.isSyncingAPI || appState.qsoRecords.isEmpty)
                .help("Download only new LoTW and QRZ confirmations")

                Button {
                    showFullConfirmationSyncPrompt = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(appState.isSyncingAPI ? .gray : .green)
                        Text("Full QSL History")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(appState.isSyncingAPI || appState.qsoRecords.isEmpty)
                .help("Download and reconcile every LoTW and QRZ confirmation from the beginning")
                
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
                
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "archivebox.fill")
                            .foregroundStyle(.secondary)
                        Text(appState.qsoRecords.count.formatted())
                            .font(.caption.monospacedDigit().bold())
                        Text("QSOs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .help("\(appState.qsoRecords.count.formatted()) QSOs in the active station log")
                    
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                        Text(appState.availableCountries.count.formatted())
                            .font(.caption.monospacedDigit().bold())
                        Text("DXCC")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
                
                Spacer()
                
                if appState.isLoading || appState.isSyncingAPI || (appState.isEnriching && !appState.isDailyRankBackfillRunning) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .padding(.trailing, 4)
                }
                
                if appState.isDailyRankBackfillRunning {
                    ProgressView(
                        value: Double(appState.dailyRankBackfillCompleted),
                        total: Double(max(1, appState.dailyRankBackfillTotal))
                    )
                    .frame(width: 110)

                    Text(appState.dailyRankBackfillStatus)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .help(appState.dailyRankBackfillStatus)
                } else if !appState.dailyRankBackfillStatus.isEmpty {
                    Text(appState.dailyRankBackfillStatus)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .help(appState.dailyRankBackfillStatus)
                } else {
                    Text("Tip: Select rows to enrich specific QSOs; with no selection, Enrich Data processes today's QSOs.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()

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
                    Text("Use File > Import Log File or select a recent file from Database.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button {
                        appState.importLogDialog()
                    } label: {
                        Label("Import Log File", systemImage: "square.and.arrow.down")
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(visibleRecords) { record in
                                rowView(for: record)
                            }
                        } header: {
                            headerRowView
                                .background(Color(NSColor.textBackgroundColor))
                        }
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
            }
            
            Divider()
            
            HStack {
                Text(appState.loadedFileName.isEmpty ? "Ready" : "File: \(appState.loadedFileName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !appState.selectedRecordIDs.isEmpty {
                    Text("Selected: \(appState.selectedRecordIDs.count)")
                        .font(.system(.caption, design: .monospaced))
                        .bold()
                        .foregroundColor(.blue)
                        .padding(.trailing, 8)
                }
                
                if appState.filterCriteria.isActive || !appState.searchText.isEmpty {
                    Text("Filtered: \(visibleRecords.count) / Total: \(appState.qsoRecords.count)")
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
        .sheet(isPresented: $appState.showQRZLoginSheet) {
            QRZLoginView().environmentObject(appState)
        }
        .sheet(isPresented: $appState.showDuplicateReviewSheet) {
            DuplicateReviewView().environmentObject(appState)
        }
        .sheet(isPresented: $appState.showQRZIncomingSheet) {
            QRZIncomingRequestsView().environmentObject(appState)
        }
        .sheet(isPresented: $appState.showConfirmationReconciliationSheet) {
            ConfirmationReconciliationView().environmentObject(appState)
        }
        .sheet(isPresented: $appState.showLogAssistantSheet) {
            LogAssistantView().environmentObject(appState)
        }
        .confirmationDialog(
            "Rebuild the complete confirmation history?",
            isPresented: $showFullConfirmationSyncPrompt,
            titleVisibility: .visible
        ) {
            Button("Download Full LoTW & QRZ History") {
                appState.syncConfirmations(forceFullSync: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("YAAM will page through every confirmed QRZ record and download LoTW confirmations from the beginning. The active station needs its QRZ Logbook API key and Settings needs your LoTW credentials. Existing log entries are preserved; only confirmation fields are reconciled.")
        }
        .onAppear {
            restoreColumnVisibility()
        }
        .onChange(of: appState.activeStationProfileID) { _, _ in
            restoreColumnVisibility()
        }
    }

    private func activateStation(_ profile: StationProfile) {
        do {
            try appState.activateStationProfile(profile)
        } catch {
            appState.alertTitle = "Station Profile"
            appState.alertMessage = error.localizedDescription
            appState.showAlert = true
        }
    }

    private var headerRowView: some View {
        HStack(spacing: 0) {
            ZStack {
                Color.accentColor
                if appState.filterCriteria.isActive {
                    Label("# UTC", systemImage: "clock")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
                .frame(width: utilityColumnWidth, height: 28)
                .border(Color.black.opacity(0.3), width: 0.5)
                .help(appState.filterCriteria.isActive ? "Temporary chronological number after filtering, newest QSO first" : "QSO actions")
            
            ForEach(displayedHeaders, id: \.self) { header in
                let w = columnWidths[header] ?? defaultColumnWidth(for: header)
                let isDerived = ConfirmationCreditColumn.isDerived(header)
                let isSorted = !isDerived && appState.sortHeader == header
                
                HStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Text(displayTitle(for: header))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if isSorted {
                            Image(systemName: appState.sortAscending ? "arrow.up" : "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.yellow)
                        }
                        
                        Spacer(minLength: 0)
                        
                        if !isDerived {
                            Button(action: { appState.deleteColumn(header: header) }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                    .frame(width: max(0, w - 6), height: 28, alignment: tableAlignment(for: header))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !isDerived {
                            appState.toggleSort(for: header)
                        }
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
                .help(headerHelp(for: header))
                .contextMenu {
                    if isDerived {
                        Text(headerHelp(for: header))
                    } else {
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
    }

    private func rowView(for record: QSORecordModel) -> some View {
        let isSelected = appState.selectedRecordIDs.contains(record.id)
        let statusBgColor = isSelected ? Color.accentColor.opacity(0.35) : (record.isConfirmed ? Color.green.opacity(0.15) : Color.orange.opacity(0.12))
        let call = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        return HStack(spacing: 0) {
            HStack(spacing: 5) {
                if let ordinal = appState.filteredChronologicalOrdinal(for: record.id) {
                    Text(ordinal.formatted())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: 31, alignment: .trailing)
                        .help("Position by UTC date and time in the current filtered result")
                }

                Button(action: { appState.toggleRecordSelection(record.id) }) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .accentColor : .gray)
                }
                .buttonStyle(.plain)
                .help(isSelected ? "Deselect QSO" : "Select QSO")

                Button(action: { appState.deleteRecord(id: record.id) }) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Delete QSO")
            }
            .frame(width: utilityColumnWidth, height: 28, alignment: .center)
            .background(statusBgColor)
            .border(Color.gray.opacity(0.2), width: 0.5)
            
            ForEach(displayedHeaders, id: \.self) { header in
                let w = columnWidths[header] ?? defaultColumnWidth(for: header)
                let val = record[header]
                let isDerived = ConfirmationCreditColumn.isDerived(header)
                
                ZStack {
                    if isDerived {
                        confirmationCreditCell(
                            header: header,
                            opportunity: appState.confirmationOpportunityIndex.opportunity(for: record.id)
                        )
                    } else if editingCellID == record.id && editingHeader == header {
                        TextField("", text: $editingText, onCommit: {
                            appState.updateCell(recordID: record.id, header: header, newValue: editingText)
                            editingCellID = nil
                            editingHeader = nil
                        })
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .multilineTextAlignment(isCompactCenteredColumn(header) ? .center : .leading)
                        .padding(.horizontal, 4)
                        .background(Color(NSColor.selectedControlColor).opacity(0.3))
                    } else {
                        HStack(spacing: 4) {
                            if header == "COUNTRY" && !val.isEmpty {
                                Text(countryToFlag(val))
                                    .font(.system(size: 10))
                            }
                            
                            if header == "QRZ_URL" || header == "QRZ" {
                                let targetUrlStr = val.isEmpty ? "https://www.qrz.com/db/\(call)" : val
                                Image(systemName: "safari.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                .onTapGesture {
                                    if let url = URL(string: targetUrlStr), !call.isEmpty {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .help("Click to open \(call) profile on QRZ.com")
                            }
                            else if header == "EMAIL" && !val.isEmpty {
                                Text(val)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.blue)
                                    .underline()
                                    .onTapGesture(count: 2) {
                                        startEditing(record: record, header: header, value: val)
                                    }
                                    .onTapGesture {
                                        appState.selectedEmailCallsign = record["CALL"]
                                        appState.selectedEmailAddress = val
                                        appState.selectedEmailQSO = record // ⭐️ FIX: Pass exact clicked record!
                                        appState.selectedEmailTemplate = nil
                                        appState.selectedEmailUnconfirmedQSOs = []
                                        appState.showEmailComposer = true
                                    }
                                    .help("Click to send an email. Double-click or right-click to edit.")
                            }
                            else if header.hasPrefix("RANK_") && !val.isEmpty {
                                Text(val)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(header == "RANK_QSO" ? .blue : (header == "RANK_BAND" ? .orange : .green))
                                    .padding(.horizontal, 4)
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(4)
                            }
                            else {
                                Text(val)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: tableAlignment(for: header))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: tableAlignment(for: header))
                    }
                }
                .padding(.horizontal, 6)
                .frame(width: w, height: 28, alignment: tableAlignment(for: header))
                .background(statusBgColor)
                .border(Color.gray.opacity(0.2), width: 0.5)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isDerived {
                        return
                    } else if header == "EMAIL" && val.isEmpty {
                        startEditing(record: record, header: header, value: val)
                    } else if header != "EMAIL" && header != "QRZ_URL" && header != "QRZ" {
                        startEditing(record: record, header: header, value: val)
                    }
                }
                .contextMenu {
                    if !isDerived && header != "QRZ_URL" && header != "QRZ" {
                        Button("Edit \(header)") {
                            startEditing(record: record, header: header, value: val)
                        }
                        Divider()
                    }

                    Button(isSelected ? "Deselect QSO" : "Select QSO") {
                        appState.toggleRecordSelection(record.id)
                    }
                    
                    if !call.isEmpty {
                        Button("Enrich QRZ Name & Email for '\(call)'") {
                            Task { await appState.fetchAndStoreQRZEmail(for: call) }
                        }
                    }
                    
                    if !appState.selectedRecordIDs.isEmpty {
                        Button("🪄 Enrich Selected (\(appState.selectedRecordIDs.count) Rows)") {
                            appState.enrichSelectedRecords()
                        }
                    }

                    if !call.isEmpty {
                        Button("Email QSL Card") {
                            appState.openQSLCardEmailComposer(for: record)
                        }
                        .disabled(!record.isConfirmed || record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if ["RANK_QSO", "RANK_BAND", "RANK_DXCC"].contains(where: { !record[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                            Button("Congratulate QRZ Achievement & Request Confirmation") {
                                appState.openQRZRankCongratulationsEmailComposer(for: record)
                            }
                            .disabled(record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        Button("Generate QSL Card") {
                            appState.selectedQSLCardQSO = record
                            appState.showQSLCardComposer = true
                        }
                    }
                    
                    Divider()
                    
                    Button("Delete QSO") {
                        appState.deleteRecord(id: record.id)
                    }
                    if !isDerived {
                        Button("Delete Column '\(header)'") {
                            appState.deleteColumn(header: header)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func confirmationCreditCell(
        header: String,
        opportunity: QSOConfirmationOpportunity?
    ) -> some View {
        if let opportunity {
            if opportunity.isConfirmed {
                confirmationCreditBadge(
                    title: "DONE",
                    icon: "checkmark.seal.fill",
                    color: .green,
                    help: "This QSO is already confirmed."
                )
            } else if header == ConfirmationCreditColumn.countryBand {
                if !opportunity.hasCountryBandData {
                    confirmationCreditBadge(
                        title: "N/A",
                        icon: "questionmark.circle",
                        color: .secondary,
                        help: "Country or band data is missing, so YAAM cannot calculate this credit."
                    )
                } else if opportunity.addsCountryBandCredit {
                    confirmationCreditBadge(
                        title: "NEW",
                        icon: "sparkles",
                        color: .blue,
                        help: "Confirming this QSO adds \(opportunity.band) as a confirmed band for \(opportunity.country)."
                    )
                } else {
                    confirmationCreditBadge(
                        title: "HAVE",
                        icon: "checkmark.circle",
                        color: .secondary,
                        help: "\(opportunity.country) is already confirmed on \(opportunity.band)."
                    )
                }
            } else if let grid = opportunity.grid {
                if opportunity.addsGridCredit {
                    confirmationCreditBadge(
                        title: "NEW",
                        icon: "square.grid.3x3.fill",
                        color: .mint,
                        help: "Confirming this QSO adds the four-character grid \(grid)."
                    )
                } else {
                    confirmationCreditBadge(
                        title: "HAVE",
                        icon: "checkmark.circle",
                        color: .secondary,
                        help: "The four-character grid \(grid) is already confirmed."
                    )
                }
            } else {
                confirmationCreditBadge(
                    title: "N/A",
                    icon: "questionmark.circle",
                    color: .secondary,
                    help: "No valid grid or coordinates are available for this QSO."
                )
            }
        } else {
            confirmationCreditBadge(
                title: "N/A",
                icon: "questionmark.circle",
                color: .secondary,
                help: "Confirmation opportunity data is unavailable."
            )
        }
    }

    private func confirmationCreditBadge(
        title: String,
        icon: String,
        color: Color,
        help: String
    ) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .frame(maxWidth: .infinity, alignment: .center)
            .help(help)
    }

    private func headerHelp(for header: String) -> String {
        switch header {
        case ConfirmationCreditColumn.countryBand:
            return "Shows whether confirming an unconfirmed QSO adds a new confirmed band for that country."
        case ConfirmationCreditColumn.grid:
            return "Shows whether confirming an unconfirmed QSO adds a new four-character Maidenhead grid."
        default:
            return "Click to sort by \(displayTitle(for: header)); drag the right edge to resize."
        }
    }

    private func startEditing(record: QSORecordModel, header: String, value: String) {
        editingCellID = record.id
        editingHeader = header
        editingText = value
    }

    private func defaultColumnWidth(for header: String) -> CGFloat {
        switch header {
        case "EMAIL": return 150
        case "APP_YAAM_LAST_EMAIL": return 260
        case "QRZ_URL", "QRZ": return 34
        case "RANK_QSO", "RANK_BAND", "RANK_DXCC": return 90
        case ConfirmationCreditColumn.countryBand, ConfirmationCreditColumn.grid: return 94
        case "QSO_DATE": return 90
        case "TIME", "TIME_ON", "TIME_OFF": return 58
        case "CALL": return 74
        case "FREQ", "FREQ_RX": return 68
        case "BAND", "BAND_RX", "MODE", "SUBMODE": return 52
        case "CONT": return 48
        case "RST_SENT", "RST_RCVD": return 70
        case "NAME": return 140
        case "COUNTRY": return 130
        case "COMMENT": return 180
        default: return 85
        }
    }

    private func isCompactCenteredColumn(_ header: String) -> Bool {
        compactCenteredColumns.contains(header)
    }

    private func tableAlignment(for header: String) -> Alignment {
        isCompactCenteredColumn(header) ? .center : .leading
    }

    private func displayTitle(for header: String) -> String {
        switch header {
        case "TIME_ON": return "TIME"
        case ConfirmationCreditColumn.countryBand: return "BAND CREDIT"
        case ConfirmationCreditColumn.grid: return "GRID CREDIT"
        default: return header
        }
    }

    private var hiddenColumnCount: Int {
        appState.tableHeaders.filter { isHiddenByDefault($0) && !explicitlyShownColumns.contains($0) }.count
    }

    private var displayedHeaders: [String] {
        let visibleStoredHeaders = appState.tableHeaders.filter { header in
            !isHiddenByDefault(header) || explicitlyShownColumns.contains(header)
        }
        return orderedHeaders(visibleStoredHeaders + ConfirmationCreditColumn.headers)
    }

    private func orderedHeaders(_ headers: [String]) -> [String] {
        headers.sorted { lhs, rhs in
            let lhsPriority = columnPriority(lhs)
            let rhsPriority = columnPriority(rhs)

            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }

            let lhsPreferred = preferredColumnOrder.firstIndex(of: lhs) ?? Int.max
            let rhsPreferred = preferredColumnOrder.firstIndex(of: rhs) ?? Int.max
            if lhsPreferred != rhsPreferred {
                return lhsPreferred < rhsPreferred
            }

            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }

    private func columnPriority(_ header: String) -> Int {
        if let preferredIndex = preferredColumnOrder.firstIndex(of: header) {
            return preferredIndex
        }

        if isMostlyEmpty(header) {
            return 9_000
        }

        if TableColumnPolicy.isLowPriority(header) {
            return 10_000
        }

        return 1_000
    }

    private func isHiddenByDefault(_ header: String) -> Bool {
        TableColumnPolicy.isHiddenByDefault(header, isMostlyEmpty: isMostlyEmpty(header))
    }

    private func isLowValueTrailingColumn(_ header: String) -> Bool {
        TableColumnPolicy.isLowPriority(header)
    }

    private var columnVisibilityStorageKey: String {
        "logTable.explicitlyShownColumns.\(appState.activeStationProfileID?.uuidString ?? "default")"
    }

    private func restoreColumnVisibility() {
        let saved = UserDefaults.standard.stringArray(forKey: columnVisibilityStorageKey) ?? []
        explicitlyShownColumns = Set(saved.filter { appState.tableHeaders.contains($0) })
    }

    private func persistColumnVisibility() {
        UserDefaults.standard.set(Array(explicitlyShownColumns).sorted(), forKey: columnVisibilityStorageKey)
    }

    private func isMostlyEmpty(_ header: String) -> Bool {
        guard !appState.qsoRecords.isEmpty else { return false }
        guard !preferredColumnOrder.contains(header) else { return false }
        guard !isLowValueTrailingColumn(header) else { return false }
        guard !TableColumnPolicy.isDatabaseOnly(header) else { return false }

        let nonEmptyCount = appState.qsoRecords.prefix(200).reduce(0) { count, record in
            record[header].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? count : count + 1
        }

        return nonEmptyCount == 0
    }
}
