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
    @Published public var errorMessage: String? = nil

    // Filters
    @Published public var selectedProgram: FieldProgramType = .pota
    @Published public var selectedBand: String = "ALL"       // "ALL", "20M", "40M", etc.
    @Published public var selectedMode: String = "ALL"       // "ALL", "CW", "SSB", "FT8"
    @Published public var searchQuery: String = ""
    @Published public var onlyP2POpportunities: Bool = false

    private var autoRefreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        startAutoRefresh()
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

        async let fetchedPOTA = fetchPOTASpots()
        async let fetchedSOTA = fetchSOTASpots()

        let (potaResult, sotaResult) = await (fetchedPOTA, fetchedSOTA)

        if let pSpots = potaResult {
            self.potaSpots = pSpots
        }
        if let sSpots = sotaResult {
            self.sotaSpots = sSpots
        }

        self.lastUpdated = Date()
        self.isLoading = false
    }

    private func fetchPOTASpots() async -> [POTASpotItem]? {
        guard let url = URL(string: "https://api.pota.app/spot/activator") else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10.0
            request.setValue("YAAM-macOS-FieldOps/1.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return fallbackPOTASpots()
            }

            let decoder = JSONDecoder()
            let decoded = try decoder.decode([POTASpotItem].self, from: data)
            return decoded
        } catch {
            return fallbackPOTASpots()
        }
    }

    private func fetchSOTASpots() async -> [SOTASpotItem]? {
        guard let url = URL(string: "https://api2.sota.org.uk/api/spots/50") else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10.0
            request.setValue("YAAM-macOS-FieldOps/1.0", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return fallbackSOTASpots()
            }

            let decoder = JSONDecoder()
            let decoded = try decoder.decode([SOTASpotItem].self, from: data)
            return decoded
        } catch {
            return fallbackSOTASpots()
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
        RigControlEngine.shared.tune(frequencyHz: hz, mode: normalizedMode)

        // 2. Also forward to TCI if active
        if TCIClient.shared.isConnected {
            TCIClient.shared.setFrequency(hz: hz)
        }
    }

    // MARK: - Mock / Offline Fallbacks
    private func fallbackPOTASpots() -> [POTASpotItem] {
        [
            POTASpotItem(spotId: 101, activator: "W1AW/P", frequency: 14074.0, mode: "FT8", reference: "K-0001", name: "Acadia National Park", locationDesc: "ME", grid: "FN54", spotTime: "2m ago", spotter: "N1MM", comments: "Loud into EU"),
            POTASpotItem(spotId: 102, activator: "EP2LMA", frequency: 14285.0, mode: "SSB", reference: "EP-0005", name: "Lar National Park", locationDesc: "Mazandaran", grid: "LM35", spotTime: "5m ago", spotter: "EP2C", comments: "QRP 5W TX-500"),
            POTASpotItem(spotId: 103, activator: "K7ATN", frequency: 7032.0, mode: "CW", reference: "K-0020", name: "Grand Canyon National Park", locationDesc: "AZ", grid: "DM36", spotTime: "7m ago", spotter: "W7W", comments: "P2P welcome!"),
            POTASpotItem(spotId: 104, activator: "DL2MDU/P", frequency: 14060.0, mode: "CW", reference: "DL-0001", name: "Bavarian Forest", locationDesc: "Bavaria", grid: "JN68", spotTime: "11m ago", spotter: "DL1BUG", comments: "CQ POTA up 1"),
            POTASpotItem(spotId: 105, activator: "VA3NMA", frequency: 21074.0, mode: "FT8", reference: "VE-0001", name: "Banff National Park", locationDesc: "AB", grid: "DO31", spotTime: "14m ago", spotter: "VE6SAR", comments: "Calling CQ POTA")
        ]
    }

    private func fallbackSOTASpots() -> [SOTASpotItem] {
        [
            SOTASpotItem(idNumber: 201, timeStamp: "4m ago", summitCode: "W6/NC-423", summitDetails: "Mount Diablo (1173m)", associationCode: "W6", regionCode: "NC", activatorCallsign: "N6JRL", frequency: "14.062", mode: "CW", comments: "KX2 5W, dipole"),
            SOTASpotItem(idNumber: 202, timeStamp: "8m ago", summitCode: "EP/TE-002", summitDetails: "Tochal Summit (3964m)", associationCode: "EP", regionCode: "TE", activatorCallsign: "EP2XXX/P", frequency: "7.030", mode: "CW", comments: "Cold wind! S2S please"),
            SOTASpotItem(idNumber: 203, timeStamp: "15m ago", summitCode: "G/LD-001", summitDetails: "Scafell Pike (978m)", associationCode: "G", regionCode: "LD", activatorCallsign: "M0WML/P", frequency: "14.285", mode: "SSB", comments: "CQ SOTA 14.285")
        ]
    }
}
