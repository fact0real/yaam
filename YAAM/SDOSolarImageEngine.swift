//
//  SDOSolarImageEngine.swift
//  YAAM
//
//  Real-time NASA Solar Dynamics Observatory (SDO) Image Pipeline
//  Fetches and caches live solar imagery across multiple spectral channels:
//  AIA 193 (Coronal Holes), AIA 304 (Filaments/Flares), and HMI (Sunspot Groups).
//

import AppKit
import Combine
import Foundation
import SwiftUI

public enum SDOChannel: String, CaseIterable, Identifiable, Sendable {
    case aia193 = "AIA 193Å (Coronal Holes)"
    case aia304 = "AIA 304Å (Prominences)"
    case hmiIntensity = "HMI Sunspots (Visible)"
    case hmiMagnetogram = "HMI Magnetogram"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .aia193: return "193Å Coronal"
        case .aia304: return "304Å Flares"
        case .hmiIntensity: return "Sunspots"
        case .hmiMagnetogram: return "Magnetic"
        }
    }

    public var imageURL: URL {
        switch self {
        case .aia193:
            return URL(string: "https://sdo.gsfc.nasa.gov/assets/img/latest/latest_512_0193.jpg")!
        case .aia304:
            return URL(string: "https://sdo.gsfc.nasa.gov/assets/img/latest/latest_512_0304.jpg")!
        case .hmiIntensity:
            return URL(string: "https://sdo.gsfc.nasa.gov/assets/img/latest/latest_512_HMIIF.jpg")!
        case .hmiMagnetogram:
            return URL(string: "https://sdo.gsfc.nasa.gov/assets/img/latest/latest_512_HMIBC.jpg")!
        }
    }

    public var description: String {
        switch self {
        case .aia193:
            return "Extreme ultraviolet (19.3 nm) reveals coronal holes, which produce high-speed solar wind streams."
        case .aia304:
            return "Ultraviolet (30.4 nm) captures solar filaments, eruptive prominences, and active flaring regions."
        case .hmiIntensity:
            return "Visible continuum light shows photospheric sunspots, active magnetic clusters, and solar limb darkening."
        case .hmiMagnetogram:
            return "Photospheric magnetic field polarity (black = inward/negative, white = outward/positive)."
        }
    }
}

@MainActor
public final class SDOSolarImageEngine: ObservableObject {
    public static let shared = SDOSolarImageEngine()

    @Published public var selectedChannel: SDOChannel = .hmiIntensity {
        didSet {
            UserDefaults.standard.set(selectedChannel.rawValue, forKey: "sdoSelectedChannel")
            fetchChannelImage(selectedChannel)
        }
    }

    @Published public private(set) var currentImage: NSImage?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastFetchedDate: Date?
    @Published public private(set) var cachedImages: [SDOChannel: NSImage] = [:]

    private var refreshCancellable: AnyCancellable?

    private init() {
        let savedChannelRaw = UserDefaults.standard.string(forKey: "sdoSelectedChannel") ?? SDOChannel.hmiIntensity.rawValue
        self.selectedChannel = SDOChannel(rawValue: savedChannelRaw) ?? .hmiIntensity

        fetchChannelImage(selectedChannel)
        startPeriodicRefresh()
    }

    private func startPeriodicRefresh() {
        // Refresh every 20 minutes (SDO updates every ~15 mins)
        refreshCancellable = Timer.publish(every: 1200.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.fetchChannelImage(self.selectedChannel, force: true)
            }
    }

    public func fetchChannelImage(_ channel: SDOChannel, force: Bool = false) {
        if !force, let cached = cachedImages[channel] {
            self.currentImage = cached
            return
        }

        isLoading = true
        let url = channel.imageURL

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            defer {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }

            guard let data = data, error == nil, let img = NSImage(data: data) else {
                return
            }

            DispatchQueue.main.async {
                self.cachedImages[channel] = img
                if self.selectedChannel == channel {
                    self.currentImage = img
                    self.lastFetchedDate = Date()
                }
            }
        }.resume()
    }

    public func cycleChannel() {
        let all = SDOChannel.allCases
        if let idx = all.firstIndex(of: selectedChannel) {
            let nextIdx = (idx + 1) % all.count
            selectedChannel = all[nextIdx]
        }
    }
}
