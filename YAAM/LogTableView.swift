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
    @State private var selectedEQSLRecord: QSORecordModel? = nil
    @State private var showEQSLCardSheet = false
    @State private var activeTablePopover: ActiveTablePopover? = nil
    @State private var pinnedOffsetX: CGFloat = 0

    private var homeCoordinate: GeoCoordinate? {
        if let profile = appState.activeStationProfile {
            if let lat = Double(profile.latitude), let lon = Double(profile.longitude), (lat != 0 || lon != 0) {
                return GeoCoordinate(latitude: lat, longitude: lon)
            }
            if !profile.grid.isEmpty, let box = MaidenheadGridEngine.boundingBox(for: profile.grid) {
                return box.center
            }
        }
        return nil
    }

    private let compactCenteredColumns: Set<String> = [
        "TIME",
        "TIME_ON",
        "CALL",
        "QSL",
        "FREQ",
        "BAND",
        "BAND_RX",
        "MODE",
        "CONT",
        "RST_SENT",
        "RST_RCVD",
        "GRIDSQUARE",
        "GRID"
    ]

    private let preferredColumnOrder = [
        "QSO_DATE", "TIME_ON", "CALL", "QSL", "FREQ", "BAND", "MODE",
        "GRIDSQUARE", "COUNTRY", "NAME", "QTH", "CONT", "DXCC", "CQZ", "ITUZ",
        ConfirmationCreditColumn.countryBand, ConfirmationCreditColumn.grid
    ]

    private var utilityColumnWidth: CGFloat {
        appState.filterCriteria.isActive ? 82 : 48
    }

    var body: some View {
        let visibleRecords = appState.filteredRecords

        VStack(spacing: 0) {
            // MARK: - Toolbar & Quick Actions Summary Bar
            HStack(spacing: 8) {
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

                    Button {
                        appState.consolidateDuplicatesNow(showFeedback: true)
                    } label: {
                        Label("Consolidate & Merge Duplicates", systemImage: "arrow.triangle.merge")
                    }
                    .disabled(appState.qsoRecords.isEmpty || appState.isAnalyzingDuplicates)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundColor(.blue)
                        Text("Database")
                            .fontWeight(.semibold)
                    }
                    .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: true, vertical: false)
                
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
                    HStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundStyle(.green)
                        Text(appState.currentStationCallsign.isEmpty ? "NO CALL" : appState.currentStationCallsign)
                            .font(.caption.monospaced().weight(.semibold))
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: true, vertical: false)
                .help("Active station profile")

                Divider().frame(height: 14)

                OnTheAirPillView()

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
                        Label("QRZ Login (2FA / WebKit)", systemImage: "lock.shield.fill")
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
                    HStack(spacing: 4) {
                        if appState.isEnriching || appState.isSendingBatchMail {
                            ProgressView()
                                .scaleEffect(0.55)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .foregroundStyle(.blue)
                        }
                        Text("Log Actions")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(appState.isEnriching || appState.isSendingBatchMail)
                .help("Log actions: Cloud logbook, QRZ enrichment, rank backfill, QSL batch mail, and reconciliation")

                if !appState.selectedRecordIDs.isEmpty {
                    Menu {
                        Button {
                            appState.enrichSelectedRecords()
                        } label: {
                            Label("Enrich QRZ Data (\(appState.selectedRecordIDs.count))", systemImage: "wand.and.stars")
                        }
                        
                        Button {
                            appState.openBatchEmailComposerForSelected()
                        } label: {
                            Label("Batch Email Selected (\(appState.selectedRecordIDs.count))...", systemImage: "paperplane.fill")
                        }
                        
                        Button {
                            appState.exportSelectedRecordsAs()
                        } label: {
                            Label("Export Selected (\(appState.selectedRecordIDs.count)) to ADIF...", systemImage: "square.and.arrow.down")
                        }

                        Divider()

                        Button(role: .destructive) {
                            appState.deleteSelectedRecords()
                        } label: {
                            Label("Delete Selected (\(appState.selectedRecordIDs.count) QSOs)", systemImage: "trash.fill")
                        }

                        Button {
                            appState.clearSelection()
                        } label: {
                            Label("Clear Selection", systemImage: "xmark.circle")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                            Text("Selected (\(appState.selectedRecordIDs.count))")
                                .font(.caption)
                                .fontWeight(.bold)
                        }
                    }
                    .menuStyle(.borderedButton)
                    .fixedSize(horizontal: true, vertical: false)
                    .help("Batch actions for \(appState.selectedRecordIDs.count) selected QSOs: Batch Email, Export, Enrich, or Delete")
                }
                
                Divider().frame(height: 14)
                
                HStack(spacing: 4) {
                    Menu {
                        Picker("Search Mode", selection: $appState.logSearchMode) {
                            ForEach(LogSearchMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.systemImage).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: appState.logSearchMode.systemImage)
                            .foregroundColor(.accentColor)
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .help("Search Mode: Quick Any, Exact Callsign, or Multi-word Contact Name")

                    TextField(appState.logSearchMode.placeholder, text: $appState.searchText)
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
                .frame(minWidth: 120, idealWidth: 160, maxWidth: 200)
                
                Divider().frame(height: 14)

                Menu {
                    Section("Hidden by default") {
                        let hiddenCandidates = appState.tableHeaders.filter { isHiddenByDefault($0) }
                        if hiddenCandidates.isEmpty {
                            Text("No hidden columns")
                        } else {
                            ForEach(hiddenCandidates, id: \.self) { header in
                                let title = displayTitle(for: header)
                                let labelText = (title == header || title.isEmpty) ? header : "\(title) (\(header))"
                                Toggle(labelText, isOn: Binding(
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
                    HStack(spacing: 4) {
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
                .fixedSize(horizontal: true, vertical: false)

                Divider().frame(height: 14)
                
                Button(action: { appState.showFilterSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: appState.filterCriteria.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundColor(appState.filterCriteria.isActive ? .orange : .primary)
                        Text(appState.filterCriteria.isActive ? "Filters Active" : "Filters")
                            .font(.caption)
                            .fontWeight(appState.filterCriteria.isActive ? .bold : .regular)
                    }
                }
                .buttonStyle(.borderless)
                .fixedSize(horizontal: true, vertical: false)
                
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
                
                let todayConfirmedCount = appState.todayConfirmedCount
                Button {
                    appState.filterCriteria.useTodayConfirmed.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(todayConfirmedCount > 0 || appState.filterCriteria.useTodayConfirmed ? .green : .secondary)
                        Text("Today Confirmed (\(todayConfirmedCount))")
                            .font(.system(size: 11, weight: appState.filterCriteria.useTodayConfirmed ? .bold : .medium))
                            .foregroundColor(appState.filterCriteria.useTodayConfirmed ? .green : (todayConfirmedCount > 0 ? .primary : .secondary))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(appState.filterCriteria.useTodayConfirmed ? Color.green.opacity(0.22) : (todayConfirmedCount > 0 ? Color.green.opacity(0.08) : Color.clear))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(appState.filterCriteria.useTodayConfirmed ? Color.green : (todayConfirmedCount > 0 ? Color.green.opacity(0.3) : Color.secondary.opacity(0.2)), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help(appState.filterCriteria.useTodayConfirmed ? "Showing only today's confirmed QSOs. Click to reset." : "Filter log table to show confirmed QSOs from today (\(todayConfirmedCount))")

                if todayConfirmedCount > 0 {
                    let readyUnsent = appState.todayConfirmedReadyUnsentCount
                    let totalUnsent = appState.todayConfirmedUnsentCount

                    if readyUnsent > 0 || totalUnsent > 0 {
                        let badgeCount = readyUnsent > 0 ? readyUnsent : totalUnsent
                        Button {
                            appState.showTodayConfirmedQSLSheet = true
                        } label: {
                            HStack(spacing: 3.5) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 8.5))
                                Text("Send QSLs (\(badgeCount))")
                                    .font(.system(size: 10.5, weight: .bold))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.green))
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .help("Open Today's Confirmed QSL Dispatcher to review, preview, and email QSL card PDFs for \(badgeCount) un-emailed contact(s)")
                    } else {
                        Button {
                            appState.showTodayConfirmedQSLSheet = true
                        } label: {
                            HStack(spacing: 3.5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 8.5))
                                    .foregroundColor(.green)
                                Text("QSLs Sent (\(todayConfirmedCount))")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color(NSColor.controlBackgroundColor)))
                            .overlay(Capsule().stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .help("All confirmed contacts with email from today have been sent QSL card emails. Click to view dispatch records.")
                    }
                }

                let newConfirmedCount = appState.newlyConfirmedCount
                if newConfirmedCount > 0 {
                    Button {
                        appState.filterCriteria.useNewlyConfirmed.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.pink)
                            Text("New QSL (\(newConfirmedCount))")
                                .font(.system(size: 11, weight: appState.filterCriteria.useNewlyConfirmed ? .bold : .medium))
                                .foregroundColor(appState.filterCriteria.useNewlyConfirmed ? .pink : .primary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(appState.filterCriteria.useNewlyConfirmed ? Color.pink.opacity(0.22) : Color.pink.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(appState.filterCriteria.useNewlyConfirmed ? Color.pink : Color.pink.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(appState.filterCriteria.useNewlyConfirmed ? "Showing only newly confirmed QSOs. Click to reset." : "Filter log table to show \(newConfirmedCount) newly confirmed QSOs")
                }

                let emailedCount = appState.emailedQSOCount
                if emailedCount > 0 {
                    Button {
                        appState.filterCriteria.useSentEmail.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.cyan)
                            Text("Emailed (\(emailedCount))")
                                .font(.system(size: 11, weight: appState.filterCriteria.useSentEmail ? .bold : .medium))
                                .foregroundColor(appState.filterCriteria.useSentEmail ? .cyan : .primary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(appState.filterCriteria.useSentEmail ? Color.cyan.opacity(0.22) : Color.cyan.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(appState.filterCriteria.useSentEmail ? Color.cyan : Color.cyan.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(appState.filterCriteria.useSentEmail ? "Showing only QSOs with sent emails. Click to reset." : "Filter log table to show \(emailedCount) QSOs with sent emails")
                }
                
                Divider().frame(height: 14)
                
                // MARK: - Unified Sync Menu
                Menu {
                    Button {
                        appState.syncConfirmations()
                    } label: {
                        Label("Sync New QSLs (LoTW & QRZ)", systemImage: "arrow.clockwise.icloud")
                    }

                    Button {
                        showFullConfirmationSyncPrompt = true
                    } label: {
                        Label("Full QSL History Reconciliation...", systemImage: "arrow.triangle.2.circlepath")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise.icloud")
                            .foregroundColor(appState.isSyncingAPI ? .gray : .cyan)
                        Text("Sync QSLs")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(appState.isSyncingAPI || appState.qsoRecords.isEmpty)
                .help("Download only new LoTW and QRZ confirmations (or reconcile full history)")

                Button(action: { appState.selectedTab = 6 }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(.purple)
                        Text("Stats")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderless)
                .fixedSize(horizontal: true, vertical: false)
                .help("Switch to Log Statistics & Analytics Tab")
                
                Divider().frame(height: 14)
                
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
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
                    
                    HStack(spacing: 3) {
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
                
                Spacer(minLength: 4)
                
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
                    .frame(width: 80)

                    Text(appState.dailyRankBackfillStatus)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 150)
                        .help(appState.dailyRankBackfillStatus)

                    Button {
                        appState.stopEnrichment()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "stop.circle.fill")
                                .foregroundColor(.red)
                            Text("Stop")
                                .font(.caption2.bold())
                                .foregroundColor(.red)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Stop QRZ rank lookup and save current progress")
                } else if !appState.dailyRankBackfillStatus.isEmpty {
                    Text(appState.dailyRankBackfillStatus)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 150)
                        .help(appState.dailyRankBackfillStatus)
                } else {
                    Text("Select rows to enrich specific QSOs")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 180)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()

            if appState.filterCriteria.useTodayConfirmed {
                todayConfirmedBanner
            }

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
                    ZStack(alignment: .topLeading) {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: LogTableScrollOffsetKey.self,
                                value: geo.frame(in: .named("logTableScrollSpace")).minX
                            )
                        }
                        .frame(height: 0)

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
                }
                .coordinateSpace(name: "logTableScrollSpace")
                .onPreferenceChange(LogTableScrollOffsetKey.self) { minX in
                    let scrollX = max(0, -minX)
                    // Only update if difference is more than 3px to avoid re-rendering rows during vertical drags
                    if abs(pinnedOffsetX - scrollX) >= 3.0 {
                        pinnedOffsetX = scrollX
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
        .sheet(isPresented: $showEQSLCardSheet) {
            if let record = selectedEQSLRecord {
                EQSLCardModalView(
                    callsign: record["CALL"],
                    date: record["QSO_DATE"],
                    time: record["TIME_ON"],
                    band: record["BAND"],
                    mode: record["MODE"],
                    rstSent: record["RST_SENT"],
                    rstRcvd: record["RST_RCVD"],
                    grid: record["GRIDSQUARE"]
                )
            }
        }
        .popover(item: $activeTablePopover) { popover in
            switch popover {
            case .sentEmail(let detail):
                SentEmailDetailCard(
                    record: detail.record,
                    entry: detail.entry,
                    onComposeFollowUp: {
                        appState.selectedEmailCallsign = detail.record["CALL"]
                        appState.selectedEmailAddress = detail.entry.email
                        appState.selectedEmailQSO = detail.record
                        appState.selectedEmailTemplate = nil
                        appState.selectedEmailUnconfirmedQSOs = []
                        appState.showEmailComposer = true
                        activeTablePopover = nil
                    }
                )
            case .callsign(let record):
                CallsignInspectionCard(record: record, onOpenGrid: { ctx in
                    activeTablePopover = .grid(ctx)
                })
            case .grid(let context):
                GridInspectionCard(context: context, homeCoordinate: homeCoordinate)
            }
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

    private func isPinnedColumn(_ header: String) -> Bool {
        header == "QSO_DATE" || header == "TIME_ON" || header == "TIME" || header == "CALL" || header == "QSL"
    }

    private var pinnedHeaders: [String] {
        displayedHeaders.filter { isPinnedColumn($0) }
    }

    private var unpinnedHeaders: [String] {
        displayedHeaders.filter { !isPinnedColumn($0) }
    }

    private var todayConfirmedBanner: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.green)
                
                Text("Today's Confirmed QSOs")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundColor(.primary)

                Text("(\(appState.filteredRecords.count))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.green)
            }

            Text("•")
                .foregroundColor(.secondary.opacity(0.5))

            let totalConfirmed = appState.todayConfirmedCount
            let readyCandidates = appState.todayConfirmedBatchCandidates
            Text("\(readyCandidates.count) of \(totalConfirmed) ready with email")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            let readyUnsent = appState.todayConfirmedReadyUnsentCount
            let totalUnsent = appState.todayConfirmedUnsentCount

            if readyUnsent > 0 || totalUnsent > 0 {
                let badgeCount = readyUnsent > 0 ? readyUnsent : totalUnsent
                Button {
                    appState.showTodayConfirmedQSLSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 9))
                        Text("Dispatch QSL Cards (\(badgeCount))")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.green))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .help("Open Today's Confirmed QSL Dispatcher to review, preview, enrich emails, and send cards to \(badgeCount) un-emailed contact(s)")
            } else {
                Button {
                    appState.showTodayConfirmedQSLSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                        Text("QSLs Sent (\(totalConfirmed))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(NSColor.controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("All confirmed contacts with email have been dispatched. Click to view history.")
            }

            Button {
                appState.filterCriteria.useTodayConfirmed = false
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                    Text("Clear")
                        .font(.system(size: 10.5))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear today's confirmed filter and view all QSOs")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.green.opacity(0.06))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.green.opacity(0.2)),
            alignment: .bottom
        )
    }

    private var headerRowView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Pinned Left Headers (Utility + Date + Time + Call + QSL)
                HStack(spacing: 0) {
                    utilityHeaderCell
                    ForEach(pinnedHeaders, id: \.self) { header in
                        headerCell(for: header)
                    }
                }
                .background(Color(white: 0.12))
                .offset(x: pinnedOffsetX)
                .zIndex(20)
                .shadow(color: pinnedOffsetX > 2 ? Color.black.opacity(0.4) : Color.clear, radius: 4, x: 2, y: 0)

                // Scrollable Trailing Headers
                HStack(spacing: 0) {
                    ForEach(unpinnedHeaders, id: \.self) { header in
                        headerCell(for: header)
                    }
                }
                .zIndex(1)
            }
            
            // Header bottom accent line (1.5px subtle blue separator)
            Rectangle()
                .fill(Color.accentColor.opacity(0.75))
                .frame(height: 1.5)
        }
    }

    private var utilityHeaderCell: some View {
        ZStack {
            Color(white: 0.12)
            if appState.filterCriteria.isActive {
                Label("# UTC", systemImage: "clock")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(white: 0.88))
            }
        }
        .frame(width: utilityColumnWidth, height: 28)
        .border(Color(white: 0.22).opacity(0.6), width: 0.5)
        .help(appState.filterCriteria.isActive ? "Temporary chronological number after filtering, newest QSO first" : "QSO actions")
    }

    private func headerCell(for header: String) -> some View {
        let w = columnWidths[header] ?? defaultColumnWidth(for: header)
        let isDerived = ConfirmationCreditColumn.isDerived(header)
        let isSorted = !isDerived && appState.sortHeader == header
        let meta = headerMeta(for: header)
        
        return HStack(spacing: 0) {
            HStack(spacing: 3.5) {
                Image(systemName: meta.icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(isSorted ? .yellow : Color(white: 0.75))

                Text(meta.title)
                    .font(.system(size: 10.5, weight: isSorted ? .bold : .semibold))
                    .foregroundColor(isSorted ? .white : Color(white: 0.88))
                    .lineLimit(1)
                
                if isSorted {
                    Image(systemName: appState.sortAscending ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.yellow)
                }
                
                if !isDerived {
                    Button(action: { appState.deleteColumn(header: header) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(Color(white: 0.55))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
            .frame(width: max(0, w - 6), height: 28, alignment: tableAlignment(for: header))
            .contentShape(Rectangle())
            .onTapGesture {
                if !isDerived {
                    appState.toggleSort(for: header)
                }
            }
            
            Rectangle()
                .fill(Color(white: 0.22).opacity(0.6))
                .frame(width: 6, height: 28)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
                .onTapGesture(count: 2) {
                    autoFitColumnWidth(header)
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
        .background(isSorted ? Color(white: 0.18) : Color(white: 0.12))
        .border(Color(white: 0.22).opacity(0.6), width: 0.5)
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
                Button("Auto-Fit Width") {
                    autoFitColumnWidth(header)
                }
                Divider()
                Button("Delete Column '\(header)'") {
                    appState.deleteColumn(header: header)
                }
            }
        }
    }

    private func rowView(for record: QSORecordModel) -> some View {
        let isSelected = appState.selectedRecordIDs.contains(record.id)
        let isNewlyConfirmed = appState.isNewlyConfirmed(record: record)
        let isTodayConfirmed = appState.isTodayConfirmed(record: record)
        let accentBarColor: Color = {
            if isSelected {
                return Color.accentColor // Blue
            } else if isNewlyConfirmed {
                return Color.pink // Pink
            } else if record.isConfirmed {
                let isLotw = ["Y", "V", "C"].contains(record["LOTW_QSL_RCVD"].uppercased()) || record["APP_LOTW_QSL_RCVD"].uppercased() == "Y"
                let isEqsl = ["Y", "V", "C"].contains(record["EQSL_QSL_RCVD"].uppercased()) || record["APP_EQSL_QSL_RCVD"].uppercased() == "Y"
                let isQrz = ["Y", "V", "C"].contains(record["QRZLOG_QSL_RCVD"].uppercased()) ||
                    ["Y", "V", "C"].contains(record["QRZCOM_QSL_RCVD"].uppercased()) ||
                    ["Y", "V", "C"].contains(record["QRZ_QSL_RCVD"].uppercased()) ||
                    record["APP_YAAM_QRZ_CONFIRMED"] == "Y" ||
                    record["APP_QRZLOG_STATUS"].uppercased() == "C"
                let isCard = ["Y", "V", "C"].contains(record["QSL_RCVD"].uppercased())
                
                if isLotw {
                    return Color(red: 0.2, green: 0.85, blue: 0.35) // LoTW Green
                } else if isEqsl {
                    return Color(red: 0.25, green: 0.65, blue: 1.0) // eQSL Electric Blue
                } else if isQrz {
                    return Color(red: 0.95, green: 0.75, blue: 0.2) // QRZ Gold / Amber
                } else if isCard {
                    return Color(red: 1.0, green: 0.5, blue: 0.2) // Paper Card Orange
                } else {
                    return Color.green
                }
            } else {
                return Color.orange.opacity(0.35) // Unconfirmed muted orange
            }
        }()
        let statusBgColor: Color = {
            if isSelected {
                return Color.accentColor.opacity(0.12)
            } else if isTodayConfirmed {
                return Color.green.opacity(0.06)
            } else if isNewlyConfirmed {
                return Color.pink.opacity(0.045)
            } else if record.isConfirmed {
                return Color.green.opacity(0.03)
            } else {
                return Color.clear
            }
        }()
        let call = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let sentEmail = appState.emailHistoryByCallsign[call] ?? appState.latestEmailHistory(for: call)
        
        return HStack(spacing: 0) {
            // Pinned Left Cells (Utility + Date + Time + Call + QSL)
            HStack(spacing: 0) {
                utilityRowCell(for: record, isSelected: isSelected, accentBarColor: accentBarColor, statusBgColor: statusBgColor)
                ForEach(pinnedHeaders, id: \.self) { header in
                    rowCell(for: record, header: header, isSelected: isSelected, isNewlyConfirmed: isNewlyConfirmed, isTodayConfirmed: isTodayConfirmed, call: call, sentEmail: sentEmail, statusBgColor: statusBgColor)
                }
            }
            .background(Color(NSColor.textBackgroundColor))
            .offset(x: pinnedOffsetX)
            .zIndex(10)
            .overlay(
                Rectangle()
                    .fill(pinnedOffsetX > 2 ? Color.black.opacity(0.3) : Color.clear)
                    .frame(width: 1),
                alignment: .trailing
            )

            // Scrollable Trailing Cells
            HStack(spacing: 0) {
                ForEach(unpinnedHeaders, id: \.self) { header in
                    rowCell(for: record, header: header, isSelected: isSelected, isNewlyConfirmed: isNewlyConfirmed, isTodayConfirmed: isTodayConfirmed, call: call, sentEmail: sentEmail, statusBgColor: statusBgColor)
                }
            }
            .zIndex(1)
        }
        .frame(height: 28)
    }

    private func utilityRowCell(for record: QSORecordModel, isSelected: Bool, accentBarColor: Color, statusBgColor: Color) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentBarColor)
                .frame(width: 3)
            
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
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: utilityColumnWidth, height: 28)
        .background(statusBgColor)
        .border(Color.gray.opacity(0.15), width: 0.5)
    }

    private func rowCell(
        for record: QSORecordModel,
        header: String,
        isSelected: Bool,
        isNewlyConfirmed: Bool,
        isTodayConfirmed: Bool,
        call: String,
        sentEmail: EmailHistoryEntry?,
        statusBgColor: Color
    ) -> some View {
        let w = columnWidths[header] ?? defaultColumnWidth(for: header)
        let val = record[header]
        let isDerived = ConfirmationCreditColumn.isDerived(header)
        
        return ZStack {
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
                .multilineTextAlignment(isRightAlignedColumn(header) ? .trailing : (isLeftAlignedColumn(header) ? .leading : .center))
                .padding(.horizontal, 4)
                .background(Color(NSColor.selectedControlColor).opacity(0.3))
            } else if header == "QSL" {
                qslMultiStatusGrid(for: record)
            } else {
                HStack(spacing: 4) {
                    if header == "COUNTRY" && !val.isEmpty {
                        Text(countryToFlag(val))
                            .font(.system(size: 10))
                    }
                    
                    if header == "CALL" {
                        HStack(spacing: 4) {
                            Button {
                                activeTablePopover = .callsign(record)
                            } label: {
                                Text(val)
                                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .help("Click to inspect callsign \(val) (bearing, distance, country, station stats)")
                            
                            if isTodayConfirmed {
                                HStack(spacing: 2) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 7, weight: .bold))
                                    Text("TODAY")
                                        .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                                }
                                .padding(.horizontal, 3.5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.green))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .fixedSize()
                                .help("Confirmed Today! Right-click or click QSL card icon to send/preview card.")
                            } else if isNewlyConfirmed {
                                HStack(spacing: 2) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 7, weight: .bold))
                                    Text("NEW")
                                        .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                                }
                                .padding(.horizontal, 3.5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.pink))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .fixedSize()
                                .help("Newly Confirmed QSO! Verified via \(record.confirmationSourcesSummary)\(record.latestConfirmationDate.map { " on " + appState.formattedEmailHistoryDate($0) } ?? "")")
                            }

                            if record.isConfirmed {
                                Button {
                                    appState.selectedQSLCardQSO = record
                                    appState.showQSLCardComposer = true
                                } label: {
                                    Image(systemName: "photo.badge.checkmark")
                                        .font(.system(size: 8.5))
                                        .foregroundColor(isTodayConfirmed ? .green : .secondary)
                                        .padding(2.5)
                                        .background(Circle().fill((isTodayConfirmed ? Color.green : Color.secondary).opacity(0.16)))
                                }
                                .buttonStyle(.plain)
                                .help("Open QSL Card Composer for \(val) (Preview, Export PDF/PNG, or Email)")
                            }

                            if let sentEmail {
                                Button {
                                    activeTablePopover = .sentEmail(SentEmailDetailContext(record: record, entry: sentEmail))
                                } label: {
                                    Image(systemName: "envelope.fill")
                                        .font(.system(size: 8.5))
                                        .foregroundColor(.cyan)
                                        .padding(2.5)
                                        .background(Circle().fill(Color.cyan.opacity(0.18)))
                                }
                                .buttonStyle(.plain)
                                .help("Email sent to \(call) on \(appState.formattedEmailHistoryDate(sentEmail.date)): \"\(sentEmail.subject)\" (\(sentEmail.status)). Click to view.")
                            }
                        }
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    else if header == "QSO_DATE" {
                        Text(formatDate(val))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    else if header == "TIME_ON" || header == "TIME" || header == "TIME_OFF" {
                        Text(formatTime(val))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    else if header == "FREQ" || header == "FREQ_RX" {
                        formattedFrequencyView(val)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    else if header == "RST_SENT" || header == "RST_RCVD" {
                        Text(val)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    else if header == "QRZ_URL" || header == "QRZ" {
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
                    else if header == "EMAIL" {
                        if let sentEmail {
                            Button {
                                activeTablePopover = .sentEmail(SentEmailDetailContext(record: record, entry: sentEmail))
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "envelope.fill")
                                        .font(.system(size: 8))
                                    Text("Sent")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.cyan.opacity(0.18)))
                                .foregroundColor(.cyan)
                            }
                            .buttonStyle(.plain)
                            .help("Sent email: \"\(sentEmail.subject)\" (\(sentEmail.status)). Click to view details.")
                            .frame(maxWidth: .infinity, alignment: .center)
                        } else if !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button {
                                appState.openEmailComposer(for: record, email: val)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 8))
                                    Text("Email")
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.blue.opacity(0.15)))
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                            .help("Send email to \(val). Double-click or right-click to edit.")
                            .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            Text("—")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    else if header == "APP_YAAM_LAST_EMAIL" && !val.isEmpty {
                        if let sentEmail {
                            Button {
                                activeTablePopover = .sentEmail(SentEmailDetailContext(record: record, entry: sentEmail))
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "envelope.fill")
                                        .font(.system(size: 8.5))
                                    Text(sentEmail.subject)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(appState.formattedEmailHistoryDate(sentEmail.date))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Click to view full email communication details")
                        } else {
                            Text(val)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    else if header.hasPrefix("RANK_") && !val.isEmpty {
                        Text(val)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(header == "RANK_QSO" ? .blue : (header == "RANK_BAND" ? .orange : .green))
                            .padding(.horizontal, 4)
                            .background(Color.black.opacity(0.05))
                            .cornerRadius(4)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    else if header == "GRIDSQUARE" || header == "GRID" {
                        let fullGrid = val.trimmingCharacters(in: .whitespacesAndNewlines)
                        if fullGrid.isEmpty {
                            Text("—")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            let displayGrid = String(fullGrid.prefix(4)).uppercased()
                            GridCellView(
                                displayGrid: displayGrid,
                                fullGrid: fullGrid,
                                call: call,
                                country: record["COUNTRY"],
                                record: record,
                                onInspect: { ctx in
                                    activeTablePopover = .grid(ctx)
                                }
                            )
                        }
                    }
                    else {
                        let isSecondary = ["NAME", "COUNTRY", "CONT", "QTH", "COMMENT"].contains(header)
                        Text(val)
                            .font(.system(size: 11, weight: .regular, design: isSecondary ? .default : .monospaced))
                            .foregroundColor(isSecondary ? Color(white: 0.72) : .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .multilineTextAlignment(isRightAlignedColumn(header) ? .trailing : (isLeftAlignedColumn(header) ? .leading : .center))
                            .frame(maxWidth: .infinity, alignment: isRightAlignedColumn(header) ? .trailing : (isLeftAlignedColumn(header) ? .leading : .center))
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 6)
        .frame(width: w, height: 28, alignment: tableAlignment(for: header))
        .background(statusBgColor)
        .border(Color.gray.opacity(0.15), width: 0.5)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if !isDerived && header != "QRZ_URL" && header != "QRZ" && header != "QSL" && header != "GRIDSQUARE" && header != "GRID" {
                startEditing(record: record, header: header, value: val)
            }
        }
        .onTapGesture {
            if header == "GRIDSQUARE" || header == "GRID" {
                let fullGrid = val.trimmingCharacters(in: .whitespacesAndNewlines)
                if !fullGrid.isEmpty {
                    activeTablePopover = .grid(GridInspectionContext(
                        record: record,
                        fullGrid: fullGrid,
                        call: call,
                        country: record["COUNTRY"]
                    ))
                    return
                }
            } else if header == "CALL" {
                activeTablePopover = .callsign(record)
                return
            } else if header == "EMAIL" {
                if let sentEmail {
                    activeTablePopover = .sentEmail(SentEmailDetailContext(record: record, entry: sentEmail))
                    return
                }
                let cleanEmail = val.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanEmail.isEmpty {
                    appState.openEmailComposer(for: record, email: cleanEmail)
                    return
                }
            } else if header == "APP_YAAM_LAST_EMAIL" {
                if let sentEmail {
                    activeTablePopover = .sentEmail(SentEmailDetailContext(record: record, entry: sentEmail))
                    return
                }
            } else if header == "QRZ_URL" || header == "QRZ" {
                let targetUrlStr = val.isEmpty ? "https://www.qrz.com/db/\(call)" : val
                if let url = URL(string: targetUrlStr), !call.isEmpty {
                    NSWorkspace.shared.open(url)
                    return
                }
            }
            appState.toggleRecordSelection(record.id)
        }
        .contextMenu {
            if !isDerived && header != "QRZ_URL" && header != "QRZ" && header != "QSL" && header != "GRIDSQUARE" && header != "GRID" {
                Button("Edit \(header)") {
                    startEditing(record: record, header: header, value: val)
                }
                Divider()
            }
            rowContextMenuContent(for: record, call: call, sentEmail: sentEmail, isSelected: isSelected, isNewlyConfirmed: isNewlyConfirmed)
        }
    }

    @ViewBuilder
    private func rowContextMenuContent(
        for record: QSORecordModel,
        call: String,
        sentEmail: EmailHistoryEntry?,
        isSelected: Bool,
        isNewlyConfirmed: Bool
    ) -> some View {
        Button(isSelected ? "Deselect QSO" : "Select QSO") {
            appState.toggleRecordSelection(record.id)
        }
        
        let emailVal = record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines)
        if !emailVal.isEmpty {
            Button {
                appState.openEmailComposer(for: record, email: emailVal)
            } label: {
                Label("Send Email to \(emailVal)...", systemImage: "paperplane")
            }
        }
        
        if !call.isEmpty {
            Button {
                activeTablePopover = .callsign(record)
            } label: {
                Label("Inspect Callsign '\(call)'...", systemImage: "info.circle")
            }
            
            Button("Enrich QRZ Name & Email for '\(call)'") {
                Task { await appState.fetchAndStoreQRZEmail(for: call) }
            }
        }

        let gridVal = record["GRIDSQUARE"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? record["GRID"].trimmingCharacters(in: .whitespacesAndNewlines)
            : record["GRIDSQUARE"].trimmingCharacters(in: .whitespacesAndNewlines)
        if !gridVal.isEmpty {
            Button {
                activeTablePopover = .grid(GridInspectionContext(
                    record: record,
                    fullGrid: gridVal,
                    call: call,
                    country: record["COUNTRY"]
                ))
            } label: {
                Label("Inspect Grid Locator '\(gridVal.uppercased())' (World Map)...", systemImage: "map.fill")
            }
        }
        
        if !appState.selectedRecordIDs.isEmpty {
            Divider()
            Button("🪄 Enrich Selected (\(appState.selectedRecordIDs.count) Rows)") {
                appState.enrichSelectedRecords()
            }
            Button("✉️ Batch Email Selected (\(appState.selectedRecordIDs.count) Rows)...") {
                appState.openBatchEmailComposerForSelected()
            }
            Button("⬇️ Export Selected (\(appState.selectedRecordIDs.count) Rows) to ADIF...") {
                appState.exportSelectedRecordsAs()
            }
            Button(role: .destructive) {
                appState.deleteSelectedRecords()
            } label: {
                Label("Delete Selected (\(appState.selectedRecordIDs.count) Rows)", systemImage: "trash.fill")
            }
        }

        if !call.isEmpty {
            Divider()
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

            Button {
                selectedEQSLRecord = record
                showEQSLCardSheet = true
            } label: {
                Label("View eQSL Graphic Card", systemImage: "photo.badge.checkmark")
            }

            if let sentEmail {
                Button {
                    activeTablePopover = .sentEmail(SentEmailDetailContext(record: record, entry: sentEmail))
                } label: {
                    Label("View Sent Email Details", systemImage: "envelope.badge")
                }
            }

            if isNewlyConfirmed {
                Button {
                    appState.unmarkRecordAsNewlyConfirmed(id: record.id)
                } label: {
                    Label("Remove New Confirmed Highlight", systemImage: "sparkles.slash")
                }
            } else if record.isConfirmed {
                Button {
                    appState.markRecordAsNewlyConfirmed(id: record.id)
                } label: {
                    Label("Highlight as Newly Confirmed", systemImage: "sparkles")
                }
            }
        }
        
        Divider()
        
        Button("Delete QSO") {
            appState.deleteRecord(id: record.id)
        }
    }

    private func autoFitColumnWidth(_ header: String) {
        let meta = headerMeta(for: header)
        var maxChars = meta.title.count + 5
        let sample = appState.filteredRecords.prefix(100)
        for record in sample {
            let val = record[header]
            if header == "QSO_DATE" {
                maxChars = max(maxChars, formatDate(val).count)
            } else if header == "TIME_ON" || header == "TIME" || header == "TIME_OFF" {
                maxChars = max(maxChars, formatTime(val).count)
            } else if header == "GRIDSQUARE" || header == "GRID" {
                maxChars = max(maxChars, 4 + 1)
            } else if header == "CALL" {
                // Account for callsign chars plus badges (NEW/TODAY, QSL card icon, email icon)
                maxChars = max(maxChars, val.count + 8)
            } else {
                maxChars = max(maxChars, val.count)
            }
        }
        let computed = CGFloat(maxChars * 8 + 24)
        columnWidths[header] = max(defaultColumnWidth(for: header), min(computed, 340))
    }

    // MARK: - QSL Multi-Status Grid & Typography Helpers
    private enum QSLChannelState {
        case confirmed
        case sent
        case none
        
        var color: Color {
            switch self {
            case .confirmed: return Color(red: 0.25, green: 0.95, blue: 0.45) // Neon green
            case .sent: return Color(red: 1.0, green: 0.65, blue: 0.15) // Vibrant amber
            case .none: return Color(white: 0.35).opacity(0.35) // Muted dark gray
            }
        }
        
        var bgOpacity: Double {
            switch self {
            case .confirmed: return 0.22
            case .sent: return 0.18
            case .none: return 0.04
            }
        }
    }

    private func qslChannelStatus(rcvd: String, sent: String, extraConfirmed: Bool = false) -> QSLChannelState {
        let r = rcvd.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let s = sent.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if ["Y", "V", "C"].contains(r) || extraConfirmed {
            return .confirmed
        } else if ["Y", "R", "Q"].contains(s) {
            return .sent
        } else {
            return .none
        }
    }

    @ViewBuilder
    private func qslMultiStatusGrid(for record: QSORecordModel) -> some View {
        let isLotwConf = ["Y", "V", "C"].contains(record["LOTW_QSL_RCVD"].uppercased()) || record["APP_LOTW_QSL_RCVD"].uppercased() == "Y"
        let lotwStatus = qslChannelStatus(
            rcvd: record["LOTW_QSL_RCVD"],
            sent: record["LOTW_QSL_SENT"],
            extraConfirmed: isLotwConf
        )

        let isEqslConf = ["Y", "V", "C"].contains(record["EQSL_QSL_RCVD"].uppercased()) || record["APP_EQSL_QSL_RCVD"].uppercased() == "Y"
        let eqslStatus = qslChannelStatus(
            rcvd: record["EQSL_QSL_RCVD"],
            sent: record["EQSL_QSL_SENT"],
            extraConfirmed: isEqslConf
        )

        let isQrzConf = ["Y", "V", "C"].contains(record["QRZLOG_QSL_RCVD"].uppercased()) ||
            ["Y", "V", "C"].contains(record["QRZCOM_QSL_RCVD"].uppercased()) ||
            ["Y", "V", "C"].contains(record["QRZ_QSL_RCVD"].uppercased()) ||
            record["APP_YAAM_QRZ_CONFIRMED"] == "Y" ||
            record["APP_QRZLOG_STATUS"].uppercased() == "C"
        let qrzSent = record["QRZLOG_QSL_SENT"].isEmpty ? (record["QRZCOM_QSL_SENT"].isEmpty ? record["QRZ_QSL_SENT"] : record["QRZCOM_QSL_SENT"]) : record["QRZLOG_QSL_SENT"]
        let qrzStatus = qslChannelStatus(
            rcvd: record["QRZLOG_QSL_RCVD"],
            sent: qrzSent,
            extraConfirmed: isQrzConf
        )

        let isCardConf = ["Y", "V", "C"].contains(record["QSL_RCVD"].uppercased())
        let cardStatus = qslChannelStatus(
            rcvd: record["QSL_RCVD"],
            sent: record["QSL_SENT"],
            extraConfirmed: isCardConf
        )
        
        HStack(spacing: 3) {
            qslBadge(label: "L", state: lotwStatus)
            qslBadge(label: "e", state: eqslStatus)
            qslBadge(label: "Q", state: qrzStatus)
            qslBadge(label: "C", state: cardStatus)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .help(qslTooltip(record: record, lotw: lotwStatus, eqsl: eqslStatus, qrz: qrzStatus, card: cardStatus))
    }

    private func qslBadge(label: String, state: QSLChannelState) -> some View {
        Text(label)
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .foregroundColor(state.color)
            .frame(width: 14, height: 16)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(state.color.opacity(state.bgOpacity))
            )
    }

    private func qslTooltip(record: QSORecordModel, lotw: QSLChannelState, eqsl: QSLChannelState, qrz: QSLChannelState, card: QSLChannelState) -> String {
        func desc(channel: String, state: QSLChannelState) -> String {
            switch state {
            case .confirmed: return "\(channel): Confirmed (Rcvd)"
            case .sent: return "\(channel): Sent / Pending"
            case .none: return "\(channel): None"
            }
        }
        return [
            desc(channel: "LoTW", state: lotw),
            desc(channel: "eQSL", state: eqsl),
            desc(channel: "QRZ", state: qrz),
            desc(channel: "Paper Card", state: card)
        ].joined(separator: "\n")
    }

    private func formatDate(_ rawDate: String) -> String {
        let trimmed = rawDate.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 8, trimmed.allSatisfy({ $0.isNumber }) {
            let year = trimmed.prefix(4)
            let month = trimmed.dropFirst(4).prefix(2)
            let day = trimmed.suffix(2)
            return "\(year)-\(month)-\(day)"
        }
        return rawDate
    }

    private func formatTime(_ rawTime: String) -> String {
        let trimmed = rawTime.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count == 6, trimmed.allSatisfy({ $0.isNumber }) {
            let h = trimmed.prefix(2)
            let m = trimmed.dropFirst(2).prefix(2)
            let s = trimmed.suffix(2)
            return "\(h):\(m):\(s)"
        } else if trimmed.count == 4, trimmed.allSatisfy({ $0.isNumber }) {
            let h = trimmed.prefix(2)
            let m = trimmed.suffix(2)
            return "\(h):\(m)"
        }
        return rawTime
    }

    @ViewBuilder
    private func formattedFrequencyView(_ rawFreq: String) -> some View {
        let trimmed = rawFreq.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dotIndex = trimmed.firstIndex(of: ".") {
            let mhz = String(trimmed[..<dotIndex])
            let decimals = String(trimmed[trimmed.index(after: dotIndex)...])
            if decimals.count > 3 {
                let khz = String(decimals.prefix(3))
                let hz = String(decimals.dropFirst(3))
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(mhz).\(khz)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.primary)
                    Text(hz)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .lineLimit(1)
            } else {
                Text(trimmed)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        } else {
            Text(trimmed)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
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

    private struct HeaderMeta {
        let title: String
        let icon: String
    }

    private func headerMeta(for header: String) -> HeaderMeta {
        switch header {
        case "QSL":
            return HeaderMeta(title: "QSL", icon: "checkmark.seal.fill")
        case "QSO_DATE":
            return HeaderMeta(title: "Date", icon: "calendar")
        case "TIME_ON", "TIME":
            return HeaderMeta(title: "Time", icon: "clock")
        case "TIME_OFF":
            return HeaderMeta(title: "Time Off", icon: "clock.badge.checkmark")
        case "CALL":
            return HeaderMeta(title: "Callsign", icon: "antenna.radiowaves.left.and.right")
        case "FREQ":
            return HeaderMeta(title: "Frequency", icon: "waveform.path")
        case "FREQ_RX":
            return HeaderMeta(title: "RX Frequency", icon: "waveform.path")
        case "BAND":
            return HeaderMeta(title: "Band", icon: "wave.3.left")
        case "BAND_RX":
            return HeaderMeta(title: "RX Band", icon: "wave.3.left")
        case "MODE":
            return HeaderMeta(title: "Mode", icon: "bolt.fill")
        case "SUBMODE":
            return HeaderMeta(title: "Submode", icon: "bolt")
        case "RST_SENT":
            return HeaderMeta(title: "Sent", icon: "arrow.up.circle.fill")
        case "RST_RCVD":
            return HeaderMeta(title: "Rcvd", icon: "arrow.down.circle.fill")
        case "NAME":
            return HeaderMeta(title: "Name", icon: "person.fill")
        case "QTH":
            return HeaderMeta(title: "QTH", icon: "house.fill")
        case "COUNTRY":
            return HeaderMeta(title: "Country", icon: "globe.europe.africa.fill")
        case "CONT":
            return HeaderMeta(title: "Continent", icon: "map.fill")
        case "GRIDSQUARE", "GRID":
            return HeaderMeta(title: "Grid", icon: "square.grid.3x3.fill")
        case "DXCC":
            return HeaderMeta(title: "DXCC", icon: "flag.fill")
        case "CQZ":
            return HeaderMeta(title: "CQ Zone", icon: "circle.grid.cross.fill")
        case "ITUZ":
            return HeaderMeta(title: "ITU Zone", icon: "circle.grid.3x3.fill")
        case "STATE":
            return HeaderMeta(title: "State", icon: "mappin.circle.fill")
        case "EMAIL":
            return HeaderMeta(title: "Email", icon: "envelope.fill")
        case "QRZ_URL", "QRZ":
            return HeaderMeta(title: "QRZ", icon: "safari.fill")
        case "RANK_QSO":
            return HeaderMeta(title: "QSO Rank", icon: "trophy.fill")
        case "RANK_BAND":
            return HeaderMeta(title: "Band Rank", icon: "medal.fill")
        case "RANK_DXCC":
            return HeaderMeta(title: "DXCC Rank", icon: "rosette")
        case ConfirmationCreditColumn.countryBand:
            return HeaderMeta(title: "Band Credit", icon: "sparkles")
        case ConfirmationCreditColumn.grid:
            return HeaderMeta(title: "Grid Credit", icon: "square.grid.3x3.fill")
        case "APP_YAAM_LAST_EMAIL":
            return HeaderMeta(title: "Last Email", icon: "envelope.badge.fill")
        case "COMMENT":
            return HeaderMeta(title: "Comment", icon: "bubble.left.fill")
        case "PROP_MODE":
            return HeaderMeta(title: "Propagation", icon: "rays")
        case "SAT_NAME":
            return HeaderMeta(title: "Satellite", icon: "orbit")
        default:
            return HeaderMeta(title: header, icon: "tag.fill")
        }
    }

    private func defaultColumnWidth(for header: String) -> CGFloat {
        switch header {
        case "QSL": return 76
        case "EMAIL": return 76
        case "APP_YAAM_LAST_EMAIL": return 220
        case "QRZ_URL", "QRZ": return 48
        case "RANK_QSO": return 105
        case "RANK_BAND": return 105
        case "RANK_DXCC": return 115
        case ConfirmationCreditColumn.countryBand: return 105
        case ConfirmationCreditColumn.grid: return 96
        case "QSO_DATE": return 92
        case "TIME", "TIME_ON", "TIME_OFF": return 72
        case "CALL": return 142
        case "FREQ": return 88
        case "FREQ_RX": return 94
        case "BAND": return 64
        case "BAND_RX": return 68
        case "MODE", "SUBMODE": return 64
        case "CONT": return 52
        case "RST_SENT", "RST_RCVD": return 62
        case "NAME": return 130
        case "QTH": return 120
        case "COUNTRY": return 130
        case "GRIDSQUARE", "GRID": return 76
        case "DXCC": return 64
        case "CQZ", "ITUZ": return 68
        case "COMMENT": return 180
        default: return 84
        }
    }

    /// Columns that remain left-aligned: Callsign, Name, Country, QTH, Comment, Propagation, and Leaderboard Ranks
    private func isLeftAlignedColumn(_ header: String) -> Bool {
        header == "CALL" || header == "NAME" || header == "COUNTRY" || header == "QTH" || header == "COMMENT" || header == "PROP_MODE" || header == "SAT_NAME" || header == "APP_YAAM_LAST_EMAIL"
    }

    /// Columns that are numbers and right-aligned: Frequency, RST reports, Ranks, and Zones
    private func isRightAlignedColumn(_ header: String) -> Bool {
        header == "FREQ" || header == "FREQ_RX" || header == "RST_SENT" || header == "RST_RCVD" || header == "DXCC" || header == "CQZ" || header == "ITUZ" || header.hasPrefix("RANK_")
    }

    private func isCompactCenteredColumn(_ header: String) -> Bool {
        !isLeftAlignedColumn(header) && !isRightAlignedColumn(header)
    }

    private func tableAlignment(for header: String) -> Alignment {
        if isRightAlignedColumn(header) {
            return .trailing
        } else if isLeftAlignedColumn(header) {
            return .leading
        } else {
            return .center
        }
    }

    private func displayTitle(for header: String) -> String {
        headerMeta(for: header).title
    }

    private var hiddenColumnCount: Int {
        appState.tableHeaders.filter { isHiddenByDefault($0) && !explicitlyShownColumns.contains($0) }.count
    }

    private var displayedHeaders: [String] {
        let visibleStoredHeaders = appState.tableHeaders.filter { header in
            !isHiddenByDefault(header) || explicitlyShownColumns.contains(header)
        }
        var headers = visibleStoredHeaders
        if !headers.contains("QSL") {
            headers.append("QSL")
        }
        for derived in ConfirmationCreditColumn.headers {
            if explicitlyShownColumns.contains(derived) && !headers.contains(derived) {
                headers.append(derived)
            }
        }
        var uniqueHeaders: [String] = []
        var seen = Set<String>()
        for h in headers {
            let key = h.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !seen.contains(key) {
                seen.insert(key)
                uniqueHeaders.append(h)
            }
        }
        return orderedHeaders(uniqueHeaders)
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
        if header == "GRIDSQUARE" || header == "GRID" {
            return 7
        }
        if let preferredIndex = preferredColumnOrder.firstIndex(of: header) {
            return preferredIndex >= 7 ? preferredIndex + 1 : preferredIndex
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
        explicitlyShownColumns = Set(saved.filter {
            appState.tableHeaders.contains($0) && !TableColumnPolicy.isDatabaseOnly($0)
        })
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

// MARK: - Sent Email Detail Context & Popover Card
struct SentEmailDetailContext: Identifiable {
    let id = UUID()
    let record: QSORecordModel
    let entry: EmailHistoryEntry
}

struct SentEmailDetailCard: View {
    let record: QSORecordModel
    let entry: EmailHistoryEntry
    let onComposeFollowUp: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.cyan)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sent Email to \(entry.callsign)")
                        .font(.headline)
                    Text("Outbox Communication Record")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer(minLength: 12)
                
                let isSent = entry.status.localizedCaseInsensitiveContains("Sent")
                HStack(spacing: 4) {
                    Image(systemName: isSent ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    Text(entry.status)
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isSent ? .green : .red)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(isSent ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                )
            }
            
            Divider()
            
            // Detail rows
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text("Date & Time:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text(formattedDate(entry.date))
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }

                HStack(alignment: .top) {
                    Text("Recipient:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    HStack(spacing: 6) {
                        Text(entry.email.isEmpty ? "(No email address recorded)" : entry.email)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                        if !entry.email.isEmpty {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.email, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Copy recipient email")
                        }
                    }
                }

                HStack(alignment: .top) {
                    Text("Subject:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    Text(entry.subject.isEmpty ? "(No subject)" : entry.subject)
                        .font(.system(size: 11, weight: .medium))
                        .textSelection(.enabled)
                }

                HStack(alignment: .top) {
                    Text("QSO Link:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .leading)
                    let summary = [record["BAND"], record["MODE"], record["QSO_DATE"], record["TIME_ON"]].filter { !$0.isEmpty }.joined(separator: " • ")
                    Text(summary.isEmpty ? "QSO Linked" : "\(summary) UTC")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Actions
            HStack {
                Button(action: onComposeFollowUp) {
                    Label("Compose Follow-up", systemImage: "paperplane.fill")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(minWidth: 350, maxWidth: 420)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

// MARK: - Callsign Inspection Popover Card
struct CallsignInspectionCard: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var rotatorService = RotatorService.shared
    @Environment(\.dismiss) private var dismiss

    let record: QSORecordModel
    var onOpenGrid: ((GridInspectionContext) -> Void)? = nil

    private var call: String {
        record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var country: String {
        record["COUNTRY"].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var flag: String {
        countryToFlag(country)
    }

    private var grid: String {
        let g = record["GRIDSQUARE"].trimmingCharacters(in: .whitespacesAndNewlines)
        return g.isEmpty ? record["GRID"].trimmingCharacters(in: .whitespacesAndNewlines) : g
    }

    private var homeCoordinate: GeoCoordinate? {
        if let profile = appState.activeStationProfile {
            if let lat = Double(profile.latitude), let lon = Double(profile.longitude), (lat != 0 || lon != 0) {
                return GeoCoordinate(latitude: lat, longitude: lon)
            }
            if !profile.grid.isEmpty, let box = MaidenheadGridEngine.boundingBox(for: profile.grid) {
                return box.center
            }
        }
        return nil
    }

    private var targetCoordinate: GeoCoordinate? {
        if !grid.isEmpty, let box = MaidenheadGridEngine.boundingBox(for: grid) {
            return box.center
        }
        return nil
    }

    private var geodesicInfo: (sp: Double, lp: Double, distKm: Double, distMi: Double)? {
        guard let home = homeCoordinate, let target = targetCoordinate else { return nil }
        let sp = GeodesicMath.initialBearing(from: home, to: target)
        let lp = GeodesicMath.longPathBearing(from: home, to: target)
        let km = GeodesicMath.distanceKm(from: home, to: target)
        let mi = km * GeodesicMath.kmToMiles
        return (sp, lp, km, mi)
    }

    private var totalQSOsWithCall: Int {
        appState.qsoRecords.filter {
            $0["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == call
        }.count
    }

    private var confirmedQSOsWithCall: Int {
        appState.qsoRecords.filter {
            $0["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == call && $0.isConfirmed
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Flag, Call, Country
            HStack(spacing: 8) {
                if !flag.isEmpty {
                    Text(flag)
                        .font(.system(size: 24))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(call)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                        if appState.isNewlyConfirmed(record: record) {
                            Text("NEW CONFIRMED")
                                .font(.system(size: 8, weight: .heavy))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.pink))
                                .foregroundColor(.white)
                        } else if record.isConfirmed {
                            Text("CONFIRMED")
                                .font(.system(size: 8, weight: .heavy))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.green))
                                .foregroundColor(.white)
                        }
                    }
                    Text(country.isEmpty ? "Unknown DXCC Entity" : country)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Details Grid
            VStack(alignment: .leading, spacing: 8) {
                // Name & QTH
                let name = record["NAME"].trimmingCharacters(in: .whitespacesAndNewlines)
                let qth = record["QTH"].trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty || !qth.isEmpty {
                    HStack(alignment: .top) {
                        Text("Operator:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 85, alignment: .leading)
                        Text([name, qth].filter { !$0.isEmpty }.joined(separator: " • "))
                            .font(.system(size: 11))
                    }
                }

                // Grid
                HStack(alignment: .top) {
                    Text("Grid Square:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 85, alignment: .leading)
                    if !grid.isEmpty && onOpenGrid != nil {
                        Button {
                            onOpenGrid?(GridInspectionContext(
                                record: record,
                                fullGrid: grid,
                                call: call,
                                country: country
                            ))
                        } label: {
                            HStack(spacing: 4) {
                                Text(grid)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.cyan)
                                Image(systemName: "map.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.cyan)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Click to view World Map Locator card for \(grid)")
                    } else {
                        Text(grid.isEmpty ? "Not specified" : grid)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(grid.isEmpty ? .secondary : .primary)
                    }
                }

                // Geodesic Beam & Distance
                if let geo = geodesicInfo {
                    HStack(alignment: .top) {
                        Text("Beam (SP):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 85, alignment: .leading)
                        HStack(spacing: 6) {
                            Text(String(format: "%.0f°", geo.sp))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                            Text("(\(GeodesicMath.compassCardinal(for: geo.sp)))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("• LP: \(String(format: "%.0f°", geo.lp))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack(alignment: .top) {
                        Text("Distance:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 85, alignment: .leading)
                        Text("\(Int(round(geo.distKm))) km (\(Int(round(geo.distMi))) mi)")
                            .font(.system(size: 11, design: .monospaced))
                    }
                } else if !grid.isEmpty {
                    HStack(alignment: .top) {
                        Text("Beam / Dist:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 85, alignment: .leading)
                        Text("Set station coordinates in Settings to calculate beam")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                // Logbook stats
                HStack(alignment: .top) {
                    Text("In Logbook:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 85, alignment: .leading)
                    Text("\(totalQSOsWithCall) QSOs (\(confirmedQSOsWithCall) confirmed)")
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                }

                // Current QSO Info
                HStack(alignment: .top) {
                    Text("This QSO:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 85, alignment: .leading)
                    let qsoDate = record["QSO_DATE"]
                    let qsoTime = record["TIME_ON"]
                    let band = record["BAND"]
                    let mode = record["MODE"]
                    let summary = [band, mode, qsoDate, qsoTime].filter { !$0.isEmpty }.joined(separator: " • ")
                    Text(summary)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Action Buttons: Rotator & QRZ
            HStack(spacing: 8) {
                if let geo = geodesicInfo {
                    Button {
                        rotatorService.turnTo(azimuth: geo.sp)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "location.north.line.fill")
                            Text("Turn Rotator to \(Int(round(geo.sp)))°")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .help("Steer antenna rotator to short path bearing \(Int(round(geo.sp)))°")
                }

                Button {
                    if let url = URL(string: "https://www.qrz.com/db/\(call)"), !call.isEmpty {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "safari.fill")
                        Text("QRZ.com")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .help("Open callsign on QRZ.com")

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(minWidth: 340, maxWidth: 400)
    }
}

// MARK: - Grid Inspection Context, Popover Card & Mini World Map
enum ActiveTablePopover: Identifiable {
    case sentEmail(SentEmailDetailContext)
    case callsign(QSORecordModel)
    case grid(GridInspectionContext)

    var id: String {
        switch self {
        case .sentEmail(let c): return "email-\(c.id)"
        case .callsign(let r): return "call-\(r.id)"
        case .grid(let g): return "grid-\(g.id)"
        }
    }
}

struct GridInspectionContext: Identifiable {
    let id = UUID()
    let record: QSORecordModel
    let fullGrid: String
    let call: String
    let country: String
}

struct GridCellView: View {
    let displayGrid: String
    let fullGrid: String
    let call: String
    let country: String
    let record: QSORecordModel
    let onInspect: (GridInspectionContext) -> Void

    @State private var isHovered: Bool = false
    @State private var hoverTask: Task<Void, Never>? = nil

    var body: some View {
        Button {
            triggerInspection()
        } label: {
            HStack(spacing: 3.5) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(isHovered ? .white : .cyan)
                Text(displayGrid)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(isHovered ? .white : .cyan)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.cyan.opacity(0.85) : Color.cyan.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isHovered ? Color.white.opacity(0.6) : Color.cyan.opacity(0.35), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                hoverTask?.cancel()
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 280_000_000)
                    if !Task.isCancelled {
                        triggerInspection()
                    }
                }
            } else {
                hoverTask?.cancel()
            }
        }
        .help("Grid: \(fullGrid.uppercased()) • Click or pause mouse to view world map locator")
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func triggerInspection() {
        onInspect(GridInspectionContext(
            record: record,
            fullGrid: fullGrid,
            call: call,
            country: country
        ))
    }
}

struct MiniGridWorldMapView: View {
    let boundingBox: MaidenheadBoundingBox?
    let targetCoordinate: GeoCoordinate?
    let homeCoordinate: GeoCoordinate?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.0) / 2.0

            Canvas { context, size in
                func toFlatScreen(lat: Double, lon: Double) -> CGPoint {
                    let x = ((lon + 180.0) / 360.0) * size.width
                    let y = ((90.0 - lat) / 180.0) * size.height
                    return CGPoint(x: x, y: y)
                }

                // 1. Ocean Background
                let bgRect = CGRect(origin: .zero, size: size)
                context.fill(Path(bgRect), with: .color(Color(red: 0.05, green: 0.08, blue: 0.16)))

                // 2. Graticule Lat / Lon Grid Lines
                let eqY = 0.5 * size.height
                var eqPath = Path()
                eqPath.move(to: CGPoint(x: 0, y: eqY))
                eqPath.addLine(to: CGPoint(x: size.width, y: eqY))
                context.stroke(eqPath, with: .color(Color.white.opacity(0.18)), lineWidth: 0.8)

                let pmX = 0.5 * size.width
                var pmPath = Path()
                pmPath.move(to: CGPoint(x: pmX, y: 0))
                pmPath.addLine(to: CGPoint(x: pmX, y: size.height))
                context.stroke(pmPath, with: .color(Color.white.opacity(0.18)), lineWidth: 0.8)

                for lat in [-60.0, -30.0, 30.0, 60.0] {
                    let y = ((90.0 - lat) / 180.0) * size.height
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(p, with: .color(Color.white.opacity(0.06)), lineWidth: 0.5)
                }
                for lon in [-120.0, -60.0, 60.0, 120.0] {
                    let x = ((lon + 180.0) / 360.0) * size.width
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(p, with: .color(Color.white.opacity(0.06)), lineWidth: 0.5)
                }

                // 3. World Continents (Polygons from WorldVectorGeography)
                for poly in WorldVectorGeography.landmassPolygons {
                    guard poly.coordinates.count >= 3 else { continue }
                    var path = Path()
                    var started = false
                    for pt in poly.coordinates {
                        let p = toFlatScreen(lat: pt.latitude, lon: pt.longitude)
                        if !started {
                            path.move(to: p)
                            started = true
                        } else {
                            path.addLine(to: p)
                        }
                    }
                    if started {
                        path.closeSubpath()
                        context.fill(path, with: .color(Color(red: 0.16, green: 0.22, blue: 0.32)))
                        context.stroke(path, with: .color(Color(red: 0.25, green: 0.35, blue: 0.48)), lineWidth: 0.7)
                    }
                }

                // 4. Great Circle Arc from Home to Target
                if let home = homeCoordinate, let target = targetCoordinate {
                    let waypoints = GeodesicMath.greatCircleWaypoints(from: home, to: target, count: 24)
                    if waypoints.count >= 2 {
                        var arcPath = Path()
                        var lastPt: CGPoint? = nil
                        for wp in waypoints {
                            let pt = toFlatScreen(lat: wp.latitude, lon: wp.longitude)
                            if let last = lastPt {
                                if abs(pt.x - last.x) < size.width * 0.5 {
                                    arcPath.addLine(to: pt)
                                } else {
                                    arcPath.move(to: pt)
                                }
                            } else {
                                arcPath.move(to: pt)
                            }
                            lastPt = pt
                        }
                        context.stroke(arcPath, with: .color(Color.yellow.opacity(0.85)), style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
                    }
                }

                // 5. Maidenhead Grid Square (Bounding Box)
                if let box = boundingBox {
                    let pTopLeft = toFlatScreen(lat: box.maxLat, lon: box.minLon)
                    let pBottomRight = toFlatScreen(lat: box.minLat, lon: box.maxLon)
                    let boxW = max(3.5, pBottomRight.x - pTopLeft.x)
                    let boxH = max(3.5, pBottomRight.y - pTopLeft.y)
                    let rect = CGRect(x: pTopLeft.x, y: pTopLeft.y, width: boxW, height: boxH)

                    context.fill(Path(rect), with: .color(Color.cyan.opacity(0.40)))
                    context.stroke(Path(rect), with: .color(Color.cyan), lineWidth: 1.5)
                }

                // 6. Target Pin / Animated Radar Target
                if let target = targetCoordinate {
                    let pt = toFlatScreen(lat: target.latitude, lon: target.longitude)
                    let pulseRadius = 5.0 + (phase * 15.0)
                    let pulseOpacity = max(0.0, 0.85 * (1.0 - phase))
                    
                    // Animated outer radar pulse ring
                    context.stroke(
                        Path(ellipseIn: CGRect(x: pt.x - pulseRadius, y: pt.y - pulseRadius, width: pulseRadius * 2, height: pulseRadius * 2)),
                        with: .color(Color.cyan.opacity(pulseOpacity)),
                        lineWidth: 1.2
                    )
                    // Inner crisp ring
                    context.stroke(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)), with: .color(Color.white), lineWidth: 1.5)
                    // Center glowing dot
                    context.fill(Path(ellipseIn: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)), with: .color(Color.cyan))
                }

                // 7. Home Station Indicator
                if let home = homeCoordinate {
                    let pt = toFlatScreen(lat: home.latitude, lon: home.longitude)
                    context.fill(Path(ellipseIn: CGRect(x: pt.x - 3.5, y: pt.y - 3.5, width: 7, height: 7)), with: .color(Color.green))
                    context.stroke(Path(ellipseIn: CGRect(x: pt.x - 3.5, y: pt.y - 3.5, width: 7, height: 7)), with: .color(Color.white), lineWidth: 1.2)
                }
            }
        }
        .frame(height: 165)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 0.8))
    }
}

struct GridInspectionCard: View {
    let context: GridInspectionContext
    let homeCoordinate: GeoCoordinate?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var rotatorService = RotatorService.shared

    private var boundingBox: MaidenheadBoundingBox? {
        MaidenheadGridEngine.boundingBox(for: context.fullGrid)
    }

    private var targetCoordinate: GeoCoordinate? {
        boundingBox?.center
    }

    private var geodesicInfo: (sp: Double, lp: Double, distKm: Double, distMi: Double)? {
        guard let home = homeCoordinate, let target = targetCoordinate else { return nil }
        let sp = GeodesicMath.initialBearing(from: home, to: target)
        let lp = GeodesicMath.longPathBearing(from: home, to: target)
        let km = GeodesicMath.distanceKm(from: home, to: target)
        let mi = km * GeodesicMath.kmToMiles
        return (sp, lp, km, mi)
    }

    private var majorGrid: String {
        String(context.fullGrid.prefix(4)).uppercased()
    }

    private var flag: String {
        countryToFlag(context.country)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Icon, Callsign, Country
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.cyan)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(context.call.isEmpty ? majorGrid : "\(context.call) • \(majorGrid)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                        if !flag.isEmpty {
                            Text(flag)
                        }
                    }
                    if !context.country.isEmpty {
                        Text(context.country)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // World Map Preview
            MiniGridWorldMapView(
                boundingBox: boundingBox,
                targetCoordinate: targetCoordinate,
                homeCoordinate: homeCoordinate
            )

            // Grid Details & Breakdown
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Grid:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(majorGrid)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.cyan)

                        if context.fullGrid.count > 4 {
                            Text("(\(context.fullGrid.uppercased()))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.85))
                        }
                    }

                    if let target = targetCoordinate {
                        Text(String(format: "Coordinates: %.4f° %@, %.4f° %@",
                                    abs(target.latitude), target.latitude >= 0 ? "N" : "S",
                                    abs(target.longitude), target.longitude >= 0 ? "E" : "W"))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Geodesic Telemetry (Distance & Bearing)
                if let geo = geodesicInfo {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int(round(geo.distKm))) km (\(Int(round(geo.distMi))) mi)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)

                        HStack(spacing: 4) {
                            Text(String(format: "%.0f°", geo.sp))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                            Text("(\(GeodesicMath.compassCardinal(for: geo.sp)))")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)

            // Rotator Steer Action Button
            if let geo = geodesicInfo {
                if rotatorService.isConnected {
                    Button {
                        rotatorService.turnTo(azimuth: geo.sp)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Turn Rotator to \(Int(round(geo.sp)))° (\(GeodesicMath.compassCardinal(for: geo.sp)))")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .help("Steer rotator antenna to short path bearing \(Int(round(geo.sp)))°")
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.secondary)
                        Text("Beam Bearing: \(Int(round(geo.sp)))° (\(GeodesicMath.compassCardinal(for: geo.sp)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("Rotator Disconnected")
                            .font(.system(size: 9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                            .foregroundColor(.secondary)
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
                }
            }
        }
        .padding(12)
        .frame(width: 350)
    }
}

private struct LogTableScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

