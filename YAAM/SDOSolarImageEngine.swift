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
            if feedActivity.isActive { fetchChannelImage(selectedChannel) }
        }
    }

    @Published public private(set) var currentImage: NSImage?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var lastFetchedDate: Date?
    @Published public private(set) var cachedImages: [SDOChannel: NSImage] = [:]


    private init() {
        let savedChannelRaw = UserDefaults.standard.string(forKey: "sdoSelectedChannel") ?? SDOChannel.hmiIntensity.rawValue
        self.selectedChannel = SDOChannel(rawValue: savedChannelRaw) ?? .hmiIntensity

    }

    private var downloadTask: URLSessionDataTask?
    private var requestID = UUID()
    private lazy var feedActivity = PublicDataFeedActivity(interval: 1200, refresh: { [weak self] in
        guard let self else { return }
        self.fetchChannelImage(self.selectedChannel, force: true)
    }, cancel: { [weak self] in
        self?.requestID = UUID()
        self?.downloadTask?.cancel()
        self?.isLoading = false
    })

    func setFeedConsumer(_ id: UUID, active: Bool) {
        feedActivity.setConsumer(id, active: active)
    }

    public func fetchChannelImage(_ channel: SDOChannel, force: Bool = false) {
        guard PublicDataFeedPolicy.shared.isEnabled else { return }
        if !force, let cached = cachedImages[channel] {
            self.currentImage = cached
            return
        }

        isLoading = true
        let url = channel.imageURL

        downloadTask?.cancel()
        requestID = UUID()
        let requestID = self.requestID
        downloadTask = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            defer {
                DispatchQueue.main.async {
                    guard self.requestID == requestID, PublicDataFeedPolicy.shared.isEnabled else { return }
                    self.isLoading = false
                }
            }

            guard let data = data, error == nil, let img = NSImage(data: data) else {
                return
            }

            DispatchQueue.main.async {
                guard self.requestID == requestID, PublicDataFeedPolicy.shared.isEnabled else { return }
                self.cachedImages[channel] = img
                if self.selectedChannel == channel {
                    self.currentImage = img
                    self.lastFetchedDate = Date()
                }
            }
        }
        downloadTask?.resume()
    }

    public func cycleChannel() {
        let all = SDOChannel.allCases
        if let idx = all.firstIndex(of: selectedChannel) {
            let nextIdx = (idx + 1) % all.count
            selectedChannel = all[nextIdx]
        }
    }
}
