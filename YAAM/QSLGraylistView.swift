import SwiftUI

struct QSLGraylistView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        QSLGraylistContent(store: appState.qslGraylist,
                           station: appState.activeStationProfile?.displayTitle ?? "No active station",
                           syncEvidence: syncEvidence,
                           onOpenContacts: appState.openQSLGraylistContacts)
    }

    private var syncEvidence: String {
        guard let profileID = appState.activeStationProfileID else { return "No station profile selected." }
        return [SyncSource.lotw, .qrz].map { source in
            let checkpoint = ConfirmationSyncCheckpointStore.load(profileID: profileID, source: source)
            let date = checkpoint.lastSuccess.map {
                $0.formatted(.dateTime.year().month(.abbreviated).day())
            } ?? "never"
            let status = appState.syncServiceStatuses.first { $0.source == source }
            // Sync service status is app-wide; only the checkpoint above is profile-scoped.
            let problem = status?.state == .failure || status?.state == .warning ? " · app’s last run needs attention" : ""
            let stale = checkpoint.lastSuccess.map { Date().timeIntervalSince($0) > 7 * 86_400 } == true ? " · over 7 days old" : ""
            let baseline = checkpoint.baselineCompleted ? "" : " · history incomplete"
            return "\(source.title): \(date)\(stale)\(baseline)\(problem)"
        }.joined(separator: "   •   ")
    }
}

// Separate content allows native visual review without starting accounts, radios, or a database.
struct QSLGraylistContent: View {
    @ObservedObject var store: QSLGraylistStore
    let station: String
    let syncEvidence: String
    let onOpenContacts: (QSLGraylistEntry) -> Void
    @State private var query = ""
    @State private var selection: String?
    @State private var inspectedCall: String?
    @State private var showsDetails = false

    private var entries: [QSLGraylistEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.index.entries.filter {
            text.isEmpty || $0.callsign.localizedCaseInsensitiveContains(text) || $0.country.localizedCaseInsensitiveContains(text)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("QSL Graylist", systemImage: "person.crop.circle.badge.clock")
                        .font(.title2.bold())
                    Text("3+ distinct contacts · no received QSL · \(station)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("\(store.index.entries.count) callsigns")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { waitingPicker; priorityToggle; Spacer(minLength: 0); exceptionsMenu }
                VStack(alignment: .leading, spacing: 6) {
                    HStack { waitingPicker; Spacer(); exceptionsMenu }
                    priorityToggle
                }
            }
            .disabled(!store.hasWorkspace)

            VStack(alignment: .leading, spacing: 3) {
                Text("Local log evidence. Sync or review confirmations before enabling lower priority.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(syncEvidence).font(.caption2).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack {
                TextField("Search callsign or country", text: $query)
                    .textFieldStyle(.roundedBorder)
                if store.isLoading { ProgressView().controlSize(.small).help("Updating from the active station log") }
            }

            Table(entries, selection: $selection) {
                TableColumn("Callsign") { entry in
                    Button {
                        inspect(entry.callsign)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.callsign).font(.system(.body, design: .monospaced).bold())
                            if !entry.country.isEmpty { Text(entry.country).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Inspect \(entry.evidence)")
                }.width(min: 115, ideal: 180)
                TableColumn("QSOs") { entry in
                    Text("\(entry.contactCount)").monospacedDigit().help(entry.evidence)
                }.width(48)
                TableColumn("Latest QSO (UTC)") { entry in
                    Text(dateText(entry.latestContact)).font(.caption.monospaced())
                }.width(min: 104, ideal: 120)
                TableColumn("Priority") { entry in
                    Label(priorityText(entry), systemImage: store.isReduced(entry) ? "arrow.down.circle" : "clock")
                        .font(.caption)
                        .foregroundStyle(store.isReduced(entry) ? Color.orange : Color.secondary)
                        .help("\(entry.matureContactCount(waitingDays: store.waitingDays, now: store.now)) contacts have passed the \(store.waitingDays)-day wait. Direct calls to you keep their priority.")
                }.width(min: 100, ideal: 135)
            }
            .frame(minHeight: 90)
            .overlay {
                if entries.isEmpty {
                    VStack(spacing: 6) {
                        if store.isLoading {
                            Text("Checking contact history…")
                        } else if !store.hasWorkspace {
                            Label("Open the active station’s master log to use QSL Graylist.", systemImage: "book.closed")
                        } else if !query.isEmpty {
                            Text("No matching callsigns")
                        } else {
                            Label("No callsigns with 3+ contacts and zero confirmations", systemImage: "checkmark.circle")
                        }
                    }
                    .font(.callout).foregroundStyle(.secondary).padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .allowsHitTesting(false)
                }
            }

            HStack {
                Text("Any received QSL removes the automatic flag.")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Details…") { if let selection { inspect(selection) } }
                    .disabled(selection == nil)
                Button("Open contacts") {
                    if let selection, let entry = store.index.entry(for: selection) { onOpenContacts(entry) }
                }.disabled(selection == nil)
            }
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showsDetails) {
            QSLGraylistDetails(store: store, callsign: inspectedCall ?? "", onOpenContacts: onOpenContacts)
        }
        .onChange(of: store.index) { _, index in
            if let selection, index.entry(for: selection) == nil { self.selection = nil }
        }
        .onChange(of: query) { _, _ in
            if let selection, !entries.contains(where: { $0.callsign == selection }) { self.selection = nil }
        }
    }

    private var waitingPicker: some View {
        Picker("QSL wait", selection: Binding(get: { store.waitingDays }, set: store.setWaitingDays)) {
            ForEach(Array(Set([0, 30, 60, 90, 180, 365, store.waitingDays])).sorted(), id: \.self) { days in
                Text(days == 0 ? "No wait" : "\(days) days").tag(days)
            }
        }.fixedSize()
        .help("The table always uses 3+/0. Lower priority requires at least three contacts older than this wait.")
    }

    private var priorityToggle: some View {
        Toggle("Lower priority in Call Roster", isOn: Binding(get: { store.reducesPriority }, set: store.setReducesPriority))
            .toggleStyle(.checkbox).fixedSize()
    }

    private var exceptionsMenu: some View {
        Menu("Exceptions (\(store.exceptions.count))") {
            if store.exceptions.isEmpty { Text("No exceptions") }
            ForEach(store.exceptions.sorted(), id: \.self) { call in
                Button("Restore automatic priority: \(call)") { store.setException(false, callsign: call) }
            }
        }.fixedSize()
    }

    private func priorityText(_ entry: QSLGraylistEntry) -> String {
        if store.exceptions.contains(entry.callsign) { return "Exception" }
        if store.isReduced(entry) { return "Lower" }
        if entry.isMature(waitingDays: store.waitingDays, now: store.now) { return "Ready · off" }
        return entry.dates.count < 3 ? "Date unknown" : "Waiting"
    }

    private func inspect(_ call: String) {
        inspectedCall = call
        showsDetails = true
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return Self.utcDate.string(from: date)
    }

    private static let utcDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct QSLGraylistDetails: View {
    @ObservedObject var store: QSLGraylistStore
    let callsign: String
    let onOpenContacts: (QSLGraylistEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(callsign).font(.title2.monospaced().bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let entry = store.index.entry(for: callsign) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(entry.evidence, systemImage: "person.crop.circle.badge.clock").font(.headline)
                        if let oldest = entry.oldestContact, let latest = entry.latestContact {
                            Text("First QSO: \(oldest.formatted(date: .abbreviated, time: .omitted))\nLatest QSO: \(latest.formatted(date: .abbreviated, time: .omitted))")
                        }
                        Text("Bands: \(entry.bands.joined(separator: ", "))\nModes: \(entry.modes.joined(separator: ", "))")
                        Text("\(entry.sentCount) of \(entry.contactCount) distinct contacts have a recorded QSL sent/submission mark. Other submission histories are unknown or unrecorded.")
                        Text("\(entry.matureContactCount(waitingDays: store.waitingDays, now: store.now)) contacts have passed the \(store.waitingDays)-day wait. At least three are needed for lower priority.")
                        if entry.dates.count < entry.contactCount || entry.unresolvedCount > 0 {
                            Label("Some dates or contact identities are incomplete. Unidentifiable rows do not count toward the three-contact threshold; invalid dates do not satisfy the wait.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        Text("New country, band and grid opportunities remain visible in Call Roster. Direct calls to you keep their priority. You can select or log any station.")
                            .foregroundStyle(.secondary)
                        Toggle("Keep normal priority for this callsign", isOn: Binding(
                            get: { store.exceptions.contains(callsign) },
                            set: { store.setException($0, callsign: callsign) }
                        ))
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("Open contacts in log") { onOpenContacts(entry); dismiss() }
            } else {
                Text(store.isLoading ? "Updating contact history…" : "This callsign no longer meets the graylist criteria.")
                Spacer()
            }
        }
        .padding(20).frame(minWidth: 440, idealWidth: 540, minHeight: 310, idealHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct QSLGraylistCallBadge: View {
    @ObservedObject var store: QSLGraylistStore
    let callsign: String
    var onOpen: () -> Void

    var body: some View {
        if let entry = store.index.entry(for: callsign) {
            Button(action: onOpen) {
                Label("QSL Graylist · \(entry.evidence)", systemImage: "person.crop.circle.badge.clock")
                    .font(.caption2)
                    .foregroundStyle(store.isReduced(entry) ? Color.orange : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Review local QSL history and priority settings")
        }
    }
}
