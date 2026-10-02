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
}

private struct SKEDCountryChoice: Identifiable {
    let iso: String
    let title: String
    var id: String { iso }
}

struct SKEDDirectoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var countryISO = "ir"
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
    @State private var composeSelection: SKEDComposeSelection?
    @State private var previewCallsign = ""
    @State private var showSMTPSettings = false
    @State private var smtpConfigured = false
    @State private var isSending = false
    @State private var cancelSending = false
    @State private var sendingCallsign = ""
    @State private var sendResults: [String: Bool] = [:]
    @State private var sendErrors: [String: String] = [:]
    @State private var skedSentCalls: Set<String> = []
    @State private var countryChoices: [SKEDCountryChoice] = []
    @State private var mailSubjectTemplate = SKEDMailTemplate.defaultSubject
    @State private var mailBodyTemplate = SKEDMailTemplate.defaultBody

    private var countries: [QRZCountrySummary] {
        var byISO: [String: QRZCountrySummary] = [:]
        for country in appState.qrzRankCountries where country.iso.count == 2 {
            let iso = country.iso.lowercased()
            byISO[iso] = QRZCountrySummary(
                iso: iso, name: fullCountryName(for: iso, fallback: country.name),
                stationCount: country.stationCount)
        }
        let available = byISO.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !available.isEmpty { return available }
        return Locale.Region.isoRegions.map(\.identifier).filter { $0.count == 2 }.compactMap { iso -> QRZCountrySummary? in
            guard let name = Locale(identifier: "en_US").localizedString(forRegionCode: iso) else { return nil }
            return QRZCountrySummary(iso: iso.lowercased(), name: name)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func fullCountryName(for iso: String, fallback: String) -> String {
        let code = iso.uppercased()
        let localized = Locale(identifier: "en_US").localizedString(forRegionCode: code) ?? ""
        return localized.isEmpty || localized.caseInsensitiveCompare(code) == .orderedSame ? fallback : localized
    }

    private func updateCountryChoices() {
        countryChoices = countries.map { country in
            let prefix = DXCCDatabase.representativePrefix(forISO: country.iso) ?? country.iso.uppercased()
            return SKEDCountryChoice(iso: country.iso.lowercased(),
                                     title: "\(flagForCountryIso(country.iso)) \(country.name) · \(prefix)")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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
        .onAppear {
            appState.fetchQRZRankCountries()
            updateCountryChoices()
            loadBandPlans()
            loadMailTemplate()
        }
        .onChange(of: appState.qrzRankCountries) { _, _ in updateCountryChoices() }
        .onChange(of: mailSubjectTemplate) { _, value in
            UserDefaults.standard.set(value, forKey: "sked.mailSubject.v1")
        }
        .onChange(of: mailBodyTemplate) { _, value in
            UserDefaults.standard.set(value, forKey: "sked.mailBody.v1")
        }
        .onChange(of: countryISO) { _, _ in
            selectedCallsigns.removeAll()
            focusedCallsign = nil
            loadBandPlans()
        }
        .onChange(of: appState.activeStationProfileID) { _, _ in
            selectedCallsigns.removeAll()
            loadBandPlans()
        }
        .task(id: "\(countryISO)-\(category)-\(refreshID)") { await load() }
        .task(id: "\(countryISO)-\(appState.qsoRecordsRevision)") { await updateCountryActivity() }
        .sheet(item: $selectedOperator) { item in
            operatorDetails(item)
        }
        .sheet(item: $composeSelection) { selection in
            composer(selection)
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
            Picker("Country", selection: $countryISO) {
                ForEach(countryChoices) { country in
                    Text(country.title).tag(country.iso)
                }
            }
            .frame(width: 335)

            Picker("Rank by", selection: $category) {
                Text("Confirmed QSOs").tag("qso")
                Text("DXCC countries").tag("countries")
                Text("Band slots").tag("band")
            }
            .frame(width: 235)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                guard let directory else { return }
                selectedCallsigns = Set(directory.operators.compactMap { $0.validEmail == nil ? nil : $0.callsign })
            } label: {
                Label("Select All", systemImage: "checkmark.square")
            }
            .disabled(directory?.emailCount == 0 || directory == nil)
            .help("Select every operator with an email address in this country")

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

    private func summary(_ directory: SKEDDirectory) -> some View {
        HStack(spacing: 16) {
            Text(flagForCountryIso(directory.countryISO))
                .font(.system(size: 36))
            VStack(alignment: .leading, spacing: 3) {
                Text(fullCountryName(for: directory.countryISO, fallback: directory.countryName))
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
                Label("\(fullCountryName(for: directory.countryISO, fallback: directory.countryName)) · band history", systemImage: "waveform.path")
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
                                if skedSentCalls.contains(item.callsign) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                            }
                            Text(item.name ?? "Name unavailable")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
        return "sked.bandPlans.v1.\(station).\(countryISO.lowercased())"
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

    private func suggestBands(for callsign: String) {
        let priority = ["20m", "40m", "17m", "15m", "10m", "30m", "80m", "12m", "160m", "6m", "60m"]
        bandPlans[callsign] = Set(priority.filter { !countryActivity.worked.contains($0) }.prefix(3))
        saveBandPlans()
    }

    private func updateCountryActivity() async {
        let records = appState.qsoRecords
        let iso = countryISO
        let result = await Task.detached(priority: .utility) {
            var countryByCall: [String: String] = [:]
            var entries: [SKEDLogBandEntry] = []
            for record in records {
                let call = record.fields["CALL"] ?? ""
                let country = record.fields["COUNTRY"] ?? ""
                let key = "\(call)|\(country)"
                let resolvedISO: String
                if let cached = countryByCall[key] {
                    resolvedISO = cached
                } else {
                    resolvedISO = DXCCDatabase.resolve(callsign: call, country: country).countryCode
                    countryByCall[key] = resolvedISO
                }
                guard resolvedISO.caseInsensitiveCompare(iso) == .orderedSame else { continue }
                let band = (record.fields["BAND"].flatMap { $0.isEmpty ? nil : $0 }
                            ?? record.fields["FREQ"].flatMap(AmateurBandPlan.band(for:))
                            ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                entries.append(.init(countryISO: resolvedISO, band: band, confirmed: record.isConfirmed))
            }
            return SKEDCountryBandActivity.make(entries: entries, countryISO: iso)
        }.value
        guard !Task.isCancelled else { return }
        countryActivity = result
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func operatorDetails(_ item: SKEDOperator) -> some View {
        let entity = DXCCDatabase.resolve(callsign: item.callsign)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(flagForCountryIso(directory?.countryISO ?? countryISO))
                    .font(.largeTitle)
                VStack(alignment: .leading) {
                    Text(item.callsign).font(.title.bold())
                    Text(directory?.countryName ?? countryISO.uppercased())
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

    private func load() async {
        isLoading = true
        errorMessage = nil
        notice = nil
        directory = nil
        do {
            let token = CredentialVault.value(for: .qrzRankAPIToken)
            let result = try await SKEDDirectoryService.shared.fetch(
                countryISO: countryISO, category: category, enrich: true,
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
        previewCallsign = operators[0].callsign
        sendResults = [:]
        sendErrors = [:]
        cancelSending = false
        sendingCallsign = ""
        composeSelection = SKEDComposeSelection(operators: operators)
    }

    private func loadMailTemplate() {
        if let saved = UserDefaults.standard.string(forKey: "sked.mailSubject.v1") {
            mailSubjectTemplate = saved
        }
        if let saved = UserDefaults.standard.string(forKey: "sked.mailBody.v1") {
            mailBodyTemplate = saved.replacingOccurrences(of: "Hi {greeting},\n\nI hope",
                                                              with: "Hi {greeting} ({callsign}),\n\nI hope")
        }
    }

    private func renderedSubject(for item: SKEDOperator) -> String {
        let station = appState.activeStationProfile
        return SKEDMailTemplate.safeSubject(SKEDMailTemplate.render(
            mailSubjectTemplate, callsign: item.callsign, name: item.name,
            bands: bandPlans[item.callsign, default: []],
            stationCallsign: station?.normalizedCallsign ?? "",
            stationGrid: station?.normalizedGrid ?? "", stationQTH: station?.qth ?? ""))
    }

    private func renderedBody(for item: SKEDOperator) -> String {
        let station = appState.activeStationProfile
        return SKEDMailTemplate.render(
            mailBodyTemplate, callsign: item.callsign, name: item.name,
            bands: bandPlans[item.callsign, default: []],
            stationCallsign: station?.normalizedCallsign ?? "",
            stationGrid: station?.normalizedGrid ?? "", stationQTH: station?.qth ?? "")
    }

    private func sendIssue(for selection: SKEDComposeSelection) -> String? {
        let pending = selection.operators.filter { sendResults[$0.callsign] != true }
        if appState.activeStationProfile?.normalizedCallsign.isEmpty != false {
            return "Choose an active station profile with your callsign before sending."
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
        return nil
    }

    private func composer(_ selection: SKEDComposeSelection) -> some View {
        let preview = selection.operators.first { $0.callsign == previewCallsign }
            ?? selection.operators[0]
        let pending = selection.operators.filter { sendResults[$0.callsign] != true }
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
                    TextField("Subject", text: $mailSubjectTemplate)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isSending)
                    TextEditor(text: $mailBodyTemplate)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(height: 245)
                        .padding(6)
                        .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor)))
                        .disabled(isSending)
                    Text("Fields: {greeting} · {name} · {callsign} · {bands} · {my_callsign} · {my_grid} · {my_qth}")
                        .font(.caption2).foregroundStyle(.secondary)
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
                    Text("Bands: \(bandPlans[preview.callsign, default: []].isEmpty ? "Choose below" : SKEDMailTemplate.bandPhrase(bandPlans[preview.callsign] ?? []))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.cyan)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 5)], spacing: 5) {
                        ForEach(SKEDMailTemplate.bands, id: \.self) { band in
                            let chosen = bandPlans[preview.callsign, default: []].contains(band)
                            Button(band) { toggleBand(band, for: preview.callsign) }
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
                    if selection.operators.count > 1 {
                        Button("Apply these bands to all selected") {
                            let chosen = bandPlans[preview.callsign, default: []]
                            for item in selection.operators { bandPlans[item.callsign] = chosen }
                            saveBandPlans()
                        }
                        .font(.caption)
                        .disabled(isSending || bandPlans[preview.callsign, default: []].isEmpty)
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
                    if selection.operators.count > 1 {
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
            let previouslyEmailed = selection.operators.filter {
                appState.emailHistoryByCallsign[$0.callsign]?.status == "Sent"
                    && sendResults[$0.callsign] != true
            }
            if !previouslyEmailed.isEmpty && !isSending {
                Label("YAAM history shows earlier email to \(previouslyEmailed.map(\.callsign).joined(separator: ", ")). Review before sending again.",
                      systemImage: "clock.arrow.circlepath")
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
                Text("\(sendResults.values.filter { $0 }.count) sent · \(sendResults.values.filter { !$0 }.count) failed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(sendResults.values.contains(false) ? .orange : .green)
            }
            HStack {
                Button("SMTP Settings") { showSMTPSettings = true }
                Spacer()
                Button("Close") { composeSelection = nil }
                    .disabled(isSending)
                Button(pending.count == selection.operators.count
                       ? "Send \(pending.count) individual email\(pending.count == 1 ? "" : "s")"
                       : "Retry \(pending.count) unsent email\(pending.count == 1 ? "" : "s")") {
                    Task { await sendComposed(selection) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || pending.isEmpty || issue != nil)
            }
        }
        .padding(22)
        .frame(width: 980, height: 700)
        .interactiveDismissDisabled(isSending)
        .sheet(isPresented: $showSMTPSettings) {
            SMTPSettingsView(embeddedInSettings: false)
        }
        .onChange(of: showSMTPSettings) { _, showing in
            if !showing { smtpConfigured = appState.isSMTPConfigured }
        }
    }

    private func sendComposed(_ selection: SKEDComposeSelection) async {
        guard sendIssue(for: selection) == nil, !isSending else { return }
        let messages = selection.operators
            .filter { sendResults[$0.callsign] != true }
            .compactMap { item -> SKEDPreparedEmail? in
                guard let email = item.validEmail else { return nil }
                return SKEDPreparedEmail(callsign: item.callsign, email: email,
                                         subject: renderedSubject(for: item), body: renderedBody(for: item))
            }
        isSending = true
        cancelSending = false
        for message in messages {
            if cancelSending { break }
            sendingCallsign = message.callsign
            let success = await withCheckedContinuation { continuation in
                appState.sendEmail(to: message.email, subject: message.subject, body: message.body,
                                   callsign: message.callsign, playSound: false) { ok, _ in
                    continuation.resume(returning: ok)
                }
            }
            sendResults[message.callsign] = success
            if success {
                skedSentCalls.insert(message.callsign)
                sendErrors.removeValue(forKey: message.callsign)
            } else {
                sendErrors[message.callsign] = "Delivery failed. Check YAAM's SMTP settings and network connection."
            }
            if !cancelSending {
                try? await Task.sleep(for: .milliseconds(750))
            }
        }
        sendingCallsign = ""
        isSending = false
    }

    private func exportCSV() {
        guard let directory, !directory.operators.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "Export SKED directory"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "SKED_\(directory.countryISO.uppercased())_top19_\(category).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try directory.csv.write(to: url, options: .atomic)
            notice = "CSV saved to \(url.lastPathComponent)."
        } catch {
            errorMessage = "Could not save CSV: \(error.localizedDescription)"
        }
    }
}
