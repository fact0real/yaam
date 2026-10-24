//
//  POTASpotsClient.swift
//  YAAM
//
//  Real-Time POTA & SOTA Live Spots Client
//  Fetches from official POTA API (api.pota.app/spot/activator) & SOTAwatch.
//  Provides Park-to-Park (P2P) and Summit-to-Summit (S2S) matching and 1-Click CAT QSY.
//

import Combine
import Foundation
import SwiftUI

@MainActor
public final class POTASpotsClient: ObservableObject {
    public static let shared = POTASpotsClient()

    @Published public private(set) var potaSpots: [POTASpotItem] = []
    @Published public private(set) var sotaSpots: [SOTASpotItem] = []
    @Published public var isLoading: Bool = false
    @Published public var lastUpdated: Date? = nil
    @Published public private(set) var potaUpdated: Date?
    @Published public private(set) var sotaUpdated: Date?
    @Published public private(set) var potaError: String?
    @Published public private(set) var sotaError: String?
    @Published public var errorMessage: String? = nil
    @Published public var tuneErrorMessage: String? = nil

    // Filters
    @Published public var selectedProgram: FieldProgramType = .pota
    @Published public var selectedBand: String = "ALL"       // "ALL", "20M", "40M", etc.
    @Published public var selectedMode: String = "ALL"       // "ALL", "CW", "SSB", "FT8"
    @Published public var searchQuery: String = ""
    @Published public var onlyP2POpportunities: Bool = false

    private var autoRefreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let session: URLSession
    init(session: URLSession = .shared, autoRefresh: Bool = false) {
        self.session = session
        if autoRefresh { startAutoRefresh() }
    }

    public var selectedUpdated: Date? { selectedProgram == .pota ? potaUpdated : sotaUpdated }
    public var selectedError: String? { selectedProgram == .pota ? potaError : sotaError }
    public var selectedIsStale: Bool { selectedError != nil }

    public var freshnessMessage: String {
        let program = selectedProgram == .pota ? "POTA" : "SOTA"
        guard let date = selectedUpdated else { return "\(program): no successful fetch yet." }
        return "\(program): \(selectedIsStale ? "stale list" : "last successful fetch") · \(TXLimits.utc(date))"
    }

    deinit {
        autoRefreshTimer?.invalidate()
    }

    public func startAutoRefresh(interval: TimeInterval = 60.0) {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshSpots()
            }
        }
        Task {
            await refreshSpots()
        }
    }

    public func stopAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }

    // MARK: - Fetch Spots
    public func refreshSpots() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        // A refresh must not contact an unselected provider.
        let program = selectedProgram
        if program == .pota {
            if let spots = await fetchPOTASpots() {
                potaSpots = spots; potaUpdated = Date(); potaError = nil; lastUpdated = Date()
            }
            errorMessage = potaError
        } else {
            if let spots = await fetchSOTASpots() {
                sotaSpots = spots; sotaUpdated = Date(); sotaError = nil; lastUpdated = Date()
            }
            errorMessage = sotaError
        }
        self.isLoading = false
    }

    private func fetchPOTASpots() async -> [POTASpotItem]? {
        guard let url = URL(string: "https://api.pota.app/spot/activator") else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10.0
            request.setValue("YAAM-macOS-FieldOps/1.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                potaError = "POTA fetch failed at \(TXLimits.utc()): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0). Retained spots are stale. Retry refresh."
                return nil
            }

            let decoder = JSONDecoder()
            let decoded = try decoder.decode([POTASpotItem].self, from: data)
            return decoded
        } catch {
            potaError = "POTA fetch failed at \(TXLimits.utc()): \(error.localizedDescription). Retained spots are stale. Retry refresh."
            return nil
        }
    }

    private func fetchSOTASpots() async -> [SOTASpotItem]? {
        guard let url = URL(string: "https://api2.sota.org.uk/api/spots/50") else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10.0
            request.setValue("YAAM-macOS-FieldOps/1.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                sotaError = "SOTA fetch failed at \(TXLimits.utc()): HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0). Retained spots are stale. Retry refresh."
                return nil
            }

            let decoder = JSONDecoder()
            let decoded = try decoder.decode([SOTASpotItem].self, from: data)
            return decoded
        } catch {
            sotaError = "SOTA fetch failed at \(TXLimits.utc()): \(error.localizedDescription). Retained spots are stale. Retry refresh."
            return nil
        }
    }

    // MARK: - Filtered Lists
    public var filteredPOTASpots: [POTASpotItem] {
        potaSpots.filter { spot in
            // Band filter
            if selectedBand != "ALL" && spot.band.uppercased() != selectedBand.uppercased() {
                return false
            }
            // Mode filter
            if selectedMode != "ALL" && !spot.mode.uppercased().contains(selectedMode.uppercased()) {
                return false
            }
            // Search Query
            if !searchQuery.isEmpty {
                let q = searchQuery.uppercased()
                let matches = spot.activator.uppercased().contains(q) ||
                              spot.reference.uppercased().contains(q) ||
                              spot.name.uppercased().contains(q) ||
                              (spot.locationDesc?.uppercased().contains(q) ?? false)
                if !matches { return false }
            }
            return true
        }
    }

    public var filteredSOTASpots: [SOTASpotItem] {
        sotaSpots.filter { spot in
            // Band filter
            if selectedBand != "ALL" && spot.band.uppercased() != selectedBand.uppercased() {
                return false
            }
            // Mode filter
            if selectedMode != "ALL" && !spot.mode.uppercased().contains(selectedMode.uppercased()) {
                return false
            }
            // Search Query
            if !searchQuery.isEmpty {
                let q = searchQuery.uppercased()
                let matches = spot.activatorCallsign.uppercased().contains(q) ||
                              spot.summitCode.uppercased().contains(q) ||
                              (spot.summitDetails?.uppercased().contains(q) ?? false)
                if !matches { return false }
            }
            return true
        }
    }

    // MARK: - CAT QSY Tune Rig
    public func tuneRig(frequencyKHz: Double, mode: String) {
        // The spot's frequency comes from the POTA or SOTA service: one that is not a usable frequency would stop YAAM
        // in UInt64(kHz * 1000), so the radio is not tuned and the reason is kept (FrequencyBounds).
        guard FrequencyBounds.isUsable(kHz: frequencyKHz) else {
            let message = "POTA/SOTA: the spot's frequency (\(frequencyKHz) kHz) is not a usable radio frequency, so at "
                + "\(TXLimits.utc()) the radio was not tuned. Tune it by hand. The rest of YAAM is not affected."
            errorMessage = message
            tuneErrorMessage = message
            NSLog("%@", message)
            return
        }
        guard !selectedIsStale else {
            tuneErrorMessage = "POTA/SOTA: the list is stale; the radio was not tuned at \(TXLimits.utc()). Refresh successfully or tune by hand."
            return
        }
        let hz = UInt64(frequencyKHz * 1000.0)
        let normalizedMode: String
        let upper = mode.uppercased()
        if upper.contains("CW") {
            normalizedMode = "CW"
        } else if upper.contains("FT8") || upper.contains("DATA") {
            normalizedMode = "USB-D"
        } else if frequencyKHz < 10000.0 {
            normalizedMode = "LSB"
        } else {
            normalizedMode = "USB"
        }

        // 1. Direct RigControlEngine (tunes rigctld, FLRig, TX-500, Icom USB, FX-4CR, Xiegu)
        let rig = RigControlEngine.shared
        let tciConnected = TCIClient.shared.isConnected
        if rig.driverType != .disabled || !tciConnected {
            if let reason = rig.tune(frequencyHz: hz, mode: normalizedMode) {
                tuneErrorMessage = "POTA/SOTA: \(reason) at \(TXLimits.utc()). Check CAT settings or tune by hand."
                return
            }
        }

        tuneErrorMessage = nil
        // 2. Also forward to TCI if active
        if TCIClient.shared.isConnected {
            TCIClient.shared.setFrequency(hz: hz)
        }
    }

}
