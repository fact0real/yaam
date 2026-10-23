import SwiftUI

struct SKEDContactDiscoveryView: View {
    @Environment(\.dismiss) private var dismiss
    let geography: SKEDGeographyCatalog?
    let localContacts: [SKEDDiscoveryContact]
    var countryHistory = SKEDCountryBandHistory()
    var usesLocalCatalog = false
    var logChanged = false
    var logSnapshotRevision = 0
    let token: String?
    let userAgent: String
    var stationCallsign: String = ""
    let onPrepare: ([SKEDDiscoveryContact], Set<String>) -> Void
    @State private var continent = "EU"
    @State private var country = ""
    @State private var bands: Set<String> = ["10m"]
    @State private var contacts: [SKEDDiscoveryContact] = []
    @State private var latestLogContacts: [SKEDDiscoveryContact] = []
    @State private var selected: Set<String> = []
    @State private var unworkedOnly = true
    @State private var historyOnly = false
    @State private var contactsPerCountry = 10
    @State private var countryStatuses: [String: SKEDCountryLoadStatus] = [:]
    @State private var expandedCountries: Set<String> = []
    @State private var query = ""
    @State private var loading = false
    @State private var progress = ""
    @State private var failures: [String] = []
    @State private var searched = false
    @State private var editingCriteria = false
    @State private var searchGeneration = UUID()
    @State private var searchTask: Task<Void, Never>?

    private var countries: [SKEDCountryOption] {
        (geography?.countries ?? []).filter { SKEDContactDiscovery.continent(for: $0) == continent }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
    private var targets: [SKEDCountryOption] {
        countryHistory.targets(countries: countries.filter { country.isEmpty || $0.iso == country },
                               bands: bands, unworkedOnly: unworkedOnly)
    }
    private var eligibleContacts: [SKEDDiscoveryContact] {
        SKEDContactDiscovery.filtered(contacts, bands: bands, historyOnly: historyOnly, query: "")
    }
    private var groups: [SKEDCountrySuggestions] {
        SKEDCountryDiscovery.suggestions(countries: targets, contacts: eligibleContacts, limit: contactsPerCountry,
                                         query: query, stationCallsign: stationCallsign)
    }
    private var visible: [SKEDDiscoveryContact] { groups.flatMap(\.contacts) }
    private var allSuggestions: [SKEDDiscoveryContact] {
        SKEDCountryDiscovery.suggestions(countries: targets, contacts: eligibleContacts, limit: Int.max,
            query: "", stationCallsign: stationCallsign).flatMap(\.contacts)
    }
    private var chosen: [SKEDDiscoveryContact] { allSuggestions.filter { selected.contains($0.id) } }
    private var selectedCountryCount: Int { Set(chosen.map(\.countryISO)).count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "globe.europe.africa.fill").font(.largeTitle).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Find your next SKED").font(.title2.bold())
                    Text("Choose where and on which bands you’d like to meet.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if logChanged {
                        Label("Updating country history from your latest log… Your search will be ready automatically.", systemImage: "arrow.clockwise.circle")
                            .foregroundStyle(.orange)
                    }
                    if searched {
                        DisclosureGroup(isExpanded: $editingCriteria) {
                            searchControls.padding(.top, 10)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(targets.count) countries · \(SKEDMailTemplate.bandPhrase(bands))")
                                    .font(.headline)
                                Text("\(unworkedOnly ? "No logged QSO on selected bands" : "All countries") · Edit search settings")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else { searchControls }
                    if loading {
                        HStack { ProgressView().controlSize(.small); Text(progress); Spacer(); Button("Stop") { stop(); failures.append("Search stopped by you; results loaded so far are shown") } }
                    }
                    if !failures.isEmpty {
                        Label("\(failures.joined(separator: "; ")). Loaded results are shown. Search again to retry.", systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange)
                    }
                    if searched { results }
                    else {
                        ContentUnavailableView("A personal invitation starts here", systemImage: "envelope.badge.person.crop",
                            description: Text("Search your log and the SKED directory, select contacts, then review a personalized invitation."))
                            .frame(maxWidth: .infinity, minHeight: 170)
                    }
                }.padding(20)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(chosen.count) selected · \(selectedCountryCount) \(selectedCountryCount == 1 ? "country" : "countries") · \(SKEDMailTemplate.bandPhrase(bands))").font(.callout.bold())
                    Text(searched ? "Review each invitation before sending." : "Choose your destination and bands, then find contacts.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !searched || editingCriteria {
                    Button { search() } label: { Label("Find contacts", systemImage: "magnifyingglass") }
                        .buttonStyle(.borderedProminent).disabled(loading || targets.isEmpty || logChanged)
                } else {
                    Button { onPrepare(chosen, bands); dismiss() } label: {
                        Label("Prepare invitations", systemImage: "square.and.pencil")
                    }.buttonStyle(.borderedProminent).disabled(chosen.isEmpty || bands.isEmpty || logChanged)
                }
            }.padding(16)
        }
        .frame(minWidth: 700, idealWidth: 880, minHeight: 440, idealHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            latestLogContacts = localContacts
            if !countries.contains(where: { $0.iso == country }) { country = "" }
        }
        .onChange(of: continent) { _, _ in country = ""; reset() }
        .onChange(of: country) { _, _ in reset() }
        .onChange(of: bands) { _, _ in reset() }
        .onChange(of: unworkedOnly) { _, _ in historyOnly = false; reset() }
        .onChange(of: historyOnly) { _, _ in reconcileSelection() }
        .onChange(of: contactsPerCountry) { _, _ in reconcileSelection() }
        .onChange(of: logSnapshotRevision) { _, _ in
            latestLogContacts = localContacts
            if searched {
                let allowed = Set(targets.map(\.iso))
                contacts = SKEDContactDiscovery.merge(localContacts.filter { allowed.contains($0.countryISO) }
                    + contacts.filter { $0.sources.contains("QRZ Rank") && allowed.contains($0.countryISO) })
                reconcileSelection()
            }
        }
        .onChange(of: logChanged) { _, changed in if changed { stop(); selected = [] } }
        .onDisappear { stop() }
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            if usesLocalCatalog {
                Label("Country list is limited to places in your log. Load the QRZ Rank country catalog to include countries you have never worked.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Label("1  Choose your destination", systemImage: "location.circle.fill").font(.headline)
            HStack(spacing: 14) {
                Picker("Continent", selection: $continent) {
                    ForEach(SKEDContactDiscovery.continents, id: \.0) { item in Text(item.1).tag(item.0) }
                }
                Picker("Country", selection: $country) {
                    Text("All countries in continent").tag("")
                    ForEach(countries) { Text($0.menuTitle).tag($0.iso) }
                }
            }
            Label("2  Choose one or more bands", systemImage: "antenna.radiowaves.left.and.right").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68))], spacing: 8) {
                ForEach(SKEDMailTemplate.bands, id: \.self) { band in
                    Button {
                        if !bands.insert(band).inserted { bands.remove(band) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: bands.contains(band) ? "checkmark.circle.fill" : "circle")
                            Text(band).monospacedDigit()
                        }.frame(maxWidth: .infinity).padding(.vertical, 5)
                    }.buttonStyle(.bordered).tint(bands.contains(band) ? .accentColor : .secondary)
                        .accessibilityLabel("\(band), \(bands.contains(band) ? "selected" : "not selected")")
                }
            }
            Toggle("Only countries with no logged QSO on any selected band", isOn: $unworkedOnly)
                .font(.callout.weight(.medium))
            HStack {
                Stepper("Up to \(contactsPerCountry) operators per country", value: $contactsPerCountry, in: 1...50)
                    .fixedSize().disabled(loading)
                Spacer()
                Text("\(targets.count) matching countries").font(.callout.bold()).foregroundStyle(Color.accentColor)
            }
            if unworkedOnly {
                Text("Every QSO counts, including unconfirmed contacts and entries without email. With several bands selected, a country must have no recorded QSO on any of them.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !targets.isEmpty {
                DisclosureGroup("Preview \(targets.count) countries") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 8) {
                        ForEach(targets) { destination in
                            Text(destination.menuTitle)
                                .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.top, 8)
                }
            } else if !bands.isEmpty && !countries.isEmpty {
                Label("No countries match these bands. Choose different bands or turn off the country history filter.", systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text("Request these bands in your invitation. Band history is shown below; confirm current availability with the operator.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if bands.isEmpty { Text("Choose at least one band.").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Text("Your log + QRZ Rank directory").font(.caption).foregroundStyle(.secondary)
            }
            if geography == nil || countries.isEmpty {
                Label("No countries available here. Choose another continent or load the country catalog on the SKED page and reopen search.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16).background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { resultHeading; Spacer(); selectSuggestionsButton }
                VStack(alignment: .leading, spacing: 8) { resultHeading; selectSuggestionsButton }
            }
            TextField("Search country, callsign, name or email", text: $query).textFieldStyle(.roundedBorder)
            if !unworkedOnly {
                Toggle("Only operators previously worked on any selected band", isOn: $historyOnly).font(.callout).disabled(loading)
            }
            Text("You can select and prepare available contacts while other countries load. Up to \(contactsPerCountry) suggestions per country, drawn from your log and up to three top-19 directory rankings. Availability on \(SKEDMailTemplate.bandPhrase(bands)) still needs the operator’s agreement.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if countryHistory.unresolvedCount > 0 {
                Label("\(countryHistory.unresolvedCount) log entries have an unresolved country and could not be checked.", systemImage: "questionmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if groups.isEmpty {
                ContentUnavailableView("No matching countries", systemImage: "globe.europe.africa",
                    description: Text("Clear the text search or change the destination and bands."))
            }
            LazyVStack(spacing: 12) {
                ForEach(groups) { group in countrySection(group) }
            }
        }
    }

    private var resultHeading: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("Countries to contact", systemImage: "globe.europe.africa.fill").font(.headline)
            Text("\(groups.count) countries · \(visible.count) suggestions with email").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var selectSuggestionsButton: some View {
        HStack {
            Button("Select up to \(contactsPerCountry) per country") { select(visible) }
                .disabled(visible.isEmpty || logChanged)
            Button("Clear (\(selected.count))") { selected = [] }
                .disabled(selected.isEmpty)
        }
    }

    private func countrySection(_ group: SKEDCountrySuggestions) -> some View {
        let status = countryStatuses[group.id]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(SKEDCountryDiscovery.flag(for: group.id)).font(.title2).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.country.displayName).font(.headline)
                    Label(unworkedOnly ? "No logged \(SKEDMailTemplate.bandPhrase(bands)) QSO" : "\(group.availableCount) contacts with email",
                          systemImage: unworkedOnly ? "sparkles" : "person.2")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(group.contacts.count) of \(contactsPerCountry) suggested").font(.callout.bold())
                    Text(status?.title ?? (loading ? "Waiting for directory…" : "Directory not checked"))
                        .font(.caption2).foregroundStyle(status == .failed || status == .partial ? Color.orange : Color.secondary)
                }
                if !group.contacts.isEmpty {
                    Button("Select \(group.contacts.count)") { select(group.contacts) }
                        .controlSize(.small).disabled(logChanged)
                }
            }
            if let missing = countryHistory.missingBandCounts[group.id], missing > 0 {
                Label("Band missing from \(missing) historical QSO\(missing == 1 ? "" : "s"). Check before assuming a new band.", systemImage: "questionmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if group.contacts.isEmpty {
                Text(emptyCountryMessage(status)).font(.caption).foregroundStyle(.secondary)
            } else {
                DisclosureGroup(isExpanded: Binding(get: { expandedCountries.contains(group.id) }, set: {
                    if $0 { expandedCountries.insert(group.id) } else { expandedCountries.remove(group.id) }
                })) {
                    LazyVStack(spacing: 8) { ForEach(group.contacts) { contact in contactRow(contact) } }.padding(.top, 8)
                } label: {
                    Text("View operators · \(group.contacts.prefix(3).map(\.id).joined(separator: ", "))")
                        .font(.caption).lineLimit(1)
                }
            }
        }.padding(14).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor.opacity(0.14)))
    }

    private func emptyCountryMessage(_ status: SKEDCountryLoadStatus?) -> String {
        switch status {
        case .complete: return "No public email is ready for this country yet. It remains on your target list; the server prepares directory profiles in the background."
        case .suggested: return "Suggestions have been loaded for this country."
        case .failed, .partial: return "The directory could not be fully checked. This does not mean no operators are available."
        case .loading: return "Looking for operators with email…"
        case .stopped: return "Search stopped before this directory check was completed. Search again to retry."
        case nil: return "No local email contacts. The directory has not been checked for this country yet."
        }
    }

    private func contactRow(_ contact: SKEDDiscoveryContact) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("Select \(contact.id)", isOn: Binding(get: { selected.contains(contact.id) }, set: {
                if $0 { select([contact]) } else { selected.remove(contact.id) }
            })).labelsHidden().disabled(logChanged ||
                (!selected.contains(contact.id) && chosen.filter { $0.countryISO == contact.countryISO }.count >= contactsPerCountry))
            VStack(alignment: .leading, spacing: 3) {
                Text(contact.id).font(.callout.bold()).foregroundStyle(Color.accentColor)
                Text(contact.operatorInfo.name ?? "Name unavailable").font(.caption)
                Text(contact.operatorInfo.validEmail ?? "").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 4) {
                let observed = contact.workedBands.intersection(bands)
                Label(observed.isEmpty ? "Availability to confirm" : "Worked: \(SKEDMailTemplate.bandPhrase(observed))",
                      systemImage: observed.isEmpty ? "questionmark.circle" : "checkmark.circle").font(.caption)
                Text(contact.sources.sorted().joined(separator: " + ")).font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(10).background(selected.contains(contact.id) ? Color.accentColor.opacity(0.10) : Color.clear,
                                 in: RoundedRectangle(cornerRadius: 9))
    }

    private func select(_ candidates: [SKEDDiscoveryContact]) {
        selected = SKEDCountryDiscovery.selecting(candidates, current: selected, pool: allSuggestions, limit: contactsPerCountry)
    }
    private func reconcileSelection() { select([]) }
    private func stop() {
        searchGeneration = UUID()
        searchTask?.cancel()
        for (iso, status) in countryStatuses where status == .loading { countryStatuses[iso] = .stopped }
        loading = false
        progress = ""
    }
    private func reset() { stop(); contacts = []; selected = []; failures = []; countryStatuses = [:]; expandedCountries = []; searched = false }

    private func search() {
        stop()
        guard !logChanged, !targets.isEmpty else { return }
        let generation = searchGeneration
        let destinations = targets
        countryStatuses = [:]
        expandedCountries = Set(destinations.prefix(1).map(\.iso))
        let allowed = Set(destinations.map(\.iso))
        contacts = SKEDContactDiscovery.merge(localContacts.filter { allowed.contains($0.countryISO) })
        selected = []; failures = []; loading = true; searched = true; editingCriteria = false
        progress = "Loading prepared contacts for \(destinations.count) countries…"
        let searchToken = token
        let agent = userAgent
        let logContacts = latestLogContacts
        searchTask = Task { @MainActor in
            do {
                let prepared = try await SKEDDirectoryService.shared.fetchPrepared(countries: destinations.map(\.iso),
                    token: searchToken, userAgent: agent)
                try Task.checkCancellation()
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    try SKEDDiscoveryLoader.prepared(countries: destinations, directories: prepared, localContacts: logContacts)
                }.value
                guard !Task.isCancelled, generation == searchGeneration else { return }
                contacts = SKEDContactDiscovery.merge(latestLogContacts.filter { allowed.contains($0.countryISO) }
                    + snapshot.contacts.filter { $0.sources.contains("QRZ Rank") })
                failures = snapshot.failures
                progress = snapshot.progress
                countryStatuses = snapshot.countryStatuses
            } catch {
                if !Task.isCancelled, generation == searchGeneration { failures = [error.localizedDescription] }
            }
            guard !Task.isCancelled, generation == searchGeneration else { return }
            loading = false
            progress = ""
        }
    }
}
