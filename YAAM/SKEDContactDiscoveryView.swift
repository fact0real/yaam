import SwiftUI

struct SKEDContactDiscoveryView: View {
    @Environment(\.dismiss) private var dismiss
    let geography: SKEDGeographyCatalog?
    let localContacts: [SKEDDiscoveryContact]
    let token: String?
    let userAgent: String
    var stationCallsign: String = ""
    let onPrepare: ([SKEDDiscoveryContact], Set<String>) -> Void
    @State private var continent = "AS"
    @State private var country = "ir"
    @State private var bands: Set<String> = ["20m"]
    @State private var contacts: [SKEDDiscoveryContact] = []
    @State private var selected: Set<String> = []
    @State private var historyOnly = false
    @State private var query = ""
    @State private var loading = false
    @State private var progress = ""
    @State private var failures: [String] = []
    @State private var searched = false
    @State private var editingCriteria = false
    @State private var searchTask: Task<Void, Never>?

    private var countries: [SKEDCountryOption] {
        (geography?.countries ?? []).filter { SKEDContactDiscovery.continent(for: $0) == continent }
            .sorted { $0.serviceName.localizedStandardCompare($1.serviceName) == .orderedAscending }
    }
    private var visible: [SKEDDiscoveryContact] {
        SKEDContactDiscovery.filtered(contacts, bands: bands, historyOnly: historyOnly, query: query)
            .filter { $0.id != stationCallsign.uppercased() }
    }
    private var chosen: [SKEDDiscoveryContact] { visible.filter { selected.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "globe.badge.chevron.backward").font(.largeTitle).foregroundStyle(Color.accentColor)
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
                    if searched {
                        DisclosureGroup(isExpanded: $editingCriteria) {
                            searchControls.padding(.top, 10)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(country.isEmpty ? "\(SKEDContactDiscovery.continents.first { $0.0 == continent }?.1 ?? continent) · All countries" : countries.first { $0.iso == country }?.serviceName ?? country.uppercased())
                                    .font(.headline)
                                Text("\(SKEDMailTemplate.bandPhrase(bands)) · Edit search settings")
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
                    Text("\(chosen.count) selected · \(SKEDMailTemplate.bandPhrase(bands))").font(.callout.bold())
                    Text("Review each invitation before sending.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { onPrepare(chosen, bands); dismiss() } label: {
                    Label("Prepare invitations", systemImage: "square.and.pencil")
                }.buttonStyle(.borderedProminent).disabled(chosen.isEmpty || bands.isEmpty || loading)
            }.padding(16)
        }
        .frame(minWidth: 700, idealWidth: 880, minHeight: 440, idealHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if !countries.contains(where: { $0.iso == country }) { country = "" }
        }
        .onChange(of: continent) { _, _ in country = ""; reset() }
        .onChange(of: country) { _, _ in reset() }
        .onChange(of: bands) { _, _ in reconcileSelection() }
        .onChange(of: historyOnly) { _, _ in reconcileSelection() }
        .onChange(of: query) { _, _ in reconcileSelection() }
        .onDisappear { searchTask?.cancel() }
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("1  Choose your destination", systemImage: "location.circle.fill").font(.headline)
            HStack(spacing: 14) {
                Picker("Continent", selection: $continent) {
                    ForEach(SKEDContactDiscovery.continents, id: \.0) { item in Text(item.1).tag(item.0) }
                }
                Picker("Country", selection: $country) {
                    Text("All countries in continent").tag("")
                    ForEach(countries) { Text($0.serviceName).tag($0.iso) }
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
            Text("Request these bands in your invitation. Band history is shown below; confirm current availability with the operator.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { search() } label: { Label("Find contacts", systemImage: "magnifyingglass") }
                    .buttonStyle(.borderedProminent).disabled(loading || bands.isEmpty || countries.isEmpty)
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
            HStack {
                Label("3  Select contacts", systemImage: "person.2.fill").font(.headline)
                Spacer()
                Text("\(visible.count) with email").foregroundStyle(.secondary)
                Button(selected.isSuperset(of: Set(visible.map(\.id))) && !visible.isEmpty ? "Clear selection" : "Select visible") {
                    let ids = Set(visible.map(\.id))
                    if selected.isSuperset(of: ids) { selected.subtract(ids) } else { selected.formUnion(ids) }
                }.disabled(visible.isEmpty || loading)
            }
            TextField("Search callsign, name, country or email", text: $query)
                .textFieldStyle(.roundedBorder)
            Toggle("Only contacts previously worked on any selected band", isOn: $historyOnly).font(.callout)
            Text("Shows all matching email contacts in your log plus the service’s top 19 per country and ranking (QSOs, countries and bands), combined without duplicate callsigns. This is not a complete worldwide directory.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if visible.isEmpty {
                ContentUnavailableView("No matching email contacts", systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Try another destination, clear the search, or include contacts whose band availability needs confirmation."))
            }
            LazyVStack(spacing: 8) {
                ForEach(visible) { contact in
                    HStack(alignment: .top, spacing: 12) {
                        Toggle("Select \(contact.id)", isOn: Binding(get: { selected.contains(contact.id) }, set: {
                            if $0 { selected.insert(contact.id) } else { selected.remove(contact.id) }
                        })).labelsHidden().disabled(loading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(contact.id).font(.headline).foregroundStyle(Color.accentColor)
                            Text([contact.operatorInfo.name, contact.countryName].compactMap { $0 }.joined(separator: " · ")).font(.caption)
                            Text(contact.operatorInfo.validEmail ?? "").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer(minLength: 10)
                        VStack(alignment: .trailing, spacing: 4) {
                            let observed = contact.workedBands.intersection(bands)
                            Label(observed.isEmpty ? "Availability to confirm" : "Worked: \(SKEDMailTemplate.bandPhrase(observed))",
                                  systemImage: observed.isEmpty ? "questionmark.circle" : "checkmark.circle")
                                .font(.caption)
                            Text(contact.sources.sorted().joined(separator: " + ")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }.padding(12).background(selected.contains(contact.id) ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    private func reconcileSelection() { selected.formIntersection(Set(visible.map(\.id))) }
    private func stop() { searchTask?.cancel(); loading = false; progress = "" }
    private func reset() { stop(); contacts = []; selected = []; failures = []; searched = false }

    private func search() {
        stop()
        let destinations = countries.filter { country.isEmpty || $0.iso == country }
        let allowed = Set(destinations.map(\.iso))
        contacts = SKEDContactDiscovery.merge(localContacts.filter { allowed.contains($0.countryISO) })
        selected = []; failures = []; loading = true; searched = true; editingCriteria = false
        let searchToken = token
        let agent = userAgent
        searchTask = Task { @MainActor in
            do {
                try await SKEDDiscoveryLoader.load(countries: destinations, localContacts: localContacts,
                    fetch: { iso, category in
                        try await SKEDDirectoryService.shared.fetch(countryISO: iso, category: category,
                            enrich: true, token: searchToken, userAgent: agent)
                    }, update: { snapshot in
                        await MainActor.run {
                            guard !Task.isCancelled else { return }
                            contacts = snapshot.contacts
                            failures = snapshot.failures
                            progress = snapshot.progress
                        }
                    })
            } catch { /* Cancellation preserves already loaded results. */ }
            guard !Task.isCancelled else { return }
            loading = false
            progress = ""
        }
    }
}
