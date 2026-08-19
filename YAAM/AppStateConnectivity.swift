//
//  AppStateConnectivity.swift
//  YAAM
//

import AppKit
import Combine
import Foundation

extension AppState {
    func loadConnectivityState() {
        cloudSyncLastRun = UserDefaults.standard.object(forKey: "cloudSyncLastRun") as? Date
        cloudSyncStatus = cloudSyncFolderURL() == nil ? "Choose an iCloud Drive folder" : "Cloud package ready"
        configureCloudSyncTimer()
        mobileCompanionServer.quickLogHandler = { [weak self] request in
            self?.acceptMobileQuickLog(request)
        }
        mobileCompanionServer.$isRunning
            .combineLatest(mobileCompanionServer.$status, mobileCompanionServer.$address)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running, status, address in
                self?.isMobileCompanionRunning = running
                self?.mobileCompanionStatus = status
                self?.mobileCompanionURL = address
            }
            .store(in: &operatorFeatureCancellables)
        updateMobileCompanionSnapshot()
    }

    func chooseCloudSyncFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use for YAAM Sync"
        panel.message = "Choose a folder in iCloud Drive or another synchronized folder. YAAM stores a versioned package, never a live database file."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(bookmark, forKey: "cloudSyncBookmark")
                self.cloudSyncStatus = "Cloud folder configured"
                self.configureCloudSyncTimer()
                self.playActivitySound(.success)
            } catch {
                self.cloudSyncStatus = error.localizedDescription
                self.playActivitySound(.failure)
            }
        }
    }

    func disconnectCloudSyncFolder() {
        UserDefaults.standard.removeObject(forKey: "cloudSyncBookmark")
        cloudSyncTimer?.invalidate()
        cloudSyncTimer = nil
        cloudSyncStatus = "Choose an iCloud Drive folder"
    }

    @MainActor
    func pushCloudPackage() async {
        guard !isCloudSyncRunning,
              let folder = cloudSyncFolderURL(),
              let profile = activeStationProfile else {
            cloudSyncStatus = "Choose a cloud folder and active station first"
            return
        }
        isCloudSyncRunning = true
        cloudSyncStatus = "Writing versioned cloud package..."
        let package = CloudSyncPackage(
            formatVersion: 1,
            appVersion: currentVersion,
            generatedAt: Date(),
            deviceID: connectivityDeviceID(),
            stationProfile: profile,
            headers: tableHeaders,
            qsos: qsoRecords.map(CloudSyncQSO.init)
        )
        do {
            let url = try await cloudFileCoordinator.write(package, to: folder)
            cloudSyncLastRun = Date()
            UserDefaults.standard.set(cloudSyncLastRun, forKey: "cloudSyncLastRun")
            cloudSyncStatus = "Pushed \(package.qsos.count) QSOs · \(url.lastPathComponent)"
            playActivitySound(.success)
        } catch {
            cloudSyncStatus = error.localizedDescription
            playActivitySound(.failure)
        }
        isCloudSyncRunning = false
    }

    @MainActor
    func pullCloudPackage() async -> Bool {
        guard !isCloudSyncRunning,
              let folder = cloudSyncFolderURL(),
              let profile = activeStationProfile else {
            cloudSyncStatus = "Choose a cloud folder and active station first"
            return false
        }
        isCloudSyncRunning = true
        cloudSyncStatus = "Reading cloud package..."
        do {
            guard let package = try await cloudFileCoordinator.read(
                profile: profile,
                from: folder
            ) else {
                cloudSyncStatus = "No package exists yet; push this station first"
                isCloudSyncRunning = false
                return true
            }
            let incoming = package.qsos.map { cloud -> CloudSyncQSO in
                var localized = cloud
                localized.fields["APP_YAAM_STATION_PROFILE_ID"] = profile.id.uuidString
                localized.fields["STATION_CALLSIGN"] = profile.normalizedCallsign
                return localized
            }
            let merge = CloudSyncMerge.merge(
                local: qsoRecords,
                localHeaders: tableHeaders,
                incoming: incoming,
                incomingHeaders: package.headers
            )
            if merge.added > 0 || merge.updated > 0 {
                _ = try logbookDatabase?.createBackup(reason: "Before cloud merge")
                qsoRecords = merge.records
                tableHeaders = merge.headers
                try persistCurrentWorkspace(reason: "Cloud package merge")
                refreshDatabaseSafetyState()
                refreshAwardProgress()
            }
            cloudSyncLastRun = Date()
            UserDefaults.standard.set(cloudSyncLastRun, forKey: "cloudSyncLastRun")
            cloudSyncStatus = "Cloud merge: \(merge.added) added · \(merge.updated) updated · \(merge.unchanged) unchanged"
            playActivitySound(.success)
            isCloudSyncRunning = false
            return true
        } catch {
            cloudSyncStatus = error.localizedDescription
            playActivitySound(.failure)
            isCloudSyncRunning = false
            return false
        }
    }

    @MainActor
    func syncCloudPackage() async {
        let safeToPush = await pullCloudPackage()
        guard safeToPush, !isCloudSyncRunning else { return }
        await pushCloudPackage()
    }

    func configureCloudSyncTimer() {
        cloudSyncTimer?.invalidate()
        cloudSyncTimer = nil
        let enabled = UserDefaults.standard.bool(forKey: "cloudSyncAutomatic")
        guard enabled, cloudSyncFolderURL() != nil else { return }
        let minutes = max(5, UserDefaults.standard.integer(forKey: "cloudSyncMinutes"))
        cloudSyncTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.syncCloudPackage() }
        }
    }

    func startMobileCompanion() {
        var token = CredentialVault.value(for: .mobileAPIToken)
        if token.isEmpty {
            token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            guard CredentialVault.set(token, for: .mobileAPIToken) else {
                mobileCompanionStatus = "Unable to store the access token securely"
                return
            }
        }
        let savedPort = UserDefaults.standard.integer(forKey: "mobileCompanionPort")
        let port = UInt16((1...65_535).contains(savedPort) ? savedPort : 7373)
        do {
            updateMobileCompanionSnapshot()
            try mobileCompanionServer.start(port: port, token: token)
            mobileCompanionStatus = "Starting local server..."
        } catch {
            mobileCompanionStatus = error.localizedDescription
            playActivitySound(.failure)
        }
    }

    func stopMobileCompanion() {
        mobileCompanionServer.stop()
    }

    func rotateMobileCompanionToken() {
        let wasRunning = isMobileCompanionRunning
        mobileCompanionServer.stop()
        _ = CredentialVault.set(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), for: .mobileAPIToken)
        mobileCompanionStatus = "Access token rotated; old links no longer work"
        if wasRunning { startMobileCompanion() }
    }

    func updateMobileCompanionSnapshot() {
        let allQSOs = qsoRecords.reversed().map {
            MobileQSOSnapshot(
                id: $0.id,
                call: $0["CALL"],
                date: $0["QSO_DATE"],
                time: $0["TIME_ON"],
                band: $0["BAND"],
                mode: $0["SUBMODE"].isEmpty ? $0["MODE"] : $0["SUBMODE"],
                confirmed: $0.isConfirmed
            )
        }
        let grids = Set(qsoRecords.compactMap { record -> String? in
            if let grid = GridLocator.fourCharacterGrid(from: record["GRIDSQUARE"]) { return grid }
            return GridLocator.fourCharacterGrid(latitude: record["LAT"], longitude: record["LON"])
        })
        let awards = awardProgress.prefix(12).map {
            MobileAwardSnapshot(
                id: $0.id,
                title: $0.title,
                confirmed: $0.confirmed,
                target: $0.target,
                percent: $0.percent,
                stage: $0.effectiveStage.title
            )
        }
        mobileCompanionServer.update(
            snapshot: MobileCompanionSnapshot(
                station: currentStationCallsign,
                generatedAt: Date(),
                qsoCount: qsoRecords.count,
                confirmedCount: qsoRecords.filter(\.isConfirmed).count,
                gridCount: grids.count,
                awards: awards,
                recentQSOs: Array(allQSOs.prefix(25))
            ),
            qsos: allQSOs
        )
    }

    private func acceptMobileQuickLog(_ request: MobileQuickLogRequest) {
        guard UserDefaults.standard.object(forKey: "mobileCompanionAllowLogging") as? Bool ?? true else {
            mobileCompanionStatus = "A mobile log request was refused by the read-only setting"
            return
        }
        let preserved = quickLogDraft
        let preservedLookup = quickLogLookup
        var draft = QuickLogDraft()
        draft.callsign = request.callsign
        draft.applyFrequency(request.frequencyMHz)
        let mode = request.mode.uppercased()
        if ["FT8", "FT4", "JS8"].contains(mode) {
            draft.mode = "DIGI"
            draft.submode = mode
        } else {
            draft.applyMode(mode)
        }
        if let rstSent = request.rstSent, !rstSent.isEmpty { draft.rstSent = rstSent }
        if let rstReceived = request.rstReceived, !rstReceived.isEmpty { draft.rstReceived = rstReceived }
        draft.comment = request.comment ?? ""
        draft.source = "Mobile Companion"
        quickLogDraft = draft
        quickLogLookup = nil
        do {
            let record = try saveQuickLog()
            mobileCompanionStatus = "Logged \(record["CALL"]) from mobile"
        } catch {
            mobileCompanionStatus = "Mobile log rejected: \(error.localizedDescription)"
        }
        quickLogDraft = preserved
        quickLogLookup = preservedLookup
        refreshQuickLogAssessment()
    }

    private func cloudSyncFolderURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: "cloudSyncBookmark") else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        if stale, let renewed = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(renewed, forKey: "cloudSyncBookmark")
        }
        return url
    }

    private func connectivityDeviceID() -> String {
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: "connectivityDeviceID"), !value.isEmpty { return value }
        let value = UUID().uuidString.lowercased()
        defaults.set(value, forKey: "connectivityDeviceID")
        return value
    }
}
