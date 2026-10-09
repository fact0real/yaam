import Foundation
import FT8Codec

@main
struct FT8ExpandedDecodeRegression {
    static func main() throws {
        var seed: UInt64 = 42
        func noise() -> Float {
            seed = seed &* 6364136223846793005 &+ 1
            return Float(Double(seed >> 11) / Double(UInt64(1) << 53) * 2 - 1)
        }
        let signal = try FT8Codec.transmitAudio("CQ EP2AES LM55", baseFrequencyHz: 1500, sampleRate: 12_000)
        var standardTotal = 0
        var expandedTotal = 0
        let started = Date()
        for amplitude: Float in [0.006, 0.01, 0.016, 0.025, 0.05, 0.1] {
            let audio = signal.map { $0 * amplitude + noise() * 0.2 }
            let standard = try FT8StationDecoder.decode(samples: audio, sampleRate: 12_000, protocol: .ft8, expanded: false)
            let expanded = try FT8StationDecoder.decode(samples: audio, sampleRate: 12_000, protocol: .ft8, expanded: true)
            let original = Set(standard.map { $0.message.text })
            let enhanced = Set(expanded.map { $0.message.text })
            precondition(original.isSubset(of: enhanced), "Expanded mode lost a standard decode")
            precondition(enhanced.isSubset(of: ["CQ EP2AES LM55"]), "Unexpected message from reference waveform")
            precondition(expanded.count == enhanced.count, "Repeated passes created duplicate messages")
            standardTotal += standard.count
            expandedTotal += expanded.count
        }
        let noiseOnly = (0..<180_000).map { _ in noise() * 0.2 }
        let noiseMessages = try FT8StationDecoder.decode(samples: noiseOnly, sampleRate: 12_000, protocol: .ft8, expanded: true)
        precondition(noiseMessages.isEmpty)
        precondition(standardTotal > 0)
        print("Six noisy reference trials: standard \(standardTotal), expanded \(expandedTotal); noise-only: 0; total \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
    }
}
