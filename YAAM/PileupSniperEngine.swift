//
//  PileupSniperEngine.swift
//  YAAM
//
//  Intelligent Pileup Sniper & Split QSX Frequency Hunter.
//  Parses live cluster comments (UP, DN, QSX, WKD), models time-decayed
//  pileup distribution, detects operator stepping patterns, and calculates
//  the high-probability transmit sweet spot for VFO-B.
//

import Combine
import Foundation
import SwiftUI

// MARK: - Models

public struct PileupHitPoint: Identifiable, Equatable, Sendable {
    public let id: String
    public let frequencyKHz: Double
    public let offsetKHz: Double
    public let timestamp: Date
    public let spotter: String
    public let comment: String
    public let weight: Double

    public init(
        frequencyKHz: Double,
        offsetKHz: Double,
        timestamp: Date,
        spotter: String,
        comment: String,
        weight: Double = 1.0
    ) {
        self.id = "\(frequencyKHz)_\(timestamp.timeIntervalSince1970)_\(spotter)"
        self.frequencyKHz = frequencyKHz
        self.offsetKHz = offsetKHz
        self.timestamp = timestamp
        self.spotter = spotter
        self.comment = comment
        self.weight = weight
    }
}

public enum PileupPattern: String, CaseIterable, Sendable {
    case steppingUp = "Stepping UP"
    case steppingDown = "Stepping DOWN"
    case clusteringCenter = "Sweet Spot Cluster"
    case wideSpread = "Wide Spread Hunting"
    case singleTarget = "Fixed QSX Target"
    case simplex = "Simplex (Zero Split)"

    public var iconName: String {
        switch self {
        case .steppingUp: return "arrow.up.right.circle.fill"
        case .steppingDown: return "arrow.down.right.circle.fill"
        case .clusteringCenter: return "scope"
        case .wideSpread: return "waveform.path"
        case .singleTarget: return "target"
        case .simplex: return "dot.circle"
        }
    }

    public var badgeColor: Color {
        switch self {
        case .steppingUp: return .green
        case .steppingDown: return .cyan
        case .clusteringCenter: return .orange
        case .wideSpread: return .purple
        case .singleTarget: return .mint
        case .simplex: return .secondary
        }
    }
}

public struct PileupSniperSolution: Identifiable, Equatable, Sendable {
    public var id: String { "\(dxCallsign)_\(String(format: "%.1f", dxRxFrequencyKHz))" }
    public let dxCallsign: String
    public let dxRxFrequencyKHz: Double
    public let isSplit: Bool
    public let splitRangeKHz: ClosedRange<Double>?
    public let splitSpreadOffsetKHz: ClosedRange<Double>?
    public let recommendedTxKHz: Double
    public let recommendedOffsetKHz: Double
    public let confidence: Double
    public let pattern: PileupPattern
    public let recentHits: [PileupHitPoint]
    public let tacticalAdvice: String
    public let summaryTag: String

    public var offsetSignFormatted: String {
        if recommendedOffsetKHz >= 0 {
            return String(format: "+%.1f kHz", recommendedOffsetKHz)
        } else {
            return String(format: "%.1f kHz", recommendedOffsetKHz)
        }
    }

    public var frequencyFormattedMHz: String {
        String(format: "%.3f MHz", recommendedTxKHz / 1000.0)
    }
}

// MARK: - Comment Parser

public enum QSXCommentParser {
    public struct ParsedComment: Equatable, Sendable {
        public let isSplit: Bool
        public let lowOffsetKHz: Double?
        public let highOffsetKHz: Double?
        public let exactFrequencyKHz: Double?
        public let isRange: Bool
        public let isSimplex: Bool
    }

    public static func parse(comment rawComment: String, dxBaseFreqKHz: Double) -> ParsedComment {
        let clean = rawComment.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            return ParsedComment(isSplit: false, lowOffsetKHz: nil, highOffsetKHz: nil, exactFrequencyKHz: nil, isRange: false, isSimplex: false)
        }

        // Simplex reset check
        if clean.contains("SIMPLEX") || clean.contains("NO SPLIT") {
            return ParsedComment(isSplit: false, lowOffsetKHz: nil, highOffsetKHz: nil, exactFrequencyKHz: nil, isRange: false, isSimplex: true)
        }

        // 1. WKD / WORKED frequency (e.g., "WKD 14024.5", "WKD +3.5", "WKD AT 14.025.2", "WKD 24.5")
        if let wkdMatch = matchPattern(clean, pattern: #"(?:WKD|WORKED)\s*(?:AT\s*)?([+0-9\.]+)"#) {
            if let freq = normalizeToFrequencyKHz(wkdMatch, baseFreqKHz: dxBaseFreqKHz) {
                let offset = freq - dxBaseFreqKHz
                return ParsedComment(isSplit: true, lowOffsetKHz: offset, highOffsetKHz: offset, exactFrequencyKHz: freq, isRange: false, isSimplex: false)
            }
        }

        // 2. QSX or LISTENING absolute frequency (e.g., "QSX 14025.4", "QSX 14.025", "LSTN 7005.2")
        if let qsxMatch = matchPattern(clean, pattern: #"(?:QSX|LSTN|LISTENING|LSTNG)\s*([0-9\.]+)"#) {
            if let freq = normalizeToFrequencyKHz(qsxMatch, baseFreqKHz: dxBaseFreqKHz) {
                let offset = freq - dxBaseFreqKHz
                return ParsedComment(isSplit: true, lowOffsetKHz: offset, highOffsetKHz: offset, exactFrequencyKHz: freq, isRange: false, isSimplex: false)
            }
        }

        // 3. UP Range (e.g., "UP 5-10", "UP 5 TO 10", "UP 2/5", "UP 1.5 - 3.5")
        if let rangeMatch = matchTwoNumbers(clean, pattern: #"UP\s*([0-9]+(?:\.[0-9]+)?)\s*(?:-|TO|\/)\s*([0-9]+(?:\.[0-9]+)?)"#) {
            let low = min(rangeMatch.0, rangeMatch.1)
            let high = max(rangeMatch.0, rangeMatch.1)
            return ParsedComment(isSplit: true, lowOffsetKHz: low, highOffsetKHz: high, exactFrequencyKHz: nil, isRange: true, isSimplex: false)
        }

        // 4. DOWN Range (e.g., "DN 1-2", "DOWN 2-5")
        if let rangeMatch = matchTwoNumbers(clean, pattern: #"(?:DN|DOWN)\s*([0-9]+(?:\.[0-9]+)?)\s*(?:-|TO|\/)\s*([0-9]+(?:\.[0-9]+)?)"#) {
            let low = -max(rangeMatch.0, rangeMatch.1)
            let high = -min(rangeMatch.0, rangeMatch.1)
            return ParsedComment(isSplit: true, lowOffsetKHz: low, highOffsetKHz: high, exactFrequencyKHz: nil, isRange: true, isSimplex: false)
        }

        // 5. UP Single Offset (e.g., "UP 5", "UP 1.5", "UP 2K", "UP 5KHZ")
        if let upMatch = matchPattern(clean, pattern: #"UP\s*([0-9]+(?:\.[0-9]+)?)\s*(?:K|KHZ)?"#) {
            if let val = Double(upMatch) {
                let high = max(1.0, val)
                let low = max(0.5, high - 2.0)
                return ParsedComment(isSplit: true, lowOffsetKHz: low, highOffsetKHz: high, exactFrequencyKHz: dxBaseFreqKHz + val, isRange: false, isSimplex: false)
            }
        }

        // 6. DOWN Single Offset (e.g., "DN 2", "DOWN 3")
        if let dnMatch = matchPattern(clean, pattern: #"(?:DN|DOWN)\s*([0-9]+(?:\.[0-9]+)?)"#) {
            if let val = Double(dnMatch) {
                let low = -max(1.0, val)
                let high = min(-0.5, low + 2.0)
                return ParsedComment(isSplit: true, lowOffsetKHz: low, highOffsetKHz: high, exactFrequencyKHz: dxBaseFreqKHz - val, isRange: false, isSimplex: false)
            }
        }

        // 7. Generic UP or SPLIT
        if clean.contains("SPLIT") || clean == "UP" || clean.contains(" UP ") {
            return ParsedComment(isSplit: true, lowOffsetKHz: 1.0, highOffsetKHz: 5.0, exactFrequencyKHz: nil, isRange: true, isSimplex: false)
        }

        return ParsedComment(isSplit: false, lowOffsetKHz: nil, highOffsetKHz: nil, exactFrequencyKHz: nil, isRange: false, isSimplex: false)
    }

    private static func matchPattern(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) else { return nil }
        guard match.numberOfRanges >= 2 else { return nil }
        return nsText.substring(with: match.range(at: 1))
    }

    private static func matchTwoNumbers(_ text: String, pattern: String) -> (Double, Double)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)) else { return nil }
        guard match.numberOfRanges >= 3 else { return nil }
        let s1 = nsText.substring(with: match.range(at: 1))
        let s2 = nsText.substring(with: match.range(at: 2))
        guard let n1 = Double(s1), let n2 = Double(s2) else { return nil }
        return (n1, n2)
    }

    public static func normalizeToFrequencyKHz(_ rawStr: String, baseFreqKHz: Double) -> Double? {
        var clean = rawStr.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle explicit plus sign e.g. "+3.5" -> base + 3.5
        if clean.hasPrefix("+") {
            clean.removeFirst()
            if let offset = Double(clean) {
                return baseFreqKHz + offset
            }
        }

        // Handle multiple dots (e.g. "14.025.5" -> "14025.5")
        let dotCount = clean.filter { $0 == "." }.count
        if dotCount > 1 {
            let parts = clean.components(separatedBy: ".")
            if parts.count >= 2 {
                let mhz = parts[0]
                let rest = parts.dropFirst().joined()
                let reconstructed = "\(mhz).\(rest)"
                if let val = Double(reconstructed) {
                    return val * 1000.0
                }
            }
        }

        guard let val = Double(clean), val > 0 else { return nil }

        // MHz notation: e.g. 14.025 or 7.005 -> convert to kHz
        if val > 1.0 && val < 60.0 {
            return val * 1000.0
        }

        // Direct kHz notation: e.g. 14025.5 or 7005.0
        if val >= 1000.0 && val <= 60000.0 {
            return val
        }

        // Relative offset < 50 kHz (e.g., 5.2 -> base + 5.2)
        if val < 50.0 {
            return baseFreqKHz + val
        }

        // Shorthand tail notation: e.g. base is 14020, user typed "24.5" meaning 14024.5
        if val >= 20.0 && val < 1000.0 {
            let baseFloor100 = floor(baseFreqKHz / 100.0) * 100.0
            return baseFloor100 + val
        }

        return nil
    }
}

// MARK: - Engine Class

public final class PileupSniperEngine: ObservableObject {
    public static let shared = PileupSniperEngine()

    private init() {}

    /// Analyzes live cluster spots and archived spots to calculate the optimal sniper solution
    static func analyze(
        dxCallsign: String,
        dxRxFrequencyKHz: Double,
        clusterSpots: [DXSpot] = [],
        archivedSpots: [ArchivedSpotRecord] = []
    ) -> PileupSniperSolution? {
        let cleanDX = dxCallsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !cleanDX.isEmpty, dxRxFrequencyKHz > 0 else { return nil }

        let now = Date()
        var hitPoints: [PileupHitPoint] = []
        var detectedLowOffsets: [Double] = []
        var detectedHighOffsets: [Double] = []
        var isSplitConfirmed = false

        var hasExplicitCeiling = false
        var hasExplicitFloor = false

        // 1. Process Live Cluster Spots
        for spot in clusterSpots {
            let spotCall = spot.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard spotCall == cleanDX || spotCall.contains(cleanDX) || cleanDX.contains(spotCall) else { continue }

            let parsed = QSXCommentParser.parse(comment: spot.comment, dxBaseFreqKHz: dxRxFrequencyKHz)
            if parsed.isSimplex {
                // If the latest spot explicitly reports SIMPLEX, honor it
                if abs(now.timeIntervalSince(spot.spottedAt)) < 300 {
                    return PileupSniperSolution(
                        dxCallsign: cleanDX,
                        dxRxFrequencyKHz: dxRxFrequencyKHz,
                        isSplit: false,
                        splitRangeKHz: nil,
                        splitSpreadOffsetKHz: nil,
                        recommendedTxKHz: dxRxFrequencyKHz,
                        recommendedOffsetKHz: 0.0,
                        confidence: 0.95,
                        pattern: .simplex,
                        recentHits: [],
                        tacticalAdvice: "Station explicitly reported SIMPLEX by \(spot.spotter). Transmit on RX frequency.",
                        summaryTag: "SIMPLEX"
                    )
                }
            } else if parsed.isSplit {
                isSplitConfirmed = true
                if parsed.isRange {
                    if let l = parsed.lowOffsetKHz {
                        detectedLowOffsets.append(l)
                        hasExplicitFloor = true
                    }
                    if let h = parsed.highOffsetKHz {
                        detectedHighOffsets.append(h)
                        hasExplicitCeiling = true
                    }
                } else {
                    if let l = parsed.lowOffsetKHz { detectedLowOffsets.append(l) }
                    if let h = parsed.highOffsetKHz { detectedHighOffsets.append(h) }
                }

                let ageSec = max(0.0, now.timeIntervalSince(spot.spottedAt))
                let decayWeight = max(0.1, exp(-ageSec / 1200.0)) // 20-min half-life

                if let exact = parsed.exactFrequencyKHz {
                    hitPoints.append(PileupHitPoint(
                        frequencyKHz: exact,
                        offsetKHz: exact - dxRxFrequencyKHz,
                        timestamp: spot.spottedAt,
                        spotter: spot.spotter,
                        comment: spot.comment,
                        weight: decayWeight
                    ))
                }
            }
        }

        // 2. Process Archived Historical Spots
        for arch in archivedSpots {
            let archCall = arch.callsign.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard archCall == cleanDX || archCall.contains(cleanDX) || cleanDX.contains(archCall) else { continue }

            let parsed = QSXCommentParser.parse(comment: arch.comment, dxBaseFreqKHz: dxRxFrequencyKHz)
            if parsed.isSplit {
                isSplitConfirmed = true
                if parsed.isRange {
                    if let l = parsed.lowOffsetKHz {
                        detectedLowOffsets.append(l)
                        hasExplicitFloor = true
                    }
                    if let h = parsed.highOffsetKHz {
                        detectedHighOffsets.append(h)
                        hasExplicitCeiling = true
                    }
                } else {
                    if let l = parsed.lowOffsetKHz { detectedLowOffsets.append(l) }
                    if let h = parsed.highOffsetKHz { detectedHighOffsets.append(h) }
                }

                let ageSec = max(0.0, now.timeIntervalSince(arch.spottedAt))
                let decayWeight = max(0.05, exp(-ageSec / 1800.0))

                if let exact = parsed.exactFrequencyKHz {
                    // Prevent exact duplicates
                    if !hitPoints.contains(where: { abs($0.frequencyKHz - exact) < 0.1 && abs($0.timestamp.timeIntervalSince(arch.spottedAt)) < 60 }) {
                        hitPoints.append(PileupHitPoint(
                            frequencyKHz: exact,
                            offsetKHz: exact - dxRxFrequencyKHz,
                            timestamp: arch.spottedAt,
                            spotter: arch.spotter,
                            comment: arch.comment,
                            weight: decayWeight
                        ))
                    }
                }
            }
        }

        guard isSplitConfirmed else { return nil }

        // Sort hit points chronologically ascending
        hitPoints.sort { $0.timestamp < $1.timestamp }

        // Compute Split Window Boundaries
        var minOffset = detectedLowOffsets.min() ?? 1.0
        var maxOffset = detectedHighOffsets.max() ?? 5.0

        // If hit points exist outside the verbal comment spread, expand the window
        if let minHit = hitPoints.map(\.offsetKHz).min() { minOffset = min(minOffset, minHit) }
        if let maxHit = hitPoints.map(\.offsetKHz).max() { maxOffset = max(maxOffset, maxHit) }

        if minOffset > maxOffset {
            swap(&minOffset, &maxOffset)
        }
        if abs(minOffset - maxOffset) < 0.5 {
            maxOffset = minOffset + 2.0
        }

        // Pattern Analysis & Sniper Target Prediction
        let pattern: PileupPattern
        let recommendedTxKHz: Double
        let recommendedOffsetKHz: Double
        let tacticalAdvice: String
        let confidence: Double

        if hitPoints.count >= 3 {
            // Analyze sequential progression
            var deltas: [Double] = []
            for i in 1..<hitPoints.count {
                deltas.append(hitPoints[i].offsetKHz - hitPoints[i - 1].offsetKHz)
            }
            let avgDelta = deltas.reduce(0.0, +) / Double(deltas.count)
            let lastHit = hitPoints.last!

            // Check if Stepping Upwards
            if avgDelta > 0.3 && deltas.filter({ $0 > 0 }).count >= deltas.count / 2 {
                pattern = .steppingUp
                let stepSize = max(0.5, min(2.0, avgDelta))
                var nextOffset = lastHit.offsetKHz + stepSize
                if nextOffset > maxOffset {
                    if hasExplicitCeiling {
                        // Explicit ceiling reached (e.g. UP 5-10): wrap around to low end of spread
                        nextOffset = minOffset + stepSize * 0.5
                    } else {
                        // Open-ended split: expand boundary upwards
                        maxOffset = nextOffset + 0.5
                    }
                }
                recommendedOffsetKHz = nextOffset
                recommendedTxKHz = dxRxFrequencyKHz + recommendedOffsetKHz
                confidence = min(0.95, 0.70 + Double(hitPoints.count) * 0.05)
                tacticalAdvice = "DX stepping UP (+\(String(format: "%.1f", stepSize)) kHz/step). Last worked \(String(format: "%.1f", lastHit.frequencyKHz)) kHz. Target \(String(format: "%.1f", recommendedTxKHz)) kHz for next CQ."
            }
            // Check if Stepping Downwards
            else if avgDelta < -0.3 && deltas.filter({ $0 < 0 }).count >= deltas.count / 2 {
                pattern = .steppingDown
                let stepSize = max(0.5, min(2.0, abs(avgDelta)))
                var nextOffset = lastHit.offsetKHz - stepSize
                if nextOffset < minOffset {
                    if hasExplicitFloor {
                        // Explicit floor reached: wrap around to top end of spread
                        nextOffset = maxOffset - stepSize * 0.5
                    } else {
                        // Open-ended split: expand boundary downwards
                        minOffset = nextOffset - 0.5
                    }
                }
                recommendedOffsetKHz = nextOffset
                recommendedTxKHz = dxRxFrequencyKHz + recommendedOffsetKHz
                confidence = min(0.95, 0.70 + Double(hitPoints.count) * 0.05)
                tacticalAdvice = "DX stepping DOWN (-\(String(format: "%.1f", stepSize)) kHz/step). Last worked \(String(format: "%.1f", lastHit.frequencyKHz)) kHz. Target \(String(format: "%.1f", recommendedTxKHz)) kHz."
            }
            // Check Clustering Sweet Spot
            else {
                // Weighted average frequency
                let totalWeight = hitPoints.reduce(0.0) { $0 + $1.weight }
                let weightedOffset = hitPoints.reduce(0.0) { $0 + ($1.offsetKHz * $1.weight) } / (totalWeight > 0 ? totalWeight : 1.0)
                pattern = .clusteringCenter
                // Offset +150 Hz to punch through heavy zero-beat QRM
                recommendedOffsetKHz = weightedOffset + 0.15
                recommendedTxKHz = dxRxFrequencyKHz + recommendedOffsetKHz
                confidence = min(0.90, 0.65 + Double(hitPoints.count) * 0.04)
                tacticalAdvice = "Dense cluster near \(String(format: "%.1f", dxRxFrequencyKHz + weightedOffset)) kHz. Positioned +150 Hz above peak to beat pileup QRM."
            }
        } else if let singleHit = hitPoints.last {
            // Single Hit or Fixed QSX
            pattern = .singleTarget
            recommendedTxKHz = singleHit.frequencyKHz
            recommendedOffsetKHz = singleHit.offsetKHz
            confidence = 0.80
            tacticalAdvice = "Direct QSX verified at \(String(format: "%.1f", singleHit.frequencyKHz)) kHz (\(singleHit.offsetKHz >= 0 ? "+" : "")\(String(format: "%.1f", singleHit.offsetKHz)) kHz)."
        } else {
            // Wide spread with verbal comments only (e.g. UP 5-10)
            pattern = .wideSpread
            let span = maxOffset - minOffset
            // Target upper-third of the spread (fewer callers, cleaner copy)
            recommendedOffsetKHz = minOffset + (span * 0.65)
            recommendedTxKHz = dxRxFrequencyKHz + recommendedOffsetKHz
            confidence = 0.75
            tacticalAdvice = "Spread \(minOffset >= 0 ? "+" : "")\(String(format: "%.0f", minOffset)) to \(maxOffset >= 0 ? "+" : "")\(String(format: "%.0f", maxOffset)) kHz reported. Aiming in upper-tier sweet spot at \(String(format: "%.1f", recommendedTxKHz)) kHz."
        }

        let finalMin = min(minOffset, recommendedOffsetKHz)
        let finalMax = max(maxOffset, recommendedOffsetKHz)
        let spreadOffsetRange = finalMin ... finalMax
        let splitRangeKHz = (dxRxFrequencyKHz + finalMin) ... (dxRxFrequencyKHz + finalMax)

        let summaryTag = "UP \(String(format: "%.0f", finalMin))–\(String(format: "%.0f", finalMax)) kHz · Sweet spot \(recommendedOffsetKHz >= 0 ? "+" : "")\(String(format: "%.1f", recommendedOffsetKHz))k"

        return PileupSniperSolution(
            dxCallsign: cleanDX,
            dxRxFrequencyKHz: dxRxFrequencyKHz,
            isSplit: true,
            splitRangeKHz: splitRangeKHz,
            splitSpreadOffsetKHz: spreadOffsetRange,
            recommendedTxKHz: recommendedTxKHz,
            recommendedOffsetKHz: recommendedOffsetKHz,
            confidence: confidence,
            pattern: pattern,
            recentHits: hitPoints,
            tacticalAdvice: tacticalAdvice,
            summaryTag: summaryTag
        )
    }
}
