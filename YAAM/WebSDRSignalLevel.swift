import Foundation

/// Audio-domain spectral amplitude in dBFS. This is not a calibrated RF SNR.
enum WebSDRSignalLevel {
    nonisolated static func estimate(samples: [Float], sampleRate: Int, onsetSeconds: Double,
                         frequencyHz: Float) -> Double? {
        guard sampleRate > 0, frequencyHz > 0, !samples.isEmpty else { return nil }
        let length = max(256, Int(Double(sampleRate) * 0.16))
        var snapshots: [Double] = []
        for delay in [1.0, 4.0, 8.0, 11.0] {
            let start = Int((onsetSeconds + delay) * Double(sampleRate))
            guard start >= 0, start + length <= samples.count else { continue }
            var best = 0.0
            for tone in -8...16 {
                let frequency = Double(frequencyHz) + Double(tone) * 6.25
                guard frequency > 0, frequency < Double(sampleRate) / 2 else { continue }
                let coefficient = 2 * cos(2 * .pi * frequency / Double(sampleRate))
                var q1 = 0.0
                var q2 = 0.0
                for index in 0..<length {
                    let window = 0.5 - 0.5 * cos(2 * .pi * Double(index) / Double(length - 1))
                    let q0 = Double(samples[start + index]) * window + coefficient * q1 - q2
                    q2 = q1
                    q1 = q0
                }
                let magnitude = sqrt(max(0, q1 * q1 + q2 * q2 - coefficient * q1 * q2))
                best = max(best, magnitude * 4 / Double(length))
            }
            if best > 0 { snapshots.append(20 * log10(best)) }
        }
        guard !snapshots.isEmpty else { return nil }
        snapshots.sort()
        return max(-120, min(0, snapshots[snapshots.count / 2]))
    }
}
