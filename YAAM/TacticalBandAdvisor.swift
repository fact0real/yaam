//
//  TacticalBandAdvisor.swift
//  YAAM
//
//  Real-time Band Health, Propagation Advisor & Intelligent QSY Recommendation Engine.
//  Analyzes FT8/FT4 decode rates from SDR-Control, SNR trends, and DX Cluster spots to
//  detect band fade and guide the operator to high-yield bands.
//

import Combine
import Foundation
import SwiftUI

public enum BandHealthTrend: String, CaseIterable, Sendable {
    case rising = "Rising"
    case steady = "Steady"
    case declining = "Declining"
    case dead = "Dead / Closed"

    public var icon: String {
        switch self {
        case .rising: return "arrow.up.right"
        case .steady: return "arrow.right"
        case .declining: return "arrow.down.right"
        case .dead: return "xmark.octagon.fill"
        }
    }

    public var color: Color {
        switch self {
        case .rising: return .green
        case .steady: return .blue
        case .declining: return .orange
        case .dead: return .red
        }
    }
}

public struct BandSwitchRecommendation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let fromBand: String
    public let targetBand: String
    public let targetFrequencyHz: UInt64
    public let reason: String
    public let scoreDiff: Double
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        fromBand: String,
        targetBand: String,
        targetFrequencyHz: UInt64,
        reason: String,
        scoreDiff: Double = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fromBand = fromBand
        self.targetBand = targetBand
        self.targetFrequencyHz = targetFrequencyHz
        self.reason = reason
        self.scoreDiff = scoreDiff
        self.createdAt = createdAt
    }

    public var formattedTargetMHz: String {
        AmateurBandPlan.formattedMHz(Double(targetFrequencyHz) / 1_000_000.0)
    }
}

public struct BandActivitySnapshot: Identifiable, Sendable {
    public var id: String { band }
    public let band: String
    public var decodeCountLastSlot: Int
    public var decodesPerMinute: Double
    public var averageSNR: Double
    public var clusterSpotCount: Int
    public var healthPercentage: Int
    public var trend: BandHealthTrend
    public var lastUpdated: Date
}

@MainActor
public final class TacticalBandAdvisor: ObservableObject {
    public static let shared = TacticalBandAdvisor()

    // MARK: - Published State
    @Published public private(set) var activeBand: String = "20M"
    @Published public private(set) var currentBandHealth: Int = 0 // 0 - 100% (0 = Standby / No Traffic)
    @Published public private(set) var currentBandTrend: BandHealthTrend = .steady
    @Published public private(set) var currentBandDecodesPerMin: Double = 0.0
    @Published public private(set) var currentBandAvgSNR: Double = 0.0
    @Published public private(set) var activeRecommendation: BandSwitchRecommendation? = nil
    @Published public private(set) var recommendationHistory: [BandSwitchRecommendation] = []
    @Published public private(set) var bandSnapshots: [String: BandActivitySnapshot] = [:]

    // Standard Digital Calling Frequencies
    public static let digitalFrequenciesHz: [String: UInt64] = [
        "160M": 1_840_000,
        "80M": 3_573_000,
        "60M": 5_357_000,
        "40M": 7_074_000,
        "30M": 10_136_000,
        "20M": 14_074_000,
        "17M": 18_100_000,
        "15M": 21_074_000,
        "12M": 24_915_000,
        "10M": 28_074_000,
        "6M": 50_313_000
    ]

    // Internal tracking: (Timestamp, SNR)
    private var decodesHistory: [String: [(Date, Double)]] = [:]
    private var clusterSpotsHistory: [String: [Date]] = [:]
    private var previousSlotRates: [String: Double] = [:]
    private var timer: AnyCancellable?

    public init() {
        startEvaluationTimer()
    }

    // MARK: - Configuration & Ingestion

    public func setActiveBand(_ band: String) {
        let clean = band.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty && clean != activeBand else { return }
        activeBand = clean
        evaluateBandsNow()
    }

    /// Records incoming decodes from SDR-Control (WSJTXListener)
    public func recordDecodes(_ decodes: [WSJTXLiveDecode], onBand band: String) {
        guard !decodes.isEmpty else { return }
        let targetBand = band.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBand = targetBand.isEmpty ? activeBand : targetBand

        let now = Date()
        var list = decodesHistory[resolvedBand] ?? []
        for d in decodes {
            list.append((now, Double(d.snr)))
        }

        // Keep last 10 minutes
        let cutoff = now.addingTimeInterval(-600)
        list = list.filter { $0.0 > cutoff }
        decodesHistory[resolvedBand] = list

        evaluateBand(resolvedBand)
    }

    /// Records incoming DX Cluster spots for cross-band awareness
    func recordClusterSpots(_ spots: [DXSpot]) {
        guard !spots.isEmpty else { return }
        let now = Date()
        let cutoff = now.addingTimeInterval(-900) // 15 minutes

        for spot in spots {
            let band = spot.band.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !band.isEmpty else { continue }
            var list = clusterSpotsHistory[band] ?? []
            list.append(now)
            clusterSpotsHistory[band] = list.filter { $0 > cutoff }
        }

        evaluateBandsNow()
    }

    // MARK: - Health & Evaluation Logic

    private func startEvaluationTimer() {
        timer = Timer.publish(every: 10.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.evaluateBandsNow()
            }
    }

    public func evaluateBandsNow() {
        let allBands = Array(Set(Array(Self.digitalFrequenciesHz.keys) + Array(decodesHistory.keys)))
        for b in allBands {
            evaluateBand(b)
        }

        checkAndGenerateRecommendation()
    }

    private func evaluateBand(_ band: String) {
        let now = Date()
        let twoMinutesAgo = now.addingTimeInterval(-120)

        let decodes = decodesHistory[band] ?? []
        let recentDecodes = decodes.filter { $0.0 > twoMinutesAgo }

        let decodesPerMin: Double = Double(recentDecodes.count) / 2.0
        let avgSNR: Double = recentDecodes.isEmpty ? -20.0 : (recentDecodes.map(\.1).reduce(0, +) / Double(recentDecodes.count))

        let spots = clusterSpotsHistory[band] ?? []
        let recentSpots = spots.filter { $0 > now.addingTimeInterval(-600) }

        // Calculate Health Score (0 - 100)
        // Factors: Decode throughput (up to 40 pts), SNR quality (up to 30 pts), Cluster activity (up to 30 pts)
        var health = 0
        if decodesPerMin >= 20 { health += 40 }
        else if decodesPerMin >= 10 { health += 30 }
        else if decodesPerMin >= 4 { health += 18 }
        else if decodesPerMin > 0 { health += 8 }

        if !recentDecodes.isEmpty {
            if avgSNR >= -5 { health += 30 }
            else if avgSNR >= -12 { health += 22 }
            else if avgSNR >= -18 { health += 14 }
            else if avgSNR > -24 { health += 6 }
        }

        if recentSpots.count >= 20 { health += 30 }
        else if recentSpots.count >= 8 { health += 20 }
        else if recentSpots.count >= 2 { health += 10 }

        if recentDecodes.isEmpty && recentSpots.isEmpty {
            health = 0
        } else {
            health = max(5, min(100, health))
        }

        // Determine trend vs previous rate
        let prevRate = previousSlotRates[band] ?? decodesPerMin
        let trend: BandHealthTrend
        if recentDecodes.isEmpty && recentSpots.isEmpty {
            trend = .steady
        } else if decodesPerMin > prevRate * 1.25 && decodesPerMin >= 3 {
            trend = .rising
        } else if decodesPerMin < prevRate * 0.65 || (decodesPerMin == 0 && prevRate > 0) {
            trend = decodesPerMin == 0 ? .dead : .declining
        } else {
            trend = .steady
        }
        previousSlotRates[band] = decodesPerMin

        let snapshot = BandActivitySnapshot(
            band: band,
            decodeCountLastSlot: recentDecodes.count,
            decodesPerMinute: decodesPerMin,
            averageSNR: avgSNR,
            clusterSpotCount: recentSpots.count,
            healthPercentage: health,
            trend: trend,
            lastUpdated: now
        )
        bandSnapshots[band] = snapshot

        if band == activeBand {
            currentBandHealth = health
            currentBandTrend = trend
            currentBandDecodesPerMin = decodesPerMin
            currentBandAvgSNR = avgSNR
        }
    }

    private func checkAndGenerateRecommendation() {
        let currentBand = activeBand
        guard let currentSnap = bandSnapshots[currentBand] else { return }

        // Band is considered degraded if health < 45 or trend is dead / declining with low decodes
        let isDegraded = currentSnap.healthPercentage < 45 || currentSnap.trend == .dead || (currentSnap.trend == .declining && currentSnap.decodesPerMinute < 3.0)

        // Find best candidate band
        let otherBands = bandSnapshots.values.filter { $0.band != currentBand }
        guard let bestCandidate = otherBands.max(by: { $0.healthPercentage < $1.healthPercentage }) else { return }

        if isDegraded && bestCandidate.healthPercentage >= 60 {
            guard let targetFreq = Self.digitalFrequenciesHz[bestCandidate.band] else { return }

            let reason: String
            if currentSnap.trend == .dead || currentSnap.decodesPerMinute == 0 {
                reason = "\(currentBand) is silent (0 decodes/min). \(bestCandidate.band) is buzzing with high activity (\(Int(bestCandidate.decodesPerMinute)) dec/min, \(bestCandidate.clusterSpotCount) spots)."
            } else {
                reason = "\(currentBand) activity has degraded (\(String(format: "%.1f", currentSnap.decodesPerMinute)) dec/min, avg \(Int(currentSnap.averageSNR)) dB). \(bestCandidate.band) has better propagation (\(bestCandidate.healthPercentage)% health)."
            }

            // Only set if different or expired
            if activeRecommendation?.targetBand != bestCandidate.band {
                let rec = BandSwitchRecommendation(
                    fromBand: currentBand,
                    targetBand: bestCandidate.band,
                    targetFrequencyHz: targetFreq,
                    reason: reason,
                    scoreDiff: Double(bestCandidate.healthPercentage - currentSnap.healthPercentage)
                )
                activeRecommendation = rec
                recommendationHistory.insert(rec, at: 0)
                if recommendationHistory.count > 20 { recommendationHistory.removeLast() }
            }
        } else if currentSnap.healthPercentage >= 70 {
            // Current band recovered
            if activeRecommendation != nil {
                activeRecommendation = nil
            }
        }
    }

    // MARK: - 1-Click QSY Execution to SDR-Control (Hamlib Port 5001)

    func executeQSY(
        to recommendation: BandSwitchRecommendation,
        rigClient: RigControlClient?
    ) {
        let targetHz = recommendation.targetFrequencyHz
        let targetBand = recommendation.targetBand

        // 1. Send frequency command to SDR-Control's Hamlib CAT server (TCP port 5001)
        rigClient?.setFrequencyHz(targetHz)
        rigClient?.setMode("USB", passbandHz: 3000)

        // 2. Update active band locally
        setActiveBand(targetBand)
        activeRecommendation = nil
    }

    public func dismissActiveRecommendation() {
        activeRecommendation = nil
    }
}
