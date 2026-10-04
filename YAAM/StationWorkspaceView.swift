import AppKit
import Combine
import MapKit
import SwiftUI

// The four overview screens share one snapshot of the active station log.
private enum WorkspacePage: String, CaseIterable, Identifiable {
    case log = "Log"
    case needed = "Needed"
    case progress = "Progress"
    case confirmations = "Confirmations"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .log: "list.bullet.rectangle"
        case .needed: "scope"
        case .progress: "chart.bar.xaxis"
        case .confirmations: "checkmark.seal"
        }
    }
}

private enum StationMapKind: String, CaseIterable, Identifiable {
    case atlas = "Atlas"
    case globe = "Globe"
    var id: String { rawValue }
}

private enum WorkspaceQSL: String {
    case worked = "Worked"
    case confirmed = "Confirmed"
    case verified = "Verified"
    case notWorked = "Not worked"

    var color: Color {
        switch self {
        case .worked: .yellow
        case .confirmed: .green
        case .verified: .blue
        case .notWorked: .secondary
        }
    }

    static func status(_ record: QSORecordModel) -> Self {
        if record["CREDIT_GRANTED"].uppercased().contains("DXCC") { return .verified }
        return record.isConfirmed ? .confirmed : .worked
    }
}

private enum WorkspaceData {
    nonisolated static let utc: TimeZone = TimeZone(secondsFromGMT: 0)!
    nonisolated static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }()
    private static let utcDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc
        formatter.dateFormat = "dd MMM"
        return formatter
    }()
    private static let utcTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc
        formatter.dateFormat = "dd MMM HH:mm"
        return formatter
    }()

    private static let localDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "dd MMM"
        return formatter
    }()
    private static let localTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "dd MMM HH:mm"
        return formatter
    }()

    static func displayDate(_ record: QSORecordModel, useUTC: Bool, includeTime: Bool = true) -> String {
        guard let date = date(record) else { return "—" }
        if useUTC { return includeTime ? utcTimeFormatter.string(from: date) : utcDayFormatter.string(from: date) }
        return includeTime ? localTimeFormatter.string(from: date) : localDayFormatter.string(from: date)
    }

    nonisolated static func date(_ record: QSORecordModel) -> Date? {
        guard let day = record.qsoDate else { return nil }
        let raw = record["TIME_ON"].filter(\.isNumber)
        guard raw.count >= 4, let hour = Int(raw.prefix(2)), let minute = Int(raw.dropFirst(2).prefix(2)),
              hour < 24, minute < 60 else { return day }
        let seconds = raw.count >= 6 ? (Int(raw.dropFirst(4).prefix(2)) ?? 0) : 0
        return calendar.date(byAdding: .second, value: hour * 3600 + minute * 60 + seconds, to: day)
    }

    nonisolated static func entity(_ record: QSORecordModel) -> String {
        let country = record["COUNTRY"].trimmingCharacters(in: .whitespacesAndNewlines)
        return country.isEmpty ? DXCCDatabase.resolve(callsign: record["CALL"]).entityName : country
    }

    static func flag(_ record: QSORecordModel) -> String {
        DXCCDatabase.resolve(callsign: record["CALL"]).flagEmoji
    }

    private static let entityFlags: [String: String] = DXCCDatabase.allEntities.reduce(into: [:]) { flags, entity in
        flags[entity.entityName] = entity.flagEmoji
    }

    static func flag(forEntity name: String) -> String { entityFlags[name] ?? "🌐" }

    nonisolated static func mode(_ record: QSORecordModel) -> String {
        let submode = record["SUBMODE"]
        return submode.isEmpty ? record["MODE"] : submode
    }

    nonisolated static func modeGroup(_ record: QSORecordModel) -> String {
        let mode = mode(record).uppercased()
        if mode == "CW" { return "CW" }
        if ["SSB", "USB", "LSB", "AM", "FM"].contains(mode) { return "Phone" }
        return "Digital"
    }

    nonisolated static func coordinate(_ record: QSORecordModel) -> GeoCoordinate? {
        let grid = record["GRIDSQUARE"]
        if let center = MaidenheadGridEngine.boundingBox(for: grid)?.center { return center }
        if let latitude = Double(record["LAT"]), let longitude = Double(record["LON"]),
           (-90...90).contains(latitude), (-180...180).contains(longitude) {
            return GeoCoordinate(latitude: latitude, longitude: longitude)
        }
        return nil
    }

    static func bandColor(_ band: String) -> Color {
        switch band.lowercased() {
        case "40m": .orange
        case "20m": .green
        case "17m": .cyan
        case "15m": .purple
        default: .teal
        }
    }
}

private struct WorkspaceRecordSummary: Sendable {
    let priorWorkedIDs: Set<UUID>
    let entityGroups: [String: [QSORecordModel]]
    let availableBands: [String]
    let awaitingCount: Int
    let hourlyActivity: [Int]
    let recent24hCount: Int
    let progressVerified: Int
    let progressConfirmed: Int
    let progressWorked: Int
    let progressCoverage: [CountryBandCoverage]
    let progressBands: [WorkspaceProgressRow]
    let progressModes: [WorkspaceProgressRow]
    let progressContinents: [WorkspaceProgressRow]
    let awaitingRecords: [QSORecordModel]
    let toVerifyRecords: [QSORecordModel]
    let newConfirmationRecords: [QSORecordModel]

    nonisolated init?(records: [QSORecordModel], now: Date) {
        guard !Task.isCancelled else { return nil }
        let chronological = records.map { ($0, WorkspaceData.date($0) ?? .distantPast) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0.id.uuidString < rhs.0.id.uuidString }
                return lhs.1 < rhs.1
            }
        var seenCalls = Set<String>()
        var previous = Set<UUID>()
        var bins = Array(repeating: 0, count: 24)
        for (record, date) in chronological {
            if Task.isCancelled { return nil }
            let call = record["CALL"].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !call.isEmpty && !seenCalls.insert(call).inserted { previous.insert(record.id) }
            let hoursAgo = Int(now.timeIntervalSince(date) / 3600)
            if (0..<24).contains(hoursAgo) { bins[23 - hoursAgo] += 1 }
        }
        guard !Task.isCancelled else { return nil }
        priorWorkedIDs = previous
        let groups = Dictionary(grouping: records, by: WorkspaceData.entity)
        entityGroups = groups
        availableBands = Array(Set(records.map { $0["BAND"] }.filter { !$0.isEmpty })).sorted()
        awaitingCount = records.reduce(0) { $0 + ($1.isConfirmed ? 0 : 1) }
        hourlyActivity = bins
        recent24hCount = bins.reduce(0, +)
        progressVerified = groups.values.filter { $0.contains { $0["CREDIT_GRANTED"].uppercased().contains("DXCC") } }.count
        progressConfirmed = groups.values.filter { $0.contains(where: \.isConfirmed) }.count
        progressWorked = groups.count
        guard !Task.isCancelled else { return nil }
        progressCoverage = ConfirmationOpportunityIndex(records: records).countryBandCoverage
        progressBands = Self.progressRows(records, key: { $0["BAND"] })
        progressModes = Self.progressRows(records, key: WorkspaceData.modeGroup)
        progressContinents = Self.progressRows(records, key: { DXCCDatabase.resolve(callsign: $0["CALL"]).continent })
        awaitingRecords = records.filter { !$0.isConfirmed }
            .sorted { (WorkspaceData.date($0) ?? .distantPast) < (WorkspaceData.date($1) ?? .distantPast) }
        toVerifyRecords = records.filter { $0.isConfirmed && !$0["CREDIT_GRANTED"].uppercased().contains("DXCC") }
        newConfirmationRecords = records.filter {
            $0.isConfirmed && ($0.latestConfirmationDate ?? .distantPast) >= now.addingTimeInterval(-7 * 86400)
        }
    }

    private nonisolated static func progressRows(_ records: [QSORecordModel],
                                                  key: (QSORecordModel) -> String) -> [WorkspaceProgressRow] {
        Dictionary(grouping: records, by: key).map { name, group in
            WorkspaceProgressRow(key: name,
                                 total: Set(group.map(WorkspaceData.entity)).count,
                                 confirmed: Set(group.filter(\.isConfirmed).map(WorkspaceData.entity)).count)
        }.sorted { $0.key < $1.key }
    }
}

private struct WorkspaceProgressRow: Identifiable, Sendable {
    let key: String
    let total: Int
    let confirmed: Int
    var id: String { key }
}

private struct WorkspaceLogResult: Sendable {
    let rows: [QSORecordModel]
    let markers: [Globe3DMarker]
    let markerRecordIDs: [UUID: UUID]

    nonisolated init?(records: [QSORecordModel], cutoff: Date?, band: String, mode: String, search: String, now: Date) {
        guard !Task.isCancelled else { return nil }
        let term = search.localizedLowercase
        let candidates = records.filter { record in
            if Task.isCancelled { return false }
            if let cutoff, (WorkspaceData.date(record) ?? .distantPast) < cutoff { return false }
            if band != "All bands" && record["BAND"].lowercased() != band.lowercased() { return false }
            if mode != "All" && WorkspaceData.modeGroup(record) != mode { return false }
            if !term.isEmpty && !record["CALL"].localizedLowercase.contains(term) &&
                !WorkspaceData.entity(record).localizedLowercase.contains(term) { return false }
            return true
        }
        guard !Task.isCancelled else { return nil }
        let filteredRows = candidates.sorted { $0["QSO_DATE"] + $0["TIME_ON"] > $1["QSO_DATE"] + $1["TIME_ON"] }
        var markers: [Globe3DMarker] = []
        var ids: [UUID: UUID] = [:]
        for record in filteredRows {
            if Task.isCancelled { return nil }
            guard markers.count < 24 else { break }
            guard let coordinate = WorkspaceData.coordinate(record) else { continue }
            let call = record["CALL"]
            let marker = Globe3DMarker(
                callsign: call,
                flag: DXCCDatabase.resolve(callsign: call).flagEmoji,
                coordinate: coordinate,
                grid: record["GRIDSQUARE"],
                band: record["BAND"],
                mode: WorkspaceData.mode(record),
                qslConfirmed: record.isConfirmed,
                timestamp: WorkspaceData.date(record) ?? now
            )
            markers.append(marker)
            ids[marker.id] = record.id
        }
        rows = filteredRows
        self.markers = markers
        markerRecordIDs = ids
    }
}

private struct WorkspaceNeededEntity: Identifiable {
    let name: String
    let flag: String
    let continent: String
    let rank: Int?
    var id: String { name }

    // The reference design supplies this dated snapshot, not a live ranking feed.
    static let mostWantedSnapshot: [WorkspaceNeededEntity] = [
        .init(name: "Johnston Island", flag: "🇺🇸", continent: "OC", rank: 1),
        .init(name: "North Korea", flag: "🇰🇵", continent: "AS", rank: 2),
        .init(name: "Kure Island", flag: "🇺🇸", continent: "OC", rank: 3),
        .init(name: "San Felix Islands", flag: "🇨🇱", continent: "SA", rank: 4),
        .init(name: "Peter I Island", flag: "🇳🇴", continent: "AN", rank: 5),
        .init(name: "Midway Island", flag: "🇺🇸", continent: "OC", rank: 6),
        .init(name: "Scarborough Reef", flag: "🇨🇳", continent: "AS", rank: 7),
        .init(name: "Pratas Island", flag: "🇹🇼", continent: "AS", rank: 8),
        .init(name: "Aves Island", flag: "🇻🇪", continent: "NA", rank: 9)
    ]
}

private enum LogColumnWidth {
    static let time: CGFloat = 112
    static let call: CGFloat = 102
    static let band: CGFloat = 48
    static let mode: CGFloat = 56
    static let frequency: CGFloat = 80
    static let qsl: CGFloat = 95
    static let history: CGFloat = 112
    static let distance: CGFloat = 78
    static let bearing: CGFloat = 62
    static let grid: CGFloat = 68
    static let minimumTable: CGFloat = 1_210
}

struct StationWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @State private var page: WorkspacePage = .log
    @AppStorage("stationWorkspace.pureBlack") private var pureBlack = false
    @AppStorage("stationWorkspace.useUTC") private var useUTC = false
    @State private var records: [QSORecordModel] = []
    @State private var entityGroups: [String: [QSORecordModel]] = [:]
    @State private var logRows: [QSORecordModel] = []
    @State private var isPreparingLog = false
    @State private var isPreparingSummary = false
    @State private var priorWorkedIDs = Set<UUID>()
    @State private var mapMarkers: [Globe3DMarker] = []
    @State private var markerRecordIDs: [UUID: UUID] = [:]
    @State private var hourlyActivity = Array(repeating: 0, count: 24)
    @State private var recent24hCount = 0
    @State private var progressVerified = 0
    @State private var progressConfirmed = 0
    @State private var progressWorked = 0
    @State private var progressCoverage: [CountryBandCoverage] = []
    @State private var progressBands: [WorkspaceProgressRow] = []
    @State private var progressModes: [WorkspaceProgressRow] = []
    @State private var progressContinents: [WorkspaceProgressRow] = []
    @State private var awaitingRecords: [QSORecordModel] = []
    @State private var toVerifyRecords: [QSORecordModel] = []
    @State private var newConfirmationRecords: [QSORecordModel] = []
    // The map owns hover telemetry; it should not invalidate the entire log view on mouse movement.
    @State private var mapTelemetryState = MapTelemetryState()
    @State private var mapKind: StationMapKind = .atlas
    @State private var mapZoomCommand = 0
    @State private var showGreyline = false
    @State private var availableBands: [String] = []
    @State private var awaitingCount = 0
    @State private var selectedRecordID: UUID?
    @State private var selectedRouteRecord: QSORecordModel?
    @State private var timeFilter = "All"
    @State private var customMinutes = 30
    @State private var customValue = 30
    @State private var customUnit = "minutes"
    @State private var showingCustomPeriod = false
    @State private var bandFilter = "All bands"
    @State private var continentFilter = "All"
    @State private var modeFilter = "All"
    @State private var search = ""
    @State private var showEntryDetails = false
    @State private var showDupeAlert = false
    @State private var entryError: String?
    @State private var lookupTask: Task<Void, Never>?
    @State private var filterTask: Task<Void, Never>?
    @State private var enabledProviders = Set<QSLProvider>()
    @State private var defaultProvider: QSLProvider = .lotw
    @State private var confirmationTab = "Awaiting QSL"
    @State private var now = Date()
    @State private var reloadTask: Task<Void, Never>?
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var pageBackground: Color { pureBlack ? .black : Color(nsColor: .windowBackgroundColor) }
    private var panelBackground: Color { pureBlack ? .black : Color(nsColor: .controlBackgroundColor) }
    private var edge: Color { pureBlack ? Color(white: 0.23) : Color.primary.opacity(0.11) }
    private func refreshLogRows(debounce: Bool = false) {
        let cutoff: Date? = {
            switch timeFilter {
            case "15 m": return now.addingTimeInterval(-900)
            case "1 h": return now.addingTimeInterval(-3600)
            case "2 h": return now.addingTimeInterval(-7200)
            case "4 h": return now.addingTimeInterval(-14400)
            case "Today": return (useUTC ? WorkspaceData.calendar : Calendar.current).startOfDay(for: now)
            case "Custom": return now.addingTimeInterval(Double(-customMinutes * 60))
            default: return nil
            }
        }()
        filterTask?.cancel()
        let source = records
        let band = bandFilter
        let mode = modeFilter
        let term = search
        let currentNow = now
        isPreparingLog = true
        filterTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
            }
            let worker = Task.detached(priority: .userInitiated) {
                WorkspaceLogResult(records: source, cutoff: cutoff, band: band,
                                   mode: mode, search: term, now: currentNow)
            }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let result, !Task.isCancelled else { return }
            logRows = result.rows
            mapMarkers = result.markers
            markerRecordIDs = result.markerRecordIDs
            isPreparingLog = false
            if let selectedRecordID, !result.rows.contains(where: { $0.id == selectedRecordID }) {
                self.selectedRecordID = nil
                selectedRouteRecord = nil
            }
        }
    }

    private func reloadRecords() {
        let source = appState.qsoRecords
        records = source
        reloadTask?.cancel()
        isPreparingSummary = true
        let currentNow = now
        reloadTask = Task {
            let worker = Task.detached(priority: .userInitiated) {
                WorkspaceRecordSummary(records: source, now: currentNow)
            }
            let summary = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let summary, !Task.isCancelled else { return }
            priorWorkedIDs = summary.priorWorkedIDs
            entityGroups = summary.entityGroups
            availableBands = summary.availableBands
            awaitingCount = summary.awaitingCount
            hourlyActivity = summary.hourlyActivity
            recent24hCount = summary.recent24hCount
            progressVerified = summary.progressVerified
            progressConfirmed = summary.progressConfirmed
            progressWorked = summary.progressWorked
            progressCoverage = summary.progressCoverage
            progressBands = summary.progressBands
            progressModes = summary.progressModes
            progressContinents = summary.progressContinents
            awaitingRecords = summary.awaitingRecords
            toVerifyRecords = summary.toVerifyRecords
            newConfirmationRecords = summary.newConfirmationRecords
            isPreparingSummary = false
        }
        refreshLogRows()
    }

    private func refreshHourlyActivity() {
        var bins = Array(repeating: 0, count: 24)
        for record in records {
            guard let date = WorkspaceData.date(record) else { continue }
            let age = now.timeIntervalSince(date)
            guard age >= 0 else { continue }
            let hoursAgo = Int(age / 3600)
            if (0..<24).contains(hoursAgo) { bins[23 - hoursAgo] += 1 }
        }
        hourlyActivity = bins
        recent24hCount = bins.reduce(0, +)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 212)
            Rectangle().fill(edge).frame(width: 1)
            VStack(spacing: 0) {
                toolbar
                Rectangle().fill(edge).frame(height: 1)
                ZStack {
                    // Keep the MapKit view mounted when visiting other station pages.
                    logPage
                        .frame(height: page == .log ? nil : 0)
                        .clipped()
                        .opacity(page == .log ? 1 : 0)
                        .allowsHitTesting(page == .log)
                        .accessibilityHidden(page != .log)
                    if page != .log {
                        Group {
                            switch page {
                            case .log: EmptyView()
                            case .needed:
                                if isPreparingSummary { preparingPage } else { neededPage }
                            case .progress:
                                if isPreparingSummary { preparingPage } else { progressPage }
                            case .confirmations:
                                if isPreparingSummary { preparingPage } else { confirmationsPage }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                legend
            }
        }
        .background(pageBackground)
        .preferredColorScheme(pureBlack ? .dark : .light)
        .onAppear {
            reloadRecords()
            if let saved = UserDefaults.standard.string(forKey: "stationWorkspace.enabledProviders") {
                enabledProviders = Set(saved.split(separator: ",").compactMap { QSLProvider(rawValue: String($0)) })
            } else {
                let credentials = appState.qslServiceCredentials(for: Set(QSLProvider.allCases))
                var configured = Set<QSLProvider>()
                if !credentials.lotwPassword.isEmpty { configured.insert(.lotw) }
                if !credentials.qrzAPIKey.isEmpty { configured.insert(.qrz) }
                if !credentials.eqslPassword.isEmpty { configured.insert(.eqsl) }
                if !credentials.clubLogEmail.isEmpty &&
                    (!credentials.clubLogPassword.isEmpty || !credentials.clubLogAPIKey.isEmpty) { configured.insert(.clubLog) }
                enabledProviders = configured
                if let first = QSLProvider.allCases.first(where: { configured.contains($0) }) { defaultProvider = first }
            }
            if appState.quickLogDraft.frequencyMHz.isEmpty,
               let snapshot = appState.rigControlClient.snapshot ?? appState.icomNetworkRadio.snapshot.map({ RigSnapshot(frequencyHz: $0.frequencyHz, mode: $0.mode, passbandHz: nil, updatedAt: $0.updatedAt) }) {
                appState.quickLogDraft.applyFrequency(snapshot.frequencyMHz)
                if !snapshot.mode.isEmpty { appState.quickLogDraft.mode = snapshot.mode }
            }
        }
        .onChange(of: appState.qsoRecordsRevision) { _, _ in reloadRecords() }
        .onChange(of: useUTC) { _, _ in
            if timeFilter == "Today" { refreshLogRows() }
        }
        .onChange(of: timeFilter) { _, _ in refreshLogRows() }
        .onChange(of: customMinutes) { _, _ in refreshLogRows() }
        .onChange(of: bandFilter) { _, _ in refreshLogRows() }
        .onChange(of: modeFilter) { _, _ in refreshLogRows() }
        .onChange(of: search) { _, _ in refreshLogRows(debounce: true) }
        .onChange(of: enabledProviders) { _, selection in
            UserDefaults.standard.set(selection.map(\.rawValue).sorted().joined(separator: ","), forKey: "stationWorkspace.enabledProviders")
        }
        .onReceive(clock) { date in
            let hourChanged = WorkspaceData.calendar.component(.hour, from: date) != WorkspaceData.calendar.component(.hour, from: now)
            guard hourChanged || (page == .log && timeFilter != "All") else { return }
            now = date
            if hourChanged { refreshHourlyActivity() }
            if page == .log && timeFilter != "All" { refreshLogRows() }
        }
        .alert("Possible duplicate QSO", isPresented: $showDupeAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Log anyway") { saveEntry() }
        } message: {
            Text("This callsign is already in your log on the same band and mode.")
        }
        .onDisappear {
            reloadTask?.cancel()
            filterTask?.cancel()
        }
    }

    private var preparingPage: some View {
        ProgressView("Preparing station data…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 46, height: 46)
                    .shadow(color: .accentColor.opacity(0.28), radius: 10, y: 4)
                    .accessibilityLabel("YAAM application icon")
                VStack(alignment: .leading, spacing: 2) {
                    Text("STATION")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.5)
                    Text("Signal desk")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 15)
            .padding(.bottom, 16)
            ForEach(WorkspacePage.allCases) { destination in
                Button {
                    page = destination
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: destination.symbol).frame(width: 17)
                        Text(destination.rawValue).lineLimit(1).minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                        if destination == .confirmations && awaitingCount > 0 {
                            Text("\(awaitingCount)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 13, weight: page == destination ? .semibold : .regular))
                    .padding(.horizontal, 10).frame(height: 31)
                    .background(page == destination ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    .foregroundStyle(page == destination ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 9)
            }
            Spacer()
            Button {
                appState.selectedTab = 0
            } label: {
                Label("Open Log Table", systemImage: "tablecells")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 15)
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.currentStationCallsign).font(.system(size: 12, weight: .bold))
                Text("\(appState.effectiveStationGrid) · \(records.count.formatted()) QSOs")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .frame(maxHeight: .infinity)
        .background(panelBackground)
    }

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.rawValue).font(.system(size: 17, weight: .semibold))
                    Text(page == .log ? "\(logRows.count.formatted()) contacts in view" : "\(records.count.formatted()) station contacts")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Label(appState.effectiveStationGrid, systemImage: "location.north.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).fixedSize()
                Picker("Time zone", selection: $useUTC) {
                    Text("Local").tag(false)
                    Text("UTC").tag(true)
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 118)
                .help(useUTC ? "Show times in the Mac's local time zone" : "Show times in UTC")
                Button { pureBlack.toggle() } label: { Image(systemName: pureBlack ? "sun.max" : "moon.stars") }
                    .help(pureBlack ? "Light appearance" : "Pure black appearance")
            }
            .padding(.horizontal, 16).frame(height: 49)

            if page == .log || page == .needed {
                Rectangle().fill(edge).frame(height: 1)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        if page == .log {
                            Text("Period").font(.caption.bold()).fixedSize()
                            Picker("Period", selection: $timeFilter) {
                                ForEach(["15 m", "1 h", "2 h", "4 h", "Today", "All", "Custom"], id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden().pickerStyle(.segmented).frame(width: 405)
                            Button { showingCustomPeriod = true } label: { Image(systemName: "plus") }
                                .popover(isPresented: $showingCustomPeriod) { customPeriodPopover }
                        }
                        Text("Band").font(.caption.bold()).fixedSize()
                        Picker("Band", selection: $bandFilter) {
                            Text("All bands").tag("All bands")
                            ForEach(availableBands, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().frame(width: 115)
                        if page == .log {
                            Text("Mode").font(.caption.bold()).fixedSize()
                            Picker("Mode", selection: $modeFilter) {
                                ForEach(["All", "CW", "Phone", "Digital"], id: \.self) { Text($0).tag($0) }
                            }.labelsHidden().pickerStyle(.segmented).frame(width: 220)
                        }
                        TextField("Callsign or entity", text: $search)
                            .textFieldStyle(.roundedBorder).frame(width: 185)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 16)
                }
                .frame(height: 43)
            }
        }
    }

    private var customPeriodPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom period").font(.headline)
            Picker("Unit", selection: $customUnit) {
                ForEach(["minutes", "hours", "days"], id: \.self) { Text($0.capitalized).tag($0) }
            }
            Stepper("Last \(customValue) \(customUnit)", value: $customValue,
                    in: customUnit == "minutes" ? 5...720 : customUnit == "hours" ? 1...168 : 1...30)
            Button("Apply") {
                customMinutes = customValue * (customUnit == "days" ? 1440 : customUnit == "hours" ? 60 : 1)
                timeFilter = "Custom"
                showingCustomPeriod = false
            }
        }.padding(16).frame(width: 240)
    }

    private var logPage: some View {
        VStack(spacing: 0) {
            entryBar
            Rectangle().fill(edge).frame(height: 1)
            GeometryReader { geometry in
                if geometry.size.width >= 970 {
                    HStack(spacing: 12) {
                        mapViewport
                        activityRail.frame(width: min(340, geometry.size.width * 0.29))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                } else {
                    VStack(spacing: 8) {
                        mapViewport.frame(height: 245)
                        activityRail.frame(height: 125)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
            .frame(height: 390)
            Rectangle().fill(edge).frame(height: 1)
            HStack {
                Text("CONTACTS").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text("\(useUTC ? "UTC" : "Local") · map uses logged grids and coordinates")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 18).frame(height: 32)
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: geometry.size.width < LogColumnWidth.minimumTable) {
                    VStack(spacing: 0) {
                        logTableHeader
                        Rectangle().fill(edge).frame(height: 1)
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(logRows) { record in
                                    Button { selectRecord(record) } label: { logRow(record) }
                                        .buttonStyle(.plain)
                                    Rectangle().fill(edge.opacity(0.55)).frame(height: 1)
                                }
                                if logRows.isEmpty {
                                    if isPreparingLog {
                                        ProgressView("Loading contacts…").padding(24)
                                    } else {
                                        emptyState("No QSOs match these filters")
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: max(geometry.size.width, LogColumnWidth.minimumTable),
                           height: geometry.size.height)
                }
            }
        }
    }

    private func selectRecord(_ record: QSORecordModel) {
        if selectedRecordID == record.id {
            selectedRecordID = nil
            selectedRouteRecord = nil
        } else {
            selectedRecordID = record.id
            selectedRouteRecord = record
        }
    }

    private var mapViewport: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if mapKind == .atlas {
                    GridTrackerMapView(
                        homeCoordinate: appState.effectiveStationCoordinate,
                        homeCallsign: appState.currentStationCallsign,
                        homeGrid: appState.effectiveStationGrid,
                        markers: mapMarkers,
                        logSummaries: [:],
                        mapType: .standard,
                        showDayNightShadow: showGreyline,
                        showGridLines: false,
                        showTrafficArcs: true,
                        showWholeWorld: true,
                        zoomCommand: mapZoomCommand,
                        telemetryState: mapTelemetryState,
                        onSelectMarker: { marker in
                            guard let id = markerRecordIDs[marker.id],
                                  let record = logRows.first(where: { $0.id == id }) else { return }
                            selectRecord(record)
                        },
                        onSelectGrid: { _ in }
                    )
                } else {
                    Globe3DMapView(
                        homeCoordinate: appState.effectiveStationCoordinate,
                        markers: mapMarkers,
                        mapType: .hybrid,
                        showGreatCircleArcs: true,
                        showDayNightShadow: showGreyline,
                        showCountryLabels: true,
                        zoomCommand: mapZoomCommand,
                        telemetryState: mapTelemetryState,
                        onSelectMarker: { marker in
                            guard let id = markerRecordIDs[marker.id],
                                  let record = logRows.first(where: { $0.id == id }) else { return }
                            selectRecord(record)
                        }
                    )
                }
            }

            HStack(alignment: .top, spacing: 8) {
                HStack(spacing: 8) {
                    Picker("Map", selection: $mapKind) {
                        ForEach(StationMapKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 166)
                    Toggle(isOn: $showGreyline) {
                        Label("Grayline", systemImage: "moon.stars")
                            .labelStyle(.titleAndIcon)
                    }
                    .toggleStyle(.button)
                    .tint(.indigo)
                }
                .controlSize(.regular)
                .padding(7)
                .background(panelBackground.opacity(0.97), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(edge, lineWidth: 1))
                .shadow(color: .black.opacity(0.23), radius: 8, y: 3)
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 0) {
                        Button { mapZoomCommand += 1 } label: {
                            Image(systemName: "plus.magnifyingglass").frame(width: 34, height: 28)
                        }
                        .help("Zoom in")
                        Rectangle().fill(edge).frame(width: 1, height: 20)
                        Button { mapZoomCommand -= 1 } label: {
                            Image(systemName: "minus.magnifyingglass").frame(width: 34, height: 28)
                        }
                        .help("Zoom out")
                    }
                    .buttonStyle(.plain)
                    .background(panelBackground.opacity(0.97), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(edge, lineWidth: 1))
                    .shadow(color: .black.opacity(0.23), radius: 8, y: 3)
                    Text("\(mapMarkers.count) recent paths")
                        .font(.caption2.bold()).lineLimit(1)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(panelBackground.opacity(0.97), in: Capsule())
                }
            }
            .padding(10)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(edge, lineWidth: 1))
        .accessibilityLabel("Interactive QSO map, \(mapMarkers.count) recent paths")
    }

    private var activityRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 7) {
                    Image(systemName: "waveform.path")
                        .foregroundStyle(.cyan)
                    Text("SIGNAL CHRONICLE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.3)
                    Spacer(minLength: 0)
                    Text(useUTC ? "UTC" : "LOCAL").font(.caption2.bold()).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(recent24hCount.formatted())
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                    Text("QSOs / 24 h").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("\(awaitingCount.formatted()) awaiting QSL") { page = .confirmations }
                        .buttonStyle(.plain)
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                let maxHour = max(1, hourlyActivity.max() ?? 1)
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(hourlyActivity.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient(colors: [.cyan.opacity(0.55), .blue.opacity(0.88)],
                                                 startPoint: .bottom, endPoint: .top))
                            .frame(maxWidth: .infinity)
                            .frame(height: 4 + CGFloat(hourlyActivity[index]) / CGFloat(maxHour) * 42)
                            .help("\(hourlyActivity[index]) QSOs · \(23 - index) hours ago")
                    }
                }
                .frame(height: 48, alignment: .bottom)
                HStack {
                    Text("24 h ago")
                    Spacer()
                    Text("Now")
                }.font(.system(size: 9)).foregroundStyle(.secondary)

                ForEach(Array(logRows.prefix(4))) { record in
                    Button { selectRecord(record) } label: {
                        HStack(spacing: 9) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(WorkspaceData.bandColor(record["BAND"]))
                                .frame(width: 3, height: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(WorkspaceData.flag(record)).font(.system(size: 13))
                                    Text(record["CALL"]).font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    Spacer(minLength: 2)
                                    Text(WorkspaceData.displayDate(record, useUTC: useUTC)).font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                                Text("\(WorkspaceData.entity(record)) · \(record["BAND"]) \(WorkspaceData.mode(record))")
                                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Circle().fill(WorkspaceQSL.status(record).color)
                                .frame(width: 6, height: 6)
                                .help(WorkspaceQSL.status(record).rawValue)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(selectedRecordID == record.id ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.035),
                                    in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
                if logRows.isEmpty {
                    Text("Your recent contacts will appear here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let selectedRouteRecord, let target = WorkspaceData.coordinate(selectedRouteRecord) {
                    let home = appState.effectiveStationCoordinate
                    HStack(spacing: 9) {
                        Image(systemName: "location.north.line.fill").foregroundStyle(.cyan)
                        Text("\(Int(GeodesicMath.distanceKm(from: home, to: target))) km")
                        Text("·")
                        Text("\(Int(GeodesicMath.initialBearing(from: home, to: target)))° short path")
                    }
                    .font(.caption2.bold())
                    .padding(.top, 2)
                    .transition(.opacity)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [Color.cyan.opacity(pureBlack ? 0.12 : 0.09),
                                              panelBackground, Color.blue.opacity(pureBlack ? 0.08 : 0.04)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.22), lineWidth: 1))
    }

    private var entryBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .bottom, spacing: 10) {
                entryField("Callsign", text: $appState.quickLogDraft.callsign, width: 176)
                    .onChange(of: appState.quickLogDraft.callsign) { _, value in
                        appState.refreshQuickLogAssessment()
                        lookupTask?.cancel()
                        let call = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                        if appState.isValidOperatorCallsign(call) {
                            lookupTask = Task {
                                try? await Task.sleep(for: .milliseconds(350))
                                guard !Task.isCancelled else { return }
                                await appState.lookupQuickLogCallsign(call)
                            }
                        }
                    }
                entryField("RST sent", text: $appState.quickLogDraft.rstSent, width: 68)
                entryField("RST rcvd", text: $appState.quickLogDraft.rstReceived, width: 68)
                VStack(alignment: .leading, spacing: 4) {
                    Text("CONTACT").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Text(appState.quickLogDraft.frequencyMHz.isEmpty
                         ? "\(appState.quickLogDraft.band) · \(appState.quickLogDraft.mode) · Set frequency"
                         : "\(appState.quickLogDraft.band) · \(appState.quickLogDraft.mode) · \(appState.quickLogDraft.frequencyMHz) MHz")
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }
                Button("Edit") { showEntryDetails.toggle() }
                Spacer(minLength: 0)
                Button("Log QSO") {
                    appState.refreshQuickLogAssessment()
                    if appState.quickLogAssessment.hasRecentDuplicate || appState.quickLogAssessment.contestDuplicate { showDupeAlert = true }
                    else { saveEntry() }
                }.buttonStyle(.borderedProminent)
            }
            if showEntryDetails {
                HStack(spacing: 10) {
                    entryField("MHz", text: $appState.quickLogDraft.frequencyMHz, width: 100)
                        .onChange(of: appState.quickLogDraft.frequencyMHz) { _, value in appState.quickLogDraft.applyFrequency(value) }
                    Picker("Band", selection: $appState.quickLogDraft.band) {
                        ForEach(AmateurBandSettings.allBands.map(\.id), id: \.self) { Text($0).tag($0) }
                    }.frame(width: 125)
                    Picker("Mode", selection: $appState.quickLogDraft.mode) {
                        ForEach(["CW", "SSB", "FT8", "FT4", "RTTY", "FM", "AM"], id: \.self) { Text($0).tag($0) }
                    }.frame(width: 135)
                    DatePicker(useUTC ? "UTC" : "Local", selection: $appState.quickLogDraft.startedAt,
                               displayedComponents: [.date, .hourAndMinute])
                        .environment(\.timeZone, useUTC ? WorkspaceData.utc : .current)
                        .frame(maxWidth: 260)
                }
            }
            let typed = appState.quickLogDraft.normalizedCallsign
            if !typed.isEmpty {
                let entity = DXCCDatabase.resolve(callsign: typed)
                let assessment = appState.quickLogAssessment
                Text("\(entity.flagEmoji) \(entity.entityName) · \(entity.continent)  •  \(assessment.totalWorked == 0 ? "New entity" : assessment.confirmed > 0 ? "Confirmed" : "Worked · awaiting QSL")")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Enter a callsign to see its entity and logging history.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let entryError { Text(entryError).font(.caption).foregroundStyle(.red) }
        }.padding(.horizontal, 18).padding(.vertical, 12)
    }

    private func entryField(_ label: String, text: Binding<String>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            TextField(label, text: text).textFieldStyle(.roundedBorder)
        }.frame(width: width)
    }

    private func saveEntry() {
        do {
            _ = try appState.saveQuickLog()
            entryError = nil
            reloadRecords()
        } catch { entryError = error.localizedDescription }
    }

    private var logTableHeader: some View {
        HStack(spacing: 10) {
            Text("\(useUTC ? "UTC" : "LOCAL") TIME").frame(width: LogColumnWidth.time, alignment: .leading)
            Text("CALLSIGN").frame(width: LogColumnWidth.call, alignment: .leading)
            Text("COUNTRY / ENTITY").frame(maxWidth: .infinity, alignment: .leading)
            Text("BAND").frame(width: LogColumnWidth.band, alignment: .leading)
            Text("MODE").frame(width: LogColumnWidth.mode, alignment: .leading)
            Text("FREQ MHz").frame(width: LogColumnWidth.frequency, alignment: .trailing)
            Text("QSL").frame(width: LogColumnWidth.qsl)
            Text("CALL HISTORY").frame(width: LogColumnWidth.history)
            Text("DIST km").frame(width: LogColumnWidth.distance, alignment: .trailing)
            Text("SHORT °").frame(width: LogColumnWidth.bearing, alignment: .trailing)
            Text("LONG °").frame(width: LogColumnWidth.bearing, alignment: .trailing)
            Text("GRID").frame(width: LogColumnWidth.grid, alignment: .leading)
        }
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 18)
        .frame(height: 30)
        .background(panelBackground)
    }

    private func logRow(_ record: QSORecordModel) -> some View {
        let target = WorkspaceData.coordinate(record)
        let home = appState.effectiveStationCoordinate
        let workedBefore = priorWorkedIDs.contains(record.id)
        return HStack(spacing: 10) {
            Text(WorkspaceData.displayDate(record, useUTC: useUTC))
                .frame(width: LogColumnWidth.time, alignment: .leading).foregroundStyle(.secondary)
            Text(record["CALL"]).fontWeight(.semibold)
                .frame(width: LogColumnWidth.call, alignment: .leading)
            HStack(spacing: 6) {
                Text(WorkspaceData.flag(record)).font(.system(size: 15))
                Text(WorkspaceData.entity(record)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Circle().fill(WorkspaceData.bandColor(record["BAND"])).frame(width: 6, height: 6)
                Text(record["BAND"])
            }.frame(width: LogColumnWidth.band, alignment: .leading)
            Text(WorkspaceData.mode(record)).frame(width: LogColumnWidth.mode, alignment: .leading)
            Text(record["FREQ"]).frame(width: LogColumnWidth.frequency, alignment: .trailing)
            statusBadge(WorkspaceQSL.status(record)).frame(width: LogColumnWidth.qsl)
            Text(workedBefore ? "Worked before" : "First contact")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(workedBefore ? Color.secondary : Color.teal)
                .frame(width: LogColumnWidth.history)
            Text(target.map { String(Int(GeodesicMath.distanceKm(from: home, to: $0))) } ?? "—")
                .frame(width: LogColumnWidth.distance, alignment: .trailing)
            Text(target.map { String(Int(GeodesicMath.initialBearing(from: home, to: $0))) + "°" } ?? "—")
                .frame(width: LogColumnWidth.bearing, alignment: .trailing)
            Text(target.map { String(Int(GeodesicMath.longPathBearing(from: home, to: $0))) + "°" } ?? "—")
                .frame(width: LogColumnWidth.bearing, alignment: .trailing)
            Text(record["GRIDSQUARE"].isEmpty ? "—" : record["GRIDSQUARE"])
                .frame(width: LogColumnWidth.grid, alignment: .leading)
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .padding(.horizontal, 18)
        .frame(height: 34)
        .background(selectedRecordID == record.id ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private var neededPage: some View {
        let groups = bandFilter == "All bands" ? entityGroups :
            Dictionary(grouping: records.filter { $0["BAND"].lowercased() == bandFilter.lowercased() },
                       by: WorkspaceData.entity)
        let quickWinsAll = groups.filter { !$0.key.isEmpty && !$0.value.contains(where: \.isConfirmed) &&
            (search.isEmpty || $0.key.localizedCaseInsensitiveContains(search)) }
            .sorted { ($0.value.compactMap(WorkspaceData.date).min() ?? .distantFuture) < ($1.value.compactMap(WorkspaceData.date).min() ?? .distantFuture) }
        let worked = Set(groups.keys)
        let rankedNames = Set(WorkspaceNeededEntity.mostWantedSnapshot.map(\.name))
        let unseenAll = (WorkspaceNeededEntity.mostWantedSnapshot.filter { !worked.contains($0.name) } +
            DXCCDatabase.allEntities.filter { !rankedNames.contains($0.entityName) && !worked.contains($0.entityName) }
                .map { WorkspaceNeededEntity(name: $0.entityName, flag: $0.flagEmoji, continent: $0.continent, rank: nil) })
            .filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        let quickWins = quickWinsAll.filter { continentFilter == "All" ||
            DXCCDatabase.resolve(callsign: $0.value.first?["CALL"] ?? "").continent == continentFilter }
        let unseen = unseenAll.filter { continentFilter == "All" || $0.continent == continentFilter }
        let spots = appState.dxClusterClient.spots.filter { spot in
            Date().timeIntervalSince(spot.lastSeenAt) < 3600 && unseen.contains(where: { $0.name == DXCCDatabase.resolve(callsign: spot.callsign).entityName })
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 6) {
                    Text("CONTINENT").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(["All", "AF", "AN", "AS", "EU", "NA", "OC", "SA"], id: \.self) { continent in
                        let count = quickWinsAll.filter { continent == "All" ||
                            DXCCDatabase.resolve(callsign: $0.value.first?["CALL"] ?? "").continent == continent }.count +
                            unseenAll.filter { continent == "All" || $0.continent == continent }.count
                        Button("\(continent) \(count)") { continentFilter = continent }
                            .buttonStyle(.bordered)
                            .tint(continentFilter == continent ? .accentColor : .secondary)
                    }
                }
                sectionHeader("ON THE AIR", detail: "Needed entities spotted in the last hour")
                if spots.isEmpty { emptyState("No needed entities in recent DX cluster spots") }
                else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(spots.prefix(12)) { spot in
                                Button {
                                    appState.quickLogDraft.callsign = spot.callsign
                                    page = .log
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(DXCCDatabase.resolve(callsign: spot.callsign).flagEmoji) \(spot.callsign)")
                                            .fontWeight(.semibold)
                                        Text(DXCCDatabase.resolve(callsign: spot.callsign).entityName)
                                        Text("\(spot.frequencyKHz / 1000, specifier: "%.3f") MHz · \(spot.mode)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }.frame(width: 175, alignment: .leading).padding(10)
                                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader("QUICK WINS", detail: "Worked, awaiting a confirmation")
                        ForEach(quickWins.prefix(60), id: \.key) { group in
                            HStack {
                                Text(WorkspaceData.flag(group.value[0]))
                                Text(group.key).lineLimit(1)
                                Spacer()
                                Text("\(group.value.count) QSOs").foregroundStyle(.secondary)
                                statusBadge(.worked)
                            }.font(.system(size: 12)).padding(.vertical, 8)
                            Divider()
                        }
                        if quickWins.isEmpty { emptyState("Every worked entity is confirmed") }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(panelBackground, in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader("RAREST FIRST", detail: "Top nine: Most Wanted snapshot, 03 Oct 2026 · then catalog")
                        ForEach(unseen.prefix(60)) { entity in
                            HStack {
                                if let rank = entity.rank { Text("#\(rank)").foregroundStyle(.secondary).frame(width: 23, alignment: .leading) }
                                Text(entity.flag)
                                Text(entity.name).lineLimit(1)
                                Spacer()
                                Text(entity.continent).foregroundStyle(.secondary)
                            }.font(.system(size: 12)).padding(.vertical, 8)
                            Divider()
                        }
                        if unseen.isEmpty { emptyState("No matching entities") }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(panelBackground, in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(18)
        }
    }

    private var progressPage: some View {
        let catalog = DXCCDatabase.allEntities.count
        let coverage = progressCoverage
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    metric("Verified", value: progressVerified, color: .blue)
                    metric("Confirmed", value: max(0, progressConfirmed - progressVerified), color: .green)
                    metric("Worked", value: max(0, progressWorked - progressConfirmed), color: .yellow)
                    metric("Catalog remaining", value: max(0, catalog - progressWorked), color: .secondary)
                }
                Text("Counts are based on this station’s log. YAAM’s local entity catalog contains \(catalog) names; official DXCC credit is determined by ARRL.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 16) {
                    progressGroup("BY BAND", rows: progressBands)
                    progressGroup("BY MODE", rows: progressModes)
                    progressGroup("BY CONTINENT", rows: progressContinents)
                }
                sectionHeader("DXCC BY BAND", detail: "Entities with at least one QSO")
                let active = coverage.filter { $0.isWorked }
                if active.isEmpty { emptyState("Log a QSO to begin the DXCC chart") }
                else {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("ENTITY").frame(width: 175, alignment: .leading)
                            ForEach(Array(coverage.first?.bands.prefix(10) ?? [])) { item in
                                Text(item.band).frame(width: 42)
                            }
                        }.font(.caption2.bold()).foregroundStyle(.secondary).padding(.bottom, 8)
                        ForEach(active.prefix(100)) { entity in
                            HStack {
                                Text("\(WorkspaceData.flag(forEntity: entity.country)) \(entity.country)")
                                    .lineLimit(1).frame(width: 175, alignment: .leading)
                                ForEach(Array(entity.bands.prefix(10))) { item in
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(item.state == .confirmed ? Color.green.opacity(0.8) : item.state == .worked ? Color.yellow.opacity(0.8) : Color.secondary.opacity(0.15))
                                        .frame(width: 35, height: 17).frame(width: 42)
                                        .help("\(entity.country) · \(item.band) · \(item.state.rawValue)")
                                }
                            }.font(.system(size: 11)).padding(.vertical, 3)
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(panelBackground, in: RoundedRectangle(cornerRadius: 12))
                }
            }.padding(18)
        }
    }

    private func progressGroup(_ title: String, rows: [WorkspaceProgressRow]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Text(row.key.isEmpty ? "Unknown" : row.key).frame(width: 70, alignment: .leading)
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.14))
                            Capsule().fill(Color.yellow.opacity(0.75)).frame(width: geometry.size.width * min(1, CGFloat(row.total) / 100))
                            Capsule().fill(Color.green.opacity(0.85)).frame(width: geometry.size.width * min(1, CGFloat(row.confirmed) / 100))
                        }
                    }.frame(height: 8)
                    Text("\(row.confirmed)/\(row.total)").frame(width: 47, alignment: .trailing)
                }.font(.system(size: 11))
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(panelBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private var confirmationsPage: some View {
        let source: [QSORecordModel] = {
            switch confirmationTab {
            case "To verify": return toVerifyRecords
            case "New": return newConfirmationRecords
            default: return awaitingRecords
            }
        }()
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(QSLProvider.allCases) { provider in
                    Toggle(isOn: Binding(
                        get: { enabledProviders.contains(provider) },
                        set: { enabled in
                            if enabled { enabledProviders.insert(provider) }
                            else { enabledProviders.remove(provider) }
                        }
                    )) {
                        VStack(alignment: .leading) {
                            Text(provider.title).font(.caption.bold())
                            Text(provider == .clubLog ? "↑ upload" : "↑↓ sync")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }.toggleStyle(.switch).controlSize(.small)
                }
                Spacer()
                Picker("Default", selection: $defaultProvider) {
                    ForEach(QSLProvider.allCases) { Text($0.title).tag($0) }
                }.frame(width: 170)
                Button("Sync") {
                    var sources = Set<SyncSource>()
                    if enabledProviders.contains(.lotw) { sources.insert(.lotw) }
                    if enabledProviders.contains(.qrz) { sources.insert(.qrz) }
                    if !sources.isEmpty { appState.syncConfirmations(sources: sources, showCompletionAlert: false) }
                    if enabledProviders.contains(.eqsl) {
                        Task { await appState.downloadEQSLConfirmations() }
                    }
                }.disabled(enabledProviders.isEmpty)
            }.padding(16)
            Rectangle().fill(edge).frame(height: 1)
            HStack {
                Picker("Status", selection: $confirmationTab) {
                    ForEach(["Awaiting QSL", "To verify", "New"], id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.segmented).frame(width: 340)
                Spacer()
                Text(appState.qslHubStatus).font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 18).padding(.vertical, 10)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(source) { record in
                        HStack(spacing: 12) {
                            Text(record["CALL"]).fontWeight(.semibold).frame(width: 100, alignment: .leading)
                            Text("\(WorkspaceData.flag(record)) \(WorkspaceData.entity(record))")
                                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                            Text(record["BAND"]).frame(width: 42)
                            Text(WorkspaceData.mode(record)).frame(width: 55)
                            Text(WorkspaceData.displayDate(record, useUTC: useUTC, includeTime: false))
                                .frame(width: 75)
                            Text(uploadedNames(record)).foregroundStyle(.secondary).lineLimit(1).frame(width: 185, alignment: .leading)
                            if record.isConfirmed {
                                statusBadge(WorkspaceQSL.status(record)).frame(width: 170)
                            } else {
                                confirmationAction(record).frame(width: 170)
                            }
                        }.font(.system(size: 12)).padding(.horizontal, 18).frame(height: 38)
                        Divider()
                    }
                    if source.isEmpty { emptyState("No QSOs in this list") }
                }
            }
        }
    }

    private func uploadedNames(_ record: QSORecordModel) -> String {
        let names = QSLProvider.allCases.filter { provider in
            ["Y", "V", "C", "CONFIRMED"].contains(record[provider.sentField].uppercased()) ||
            appState.qslQueueJobs.contains { $0.qsoID == record.id && $0.provider == provider && $0.state == .succeeded }
        }.map(\.title)
        return names.isEmpty ? "Not uploaded" : "Uploaded to " + names.joined(separator: ", ")
    }

    private func confirmationAction(_ record: QSORecordModel) -> some View {
        let missing = enabledProviders.filter { provider in
            let sent = ["Y", "V", "C", "CONFIRMED"].contains(record[provider.sentField].uppercased())
            let queued = appState.qslQueueJobs.contains { $0.qsoID == record.id && $0.provider == provider && ($0.state.isPending || $0.state == .succeeded) }
            return !sent && !queued
        }.sorted { $0.title < $1.title }
        return Group {
            if enabledProviders.isEmpty {
                SettingsLink { Text("Configure logbooks") }
            } else if missing.isEmpty {
                if record.qsoAgeInDays ?? 0 >= 3 {
                    Button("Request QSL") { appState.openQSLReminderEmailComposer(for: record) }
                        .tint(.yellow)
                } else {
                    Text("Awaiting QSL").foregroundStyle(.yellow)
                }
            } else {
                let primary = missing.contains(defaultProvider) ? [defaultProvider] : missing
                HStack(spacing: 1) {
                    Button(primary.count == 1 ? "Upload to \(primary[0].title)" : "Upload to all") {
                        queue(record, providers: Set(primary))
                    }.lineLimit(1)
                    if missing.count > 1 {
                        Menu {
                            Button("Upload to all") { queue(record, providers: Set(missing)) }
                            ForEach(missing) { provider in
                                Button("Upload to \(provider.title)") { queue(record, providers: [provider]) }
                            }
                        } label: { Image(systemName: "chevron.down") }
                            .menuStyle(.borderlessButton)
                            .frame(width: 22)
                    }
                }
                .tint(.yellow)
            }
        }
    }

    private func queue(_ record: QSORecordModel, providers: Set<QSLProvider>) {
        appState.enqueueQSL(records: [record], providers: providers)
        Task { await appState.processQSLQueue() }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(.primary)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func metric(_ title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
            Text(value.formatted()).font(.system(size: 29, weight: .semibold, design: .rounded)).foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(panelBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private func statusBadge(_ status: WorkspaceQSL) -> some View {
        Text(status.rawValue).font(.caption.bold()).foregroundStyle(status.color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(status.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 4))
    }

    private func emptyState(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(24)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            ForEach([WorkspaceQSL.worked, .confirmed, .verified, .notWorked], id: \.rawValue) { status in
                HStack(spacing: 5) {
                    statusBadge(status)
                    Text(legendDescription(status)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(useUTC ? "UTC" : "Local").foregroundStyle(.secondary)
        }
        .font(.system(size: 10))
        .padding(.horizontal, 18).frame(height: 30)
        .overlay(alignment: .top) { Rectangle().fill(edge).frame(height: 1) }
    }

    private func legendDescription(_ status: WorkspaceQSL) -> String {
        switch status {
        case .worked: "awaiting QSL"
        case .confirmed: "QSL received"
        case .verified: "DXCC credit"
        case .notWorked: "no QSO"
        }
    }
}
