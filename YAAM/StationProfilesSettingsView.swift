//
//  StationProfilesSettingsView.swift
//  YAAM
//

import SwiftUI

struct StationProfilesSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedProfileID: UUID?
    @State private var draft = StationProfile()
    @State private var original = StationProfile()
    @State private var qrzAPIKey = ""
    @State private var statusMessage = ""
    @State private var profileToDelete: StationProfile?

    private var isDirty: Bool {
        draft != original || !qrzAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HSplitView {
            profileSidebar
                .frame(minWidth: 205, idealWidth: 225, maxWidth: 260)
            profileEditor
                .frame(minWidth: 520)
        }
        .onAppear {
            let initial = appState.activeStationProfile ?? appState.stationProfiles.first
            if let initial { selectProfile(initial) }
        }
        .alert("Delete Station Profile?", isPresented: Binding(
            get: { profileToDelete != nil },
            set: { if !$0 { profileToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { profileToDelete = nil }
            Button("Delete", role: .destructive) { deleteSelectedProfile() }
        } message: {
            Text("Only an inactive profile with no QSOs can be deleted. Credentials stored for that profile will also be removed.")
        }
    }

    private var profileSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Stations")
                    .font(.headline)
                Spacer()
                Text(appState.stationProfiles.count.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(12)

            Divider()

            List(appState.stationProfiles) { profile in
                Button {
                    saveBeforeChangingSelection(to: profile)
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: profile.id == appState.activeStationProfileID ? "dot.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                            .foregroundStyle(profile.id == appState.activeStationProfileID ? .green : .secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Text(profile.normalizedCallsign)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(selectedProfileID == profile.id ? Color.accentColor.opacity(0.14) : Color.clear)
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 8) {
                Button {
                    startNewProfile()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add station profile")

                Button {
                    duplicateSelectedProfile()
                } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .disabled(selectedProfileID == nil)
                .help("Duplicate selected profile")

                Button(role: .destructive) {
                    profileToDelete = appState.stationProfiles.first { $0.id == selectedProfileID }
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedProfileID == nil || selectedProfileID == appState.activeStationProfileID)
                .help("Delete selected profile")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private var profileEditor: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.name.isEmpty ? "New Station" : draft.name)
                        .font(.title3.weight(.semibold))
                    Text(draft.normalizedCallsign.isEmpty ? "Complete the station identity" : draft.normalizedCallsign)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()

                if selectedProfileID == appState.activeStationProfileID {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else if selectedProfileID != nil {
                    Button {
                        activateDraft()
                    } label: {
                        Label("Make Active", systemImage: "dot.radiowaves.left.and.right")
                    }
                }

                Button {
                    saveDraft()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isDirty && selectedProfileID != nil)
            }
            .padding(14)

            Divider()

            ScrollView {
                Form {
                    Section("Identity") {
                        TextField("Profile name", text: $draft.name)
                        TextField("Station callsign", text: $draft.callsign)
                        TextField("QTH", text: $draft.qth)
                        TextField("Country", text: $draft.country)
                    }

                    Section("Location") {
                        TextField("Grid Locator", text: $draft.grid)
                        HStack {
                            TextField("Latitude", text: $draft.latitude)
                            TextField("Longitude", text: $draft.longitude)
                        }
                        HStack {
                            TextField("DXCC code", text: $draft.dxccCode)
                            TextField("CQ zone", text: $draft.cqZone)
                            TextField("ITU zone", text: $draft.ituZone)
                        }
                    }

                    Section("Radio & Antenna") {
                        TextField("Radio model", text: $draft.radioModel)
                        Stepper("Power: \(draft.powerWatts) W", value: $draft.powerWatts, in: 1...1500, step: 5)
                        TextField("Antenna", text: $draft.antennaDescription)
                        Stepper("Antenna height: \(draft.antennaHeightMeters) m", value: $draft.antennaHeightMeters, in: 0...500)
                    }

                    Section("Validity") {
                        Toggle("Start date", isOn: optionalDateBinding(\.validFrom))
                        if draft.validFrom != nil {
                            DatePicker("Valid from", selection: dateBinding(\.validFrom), displayedComponents: .date)
                        }
                        Toggle("End date", isOn: optionalDateBinding(\.validTo))
                        if draft.validTo != nil {
                            DatePicker("Valid through", selection: dateBinding(\.validTo), displayedComponents: .date)
                        }
                    }

                    Section("Service Identity") {
                        TextField("LoTW station location", text: $draft.lotwStationLocation)
                        TextField("eQSL QTH nickname", text: $draft.eqslQTHNickname)
                        SecureField("New QRZ Logbook API key (blank keeps the saved key)", text: $qrzAPIKey)
                        Label("The existing key is not read when Settings opens. Enter a new value only to replace it for this station.", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }

            if !statusMessage.isEmpty {
                Divider()
                HStack {
                    Image(systemName: statusMessage.hasPrefix("Saved") ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    Text(statusMessage)
                        .lineLimit(2)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(statusMessage.hasPrefix("Saved") ? .green : .orange)
                .padding(10)
            }
        }
    }

    private func optionalDateBinding(_ keyPath: WritableKeyPath<StationProfile, Date?>) -> Binding<Bool> {
        Binding(
            get: { draft[keyPath: keyPath] != nil },
            set: { enabled in draft[keyPath: keyPath] = enabled ? (draft[keyPath: keyPath] ?? Date()) : nil }
        )
    }

    private func dateBinding(_ keyPath: WritableKeyPath<StationProfile, Date?>) -> Binding<Date> {
        Binding(
            get: { draft[keyPath: keyPath] ?? Date() },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }

    private func saveBeforeChangingSelection(to profile: StationProfile) {
        if isDirty, !saveDraft(showSuccess: false) { return }
        selectProfile(profile)
    }

    private func selectProfile(_ profile: StationProfile) {
        selectedProfileID = profile.id
        draft = profile
        original = profile
        qrzAPIKey = ""
        statusMessage = ""
    }

    private func startNewProfile() {
        if isDirty, !saveDraft(showSuccess: false) { return }
        selectedProfileID = nil
        draft = appState.makeNewStationProfile()
        original = draft
        qrzAPIKey = ""
        statusMessage = "Enter a unique name and the operating callsign, then save."
    }

    @discardableResult
    private func saveDraft(showSuccess: Bool = true) -> Bool {
        do {
            let cleanKey = qrzAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            try appState.saveStationProfile(draft, qrzAPIKey: cleanKey.isEmpty ? nil : cleanKey)
            if let saved = appState.stationProfiles.first(where: { $0.id == draft.id }) {
                selectedProfileID = saved.id
                draft = saved
                original = saved
            }
            qrzAPIKey = ""
            statusMessage = showSuccess ? "Saved securely." : ""
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    private func activateDraft() {
        guard saveDraft(showSuccess: false),
              let profile = appState.stationProfiles.first(where: { $0.id == draft.id }) else { return }
        do {
            try appState.activateStationProfile(profile)
            statusMessage = "Saved and activated. The Master Log now shows this station."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func duplicateSelectedProfile() {
        guard let profile = appState.stationProfiles.first(where: { $0.id == selectedProfileID }) else { return }
        do {
            let copy = try appState.duplicateStationProfile(profile)
            selectProfile(copy)
            statusMessage = "Duplicate created. Review its identity before activation."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func deleteSelectedProfile() {
        guard let profile = profileToDelete else { return }
        do {
            try appState.deleteStationProfile(profile)
            profileToDelete = nil
            if let fallback = appState.activeStationProfile ?? appState.stationProfiles.first {
                selectProfile(fallback)
            }
        } catch {
            profileToDelete = nil
            statusMessage = error.localizedDescription
        }
    }
}
