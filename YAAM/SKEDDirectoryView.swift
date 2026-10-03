import SwiftUI
import AppKit
import UniformTypeIdentifiers

private struct SKEDComposeSelection: Identifiable {
    let id = UUID()
    let operators: [SKEDOperator]
}

private struct SKEDPreparedEmail {
    let callsign: String
    let email: String
    let subject: String
    let body: String
    let details: SKEDMailDetails
}

private struct SKEDCountryChoice: Identifiable {
    let iso: String
    let title: String
    var id: String { iso }
}

struct SKEDDirectoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var regionID = "me"
    @State private var countryISO = "ir"
    @State private var selectedUSState = ""
    @State private var geography: SKEDGeographyCatalog?
    @State private var geographyError: String?
    @State private var isLoadingGeography = false
    @State private var geographyRefreshID = 0
    @State private var category = "qso"
    @State private var refreshID = 0
    @State private var directory: SKEDDirectory?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var tokenDraft = ""
    @State private var validatingToken = false
    @State private var selectedOperator: SKEDOperator?
    @State private var focusedCallsign: String?
    @State private var selectedCallsigns: Set<String> = []
    @State private var bandPlans: [String: Set<String>] = [:]
    @State private var countryActivity = SKEDCountryBandActivity.empty
    @State private var operatorActivityByCallsign: [String: SKEDOperatorBandActivity] = [:]
    @State private var isLoadingLogHistory = false
    @State private var composeSelection: SKEDComposeSelection?
    @State private var previewCallsign = ""
    @State private var smtpConfigured = false
    @State private var senderName = ""
    @State private var includeTimeWindow = false
    @State private var timeStart = Date().addingTimeInterval(3600)
    @State private var timeEnd = Date().addingTimeInterval(7200)
    @State private var showSendSuccess = false
    @State private var sendSuccessCount = 0
    @State private var isSending = false
    @State private var cancelSending = false
    @State private var sendingCallsign = ""
    @State private var sendResults: [String: Bool] = [:]
    @State private var sendErrors: [String: String] = [:]
    @State private var allowOverlappingSKED = false
    @State private var showSKEDHistory = false
    @State private var showComposerHistory = false
    @State private var historyFilterCallsign = ""
    @State private var historySaveWarnings: Set<String> = []
    @State private var mailSubjectTemplate = SKEDMailTemplate.defaultSubject
    @State private var mailBodyTemplate = SKEDMailTemplate.defaultBody

    private var destinationKey: String {
        countryISO == "us" && !selectedUSState.isEmpty ? "state:\(selectedUSState.lowercased())" : countryISO
    }

    private var destinationTitle: String {
        if countryISO == "us", let state = geography?.states.first(where: { $0.code == selectedUSState }) {
            return "\(state.name), United States"
        }
        let fallback = geography?.countries.first(where: { $0.iso == countryISO })?.serviceName ?? countryISO.uppercased()
        return fullCountryName(for: countryISO, fallback: fallback)
    }

    private func fullCountryName(for iso: String, fallback: String) -> String {
        if iso.caseInsensitiveCompare("bq1") == .orderedSame { return "Bonaire" }
        if ["x1", "x2"].contains(iso.lowercased()) { return "Antarctic station \(iso.uppercased())" }
        let code = iso.uppercased()
        let localized = Locale(identifier: "en_US").localizedString(forRegionCode: code) ?? ""
        return localized.isEmpty || localized.caseInsensitiveCompare(code) == .orderedSame ? fallback : localized
    }

    private var countryChoices: [SKEDCountryChoice] {
        (geography?.countries(in: regionID) ?? []).sorted {
            fullCountryName(for: $0.iso, fallback: $0.serviceName)
                .localizedStandardCompare(fullCountryName(for: $1.iso, fallback: $1.serviceName)) == .orderedAscending
        }.map { country in
            let prefix = country.iso == "bq1" ? "PJ4" : DXCCDatabase.representativePrefix(forISO: country.iso) ?? country.iso.uppercased()
            let flag = flagForCountryIso(country.iso == "bq1" ? "bq" : country.iso)
            return SKEDCountryChoice(iso: country.iso,
                                     title: "\(flag) \(fullCountryName(for: country.iso, fallback: country.serviceName)) · \(prefix)")
        }
    }

    private var mainView: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let geographyError {
                        HStack {
                            Label("Region and state catalog: \(geographyError)", systemImage: "globe.americas.fill")
                                .foregroundStyle(.orange)
                            Spacer()
                            Button("Retry") { geographyRefreshID += 1 }
                        }
                        .padding(12)
                        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if directory == nil && !isLoading {
                        tokenControls
                    }
                    if let directory {
                        summary(directory)
                        countryBandOverview(directory)
                        if !selectedCallsigns.isEmpty {
                            selectedOperatorsBandBar(directory)
                        }
                        if directory.operators.isEmpty {
                            ContentUnavailableView("No operators found", systemImage: "antenna.radiowaves.left.and.right.slash",
                                                   description: Text("Try another country or ranking category."))
                                .frame(maxWidth: .infinity, minHeight: 250)
                        } else {
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: 18) {
                                    operatorTable(directory).frame(minWidth: 680)
                                    planningPanel(directory).frame(width: 340)
                                }
                                VStack(spacing: 18) {
                                    planningPanel(directory)
                                    operatorTable(directory)
                                }
                            }
                        }
                    } else if isLoading {
                        VStack(spacing: 14) {
                            ProgressView().controlSize(.large)
                            Text("Loading the top 19 SKED contacts…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 300)
                    } else {
                        ContentUnavailableView("Directory unavailable", systemImage: "wifi.exclamationmark",
                                               description: Text("Refresh to try the SKED service again."))
                            .frame(maxWidth: .infinity, minHeight: 300)
                    }
                }
                .padding(22)
                .frame(maxWidth: 1480)
                .frame(maxWidth: .infinity)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
    }

    private var persistedPreferencesView: some View {
        mainView
        .onAppear {
            loadBandPlans()
            loadMailTemplate()
            loadSenderName()
        }
        .onChange(of: regionID) { _, newRegion in
            guard let geography, !geography.countries(in: newRegion).contains(where: { $0.iso == countryISO }) else { return }
            countryISO = newRegion == "na" ? "us" : geography.countries(in: newRegion).first?.iso ?? countryISO
        }
        .onChange(of: mailSubjectTemplate) { _, value in
            UserDefaults.standard.set(value, forKey: "sked.mailSubject.v1")
        }
        .onChange(of: mailBodyTemplate) { _, value in
            UserDefaults.standard.set(value, forKey: "sked.mailBody.v1")
        }
        .onChange(of: senderName) { _, value in
            UserDefaults.standard.set(value, forKey: senderNameStorageKey)
        }
    }

    private var selectionObservedView: some View {
        persistedPreferencesView
        .onChange(of: includeTimeWindow) { _, _ in allowOverlappingSKED = false }
        .onChange(of: timeStart) { _, _ in allowOverlappingSKED = false }
        .onChange(of: timeEnd) { _, _ in allowOverlappingSKED = false }
        .onChange(of: countryISO) { _, _ in
            selectedUSState = ""
            selectedCallsigns.removeAll()
            focusedCallsign = nil
            loadBandPlans()
        }
        .onChange(of: selectedUSState) { _, _ in
            selectedCallsigns.removeAll()
            focusedCallsign = nil
            loadBandPlans()
        }
        .onChange(of: appState.activeStationProfileID) { _, _ in
            selectedCallsigns.removeAll()
            loadBandPlans()
            loadSenderName()
        }
    }

    private var observedView: some View {
        selectionObservedView
        .task(id: geographyRefreshID) { await loadGeography() }
        .task(id: "\(destinationKey)-\(category)-\(refreshID)") { await load() }
        .task(id: "\(destinationKey)-\(appState.qsoRecordsRevision)-\(directory?.operators.map(\.callsign).joined(separator: ",") ?? "")") {
            await updateCountryActivity()
        }
    }

    private var presentedView: some View {
        observedView
        .sheet(item: $selectedOperator) { item in
            operatorDetails(item)
        }
        .sheet(item: $composeSelection) { selection in
            composer(selection)
        }
        .sheet(isPresented: $showSKEDHistory) {
            SKEDMailHistoryView(entries: SKEDMailHistory.successfulEntries(appState.emailHistory),
                                destinationKey: destinationKey, initialCallsign: historyFilterCallsign)
        }
    }

    var body: some View {
        presentedView
        .alert("SKED email sent", isPresented: $showSendSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Sent \(sendSuccessCount) personalized email\(sendSuccessCount == 1 ? "" : "s") successfully." +
                 (historySaveWarnings.isEmpty ? "" :
                  " Local history could not be saved for \(historySaveWarnings.sorted().joined(separator: ", ")). Check your mailbox before sending again."))
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 48, height: 48)
                .background(.cyan.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text("SKED Directory")
                    .font(.title2.weight(.bold))
                Text("Plan the bands, write a personal note, and arrange a time on the air")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                filters
                Spacer(minLength: 8)
                actions
            }
            VStack(alignment: .leading, spacing: 10) {
                filters
                actions
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Picker("Region", selection: $regionID) {
                if let geography {
                    ForEach(geography.regions) { region in
                        Text("\(region.icon) \(region.name)").tag(region.id)
                    }
                } else {
                    Text("🕌 Middle East").tag("me")
                }
            }
            .frame(width: 225)
            .disabled(geography == nil)
            if isLoadingGeography { ProgressView().controlSize(.small) }

            Picker("Country", selection: $countryISO) {
                if geography == nil {
                    Text("🇮🇷 Iran · EP").tag("ir")
                } else {
                    ForEach(countryChoices) { country in
                        Text(country.title).tag(country.iso)
                    }
                }
            }
            .frame(width: 285)
            .disabled(geography == nil)

            if countryISO == "us" {
                Picker("US state", selection: $selectedUSState) {
                    Text("All United States").tag("")
                    ForEach(geography?.states ?? []) { state in
                        Text("\(state.name) · \(state.code)").tag(state.code)
                    }
                }
                .frame(width: 265)
                .disabled(geography == nil)
            }

            Picker("Rank by", selection: $category) {
                Text("Confirmed QSOs").tag("qso")
                Text("DXCC countries").tag("countries")
                Text("Band slots").tag("band")
            }
            .frame(width: 190)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                guard let directory else { return }
                let eligible = Set(directory.operators.compactMap { $0.validEmail == nil ? nil : $0.callsign })
                if eligible.isSubset(of: selectedCallsigns) {
                    selectedCallsigns.subtract(eligible)
                } else {
                    selectedCallsigns.formUnion(eligible)
                }
            } label: {
                let allSelected = directory.map { directory in
                    let eligible = Set(directory.operators.compactMap { $0.validEmail == nil ? nil : $0.callsign })
                    return !eligible.isEmpty && eligible.isSubset(of: selectedCallsigns)
                } ?? false
                Label(allSelected ? "Deselect All" : "Select All",
                      systemImage: allSelected ? "square" : "checkmark.square")
            }
            .disabled(directory?.emailCount == 0 || directory == nil)
            .help("Toggle all operators with an email address in this country")

            Button {
                guard let directory else { return }
                let operators = directory.operators.filter { selectedCallsigns.contains($0.callsign) && $0.validEmail != nil }
                openComposer(for: operators)
            } label: {
                Label("Email selected (\(selectedCallsigns.count))", systemImage: "paperplane")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCallsigns.isEmpty || directory == nil)

            Button {
                exportCSV()
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.down")
            }
            .disabled(directory?.operators.isEmpty != false)

            Button {
                historyFilterCallsign = ""
                showSKEDHistory = true
            } label: {
                Label("Sent history (\(SKEDMailHistory.successfulEntries(appState.emailHistory).count))",
                      systemImage: "clock.arrow.circlepath")
            }

            Button {
                if let emails = directory?.allEmails, !emails.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(emails, forType: .string)
                    notice = "Copied \(directory?.emailCount ?? 0) email addresses."
                }
            } label: {
                Label("Copy all emails", systemImage: "doc.on.doc")
            }
            .disabled(directory?.allEmails.isEmpty != false)

            Button {
                refreshID += 1
            } label: {
                Label("Sync QRZ", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(isLoading)
            .help("Refresh rankings and look up missing contact details on QRZ")
        }
    }

    private func selectedOperatorsBandBar(_ directory: SKEDDirectory) -> some View {
        let operators = directory.operators.filter { selectedCallsigns.contains($0.callsign) && $0.validEmail != nil }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(operators.count) operators selected", systemImage: "person.2.fill")
                    .font(.headline)
                Text("Choose bands for everyone here; each email will use the operator's name and callsign.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear selection") { selectedCallsigns.removeAll() }
                    .controlSize(.small)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 7)], spacing: 7) {
                ForEach(SKEDMailTemplate.bands, id: \.self) { band in
                    let chosenForAll = operators.allSatisfy { bandPlans[$0.callsign, default: []].contains(band) }
                    Button(band) { toggleBand(band, for: operators) }
                        .buttonStyle(.plain)
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(chosenForAll ? Color.accentColor.opacity(0.24) : Color.secondary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .stroke(chosenForAll ? Color.accentColor : .clear, lineWidth: 1))
                        .help(chosenForAll ? "Remove \(band) from all selected operators" : "Add \(band) to all selected operators")
                }
            }
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func summary(_ directory: SKEDDirectory) -> some View {
        HStack(spacing: 16) {
            Text(flagForCountryIso(countryISO == "bq1" ? "bq" : countryISO))
                .font(.system(size: 36))
            VStack(alignment: .leading, spacing: 3) {
                Text(destinationTitle)
                    .font(.title3.weight(.bold))
                Text("\(directory.operators.count) ranked operators")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(countryActivity.worked.count) bands worked")
                    .font(.headline.monospacedDigit())
                Text("\(countryActivity.confirmed.count) confirmed · \(countryActivity.qsoCount) QSOs")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(directory.emailCount) / \(directory.operators.count)")
                    .font(.headline.monospacedDigit())
                Text("emails available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.accentColor.opacity(0.18)))
    }

    private func countryBandOverview(_ directory: SKEDDirectory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(destinationTitle) · band history", systemImage: "waveform.path")
                    .font(.headline)
                Spacer()
                Text("From the active station logbook")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 77), spacing: 7)], spacing: 7) {
                ForEach(SKEDMailTemplate.bands, id: \.self) { band in
                    let confirmed = countryActivity.confirmed.contains(band)
                    let worked = countryActivity.worked.contains(band)
                    HStack(spacing: 5) {
                        Circle().fill(confirmed ? Color.green : worked ? Color.blue : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(band).font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background((confirmed ? Color.green : worked ? Color.blue : Color.orange).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 7))
                    .help(confirmed ? "Confirmed QSO with this country" : worked ? "QSO logged, not confirmed" : "No QSO logged on this band")
                }
            }
            HStack(spacing: 14) {
                Label("Confirmed", systemImage: "circle.fill").foregroundStyle(.green)
                Label("Worked", systemImage: "circle.fill").foregroundStyle(.blue)
                Label("Not worked", systemImage: "circle.fill").foregroundStyle(.orange)
            }
            .font(.caption2)
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 13))
    }

    private func operatorTable(_ directory: SKEDDirectory) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Operators").font(.headline)
                    Text("Select contacts, then set the bands you want for each one.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(directory.emailCount) contacts with email")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Suggest bands for selected") {
                    for callsign in selectedCallsigns where bandPlans[callsign, default: []].isEmpty {
                        suggestBands(for: callsign)
                    }
                }
                .disabled(selectedCallsigns.isEmpty)
                Button("Clear") { selectedCallsigns.removeAll() }
            }
            .controlSize(.small)
            .padding(15)
            .background(Color(NSColor.controlBackgroundColor))

            ForEach(directory.operators) { item in
                let sentSKED = SKEDMailHistory.entries(for: item.callsign, email: item.validEmail,
                                                       in: appState.emailHistory)
                HStack(spacing: 10) {
                    Toggle("Select \(item.callsign)", isOn: Binding(
                        get: { selectedCallsigns.contains(item.callsign) },
                        set: { selected in
                            if selected { selectedCallsigns.insert(item.callsign) }
                            else { selectedCallsigns.remove(item.callsign) }
                        }
                    ))
                    .labelsHidden()
                    .disabled(item.validEmail == nil)
                    Text("#\(item.rank)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .leading)
                    Button {
                        focusedCallsign = item.callsign
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Text(item.callsign).font(.callout.bold()).foregroundStyle(.cyan)
                                if !sentSKED.isEmpty {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                            Text(item.name ?? "Name unavailable")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            if let latest = sentSKED.first {
                                Text("SKED emailed \(latest.date.formatted(date: .abbreviated, time: .omitted)) · \(sentSKED.count) sent")
                                    .font(.caption2).foregroundStyle(.green).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(bandPlans[item.callsign, default: []].isEmpty
                             ? "Choose bands" : SKEDMailTemplate.bandPhrase(bandPlans[item.callsign] ?? []))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(bandPlans[item.callsign, default: []].isEmpty ? Color.orange : Color.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(item.validEmail ?? "No email available")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: 220, alignment: .leading)
                    operatorHistory(item)
                        .frame(width: 195, alignment: .leading)
                    Button("Email") { openComposer(for: [item]) }
                        .buttonStyle(.bordered)
                        .disabled(item.validEmail == nil)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(focusedCallsign == item.callsign ? Color.cyan.opacity(0.10) : .clear)
                Divider()
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(NSColor.separatorColor)))
        .overlay(alignment: .bottomLeading) {
            if let notice {
                Text(notice)
                    .font(.caption)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(10)
            }
        }
    }

    private func operatorHistory(_ item: SKEDOperator) -> some View {
        let call = item.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return VStack(alignment: .leading, spacing: 3) {
            if isLoadingLogHistory {
                Label("Checking logbook…", systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let activity = operatorActivityByCallsign[call] {
                Label("\(activity.qsoCount) previous QSO\(activity.qsoCount == 1 ? "" : "s")",
                      systemImage: activity.confirmed.isEmpty ? "waveform" : "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(activity.confirmed.isEmpty ? Color.blue : Color.green)
                Text(activity.bandSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Label("No previous QSO", systemImage: "circle.dashed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .help(isLoadingLogHistory ? "Checking the active station logbook" : operatorActivityByCallsign[call].map {
            "Your active station log: \($0.qsoCount) QSO\($0.qsoCount == 1 ? "" : "s") with \(item.callsign). \($0.bandSummary)."
        } ?? "No QSO with \(item.callsign) in the active station logbook")
    }

    private func planningPanel(_ directory: SKEDDirectory) -> some View {
        let item = directory.operators.first { $0.callsign == focusedCallsign }
            ?? directory.operators.first
        return VStack(alignment: .leading, spacing: 13) {
            Label("SKED plan", systemImage: "calendar.badge.clock")
                .font(.headline)
            if let item {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.callsign).font(.title2.bold())
                    Spacer()
                    Text("#\(item.rank)").foregroundStyle(.secondary)
                }
                Text(item.name ?? "Operator name unavailable")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let email = item.validEmail {
                    Text(email).font(.caption).textSelection(.enabled)
                } else {
                    Label("No email address available", systemImage: "envelope.badge")
                        .font(.caption).foregroundStyle(.orange)
                }
                operatorHistory(item)
                let sentSKED = SKEDMailHistory.entries(for: item.callsign, email: item.validEmail,
                                                       in: appState.emailHistory)
                if !sentSKED.isEmpty {
                    Button("View \(sentSKED.count) sent SKED email\(sentSKED.count == 1 ? "" : "s")") {
                        historyFilterCallsign = item.callsign
                        showSKEDHistory = true
                    }
                    .font(.caption)
                }
                HStack {
                    Button("Operator details") { selectedOperator = item }
                    Spacer()
                    Link("QRZ profile", destination: URL(string: "https://www.qrz.com/db/\(item.callsign)")!)
                }
                .font(.caption)
                Divider()
                Text("Bands to request").font(.subheadline.bold())
                Text("Choose bands for \(item.callsign). Your choices appear in the directory and the email preview.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 7)], spacing: 7) {
                    ForEach(SKEDMailTemplate.bands, id: \.self) { band in
                        let selected = bandPlans[item.callsign, default: []].contains(band)
                        Button {
                            toggleBand(band, for: item.callsign)
                        } label: {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(countryActivity.confirmed.contains(band) ? Color.green :
                                          countryActivity.worked.contains(band) ? Color.blue : Color.orange)
                                    .frame(width: 6, height: 6)
                                Text(band).font(.caption.bold())
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(selected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7)
                                .stroke(selected ? Color.accentColor : .clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Button("Suggest 3 new bands") { suggestBands(for: item.callsign) }
                    Button("Clear") {
                        bandPlans[item.callsign] = []
                        saveBandPlans()
                    }
                }
                .font(.caption)
                Divider()
                Button {
                    openComposer(for: [item])
                } label: {
                    Label("Write email to \(item.callsign)", systemImage: "envelope.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(item.validEmail == nil)
            } else {
                Text("Choose an operator to plan a SKED.")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8),
                    in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color(NSColor.separatorColor)))
    }

    private var bandPlanStorageKey: String {
        let station = appState.activeStationProfile?.normalizedCallsign ?? "no-station"
        return "sked.bandPlans.v1.\(station).\(destinationKey)"
    }

    private func loadBandPlans() {
        guard let data = UserDefaults.standard.data(forKey: bandPlanStorageKey),
              let saved = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            bandPlans = [:]
            return
        }
        bandPlans = saved.mapValues { Set($0).intersection(SKEDMailTemplate.bands) }
    }

    private func saveBandPlans() {
        let saved = bandPlans.mapValues { SKEDMailTemplate.ordered($0) }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: bandPlanStorageKey)
        }
    }

    private func toggleBand(_ band: String, for callsign: String) {
        var selected = bandPlans[callsign, default: []]
        if selected.contains(band) { selected.remove(band) }
        else { selected.insert(band) }
        bandPlans[callsign] = selected
        saveBandPlans()
    }

    private func toggleBand(_ band: String, for operators: [SKEDOperator]) {
        guard !operators.isEmpty else { return }
        let remove = operators.allSatisfy { bandPlans[$0.callsign, default: []].contains(band) }
        for item in operators {
            var chosen = bandPlans[item.callsign, default: []]
            if remove { chosen.remove(band) } else { chosen.insert(band) }
            bandPlans[item.callsign] = chosen
        }
        saveBandPlans()
    }

    private func suggestBands(for callsign: String) {
        let priority = ["20m", "40m", "17m", "15m", "10m", "30m", "80m", "12m", "160m", "6m", "60m"]
        bandPlans[callsign] = Set(priority.filter { !countryActivity.worked.contains($0) }.prefix(3))
        saveBandPlans()
    }

    private func updateCountryActivity() async {
        guard let directory, directory.countryISO.caseInsensitiveCompare(countryISO) == .orderedSame else {
            countryActivity = .empty
            operatorActivityByCallsign = [:]
            isLoadingLogHistory = false
            return
        }
        isLoadingLogHistory = true
        let records = appState.qsoRecords
        let iso = countryISO
        let destinationCountryKey = CountryNameNormalizer.canonicalKey(directory.countryName)
        let stateCode = selectedUSState
        let stateName = geography?.states.first(where: { $0.code == stateCode })?.name.lowercased() ?? ""
        let callsigns = Set(directory.operators.map { $0.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() })
        let result = await Task.detached(priority: .utility) {
            var countryByCall: [String: String] = [:]
            var entries: [SKEDLogBandEntry] = []
            var operatorEntries: [SKEDOperatorLogBandEntry] = []
            for record in records {
                let call = (record.fields["CALL"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let country = record.fields["COUNTRY"] ?? ""
                let key = "\(call)|\(country)"
                let resolvedISO: String
                if let cached = countryByCall[key] {
                    resolvedISO = cached
                } else {
                    let loggedNameKey = CountryNameNormalizer.canonicalKey(country)
                    resolvedISO = !country.isEmpty && loggedNameKey == destinationCountryKey
                        ? iso : DXCCDatabase.resolve(callsign: call, country: country).countryCode
                    countryByCall[key] = resolvedISO
                }
                let countryMatches = SKEDStateLogMatch.matches(
                    destinationISO: iso, stateCode: stateCode, stateName: stateName,
                    loggedISO: resolvedISO, loggedState: record.fields["STATE"] ?? "")
                    || (iso == "bq1" && call.hasPrefix("PJ4"))
                let operatorMatches = callsigns.contains(call)
                guard countryMatches || operatorMatches else { continue }
                let band = (record.fields["BAND"].flatMap {
                                let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                                return value.isEmpty ? nil : value
                            }
                            ?? record.fields["FREQ"].flatMap(AmateurBandPlan.band(for:))
                            ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if countryMatches {
                    entries.append(.init(countryISO: iso, band: band, confirmed: record.isConfirmed))
                }
                if operatorMatches {
                    operatorEntries.append(.init(callsign: call, band: band, confirmed: record.isConfirmed))
                }
            }
            return (SKEDCountryBandActivity.make(entries: entries, countryISO: iso),
                    SKEDOperatorBandActivity.grouped(entries: operatorEntries))
        }.value
        guard !Task.isCancelled else { return }
        countryActivity = result.0
        operatorActivityByCallsign = result.1
        isLoadingLogHistory = false
    }

    private var tokenControls: some View {
        HStack(spacing: 10) {
            SecureField("QRZ Rank API token", text: $tokenDraft)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 340)
            Button("Verify and save token") {
                Task { await verifyAndSaveToken() }
            }
            .disabled(validatingToken || QRZRankAPIContract.normalizedToken(tokenDraft).isEmpty)
            if validatingToken { ProgressView().controlSize(.small) }
            Link("Get a token", destination: URL(string: "https://qrz-rank.asis.sh/")!)
            Spacer()
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func verifyAndSaveToken() async {
        let token = QRZRankAPIContract.normalizedToken(tokenDraft)
        guard !token.isEmpty else { return }
        validatingToken = true
        defer { validatingToken = false }
        do {
            _ = try await SKEDDirectoryService.shared.fetch(
                countryISO: countryISO, category: category, enrich: false,
                token: token, userAgent: "YAAM-macOS/\(appState.currentVersion)")
            guard CredentialVault.set(token, for: .qrzRankAPIToken) else {
                errorMessage = "The verified token could not be saved in Keychain."
                return
            }
            tokenDraft = ""
            refreshID += 1
            geographyRefreshID += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func operatorDetails(_ item: SKEDOperator) -> some View {
        let entity = DXCCDatabase.resolve(callsign: item.callsign)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(flagForCountryIso(countryISO == "bq1" ? "bq" : countryISO))
                    .font(.largeTitle)
                VStack(alignment: .leading) {
                    Text(item.callsign).font(.title.bold())
                    Text(destinationTitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("#\(item.rank)").font(.title3.monospacedDigit())
            }
            Divider()
            LabeledContent("Operator", value: item.name ?? "Name unavailable")
            LabeledContent("Email", value: item.validEmail ?? "Not available")
            LabeledContent("DXCC entity", value: "\(entity.flagEmoji) \(entity.entityName)")
            LabeledContent("Continent / CQ zone", value: "\(entity.continent) / \(entity.cqZone)")
            if let value = item.confirmedQSOs {
                LabeledContent("Confirmed QSOs", value: value.formatted())
            }
            if let value = item.dxccCountries {
                LabeledContent("DXCC countries", value: value.formatted())
            }
            if let value = item.bandSlots {
                LabeledContent("Band slots", value: value.formatted())
            }
            HStack {
                Link("View on QRZ", destination: URL(string: "https://www.qrz.com/db/\(item.callsign)")!)
                Spacer()
                Button("Email for SKED") {
                    selectedOperator = nil
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        openComposer(for: [item])
                    }
                }
                    .disabled(item.validEmail == nil)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func loadGeography() async {
        isLoadingGeography = true
        defer { isLoadingGeography = false }
        do {
            let catalog = try await SKEDGeographyService.shared.fetch(
                token: CredentialVault.value(for: .qrzRankAPIToken),
                userAgent: "YAAM-macOS/\(appState.currentVersion)")
            guard !Task.isCancelled else { return }
            geography = catalog
            geographyError = nil
            if let actualRegion = catalog.region(for: countryISO) { regionID = actualRegion }
        } catch {
            guard !Task.isCancelled else { return }
            geographyError = error.localizedDescription
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        notice = nil
        directory = nil
        do {
            let token = CredentialVault.value(for: .qrzRankAPIToken)
            let result = try await SKEDDirectoryService.shared.fetch(
                countryISO: destinationKey, category: category, enrich: true,
                token: token, userAgent: "YAAM-macOS/\(appState.currentVersion)"
            )
            guard !Task.isCancelled else { return }
            directory = result
            selectedCallsigns = selectedCallsigns.intersection(Set(result.operators.compactMap { $0.validEmail == nil ? nil : $0.callsign }))
            if !result.operators.contains(where: { $0.callsign == focusedCallsign }) {
                focusedCallsign = result.operators.first?.callsign
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func openComposer(for operators: [SKEDOperator]) {
        guard !operators.isEmpty else { return }
        smtpConfigured = appState.isSMTPConfigured
        includeTimeWindow = false
        timeStart = Date().addingTimeInterval(3600)
        timeEnd = Date().addingTimeInterval(7200)
        previewCallsign = operators[0].callsign
        sendResults = [:]
        sendErrors = [:]
        allowOverlappingSKED = false
        historySaveWarnings = []
        showComposerHistory = false
        cancelSending = false
        sendingCallsign = ""
        composeSelection = SKEDComposeSelection(operators: operators)
    }

    private func loadMailTemplate() {
        if let saved = UserDefaults.standard.string(forKey: "sked.mailSubject.v1") {
            mailSubjectTemplate = saved
        }
        if let saved = UserDefaults.standard.string(forKey: "sked.mailBody.v1") {
            if saved.contains("I hope you're doing well!") {
                mailBodyTemplate = SKEDMailTemplate.defaultBody
            } else {
                let oldFooter = "\n\n73,\n{my_callsign}"
                mailBodyTemplate = saved.hasSuffix(oldFooter)
                    ? String(saved.dropLast(oldFooter.count)) : saved
            }
        }
    }

    private var senderNameStorageKey: String {
        "sked.senderName.v1.\(appState.activeStationProfile?.normalizedCallsign ?? "no-station")"
    }

    private func loadSenderName() {
        senderName = UserDefaults.standard.string(forKey: senderNameStorageKey) ?? ""
    }

    private var utcTimeWindow: String? {
        includeTimeWindow ? SKEDMailTemplate.utcWindow(start: timeStart, end: timeEnd) : nil
    }

    private var proposedSchedule: SKEDMailSchedule? {
        includeTimeWindow ? SKEDMailSchedule(start: timeStart, end: timeEnd) : nil
    }

    private func conflictingSKED(for item: SKEDOperator) -> [EmailHistoryEntry] {
        SKEDMailHistory.conflicts(for: item.callsign, email: item.validEmail,
                                  schedule: proposedSchedule, in: appState.emailHistory)
    }

    private func localTimeDescription(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private func renderedSubject(for item: SKEDOperator) -> String {
        let station = appState.activeStationProfile
        return SKEDMailTemplate.safeSubject(SKEDMailTemplate.render(
            mailSubjectTemplate, callsign: item.callsign, name: item.name,
            bands: bandPlans[item.callsign, default: []],
            stationCallsign: station?.normalizedCallsign ?? "",
            stationGrid: SKEDMailTemplate.fourCharacterGrid(station?.normalizedGrid ?? ""),
            stationQTH: station?.qth ?? "", stationName: senderName,
            timeWindowUTC: utcTimeWindow))
    }

    private func renderedBody(for item: SKEDOperator) -> String {
        let station = appState.activeStationProfile
        var rendered = SKEDMailTemplate.render(
            mailBodyTemplate, callsign: item.callsign, name: item.name,
            bands: bandPlans[item.callsign, default: []],
            stationCallsign: station?.normalizedCallsign ?? "",
            stationGrid: SKEDMailTemplate.fourCharacterGrid(station?.normalizedGrid ?? ""),
            stationQTH: station?.qth ?? "", stationName: senderName,
            timeWindowUTC: utcTimeWindow)
        if !mailBodyTemplate.localizedCaseInsensitiveContains("{callsign}") {
            let greeting = SKEDMailTemplate.greetingName(item.name, callsign: item.callsign)
            rendered = "Hi \(greeting) (\(item.callsign)),\n\n" + rendered
        }
        if !mailBodyTemplate.localizedCaseInsensitiveContains("{bands}") {
            rendered += "\n\nSuggested bands: \(SKEDMailTemplate.bandPhrase(bandPlans[item.callsign, default: []]))."
        }
        if let utcTimeWindow, !mailBodyTemplate.localizedCaseInsensitiveContains("{time_window}") {
            rendered += "\n\n" + utcTimeWindow
        }
        return rendered.trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n\n" + SKEDMailTemplate.signature(name: senderName,
                                                    callsign: station?.normalizedCallsign ?? "")
    }

    private func sendIssue(for selection: SKEDComposeSelection) -> String? {
        let pending = selection.operators.filter { sendResults[$0.callsign] != true }
        if appState.activeStationProfile?.normalizedCallsign.isEmpty != false {
            return "Choose an active station profile with your callsign before sending."
        }
        if senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter your name for the email signature."
        }
        if includeTimeWindow && !SKEDMailTemplate.isValidDailyWindow(start: timeStart, end: timeEnd) {
            return "Choose up to 31 days, with a daily end time later than the daily start time."
        }
        if includeTimeWindow && timeEnd < Date().addingTimeInterval(-60) {
            return "Choose dates that still include a future daily window."
        }
        if mailBodyTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Write a message before sending."
        }
        let unknown = SKEDMailTemplate.unresolvedFields(mailSubjectTemplate + "\n" + mailBodyTemplate)
        if !unknown.isEmpty {
            return "Unknown email field: " + unknown.map { "{\($0)}" }.joined(separator: ", ")
        }
        if !smtpConfigured {
            return "Configure your SMTP account in YAAM Settings → Email before sending."
        }
        if let item = pending.first(where: { $0.validEmail == nil }) {
            return "\(item.callsign) has no valid email address."
        }
        if let item = pending.first(where: { bandPlans[$0.callsign, default: []].isEmpty }) {
            return "Choose at least one requested band for \(item.callsign)."
        }
        if pending.contains(where: { renderedSubject(for: $0).isEmpty || renderedBody(for: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "The subject and message cannot be empty."
        }
        if !allowOverlappingSKED, !pending.isEmpty,
           pending.allSatisfy({ !conflictingSKED(for: $0).isEmpty }) {
            return "Every selected operator has an overlapping or unknown SKED schedule. Choose different days or review the earlier email and explicitly allow another send."
        }
        return nil
    }

    private func composer(_ selection: SKEDComposeSelection) -> some View {
        let preview = selection.operators.first { $0.callsign == previewCallsign }
            ?? selection.operators[0]
        let pending = selection.operators.filter { sendResults[$0.callsign] != true }
        let eligibleCount = pending.filter { allowOverlappingSKED || conflictingSKED(for: $0).isEmpty }.count
        let issue = sendIssue(for: selection)
        return VStack(alignment: .leading, spacing: 15) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selection.operators.count == 1 ? "SKED email · \(preview.callsign)" : "SKED emails · \(selection.operators.count) operators")
                        .font(.title2.bold())
                    Text("Each operator receives a separate, personalized message through your YAAM SMTP account.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Label(appState.configuredSMTPEmail.isEmpty ? "SMTP not configured" : appState.configuredSMTPEmail,
                      systemImage: "envelope.badge.shield.half.filled")
                    .font(.caption)
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Shared template").font(.headline)
                    Text("Saved automatically. Each preview replaces the fields below with that operator's details and band plan.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("Your name for the signature", text: $senderName)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isSending)
                    TextField("Subject", text: $mailSubjectTemplate)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isSending)
                    TextEditor(text: $mailBodyTemplate)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(height: 190)
                        .padding(6)
                        .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor)))
                        .disabled(isSending)
                    Text("Fields: {greeting} · {name} · {callsign} · {bands} · {my_name} · {my_callsign} / {my_call} · {my_grid} · {my_qth} · {my_location} · {time_window}")
                        .font(.caption2).foregroundStyle(.secondary)
                    Toggle("Propose daily availability", isOn: $includeTimeWindow)
                        .font(.caption.bold())
                        .disabled(isSending)
                    if includeTimeWindow {
                        Text("Choose the first and last day, then your available hours each day in local time (\(TimeZone.current.abbreviation(for: timeStart) ?? TimeZone.current.identifier)).")
                            .font(.caption2).foregroundStyle(.secondary)
                        DatePicker("First day · daily start", selection: $timeStart, displayedComponents: [.date, .hourAndMinute])
                            .disabled(isSending)
                        DatePicker("Last day · daily end", selection: $timeEnd, displayedComponents: [.date, .hourAndMinute])
                            .disabled(isSending)
                        Text("Local: each day, \(localTimeDescription(timeStart)) through \(localTimeDescription(timeEnd))")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(utcTimeWindow ?? "")
                            .font(.caption2).foregroundStyle(.cyan)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Restore friendly default") {
                        mailSubjectTemplate = SKEDMailTemplate.defaultSubject
                        mailBodyTemplate = SKEDMailTemplate.defaultBody
                    }
                    .font(.caption)
                    .disabled(isSending)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Personalized preview").font(.headline)
                        Spacer()
                        if selection.operators.count > 1 {
                            Picker("Operator", selection: $previewCallsign) {
                                ForEach(selection.operators) { item in
                                    Text(item.callsign).tag(item.callsign)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 130)
                        }
                    }
                    Text("To: \(preview.name ?? preview.callsign) <\(preview.validEmail ?? "no email")>")
                        .font(.caption)
                        .textSelection(.enabled)
                    Text(selection.operators.count == 1
                         ? "Bands for \(preview.callsign)"
                         : "Bands for all \(selection.operators.count) recipients")
                        .font(.caption.bold())
                    Text("Preview: \(bandPlans[preview.callsign, default: []].isEmpty ? "Choose below" : SKEDMailTemplate.bandPhrase(bandPlans[preview.callsign] ?? []))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 5)], spacing: 5) {
                        ForEach(SKEDMailTemplate.bands, id: \.self) { band in
                            let chosen = selection.operators.allSatisfy { bandPlans[$0.callsign, default: []].contains(band) }
                            Button(band) {
                                if selection.operators.count == 1 {
                                    toggleBand(band, for: preview.callsign)
                                } else {
                                    toggleBand(band, for: selection.operators)
                                }
                            }
                                .buttonStyle(.plain)
                                .disabled(isSending)
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(chosen ? Color.accentColor.opacity(0.23) : Color.secondary.opacity(0.08),
                                            in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(chosen ? Color.accentColor : .clear, lineWidth: 1))
                        }
                    }
                    Divider()
                    Text(renderedSubject(for: preview))
                        .font(.subheadline.bold())
                        .textSelection(.enabled)
                    ScrollView {
                        Text(renderedBody(for: preview))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 150)
                    .padding(12)
                    .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    if selection.operators.count > 1 || !sendErrors.isEmpty {
                        Divider()
                        Text("Individual delivery").font(.caption.bold())
                        ScrollView {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(selection.operators) { item in
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(item.callsign).font(.caption.bold()).frame(width: 75, alignment: .leading)
                                            Text(item.name ?? item.callsign)
                                                .font(.caption).lineLimit(1)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                            Text(SKEDMailTemplate.bandPhrase(bandPlans[item.callsign] ?? []))
                                                .font(.caption).lineLimit(1)
                                                .frame(maxWidth: 125, alignment: .trailing)
                                            Spacer()
                                            if let sent = sendResults[item.callsign] {
                                                Image(systemName: sent ? "checkmark.circle.fill" : "xmark.circle.fill")
                                                    .foregroundStyle(sent ? Color.green : Color.red)
                                            }
                                        }
                                        if let error = sendErrors[item.callsign] {
                                            Text(error).font(.caption2).foregroundStyle(.red)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(height: 105)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            if let issue {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            let conflicts = pending.compactMap { item -> (SKEDOperator, EmailHistoryEntry)? in
                guard let latest = conflictingSKED(for: item).first else { return nil }
                return (item, latest)
            }
            if !conflicts.isEmpty && !isSending {
                VStack(alignment: .leading, spacing: 5) {
                    Label("Review previous SKED emails before sending again", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.bold()).foregroundStyle(.orange)
                    ForEach(Array(conflicts.indices.prefix(3)), id: \.self) { index in
                        let item = conflicts[index].0
                        let previous = conflicts[index].1
                        Text("\(item.callsign): sent \(previous.date.formatted(date: .abbreviated, time: .shortened)) · \(previous.sked?.schedule?.shortDescription ?? "planned days unknown")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if conflicts.count > 3 {
                        Text("And \(conflicts.count - 3) more recipients. Open history to review them.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack {
                        Toggle("Send again despite overlap or unknown dates", isOn: $allowOverlappingSKED)
                            .font(.caption)
                            .disabled(isSending)
                        Spacer()
                        Button("View sent history") {
                            showComposerHistory = true
                        }
                        .popover(isPresented: $showComposerHistory, arrowEdge: .bottom) {
                            SKEDMailHistoryView(entries: SKEDMailHistory.successfulEntries(appState.emailHistory),
                                                destinationKey: destinationKey,
                                                initialCallsign: conflicts.count == 1 ? conflicts[0].0.callsign : "")
                        }
                    }
                }
                .padding(10)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }
            if !historySaveWarnings.isEmpty {
                Label("Email sent, but local history could not be saved for \(historySaveWarnings.sorted().joined(separator: ", ")). Do not resend without checking your mailbox.",
                      systemImage: "externaldrive.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.orange)
            }
            if isSending {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Sending to \(sendingCallsign)…")
                    Spacer()
                    Button("Stop after this email") { cancelSending = true }
                        .disabled(cancelSending)
                }
            } else if !sendResults.isEmpty {
                Text("\(sendResults.values.filter { $0 }.count) sent · \(sendResults.values.filter { !$0 }.count) not sent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(sendResults.values.contains(false) ? .orange : .green)
            }
            HStack {
                Spacer()
                Button("Close") { composeSelection = nil }
                    .disabled(isSending)
                Button("Send \(eligibleCount) email\(eligibleCount == 1 ? "" : "s")" +
                       (eligibleCount < pending.count ? " · skip \(pending.count - eligibleCount) overlap" : "")) {
                    Task { await sendComposed(selection) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || eligibleCount == 0 || issue != nil)
            }
        }
        .padding(22)
        .frame(width: 1000, height: 760)
        .interactiveDismissDisabled(isSending)
    }

    private func sendComposed(_ selection: SKEDComposeSelection) async {
        guard sendIssue(for: selection) == nil, !isSending else { return }
        let schedule = proposedSchedule
        let stationCallsign = appState.activeStationProfile?.normalizedCallsign ?? ""
        let destination = destinationKey
        let destinationName = destinationTitle
        let messages = selection.operators
            .filter { sendResults[$0.callsign] != true }
            .compactMap { item -> SKEDPreparedEmail? in
                guard let email = item.validEmail else { return nil }
                let body = renderedBody(for: item)
                return SKEDPreparedEmail(callsign: item.callsign, email: email,
                                         subject: renderedSubject(for: item), body: body,
                                         details: SKEDMailDetails(recipientName: item.name,
                                            senderCallsign: stationCallsign, destinationKey: destination,
                                            destinationName: destinationName, body: body,
                                            bands: SKEDMailTemplate.ordered(bandPlans[item.callsign, default: []]),
                                            schedule: schedule))
            }
        isSending = true
        cancelSending = false
        for message in messages {
            if cancelSending { break }
            if !allowOverlappingSKED,
               !SKEDMailHistory.conflicts(for: message.callsign, email: message.email,
                                          schedule: schedule, in: appState.emailHistory).isEmpty {
                sendResults[message.callsign] = false
                sendErrors[message.callsign] = "An overlapping SKED email was already sent to this callsign or address. Review its history before retrying."
                continue
            }
            sendingCallsign = message.callsign
            let result: (Bool, String) = await withCheckedContinuation { continuation in
                appState.sendEmail(to: message.email, subject: message.subject, body: message.body,
                                   callsign: message.callsign, historyKind: "SKED",
                                   skedDetails: message.details, playSound: false) { ok, detail in
                    continuation.resume(returning: (ok, detail))
                }
            }
            let success = result.0
            sendResults[message.callsign] = success
            if success {
                sendErrors.removeValue(forKey: message.callsign)
                if result.1.hasPrefix("HISTORY SAVE FAILED:") {
                    historySaveWarnings.insert(message.callsign)
                }
            } else {
                sendErrors[message.callsign] = result.1
                if [5, 6, 7, 28, 35, 51, 58, 60, 67].contains(Int(result.1.split(separator: ":").first?.dropFirst(6) ?? "") ?? -1) {
                    break
                }
            }
            if !cancelSending {
                try? await Task.sleep(for: .milliseconds(750))
            }
        }
        sendingCallsign = ""
        isSending = false
        if selection.operators.allSatisfy({ sendResults[$0.callsign] == true }) {
            sendSuccessCount = selection.operators.count
            notice = historySaveWarnings.isEmpty
                ? "Sent \(sendSuccessCount) personalized SKED email\(sendSuccessCount == 1 ? "" : "s") successfully."
                : "Emails sent, but local history was not saved for \(historySaveWarnings.sorted().joined(separator: ", ")). Check your mailbox before sending again."
            selectedCallsigns.subtract(Set(selection.operators.map(\.callsign)))
            composeSelection = nil
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                showSendSuccess = true
            }
        }
    }

    private func exportCSV() {
        guard let directory, !directory.operators.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "Export SKED directory"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "SKED_\(destinationKey.uppercased().replacingOccurrences(of: ":", with: "_"))_top19_\(category).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try directory.csv(locationName: destinationTitle).write(to: url, options: .atomic)
            notice = "CSV saved to \(url.lastPathComponent)."
        } catch {
            errorMessage = "Could not save CSV: \(error.localizedDescription)"
        }
    }
}
