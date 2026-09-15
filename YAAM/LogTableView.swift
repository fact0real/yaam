//
//  LogTableView.swift
//  YAAM
//
//  Created by factoreal on 7/30/26.
//

import SwiftUI

// MARK: - Log Table Layout & Column Alignment Helpers
fileprivate enum LogTableLayout {
    static let compactCenteredColumns: Set<String> = [
        "TIME", "TIME_ON", "CALL", "QSL", "AGING", "APP_VIEW_AGING",
        "QSL_VIA", "QSL_SENT_VIA", "ROUTE", "FREQ", "BAND", "BAND_RX",
        "MODE", "CONT", "RST_SENT", "RST_RCVD", "GRIDSQUARE", "GRID"
    ]

    static let preferredColumnOrder = [
        "QSO_DATE", "TIME_ON", "CALL", "QSL", "AGING", "FREQ", "BAND", "MODE",
        "GRIDSQUARE", "COUNTRY", "NAME", "QTH", "CONT", "DXCC", "CQZ", "ITUZ",
        "QSL_VIA", ConfirmationCreditColumn.countryBand, ConfirmationCreditColumn.grid
    ]

    static let preferredColumnIndices: [String: Int] = {
        var dict: [String: Int] = [:]
        for (idx, col) in preferredColumnOrder.enumerated() {
            dict[col] = idx
        }
        return dict
    }()

    static func defaultColumnWidth(for header: String) -> CGFloat {
        switch header {
        case "QSL": return 88
        case "AGING", "APP_VIEW_AGING": return 78
        case "QSL_VIA", "QSL_SENT_VIA", "QSL_RCVD_VIA", "ROUTE": return 88
        case "EMAIL": return 50
        case "APP_YAAM_LAST_EMAIL": return 220
        case "QRZ_URL", "QRZ": return 74
        case "RANK_QSO": return 118
        case "RANK_BAND": return 118
        case "RANK_DXCC": return 128
        case ConfirmationCreditColumn.countryBand: return 110
        case ConfirmationCreditColumn.grid: return 100
        case "QSO_DATE": return 96
        case "TIME", "TIME_ON", "TIME_OFF": return 76
        case "CALL": return 152
        case "FREQ": return 108
        case "FREQ_RX": return 114
        case "BAND": return 72
        case "BAND_RX": return 76
        case "MODE": return 74
        case "SUBMODE": return 80
        case "CONT": return 104
        case "RST_SENT", "RST_RCVD": return 68
        case "NAME": return 155
        case "QTH": return 135
        case "COUNTRY": return 150
        case "GRIDSQUARE", "GRID": return 82
        case "DXCC": return 66
        case "CQZ", "ITUZ": return 70
        case "COMMENT": return 220
        default: return 90
        }
    }

    static func isLeftAlignedColumn(_ header: String) -> Bool {
        header == "CALL" || header == "NAME" || header == "COUNTRY" || header == "QTH" || header == "COMMENT" || header == "PROP_MODE" || header == "SAT_NAME" || header == "APP_YAAM_LAST_EMAIL"
    }

    static func isRightAlignedColumn(_ header: String) -> Bool {
        header == "FREQ" || header == "FREQ_RX" || header == "RST_SENT" || header == "RST_RCVD" || header == "DXCC" || header == "CQZ" || header == "ITUZ"
    }

    static func isCompactCenteredColumn(_ header: String) -> Bool {
        !isLeftAlignedColumn(header) && !isRightAlignedColumn(header)
    }

    static func tableAlignment(for header: String) -> Alignment {
        if isRightAlignedColumn(header) {
            return .trailing
        } else if isLeftAlignedColumn(header) {
            return .leading
        } else {
            return .center
        }
    }
}

// MARK: - Row Actions
enum LogRowAction {
    case toggleSelection
    case startEditing(header: String, value: String)
    case commitEditing(header: String, value: String)
    case inspectCallsign
    case inspectGrid(GridInspectionContext)
    case showSentEmail(SentEmailDetailContext)
    case showRankLegend
    case showEQSLCard
    case toggleAgingSort
    case openEmail(String)
    case openReminder
    case openQSLCardComposer
    case openEmailQSLCard
    case openCongratulations
    case enrichCallsign
    case delete
    case batchEnrich
    case batchReminders
    case batchEmails
    case batchExport
    case batchDelete
    case markNewlyConfirmed
    case unmarkNewlyConfirmed
    case trackRival(String)
    case untrackRival(String)
}

// MARK: - High Performance Spreadsheet Table View Component
struct LogTableView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var editingCellID: UUID? = nil
    @State private var editingHeader: String? = nil
    @State private var editingText: String = ""
    
    @State private var columnWidths: [String: CGFloat] = [:]
    @State private var dragStartWidths: [String: CGFloat] = [:]
    @State private var explicitlyShownColumns: Set<String> = []
    @State private var cachedDisplayedHeaders: [String] = []
    @State private var cachedPinnedHeaders: [String] = []
    @State private var cachedUnpinnedHeaders: [String] = []
    @State private var showFullConfirmationSyncPrompt = false
    @State private var selectedEQSLRecord: QSORecordModel? = nil
    @State private var showEQSLCardSheet = false
    @State private var activeTablePopover: ActiveTablePopover? = nil
    @State private var pinnedOffsetX: CGFloat = 0
    @State private var isRoverControlSheetPresented = false
    @State private var localSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var displayLimit: Int = 1000
    @State private var showBackToTop: Bool = false
    @State private var tableScrollView: NSScrollView? = nil

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

    private var compactCenteredColumns: Set<String> {
        LogTableLayout.compactCenteredColumns
    }

    private var preferredColumnOrder: [String] {
        LogTableLayout.preferredColumnOrder
    }

    private var utilityColumnWidth: CGFloat {
        appState.filterCriteria.isActive ? 82 : 48
    }

    private func scrollToTop(proxy: ScrollViewProxy) {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        if let scrollView = tableScrollView {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: 0))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            proxy.scrollTo("logTableTopAnchor", anchor: .topLeading)
        }
    }

    var body: some View {
        let visibleRecords = appState.filteredRecords
        let currentPinned = cachedPinnedHeaders.isEmpty ? pinnedHeaders : cachedPinnedHeaders
        let currentUnpinned = cachedUnpinnedHeaders.isEmpty ? unpinnedHeaders : cachedUnpinnedHeaders

        ScrollViewReader { scrollProxy in
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

                    Divider()

                    Button {
                        AuditLogger.shared.revealInFinder()
                    } label: {
                        Label("Reveal Activity Audit Log in Finder...", systemImage: "doc.text.magnifyingglass")
                    }
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
                    Button {
                        isRoverControlSheetPresented = true
                    } label: {
                        if RoverModeEngine.shared.isRoverActive, let session = RoverModeEngine.shared.activeSession {
                            Label("Rover Active: \(session.targetGrid) (\(session.formattedRemainingTime))", systemImage: "shoeprints.fill")
                        } else {
                            Label("Tactical Rover / Portable Scout...", systemImage: "figure.walk")
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
                    Section("Sync & Cloud") {
                        Button {
                            appState.syncConfirmations()
                        } label: {
                            Label("Sync New QSLs (LoTW & QRZ)", systemImage: "arrow.clockwise.icloud")
                        }
                        .disabled(appState.isSyncingAPI || appState.qsoRecords.isEmpty)

                        Button {
                            showFullConfirmationSyncPrompt = true
                        } label: {
                            Label("Full QSL History Reconciliation...", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(appState.isSyncingAPI || appState.qsoRecords.isEmpty)

                        Button {
                            appState.confirmAndFetchCloudLogbook()
                        } label: {
                            Label("Download LoTW Cloud Logbook...", systemImage: "icloud.and.arrow.down.fill")
                        }
                    }

                    Divider()

                    Section("Enrichment & Ranks") {
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
                    }

                    Divider()

                    Section("Batch QSL & Reminders") {
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
                    }

                    Divider()

                    Section("Tools & Services") {
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
                    }
                } label: {
                    HStack(spacing: 4) {
                        if appState.isEnriching || appState.isSendingBatchMail || appState.isSyncingAPI {
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
                .help("Log actions: Sync QSLs, QRZ enrichment, rank backfill, QSL batch mail, and tools")

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

                    TextField(appState.logSearchMode.placeholder, text: $localSearchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .disableAutocorrection(true)
                        .onChange(of: localSearchText) { _, newValue in
                            let sanitized = EnglishSearchInputFilter.sanitize(newValue)
                            if sanitized != newValue {
                                localSearchText = sanitized
                                return
                            }
                            searchDebounceTask?.cancel()
                            searchDebounceTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 120_000_000)
                                if !Task.isCancelled {
                                    appState.searchText = sanitized
                                }
                            }
                        }
                        .onSubmit {
                            searchDebounceTask?.cancel()
                            let sanitized = EnglishSearchInputFilter.sanitize(localSearchText)
                            localSearchText = sanitized
                            appState.searchText = sanitized
                        }

                    if !localSearchText.isEmpty {
                        Button(action: {
                            localSearchText = ""
                            searchDebounceTask?.cancel()
                            appState.searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Clear search")
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

                let overdueCount = appState.overduePendingCount
                if overdueCount > 0 {
                    Button {
                        appState.filterCriteria.useOverduePending.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "hourglass.bottomhalf.filled")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.orange)
                            Text("Overdue >30d (\(overdueCount))")
                                .font(.system(size: 11, weight: appState.filterCriteria.useOverduePending ? .bold : .medium))
                                .foregroundColor(appState.filterCriteria.useOverduePending ? .orange : .primary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(appState.filterCriteria.useOverduePending ? Color.orange.opacity(0.22) : Color.orange.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(appState.filterCriteria.useOverduePending ? Color.orange : Color.orange.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(appState.filterCriteria.useOverduePending ? "Showing unconfirmed QSOs pending over 30 days. Click to reset." : "Filter log table to show \(overdueCount) overdue unconfirmed QSOs (>30 days)")
                }

                let unconfCount = appState.unconfirmedCount
                if unconfCount > 0 && unconfCount < appState.qsoRecords.count {
                    Button {
                        appState.filterCriteria.useUnconfirmedOnly.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "circle.dashed")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(appState.filterCriteria.useUnconfirmedOnly ? .primary : .secondary)
                            Text("Pending (\(unconfCount))")
                                .font(.system(size: 11, weight: appState.filterCriteria.useUnconfirmedOnly ? .bold : .medium))
                                .foregroundColor(appState.filterCriteria.useUnconfirmedOnly ? .primary : .secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(appState.filterCriteria.useUnconfirmedOnly ? Color.secondary.opacity(0.22) : Color.secondary.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(appState.filterCriteria.useUnconfirmedOnly ? Color.secondary : Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(appState.filterCriteria.useUnconfirmedOnly ? "Showing all unconfirmed contacts. Click to reset." : "Filter to show \(unconfCount) unconfirmed contacts awaiting QSL")
                }

                let lotwWaitCount = appState.lotwWaitingCount
                if lotwWaitCount > 0 {
                    Button {
                        appState.filterCriteria.useLotwWaiting.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(appState.filterCriteria.useLotwWaiting ? Color(red: 0.25, green: 0.95, blue: 0.45) : .green)
                            Text("LoTW Wait (\(lotwWaitCount))")
                                .font(.system(size: 11, weight: appState.filterCriteria.useLotwWaiting ? .bold : .medium))
                                .foregroundColor(appState.filterCriteria.useLotwWaiting ? Color(red: 0.25, green: 0.95, blue: 0.45) : .primary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(appState.filterCriteria.useLotwWaiting ? Color.green.opacity(0.22) : Color.green.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(appState.filterCriteria.useLotwWaiting ? Color.green : Color.green.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(appState.filterCriteria.useLotwWaiting ? "Showing contacts sent to LoTW awaiting match. Click to reset." : "Filter log table to show \(lotwWaitCount) contacts sent to LoTW awaiting match")
                }
                
                if appState.isLoading && !appState.qsoRecords.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                }
                
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()

            if appState.filterCriteria.useTodayConfirmed {
                todayConfirmedBanner
            }

            if appState.isLoading && appState.qsoRecords.isEmpty {
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
                ZStack(alignment: .bottomTrailing) {
                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            ScrollViewAccessor { self.tableScrollView = $0 }
                                .frame(width: 0, height: 0)

                            GeometryReader { geo in
                                let frame = geo.frame(in: .named("logTableScrollSpace"))
                                let rawX = frame.minX
                                let scrollX = max(0, -rawX)
                                let quantizedX = scrollX < 10.0 ? 0.0 : (floor(scrollX / 8.0) * 8.0)
                                let rawY = frame.minY
                                let scrollY = max(0, -rawY)
                                let isScrolledDown = scrollY > 60.0

                                Color.clear.preference(
                                    key: LogTableScrollStateKey.self,
                                    value: LogTableScrollState(quantizedX: quantizedX, isScrolledDown: isScrolledDown)
                                )
                            }
                            .frame(height: 0)

                                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                                    Section {
                                        Color.clear
                                            .frame(width: 1, height: 1)
                                            .id("logTableTopAnchor")

                                        let renderedRecords = Array(visibleRecords.prefix(displayLimit))
                                        let trackedRivalsSet = Set(appState.trackedRankCallsigns.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })
                                        let hasBatch = !appState.selectedRecordIDs.isEmpty
                                        let batchCount = appState.selectedRecordIDs.count

                                        ForEach(renderedRecords) { record in
                                            let cleanCall = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                                            LogRowView(
                                                record: record,
                                                isSelected: appState.selectedRecordIDs.contains(record.id),
                                                isNewlyConfirmed: appState.isNewlyConfirmed(recordID: record.id),
                                                isTodayConfirmed: appState.isTodayConfirmed(recordID: record.id),
                                                ordinal: appState.filteredChronologicalOrdinal(for: record.id),
                                                sentEmail: appState.emailHistoryByCallsign[cleanCall],
                                                opportunity: appState.confirmationOpportunityIndex.opportunity(for: record.id),
                                                pinnedOffsetX: pinnedOffsetX,
                                                isEditingThisRow: editingCellID == record.id,
                                                editingHeader: editingCellID == record.id ? editingHeader : nil,
                                                editingText: $editingText,
                                                isTrackedRival: trackedRivalsSet.contains(cleanCall),
                                                hasBatchSelection: hasBatch,
                                                batchSelectionCount: batchCount,
                                                pinnedHeaders: currentPinned,
                                                unpinnedHeaders: currentUnpinned,
                                                columnWidths: columnWidths,
                                                utilityColumnWidth: utilityColumnWidth,
                                                onAction: { action in
                                                    handleRowAction(action, record: record)
                                                }
                                            )
                                            .equatable()
                                        }
                                        if displayLimit < visibleRecords.count {
                                            HStack(spacing: 8) {
                                                Text("Showing \(min(displayLimit, visibleRecords.count).formatted()) of \(visibleRecords.count.formatted()) QSOs")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                Button("Load Next 1000") {
                                                    displayLimit += 1000
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                                Button("Show All") {
                                                    displayLimit = visibleRecords.count
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.small)
                                            }
                                            .padding(.vertical, 10)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                            .onAppear {
                                                if displayLimit < visibleRecords.count {
                                                    displayLimit += 500
                                                }
                                            }
                                        }
                                    } header: {
                                        headerRowView(pinnedHeaders: currentPinned, unpinnedHeaders: currentUnpinned)
                                            .background(Color(NSColor.textBackgroundColor))
                                    }
                                }
                            }
                        }
                        .coordinateSpace(name: "logTableScrollSpace")
                        .onPreferenceChange(LogTableScrollStateKey.self) { state in
                            if pinnedOffsetX != state.quantizedX {
                                pinnedOffsetX = state.quantizedX
                            }
                            if showBackToTop != state.isScrolledDown {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    showBackToTop = state.isScrolledDown
                                }
                            }
                        }
                        .background(Color(NSColor.textBackgroundColor))

                        // Floating Back to Top Button
                        if showBackToTop {
                            LogTableBackToTopButton {
                                scrollToTop(proxy: scrollProxy)
                            }
                            .padding(.trailing, 22)
                            .padding(.bottom, 16)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.85)),
                                    removal: .opacity.combined(with: .scale(scale: 0.9))
                                )
                            )
                            .zIndex(100)
                        }
                    }
            }
            
            Divider()
            
            HStack(spacing: 12) {
                Text(appState.loadedFileName.isEmpty ? "Ready" : "File: \(appState.loadedFileName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if appState.isDailyRankBackfillRunning {
                    HStack(spacing: 6) {
                        ProgressView(
                            value: Double(appState.dailyRankBackfillCompleted),
                            total: Double(max(1, appState.dailyRankBackfillTotal))
                        )
                        .frame(width: 70)
                        
                        Text(appState.dailyRankBackfillStatus)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        Button {
                            appState.stopEnrichment()
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "stop.circle.fill")
                                    .foregroundColor(.red)
                                Text("Stop")
                                    .font(.caption2.bold())
                                    .foregroundColor(.red)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Stop QRZ rank lookup and save current progress")
                    }
                } else if appState.isLoading || appState.isSyncingAPI || (appState.isEnriching && !appState.isDailyRankBackfillRunning) {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 12, height: 12)
                        if !appState.dailyRankBackfillStatus.isEmpty {
                            Text(appState.dailyRankBackfillStatus)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                } else if !appState.dailyRankBackfillStatus.isEmpty {
                    Text(appState.dailyRankBackfillStatus)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if !appState.selectedRecordIDs.isEmpty {
                    Text("Selected: \(appState.selectedRecordIDs.count)")
                        .font(.system(.caption, design: .monospaced))
                        .bold()
                        .foregroundColor(.blue)
                }
                
                HStack(spacing: 3) {
                    Image(systemName: "globe")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(appState.availableCountries.count.formatted()) DXCC")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.secondary)
                }
                
                if appState.filterCriteria.isActive || !appState.searchText.isEmpty {
                    Text("Filtered: \(visibleRecords.count.formatted()) / Total: \(appState.qsoRecords.count.formatted()) QSOs")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundColor(.orange)
                } else {
                    Text("\(appState.qsoRecords.count.formatted()) QSOs")
                        .font(.caption.monospacedDigit().bold())
                }

                Divider()
                    .frame(height: 12)

                Button {
                    scrollToTop(proxy: scrollProxy)
                } label: {
                    HStack(spacing: 3.5) {
                        Image(systemName: "arrow.up.to.line.compact")
                            .font(.system(size: 10, weight: .bold))
                        Text("Top")
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .help("Scroll back to the top of the table (⌥↑)")
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
        .sheet(isPresented: $isRoverControlSheetPresented) {
            RoverModeControlSheet()
                .environmentObject(appState)
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
            case .rankLegend:
                RankLegendCardView()
            }
        }
        .onAppear {
            localSearchText = appState.searchText
            restoreColumnVisibility()
            refreshHeaderCaches()
        }
        .onChange(of: appState.searchText) { _, newQuery in
            if localSearchText != newQuery {
                localSearchText = newQuery
            }
            displayLimit = 1000
        }
        .onChange(of: appState.filterCriteria.isActive) { _, _ in
            displayLimit = 1000
        }
        .onChange(of: appState.loadedFileURL) { _, _ in
            displayLimit = 1000
            refreshHeaderCaches()
        }
        .onChange(of: appState.tableHeaders) { _, _ in
            refreshHeaderCaches()
        }
        .onChange(of: appState.activeStationProfileID) { _, _ in
            restoreColumnVisibility()
            refreshHeaderCaches()
        }
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

    private func headerRowView(pinnedHeaders: [String], unpinnedHeaders: [String]) -> some View {
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
        let canSort = !isDerived || header == "AGING" || header == "APP_VIEW_AGING"
        let isSorted = canSort && appState.sortHeader == header
        let meta = headerMeta(for: header)
        let isRankHeader = header.hasPrefix("RANK_")
        
        return HeaderCellView(
            header: header,
            width: w,
            isDerived: isDerived,
            isSorted: isSorted,
            sortAscending: appState.sortAscending,
            meta: meta,
            alignment: tableAlignment(for: header),
            helpText: headerHelp(for: header),
            onSort: {
                if canSort {
                    appState.toggleSort(for: header)
                }
            },
            onAutoFit: {
                autoFitColumnWidth(header)
            },
            onDelete: {
                appState.deleteColumn(header: header)
            },
            onSortAscending: {
                appState.sortHeader = header
                appState.sortAscending = true
            },
            onSortDescending: {
                appState.sortHeader = header
                appState.sortAscending = false
            },
            onShowRankLegend: isRankHeader ? {
                activeTablePopover = .rankLegend
            } : nil,
            onResizeChange: { translation in
                if dragStartWidths[header] == nil {
                    dragStartWidths[header] = columnWidths[header] ?? defaultColumnWidth(for: header)
                }
                if let start = dragStartWidths[header] {
                    columnWidths[header] = max(40, start + translation)
                }
            },
            onResizeEnd: {
                dragStartWidths[header] = nil
            }
        )
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


    private func headerHelp(for header: String) -> String {
        switch header {
        case "AGING", "APP_VIEW_AGING":
            return "QSL Wait Time: Days elapsed since QSL request sent (or contact date if unsent). Highlights overdue contacts (>30d amber, >90d red). Click to sort."
        case "QSL_VIA", "QSL_SENT_VIA", "QSL_RCVD_VIA", "ROUTE":
            return "QSL Route: Direct (📮), Bureau (🏛️), Electronic (⚡), or Manager callsign."
        case "RANK_QSO":
            return "QRZ World QSO Rank: Standing in QRZ Leaderboard by total logged QSOs (Blue). Click to view Ranks Legend."
        case "RANK_BAND":
            return "QRZ Band Rank: Standing in QRZ Leaderboard for contacts on this amateur band (Orange). Click to view Ranks Legend."
        case "RANK_DXCC":
            return "QRZ DXCC Rank: Standing in QRZ Leaderboard by verified DXCC entities (Green). Click to view Ranks Legend."
        case "QSL":
            return "QSL Confirmation Status Matrix (L: LoTW, e: eQSL, Q: QRZ, C: Card).\nGreen ✓ = Confirmed, Amber ↑ = Sent / Pending, Red ✕ = Rejected / Invalid, Gray = Not Sent."
        case ConfirmationCreditColumn.countryBand:
            return "Shows whether confirming an unconfirmed QSO adds a new confirmed band for that country."
        case ConfirmationCreditColumn.grid:
            return "Shows whether confirming an unconfirmed QSO adds a new four-character Maidenhead grid."
        case "CONT":
            return "Continent: Click to sort; drag the right edge to resize."
        case "EMAIL":
            return "Email: Interactive 1-click copy & compose. Click to email contact; double-click to edit."
        case "QRZ_URL", "QRZ":
            return "QRZ Profile: Click to open QRZ.com profile; drag the right edge to resize."
        default:
            return "Click to sort by \(displayTitle(for: header)); drag the right edge to resize."
        }
    }

    private func startEditing(record: QSORecordModel, header: String, value: String) {
        editingCellID = record.id
        editingHeader = header
        editingText = value
    }

    private func handleRowAction(_ action: LogRowAction, record: QSORecordModel) {
        switch action {
        case .toggleSelection:
            appState.toggleRecordSelection(record.id)
        case .startEditing(let header, let value):
            startEditing(record: record, header: header, value: value)
        case .commitEditing(let header, let value):
            appState.updateCell(recordID: record.id, header: header, newValue: value)
            editingCellID = nil
            editingHeader = nil
        case .inspectCallsign:
            activeTablePopover = .callsign(record)
        case .inspectGrid(let ctx):
            activeTablePopover = .grid(ctx)
        case .showSentEmail(let ctx):
            activeTablePopover = .sentEmail(ctx)
        case .showRankLegend:
            activeTablePopover = .rankLegend
        case .showEQSLCard:
            selectedEQSLRecord = record
            showEQSLCardSheet = true
        case .toggleAgingSort:
            appState.toggleSort(for: "AGING")
        case .openEmail(let email):
            appState.openEmailComposer(for: record, email: email)
        case .openReminder:
            appState.openQSLReminderEmailComposer(for: record)
        case .openQSLCardComposer:
            appState.selectedQSLCardQSO = record
            appState.showQSLCardComposer = true
        case .openEmailQSLCard:
            appState.openQSLCardEmailComposer(for: record)
        case .openCongratulations:
            appState.openQRZRankCongratulationsEmailComposer(for: record)
        case .enrichCallsign:
            Task { await appState.fetchAndStoreQRZEmail(for: record["CALL"]) }
        case .delete:
            appState.deleteRecord(id: record.id)
        case .batchEnrich:
            appState.enrichSelectedRecords()
        case .batchReminders:
            appState.openBatchQSLReminderComposerForSelected()
        case .batchEmails:
            appState.openBatchEmailComposerForSelected()
        case .batchExport:
            appState.exportSelectedRecordsAs()
        case .batchDelete:
            appState.deleteSelectedRecords()
        case .markNewlyConfirmed:
            appState.markRecordAsNewlyConfirmed(id: record.id)
        case .unmarkNewlyConfirmed:
            appState.unmarkRecordAsNewlyConfirmed(id: record.id)
        case .trackRival(let call):
            appState.addTrackedRankCallsigns([call])
        case .untrackRival(let call):
            appState.removeTrackedRankCallsign(call)
        }
    }

    private func refreshHeaderCaches() {
        let displayed = displayedHeaders
        cachedDisplayedHeaders = displayed
        cachedPinnedHeaders = displayed.filter { isPinnedColumn($0) }
        cachedUnpinnedHeaders = displayed.filter { !isPinnedColumn($0) }
    }

    private func headerMeta(for header: String) -> LogTableHeaderMeta {
        switch header {
        case "QSL":
            return LogTableHeaderMeta(title: "QSL", icon: "checkmark.seal.fill")
        case "AGING", "APP_VIEW_AGING":
            return LogTableHeaderMeta(title: "Wait", icon: "hourglass")
        case "QSL_VIA", "QSL_SENT_VIA", "QSL_RCVD_VIA", "ROUTE":
            return LogTableHeaderMeta(title: "Route", icon: "envelope.and.arrow.triangle.branch.fill")
        case "QSO_DATE":
            return LogTableHeaderMeta(title: "Date", icon: "calendar")
        case "TIME_ON", "TIME":
            return LogTableHeaderMeta(title: "Time", icon: "clock")
        case "TIME_OFF":
            return LogTableHeaderMeta(title: "Time Off", icon: "clock.badge.checkmark")
        case "CALL":
            return LogTableHeaderMeta(title: "Callsign", icon: "antenna.radiowaves.left.and.right")
        case "FREQ":
            return LogTableHeaderMeta(title: "Frequency", icon: "waveform.path")
        case "FREQ_RX":
            return LogTableHeaderMeta(title: "RX Frequency", icon: "waveform.path")
        case "BAND":
            return LogTableHeaderMeta(title: "Band", icon: "wave.3.left")
        case "BAND_RX":
            return LogTableHeaderMeta(title: "RX Band", icon: "wave.3.left")
        case "MODE":
            return LogTableHeaderMeta(title: "Mode", icon: "bolt.fill")
        case "SUBMODE":
            return LogTableHeaderMeta(title: "Submode", icon: "bolt")
        case "RST_SENT":
            return LogTableHeaderMeta(title: "Sent", icon: "arrow.up.circle.fill")
        case "RST_RCVD":
            return LogTableHeaderMeta(title: "Rcvd", icon: "arrow.down.circle.fill")
        case "NAME":
            return LogTableHeaderMeta(title: "Name", icon: "person.fill")
        case "QTH":
            return LogTableHeaderMeta(title: "QTH", icon: "house.fill")
        case "COUNTRY":
            return LogTableHeaderMeta(title: "Country", icon: "globe.europe.africa.fill")
        case "CONT":
            return LogTableHeaderMeta(title: "Continent", icon: "map.fill")
        case "GRIDSQUARE", "GRID":
            return LogTableHeaderMeta(title: "Grid", icon: "square.grid.3x3.fill")
        case "DXCC":
            return LogTableHeaderMeta(title: "DXCC", icon: "flag.fill")
        case "CQZ":
            return LogTableHeaderMeta(title: "CQ Zone", icon: "circle.grid.cross.fill")
        case "ITUZ":
            return LogTableHeaderMeta(title: "ITU Zone", icon: "circle.grid.3x3.fill")
        case "STATE":
            return LogTableHeaderMeta(title: "State", icon: "mappin.circle.fill")
        case "EMAIL":
            return LogTableHeaderMeta(title: "Email", icon: "envelope.fill")
        case "QRZ_URL", "QRZ":
            return LogTableHeaderMeta(title: "QRZ", icon: "safari.fill")
        case "RANK_QSO":
            return LogTableHeaderMeta(title: "QSO Rank", icon: "trophy.fill")
        case "RANK_BAND":
            return LogTableHeaderMeta(title: "Band Rank", icon: "medal.fill")
        case "RANK_DXCC":
            return LogTableHeaderMeta(title: "DXCC Rank", icon: "rosette")
        case ConfirmationCreditColumn.countryBand:
            return LogTableHeaderMeta(title: "Band Credit", icon: "sparkles")
        case ConfirmationCreditColumn.grid:
            return LogTableHeaderMeta(title: "Grid Credit", icon: "square.grid.3x3.fill")
        case "APP_YAAM_LAST_EMAIL":
            return LogTableHeaderMeta(title: "Last Email", icon: "envelope.badge.fill")
        case "COMMENT":
            return LogTableHeaderMeta(title: "Comment", icon: "bubble.left.fill")
        case "PROP_MODE":
            return LogTableHeaderMeta(title: "Propagation", icon: "rays")
        case "SAT_NAME":
            return LogTableHeaderMeta(title: "Satellite", icon: "orbit")
        default:
            return LogTableHeaderMeta(title: header, icon: "tag.fill")
        }
    }

    private func defaultColumnWidth(for header: String) -> CGFloat {
        LogTableLayout.defaultColumnWidth(for: header)
    }

    private func isLeftAlignedColumn(_ header: String) -> Bool {
        LogTableLayout.isLeftAlignedColumn(header)
    }

    private func isRightAlignedColumn(_ header: String) -> Bool {
        LogTableLayout.isRightAlignedColumn(header)
    }

    private func isCompactCenteredColumn(_ header: String) -> Bool {
        LogTableLayout.isCompactCenteredColumn(header)
    }

    private func tableAlignment(for header: String) -> Alignment {
        LogTableLayout.tableAlignment(for: header)
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
        if !headers.contains("AGING") && (explicitlyShownColumns.contains("AGING") || !isHiddenByDefault("AGING")) {
            headers.append("AGING")
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

            let lhsPreferred = LogTableLayout.preferredColumnIndices[lhs] ?? Int.max
            let rhsPreferred = LogTableLayout.preferredColumnIndices[rhs] ?? Int.max
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
        if let preferredIndex = LogTableLayout.preferredColumnIndices[header] {
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
        guard LogTableLayout.preferredColumnIndices[header] == nil else { return false }
        guard !isLowValueTrailingColumn(header) else { return false }
        guard !TableColumnPolicy.isDatabaseOnly(header) else { return false }

        let sample = appState.qsoRecords.prefix(100)
        return !sample.contains(where: { !$0[header].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }
}

// MARK: - Fast Date Helpers
fileprivate enum LogTableDateHelpers {
    static let emailDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df
    }()
}

// MARK: - Equatable High-Performance Log Row View
fileprivate struct LogRowView: View, Equatable {
    let record: QSORecordModel
    let isSelected: Bool
    let isNewlyConfirmed: Bool
    let isTodayConfirmed: Bool
    let ordinal: Int?
    let sentEmail: EmailHistoryEntry?
    let opportunity: QSOConfirmationOpportunity?
    let pinnedOffsetX: CGFloat
    let isEditingThisRow: Bool
    let editingHeader: String?
    @Binding var editingText: String
    let isTrackedRival: Bool
    let hasBatchSelection: Bool
    let batchSelectionCount: Int
    let pinnedHeaders: [String]
    let unpinnedHeaders: [String]
    let columnWidths: [String: CGFloat]
    let utilityColumnWidth: CGFloat

    let onAction: (LogRowAction) -> Void

    @State private var isHovered: Bool = false

    static func == (lhs: LogRowView, rhs: LogRowView) -> Bool {
        lhs.record == rhs.record &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isNewlyConfirmed == rhs.isNewlyConfirmed &&
        lhs.isTodayConfirmed == rhs.isTodayConfirmed &&
        lhs.ordinal == rhs.ordinal &&
        lhs.pinnedOffsetX == rhs.pinnedOffsetX &&
        lhs.isEditingThisRow == rhs.isEditingThisRow &&
        lhs.editingHeader == rhs.editingHeader &&
        (!lhs.isEditingThisRow || lhs.editingText == rhs.editingText) &&
        lhs.isTrackedRival == rhs.isTrackedRival &&
        lhs.hasBatchSelection == rhs.hasBatchSelection &&
        lhs.batchSelectionCount == rhs.batchSelectionCount &&
        lhs.utilityColumnWidth == rhs.utilityColumnWidth &&
        lhs.sentEmail == rhs.sentEmail &&
        lhs.opportunity == rhs.opportunity &&
        lhs.pinnedHeaders == rhs.pinnedHeaders &&
        lhs.unpinnedHeaders == rhs.unpinnedHeaders &&
        lhs.columnWidths == rhs.columnWidths
    }

    private var accentBarColor: Color {
        if isSelected {
            return Color.accentColor
        } else if isNewlyConfirmed {
            return Color.pink
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
                return Color(red: 0.2, green: 0.85, blue: 0.35)
            } else if isEqsl {
                return Color(red: 0.25, green: 0.65, blue: 1.0)
            } else if isQrz {
                return Color(red: 0.95, green: 0.75, blue: 0.2)
            } else if isCard {
                return Color(red: 1.0, green: 0.5, blue: 0.2)
            } else {
                return Color.green
            }
        } else {
            return Color.orange.opacity(0.35)
        }
    }

    private var statusBgColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        } else if isHovered {
            return Color.white.opacity(0.04)
        } else if isNewlyConfirmed {
            return Color.pink.opacity(0.045)
        } else if record.isConfirmed {
            return Color.green.opacity(0.03)
        } else {
            return Color.clear
        }
    }

    var body: some View {
        let call = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        
        HStack(spacing: 0) {
            // Pinned Left Cells (Utility + Date + Time + Call + QSL)
            HStack(spacing: 0) {
                utilityRowCell
                ForEach(pinnedHeaders, id: \.self) { header in
                    rowCell(header: header, call: call)
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
            .overlay(alignment: .trailing) {
                if isHovered {
                    HoverQuickActionBar(
                        record: record,
                        call: call,
                        onAction: onAction,
                        onEdit: {
                            onAction(.startEditing(header: "CALL", value: record["CALL"]))
                        }
                    )
                    .padding(.trailing, 4)
                }
            }

            // Scrollable Trailing Cells
            HStack(spacing: 0) {
                ForEach(unpinnedHeaders, id: \.self) { header in
                    rowCell(header: header, call: call)
                }
            }
            .zIndex(1)
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .onTapGesture {
            onAction(.toggleSelection)
        }
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
            }
        }
        .contextMenu {
            rowContextMenuContent(call: call)
        }
    }

    private var utilityRowCell: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentBarColor)
                .frame(width: 3)
            
            HStack(spacing: 5) {
                if let ordinal {
                    Text(ordinal.formatted())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: 31, alignment: .trailing)
                        .help("Position by UTC date and time in the current filtered result")
                }

                Button(action: { onAction(.toggleSelection) }) {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .accentColor : .gray)
                }
                .buttonStyle(.plain)
                .help(isSelected ? "Deselect QSO" : "Select QSO")
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: utilityColumnWidth, height: 28)
        .background(statusBgColor)
        .border(Color.gray.opacity(0.15), width: 0.5)
    }

    private func isEditableColumn(_ header: String, isDerived: Bool) -> Bool {
        !isDerived &&
        header != "QRZ_URL" &&
        header != "QRZ" &&
        header != "QSL" &&
        header != "GRIDSQUARE" &&
        header != "GRID" &&
        header != "AGING" &&
        header != "APP_VIEW_AGING" &&
        !header.hasPrefix("RANK_")
    }

    @ViewBuilder
    private func rowCell(header: String, call: String) -> some View {
        let w = columnWidths[header] ?? LogTableLayout.defaultColumnWidth(for: header)
        let val = record[header]
        let isDerived = ConfirmationCreditColumn.isDerived(header)
        
        let cellBase = ZStack {
            if header == "AGING" || header == "APP_VIEW_AGING" {
                AgingCellView(record: record)
            } else if isDerived {
                confirmationCreditCell(
                    header: header,
                    opportunity: opportunity
                )
            } else if isEditingThisRow && editingHeader == header {
                TextField("", text: $editingText, onCommit: {
                    onAction(.commitEditing(header: header, value: editingText))
                })
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .multilineTextAlignment(LogTableLayout.isRightAlignedColumn(header) ? .trailing : (LogTableLayout.isLeftAlignedColumn(header) ? .leading : .center))
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
                                onAction(.inspectCallsign)
                            } label: {
                                Text(val)
                                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .help("Click to inspect callsign \(val) (bearing, distance, country, station stats)")
                            
                            if isNewlyConfirmed {
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
                                .help("Newly Confirmed QSO! Verified via \(record.confirmationSourcesSummary)\(record.latestConfirmationDate.map { " on " + LogTableDateHelpers.emailDateFormatter.string(from: $0) } ?? "")")
                            } else if let opp = opportunity {
                                if opp.addsCountryBandCredit {
                                    HStack(spacing: 2) {
                                        Image(systemName: "antenna.radiowaves.left.and.right")
                                            .font(.system(size: 6.5, weight: .bold))
                                        Text("NEW BAND")
                                            .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                                    }
                                    .padding(.horizontal, 3.5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.blue))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .fixedSize()
                                    .help("Confirming this contact earns a new DXCC band credit on \(opp.band) for \(opp.country)!")
                                } else if opp.addsGridCredit {
                                    HStack(spacing: 2) {
                                        Image(systemName: "square.grid.2x2.fill")
                                            .font(.system(size: 6.5, weight: .bold))
                                        Text("NEW GRID")
                                            .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                                    }
                                    .padding(.horizontal, 3.5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.teal))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .fixedSize()
                                    .help("Confirming this contact confirms new Maidenhead grid square: \(opp.grid ?? "")!")
                                }
                            }

                            if record.isConfirmed {
                                Button {
                                    onAction(.openQSLCardComposer)
                                } label: {
                                    Image(systemName: "photo.badge.checkmark")
                                        .font(.system(size: 8.5))
                                        .foregroundColor(.secondary)
                                        .padding(2.5)
                                        .background(Circle().fill(Color.secondary.opacity(0.16)))
                                }
                                .buttonStyle(.plain)
                                .help("Open QSL Card Composer for \(val) (Preview, Export PDF/PNG, or Email)")
                            }

                            if let sentEmail {
                                Button {
                                    onAction(.showSentEmail(SentEmailDetailContext(record: record, entry: sentEmail)))
                                } label: {
                                    Image(systemName: "envelope.fill")
                                        .font(.system(size: 8.5))
                                        .foregroundColor(.cyan)
                                        .padding(2.5)
                                        .background(Circle().fill(Color.cyan.opacity(0.18)))
                                }
                                .buttonStyle(.plain)
                                .help("Email sent to \(call) on \(LogTableDateHelpers.emailDateFormatter.string(from: sentEmail.date)): \"\(sentEmail.subject)\" (\(sentEmail.status)). Click to view.")
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
                        EmailCellView(
                            record: record,
                            email: val,
                            call: call,
                            sentEmail: sentEmail,
                            onOpenComposer: {
                                onAction(.openEmail(val))
                            },
                            onViewSentEmail: {
                                if let sentEmail {
                                    onAction(.showSentEmail(SentEmailDetailContext(record: record, entry: sentEmail)))
                                }
                            }
                        )
                    }
                    else if header == "QSL_VIA" || header == "QSL_SENT_VIA" || header == "QSL_RCVD_VIA" || header == "ROUTE" {
                        RouteCellView(value: val)
                    }
                    else if header == "APP_YAAM_LAST_EMAIL" && !val.isEmpty {
                        if let sentEmail {
                            Button {
                                onAction(.showSentEmail(SentEmailDetailContext(record: record, entry: sentEmail)))
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "envelope.fill")
                                        .font(.system(size: 8.5))
                                    Text(sentEmail.subject)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(LogTableDateHelpers.emailDateFormatter.string(from: sentEmail.date))
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
                        RankCellView(header: header, val: val, call: call)
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
                                    onAction(.inspectGrid(ctx))
                                }
                            )
                        }
                    }
                    else if header == "MODE" {
                        let submode = record["SUBMODE"].trimmingCharacters(in: .whitespacesAndNewlines)
                        let displayMode: String = {
                            if val.uppercased() == "DATA" && !submode.isEmpty {
                                return submode
                            }
                            return val.isEmpty ? "—" : val
                        }()
                        Text(displayMode)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .help(submode.isEmpty || submode == val ? "Mode: \(val)" : "Mode: \(val) / Submode: \(submode)")
                    }
                    else {
                        let isSecondary = ["NAME", "COUNTRY", "CONT", "QTH", "COMMENT"].contains(header)
                        Text(val)
                            .font(.system(size: 11, weight: .regular, design: isSecondary ? .default : .monospaced))
                            .foregroundColor(isSecondary ? Color(white: 0.72) : .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .multilineTextAlignment(LogTableLayout.isRightAlignedColumn(header) ? .trailing : (LogTableLayout.isLeftAlignedColumn(header) ? .leading : .center))
                            .frame(maxWidth: .infinity, alignment: LogTableLayout.isRightAlignedColumn(header) ? .trailing : (LogTableLayout.isLeftAlignedColumn(header) ? .leading : .center))
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 6)
        .frame(width: w, height: 28, alignment: LogTableLayout.tableAlignment(for: header))
        .background(statusBgColor)
        .border(Color.gray.opacity(0.15), width: 0.5)
        .contentShape(Rectangle())

        if header.hasPrefix("RANK_") {
            cellBase.onTapGesture {
                onAction(.showRankLegend)
            }
        } else if header == "AGING" || header == "APP_VIEW_AGING" {
            cellBase.onTapGesture {
                onAction(.toggleAgingSort)
            }
        } else if isEditableColumn(header, isDerived: isDerived) {
            cellBase.onTapGesture(count: 2) {
                onAction(.startEditing(header: header, value: val))
            }
        } else {
            cellBase
        }
    }

    @ViewBuilder
    private func rowContextMenuContent(call: String) -> some View {
        Button(isSelected ? "Deselect QSO" : "Select QSO") {
            onAction(.toggleSelection)
        }
        
        let emailVal = record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines)
        if !emailVal.isEmpty {
            Button {
                onAction(.openEmail(emailVal))
            } label: {
                Label("Send Email to \(emailVal)...", systemImage: "paperplane")
            }

            if !record.isConfirmed {
                Button {
                    onAction(.openReminder)
                } label: {
                    Label("Send QSL Reminder Email...", systemImage: "bell.badge")
                }
            }
        }
        
        if !call.isEmpty {
            Button {
                onAction(.inspectCallsign)
            } label: {
                Label("Inspect Callsign '\(call)'...", systemImage: "info.circle")
            }
            
            Button("Enrich QRZ Name & Email for '\(call)'") {
                onAction(.enrichCallsign)
            }
        }

        let gridVal = record["GRIDSQUARE"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? record["GRID"].trimmingCharacters(in: .whitespacesAndNewlines)
            : record["GRIDSQUARE"].trimmingCharacters(in: .whitespacesAndNewlines)
        if !gridVal.isEmpty {
            Button {
                onAction(.inspectGrid(GridInspectionContext(
                    record: record,
                    fullGrid: gridVal,
                    call: call,
                    country: record["COUNTRY"]
                )))
            } label: {
                Label("Inspect Grid Locator '\(gridVal.uppercased())' (World Map)...", systemImage: "map.fill")
            }
        }
        
        if hasBatchSelection {
            Divider()
            Button("🪄 Enrich Selected (\(batchSelectionCount) Rows)") {
                onAction(.batchEnrich)
            }
            Button("🔔 Batch QSL Reminders (\(batchSelectionCount) Rows)...") {
                onAction(.batchReminders)
            }
            Button("✉️ Batch Email Selected (\(batchSelectionCount) Rows)...") {
                onAction(.batchEmails)
            }
            Button("⬇️ Export Selected (\(batchSelectionCount) Rows) to ADIF...") {
                onAction(.batchExport)
            }
            Button(role: .destructive) {
                onAction(.batchDelete)
            } label: {
                Label("Delete Selected (\(batchSelectionCount) Rows)", systemImage: "trash.fill")
            }
        }

        if !call.isEmpty {
            Divider()
            Button("Email QSL Card") {
                onAction(.openEmailQSLCard)
            }
            .disabled(!record.isConfirmed || record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if ["RANK_QSO", "RANK_BAND", "RANK_DXCC"].contains(where: { !record[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                Button("Congratulate QRZ Achievement & Request Confirmation") {
                    onAction(.openCongratulations)
                }
                .disabled(record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    onAction(.showRankLegend)
                } label: {
                    Label("Show QRZ Ranks Legend...", systemImage: "questionmark.circle")
                }
            }

            Button("Generate QSL Card") {
                onAction(.openQSLCardComposer)
            }

            Button {
                onAction(.showEQSLCard)
            } label: {
                Label("View eQSL Graphic Card", systemImage: "photo.badge.checkmark")
            }

            if let sentEmail {
                Button {
                    onAction(.showSentEmail(SentEmailDetailContext(record: record, entry: sentEmail)))
                } label: {
                    Label("View Sent Email Details", systemImage: "envelope.badge")
                }
            }

            if isNewlyConfirmed {
                Button {
                    onAction(.unmarkNewlyConfirmed)
                } label: {
                    Label("Unmark as Newly Confirmed", systemImage: "sparkles")
                }
            } else if record.isConfirmed {
                Button {
                    onAction(.markNewlyConfirmed)
                } label: {
                    Label("Highlight as Newly Confirmed", systemImage: "sparkles")
                }
            }

            // MARK: Leaderboard Rivals
            let normalizedCall = call.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

            Divider()

            if isTrackedRival {
                Button {
                    onAction(.untrackRival(call))
                } label: {
                    Label("Remove '\(normalizedCall)' from Leaderboard Rivals", systemImage: "person.badge.minus")
                }
            } else {
                Button {
                    onAction(.trackRival(call))
                } label: {
                    Label("Add '\(normalizedCall)' to Leaderboard Rivals", systemImage: "person.badge.plus")
                }
            }
        }
        
        Divider()
        
        Button("Delete QSO") {
            onAction(.delete)
        }
    }
}

// MARK: - Log Table Formatting and QSL Helpers
fileprivate func formatDate(_ rawDate: String) -> String {
    let trimmed = rawDate.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count == 8, trimmed.allSatisfy({ $0.isNumber }) {
        let year = trimmed.prefix(4)
        let month = trimmed.dropFirst(4).prefix(2)
        let day = trimmed.suffix(2)
        return "\(year)-\(month)-\(day)"
    }
    return rawDate
}

fileprivate func formatTime(_ rawTime: String) -> String {
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
fileprivate func formattedFrequencyView(_ rawFreq: String) -> some View {
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

fileprivate enum QSLChannelState {
    case confirmed
    case sent
    case rejected
    case none
    
    var color: Color {
        switch self {
        case .confirmed: return Color(red: 0.25, green: 0.95, blue: 0.45) // Neon green
        case .sent: return Color(red: 1.0, green: 0.72, blue: 0.18) // Vibrant amber
        case .rejected: return Color(red: 1.0, green: 0.35, blue: 0.35) // Neon red
        case .none: return Color(red: 0.65, green: 0.65, blue: 0.68) // High-contrast silver/gray #A0A0A5
        }
    }
    
    var bgOpacity: Double {
        switch self {
        case .confirmed: return 0.22
        case .sent: return 0.18
        case .rejected: return 0.20
        case .none: return 0.08
        }
    }
}

fileprivate func qslChannelStatus(rcvd: String, sent: String, extraConfirmed: Bool = false) -> QSLChannelState {
    let r = rcvd.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let s = sent.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if ["Y", "V", "C"].contains(r) || extraConfirmed {
        return .confirmed
    } else if ["R", "I"].contains(r) || s == "I" {
        return .rejected
    } else if ["Y", "R", "Q"].contains(s) {
        return .sent
    } else {
        return .none
    }
}

fileprivate func qslBadge(label: String, state: QSLChannelState) -> some View {
    HStack(spacing: 0.5) {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(state.color)
        if state == .confirmed {
            Image(systemName: "checkmark")
                .font(.system(size: 6, weight: .black))
                .foregroundColor(state.color)
        } else if state == .sent {
            Image(systemName: "arrow.up")
                .font(.system(size: 5.5, weight: .black))
                .foregroundColor(state.color)
        } else if state == .rejected {
            Image(systemName: "xmark")
                .font(.system(size: 5.5, weight: .black))
                .foregroundColor(state.color)
        }
    }
    .frame(width: state == .none ? 15 : 19, height: 16)
    .background(
        RoundedRectangle(cornerRadius: 3.5)
            .fill(state.color.opacity(state.bgOpacity))
    )
    .overlay(
        RoundedRectangle(cornerRadius: 3.5)
            .stroke(
                state == .confirmed ? state.color.opacity(0.45) :
                (state == .sent ? state.color.opacity(0.55) :
                (state == .rejected ? state.color.opacity(0.6) : Color(white: 0.45).opacity(0.35))),
                lineWidth: 0.6
            )
    )
}

fileprivate func qslTooltip(
    record: QSORecordModel,
    lotw: QSLChannelState,
    eqsl: QSLChannelState,
    qrz: QSLChannelState,
    card: QSLChannelState
) -> String {
    func channelDetail(name: String, state: QSLChannelState, sentKey: String, rcvdKey: String) -> String {
        let stateStr: String = {
            switch state {
            case .confirmed: return "Confirmed"
            case .sent: return "Sent / Pending"
            case .rejected: return "Rejected / Invalid"
            case .none: return "Not Sent"
            }
        }()
        let sDate = record[sentKey].trimmingCharacters(in: .whitespacesAndNewlines)
        let rDate = record[rcvdKey].trimmingCharacters(in: .whitespacesAndNewlines)
        var dates: [String] = []
        if !sDate.isEmpty { dates.append("Sent: \(formatDate(sDate))") }
        if !rDate.isEmpty { dates.append("Rcvd: \(formatDate(rDate))") }
        let datesStr = dates.isEmpty ? "" : " (\(dates.joined(separator: ", ")))"
        return "\(name): \(stateStr)\(datesStr)"
    }
    return [
        channelDetail(name: "LoTW", state: lotw, sentKey: "LOTW_QSLSDATE", rcvdKey: "LOTW_QSLRDATE"),
        channelDetail(name: "eQSL", state: eqsl, sentKey: "EQSL_QSLSDATE", rcvdKey: "EQSL_QSLRDATE"),
        channelDetail(name: "QRZ", state: qrz, sentKey: "QRZLOG_QSLSDATE", rcvdKey: "QRZLOG_QSLRDATE"),
        channelDetail(name: "Card", state: card, sentKey: "QSLSDATE", rcvdKey: "QSLRDATE")
    ].joined(separator: "\n")
}

@ViewBuilder
fileprivate func qslMultiStatusGrid(for record: QSORecordModel) -> some View {
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

@ViewBuilder
fileprivate func confirmationCreditCell(
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

fileprivate func confirmationCreditBadge(
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
    case rankLegend

    var id: String {
        switch self {
        case .sentEmail(let c): return "email-\(c.id)"
        case .callsign(let r): return "call-\(r.id)"
        case .grid(let g): return "grid-\(g.id)"
        case .rankLegend: return "rank-legend"
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
            if isHovered != hovering {
                isHovered = hovering
            }
        }
        .help("Grid: \(fullGrid.uppercased()) • Click to view world map locator")
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

private struct LogTableScrollState: Equatable {
    var quantizedX: CGFloat = 0
    var isScrolledDown: Bool = false
}

private struct LogTableScrollStateKey: PreferenceKey {
    static var defaultValue = LogTableScrollState()
    static func reduce(value: inout LogTableScrollState, nextValue: () -> LogTableScrollState) {
        value = nextValue()
    }
}

fileprivate struct ScrollViewAccessor: NSViewRepresentable {
    let onFound: (NSScrollView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            if let scrollView = view?.enclosingScrollView {
                onFound(scrollView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Back to Top Floating Button
struct LogTableBackToTopButton: View {
    let action: () -> Void
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isHovered ? Color.accentColor : Color.secondary.opacity(0.20))
                        .frame(width: 20, height: 20)

                    Image(systemName: "arrow.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isHovered ? .white : .primary)
                        .offset(y: isHovered ? -1.0 : 0)
                }

                Text("Back to Top")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(isHovered ? Color.accentColor : .primary)

                Text("⌥↑")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(Color.secondary.opacity(isHovered ? 0.16 : 0.10))
                    )
            }
            .padding(.leading, 6)
            .padding(.trailing, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color(NSColor.windowBackgroundColor).opacity(colorScheme == .dark ? 0.82 : 0.92))
            )
            .background(
                .ultraThinMaterial,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isHovered ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.14),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.14),
                radius: isHovered ? 8 : 5,
                x: 0,
                y: isHovered ? 4 : 2
            )
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(NSUpArrowFunctionKey)!)), modifiers: [.option])
        .help("Scroll back to the top of the log (⌥↑)")
    }
}

// MARK: - Header Meta & Modern Header Cell Component
struct LogTableHeaderMeta {
    let title: String
    let icon: String
}

struct HeaderCellView: View {
    let header: String
    let width: CGFloat
    let isDerived: Bool
    let isSorted: Bool
    let sortAscending: Bool
    let meta: LogTableHeaderMeta
    let alignment: Alignment
    let helpText: String
    let onSort: () -> Void
    let onAutoFit: () -> Void
    let onDelete: () -> Void
    let onSortAscending: () -> Void
    let onSortDescending: () -> Void
    let onShowRankLegend: (() -> Void)?
    let onResizeChange: (CGFloat) -> Void
    let onResizeEnd: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 3.5) {
                Image(systemName: meta.icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(isSorted ? .yellow : Color(white: 0.75))

                Text(meta.title)
                    .font(.system(size: 10.5, weight: isSorted ? .bold : .semibold))
                    .foregroundColor(isSorted ? .white : Color(white: 0.88))
                    .lineLimit(1)
                
                if isSorted {
                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.yellow)
                }
                
                if !isDerived && isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(Color(white: 0.65))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 4)
            .frame(width: max(0, width - 6), height: 28, alignment: alignment)
            .contentShape(Rectangle())
            .onTapGesture {
                onSort()
            }
            
            Rectangle()
                .fill(Color(white: 0.22).opacity(0.6))
                .frame(width: 6, height: 28)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
                .onTapGesture(count: 2) {
                    onAutoFit()
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            onResizeChange(value.translation.width)
                        }
                        .onEnded { _ in
                            onResizeEnd()
                        }
                )
        }
        .frame(width: width, height: 28)
        .background(isSorted ? Color(white: 0.18) : Color(white: 0.12))
        .border(Color(white: 0.22).opacity(0.6), width: 0.5)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help(helpText)
        .contextMenu {
            if isDerived {
                Text(helpText)
            } else {
                Button("Sort Ascending") {
                    onSortAscending()
                }
                Button("Sort Descending") {
                    onSortDescending()
                }
                Divider()
                Button("Auto-Fit Width") {
                    onAutoFit()
                }
                if let onShowRankLegend {
                    Divider()
                    Button("Show QRZ Ranks Legend...") {
                        onShowRankLegend()
                    }
                }
                Divider()
                Button("Delete Column '\(header)'") {
                    onDelete()
                }
            }
        }
    }
}

// MARK: - Email Cell with 50px Smart Interactive Icon & 1-Click Copy
struct EmailCellView: View {
    let record: QSORecordModel
    let email: String
    let call: String
    let sentEmail: EmailHistoryEntry?
    let onOpenComposer: () -> Void
    let onViewSentEmail: () -> Void

    @State private var isHovered: Bool = false
    @State private var justCopied: Bool = false

    var body: some View {
        let clean = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if let sentEmail {
            Button(action: onViewSentEmail) {
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.cyan)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.cyan.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .help("Email sent to \(call) on \(appStateFormatted(sentEmail.date)): \"\(sentEmail.subject)\" (\(sentEmail.status)). Click to view.")
            .frame(maxWidth: .infinity, alignment: .center)
        } else if !clean.isEmpty {
            HStack(spacing: 2) {
                if isHovered {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(clean, forType: .string)
                        justCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            justCopied = false
                        }
                    } label: {
                        Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(justCopied ? .green : .secondary)
                            .frame(width: 17, height: 17)
                            .background(Circle().fill(Color.secondary.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .help(justCopied ? "Copied to clipboard!" : "Copy email '\(clean)'")

                    Button(action: onOpenComposer) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 17, height: 17)
                            .background(Circle().fill(Color.blue))
                    }
                    .buttonStyle(.plain)
                    .help("Compose email to \(call) (\(clean))")
                } else {
                    Button(action: onOpenComposer) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.blue.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onHover { hovering in
                if isHovered != hovering {
                    isHovered = hovering
                }
            }
            .help("Email: \(clean)\nClick to compose email to \(call). Double-click to edit.")
        } else {
            Text("—")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func appStateFormatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Aging / Elapsed Time / Wait Cell Component
struct AgingCellView: View {
    let record: QSORecordModel

    var body: some View {
        let isConfirmed = record.isConfirmed
        let isSent = record.isAnyQSLSent
        let waitingDays = record.qslWaitingDays ?? record.qsoAgeInDays

        if isConfirmed {
            HStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.green.opacity(0.85))
                if let days = waitingDays {
                    Text(displayAge(days))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.green.opacity(0.08)))
            .frame(maxWidth: .infinity, alignment: .center)
            .help(tooltipText(isConfirmed: true, isSent: isSent, days: waitingDays))
        } else if let days = waitingDays {
            let (bg, fg, icon) = style(for: days, isSent: isSent)
            HStack(spacing: 2) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 7.5, weight: .bold))
                }
                Text(displayAge(days))
                    .font(.system(size: 9.5, weight: days >= 30 ? .bold : .medium, design: .monospaced))
            }
            .padding(.horizontal, 4.5)
            .padding(.vertical, 2)
            .background(Capsule().fill(bg))
            .foregroundColor(fg)
            .frame(maxWidth: .infinity, alignment: .center)
            .help(tooltipText(isConfirmed: false, isSent: isSent, days: days))
        } else {
            Text("—")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func displayAge(_ days: Int) -> String {
        if days == 0 { return "0d" }
        if days < 365 { return "\(days)d" }
        let years = Double(days) / 365.25
        return String(format: "%.1fy", years)
    }

    private func style(for days: Int, isSent: Bool) -> (Color, Color, String?) {
        let defaultIcon = isSent ? "arrow.up" : nil
        if days < 30 {
            return (Color.secondary.opacity(0.12), Color.secondary, defaultIcon)
        } else if days < 90 {
            return (Color.orange.opacity(0.20), Color.orange, isSent ? "arrow.up" : "clock")
        } else {
            return (Color.red.opacity(0.22), Color.red, isSent ? "arrow.up.circle.fill" : "exclamationmark.circle.fill")
        }
    }

    private func tooltipText(isConfirmed: Bool, isSent: Bool, days: Int?) -> String {
        let d = days ?? 0
        let qsoDate = record["QSO_DATE"]
        if isConfirmed {
            return "Confirmed QSO (\(d) days ago)"
        } else if isSent {
            let sentDateStr = record.qslSentDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "sent"
            if d >= 90 {
                return "Overdue Pending (\(d) days waiting since QSL sent on \(sentDateStr)).\nQSO Date: \(qsoDate). Target: \(record["CALL"]). Right-click to send reminder."
            } else if d >= 30 {
                return "Waiting for QSL (\(d) days elapsed since QSL request sent on \(sentDateStr)).\nQSO Date: \(qsoDate)."
            } else {
                return "Recently sent QSL (\(d) days waiting since \(sentDateStr)). Awaiting confirmation from \(record["CALL"])."
            }
        } else {
            if d >= 90 {
                return "QSL not sent yet (\(d) days since QSO on \(qsoDate)).\nConsider sending via LoTW, eQSL, or Direct."
            } else if d >= 30 {
                return "Unconfirmed QSO (\(d) days since \(qsoDate)). No QSL sent yet."
            } else {
                return "Recent QSO (\(d) days ago). No QSL sent yet."
            }
        }
    }
}

// MARK: - Hover Quick Actions Bar Component
struct HoverQuickActionBar: View {
    let record: QSORecordModel
    let call: String
    let onAction: (LogRowAction) -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            let emailVal = record["EMAIL"].trimmingCharacters(in: .whitespacesAndNewlines)

            // Email or QSL Reminder
            Button {
                if !record.isConfirmed && !emailVal.isEmpty {
                    onAction(.openReminder)
                } else {
                    onAction(.openEmail(emailVal))
                }
            } label: {
                Image(systemName: !record.isConfirmed && !emailVal.isEmpty ? "bell.badge.fill" : "envelope.fill")
                    .font(.system(size: 8.5))
                    .foregroundColor(emailVal.isEmpty ? .secondary : .blue)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill((emailVal.isEmpty ? Color.secondary : Color.blue).opacity(0.18)))
            }
            .buttonStyle(.plain)
            .help(emailVal.isEmpty ? "Compose email to \(call)" : (!record.isConfirmed ? "Send QSL reminder to \(call)" : "Compose email to \(call)"))

            // QRZ Profile
            Button {
                let target = "https://www.qrz.com/db/\(call)"
                if let url = URL(string: target), !call.isEmpty {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "globe")
                    .font(.system(size: 8.5))
                    .foregroundColor(.cyan)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.cyan.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .help("Open \(call) on QRZ.com")

            // QSL Card Composer
            Button {
                onAction(.openQSLCardComposer)
            } label: {
                Image(systemName: "photo.badge.checkmark")
                    .font(.system(size: 8.5))
                    .foregroundColor(.orange)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.orange.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .help("Open QSL Card Composer for \(call)")

            // Edit QSO
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 8.5))
                    .foregroundColor(.teal)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.teal.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .help("Edit QSO with \(call)")

            // Delete QSO
            Button {
                onAction(.delete)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 8.5))
                    .foregroundColor(.red.opacity(0.85))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.red.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .help("Delete QSO with \(call)")
        }
        .padding(.horizontal, 3.5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.96))
                .shadow(color: Color.black.opacity(0.28), radius: 3, x: 0, y: 1)
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.18), lineWidth: 0.6)
        )
    }
}

// MARK: - QSL Route / Method Cell Component
struct RouteCellView: View {
    let value: String

    var body: some View {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if clean.isEmpty {
            Text("—")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.4))
                .frame(maxWidth: .infinity, alignment: .center)
        } else if clean == "B" || clean.contains("BURO") || clean.contains("BUREAU") {
            HStack(spacing: 2.5) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 7.5))
                Text("Bureau")
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .foregroundColor(.indigo)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Color.indigo.opacity(0.12)))
            .frame(maxWidth: .infinity, alignment: .center)
            .help("QSL via Bureau (Amateur Radio Bureau Service)")
        } else if clean == "D" || clean == "DIRECT" {
            HStack(spacing: 2.5) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 7.5))
                Text("Direct")
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .foregroundColor(.purple)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Color.purple.opacity(0.12)))
            .frame(maxWidth: .infinity, alignment: .center)
            .help("QSL via Direct Postal Mail")
        } else if clean == "E" || clean == "ELECTRONIC" {
            HStack(spacing: 2.5) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 7.5))
                Text("eQSL")
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .foregroundColor(.teal)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Color.teal.opacity(0.12)))
            .frame(maxWidth: .infinity, alignment: .center)
            .help("QSL via Electronic Service (LoTW / eQSL / QRZ)")
        } else {
            HStack(spacing: 2.5) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 7.5))
                Text(clean)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .center)
            .help("QSL Route / Manager: \(value)")
        }
    }
}

// MARK: - Rank Cell View Component
struct RankCellView: View {
    let header: String
    let val: String
    let call: String

    var body: some View {
        let (icon, color, label, desc) = rankInfo
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundColor(color)
            Text(val.hasPrefix("#") ? val : "#\(val)")
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(color.opacity(0.3), lineWidth: 0.8)
        )
        .frame(maxWidth: .infinity, alignment: .center)
        .help("\(label) for \(call): #\(val)\n\(desc)\nClick to view QRZ Ranks Legend.")
    }

    private var rankInfo: (icon: String, color: Color, label: String, desc: String) {
        switch header {
        case "RANK_QSO":
            return ("trophy.fill", .blue, "QRZ World QSO Rank", "Ranked by total logbook QSO volume (Blue)")
        case "RANK_BAND":
            return ("medal.fill", .orange, "QRZ Band Rank", "Ranked by contacts on this band (Orange)")
        case "RANK_DXCC":
            return ("rosette", .green, "QRZ DXCC Rank", "Ranked by confirmed DXCC entities (Green)")
        default:
            return ("chart.line.uptrend.xyaxis", .secondary, "Leaderboard Rank", "")
        }
    }
}

// MARK: - Rank Legend Popover View
struct RankLegendCardView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "rosette")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("QRZ Leaderboard Ranks Legend")
                        .font(.headline)
                    Text("Standing and color coding for enriched amateur stations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()

            VStack(alignment: .leading, spacing: 12) {
                legendItem(
                    icon: "trophy.fill",
                    color: .blue,
                    title: "QSO Rank (Blue)",
                    column: "RANK_QSO",
                    description: "Global or territorial leaderboard rank based on the all-time total number of confirmed QSOs logged by the station."
                )

                legendItem(
                    icon: "medal.fill",
                    color: .orange,
                    title: "Band Rank (Orange)",
                    column: "RANK_BAND",
                    description: "Leaderboard rank specifically for the amateur band on which the contact occurred (e.g. 20m, 40m, 15m)."
                )

                legendItem(
                    icon: "rosette",
                    color: .green,
                    title: "DXCC Rank (Green)",
                    column: "RANK_DXCC",
                    description: "Leaderboard standing based on the total number of unique DXCC entities (countries/territories) verified and credited to the station."
                )
            }

            Divider()

            HStack {
                Text("Note: Ranks are retrieved via QRZ XML API and cached locally.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 440)
    }

    private func legendItem(icon: String, color: Color, title: String, column: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(color)
                    Text("(\(column))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

