//
//  AmateurBandSettings.swift
//  YAAM
//
//  Created by EP2AES on 8/9/26.
//

import SwiftUI
import Combine

// MARK: - Amateur Radio Band Category
enum AmateurBandCategory: String, CaseIterable, Identifiable, Sendable {
    case hfCore = "HF Core Bands"
    case vhf = "VHF Bands"
    case uhf = "UHF Bands"
    case lfMf = "LF & MF Bands"
    case microwave = "Microwave & SHF"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .hfCore: return "globe.americas.fill"
        case .vhf: return "antenna.radiowaves.left.and.right"
        case .uhf: return "dot.radiowaves.left.and.right"
        case .lfMf: return "waveform.path"
        case .microwave: return "bolt.horizontal.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .hfCore: return .blue
        case .vhf: return .green
        case .uhf: return .orange
        case .lfMf: return .purple
        case .microwave: return .pink
        }
    }

    var subtitle: String {
        switch self {
        case .hfCore: return "Primary DXCC, contest, and global amateur communications (160m – 10m)"
        case .vhf: return "Line-of-sight, repeater, sporadic-E, and 6m magic band (6m – 1.25m)"
        case .uhf: return "Repeaters, satellite, digital voice, and weak signal (70cm – 23cm)"
        case .lfMf: return "Experimental groundwave and long-distance sub-MHz propagation"
        case .microwave: return "Centimeter wave, terrestrial line-of-sight, and QO-100 satellite links"
        }
    }
}

// MARK: - Band Definition Metadata
struct AmateurBandDefinition: Identifiable, Hashable, Sendable {
    let id: String // canonical lowercased ADIF band, e.g. "160m"
    let uppercaseName: String // "160M"
    let frequencyRange: String // "1.800 – 2.000 MHz"
    let wavelengthDesc: String // "Topband"
    let category: AmateurBandCategory
    let isCore: Bool // True for 160m to 6m (the 11 standard bands)
    let orderIndex: Int

    var displayName: String { uppercaseName }
}

// MARK: - Band Settings & State Store
@MainActor
final class AmateurBandSettings: ObservableObject {
    static let shared = AmateurBandSettings()

    // MARK: - All 24 Defined Amateur Radio Bands (Frequency Order)
    nonisolated static let allBands: [AmateurBandDefinition] = [
        // LF / MF (Below 160m)
        AmateurBandDefinition(id: "2190m", uppercaseName: "2190M", frequencyRange: "135.7 – 137.8 kHz", wavelengthDesc: "LF Experimental", category: .lfMf, isCore: false, orderIndex: 0),
        AmateurBandDefinition(id: "630m", uppercaseName: "630M", frequencyRange: "472.0 – 479.0 kHz", wavelengthDesc: "MF Maritime Heritage", category: .lfMf, isCore: false, orderIndex: 1),

        // HF Core Bands (160m - 10m) + 6m VHF Core = 11 Core Bands
        AmateurBandDefinition(id: "160m", uppercaseName: "160M", frequencyRange: "1.800 – 2.000 MHz", wavelengthDesc: "Topband / Nighttime DX", category: .hfCore, isCore: true, orderIndex: 2),
        AmateurBandDefinition(id: "80m", uppercaseName: "80M", frequencyRange: "3.500 – 4.000 MHz", wavelengthDesc: "Regional & Nighttime DX", category: .hfCore, isCore: true, orderIndex: 3),
        AmateurBandDefinition(id: "60m", uppercaseName: "60M", frequencyRange: "5.000 – 5.500 MHz", wavelengthDesc: "WRC-15 Secondary Allocation", category: .hfCore, isCore: true, orderIndex: 4),
        AmateurBandDefinition(id: "40m", uppercaseName: "40M", frequencyRange: "7.000 – 7.300 MHz", wavelengthDesc: "Worldwide Day/Night Workhorse", category: .hfCore, isCore: true, orderIndex: 5),
        AmateurBandDefinition(id: "30m", uppercaseName: "30M", frequencyRange: "10.100 – 10.150 MHz", wavelengthDesc: "WARC CW & Digital Exclusive", category: .hfCore, isCore: true, orderIndex: 6),
        AmateurBandDefinition(id: "20m", uppercaseName: "20M", frequencyRange: "14.000 – 14.350 MHz", wavelengthDesc: "Premier Intercontinental DX", category: .hfCore, isCore: true, orderIndex: 7),
        AmateurBandDefinition(id: "17m", uppercaseName: "17M", frequencyRange: "18.068 – 18.168 MHz", wavelengthDesc: "WARC Quiet Solar Band", category: .hfCore, isCore: true, orderIndex: 8),
        AmateurBandDefinition(id: "15m", uppercaseName: "15M", frequencyRange: "21.000 – 21.450 MHz", wavelengthDesc: "Solar Cycle DX Classic", category: .hfCore, isCore: true, orderIndex: 9),
        AmateurBandDefinition(id: "12m", uppercaseName: "12M", frequencyRange: "24.890 – 24.990 MHz", wavelengthDesc: "WARC High Solar Maximum", category: .hfCore, isCore: true, orderIndex: 10),
        AmateurBandDefinition(id: "10m", uppercaseName: "10M", frequencyRange: "28.000 – 29.700 MHz", wavelengthDesc: "Sporadic-E & Solar Apex", category: .hfCore, isCore: true, orderIndex: 11),
        AmateurBandDefinition(id: "6m", uppercaseName: "6M", frequencyRange: "50.000 – 54.000 MHz", wavelengthDesc: "The Magic Band (VHF)", category: .vhf, isCore: true, orderIndex: 12),

        // VHF Extended Bands (Above 6m)
        AmateurBandDefinition(id: "4m", uppercaseName: "4M", frequencyRange: "69.900 – 71.000 MHz", wavelengthDesc: "European & African VHF", category: .vhf, isCore: false, orderIndex: 13),
        AmateurBandDefinition(id: "2m", uppercaseName: "2M", frequencyRange: "144.000 – 148.000 MHz", wavelengthDesc: "Popular Repeaters & Weak-Signal", category: .vhf, isCore: false, orderIndex: 14),
        AmateurBandDefinition(id: "1.25m", uppercaseName: "1.25M", frequencyRange: "219.000 – 225.000 MHz", wavelengthDesc: "Region 2 / 222 MHz VHF", category: .vhf, isCore: false, orderIndex: 15),

        // UHF Extended Bands
        AmateurBandDefinition(id: "70cm", uppercaseName: "70CM", frequencyRange: "420.0 – 450.0 MHz", wavelengthDesc: "UHF Repeaters & Satellite", category: .uhf, isCore: false, orderIndex: 16),
        AmateurBandDefinition(id: "33cm", uppercaseName: "33CM", frequencyRange: "902.0 – 928.0 MHz", wavelengthDesc: "Region 2 UHF", category: .uhf, isCore: false, orderIndex: 17),
        AmateurBandDefinition(id: "23cm", uppercaseName: "23CM", frequencyRange: "1,240 – 1,300 MHz", wavelengthDesc: "1.2 GHz Weak-Signal & ATV", category: .uhf, isCore: false, orderIndex: 18),

        // Microwave & SHF Extended Bands
        AmateurBandDefinition(id: "13cm", uppercaseName: "13CM", frequencyRange: "2,300 – 2,450 MHz", wavelengthDesc: "2.4 GHz & QO-100 Uplink", category: .microwave, isCore: false, orderIndex: 19),
        AmateurBandDefinition(id: "9cm", uppercaseName: "9CM", frequencyRange: "3,300 – 3,500 MHz", wavelengthDesc: "3.4 GHz Amateur Satellite", category: .microwave, isCore: false, orderIndex: 20),
        AmateurBandDefinition(id: "6cm", uppercaseName: "6CM", frequencyRange: "5,650 – 5,925 MHz", wavelengthDesc: "5.7 GHz Microwave", category: .microwave, isCore: false, orderIndex: 21),
        AmateurBandDefinition(id: "3cm", uppercaseName: "3CM", frequencyRange: "10.00 – 10.50 GHz", wavelengthDesc: "10 GHz Rain Scatter & Terrestrial", category: .microwave, isCore: false, orderIndex: 22),
        AmateurBandDefinition(id: "1.25cm", uppercaseName: "1.25CM", frequencyRange: "24.00 – 24.25 GHz", wavelengthDesc: "24 GHz Millimeter Wave", category: .microwave, isCore: false, orderIndex: 23)
    ]

    // MARK: - The 11 Core Amateur Radio Bands (160m to 6m)
    nonisolated static let coreBands: [String] = [
        "160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m", "6m"
    ]

    // MARK: - The 13 Extended Amateur Radio Bands
    nonisolated static let extendedBands: [String] = [
        "2190m", "630m", "4m", "2m", "1.25m", "70cm", "33cm", "23cm", "13cm", "9cm", "6cm", "3cm", "1.25cm"
    ]

    nonisolated static let userDefaultsKey = "activeAmateurBands"
    nonisolated static let autoIncludeKey = "autoIncludeBandsWithQSOs"

    @Published var activeBands: Set<String> {
        didSet {
            save()
        }
    }

    @Published var autoIncludeBandsWithQSOs: Bool {
        didSet {
            UserDefaults.standard.set(autoIncludeBandsWithQSOs, forKey: Self.autoIncludeKey)
            NotificationCenter.default.post(name: .amateurBandsConfigurationDidChange, object: nil)
        }
    }

    private init() {
        if let saved = UserDefaults.standard.array(forKey: Self.userDefaultsKey) as? [String], !saved.isEmpty {
            self.activeBands = Set(saved.map { $0.lowercased() })
        } else {
            // Default: strictly the 11 core bands from 160m to 6m
            self.activeBands = Set(Self.coreBands)
        }

        if UserDefaults.standard.object(forKey: Self.autoIncludeKey) != nil {
            self.autoIncludeBandsWithQSOs = UserDefaults.standard.bool(forKey: Self.autoIncludeKey)
        } else {
            self.autoIncludeBandsWithQSOs = true
        }
    }

    private func save() {
        UserDefaults.standard.set(Array(activeBands), forKey: Self.userDefaultsKey)
        NotificationCenter.default.post(name: .amateurBandsConfigurationDidChange, object: nil)
    }

    // MARK: - Query Methods
    func isBandActive(_ band: String) -> Bool {
        activeBands.contains(band.lowercased())
    }

    func toggleBand(_ band: String) {
        let clean = band.lowercased()
        if activeBands.contains(clean) {
            activeBands.remove(clean)
        } else {
            activeBands.insert(clean)
        }
    }

    func setBand(_ band: String, enabled: Bool) {
        let clean = band.lowercased()
        if enabled {
            activeBands.insert(clean)
        } else {
            activeBands.remove(clean)
        }
    }

    // MARK: - Presets
    func resetToCore11Only() {
        activeBands = Set(Self.coreBands)
    }

    func enableAll24Bands() {
        activeBands = Set(Self.allBands.map(\.id))
    }

    func enableHFOnly() {
        activeBands = Set(["160m", "80m", "60m", "40m", "30m", "20m", "17m", "15m", "12m", "10m"])
    }

    func enableCorePlusVHFUHF() {
        activeBands = Set(Self.coreBands + ["2m", "70cm"])
    }

    // MARK: - Ordered Active Bands Helper
    func orderedActiveBands(observedBands: Set<String> = []) -> [String] {
        Self.savedOrderedActiveBands(observedBands: observedBands, customActiveBands: activeBands, customAutoInclude: autoIncludeBandsWithQSOs)
    }

    // MARK: - Nonisolated Global Helper (callable from any context / model)
    nonisolated static func savedOrderedActiveBands(
        observedBands: Set<String> = [],
        customActiveBands: Set<String>? = nil,
        customAutoInclude: Bool? = nil
    ) -> [String] {
        let active: Set<String> = {
            if let custom = customActiveBands { return custom }
            if let saved = UserDefaults.standard.array(forKey: userDefaultsKey) as? [String], !saved.isEmpty {
                return Set(saved.map { $0.lowercased() })
            }
            return Set(coreBands)
        }()

        let autoInclude: Bool = {
            if let custom = customAutoInclude { return custom }
            if UserDefaults.standard.object(forKey: autoIncludeKey) != nil {
                return UserDefaults.standard.bool(forKey: autoIncludeKey)
            }
            return true
        }()

        var effective = active
        if autoInclude {
            for obs in observedBands {
                effective.insert(obs.lowercased())
            }
        }

        let orderedKnown = allBands
            .filter { effective.contains($0.id) }
            .map(\.id)

        let knownSet = Set(allBands.map(\.id))
        let extra = observedBands
            .filter { !knownSet.contains($0.lowercased()) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        return orderedKnown + extra
    }
}

extension Notification.Name {
    static let amateurBandsConfigurationDidChange = Notification.Name("amateurBandsConfigurationDidChange")
}
