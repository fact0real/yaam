//
//  WavelogSyncEngine.swift
//  YAAM
//
//  Automated Real-Time & Batch Synchronization Engine for Wavelog / Cloudlog
//  Handles Keychain credentials, remote station profile linking, auto-push on log,
//  two-way batch ADIF synchronization with duplicate detection, and live radio broadcasting.
//

import Combine
import Foundation

@MainActor
public final class WavelogSyncEngine: ObservableObject {
    public static let shared = WavelogSyncEngine()

    // MARK: - Published State
    @Published public var isSyncing: Bool = false
    @Published public var isAutoPushEnabled: Bool = true
    @Published public var isLiveRadioBroadcastEnabled: Bool = false
    @Published public var availableStationProfiles: [WavelogStationProfile] = []
    @Published public var selectedStationProfileID: String = "1"
    @Published public var lastSyncDate: Date? = nil
    @Published public var lastStatusMessage: String = "Ready"
    @Published public var lastError: String? = nil
    @Published public var syncedQSOsCount: Int = 0

    @Published public var serverURL: String = ""
    private var radioBroadcastTimer: Timer?

    public init() {
        reloadSettings()
        self.isLiveRadioBroadcastEnabled = UserDefaults.standard.bool(forKey: "wavelogLiveRadioBroadcastEnabled")

        startRadioBroadcastTimer()
    }

    /// Settings writes these keys through @AppStorage only, so read them again before each use.
    /// Auto-push uses the same default as the Settings toggle (ON) when the key has never been written.
    func reloadSettings() {
        let defaults = UserDefaults.standard
        serverURL = defaults.string(forKey: "wavelogServerURL") ?? ""
        selectedStationProfileID = defaults.string(forKey: "wavelogStationProfileID") ?? "1"
        isAutoPushEnabled = defaults.object(forKey: "wavelogAutoPushEnabled") as? Bool ?? true
    }

    public var isConfigured: Bool {
        let key = CredentialVault.value(for: .wavelogAPIKey)
        return !serverURL.isEmpty && !key.isEmpty
    }

    // MARK: - Station Profiles Discovery

    public func discoverStationProfiles() async {
        reloadSettings()
        let key = CredentialVault.value(for: .wavelogAPIKey)
        guard !serverURL.isEmpty, !key.isEmpty else {
            self.lastError = "Please enter Server URL and API Key"
            return
        }

        self.isSyncing = true
        self.lastStatusMessage = "Connecting to Wavelog / Cloudlog server..."
        self.lastError = nil

        defer { self.isSyncing = false }

        do {
            let profiles = try await WavelogClient.shared.fetchStationProfiles(baseURL: serverURL, apiKey: key)
            self.availableStationProfiles = profiles
            if let first = profiles.first, selectedStationProfileID.isEmpty || selectedStationProfileID == "1" {
                self.selectedStationProfileID = first.stationID
                UserDefaults.standard.set(first.stationID, forKey: "wavelogStationProfileID")
            }
            self.lastStatusMessage = "Connected. Found \(profiles.count) station profile(s)."
        } catch {
            self.lastError = error.localizedDescription
            self.lastStatusMessage = "Connection failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Real-Time Live Auto-Push (Single QSO)

    /// Pushes one QSO and reports what really happened (the zero-click daemon awaits this).
    func pushSingleQSO(record: QSORecordModel) async -> WavelogPushOutcome {
        reloadSettings()
        guard isConfigured, isAutoPushEnabled else { return .notConfigured }
        let outcome = await WavelogClient.shared.pushQSO(
            record: record,
            baseURL: serverURL,
            apiKey: CredentialVault.value(for: .wavelogAPIKey),
            stationProfileID: selectedStationProfileID
        )
        switch outcome {
        case .success:
            syncedQSOsCount += 1
            lastStatusMessage = "Pushed \(record["CALL"]) to Wavelog."
            lastError = nil
        case .duplicate:
            lastStatusMessage = "\(record["CALL"]) is already in Wavelog."
            lastError = nil
        case .notConfigured:
            break
        case .rejected, .networkError:
            lastError = "Auto-push failed for \(record["CALL"]): \(outcome.message)"
        }
        return outcome
    }

    /// Fire-and-forget push for logging paths that do not go through the zero-click daemon.
    func autoPushSingleQSO(record: QSORecordModel) {
        Task { @MainActor [weak self] in
            _ = await self?.pushSingleQSO(record: record)
        }
    }

    // MARK: - Two-Way Batch Synchronization

    func performFullSync(appState: AppState) async {
        reloadSettings()
        guard isConfigured else {
            self.lastError = "Wavelog is not configured in Settings."
            return
        }

        let key = CredentialVault.value(for: .wavelogAPIKey)
        let url = serverURL
        let stationID = selectedStationProfileID

        self.isSyncing = true
        self.lastError = nil
        self.lastStatusMessage = "Starting two-way synchronization with Wavelog..."

        defer {
            self.isSyncing = false
            self.lastSyncDate = Date()
        }

        do {
            // 1. Export local records as batch ADIF and push to Wavelog
            self.lastStatusMessage = "Uploading local QSOs to Wavelog..."
            let dicts = appState.qsoRecords.map { $0.fields }
            let localADIF = generateADIF(originalContent: "", records: dicts)
            if !localADIF.isEmpty {
                let uploadResult = try await WavelogClient.shared.uploadBatchADIF(
                    adifContent: localADIF,
                    baseURL: url,
                    apiKey: key,
                    stationProfileID: stationID
                )
                self.lastStatusMessage = uploadResult.message
            }

            // 2. Pull remote records from Wavelog into YAAM
            self.lastStatusMessage = "Downloading web log from Wavelog..."
            let remoteADIF = try await WavelogClient.shared.exportADIF(
                baseURL: url,
                apiKey: key,
                stationProfileID: stationID
            )

            if !remoteADIF.isEmpty {
                let (_, parsedRecords) = parseADIF(content: remoteADIF)
                var newImportedCount = 0

                // Same station, day, band and mode within 5 minutes is the same QSO (the import review uses the same window)
                let freshRecords = QSOIdentity.newRecords(
                    parsedRecords,
                    existing: appState.qsoRecords.map(\.fields),
                    toleranceSeconds: 300
                )
                for remoteRec in freshRecords {
                    guard !appState.isSelfContact(remoteRec) else { continue }
                    let newModel = QSORecordModel(index: appState.qsoRecords.count + 1, fields: remoteRec)
                    appState.qsoRecords.append(newModel)
                    newImportedCount += 1
                }

                if newImportedCount > 0 {
                    appState.saveCurrentLog()
                }

                self.lastStatusMessage = "Sync complete. \(newImportedCount) new QSOs imported from Wavelog."
            } else {
                self.lastStatusMessage = "Sync complete. All logs up to date."
            }
        } catch {
            self.lastError = error.localizedDescription
            self.lastStatusMessage = "Sync failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Live Radio CAT Telemetry Broadcast

    private func startRadioBroadcastTimer() {
        radioBroadcastTimer?.invalidate()
        radioBroadcastTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.broadcastActiveRadioTelemetry()
            }
        }
    }

    public func broadcastActiveRadioTelemetry() {
        guard isConfigured, isLiveRadioBroadcastEnabled else { return }
        let key = CredentialVault.value(for: .wavelogAPIKey)
        let url = serverURL

        guard FLRigClient.shared.isConnected else { return }
        let freqHz = FLRigClient.shared.frequencyHz
        let mode = FLRigClient.shared.mode
        let radioName = FLRigClient.shared.rigName

        guard freqHz > 0 else { return }

        Task {
            _ = try? await WavelogClient.shared.broadcastRadio(
                baseURL: url,
                apiKey: key,
                radioName: radioName,
                frequencyHz: freqHz,
                mode: mode
            )
        }
    }
}
